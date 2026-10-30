// GERADO por scripts/generate_tokens.py a partir de packages/design-tokens/tokens.json. Não edite.
// ignore_for_file: constant_identifier_names

import 'dart:ui';

abstract final class EvoColors {
  static const bgBase = Color(0xFFF6F5F1);
  static const bgSurface = Color(0xFFFFFFFF);
  static const bgElevated = Color(0xFFECEBE6);
  static const borderSubtle = Color(0xFFE3E2DC);
  static const borderStrong = Color(0xFF8A8983);
  static const textPrimary = Color(0xFF0C0C0D);
  static const textSecondary = Color(0xFF5E5E63);
  static const accent = Color(0xFF0C0C0D);
  static const accentPressed = Color(0xFF2B2B2E);
  static const onAccent = Color(0xFFFFFFFF);
  static const success = Color(0xFF1E7F4F);
  static const warning = Color(0xFFA35F00);
  static const danger = Color(0xFFC62D2D);
  static const stimulusNone = Color(0xFFDCDBD5);
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
  static const double input = 14;
  static const double card = 22;
  static const double pill = 999;
}

abstract final class EvoFontSize {
  static const double caption = 12;
  static const double bodySm = 14;
  static const double body = 16;
  static const double titleSm = 20;
  static const double title = 24;
  static const double displaySm = 34;
  static const double display = 44;
}

abstract final class EvoMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const page = Duration(milliseconds: 420);
}

const double evoTouchTargetMin = 48;
