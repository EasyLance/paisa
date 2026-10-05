import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loaded once in `main()` and overridden in tests. Everything kept here is a
/// convenience (theme, last book, lock setting), never a secret or a permission.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Override sharedPreferencesProvider'));
