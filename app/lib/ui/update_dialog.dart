import 'package:flutter/material.dart';
import '../core/update/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(updateInfo: info),
    );
  }

  static Future<void> check(BuildContext context, {bool showIfLatest = false}) async {
    try {
      final info = await UpdateService.checkForUpdate();
      if (!context.mounted) return;

      if (info != null) {
        show(context, info);
      } else if (showIfLatest) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Text('Uygulamanız güncel (v${UpdateService.currentVersionName})'),
              ],
            ),
            backgroundColor: const Color(0xFF161B22),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (showIfLatest && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Güncelleme kontrolü başarısız: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _progressText = '';
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _progressText = 'İndirme başlatılıyor...';
    });

    try {
      await UpdateService.downloadAndInstall(
        downloadUrl: widget.updateInfo.downloadUrl,
        onProgress: (progress, received, total) {
          if (!mounted) return;
          final mbReceived = (received / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (total / (1024 * 1024)).toStringAsFixed(1);
          setState(() {
            _progress = progress;
            _progressText = '$mbReceived MB / $mbTotal MB (%${(progress * 100).toInt()})';
          });
        },
      );

      if (mounted) {
        setState(() {
          _progressText = 'Kurulum başlatılıyor...';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;

    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update, color: Colors.cyanAccent, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Yeni Güncelleme Mevcut!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'v${info.version}',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(Mevcut: v${UpdateService.currentVersionName})',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const Spacer(),
                if (info.releaseDate.isNotEmpty)
                  Text(
                    info.releaseDate,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Yenilikler:',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.white12,
                color: Colors.cyanAccent,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progressText,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Daha Sonra', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: _startUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Şimdi Güncelle', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ] else ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Arka Plana Al', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ],
    );
  }
}
