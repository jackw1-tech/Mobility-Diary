import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:flutter/material.dart';

/// Helper di presentazione dei livelli di privacy, condivisi fra il profilo e
/// l'onboarding. L'icona sta qui e non sull'enum perche' e' una scelta di
/// presentazione: il layer model resta senza dipendenze dal framework UI.
IconData privacyLevelIcon(PrivacyLevel level) {
  switch (level) {
    case PrivacyLevel.precise:
      return Icons.my_location;
    case PrivacyLevel.approximate:
      return Icons.location_searching;
    case PrivacyLevel.aggregated:
      return Icons.bar_chart;
  }
}
