import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/auth/auth_service.dart';
import 'core/prefs.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Local development talks to the API's dev auth and needs no Firebase.
  if (!AppConfig.devAuth) await Firebase.initializeApp();
  final AuthService auth = AppConfig.devAuth ? DevAuthService(AppConfig.devUserId) : FirebaseAuthService();
  runApp(ProviderScope(
    // Riverpod retries a failed provider on its own. A failed sign-in lookup
    // should show its error once, not hammer the API.
    retry: (count, error) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authServiceProvider.overrideWithValue(auth),
    ],
    child: const PaisaApp(),
  ));
}
