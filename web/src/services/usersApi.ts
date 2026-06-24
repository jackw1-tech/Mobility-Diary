import { sendJson } from './apiClient';

export type WebUserSummary = {
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
  owner: WebUserSummary;
  trips: WebTripListItem[];
};

export type LineStringGeoJson = {
  type: 'LineString';
  coordinates: [number, number][];
};

export type WebDiarySegment = {
  kind: 'MOVE' | 'STOP';
  start_timestamp: string;
  end_timestamp: string;
  activity_label: string;
  distance_meters: number;
  path_geojson: LineStringGeoJson | null;
};

export type WebTripDashboard = {
  owner: WebUserSummary;
  trip: WebTripDetail;
  track: {
    trip_id: number;
    point_count: number;
    distance_meters: number;
    geojson: LineStringGeoJson | null;
  };
  diary: {
    trip_id: number;
    status: string;
    processed: boolean;
    segments: WebDiarySegment[];
  };
};

export function fetchUsers(): Promise<WebUserSummary[]> {
  return sendJson<WebUserSummary[]>('/web/users');
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

export function fetchTripDashboard(
  userId: string | number,
  tripId: string | number,
): Promise<WebTripDashboard> {
  return sendJson<WebTripDashboard>(`/web/users/${userId}/trips/${tripId}`);
}
