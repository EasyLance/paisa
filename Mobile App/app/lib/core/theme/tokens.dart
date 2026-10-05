import 'package:flutter/material.dart';

/// Colours that Material's ColorScheme has no slot for. Light values are the web
/// dashboard's tokens (docs/design.md §2). The dark set is new: the web has none.
@immutable
class PaisaColors extends ThemeExtension<PaisaColors> {
  const PaisaColors({
    required this.ink,
    required this.muted,
    required this.cream,
    required this.paper,
    required this.line,
    required this.lime,
    required this.coral,
    required this.positive,
    required this.essentials,
    required this.lifestyle,
    required this.saving,
    required this.other,
    required this.income,
  });

  final Color ink;
  final Color muted;
  final Color cream;
  final Color paper;
  final Color line;
  final Color lime;
  final Color coral;

  /// Text colour for money coming in (`+₹5,87,867`).
  final Color positive;

  final Color essentials;
  final Color lifestyle;
  final Color saving;
  final Color other;
  final Color income;

  /// Category-group swatch by the group name the API returns.
  Color group(String name) => switch (name.toLowerCase()) {
    'essentials' => essentials,
    'lifestyle' => lifestyle,
    'saving' => saving,
    'income' => income,
    _ => other,
  };

  static const light = PaisaColors(
    ink: Color(0xff17211c),
    // The web's #6e7771 reads 4.1:1 on the cream background; a phone is used
    // outdoors, so secondary text is darkened to pass 4.5:1 everywhere.
    muted: Color(0xff5b665f),
    cream: Color(0xfff4f2eb),
    paper: Color(0xffffffff),
    line: Color(0xffe5e7df),
    lime: Color(0xffd9e8a8),
    coral: Color(0xffe47d5f),
    positive: Color(0xff2b6a4a),
    essentials: Color(0xff244e3c),
    lifestyle: Color(0xffa9c467),
    saving: Color(0xffdf8d6d),
    other: Color(0xffa1a8a3),
    income: Color(0xff6399a4),
  );

  static const dark = PaisaColors(
    ink: Color(0xffe9eee9),
    muted: Color(0xff9aa7a0),
    cream: Color(0xff101714),
    paper: Color(0xff19231e),
    line: Color(0xff2a3730),
    lime: Color(0xffd9e8a8),
    coral: Color(0xffee9a80),
    positive: Color(0xff8fd0ac),
    essentials: Color(0xff5fa085),
    lifestyle: Color(0xffc3d98a),
    saving: Color(0xffeba083),
    other: Color(0xff8b948f),
    income: Color(0xff7fb4bf),
  );

  @override
  PaisaColors copyWith({
    Color? ink, Color? muted, Color? cream, Color? paper, Color? line, Color? lime, Color? coral, Color? positive,
    Color? essentials, Color? lifestyle, Color? saving, Color? other, Color? income,
  }) => PaisaColors(
    ink: ink ?? this.ink, muted: muted ?? this.muted, cream: cream ?? this.cream, paper: paper ?? this.paper,
    line: line ?? this.line, lime: lime ?? this.lime, coral: coral ?? this.coral, positive: positive ?? this.positive,
    essentials: essentials ?? this.essentials, lifestyle: lifestyle ?? this.lifestyle, saving: saving ?? this.saving,
    other: other ?? this.other, income: income ?? this.income,
  );

  @override
  PaisaColors lerp(ThemeExtension<PaisaColors>? other, double t) {
    if (other is! PaisaColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return PaisaColors(
      ink: mix(ink, other.ink), muted: mix(muted, other.muted), cream: mix(cream, other.cream), paper: mix(paper, other.paper),
      line: mix(line, other.line), lime: mix(lime, other.lime), coral: mix(coral, other.coral), positive: mix(positive, other.positive),
      essentials: mix(essentials, other.essentials), lifestyle: mix(lifestyle, other.lifestyle), saving: mix(saving, other.saving),
      other: mix(this.other, other.other), income: mix(income, other.income),
    );
  }
}

extension PaisaTheme on BuildContext {
  PaisaColors get paisa => Theme.of(this).extension<PaisaColors>()!;
}
