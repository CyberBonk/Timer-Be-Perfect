import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

/// Firebase-backed epoch clock for consistent timer calculations across devices.
class ServerClock {
  static final ServerClock _instance = ServerClock._internal();
  factory ServerClock() => _instance;
  ServerClock._internal();

  DatabaseReference? get _offsetRef {
    try {
      return FirebaseDatabase.instance.ref('.info/serverTimeOffset');
    } catch (_) {
      return null;
    }
  }
  StreamSubscription<DatabaseEvent>? _subscription;
  int _offsetMs = 0;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    try {
      final ref = _offsetRef;
      if (ref != null) {
        _subscription = ref.onValue.listen((event) {
          final value = event.snapshot.value;
          if (value is num) _offsetMs = value.toInt();
        });
      }
    } catch (_) {}
  }

  int nowMs() {
    start();
    return DateTime.now().millisecondsSinceEpoch + _offsetMs;
  }

  Future<int> syncedNowMs() async {
    start();
    try {
      final ref = _offsetRef;
      if (ref != null) {
        final snapshot =
            await ref.get().timeout(const Duration(seconds: 2));
        final value = snapshot.value;
        if (value is num) _offsetMs = value.toInt();
      }
    } catch (_) {
      // Offline fallback uses the last known offset, initially zero.
    }
    return nowMs();
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
