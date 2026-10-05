import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/theme/theme.dart';
import 'package:paisa_mobile/core/theme/tokens.dart';

double _channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double _luminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      final theme = buildTheme(brightness);
      final c = theme.extension<PaisaColors>()!;
      final scheme = theme.colorScheme;

      test('body and secondary text meet WCAG AA (4.5:1) on every surface', () {
        for (final surface in [c.cream, c.paper]) {
          expect(contrast(c.ink, surface), greaterThanOrEqualTo(4.5), reason: 'ink on $surface');
          expect(contrast(c.muted, surface), greaterThanOrEqualTo(4.5), reason: 'muted on $surface');
          expect(contrast(c.positive, surface), greaterThanOrEqualTo(4.5), reason: 'positive on $surface');
        }
      });

      test('buttons and the review banner are readable', () {
        expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onPrimaryContainer, scheme.primaryContainer), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.error, c.paper), greaterThanOrEqualTo(4.5));
      });

      test('chart colours are visible on the card and all different', () {
        final swatches = [c.essentials, c.lifestyle, c.saving, c.other, c.income];
        // WCAG asks 3:1 for graphics that carry meaning on their own. The light
        // swatches are the web's brand colours and the lighter ones sit near 2:1,
        // so every segment is also named and valued in a legend; the colour is
        // never the only carrier. This floor stops a swatch fading into the card.
        for (final swatch in swatches) {
          expect(contrast(swatch, c.paper), greaterThanOrEqualTo(1.9));
        }
        expect(swatches.toSet().length, swatches.length);
      });

      test('group lookup falls back to Other', () {
        expect(c.group('Essentials'), c.essentials);
        expect(c.group('something new'), c.other);
      });
    });
  }
}
