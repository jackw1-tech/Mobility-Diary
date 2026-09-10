import 'package:diary/model/entities/places/place_mining_status.dart';
import 'package:diary/model/entities/places/place_review.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:flutter/material.dart';

/// Helper di presentazione condivisi fra la lista e il dettaglio dei luoghi.

Color placeStateColor(PlaceReview place, {required SemanticColors sem}) {
  switch (place.state) {
    case 'CONFIRMED':
      return sem.success;
    case 'REJECTED':
      return sem.error;
    default:
      return sem.warning;
  }
}

IconData placeStateIcon(PlaceReview place) {
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
String placeEvidenceText(PlaceReview place) {
  final visits = place.visitCount == 1
      ? '1 visita'
      : '${place.visitCount} visite';
  final days = place.distinctDays == 1
      ? '1 giorno'
      : '${place.distinctDays} giorni';
  return '$visits · $days';
}

/// Frase che spiega perche' un luogo e' stato proposto o confermato.
String placeWhyProposed(PlaceReview place) {
  final evidenceText = placeEvidenceText(place);
  return place.isConfirmed
      ? 'Confermato come luogo abituale ($evidenceText).'
      : 'Proposto come possibile luogo abituale ($evidenceText).';
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

String placeMiningStatusTitle(PlaceMiningStatus status) {
  if (status.isRunning) return 'Analisi dei luoghi in corso';
  if (status.isPending) return 'Analisi dei luoghi in attesa';
  if (status.isFailed) return 'Analisi dei luoghi non completata';
  return 'Luoghi aggiornati';
}

String placeMiningStatusMessage(PlaceMiningStatus status) {
  if (status.isRunning) {
    return 'Puoi leggere l\'ultimo snapshot salvato, ma le azioni di review restano bloccate finche\' il ricalcolo non finisce.';
  }
  if (status.isPending) {
    return 'Il ricalcolo dei luoghi e\' stato richiesto. Puoi aggiornare manualmente questa schermata per verificare quando sara\' pronto.';
  }
  if (status.isFailed) {
    final suffix = status.errorMessage.isEmpty
        ? ''
        : ' Dettaglio: ${status.errorMessage}.';
    return 'L\'ultimo ricalcolo non e\' andato a buon fine e la review resta bloccata finche\' non verra\' eseguita una nuova analisi.$suffix';
  }
  return '';
}
