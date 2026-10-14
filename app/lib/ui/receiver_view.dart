import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/discovery/discovery_service.dart';
import '../core/protocol/models.dart';
import '../core/server/signaling_server.dart';
import '../core/storage/trust_store.dart';
import '../core/webrtc/webrtc_manager.dart';
import 'fullscreen_stream_view.dart';

class ActiveStreamTile {
  final String senderId;
  final String name;
  final RTCVideoRenderer renderer;
  final WebRtcManager webrtc;
  bool isMuted = false;
  double volume = 1.8; // Default 1.8 (180% boost for clear and loud playback)

  ActiveStreamTile({
    required this.senderId,
    required this.name,
    required this.renderer,
    required this.webrtc,
  });

  Future<void> setVolume(double newVolume) async {
    volume = newVolume.clamp(0.0, 3.0);
    final stream = renderer.srcObject;
    if (stream != null) {
      for (final t in stream.getAudioTracks()) {
        try {
          await Helper.setVolume(isMuted ? 0.0 : volume, t);
        } catch (_) {}
      }
    }
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    final stream = renderer.srcObject;
    if (stream != null) {
      for (final t in stream.getAudioTracks()) {
        t.enabled = !isMuted;
        try {
          await Helper.setVolume(isMuted ? 0.0 : volume, t);
        } catch (_) {}
      }
    }
  }

