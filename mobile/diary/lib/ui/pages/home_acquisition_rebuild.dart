import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';

bool shouldRebuildHomeForAcquisition(
  AcquisitionCubitState previous,
  AcquisitionCubitState current,
) {
  return previous.isTracking != current.isTracking ||
      previous.isTransitioning != current.isTransitioning ||
      previous.trackingState != current.trackingState ||
      previous.latestSigma != current.latestSigma ||
      previous.snapshot.latestSigmaAt != current.snapshot.latestSigmaAt ||
      previous.latestSpeedMetersPerSecond !=
          current.latestSpeedMetersPerSecond ||
      previous.snapshot.latestSpeedAt != current.snapshot.latestSpeedAt ||
      previous.snapshot.replaySecondsRemaining !=
          current.snapshot.replaySecondsRemaining;
}
