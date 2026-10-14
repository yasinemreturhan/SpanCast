import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../protocol/models.dart';
import '../protocol/proof.dart';
import 'rate_limiter.dart';
import 'room_manager.dart';

class _SenderClient {
  final Sender sender;
  final WebSocket socket;
  final String ip;

  _SenderClient({
    required this.sender,
    required this.socket,
    required this.ip,
  });

  void send(SignalMessage msg) {
    try {
      socket.add(msg.encode());
    } catch (_) {}
  }

  void close() {
    try {
      socket.close();
    } catch (_) {}
  }
}

class _ReceiverClient {
  final Room room;
  final WebSocket socket;
  final Map<String, _SenderClient> senders = {};

  _ReceiverClient({required this.room, required this.socket});

  void send(SignalMessage msg) {
    try {
      socket.add(msg.encode());
    } catch (_) {}
  }

  void close() {
    try {
      socket.close();
    } catch (_) {}
  }
}

/// Embedded Dart Signaling Server running on each receiver device.
/// Enables completely serverless P2P screen sharing across LAN.
class SignalingServer {
  final String name;
  final int requestedPort;
  final RoomManager _roomManager;
  final RateLimiter _limiter;

  HttpServer? _server;
  final Map<Room, _ReceiverClient> _receivers = {};
  Timer? _sweepTimer;

  static const int maxMessageLength = 65536; // 64 KB
  static const Set<String> _senderAllowedTypes = {'offer', 'answer', 'ice'};
  static const Set<String> _receiverAllowedTypes = {'offer', 'answer', 'ice', 'regen'};

  SignalingServer({
    required this.name,
    this.requestedPort = 8788,
    RoomManager? roomManager,
    RateLimiter? limiter,
  })  : _roomManager = roomManager ?? RoomManager(),
        _limiter = limiter ?? RateLimiter();

  int get port => _server?.port ?? requestedPort;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;

    _server = await HttpServer.bind(InternetAddress.anyIPv4, requestedPort);
    _sweepTimer = Timer.periodic(const Duration(minutes: 5), (_) => _limiter.sweep());

