import 'package:diary/model/entities/places/place_enums.dart';

class PlaceMiningStatus {
  final PlaceMiningState miningState;
  final DateTime? requestedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String errorMessage;
  final bool rerunRequested;

  const PlaceMiningStatus({
    required PlaceMiningState status,
    this.requestedAt,
    this.startedAt,
    this.finishedAt,
    this.errorMessage = '',
    this.rerunRequested = false,
  }) : miningState = status;

  String get status => miningState.wireName;

  bool get isActionable => miningState == PlaceMiningState.succeeded;
  bool get isPending => miningState == PlaceMiningState.pending;
  bool get isRunning => miningState == PlaceMiningState.running;
  bool get isFailed => miningState == PlaceMiningState.failed;
  bool get isInProgress => isPending || isRunning;
}

class PlaceReviewBlockedException implements Exception {
  final String message;
  final PlaceMiningStatus placeStatus;

  const PlaceReviewBlockedException(
    this.message, {
    required this.placeStatus,
  });

  @override
  String toString() => message;
}
