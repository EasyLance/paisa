import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/theme/theme.dart';

// The app has one typeface, Anek Latin, bundled in the app. These tests keep it
// that way: a second family, or a font that is declared but not shipped, would
// show up on a phone and not in any other test (the test runner draws every
// font as boxes).
void main() {
  test('the theme sets Anek Latin as the family for every text style', () {
    for (final brightness in Brightness.values) {
      final theme = buildTheme(brightness);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'AnekLatin');
      for (final style in [
        theme.textTheme.displaySmall,
        theme.textTheme.headlineMedium,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelSmall,
      ]) {
        expect(style?.fontFamily, 'AnekLatin');
      }
    }
  });

  test('no screen picks a typeface of its own', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && !file.path.endsWith('core/theme/theme.dart') && file.readAsStringSync().contains('fontFamily')) file.path,
    ];
    expect(offenders, isEmpty, reason: 'only the theme names a font');
  });

  test('the font is declared in pubspec and the file and its licence are really there', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: AnekLatin'));
    expect(pubspec, contains('asset: assets/fonts/AnekLatin.ttf'));
    expect(pubspec, contains('assets/fonts/OFL.txt'));
    final font = File('assets/fonts/AnekLatin.ttf').readAsBytesSync();
    expect(font.length, greaterThan(100000), reason: 'a real font, not a stub');
    expect(font.sublist(0, 4), [0, 1, 0, 0], reason: 'TrueType header');
    expect(File('assets/fonts/OFL.txt').readAsStringSync(), contains('SIL Open Font License'));
  });

  test('headings are heavier than body text, so the hierarchy survives a single family', () {
    final text = buildTheme(Brightness.light).textTheme;
    expect(text.titleLarge!.fontWeight!.value, greaterThan(text.bodyMedium!.fontWeight?.value ?? 400));
    expect(text.headlineSmall!.fontWeight!.value, greaterThanOrEqualTo(600));
  });
}
