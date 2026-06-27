export type DashboardTrip = {
  started_at: string;
  ended_at: string | null;
};

export type DashboardLineString = {
  type: 'LineString';
  coordinates: [number, number][];
};

export type DashboardSegment = {
  kind: 'MOVE' | 'STOP';
  start_timestamp: string;
  end_timestamp: string;
  activity_label: string;
  distance_meters: number;
  path_geojson?: DashboardLineString | null;
  place?: {
    center_geojson?: { type: 'Point'; coordinates: [number, number] } | null;
    label: string;
    radius_meters: number;
  } | null;
};

const activityMeta: Record<string, { label: string; color: string }> = {
  IDLE: { label: 'Sosta', color: '#8c8c8c' },
  WALKING: { label: 'Camminata', color: '#1f8a70' },
  RUNNING: { label: 'Corsa', color: '#c43d3d' },
  BIKING: { label: 'Bici', color: '#2563eb' },
  MOVING_VEHICLE: { label: 'Veicolo', color: '#8a5cf6' },
};

export type ActivitySplit = {
  label: string;
  seconds: number;
  color: string;
};

export type TripStats = {
  totalDurationSeconds: number;
  movementSeconds: number;
  stoppedSeconds: number;
  stopCount: number;
  movementDistanceMeters: number;
  activitySplit: ActivitySplit[];
};

export type SegmentFilters = {
  activities?: string[];
  from?: string;
  to?: string;
};

export type ActivityFilterOption = {
  value: string;
  label: string;
  color: string;
};

export function isStopSegment(segment: DashboardSegment): boolean {
  return segment.kind === 'STOP';
}

export function activityLabel(value: string): string {
  return activityMeta[value]?.label ?? value;
}

export function activityColor(value: string): string {
  return activityMeta[value]?.color ?? '#000000';
}

export function segmentSeconds(segment: DashboardSegment): number {
  return secondsBetween(segment.start_timestamp, segment.end_timestamp);
}

export function orderedSegments(
  segments: DashboardSegment[],
): DashboardSegment[] {
  return [...segments].sort((left, right) => (
    Date.parse(left.start_timestamp) - Date.parse(right.start_timestamp)
  ));
}

export function activityFilterOptions(
  segments: DashboardSegment[],
): ActivityFilterOption[] {
  const options = new Map<string, ActivityFilterOption>();
  for (const segment of orderedSegments(segments)) {
    options.set(segment.activity_label, {
      value: segment.activity_label,
      label: activityLabel(segment.activity_label),
      color: activityColor(segment.activity_label),
    });
  }
  return [...options.values()];
}

export function filterSegments(
  segments: DashboardSegment[],
  filters: SegmentFilters,
): DashboardSegment[] {
  const activities = new Set(filters.activities ?? []);
  const from = filterTimestamp(filters.from);
  const to = filterTimestamp(filters.to);

  return orderedSegments(segments).filter((segment) => {
    const startsAt = Date.parse(segment.start_timestamp);
    const endsAt = Date.parse(segment.end_timestamp);
    return (
      (activities.size === 0 || activities.has(segment.activity_label)) &&
      (from == null || endsAt >= from) &&
      (to == null || startsAt <= to)
    );
  });
}

export function summarizeTrip(
  trip: DashboardTrip,
  segments: DashboardSegment[],
  options: { durationMode?: 'trip' | 'segments' } = {},
): TripStats {
  const ordered = orderedSegments(segments);
  const split = new Map<string, ActivitySplit>();
  const segmentDuration = ordered.reduce(
    (total, segment) => total + segmentSeconds(segment),
    0,
  );
  const stats: TripStats = {
    totalDurationSeconds: options.durationMode === 'segments'
      ? segmentDuration
      : secondsBetween(trip.started_at, trip.ended_at ?? new Date().toISOString()),
    movementSeconds: 0,
    stoppedSeconds: 0,
    stopCount: 0,
    movementDistanceMeters: 0,
    activitySplit: [],
  };

  for (const segment of ordered) {
    const seconds = segmentSeconds(segment);
    if (isStopSegment(segment)) {
      stats.stoppedSeconds += seconds;
      stats.stopCount += 1;
      continue;
    }

    stats.movementSeconds += seconds;
    stats.movementDistanceMeters += segment.distance_meters;

    const current = split.get(segment.activity_label) ?? {
      label: activityLabel(segment.activity_label),
      seconds: 0,
      color: activityColor(segment.activity_label),
    };
    current.seconds += seconds;
    split.set(segment.activity_label, current);
  }

  stats.activitySplit = [...split.values()].sort((left, right) => (
    right.seconds - left.seconds
  ));
  return stats;
}

export function stopLabel(segment: DashboardSegment): string {
  return segment.place?.label || 'Sosta rilevata';
}

function secondsBetween(start: string, end: string): number {
  return Math.max(0, (Date.parse(end) - Date.parse(start)) / 1000);
}

function filterTimestamp(value?: string): number | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}
