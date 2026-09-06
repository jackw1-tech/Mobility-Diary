import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter/material.dart';

/// Colore con cui viene disegnato un segmento in base all'attivita'
/// riconosciuta dal backend.
///
/// I colori attivita' sono fissi (non variano con il tema) perche' devono
/// rimanere distinguibili sulla mappa indipendentemente dal brightness.
/// L'unico fallback che prima usava `ColorPalette.primary` ora usa
/// `onSurface` dal [ColorScheme] del tema corrente.
Color activityColor(String label, {required ColorScheme colorScheme}) {
  switch (label) {
    case 'WALKING':
      return const Color(0xFF1F8A4C);
    case 'RUNNING':
      return const Color(0xFFE04F5F);
    case 'BIKING':
      return const Color(0xFF2563EB);
    case 'MOVING_VEHICLE':
      return const Color(0xFF6D5DF6);
    default:
      return colorScheme.primary;
  }
}

/// Identita' stabile di un segmento: i segmenti non hanno un id proprio, quindi
/// la selezione sulla mappa si aggancia a questa chiave derivata.
String segmentKey(TripTrackSegmentState segment) {
  return '${segment.startTimestamp.toIso8601String()}|'
      '${segment.endTimestamp.toIso8601String()}|'
      '${segment.activityLabel}|'
      '${segment.distanceMeters.toStringAsFixed(1)}';
}
