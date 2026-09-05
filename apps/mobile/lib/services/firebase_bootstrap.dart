import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseBootstrap {
  static const enabled = bool.fromEnvironment('FIREBASE_ENABLED');

  static Future<void> initialize() async {
    if (!enabled) return;

    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  static Future<String?> idToken() async {
    if (!enabled) return null;
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  static Future<String?> appCheckToken() async {
    if (!enabled) return null;
    return FirebaseAppCheck.instance.getToken();
  }
}
