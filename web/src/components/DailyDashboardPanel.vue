<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, reactive, ref, watch } from 'vue';
import L from 'leaflet';
import type { LatLngTuple } from 'leaflet';
import {
  BarChart3,
  CalendarDays,
  Clock,
  MapPinned,
  Route as RouteIcon,
  Search,
  X,
} from 'lucide-vue-next';
import { ApiError } from '../services/apiClient';
import {
  fetchTripDashboard,
  fetchUserTrips,
  type LineStringGeoJson,
  type WebTripDashboard,
} from '../services/usersApi';
import {
  formatDateTime,
  formatDistance,
  formatDuration,
} from '../utils/formatters';
import {
  activityColor,
  activityFilterOptions,
  activityLabel,
  type DashboardSegment,
  filterSegments,
  placeFilterOptions,
  segmentSeconds,
  stopLabel,
  summarizeTrip,
} from '../utils/tripDashboard';

const props = defineProps<{
  userId: string;
  initialDay?: string;
}>();

const dashboards = ref<WebTripDashboard[]>([]);
const loading = ref(false);
const error = ref('');
const selectedDay = ref(props.initialDay || new Date().toISOString().slice(0, 10));
const mapElement = ref<HTMLElement | null>(null);
const filters = reactive({
  activities: [] as string[],
  place: '',
  from: '',
  to: '',
});
let leafletMap: ReturnType<typeof L.map> | null = null;

const day = computed(() => selectedDay.value);
const dayStartInput = computed(() => `${day.value}T00:00`);
const dayEndInput = computed(() => `${day.value}T23:59`);
const hasLocalFilters = computed(() => (
  filters.activities.length > 0 ||
  Boolean(filters.place) ||
  filters.from !== dayStartInput.value ||
  filters.to !== dayEndInput.value
));
const rawSegments = computed(() => (
  dashboards.value.flatMap((dashboard) => dashboard.diary.segments)
));
const timeWindowSegments = computed(() => (
  filterSegments(rawSegments.value, { from: filters.from, to: filters.to })
));
const visibleSegments = computed(() => filterSegments(rawSegments.value, filters));
const moveSegments = computed(() => (
  visibleSegments.value.filter((segment) => segment.kind === 'MOVE')
));
const stopSegments = computed(() => (
  visibleSegments.value.filter((segment) => segment.kind === 'STOP')
));
const activityOptions = computed(() => activityFilterOptions(timeWindowSegments.value));
const placeOptions = computed(() => placeFilterOptions(timeWindowSegments.value));
const stats = computed(() => (
  summarizeTrip(
    { started_at: `${day.value}T00:00:00.000Z`, ended_at: `${day.value}T23:59:59.000Z` },
    visibleSegments.value,
    { durationMode: 'segments' },
  )
));
const statCards = computed(() => [
  { icon: Clock, label: 'Tempo visibile', value: formatDuration(stats.value.totalDurationSeconds) },
  { icon: RouteIcon, label: 'Movimento', value: formatDuration(stats.value.movementSeconds) },
  {
    icon: MapPinned,
    label: 'Soste',
    value: `${stats.value.stopCount} · ${formatDuration(stats.value.stoppedSeconds)}`,
  },
  { icon: BarChart3, label: 'Distanza movimento', value: formatDistance(stats.value.movementDistanceMeters) },
]);
const hasVisibleMapGeometry = computed(() => (
  moveSegments.value.some((segment) => segment.path_geojson) ||
  stopSegments.value.some((segment) => segment.place?.center_geojson) ||
  (!hasLocalFilters.value && dashboards.value.some((dashboard) => dashboard.track.geojson))
));

async function loadDailyDashboard() {
  if (!props.userId || !day.value) return;
  loading.value = true;
  error.value = '';
  dashboards.value = [];
  try {
    const response = await fetchUserTrips(props.userId);
    const dayTrips = response.trips.filter((trip) => tripOverlapsDay(
      trip.started_at,
      trip.ended_at,
    ));
    dashboards.value = await Promise.all(
      dayTrips.map((trip) => fetchTripDashboard(props.userId, trip.id)),
    );
  } catch (unknownError) {
    dashboards.value = [];
    error.value = unknownError instanceof ApiError
      ? unknownError.message
      : 'Dashboard giornaliera non disponibile';
  } finally {
    loading.value = false;
  }
}

