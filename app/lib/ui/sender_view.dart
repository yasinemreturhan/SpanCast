import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
  bool _shareSystemAudio = true;
  bool _shareMicrophone = false;
  bool _isSystemAudioMuted = false;
  bool _isMicrophoneMuted = false;
  String? _statusMessage;
  Timer? _stopwatchTimer;
  String _currentTimestamp = '';

  late final DiscoveryService _discovery;
  TrustStore? _trustStore;
  List<DiscoveredDevice> _discoveredDevices = [];
  String? _selectedDeviceToken;

  List<DesktopCapturerSource> _availableSources = [];
  String? _selectedSourceId;

  @override
  void initState() {
    super.initState();
    _startStopwatch();
    _initDiscovery();
    if (WebRTC.platformIsDesktop) {
      _loadDesktopSources();
    }
  }

  Future<void> _loadDesktopSources() async {
    try {
      final sources = await desktopCapturer.getSources(types: [SourceType.Screen]);
      if (mounted) {
        setState(() {
          _availableSources = sources;
          if (sources.isNotEmpty && _selectedSourceId == null) {
            _selectedSourceId = sources.first.id;
          }
        });
      }
    } catch (_) {}
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

    String cleanHost = host.trim();
    if (!cleanHost.startsWith('http://') &&
        !cleanHost.startsWith('https://') &&
        !cleanHost.startsWith('ws://') &&
        !cleanHost.startsWith('wss://')) {
      cleanHost = 'http://$cleanHost';
    }
    Uri targetUri = Uri.parse(cleanHost);
    if (!targetUri.hasPort || targetUri.port == 80) {
      targetUri = targetUri.replace(port: 8788);
    }

    final client = SignalingClient(
      serverUri: targetUri,
      deviceName: name,
      pin: pin.isNotEmpty ? pin : '000000',
      trustToken: token,
    );
    _client = client;

    final webrtc = WebRtcManager(signalingClient: client);
    _webrtc = webrtc;

    client.on('_state', (msg) {
      if (mounted && !_isStreaming) {
        if (msg.reason == 'connecting') {
          setState(() => _statusMessage = 'Alıcıya bağlanılıyor...');
        } else if (msg.reason == 'authenticating') {
          setState(() => _statusMessage = 'Doğrulanıyor...');
        }
      }
    });

    client.on('paired', (msg) async {
      final issued = client.issuedToken;
      if (issued != null) {
        await _trustStore?.saveToken(host, issued);
      }

      setState(() => _statusMessage = 'Eşleşti! Ekran yakalanıyor...');
      try {
        await webrtc.startScreenCapture(
          sourceId: _selectedSourceId,
          enableAudio: _shareSystemAudio || _shareMicrophone,
          enableSystemAudio: _shareSystemAudio,
          enableMicrophone: _shareMicrophone,
        );
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
        'connection-failed': 'Alıcıya bağlanılamadı. IP adresini ve alıcının açık olduğunu kontrol edin.',
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
                    const SizedBox(height: 14),
                    _buildSourceSelector(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 4, bottom: 2),
                            child: Text(
                              'SES SEÇENEKLERİ',
                              style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ),
                          CheckboxListTile(
                            value: _shareSystemAudio,
                            onChanged: (v) => setState(() => _shareSystemAudio = v ?? true),
                            title: const Text('Medya / Sistem Sesi', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Video, müzik ve oyun sesleri aktarılır', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            secondary: const Icon(Icons.volume_up, color: Colors.cyanAccent),
                            activeColor: Colors.blueAccent,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _shareMicrophone,
                            onChanged: (v) => setState(() => _shareMicrophone = v ?? false),
                            title: const Text('Mikrofon Sesi', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Kendi konuşmanız ve ortam sesi aktarılır', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            secondary: const Icon(Icons.mic, color: Colors.orangeAccent),
                            activeColor: Colors.blueAccent,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
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
                    // Live Audio Controls while Streaming
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          const Text('CANLI SES KONTROLÜ', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() => _isSystemAudioMuted = !_isSystemAudioMuted);
                                    _webrtc?.setSystemAudioEnabled(!_isSystemAudioMuted);
                                  },
                                  icon: Icon(
                                    _isSystemAudioMuted ? Icons.volume_off : Icons.volume_up,
                                    color: _isSystemAudioMuted ? Colors.redAccent : Colors.cyanAccent,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _isSystemAudioMuted ? 'Medya Kapalı' : 'Medya Açık',
                                    style: TextStyle(
                                      color: _isSystemAudioMuted ? Colors.redAccent : Colors.cyanAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: _isSystemAudioMuted ? Colors.redAccent : Colors.cyanAccent),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() => _isMicrophoneMuted = !_isMicrophoneMuted);
                                    _webrtc?.setMicrophoneEnabled(!_isMicrophoneMuted);
                                  },
                                  icon: Icon(
                                    _isMicrophoneMuted ? Icons.mic_off : Icons.mic,
                                    color: _isMicrophoneMuted ? Colors.redAccent : Colors.orangeAccent,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _isMicrophoneMuted ? 'Mic Kapalı' : 'Mic Açık',
                                    style: TextStyle(
                                      color: _isMicrophoneMuted ? Colors.redAccent : Colors.orangeAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: _isMicrophoneMuted ? Colors.redAccent : Colors.orangeAccent),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

  Widget _buildSourceSelector() {
    if (!WebRTC.platformIsDesktop || _availableSources.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Paylaşılacak Ekran / Monitör',
              style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
              tooltip: 'Ekranları Yenile',
              onPressed: _loadDesktopSources,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedSourceId,
          dropdownColor: const Color(0xFF161B22),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.monitor, color: Colors.blueAccent),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: _availableSources.map((src) {
            final isScreen = src.type == SourceType.Screen;
            return DropdownMenuItem<String>(
              value: src.id,
              child: Row(
                children: [
                  Icon(isScreen ? Icons.desktop_windows : Icons.web_asset, size: 18, color: Colors.cyanAccent),
                  const SizedBox(width: 8),
                  Text(
                    src.name.isNotEmpty ? src.name : 'Ekran ${src.id}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            setState(() => _selectedSourceId = val);
          },
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (_availableSources.length > 1)
                ? Colors.green.withValues(alpha: 0.15)
                : const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (_availableSources.length > 1)
                  ? Colors.greenAccent
                  : Colors.cyanAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                (_availableSources.length > 1) ? Icons.check_circle : Icons.help_outline,
                color: (_availableSources.length > 1) ? Colors.greenAccent : Colors.cyanAccent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (_availableSources.length > 1)
                          ? 'Çoklu Ekran Aktif (${_availableSources.length} Monitör Bulundu)'
                          : 'TV veya Tableti 2. Monitör Yapma',
                      style: TextStyle(
                        color: (_availableSources.length > 1) ? Colors.greenAccent : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (_availableSources.length > 1)
                          ? 'Yukarıdaki menüden 2. ekranınızı seçip TV\'ye aktarabilirsiniz'
                          : 'BetterDisplay veya Dummy HDMI ile bağımsız masaüstü oluşturma',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _showVirtualDisplayGuide,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: const Text('Rehber', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  void _showVirtualDisplayGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF30363D)),
        ),
        title: Row(
          children: const [
            Icon(Icons.desktop_windows, color: Colors.cyanAccent),
            SizedBox(width: 10),
            Text('🖥️ 2. Monitör Yapma Rehberi', style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Televizyonu veya tableti ana ekranınızı aynalamak yerine tamamen bağımsız bir 2. monitör olarak kullanabilirsiniz:',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 14),
                Text(
                  '🪟 Windows 10 / 11:',
                  style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  '1. Açık kaynaklı Virtual Display Driver (IddCx VDD) ile sanal bir ekran açın (veya 2. fiziksel monitörünüzü bağlayın).\n'
                  '2. Windows Ayarları -> Sistem -> Ekran -> "Bu ekranları genişlet" (Extend) seçeneğini seçin.\n'
                  '3. DoScreen üzerindeki "Ekranları Yenile" butonuna basın ve listeden "Ekran 2"yi seçin.\n'
                  '4. TV\'ye yayını başlatın! Artık TV\'niz bağımsız 2. ekranınızdır.',
                  style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                ),
                SizedBox(height: 14),
                Text(
                  '🍎 macOS (Mac):',
                  style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  '1. Ücretsiz BetterDisplay veya FluffyDisplay uygulamasını açın ve "Create Virtual Screen" deyin (veya Mac\'inize donanımsal bir Dummy HDMI fişi takın).\n'
                  '2. macOS anında yeni bir genişletilmiş masaüstü oluşturacaktır.\n'
                  '3. DoScreen bu ekranı doğrudan algılayıp yukarıdaki listede "Ekran 2" olarak gösterir.\n'
                  '4. Ekran 2\'yi seçip TV\'ye yayını başlatın!',
                  style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anladım', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }
}
