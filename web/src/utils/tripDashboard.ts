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
    if (segment.kind !== 'MOVE') continue;
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
  if (from != null && to != null && from > to) return [];

  return orderedSegments(segments).flatMap((segment) => {
    const startsAt = Date.parse(segment.start_timestamp);
    const endsAt = Date.parse(segment.end_timestamp);
    if (activities.size > 0 && !activities.has(segment.activity_label)) return [];
    if (from != null && endsAt <= from) return [];
    if (to != null && startsAt >= to) return [];

    return [clipSegmentToWindow(segment, from, to)];
  });
}

export function calculateTripStats(
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

function clipSegmentToWindow(
  segment: DashboardSegment,
  from: number | null,
  to: number | null,
): DashboardSegment {
  const startsAt = Date.parse(segment.start_timestamp);
  const endsAt = Date.parse(segment.end_timestamp);
  const clippedStart = from == null ? startsAt : Math.max(startsAt, from);
  const clippedEnd = to == null ? endsAt : Math.min(endsAt, to);
  if (clippedStart === startsAt && clippedEnd === endsAt) return segment;
  const originalDuration = Math.max(0, endsAt - startsAt);
  const startFraction = originalDuration === 0
    ? 0
    : (clippedStart - startsAt) / originalDuration;
  const endFraction = originalDuration === 0
    ? 1
    : (clippedEnd - startsAt) / originalDuration;

  return {
    ...segment,
    start_timestamp: new Date(clippedStart).toISOString(),
    end_timestamp: new Date(clippedEnd).toISOString(),
    distance_meters: proratedDistance(segment, startsAt, endsAt, clippedStart, clippedEnd),
    path_geojson: segment.kind === 'MOVE'
      ? clipLineString(segment.path_geojson, startFraction, endFraction)
      : segment.path_geojson,
  };
}

function clipLineString(
  line: DashboardLineString | null | undefined,
  startFraction: number,
  endFraction: number,
): DashboardLineString | null | undefined {
  if (!line || line.coordinates.length < 2) return line;
  const start = clampFraction(startFraction);
  const end = clampFraction(endFraction);
  if (start <= 0 && end >= 1) return line;
  if (start >= end) return null;

  const maxIndex = line.coordinates.length - 1;
  const startPosition = start * maxIndex;
  const endPosition = end * maxIndex;
  const coordinates: [number, number][] = [
    interpolateCoordinate(line.coordinates, startPosition),
  ];

  for (
    let index = Math.floor(startPosition) + 1;
    index <= Math.floor(endPosition);
    index += 1
  ) {
    if (index > 0 && index < maxIndex) {
      coordinates.push(line.coordinates[index]);
    }
  }

  coordinates.push(interpolateCoordinate(line.coordinates, endPosition));
  return {
    ...line,
    coordinates: dedupeAdjacentCoordinates(coordinates),
  };
}

function interpolateCoordinate(
  coordinates: [number, number][],
  position: number,
): [number, number] {
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return coordinates[lower];
  const fraction = position - lower;
  const [leftLon, leftLat] = coordinates[lower];
  const [rightLon, rightLat] = coordinates[upper];
  return [
    leftLon + (rightLon - leftLon) * fraction,
    leftLat + (rightLat - leftLat) * fraction,
  ];
}

function dedupeAdjacentCoordinates(
  coordinates: [number, number][],
): [number, number][] {
  return coordinates.filter((coordinate, index) => (
    index === 0 ||
    coordinate[0] !== coordinates[index - 1][0] ||
    coordinate[1] !== coordinates[index - 1][1]
  ));
}

function clampFraction(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(1, Math.max(0, value));
}

function proratedDistance(
  segment: DashboardSegment,
  startsAt: number,
  endsAt: number,
  clippedStart: number,
  clippedEnd: number,
): number {
  if (segment.kind !== 'MOVE') return segment.distance_meters;
  const originalDuration = endsAt - startsAt;
  if (originalDuration <= 0) return 0;
  const visibleDuration = Math.max(0, clippedEnd - clippedStart);
  return segment.distance_meters * (visibleDuration / originalDuration);
}

function filterTimestamp(value?: string): number | null {
  if (!value) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}
