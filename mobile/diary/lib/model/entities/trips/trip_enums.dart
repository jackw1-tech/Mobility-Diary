enum TripStatus {
  processed('PROCESSED'),
  processing('PROCESSING'),
  failed('FAILED'),
  unknown('');

  final String wireName;

  const TripStatus(this.wireName);

  static TripStatus fromWire(String value) {
    for (final status in TripStatus.values) {
      if (status.wireName == value) return status;
    }
    return TripStatus.unknown;
  }
}

enum TripDiaryStatus {
  closed('CLOSED'),
  processed('PROCESSED'),
  pending('PENDING'),
  failed('FAILED'),
  unknown('');

  final String wireName;

  const TripDiaryStatus(this.wireName);

  static TripDiaryStatus fromWire(String value) {
    for (final status in TripDiaryStatus.values) {
      if (status.wireName == value) return status;
    }
    return TripDiaryStatus.unknown;
  }
}

enum TripDiarySegmentKind {
  move('MOVE'),
  stop('STOP'),
  unknown('');

  final String wireName;

  const TripDiarySegmentKind(this.wireName);

  static TripDiarySegmentKind fromWire(String value) {
    for (final kind in TripDiarySegmentKind.values) {
      if (kind.wireName == value) return kind;
    }
    return TripDiarySegmentKind.unknown;
  }
}

enum MobilityActivity {
  walking('WALKING'),
  running('RUNNING'),
  biking('BIKING'),
  movingVehicle('MOVING_VEHICLE'),
  idle('IDLE'),
  unknown('');

  final String wireName;

  const MobilityActivity(this.wireName);

  static MobilityActivity fromWire(String value) {
    for (final activity in MobilityActivity.values) {
      if (activity.wireName == value) return activity;
    }
    return MobilityActivity.unknown;
  }
}
