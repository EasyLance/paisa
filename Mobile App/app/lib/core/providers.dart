import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/models.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  // Phase 1 swaps NoAuth for a Firebase-backed AuthSource.
  const AuthSource auth = AppConfig.devAuth ? DevAuth(AppConfig.devUserId) : NoAuth();
  final client = ApiClient(baseUrl: AppConfig.apiUrl, auth: auth);
  ref.onDispose(client.close);
  return client;
});

final meProvider = FutureProvider<Me>((ref) async {
  final json = await ref.watch(apiClientProvider).get('/v1/me');
  return Me.fromJson(json as Map<String, dynamic>);
});

final booksProvider = FutureProvider<List<Book>>((ref) async {
  final json = await ref.watch(apiClientProvider).get('/v1/books') as Map<String, dynamic>;
  return [for (final item in json['items'] as List) Book.fromJson(item as Map<String, dynamic>)];
});

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void choose(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
