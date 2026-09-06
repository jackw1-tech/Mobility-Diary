import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/ui/pages/home_acquisition_rebuild.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home rebuilds when a live acquisition starts', () {
    final idle = AcquisitionCubitState.fromSnapshot(
      AcquisitionSnapshot.idle(),
    );
    final tracking = AcquisitionCubitState.fromSnapshot(
      AcquisitionSnapshot(
        isTracking: true,
        trackingState: TrackingState.stationary,
        latestSigma: 0,
        latestSpeedMetersPerSecond: 0,
        lastTransition: null,
        updatedAt: DateTime.utc(2026, 9, 4, 10),
      ),
    );

    expect(shouldRebuildHomeForAcquisition(idle, tracking), isTrue);
  });

  test('home rebuilds when live metrics change', () {
    final previous = _trackingState();
    final current = AcquisitionCubitState.fromSnapshot(
      previous.snapshot.copyWith(
        latestSigma: 1.25,
        latestSpeedMetersPerSecond: 2,
      ),
    );

    expect(shouldRebuildHomeForAcquisition(previous, current), isTrue);
  });

  test('home rebuilds when a metric updates to the same value', () {
    final previous = _trackingState();
    final current = AcquisitionCubitState.fromSnapshot(
      previous.snapshot.copyWith(
        latestSigmaAt: DateTime.utc(2026, 9, 4, 10, 0, 2),
      ),
    );

    expect(shouldRebuildHomeForAcquisition(previous, current), isTrue);
  });

  test('home rebuilds while a start or stop action is in progress', () {
    final idle = AcquisitionCubitState.fromSnapshot(AcquisitionSnapshot.idle());

    expect(
      shouldRebuildHomeForAcquisition(
        idle,
        idle.copyWith(isTransitioning: true),
      ),
      isTrue,
    );
  });
}

AcquisitionCubitState _trackingState() {
  return AcquisitionCubitState.fromSnapshot(
    AcquisitionSnapshot(
      isTracking: true,
      trackingState: TrackingState.stationary,
      latestSigma: 0,
      latestSpeedMetersPerSecond: 0,
      lastTransition: null,
      updatedAt: DateTime.utc(2026, 9, 4, 10),
    ),
  );
}
