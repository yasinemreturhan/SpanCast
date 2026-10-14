import 'dart:async';
import 'package:flutter/material.dart';
import '../core/client/signaling_client.dart';
import '../core/discovery/device_model.dart';
import '../core/discovery/discovery_service.dart';
import '../core/storage/trust_store.dart';
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
  bool _shareAudio = true;
  String? _statusMessage;
  Timer? _stopwatchTimer;
  String _currentTimestamp = '';

  late final DiscoveryService _discovery;
  TrustStore? _trustStore;
  List<DiscoveredDevice> _discoveredDevices = [];
  String? _selectedDeviceToken;

  @override
  void initState() {
    super.initState();
    _startStopwatch();
    _initDiscovery();
  }

  Future<void> _initDiscovery() async {
    _trustStore = await TrustStore.create();
    _discovery = DiscoveryService();
    await _discovery.startListening();

    _discovery.devicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _discoveredDevices = devices;
        });
      }
    });
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

  void _selectDevice(DiscoveredDevice device) {
    setState(() {
      _hostController.text = device.endpoint;
      final token = _trustStore?.getToken(device.endpoint);
      _selectedDeviceToken = token;
      if (token != null) {
        _statusMessage = '🔒 Bu cihazla önceden eşleşildi. PIN girmeden bağlanabilirsiniz!';
      } else {
        _statusMessage = null;
      }
    });
  }

  Future<void> _startSharing() async {
    final host = _hostController.text.trim();
    final pin = _pinController.text.trim();
    final name = _nameController.text.trim().isEmpty ? 'Cihaz' : _nameController.text.trim();
    final token = _selectedDeviceToken ?? _trustStore?.getToken(host);

    if (host.isEmpty) {
      setState(() => _statusMessage = 'Lütfen alıcı adresini girin veya listeden seçin.');
      return;
    }
    if (token == null && !RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _statusMessage = 'Lütfen 6 haneli PIN kodunu girin.');
      return;
    }

    setState(() {
      _statusMessage = token != null
          ? '🔒 Kayıtlı cihaz olarak bağlanılıyor...'
          : 'Alıcıya bağlanılıyor...';
    });

    final targetUri = Uri.parse(host.startsWith('http') ? host : 'http://$host');
    final client = SignalingClient(
      serverUri: targetUri,
      deviceName: name,
      pin: pin.isNotEmpty ? pin : '000000',
      trustToken: token,
    );
    _client = client;

    final webrtc = WebRtcManager(signalingClient: client);
    _webrtc = webrtc;

    client.on('paired', (msg) async {
      final issued = client.issuedToken;
      if (issued != null) {
        await _trustStore?.saveToken(host, issued);
      }

      setState(() => _statusMessage = 'Eşleşti! Ekran yakalanıyor...');
      try {
        await webrtc.startScreenCapture(enableAudio: _shareAudio);
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

    client.on('error', (msg) async {
      final reason = msg.reason ?? 'Bilinmeyen hata';
      if (reason == 'bad-token') {
        await _trustStore?.removeToken(host);
        _selectedDeviceToken = null;
      }

      final errorMap = {
        'bad-pin': 'PIN kodu hatalı!',
        'bad-token': 'Kayıtlı cihaz süresi doldu. Lütfen PIN ile tekrar bağlanın.',
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
    _discovery.dispose();
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
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            color: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF30363D)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.screen_share, size: 50, color: Colors.blueAccent),
                  const SizedBox(height: 10),
                  const Text(
                    'Ekran Paylaş (Gönderici)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 18),

                  // Discovered devices panel
                  if (!_isStreaming) ...[
                    _buildDiscoveredDevicesList(),
                    const SizedBox(height: 18),
                  ],

                  if (_statusMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isStreaming ? Colors.green.withValues(alpha: 0.15) : Colors.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isStreaming ? Colors.greenAccent : Colors.cyanAccent,
                        ),
                      ),
                      child: Text(
                        _statusMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isStreaming ? Colors.greenAccent : Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (!_isStreaming) ...[
                    TextField(
                      controller: _hostController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (val) {
                        setState(() {
                          _selectedDeviceToken = _trustStore?.getToken(val.trim());
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Alıcı Adresi (IP:Port)',
                        hintText: '192.168.1.100:8788',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        labelStyle: const TextStyle(color: Colors.blueAccent),
                        prefixIcon: const Icon(Icons.wifi, color: Colors.blueAccent),
                        suffixIcon: _selectedDeviceToken != null
                            ? const Tooltip(
                                message: 'Kayıtlı Güvenilen Cihaz (PIN Gerekmez)',
                                child: Icon(Icons.verified, color: Colors.cyanAccent),
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_selectedDeviceToken == null) ...[
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
                      const SizedBox(height: 14),
                    ],
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
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _shareAudio,
                      onChanged: (v) => setState(() => _shareAudio = v ?? true),
                      title: const Text('Sistem Sesini de Aktar', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Görüntüyle birlikte ses de iletilir', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      activeColor: Colors.blueAccent,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _startSharing,
                      icon: Icon(_selectedDeviceToken != null ? Icons.bolt : Icons.play_arrow),
                      label: Text(
                        _selectedDeviceToken != null
                            ? 'Tek Tıkla Yayını Başlat (PIN Yok)'
                            : 'Yayını Başlat',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedDeviceToken != null ? Colors.cyan : Colors.blueAccent,
                        foregroundColor: _selectedDeviceToken != null ? Colors.black : Colors.white,
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
                  const SizedBox(height: 24),
                  // Gecikme ölçüm kronometresi (camdan-cama ölçüm için)
                  Container(
                    padding: const EdgeInsets.all(12),
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
                        const SizedBox(height: 4),
                        Text(
                          _currentTimestamp,
                          style: const TextStyle(
                            color: Colors.yellowAccent,
                            fontSize: 20,
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

  Widget _buildDiscoveredDevicesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'AĞDAKİ CİHAZLAR (OTOMATİK KEŞİF)',
              style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 6),
                const Text('Aranıyor...', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_discoveredDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_find, color: Colors.grey, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aynı Wi-Fi ağında açık bir DoScreen alıcısı bekleniyor...',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _discoveredDevices.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final dev = _discoveredDevices[i];
                final isSelected = _hostController.text.trim() == dev.endpoint;
                final isTrusted = _trustStore?.getToken(dev.endpoint) != null;

                return InkWell(
                  onTap: () => _selectDevice(dev),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.cyan.withValues(alpha: 0.2) : const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.cyanAccent : (isTrusted ? Colors.greenAccent.withValues(alpha: 0.6) : Colors.white12),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          dev.role == 'receiver' ? Icons.tv : Icons.devices,
                          color: isSelected ? Colors.cyanAccent : Colors.white70,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  dev.name,
                                  style: TextStyle(
                                    color: isSelected ? Colors.cyanAccent : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                if (isTrusted) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, color: Colors.greenAccent, size: 14),
                                ],
                              ],
                            ),
                            Text(
                              dev.endpoint,
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
