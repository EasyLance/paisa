import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/theme.dart';
import 'features/phase0/status_screen.dart';

void main() {
  runApp(const ProviderScope(child: PaisaApp()));
}

class PaisaApp extends ConsumerWidget {
  const PaisaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Paisa',
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: ref.watch(themeModeProvider),
    home: const StatusScreen(),
  );
}