function tripOverlapsDay(startedAt: string, endedAt: string | null): boolean {
  const start = Date.parse(startedAt);
  const end = Date.parse(endedAt ?? startedAt);
  const dayStart = Date.parse(dayStartInput.value);
  const dayEnd = Date.parse(dayEndInput.value);
  return start <= dayEnd && end >= dayStart;
}

function renderMap() {
  destroyMap();
  if (!mapElement.value) return;
  const map = L.map(mapElement.value, { scrollWheelZoom: false });
  leafletMap = map;
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors',
  }).addTo(map);

  const visiblePoints: LatLngTuple[] = [];
  if (!hasLocalFilters.value) {
    for (const dashboard of dashboards.value) {
      drawLine(dashboard.track.geojson, '#111111', 3, 0.18, visiblePoints);
    }
  }
  for (const segment of moveSegments.value) {
    drawLine(
      segment.path_geojson ?? null,
      activityColor(segment.activity_label),
      6,
      0.88,
      visiblePoints,
    );
  }
  drawStopMarkers(stopSegments.value, visiblePoints);

  if (visiblePoints.length > 0) {
    map.fitBounds(L.polyline(visiblePoints).getBounds(), { padding: [28, 28] });
  } else {
    map.setView([45.4642, 9.19], 12);
  }
}

function drawLine(
  geojson: LineStringGeoJson | null,
  color: string,
  weight: number,
  opacity: number,
  visiblePoints: LatLngTuple[],
) {
  if (!geojson?.coordinates.length || !leafletMap) return;
  const points = geojson.coordinates.map(([lon, lat]) => [lat, lon] as LatLngTuple);
  visiblePoints.push(...points);
  L.polyline(points, { color, opacity, weight }).addTo(leafletMap);
}

function drawStopMarkers(segments: DashboardSegment[], visiblePoints: LatLngTuple[]) {
  if (!leafletMap) return;
  for (const segment of segments) {
    const coordinates = segment.place?.center_geojson?.coordinates;
    if (!coordinates) continue;
    const [lon, lat] = coordinates;
    const position: LatLngTuple = [lat, lon];
    visiblePoints.push(position);
    L.circleMarker(position, {
      color: '#525252',
      fillColor: '#ffffff',
      fillOpacity: 0.92,
      radius: 6,
      weight: 2,
    })
      .bindTooltip(stopTooltipContent(segment))
      .addTo(leafletMap);
  }
}

