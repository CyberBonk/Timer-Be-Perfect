import 'dart:async';
import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/routes.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/fcm_service.dart';
import 'core/firebase/server_clock.dart';
import 'core/localization/app_locale.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'qa/qa_harness.dart';

const bool kUseFirebaseEmulators =
    bool.fromEnvironment('USE_FIREBASE_EMULATORS', defaultValue: false);
const bool kIsPhysicalPhoneAdlib =
    bool.fromEnvironment('PHYSICAL_PHONE_EMULATOR', defaultValue: false);
const bool kEnableQaHarness =
    bool.fromEnvironment('QA_HARNESS', defaultValue: false);

class FirebaseInitErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setError(String? err) => state = err;
}

final firebaseInitErrorProvider =
    NotifierProvider<FirebaseInitErrorNotifier, String?>(
        FirebaseInitErrorNotifier.new);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final alarmInitialization = Alarm.init();
  final notificationInitialization = NotificationService().initialize();

  String? initError;

  try {
    if (Firebase.apps.isEmpty) {
      // A device with a broken/filtered network must still render the app.
      // Firebase can be retried by the repositories after startup; it must
      // not hold the first Flutter frame indefinitely.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 8));
    }

    // Layer 2: Register top-level FCM background handler and start FcmService
    unawaited(FcmService().initialize());

    if (kUseFirebaseEmulators) {
      final emulatorHost = kIsPhysicalPhoneAdlib
          ? '127.0.0.1'
          : (Platform.isAndroid ? '10.0.2.2' : 'localhost');

      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
      FirebaseDatabase.instance.useDatabaseEmulator(emulatorHost, 9000);
      FirebaseFunctions.instanceFor(region: 'europe-west1')
          .useFunctionsEmulator(emulatorHost, 5001);
    }
  } catch (e) {
    if (!e.toString().contains('duplicate-app')) {
      debugPrint('Firebase Initialization Error: $e');
      initError = e.toString();
    }
  }

  ServerClock().start();
  try {
    await alarmInitialization.timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Alarm initialization did not complete before startup: $e');
  }
  unawaited(notificationInitialization);

  final container = ProviderContainer();
  if (initError != null) {
    container.read(firebaseInitErrorProvider.notifier).setError(initError);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: kEnableQaHarness
          ? const QaHarness(child: BePerfectApp())
          : const BePerfectApp(),
    ),
  );
}

class BePerfectApp extends ConsumerWidget {
  const BePerfectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSeed = ref.watch(themeSeedColorProvider);
    final locale = ref.watch(appLocaleProvider);

    return MaterialApp(
      title: 'Timer Be Perfect',
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightThemeWithSeed(selectedSeed),
      darkTheme: AppTheme.darkThemeWithSeed(selectedSeed),
      themeMode: ThemeMode.system,
      builder: (context, child) => TweenAnimationBuilder<double>(
        key: ValueKey(locale.languageCode),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        builder: (context, opacity, child) => Opacity(
          opacity: opacity,
          child: child,
        ),
        child: child,
      ),
      home: const NavigationHostPage(),
    );
  }
}
