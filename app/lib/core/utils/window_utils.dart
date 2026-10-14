import 'dart:io';
import 'package:flutter/services.dart';

/// Manages native window operations such as true fullscreen.
class WindowUtils {
  static const MethodChannel _channel = MethodChannel('app.doscreen/window');

  /// Toggles native fullscreen (macOS NSWindow native space fullscreen, Android immersive mode).
  static Future<void> toggleFullScreen() async {
    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod('toggleFullScreen');
      } catch (_) {}
    } else if (Platform.isAndroid || Platform.isIOS) {
      try {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } catch (_) {}
    }
  }

  /// Sets native fullscreen state explicitly.
  static Future<void> setFullScreen(bool enable) async {
    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod('setFullScreen', {'enable': enable});
      } catch (_) {}
    } else if (Platform.isAndroid || Platform.isIOS) {
      try {
        if (enable) {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      } catch (_) {}
    }
  }

  /// Exits native fullscreen and restores standard UI bars.
  static Future<void> exitFullScreen() async {
    await setFullScreen(false);
  }
}