    _server!.listen(_handleHttpRequest);
  }

  Future<void> stop() async {
    _sweepTimer?.cancel();
    _sweepTimer = null;

    for (final rc in _receivers.values) {
      for (final sc in rc.senders.values) {
        sc.send(const SignalMessage(type: 'error', reason: 'receiver-gone'));
        sc.close();
      }
      rc.close();
      _roomManager.close(rc.room);
    }
    _receivers.clear();

    await _server?.close(force: true);
    _server = null;
  }

  void _handleHttpRequest(HttpRequest request) {
    // Enable CORS for web/LAN clients
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/healthz') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('ok');
      request.response.close();
      return;
    }

    if (path == '/api/info') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'name': name,
          'version': '0.1.0',
          'caps': ['mirror', 'multi'],
        }));
      request.response.close();
      return;
    }

    if (path == '/' || path == '/view') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_webReceiverHtml);
      request.response.close();
      return;
    }

    if (path == '/ws') {
      _upgradeWebSocket(request);
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not found');
    request.response.close();
  }

  Future<void> _upgradeWebSocket(HttpRequest request) async {
    final role = request.uri.queryParameters['role'];
    if (role != 'receiver' && role != 'sender') {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('role must be receiver or sender');
      request.response.close();
      return;
    }

    final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      if (role == 'receiver') {
        _handleReceiver(socket);
      } else {
        final clientName = request.uri.queryParameters['name'] ?? 'Device';
        _handleSender(socket, ip, clientName);
      }
    } catch (_) {}
  }

  void _handleReceiver(WebSocket socket) {
    final room = _roomManager.createRoom();
    final rc = _ReceiverClient(room: room, socket: socket);
    _receivers[room] = rc;

    // Send initial PIN to receiver
    rc.send(SignalMessage(type: 'pin', pin: room.pin, roomId: room.id));

    socket.listen(
      (data) {
        if (data is! String || data.length > maxMessageLength) return;
        final msg = SignalMessage.tryParse(data);
        if (msg == null) return;

        if (!_receiverAllowedTypes.contains(msg.type)) return;

        if (msg.type == 'regen') {
          final newPin = _roomManager.regenerate(room);
          rc.send(SignalMessage(type: 'pin', pin: newPin, roomId: room.id));
          return;
        }

        // Forward to designated sender
        final targetId = msg.to;
        if (targetId != null) {
          final targetSender = rc.senders[targetId];
          if (targetSender != null) {
            targetSender.send(SignalMessage(
              type: msg.type,
              from: 'receiver',
              payload: msg.payload,
            ));
          }
        }
      },
      onDone: () => _receiverDisconnected(rc),
      onError: (_) => _receiverDisconnected(rc),
      cancelOnError: true,
    );
  }

  void _receiverDisconnected(_ReceiverClient rc) {
    _receivers.remove(rc.room);
    _roomManager.close(rc.room);

    for (final sc in rc.senders.values) {
      sc.send(const SignalMessage(type: 'error', reason: 'receiver-gone'));
      sc.close();
    }
    rc.senders.clear();
  }

  Future<void> _handleSender(WebSocket socket, String ip, String clientName) async {
    if (!_limiter.isAllowed(ip)) {
      socket.add(const SignalMessage(type: 'error', reason: 'rate-limited').encode());
      await socket.close();
      return;
    }

    final salt = PinProof.generateSalt();
    socket.add(SignalMessage(type: 'challenge', payload: {'salt': salt}).encode());

    bool isAuthenticated = false;
    _ReceiverClient? activeRc;
    _SenderClient? activeSc;

    final authTimeout = Timer(const Duration(seconds: 30), () {
      if (!isAuthenticated) socket.close();
    });

    socket.listen(
      (data) {
        if (data is! String || data.length > maxMessageLength) {
          socket.close();
          return;
        }

        final msg = SignalMessage.tryParse(data);
        if (msg == null) return;

        if (!isAuthenticated) {
          authTimeout.cancel();
          _ReceiverClient? targetRc;
          String? issuedToken;

          if (msg.type == 'trust') {
            final token = msg.payload is Map ? msg.payload['token'] as String? : null;
            final room = token != null ? _roomManager.findByTrustToken(token) : null;
            targetRc = room != null ? _receivers[room] : null;

            if (targetRc == null) {
              socket.add(const SignalMessage(type: 'error', reason: 'bad-token').encode());
              socket.close();
              return;
            }
          } else if (msg.type == 'auth') {
            final proof = msg.payload is Map ? msg.payload['proof'] as String? : null;
            final room = proof != null ? _roomManager.findByProof(salt, proof) : null;
            targetRc = room != null ? _receivers[room] : null;

            if (targetRc == null) {
              _limiter.recordFailure(ip);
              socket.add(const SignalMessage(type: 'error', reason: 'bad-pin').encode());
              socket.close();
              return;
            }
            issuedToken = _roomManager.issueTrustToken(targetRc.room);
          } else {
            socket.close();
            return;
          }

          // Attach sender
          Sender sender;
          try {
            sender = targetRc.room.addSender(clientName);
          } catch (e) {
            final reason = e is RoomFullException ? 'room-full' : 'join-failed';
            socket.add(SignalMessage(type: 'error', reason: reason).encode());
            socket.close();
            return;
          }

          isAuthenticated = true;
          activeRc = targetRc;
          final sc = _SenderClient(sender: sender, socket: socket, ip: ip);
          activeSc = sc;
          targetRc.senders[sender.id] = sc;

          // Notify receiver
          targetRc.send(SignalMessage(type: 'joined', from: sender.id, name: clientName));

          // Confirm paired to sender
          sc.send(SignalMessage(
            type: 'paired',
            from: sender.id,
            payload: issuedToken != null ? {'token': issuedToken} : null,
          ));
          return;
        }

        // Post-authentication signaling messages:
        if (!_senderAllowedTypes.contains(msg.type)) return;

        if (activeRc != null && activeSc != null) {
          activeRc!.send(SignalMessage(
            type: msg.type,
            from: activeSc!.sender.id,
            payload: msg.payload,
          ));
        }
      },
      onDone: () {
        authTimeout.cancel();
        if (activeRc != null && activeSc != null) {
          _senderDisconnected(activeRc!, activeSc!);
        }
      },
      onError: (_) {
        authTimeout.cancel();
        if (activeRc != null && activeSc != null) {
          _senderDisconnected(activeRc!, activeSc!);
        }
      },
      cancelOnError: true,
    );
  }

  void _senderDisconnected(_ReceiverClient rc, _SenderClient sc) {
    rc.senders.remove(sc.sender.id);
    rc.room.removeSender(sc.sender.id);
    rc.send(SignalMessage(type: 'left', from: sc.sender.id));
    sc.close();
  }
}

