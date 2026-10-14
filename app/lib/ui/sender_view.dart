import 'dart:async';
import 'package:flutter/material.dart';
import '../core/client/signaling_client.dart';
import '../core/webrtc/webrtc_manager.dart';

class SenderView extends StatefulWidget {
  const SenderView({super.key});

  @override
  State<SenderView> createState() => _SenderViewState();
}

class _SenderViewState extends State<SenderView> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _nameController = TextEditingController(text: 'Telefon/PC');

  SignalingClient? _client;
  WebRtcManager? _webrtc;
  bool _isStreaming = false;
  String? _statusMessage;
  Timer? _stopwatchTimer;
  String _currentTimestamp = '';

  @override
  void initState() {
    super.initState();
    _startStopwatch();
  }

  void _startStopwatch() {
    _stopwatchTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      final ms = now.millisecond.toString().padLeft(3, '0');
      final s = now.second.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      final h = now.hour.toString().padLeft(2, '0');
      if (mounted) {
        setState(() => _currentTimestamp = '$h:$m:$s.$ms');
      }
    });
  }

  Future<void> _startSharing() async {
    final host = _hostController.text.trim();
    final pin = _pinController.text.trim();
    final name = _nameController.text.trim().isEmpty ? 'Cihaz' : _nameController.text.trim();

    if (host.isEmpty) {
      setState(() => _statusMessage = 'Lütfen alıcı adresini girin.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _statusMessage = 'Lütfen 6 haneli PIN kodunu girin.');
      return;
    }

    setState(() {
      _statusMessage = 'Alıcıya bağlanılıyor...';
    });

    final targetUri = Uri.parse(host.startsWith('http') ? host : 'http://$host');
    final client = SignalingClient(
      serverUri: targetUri,
      deviceName: name,
      pin: pin,
    );
    _client = client;

    final webrtc = WebRtcManager(signalingClient: client);
    _webrtc = webrtc;

    client.on('paired', (msg) async {
      setState(() => _statusMessage = 'Eşleşti! Ekran yakalanıyor...');
      try {
        await webrtc.startScreenCapture();
        if (mounted) {
          setState(() {
            _isStreaming = true;
            _statusMessage = '🟢 Canlı Yayında';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _statusMessage = 'Ekran yakalama hatası: $e');
        }
        _stopSharing();
      }
    });

    client.on('answer', (msg) async {
      final payload = msg.payload as Map<String, dynamic>;
      await webrtc.handleAnswer(payload);
    });

    client.on('ice', (msg) async {
      final payload = msg.payload as Map<String, dynamic>;
      await webrtc.addCandidate(payload);
    });

    client.on('error', (msg) {
      final reason = msg.reason ?? 'Bilinmeyen hata';
      final errorMap = {
        'bad-pin': 'PIN kodu hatalı!',
        'room-full': 'Oda dolu (en fazla 4 kaynak).',
        'rate-limited': 'Çok fazla hatalı deneme! Lütfen 1 dakika bekleyin.',
        'receiver-gone': 'Alıcı kapandı.',
      };
      if (mounted) {
        setState(() => _statusMessage = '❌ ${errorMap[reason] ?? reason}');
      }
      _stopSharing();
    });

    await client.connect();
  }

  void _stopSharing() {
    _client?.close();
    _webrtc?.dispose();
    _client = null;
    _webrtc = null;
    if (mounted) {
      setState(() => _isStreaming = false);
    }
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _stopSharing();
    _hostController.dispose();
    _pinController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.screen_share, size: 54, color: Colors.blueAccent),
                  const SizedBox(height: 12),
                  const Text(
                    'Ekran Paylaş (Gönderici)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  if (_statusMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isStreaming ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isStreaming ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      child: Text(
                        _statusMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isStreaming ? Colors.greenAccent : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (!_isStreaming) ...[
                    TextField(
                      controller: _hostController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Alıcı Adresi (IP:Port)',
                        hintText: '192.168.1.100:8788',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        labelStyle: const TextStyle(color: Colors.blueAccent),
                        prefixIcon: const Icon(Icons.wifi, color: Colors.blueAccent),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 18),
                      decoration: InputDecoration(
                        labelText: 'Eşleşme PIN Kodu (6 Hane)',
                        counterText: '',
                        labelStyle: const TextStyle(color: Colors.blueAccent),
                        prefixIcon: const Icon(Icons.pin, color: Colors.blueAccent),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Cihaz Adı',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.devices, color: Colors.white70),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _startSharing,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Yayını Başlat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: _stopSharing,
                      icon: const Icon(Icons.stop),
                      label: const Text('Yayını Durdur'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  // Gecikme ölçüm kronometresi (camdan-cama ölçüm için)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Milisaniye Hassasiyetinde Saat (Gecikme Testi)',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _currentTimestamp,
                          style: const TextStyle(
                            color: Colors.yellowAccent,
                            fontSize: 22,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