  Future<void> dispose() async {
    await webrtc.dispose();
    renderer.srcObject = null;
    await renderer.dispose();
  }
}

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
  final Map<String, ActiveStreamTile> _tiles = {};
  String? _focusedSenderId;

  late final DiscoveryService _discovery;
  TrustStore? _trustStore;

  @override
  void initState() {
    super.initState();
    _discovery = DiscoveryService();
    _initReceiver();
  }

  Future<void> _initReceiver() async {
    _trustStore = await TrustStore.create();
    await _fetchLocalIps();

    _server = SignalingServer(name: 'DoScreen-TV', requestedPort: 8788);
    await _server!.start();

    // Broadcast availability on LAN so sender devices automatically discover this receiver
    final primaryIp = _localIps.isNotEmpty ? _localIps.first : 'localhost';
    _discovery.startBroadcasting(
      name: 'DoScreen-TV',
      port: 8788,
      role: 'receiver',
      id: '$primaryIp:8788',
    );

    // Connect local controller socket as receiver role
    try {
      final ws = await WebSocket.connect('ws://127.0.0.1:${_server!.port}/ws?role=receiver');
      _receiverSocket = ws;

      ws.listen(_handleReceiverMessage, onDone: () {
        if (mounted) setState(() => _tiles.clear());
      });
    } catch (e) {
      debugPrint('Receiver WS error: $e');
    }
  }

  Future<void> _fetchLocalIps() async {
    try {
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
    } catch (_) {}
  }

  Future<void> _handleReceiverMessage(dynamic data) async {
    if (data is! String) return;
    final msg = SignalMessage.tryParse(data);
    if (msg == null) return;

    if (msg.type == 'pin') {
      if (mounted) setState(() => _pin = msg.pin ?? '------');
    } else if (msg.type == 'joined') {
      final senderId = msg.from;
      final senderName = msg.name ?? 'Cihaz';
      if (senderId != null) {
        _trustStore?.addTrustedDevice(senderId, senderName);
      }
    } else if (msg.type == 'offer') {
      final senderId = msg.from;
      if (senderId == null) return;
      final payload = msg.payload as Map<String, dynamic>;

      // Create new tile for this sender
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      final webrtc = WebRtcManager();

      final tile = ActiveStreamTile(
        senderId: senderId,
        name: 'Kaynak ($senderId)',
        renderer: renderer,
        webrtc: webrtc,
      );

      final answer = await webrtc.handleOffer(
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
          renderer.srcObject = stream;
          for (final t in stream.getAudioTracks()) {
            t.enabled = true;
            try {
              Helper.setVolume(tile.volume, t);
            } catch (_) {}
          }
          if (Platform.isIOS || Platform.isAndroid) {
            try {
              Helper.setSpeakerphoneOn(true);
            } catch (_) {}
          }
          if (mounted) setState(() {});
        },
      );

      if (mounted) {
        setState(() {
          _tiles[senderId] = tile;
        });
      }

      _receiverSocket?.add(SignalMessage(
        type: 'answer',
        to: senderId,
        payload: {'sdp': answer.sdp, 'type': answer.type},
      ).encode());
    } else if (msg.type == 'ice') {
      final senderId = msg.from;
      if (senderId != null && _tiles.containsKey(senderId)) {
        final payload = msg.payload as Map<String, dynamic>;
        await _tiles[senderId]?.webrtc.addCandidate(payload);
      }
    } else if (msg.type == 'left') {
      final senderId = msg.from;
      if (senderId != null && _tiles.containsKey(senderId)) {
        final tile = _tiles.remove(senderId);
        await tile?.dispose();
        if (_focusedSenderId == senderId) _focusedSenderId = null;
        if (mounted) setState(() {});
      }
    }
  }

  void _regeneratePin() {
    _receiverSocket?.add(const SignalMessage(type: 'regen').encode());
  }

  void _showTrustedDevicesDialog() {
    final trusted = _trustStore?.getTrustedDevices() ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('🔒 Güvenilen Cihazlar', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          child: trusted.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Henüz kayıtlı güvenilen cihaz yok.', style: TextStyle(color: Colors.grey)),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: trusted.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white12),
                itemBuilder: (_, i) {
                  final item = trusted[i];
                  return ListTile(
                    leading: const Icon(Icons.verified_user, color: Colors.cyanAccent),
                    title: Text(item['name'] ?? 'Cihaz', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('Token: ${item['token']?.substring(0, 10)}...', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () async {
                        await _trustStore?.revokeTrustedDevice(item['token'] ?? '');
                        if (!context.mounted) return;
                        Navigator.pop(ctx);
                        _showTrustedDevicesDialog();
                      },
                    ),
                  );
                },
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _discovery.dispose();
    _receiverSocket?.close();
    _server?.stop();
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    _tiles.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tiles.isNotEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildStreamGrid(),
            Positioned(
              top: 24,
              left: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                    const SizedBox(width: 8),
                    Text(
                      '${_tiles.length} Kaynak Yayında',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            if (_focusedSenderId != null)
              Positioned(
                top: 24,
                right: 24,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _focusedSenderId = null),
                  icon: const Icon(Icons.grid_view, size: 16),
                  label: const Text('Bölünmüş Ekrana Dön'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
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
                  'Gönderen cihazlar ağda bu ekranı otomatik görebilir veya adresi girebilir:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _showTrustedDevicesDialog,
                      icon: const Icon(Icons.security, size: 18, color: Colors.cyanAccent),
                      label: const Text('Güvenilen Cihazlar', style: TextStyle(color: Colors.cyanAccent)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamGrid() {
    final tileList = _tiles.values.toList();

    // If a single tile is focused, show it full-screen
    if (_focusedSenderId != null && _tiles.containsKey(_focusedSenderId)) {
      final tile = _tiles[_focusedSenderId]!;
      return _buildTileWrapper(tile, isFullscreen: true);
    }

    if (tileList.length == 1) {
      return _buildTileWrapper(tileList.first, isFullscreen: false);
    }

    // 2 senders: split horizontally
    if (tileList.length == 2) {
      return Row(
        children: tileList.map((t) => Expanded(child: _buildTileWrapper(t, isFullscreen: false))).toList(),
      );
    }

    // 3 or 4 senders: 2x2 grid
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildTileWrapper(tileList[0], isFullscreen: false)),
              Expanded(child: _buildTileWrapper(tileList[1], isFullscreen: false)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildTileWrapper(tileList[2], isFullscreen: false)),
              if (tileList.length > 3)
                Expanded(child: _buildTileWrapper(tileList[3], isFullscreen: false))
              else
                const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  void _openFullscreen(ActiveStreamTile tile) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => FullscreenStreamView(
          tile: tile,
          onMuteChanged: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Widget _buildTileWrapper(ActiveStreamTile tile, {required bool isFullscreen}) {
    final hasAudio = tile.renderer.srcObject?.getAudioTracks().isNotEmpty ?? false;

    return Container(
      margin: isFullscreen ? EdgeInsets.zero : const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: isFullscreen ? BorderRadius.zero : BorderRadius.circular(12),
        border: isFullscreen ? null : Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GestureDetector(
            onDoubleTap: () => _openFullscreen(tile),
            child: Center(
              child: RTCVideoView(
                tile.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cast_connected, color: Colors.cyanAccent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        tile.name,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: (hasAudio && !tile.isMuted)
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (hasAudio && !tile.isMuted) ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (hasAudio && !tile.isMuted) ? Icons.volume_up : Icons.volume_off,
                        color: (hasAudio && !tile.isMuted) ? Colors.greenAccent : Colors.orangeAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        !hasAudio
                            ? 'Ses Yok'
                            : (tile.isMuted ? 'Sessiz' : 'Ses %${(tile.volume * 100).toInt()}'),
                        style: TextStyle(
                          color: (hasAudio && !tile.isMuted) ? Colors.greenAccent : Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasAudio) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Tooltip(
                      message: 'Ses Seviyesi (Tıkla: Değiştir)',
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          double nextVol;
                          if (tile.volume < 1.0) {
                            nextVol = 1.0;
                          } else if (tile.volume < 1.5) {
                            nextVol = 1.5;
                          } else if (tile.volume < 2.0) {
                            nextVol = 2.0;
                          } else if (tile.volume < 2.5) {
                            nextVol = 2.5;
                          } else {
                            nextVol = 0.8;
                          }
                          await tile.setVolume(nextVol);
                          if (mounted) setState(() {});
                        },
                        child: Text(
                          '%${(tile.volume * 100).toInt()}',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(
                        tile.isMuted ? Icons.volume_off : Icons.volume_up,
                        color: tile.isMuted ? Colors.redAccent : Colors.cyanAccent,
                        size: 20,
                      ),
                      tooltip: tile.isMuted ? 'Sesi Aç' : 'Sesi Kapat',
                      onPressed: () async {
                        await tile.toggleMute();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(
                      isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      size: 20,
                    ),
                    tooltip: isFullscreen ? 'Bölünmüş Ekrana Dön' : 'Tam Ekran Yap',
                    onPressed: () {
                      if (isFullscreen) {
                        setState(() => _focusedSenderId = null);
                      } else {
                        _openFullscreen(tile);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
