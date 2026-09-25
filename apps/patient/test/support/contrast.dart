import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Luminância relativa WCAG (definição de 1.4.3), 0.0 (preto) a 1.0 (branco).
double relativeLuminance(Color color) {
  double channel(double srgb) =>
      srgb <= 0.04045 ? srgb / 12.92 : math.pow((srgb + 0.055) / 1.055, 2.4).toDouble();
  // `Color.r/g/b` (0.0-1.0) substitui `.red/.green/.blue` (0-255),
  // descontinuados nesta versão do Flutter.
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
}

/// Razão de contraste WCAG entre duas cores OPACAS (sem canal alfa a
/// resolver). Para uma cor com alfa, componha antes com [compositeOver].
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Resolve uma cor com transparência (`Colors.white54`,
/// `color.withValues(alpha: ...)`) contra o fundo em que ela realmente é
/// pintada — sem isto, a luminância de uma cor semitransparente não
/// corresponde ao que a tela mostra.
Color compositeOver(Color fg, Color bg) {
  final a = fg.a; // 0.0-1.0
  double mix(double f, double b) => a * f + (1 - a) * b;
  return Color.from(
    alpha: 1.0,
    red: mix(fg.r, bg.r),
    green: mix(fg.g, bg.g),
    blue: mix(fg.b, bg.b),
  );
}

/// Razão de contraste já resolvendo o alfa de [fg] contra [bg].
double contrastOn(Color fg, Color bg) => contrastRatio(compositeOver(fg, bg), bg);
