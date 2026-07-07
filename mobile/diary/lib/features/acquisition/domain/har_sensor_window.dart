class HarSensorSample {
  final DateTime timestamp;
  final double accX;
  final double accY;
  final double accZ;
  final double gyrX;
  final double gyrY;
  final double gyrZ;

  const HarSensorSample({
    required this.timestamp,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyrX,
    required this.gyrY,
    required this.gyrZ,
  });

  List<double> get channels {
    return [
      accX,
      accY,
      accZ,
      gyrX,
      gyrY,
      gyrZ,
    ];
  }
}

class HarSensorWindow {
  static const int targetSamplingHz = 100;
  static const Duration targetDuration = Duration(seconds: 5);
  static const int targetSampleCount = 500;

  static const List<String> channelNames = [
    'Acc_x',
    'Acc_y',
    'Acc_z',
    'Gyr_x',
    'Gyr_y',
    'Gyr_z',
  ];

  final DateTime startedAt;
  final DateTime endedAt;
  final int accelerometerHz;
  final int gyroscopeHz;
  final int magnetometerHz;
  final List<HarSensorSample> samples;

  const HarSensorWindow({
    required this.startedAt,
    required this.endedAt,
    required this.accelerometerHz,
    required this.gyroscopeHz,
    required this.magnetometerHz,
    required this.samples,
  });

  int get samplingHz => accelerometerHz;

  int get sampleCount => samples.length;

  int get channelCount => channelNames.length;

  bool get hasTargetSamplingRate {
    return accelerometerHz == targetSamplingHz &&
        gyroscopeHz == targetSamplingHz;
  }

  bool get hasTargetShape {
    return modelInputMatrix.length == targetSampleCount &&
        modelInputMatrix.every((row) => row.length == channelCount);
  }

  bool get hasCompleteInertialData {
    return gyroscopeHz > 0;
  }

  List<List<double>> get matrix {
    return samples.map((sample) => sample.channels).toList(growable: false);
  }

  List<List<double>> get modelInputMatrix {
    if (samples.isEmpty) {
      return List<List<double>>.generate(
        targetSampleCount,
        (_) => List<double>.filled(channelCount, 0),
        growable: false,
      );
    }

    if (samples.length == targetSampleCount) {
      return matrix;
    }

    if (samples.length == 1) {
      final channels = samples.single.channels;
      return List<List<double>>.generate(
        targetSampleCount,
        (_) => List<double>.from(channels),
        growable: false,
      );
    }

    final lastSourceIndex = samples.length - 1;
    const lastTargetIndex = targetSampleCount - 1;

    return List<List<double>>.generate(
      targetSampleCount,
      (targetIndex) {
        final sourcePosition =
            (targetIndex * lastSourceIndex) / lastTargetIndex;
        final lowerIndex = sourcePosition.floor();
        final upperIndex = sourcePosition.ceil();

        if (lowerIndex == upperIndex) {
          return samples[lowerIndex].channels;
        }

        final ratio = sourcePosition - lowerIndex;
        final lowerChannels = samples[lowerIndex].channels;
        final upperChannels = samples[upperIndex].channels;

        return List<double>.generate(
          channelCount,
          (channelIndex) {
            final lowerValue = lowerChannels[channelIndex];
            final upperValue = upperChannels[channelIndex];
            return lowerValue + ((upperValue - lowerValue) * ratio);
          },
          growable: false,
        );
      },
      growable: false,
    );
  }
}
