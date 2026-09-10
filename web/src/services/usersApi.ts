import { sendJson } from './apiClient';

export type WebUserOverview = {
  id: number;
  email: string;
  first_name: string;
  last_name: string;
  is_active: boolean;
  trip_count: number;
  processed_trip_count: number;
  latest_trip_started_at: string | null;
  total_distance_meters: number;
};

export type WebTripStatus = 'OPEN' | 'CLOSED' | 'PROCESSED';

export type WebTripListItem = {
  id: number;
  started_at: string;
  ended_at: string | null;
  status: WebTripStatus;
  distance_meters: number | null;
  processed: boolean;
  has_track: boolean;
};

export type WebTripDetail = Omit<WebTripListItem, 'has_track'>;

export type WebTripFilters = {
  from?: string;
  to?: string;
  status?: WebTripStatus | '';
  processed?: 'true' | 'false' | '';
  has_track?: 'true' | 'false' | '';
};

export type WebUserTripsResponse = {
  owner: WebUserOverview;
  trips: WebTripListItem[];
};

export type LineStringGeoJson = {
  type: 'LineString';
  coordinates: [number, number][];
};

export type PointGeoJson = {
  type: 'Point';
  coordinates: [number, number];
};

export type PrivacyLevel = 'precise' | 'approximate' | 'aggregated';

export type WebDiaryPlace = {
  center_geojson: PointGeoJson | null;
  label: string;
  radius_meters: number;
};

export type WebDiarySegment = {
  kind: 'MOVE' | 'STOP';
  start_timestamp: string;
  end_timestamp: string;
  activity_label: string;
  distance_meters: number;
  path_geojson: LineStringGeoJson | null;
  place?: WebDiaryPlace | null;
};

export type WebTrack = {
  trip_id: number;
  point_count: number;
  distance_meters: number;
  geojson: LineStringGeoJson | null;
};

export type WebDiary = {
  trip_id: number;
  status: string;
  processed: boolean;
  segments: WebDiarySegment[];
};

export type WebSignificantPlace = {
  center_geojson: PointGeoJson | null;
  label: string;
  radius_meters: number;
  dwell_seconds: number;
};

export type WebPrivacyMetrics = {
  privacy_perturbation: {
    mean_meters: number;
    max_meters: number;
    sample_count: number;
  };
  quality_of_service: {
    relative_distance_error: number;
    private_distance_meters: number;
    privacy_aware_distance_meters: number;
  };
};

export type WebPrivacyAware = {
  level: PrivacyLevel;
  default_level: PrivacyLevel;
  track: WebTrack;
  diary: WebDiary;
  significant_places: WebSignificantPlace[];
  metrics: WebPrivacyMetrics;
};

export type WebSensorGap = {
  start_timestamp: string;
  end_timestamp: string;
  gap_seconds: number;
};

export type WebTripDashboard = {
  owner: WebUserOverview;
  trip: WebTripDetail;
  track: WebTrack;
  diary: WebDiary;
  privacy_aware: WebPrivacyAware;
  sensor_gaps: WebSensorGap[];
};

export type WebAxisStats = {
  mean: number;
  std: number;
};

export type WebMotionStats = {
  activity_label: string;
  sample_count: number;
  accel_x: WebAxisStats;
  accel_y: WebAxisStats;
  accel_z: WebAxisStats;
  gyro_x: WebAxisStats;
  gyro_y: WebAxisStats;
  gyro_z: WebAxisStats;
};

export function fetchUsers(): Promise<WebUserOverview[]> {
  return sendJson<WebUserOverview[]>('/web/users');
}

export function fetchUserTrips(
  userId: string | number,
  filters: WebTripFilters = {},
): Promise<WebUserTripsResponse> {
  const query = new URLSearchParams();
  Object.entries(filters).forEach(([key, value]) => {
    if (value) query.set(key, value);
  });
  const suffix = query.size > 0 ? `?${query.toString()}` : '';
  return sendJson<WebUserTripsResponse>(`/web/users/${userId}/trips${suffix}`);
}

export function fetchUserMotionStats(
  userId: string | number,
): Promise<WebMotionStats[]> {
  return sendJson<WebMotionStats[]>(`/web/users/${userId}/motion-stats`);
}

export function fetchTripDashboard(
  userId: string | number,
  tripId: string | number,
  level?: PrivacyLevel,
): Promise<WebTripDashboard> {
  const suffix = level ? `?level=${level}` : '';
  return sendJson<WebTripDashboard>(`/web/users/${userId}/trips/${tripId}${suffix}`);
}
