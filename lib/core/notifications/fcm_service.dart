import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase/room_repository.dart';
import 'fcm_background_handler.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  static const _fcmTokenKey = 'fcm_device_token';

  String? _cachedToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return;

    try {
      // 1. Register top-level background isolate message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 2. Request notification permissions (Android 13+ POST_NOTIFICATIONS)
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      // 3. Retrieve and cache current registration token
      _cachedToken = await messaging.getToken();
      if (_cachedToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_fcmTokenKey, _cachedToken!);
      }

      // 4. Listen for token refreshes
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        _cachedToken = newToken;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_fcmTokenKey, newToken);

        final activeRoomId = prefs.getString('active_room_id');
        if (activeRoomId != null && activeRoomId.isNotEmpty) {
          try {
            await RoomRepository().updateMemberReadiness(
              roomId: activeRoomId,
              fcmToken: newToken,
            );
          } catch (e) {
            debugPrint('Failed to sync refreshed FCM token to room: $e');
          }
        }
      });

      // 5. Handle foreground data pushes
      _foregroundMessageSub =
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.data.isNotEmpty) {
          handleBackgroundDataMessage(message.data);
        }
      });

      _initialized = true;
    } catch (e) {
      debugPrint('FCM initialization warning: $e');
    }
  }

  Future<String?> getToken() async {
    if (kIsWeb) return null;
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_fcmTokenKey);
      if (stored != null && stored.isNotEmpty) {
        _cachedToken = stored;
        return stored;
      }
      _cachedToken = await FirebaseMessaging.instance.getToken();
      if (_cachedToken != null) {
        await prefs.setString(_fcmTokenKey, _cachedToken!);
      }
      return _cachedToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> syncTokenWithRoom({
    required String roomId,
    RoomRepository? repository,
  }) async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      final repo = repository ?? RoomRepository();
      try {
        await repo.updateMemberReadiness(
          roomId: roomId,
          fcmToken: token,
        );
      } catch (e) {
        debugPrint('Failed to sync FCM token with room $roomId: $e');
      }
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMessageSub?.cancel();
  }
}
