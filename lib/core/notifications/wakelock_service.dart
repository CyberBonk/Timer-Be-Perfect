import 'dart:io';
import 'package:flutter/services.dart';

class WakeLockService {
  static const _channel = MethodChannel('com.cyberbonk.beperfect/wakelock');
  static final WakeLockService _instance = WakeLockService._internal();
  factory WakeLockService() => _instance;
  WakeLockService._internal();

  bool _isHeld = false;

  Future<void> acquire() async {
    if (!Platform.isAndroid || _isHeld) return;
    try {
      await _channel.invokeMethod('acquireWakeLock');
      _isHeld = true;
    } catch (_) {}
  }

  Future<void> release() async {
    if (!Platform.isAndroid || !_isHeld) return;
    try {
      await _channel.invokeMethod('releaseWakeLock');
      _isHeld = false;
    } catch (_) {}
  }
}
