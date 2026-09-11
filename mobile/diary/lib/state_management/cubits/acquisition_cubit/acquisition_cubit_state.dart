import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:latlong2/latlong.dart';

enum AcquisitionCubitStatus { idle, tracking }

class AcquisitionCubitState {
  final AcquisitionCubitStatus status;
  final AcquisitionSnapshot snapshot;
  final AcquisitionSyncSnapshot syncSnapshot;
  final String? errorMessage;
  final bool isTransitioning;

  final List<LatLng> routePoints;
  final int? completedReplayTripId;

  const AcquisitionCubitState({
    required this.status,
    required this.snapshot,
    this.syncSnapshot = const AcquisitionSyncSnapshot.none(),
    this.errorMessage,
    this.isTransitioning = false,
    this.routePoints = const [],
    this.completedReplayTripId,
  });

  factory AcquisitionCubitState.initial() {
    return AcquisitionCubitState.fromSnapshot(AcquisitionSnapshot.idle());
  }

  factory AcquisitionCubitState.fromSnapshot(
    AcquisitionSnapshot snapshot, {
    AcquisitionSyncSnapshot syncSnapshot = const AcquisitionSyncSnapshot.none(),
    String? errorMessage,
    bool isTransitioning = false,
    List<LatLng> routePoints = const [],
    int? completedReplayTripId,
  }) {
    return AcquisitionCubitState(
      status: snapshot.isTracking
          ? AcquisitionCubitStatus.tracking
          : AcquisitionCubitStatus.idle,
      snapshot: snapshot,
      syncSnapshot: syncSnapshot,
      errorMessage: errorMessage,
      isTransitioning: isTransitioning,
      routePoints: routePoints,
      completedReplayTripId: completedReplayTripId,
    );
  }

  AcquisitionCubitState copyWith({
    AcquisitionCubitStatus? status,
    AcquisitionSnapshot? snapshot,
    AcquisitionSyncSnapshot? syncSnapshot,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isTransitioning,
    List<LatLng>? routePoints,
    int? completedReplayTripId,
    bool clearCompletedReplayTripId = false,
  }) {
    return AcquisitionCubitState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      syncSnapshot: syncSnapshot ?? this.syncSnapshot,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      isTransitioning: isTransitioning ?? this.isTransitioning,
      routePoints: routePoints ?? this.routePoints,
      completedReplayTripId: clearCompletedReplayTripId
          ? null
          : completedReplayTripId ?? this.completedReplayTripId,
    );
  }

  bool get isTracking => status == AcquisitionCubitStatus.tracking;

  bool get isReplay => snapshot.isReplay;

  LatLng? get latestPosition {
    if (!snapshot.hasPosition) return null;
    return LatLng(snapshot.latitude!, snapshot.longitude!);
  }

  TrackingState get trackingState => snapshot.trackingState;

  double get latestSigma => snapshot.latestSigma;

  double get latestSpeedMetersPerSecond {
    return snapshot.latestSpeedMetersPerSecond;
  }
}