const String _webReceiverHtml = r'''<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>DoScreen - Ultra Düşük Gecikmeli Ekran Paylaşımı</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0b0f19;
      color: #f1f5f9;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 24px 16px;
    }
    .container {
      width: 100%;
      max-width: 720px;
      display: flex;
      flex-direction: column;
      gap: 20px;
    }
    .header {
      text-align: center;
      padding: 20px 0 10px;
    }
    .badge {
      display: inline-block;
      padding: 4px 12px;
      background: rgba(99, 102, 241, 0.2);
      color: #818cf8;
      border: 1px solid rgba(99, 102, 241, 0.4);
      border-radius: 999px;
      font-size: 13px;
      font-weight: 600;
      margin-bottom: 12px;
    }
    h1 { font-size: 28px; font-weight: 800; color: #fff; letter-spacing: -0.5px; }
    p.subtitle { color: #94a3b8; font-size: 14px; margin-top: 6px; }
    .card {
      background: #151c2e;
      border: 1px solid #24304f;
      border-radius: 16px;
      padding: 24px;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.5);
    }
    .card h2 { font-size: 18px; margin-bottom: 12px; color: #e2e8f0; display: flex; align-items: center; gap: 8px; }
    .input-group {
      display: flex;
      gap: 12px;
      margin-top: 14px;
    }
    input[type="text"] {
      flex: 1;
      background: #0b0f19;
      border: 1px solid #334155;
      color: #fff;
      font-size: 20px;
      font-weight: 700;
      letter-spacing: 4px;
      text-align: center;
      padding: 12px;
      border-radius: 10px;
      outline: none;
    }
    input[type="text"]:focus {
      border-color: #6366f1;
      box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.25);
    }
    button.btn-primary {
      background: linear-gradient(135deg, #6366f1, #4f46e5);
      color: white;
      border: none;
      font-weight: 600;
      font-size: 15px;
      padding: 12px 24px;
      border-radius: 10px;
      cursor: pointer;
      transition: all 0.2s;
    }
    button.btn-primary:hover {
      background: linear-gradient(135deg, #4f46e5, #4338ca);
      transform: translateY(-1px);
    }
    button.btn-danger {
      background: #ef4444;
      color: white;
      border: none;
      font-weight: 600;
      font-size: 15px;
      padding: 12px 24px;
      border-radius: 10px;
      cursor: pointer;
    }
    .status-box {
      margin-top: 14px;
      padding: 12px;
      border-radius: 8px;
      background: #0b0f19;
      font-size: 13px;
      color: #94a3b8;
      display: none;
    }
    .downloads-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin-top: 12px;
    }
    .dl-btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 12px;
      background: #1e293b;
      color: #f8fafc;
      text-decoration: none;
      border-radius: 10px;
      border: 1px solid #334155;
      font-size: 14px;
      font-weight: 500;
      transition: all 0.2s;
    }
    .dl-btn:hover {
      background: #334155;
      border-color: #6366f1;
    }
    video {
      width: 100%;
      border-radius: 12px;
      background: #000;
      margin-top: 14px;
      display: none;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="badge">DoScreen v0.1.0 • Web Alıcı</div>
      <h1>DoScreen Alıcı Aktif</h1>
      <p class="subtitle">Bu cihaz şu anda yerel ağda ekran alıcısı olarak çalışıyor.</p>
    </div>

    <!-- Web Cast from Browser -->
    <div class="card">
      <h2>🖥️ Bu Tarayıcıdan Ekrana Paylaş</h2>
      <p style="color: #94a3b8; font-size: 14px;">Herhangi bir uygulama yüklemeden, bu bilgisayarın ekranını televizyona yansıtmak için ekrandaki 6 haneli PIN'i girin.</p>
      <div class="input-group">
        <input type="text" id="pinInput" maxlength="6" placeholder="123456" autocomplete="off" />
        <button class="btn-primary" id="startBtn" onclick="startCast()">Yansıtmayı Başlat</button>
        <button class="btn-danger" id="stopBtn" style="display:none;" onclick="stopCast()">Durdur</button>
      </div>
      <div id="statusBox" class="status-box"></div>
      <video id="previewVideo" autoplay playsinline muted></video>
    </div>

    <!-- Downloads -->
    <div class="card">
      <h2>📥 DoScreen Uygulamaları</h2>
      <p style="color: #94a3b8; font-size: 14px;">Tam performans, ses iletimi ve 60 FPS ultra düşük gecikme için DoScreen uygulamasını indirin:</p>
      <div class="downloads-grid">
        <a class="dl-btn" href="https://doscreen.yasinemreturhan.com/DoScreen.apk" target="_blank">📱 Android (APK)</a>
        <a class="dl-btn" href="https://doscreen.yasinemreturhan.com/DoScreen-Windows-x64.zip" target="_blank">🪟 Windows (x64)</a>
        <a class="dl-btn" href="https://doscreen.yasinemreturhan.com/DoScreen-macOS.zip" target="_blank">🍎 macOS (Apple Silicon/Intel)</a>
      </div>
      <div style="margin-top: 14px; text-align: center;">
        <a href="https://doscreen.yasinemreturhan.com" target="_blank" style="color: #818cf8; font-size: 13px; text-decoration: none;">Resmi İndirme Sayfası ve Rehber &rarr;</a>
      </div>
    </div>
  </div>

  <script>
    let ws = null;
    let pc = null;
    let localStream = null;

    function log(msg, isError = false) {
      const box = document.getElementById('statusBox');
      box.style.display = 'block';
      box.style.color = isError ? '#f87171' : '#38bdf8';
      box.innerText = msg;
    }

    async function computeHmac(pin, saltHex) {
      const enc = new TextEncoder();
      const key = await crypto.subtle.importKey(
        'raw',
        enc.encode(pin),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign']
      );
      const signature = await crypto.subtle.sign('HMAC', key, enc.encode(saltHex));
      return Array.from(new Uint8Array(signature)).map(b => b.toString(16).padStart(2, '0')).join('');
    }

    async function startCast() {
      const pin = document.getElementById('pinInput').value.trim();
      if (!pin || pin.length !== 6) {
        log('Lütfen 6 haneli geçerli PIN girin.', true);
        return;
      }

      log('Ekran izni isteniyor...');
      try {
        localStream = await navigator.mediaDevices.getDisplayMedia({
          video: { frameRate: 60 },
          audio: true
        });
      } catch (err) {
        log('Ekran paylaşımı iptal edildi veya izin verilmedi: ' + err.message, true);
        return;
      }

      const video = document.getElementById('previewVideo');
      video.srcObject = localStream;
      video.style.display = 'block';

      document.getElementById('startBtn').style.display = 'none';
      document.getElementById('stopBtn').style.display = 'inline-block';

      localStream.getVideoTracks()[0].onended = () => stopCast();

      const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${proto}//${location.host}/ws?role=sender&name=WebBrowser`;
      log('Alıcıya bağlanılıyor...');
      ws = new WebSocket(wsUrl);

      ws.onmessage = async (evt) => {
        try {
          const msg = JSON.parse(evt.data);
          if (msg.type === 'challenge') {
            const proof = await computeHmac(pin, msg.payload.salt);
            ws.send(JSON.stringify({ type: 'auth', payload: { proof: proof } }));
            log('PIN doğrulandı, bağlantı kuruluyor...');
          } else if (msg.type === 'paired') {
            log('Eşleşme sağlandı, WebRTC akışı başlatılıyor...');
            await initPeerConnection();
          } else if (msg.type === 'answer') {
            await pc.setRemoteDescription(new RTCSessionDescription(msg.payload));
            log('Canlı yayın aktarılıyor!');
          } else if (msg.type === 'ice') {
            if (msg.payload && msg.payload.candidate) {
              await pc.addIceCandidate(new RTCIceCandidate(msg.payload));
            }
          } else if (msg.type === 'error') {
            log('Hata: ' + (msg.reason || 'Bilinmeyen hata'), true);
            stopCast();
          }
        } catch (e) {
          log('Hata: ' + e.message, true);
        }
      };

      ws.onerror = (e) => log('Soket bağlantı hatası', true);
      ws.onclose = () => log('Bağlantı kapandı.');
    }

    async function initPeerConnection() {
      pc = new RTCPeerConnection({
        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
      });

      localStream.getTracks().forEach(track => pc.addTrack(track, localStream));

      pc.onicecandidate = (event) => {
        if (event.candidate && ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({
            type: 'ice',
            payload: {
              candidate: event.candidate.candidate,
              sdpMid: event.candidate.sdpMid,
              sdpMLineIndex: event.candidate.sdpMLineIndex
            }
          }));
        }
      };

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      ws.send(JSON.stringify({
        type: 'offer',
        payload: { sdp: offer.sdp, type: offer.type }
      }));
    }

    function stopCast() {
      if (localStream) {
        localStream.getTracks().forEach(t => t.stop());
        localStream = null;
      }
      if (pc) {
        pc.close();
        pc = null;
      }
      if (ws) {
        ws.close();
        ws = null;
      }
      document.getElementById('startBtn').style.display = 'inline-block';
      document.getElementById('stopBtn').style.display = 'none';
      document.getElementById('previewVideo').style.display = 'none';
      log('Yansıtma durduruldu.');
    }
  </script>
</body>
</html>
''';
