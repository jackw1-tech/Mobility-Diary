import 'package:diary/network/dto/place_review_dto.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:flutter/material.dart';

/// Helper di presentazione condivisi fra la lista e il dettaglio dei luoghi.

Color placeStateColor(PlaceReviewDto place) {
  switch (place.state) {
    case 'CONFIRMED':
      return ColorPalette.success;
    case 'REJECTED':
      return ColorPalette.error;
    default:
      return ColorPalette.warning;
  }
}

IconData placeStateIcon(PlaceReviewDto place) {
  switch (place.state) {
    case 'CONFIRMED':
      return Icons.verified_outlined;
    case 'REJECTED':
      return Icons.block;
    default:
      return Icons.help_outline;
  }
}

String placeStateLabel(String state) {
  switch (state) {
    case 'CONFIRMED':
      return 'Confermato';
    case 'REJECTED':
      return 'Rifiutato';
    default:
      return 'Candidato';
  }
}

/// "3 visite · 2 giorni": il contesto che spiega l'evidenza del luogo.
String placeEvidenceSummary(PlaceReviewDto place) {
  final visits =
      place.visitCount == 1 ? '1 visita' : '${place.visitCount} visite';
  final days =
      place.distinctDays == 1 ? '1 giorno' : '${place.distinctDays} giorni';
  return '$visits · $days';
}

/// Frase che spiega perche' un luogo e' stato proposto o confermato.
String placeWhyProposed(PlaceReviewDto place) {
  final summary = placeEvidenceSummary(place);
  return place.isConfirmed
      ? 'Confermato come luogo abituale ($summary).'
      : 'Proposto come possibile luogo abituale ($summary).';
}

/// Categorie chiuse per l'etichetta manuale (allineate al backend).
const List<String> placeCategories = [
  'casa',
  'universita',
  'lavoro',
  'palestra',
  'altro',
];

String placeCategoryLabel(String category) {
  if (category.isEmpty) return '';
  return category[0].toUpperCase() + category.substring(1);
}
