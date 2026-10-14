import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/protocol/models.dart';
import '../core/server/signaling_server.dart';
import '../core/webrtc/webrtc_manager.dart';

class ReceiverView extends StatefulWidget {
  const ReceiverView({super.key});

  @override
  State<ReceiverView> createState() => _ReceiverViewState();
}

class _ReceiverViewState extends State<ReceiverView> {
  SignalingServer? _server;
  WebSocket? _receiverSocket;
  String _pin = '------';
  List<String> _localIps = [];
  bool _isStreaming = false;
  String? _connectedSenderName;

  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final WebRtcManager _webrtc = WebRtcManager();

  @override
  void initState() {
    super.initState();
    _initReceiver();
  }

  Future<void> _initReceiver() async {
    await _renderer.initialize();
    await _fetchLocalIps();

    _server = SignalingServer(name: 'DoScreen-TV', requestedPort: 8788);
    await _server!.start();

    // Connect local controller socket as receiver role
    try {
      final ws = await WebSocket.connect('ws://localhost:8788/ws?role=receiver');
      _receiverSocket = ws;

      ws.listen(_handleReceiverMessage, onDone: () {
        if (mounted) setState(() => _isStreaming = false);
      });
    } catch (e) {
      debugPrint('Receiver WS error: $e');
    }
  }

  Future<void> _fetchLocalIps() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final ips = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        ips.add(addr.address);
      }
    }
    if (mounted) setState(() => _localIps = ips);
  }

  Future<void> _handleReceiverMessage(dynamic data) async {
    if (data is! String) return;
    final msg = SignalMessage.tryParse(data);
    if (msg == null) return;

    if (msg.type == 'pin') {
      if (mounted) setState(() => _pin = msg.pin ?? '------');
    } else if (msg.type == 'joined') {
      if (mounted) {
        setState(() => _connectedSenderName = msg.name ?? 'Cihaz');
      }
    } else if (msg.type == 'offer') {
      final senderId = msg.from;
      final payload = msg.payload as Map<String, dynamic>;

      final answer = await _webrtc.handleOffer(
        payload,
        (candidate) {
          _receiverSocket?.add(SignalMessage(
            type: 'ice',
            to: senderId,
            payload: {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          ).encode());
        },
        (stream) {
          _renderer.srcObject = stream;
          if (mounted) setState(() => _isStreaming = true);
        },
      );

      _receiverSocket?.add(SignalMessage(
        type: 'answer',
        to: senderId,
        payload: {'sdp': answer.sdp, 'type': answer.type},
      ).encode());
    } else if (msg.type == 'ice') {
      final payload = msg.payload as Map<String, dynamic>;
      await _webrtc.addCandidate(payload);
    } else if (msg.type == 'left') {
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _connectedSenderName = null;
        });
      }
    }
  }

  void _regeneratePin() {
    _receiverSocket?.add(const SignalMessage(type: 'regen').encode());
  }

  @override
  void dispose() {
    _receiverSocket?.close();
    _server?.stop();
    _webrtc.dispose();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isStreaming) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: RTCVideoView(
                _renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),
            Positioned(
              top: 24,
              left: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                    const SizedBox(width: 8),
                    Text(
                      'Yayında: ${_connectedSenderName ?? 'Cihaz'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () {
                  setState(() => _isStreaming = false);
                },
              ),
            ),
          ],
        ),
      );
    }

    final ipDisplay = _localIps.isNotEmpty ? _localIps.first : '192.168.x.x';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550),
        child: Card(
          color: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF30363D)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tv, size: 54, color: Colors.cyanAccent),
                const SizedBox(height: 12),
                const Text(
                  'Bu Ekran Alıcı Olarak Hazır',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Gönderen cihazda aşağıdaki adresi ve PIN kodunu girin:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi, color: Colors.cyanAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '$ipDisplay:8788',
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'EŞLEŞME KODU',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _pin,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _regeneratePin,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Yeni Kod Üret'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
