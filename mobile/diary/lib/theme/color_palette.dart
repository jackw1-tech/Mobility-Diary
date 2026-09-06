import 'package:flutter/material.dart';

/// Palette ispirata al design system Uber: un duetto bianco/nero con scala di
/// grigi, dove il nero `primary` e' l'unico colore di conversione (ogni CTA,
/// la nav, le bande scure). Non esiste un secondo accento di brand.
///
/// Deviazione consapevole rispetto al brand puro: i colori semantici
/// (`success`/`warning`/`error`) sono mantenuti perche' in un'app di tracking
/// gli stati di sincronizzazione devono restare distinguibili a colpo d'occhio.
/// Tutto il resto, incluso lo stato "in corso" (`info`), resta nero.
class ColorPalette {
  // Brand: il nero e' l'unico colore di conversione.
  static const Color primary = Color(0xFF000000); // ink
  static const Color secondary = Color(0xFF5E5E5E); // body gray
  static const Color accent = Color(0xFF000000); // nessun secondo accento: ink

  // Superfici (canvas Uber)
  static const Color background = Color(0xFFEFEFEF); // canvas-soft
  static const Color surface = Color(0xFFFFFFFF); // canvas
  static const Color surfaceSoft = Color(0xFFEFEFEF); // canvas-soft
  static const Color surfaceSofter = Color(0xFFF3F3F3); // canvas-softer
  static const Color surfacePressed =
      Color(0xFFE2E2E2); // pressed pill / divider
  static const Color hairline = Color(0xFFE2E2E2); // bordi flat sulle card

  // Testo
  static const Color textPrimary = Color(0xFF000000); // ink
  static const Color textSecondary = Color(0xFF5E5E5E); // body
  static const Color textHint = Color(0xFFAFAFAF); // mute

  // Stato di sincronizzazione (mantenuti funzionali).
  static const Color error = Color(0xFFD93025);
  static const Color success = Color(0xFF1F8A4C);
  static const Color warning = Color(0xFFEC7E00);
  static const Color info = Color(0xFF000000); // "in corso": ink, on-brand

  // ── Dark mode ─────────────────────────────────────────────────────────
  // Inversione contrasto Uber-style: sfondo quasi nero, testo bianco.

  // Primary: il bianco diventa il colore di conversione su sfondo scuro.
  static const Color darkPrimary = Color(0xFFFFFFFF);
  static const Color darkSecondary = Color(0xFFB0B0B0);

  // Superfici
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceSoft = Color(0xFF2C2C2C);
  static const Color darkSurfaceSofter = Color(0xFF252525);
  static const Color darkSurfacePressed = Color(0xFF3A3A3A);
  static const Color darkHairline = Color(0xFF3A3A3A);

  // Testo
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB0B0B0);
  static const Color darkTextHint = Color(0xFF6E6E6E);

  // Stato di sincronizzazione — versioni più luminose per sfondo scuro.
  static const Color darkError = Color(0xFFEF5350);
  static const Color darkSuccess = Color(0xFF4CAF50);
  static const Color darkWarning = Color(0xFFFFA726);
  static const Color darkInfo = Color(0xFFFFFFFF); // "in corso": bianco, on-brand
}
