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
