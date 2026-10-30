// GERADO por scripts/generate_tokens.py a partir de packages/design-tokens/tokens.json. Não edite.
// ignore_for_file: constant_identifier_names

import 'dart:ui';

abstract final class EvoColors {
  static const bgBase = Color(0xFF0A0D14);
  static const bgSurface = Color(0xFF121722);
  static const bgElevated = Color(0xFF1A2030);
  static const borderSubtle = Color(0xFF262E40);
  static const textPrimary = Color(0xFFE8ECF4);
  static const textSecondary = Color(0xFF9AA4B8);
  static const accent = Color(0xFF4C7DFF);
  static const accentPressed = Color(0xFF3A66DB);
  static const onAccent = Color(0xFFFFFFFF);
  static const success = Color(0xFF3CCB8B);
  static const warning = Color(0xFFF2A93B);
  static const danger = Color(0xFFF0566A);
  static const stimulusNone = Color(0xFF3A4253);
  static const stimulusLow = Color(0xFF3D7BFF);
  static const stimulusMid = Color(0xFFF28C28);
  static const stimulusHigh = Color(0xFFE5484D);
}

abstract final class EvoSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double x2xl = 32;
  static const double x3xl = 48;
}

abstract final class EvoRadius {
  static const double input = 8;
  static const double card = 14;
  static const double pill = 999;
}

abstract final class EvoFontSize {
  static const double caption = 12;
  static const double bodySm = 14;
  static const double body = 16;
  static const double titleSm = 20;
  static const double title = 24;
  static const double displaySm = 32;
  static const double display = 40;
}

abstract final class EvoMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 250);
}

const double evoTouchTargetMin = 48;
