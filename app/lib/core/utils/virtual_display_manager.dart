import 'dart:io';
import 'package:flutter/services.dart';

class VirtualDisplayManager {
  static const _channel = MethodChannel('app.doscreen/virtual_display');

  static Future<bool> isSupported() async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isSupported');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isActive() async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isActive');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> createVirtualDisplay({int width = 1920, int height = 1080}) async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await _channel.invokeMethod<bool>('create', {
        'width': width,
        'height': height,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> destroyVirtualDisplay() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('destroy');
    } catch (_) {}
  }
}