function stopTooltipContent(segment: DashboardSegment): string {
  return [
    '<div class="map-tooltip-detail">',
    `<strong>${escapeHtml(segment.place?.label || 'Sosta rilevata')}</strong>`,
    `<span>Inizio: ${escapeHtml(formatDateTime(segment.start_timestamp))}</span>`,
    `<span>Fine: ${escapeHtml(formatDateTime(segment.end_timestamp))}</span>`,
    `<span>Durata: ${escapeHtml(formatDuration(segmentSeconds(segment)))}</span>`,
    '</div>',
  ].join('');
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function destroyMap() {
  leafletMap?.remove();
  leafletMap = null;
}

function resetFilters() {
  filters.activities = [];
  filters.place = '';
  filters.from = dayStartInput.value;
  filters.to = dayEndInput.value;
}

function clampFromFilter() {
  filters.from = clampDateTimeValue(filters.from, dayStartInput.value, filters.to || dayEndInput.value);
}

function clampToFilter() {
  filters.to = clampDateTimeValue(filters.to, filters.from || dayStartInput.value, dayEndInput.value);
}

function clampDateTimeValue(value: string, min: string, max: string): string {
  let current = value || min || max;
  if (min && current < min) current = min;
  if (max && current > max) current = max;
  return current;
}

function changeDay(nextDay: string) {
  if (!nextDay || nextDay === day.value) return;
  selectedDay.value = nextDay;
}

watch(() => props.initialDay, (nextDay) => {
  if (nextDay && nextDay !== selectedDay.value) {
    selectedDay.value = nextDay;
  }
});
watch([() => props.userId, day], () => {
  resetFilters();
  void loadDailyDashboard();
}, { immediate: true });
watch(activityOptions, (options) => {
  const available = new Set(options.map((option) => option.value));
  const selected = filters.activities.filter((activity) => available.has(activity));
  if (selected.length !== filters.activities.length) {
    filters.activities = selected;
  }
});
watch(placeOptions, (options) => {
  if (filters.place && !options.some((option) => option.value === filters.place)) {
    filters.place = '';
  }
});
watch(
  [dashboards, moveSegments, stopSegments],
  () => nextTick(renderMap),
  { flush: 'post' },
);
onBeforeUnmount(destroyMap);
</script>

<template>
  <section class="daily-dashboard-section" aria-labelledby="daily-dashboard-title">
    <div class="section-heading">
      <div>
        <p class="eyebrow">Dashboard giorno</p>
        <h2 id="daily-dashboard-title">{{ day }}</h2>
        <p>{{ dashboards.length }} viaggi aggregati</p>
      </div>
      <div class="daily-heading-actions">
        <label class="day-jump-control">
          Giorno
          <input
            :value="day"
            type="date"
            @change="changeDay(($event.target as HTMLInputElement).value)"
          />
        </label>
        <button class="button-primary" type="button" :disabled="loading" @click="loadDailyDashboard">
          <Search :size="18" />
          <span>Aggiorna</span>
        </button>
      </div>
    </div>

    <section v-if="loading" class="message-panel state-panel">
      <strong>Caricamento giornata...</strong>
      <p>Aggregazione dei viaggi e dei segmenti del diario.</p>
    </section>
    <section v-else-if="error" class="message-panel state-panel error-panel">
      <strong>{{ error }}</strong>
      <button class="button-primary" type="button" @click="loadDailyDashboard">
        Riprova
      </button>
    </section>

    <div v-else class="trip-dashboard-grid">
      <form class="filters-panel detail-filters daily-filters" @submit.prevent>
        <div class="filters-grid detail-filters-grid">
          <label>
            Da
            <input
              v-model="filters.from"
              type="datetime-local"
              :min="dayStartInput"
              :max="filters.to || dayEndInput"
              @change="clampFromFilter"
            />
          </label>
          <label>
            A
            <input
              v-model="filters.to"
              type="datetime-local"
              :min="filters.from || dayStartInput"
              :max="dayEndInput"
              @change="clampToFilter"
            />
          </label>
        </div>

        <fieldset class="activity-filter-list">
          <legend>Attività</legend>
          <label
            v-for="activity in activityOptions"
            :key="activity.value"
            class="activity-filter"
          >
            <input
              v-model="filters.activities"
              type="checkbox"
              :value="activity.value"
            />
            <span class="activity-dot" :style="{ backgroundColor: activity.color }"></span>
            <span>{{ activity.label }}</span>
          </label>
          <span v-if="activityOptions.length === 0" class="muted-text">
            Nessuna attività disponibile.
          </span>
        </fieldset>

        <label>
          Luogo significativo
          <select v-model="filters.place" :disabled="placeOptions.length === 0">
            <option value="">Tutti</option>
            <option
              v-for="place in placeOptions"
              :key="place.value"
              :value="place.value"
            >
              {{ place.label }}
            </option>
          </select>
        </label>

        <div class="filters-actions">
          <button
            class="button-subtle"
            type="button"
            :disabled="!hasLocalFilters"
            @click="resetFilters"
          >
            <X :size="18" />
            <span>Pulisci</span>
          </button>
        </div>
      </form>

      <section class="map-panel" aria-label="Mappa della giornata">
        <div class="map-legend">
          <span><i class="legend-line private-line"></i>Viaggi del giorno</span>
          <span><i class="legend-dot stop-dot"></i>Sosta</span>
        </div>
        <div ref="mapElement" class="trip-map"></div>
        <div v-if="!hasVisibleMapGeometry" class="map-empty">
          Traccia non disponibile
        </div>
      </section>

      <aside class="stats-panel" aria-label="Statistiche giornaliere">
        <div v-for="card in statCards" :key="card.label" class="stat-card">
          <component :is="card.icon" :size="18" />
          <span>{{ card.label }}</span>
          <strong>{{ card.value }}</strong>
        </div>

        <div class="activity-split">
          <p class="eyebrow">Attività</p>
          <div v-if="stats.activitySplit.length === 0" class="muted-text">
            Nessun segmento di movimento.
          </div>
          <div
            v-for="activity in stats.activitySplit"
            :key="activity.label"
            class="activity-row"
          >
            <span class="activity-dot" :style="{ backgroundColor: activity.color }"></span>
            <span>{{ activity.label }}</span>
            <strong>{{ formatDuration(activity.seconds) }}</strong>
          </div>
        </div>
      </aside>

      <section class="timeline-panel" aria-labelledby="daily-timeline-title">
        <div class="section-heading compact-heading">
          <div>
            <p class="eyebrow">Diario giornaliero</p>
            <h2 id="daily-timeline-title">Timeline</h2>
          </div>
          <span class="muted-text">{{ visibleSegments.length }} segmenti</span>
        </div>

        <div v-if="visibleSegments.length === 0" class="message-panel state-panel">
          Nessun segmento corrisponde ai filtri.
        </div>
        <ol v-else class="timeline-list">
          <li
            v-for="segment in visibleSegments"
            :key="`${segment.start_timestamp}-${segment.end_timestamp}-${segment.kind}`"
            class="timeline-item"
          >
            <span
              class="timeline-marker"
              :style="{ backgroundColor: segment.kind === 'MOVE'
                ? activityColor(segment.activity_label)
                : '#8c8c8c' }"
            ></span>
            <div>
              <strong>
                {{ segment.kind === 'MOVE'
                  ? activityLabel(segment.activity_label)
                  : stopLabel(segment) }}
              </strong>
              <small>
                {{ formatDateTime(segment.start_timestamp) }} ·
                {{ formatDuration(segmentSeconds(segment)) }}
              </small>
              <span v-if="segment.kind === 'MOVE'">
                {{ formatDistance(segment.distance_meters) }}
              </span>
            </div>
          </li>
        </ol>
      </section>

      <section class="diary-table-panel" aria-labelledby="daily-table-title">
        <div class="section-heading compact-heading">
          <div>
            <p class="eyebrow">Diario tabellare</p>
            <h2 id="daily-table-title">Segmenti della giornata</h2>
          </div>
          <span class="muted-text">{{ visibleSegments.length }} righe</span>
        </div>

        <div class="data-table diary-segments-table" role="table" aria-label="Segmenti giornalieri">
          <div class="table-row diary-segment-row table-header" role="row">
            <span>Inizio</span>
            <span>Fine</span>
            <span>Durata</span>
            <span>Tipo</span>
            <span>Attività</span>
            <span>Luogo</span>
            <span>Distanza</span>
          </div>
          <div
            v-for="segment in visibleSegments"
            :key="`${segment.start_timestamp}-${segment.end_timestamp}-${segment.kind}-daily-table`"
            class="table-row diary-segment-row"
            role="row"
          >
            <span>{{ formatDateTime(segment.start_timestamp) }}</span>
            <span>{{ formatDateTime(segment.end_timestamp) }}</span>
            <span>{{ formatDuration(segmentSeconds(segment)) }}</span>
            <span>{{ segment.kind }}</span>
            <span>{{ activityLabel(segment.activity_label) }}</span>
            <span>{{ segment.place ? stopLabel(segment) : '-' }}</span>
            <span>{{ segment.kind === 'MOVE' ? formatDistance(segment.distance_meters) : '-' }}</span>
          </div>
        </div>
      </section>
    </div>
  </section>
</template>
