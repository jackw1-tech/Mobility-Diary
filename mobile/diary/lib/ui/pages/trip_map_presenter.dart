import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter/material.dart';

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

String segmentKey(TripTrackSegmentState segment) {
  return '${segment.startTimestamp.toIso8601String()}|'
      '${segment.endTimestamp.toIso8601String()}|'
      '${segment.activityLabel}|'
      '${segment.distanceMeters.toStringAsFixed(1)}';
}
