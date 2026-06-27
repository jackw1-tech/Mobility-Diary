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

export function isStopLikeSegment(segment: DashboardSegment): boolean {
  return segment.kind === 'STOP' || segment.activity_label === 'IDLE';
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

export function presentableSegments(
  segments: DashboardSegment[],
): DashboardSegment[] {
  const ordered = [...segments].sort((left, right) => (
    Date.parse(left.start_timestamp) - Date.parse(right.start_timestamp)
  ));
  const projected: DashboardSegment[] = [];
  let pendingStop: DashboardSegment | null = null;

  for (const segment of ordered) {
    if (isStopLikeSegment(segment)) {
      const stopProjection = asStopSegment(segment);
      if (pendingStop == null) {
        pendingStop = stopProjection;
        continue;
      }
      if (Date.parse(stopProjection.start_timestamp) <= Date.parse(pendingStop.end_timestamp)) {
        pendingStop = {
          ...pendingStop,
          end_timestamp: Date.parse(stopProjection.end_timestamp) > Date.parse(pendingStop.end_timestamp)
            ? stopProjection.end_timestamp
            : pendingStop.end_timestamp,
        };
        continue;
      }
      projected.push(pendingStop);
      pendingStop = stopProjection;
      continue;
    }

    if (pendingStop != null) {
      projected.push(pendingStop);
      pendingStop = null;
    }
    projected.push(segment);
  }

  if (pendingStop != null) {
    projected.push(pendingStop);
  }

  return projected;
}

export function activityFilterOptions(
  segments: DashboardSegment[],
): ActivityFilterOption[] {
  const options = new Map<string, ActivityFilterOption>();
  for (const segment of presentableSegments(segments)) {
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
  const presentable = presentableSegments(segments);
  const activities = new Set(filters.activities ?? []);
  const from = filterTimestamp(filters.from);
  const to = filterTimestamp(filters.to);

  return presentable.filter((segment) => {
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
  const presentable = presentableSegments(segments);
  const split = new Map<string, ActivitySplit>();
  const segmentDuration = presentable.reduce(
    (total, segment) => total + segmentSeconds(segment),
    0,
  );
  const stats: TripStats = {
    totalDurationSeconds: options.durationMode === 'segments'
      ? segmentDuration
      : secondsBetween(trip.started_at, trip.ended_at ?? new Date().toISOString()),
    movementSeconds: 0,
    stoppedSeconds: 0,
    movementDistanceMeters: 0,
    activitySplit: [],
  };

  for (const segment of presentable) {
    const seconds = segmentSeconds(segment);
    if (isStopLikeSegment(segment)) {
      stats.stoppedSeconds += seconds;
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

function secondsBetween(start: string, end: string): number {
  return Math.max(0, (Date.parse(end) - Date.parse(start)) / 1000);
}

function filterTimestamp(value?: string): number | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function asStopSegment(segment: DashboardSegment): DashboardSegment {
  return {
    ...segment,
    kind: 'STOP',
    activity_label: 'IDLE',
    distance_meters: 0,
    path_geojson: null,
  };
}
