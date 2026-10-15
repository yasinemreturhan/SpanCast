import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppUpdateInfo {
  final String version;
  final int versionCode;
  final String releaseDate;
  final String releaseNotes;
  final String downloadUrl;

  const AppUpdateInfo({
    required this.version,
    required this.versionCode,
    required this.releaseDate,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final downloads = json['downloads'] as Map<String, dynamic>? ?? {};
    String url = '';
    if (Platform.isAndroid) {
      url = downloads['android'] as String? ?? 'https://spancast.yasinemreturhan.com/SpanCast.apk';
    } else if (Platform.isWindows) {
      url = downloads['windows'] as String? ?? 'https://spancast.yasinemreturhan.com/SpanCast-Windows-x64.zip';
    } else if (Platform.isMacOS) {
      url = downloads['macos'] as String? ?? 'https://spancast.yasinemreturhan.com/SpanCast-macOS.zip';
    } else {
      url = 'https://spancast.yasinemreturhan.com';
    }

    return AppUpdateInfo(
      version: json['version'] as String? ?? '0.1.0',
      versionCode: json['versionCode'] as int? ?? 1,
      releaseDate: json['releaseDate'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? 'Performans ve kararlılık iyileştirmeleri.',
      downloadUrl: url,
    );
  }
}

class UpdateService {
  static const int currentVersionCode = 1;
  static const String currentVersionName = '0.1.0';

  static const String updateCheckUrl = 'https://spancast.yasinemreturhan.com/version.json';
  static const MethodChannel _channel = MethodChannel('app.spancast/updater');

  /// Checks the remote server for any newer version of SpanCast.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      final request = await client.getUrl(Uri.parse(updateCheckUrl));
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final info = AppUpdateInfo.fromJson(json);

        if (info.versionCode > currentVersionCode) {
          return info;
        }
      }
    } catch (e) {
      debugPrint('UpdateService check error: $e');
    }
    return null;
  }

  /// Downloads the APK and triggers Android system package installer directly.
  static Future<void> downloadAndInstall({
    required String downloadUrl,
    required void Function(double progress, int received, int total) onProgress,
  }) async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(downloadUrl));
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('İndirme sunucu hatası: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength;
    final tempDir = Directory.systemTemp;
    final targetFile = File('${tempDir.path}/spancast_update.apk');
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final sink = targetFile.openWrite();
    int receivedBytes = 0;

    await for (final chunk in response) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress(receivedBytes / totalBytes, receivedBytes, totalBytes);
      }
    }
    await sink.flush();
    await sink.close();

    if (Platform.isAndroid) {
      await _channel.invokeMethod('installApk', {
        'filePath': targetFile.path,
      });
    }
  }
}
