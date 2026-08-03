import 'package:diary/model/entities/trips/trip_enums.dart';

class TripListItem {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final TripStatus tripStatus;
  final double? distanceMeters;
  final String note;
  final bool hasTrack;
  final bool isReloadable;
  final bool isDerived;
  final bool canDelete;
  final bool canToggleReloadable;
  final bool canEditNote;

  const TripListItem({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required TripStatus status,
    required this.distanceMeters,
    this.note = '',
    required this.hasTrack,
    this.isReloadable = false,
    this.isDerived = false,
    this.canDelete = false,
    this.canToggleReloadable = false,
    this.canEditNote = false,
  }) : tripStatus = status;

  String get status => tripStatus.wireName;
}
