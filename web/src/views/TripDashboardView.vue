<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { RouterLink, useRoute } from 'vue-router';
import L from 'leaflet';
import type { LatLngTuple } from 'leaflet';
import {
  ArrowLeft,
  BarChart3,
  Clock,
  MapPinned,
  Route as RouteIcon,
  X,
} from 'lucide-vue-next';
import { ApiError } from '../services/apiClient';
import {
  fetchTripDashboard,
  type LineStringGeoJson,
  type PrivacyLevel,
  type WebTripDashboard,
} from '../services/usersApi';
import {
  displayName,
  formatDateTime,
  formatDateTimeInput,
  formatDistance,
  formatDuration,
  formatTripStatus,
} from '../utils/formatters';
import {
  activityColor,
  activityFilterOptions,
  activityLabel,
  type DashboardSegment,
  filterSegments,
  placeFilterOptions,
  stopLabel,
  segmentSeconds,
  summarizeTrip,
} from '../utils/tripDashboard';
import {
  isProtectedLevel,
  privacyLevelLabel,
  privacyLevelOptions,
  privacyMetricCards,
} from '../utils/privacyDashboard';

const route = useRoute();
const dashboard = ref<WebTripDashboard | null>(null);
const loading = ref(false);
const privacyLoading = ref(false);
const error = ref('');
const mapElement = ref<HTMLElement | null>(null);
const visibleMapLayer = ref<'private' | 'privacy-aware' | 'both'>('both');
const filters = reactive({
  activities: [] as string[],
  place: '',
  from: '',
  to: '',
});
let leafletMap: ReturnType<typeof L.map> | null = null;

const userId = computed(() => route.params.userId?.toString() ?? '');
const tripId = computed(() => route.params.tripId?.toString() ?? '');
const ownerName = computed(() => {
  const owner = dashboard.value?.owner;
  if (!owner) return `Utente #${userId.value}`;
  return displayName(owner.first_name, owner.last_name, owner.email);
});
const moveSegments = computed(() => (
  visibleSegments.value.filter((segment) => segment.kind === 'MOVE')
));
const stopSegments = computed(() => (
  visibleSegments.value.filter((segment) => segment.kind === 'STOP')
));
const activityOptions = computed(() => (
  activityFilterOptions(timeWindowSegments.value)
));
const placeOptions = computed(() => (
  placeFilterOptions(timeWindowSegments.value)
));
const hasActivityFilters = computed(() => filters.activities.length > 0);
const hasPlaceFilter = computed(() => Boolean(filters.place));
const hasTimeWindowFilter = computed(() => (
  filters.from !== tripStartInput.value ||
  filters.to !== tripEndInput.value
));
const hasLocalFilters = computed(() => (
  hasActivityFilters.value || hasPlaceFilter.value || hasTimeWindowFilter.value
));
const showFullTripGhost = computed(() => (
  hasActivityFilters.value && !hasTimeWindowFilter.value
));
const timeWindowSegments = computed(() => (
  filterSegments(dashboard.value?.diary.segments ?? [], {
    from: filters.from,
    to: filters.to,
  })
));
const visibleSegments = computed(() => (
  filterSegments(dashboard.value?.diary.segments ?? [], filters)
));
const tripStartInput = computed(() => formatDateTimeInput(dashboard.value?.trip.started_at));
const tripEndInput = computed(() => formatDateTimeInput(dashboard.value?.trip.ended_at));
const hasVisibleMapGeometry = computed(() => Boolean(
  (!hasLocalFilters.value && dashboard.value?.track.geojson) ||
  moveSegments.value.some((segment) => segment.path_geojson) ||
  stopSegments.value.some((segment) => segment.place?.center_geojson) ||
  visiblePrivacyStops.value.some((segment) => segment.place?.center_geojson),
));
const visiblePrivacySegments = computed(() => {
  if (!dashboard.value) return [];
  return filterSegments(dashboard.value.privacy_aware.diary.segments, filters);
});
const visiblePrivacyMoves = computed(() => (
  visiblePrivacySegments.value.filter((segment) => segment.kind === 'MOVE')
));
const visiblePrivacyStops = computed(() => (
  visiblePrivacySegments.value.filter((segment) => segment.kind === 'STOP')
));
const hasPrivateLayer = computed(() => (
  visibleMapLayer.value === 'private' || visibleMapLayer.value === 'both'
));
const hasPrivacyAwareLayer = computed(() => (
  visibleMapLayer.value === 'privacy-aware' || visibleMapLayer.value === 'both'
));
const activeTimelineSegments = computed(() => (
  hasPrivacyAwareLayer.value ? visiblePrivacySegments.value : visibleSegments.value
));
const activeTimelineLabel = computed(() => (
  hasPrivacyAwareLayer.value
    ? `Privacy-aware · ${privacyLevelLabel(dashboard.value?.privacy_aware.level ?? 'precise')}`
    : 'Privata'
));
const stats = computed(() => (
  dashboard.value
    ? summarizeTrip(dashboard.value.trip, activeTimelineSegments.value, {
      durationMode: hasLocalFilters.value ? 'segments' : 'trip',
    })
    : null
));
const statCards = computed(() => {
  if (!stats.value) return [];
  return [
    { icon: Clock, label: 'Durata totale', value: formatDuration(stats.value.totalDurationSeconds) },
    { icon: RouteIcon, label: 'Movimento', value: formatDuration(stats.value.movementSeconds) },
    {
      icon: MapPinned,
      label: 'Soste',
      value: `${stats.value.stopCount} · ${formatDuration(stats.value.stoppedSeconds)}`,
    },
    { icon: BarChart3, label: 'Distanza movimento', value: formatDistance(stats.value.movementDistanceMeters) },
  ];
});
const privacyAware = computed(() => dashboard.value?.privacy_aware ?? null);
const privacyPlaces = computed(() => privacyAware.value?.significant_places ?? []);
const visiblePrivacyPlaces = computed(() => (
  hasLocalFilters.value ? [] : privacyPlaces.value
));
const privacyMetricList = computed(() => (
  privacyAware.value
    ? privacyMetricCards(privacyAware.value.metrics, privacyAware.value.level)
    : []
));

async function loadDashboard() {
  if (!userId.value || !tripId.value) return;
  loading.value = true;
  error.value = '';
  dashboard.value = null;
  try {
    dashboard.value = await fetchTripDashboard(userId.value, tripId.value);
  } catch (unknownError) {
    dashboard.value = null;
    error.value = unknownError instanceof ApiError
      ? unknownError.message
      : 'Viaggio non disponibile';
  } finally {
    loading.value = false;
  }
}

async function selectPrivacyLevel(level: PrivacyLevel) {
  if (!dashboard.value || privacyLoading.value) return;
  if (dashboard.value.privacy_aware.level === level) return;
  privacyLoading.value = true;
  try {
    const response = await fetchTripDashboard(userId.value, tripId.value, level);
    if (dashboard.value) {
      // Swap only the privacy-aware view so the private comparison, local
      // filters, and the owner's saved preference stay untouched.
      dashboard.value.privacy_aware = response.privacy_aware;
    }
  } catch {
    // Keep the previously rendered privacy-aware view on a failed preview.
  } finally {
    privacyLoading.value = false;
  }
}

function renderMap() {
  destroyMap();
  if (!mapElement.value || !dashboard.value) return;

  const map = L.map(mapElement.value, { scrollWheelZoom: false });
  leafletMap = map;
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors',
  }).addTo(map);

  const visiblePoints: LatLngTuple[] = [];
  if (hasPrivateLayer.value) {
    if (!hasLocalFilters.value) {
      drawLine(dashboard.value.track.geojson, '#000000', 5, 0.45, visiblePoints);
    } else if (showFullTripGhost.value) {
      drawLine(dashboard.value.track.geojson, '#000000', 3, 0.06, visiblePoints, undefined, false);
    }
    for (const segment of moveSegments.value) {
      drawLine(
        segment.path_geojson ?? null,
        activityColor(segment.activity_label),
        6,
        0.85,
        visiblePoints,
      );
    }
    drawStopMarkers(stopSegments.value, visiblePoints);
  }

  if (hasPrivacyAwareLayer.value) {
    if (!hasLocalFilters.value) {
      drawLine(
        dashboard.value.privacy_aware.track.geojson,
        '#0f766e',
        4,
        0.9,
        visiblePoints,
        '8 8',
      );
    } else if (showFullTripGhost.value) {
      drawLine(
        dashboard.value.privacy_aware.track.geojson,
        '#0f766e',
        3,
        0.07,
        visiblePoints,
        '8 8',
        false,
      );
    }
    for (const segment of visiblePrivacyMoves.value) {
      drawLine(
        segment.path_geojson ?? null,
        '#0f766e',
        5,
        0.75,
        visiblePoints,
        '8 8',
      );
    }
    drawStopMarkers(visiblePrivacyStops.value, visiblePoints);
    drawPrivacyPlaces(visiblePoints);
  }

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
  dashArray?: string,
  includeInBounds = true,
) {
  if (!geojson?.coordinates.length || !leafletMap) return;
  const points = geojson.coordinates.map(([lon, lat]) => [lat, lon] as LatLngTuple);
  if (includeInBounds) {
    visiblePoints.push(...points);
  }
  L.polyline(points, { color, dashArray, opacity, weight }).addTo(leafletMap);
}

function drawPrivacyPlaces(visiblePoints: LatLngTuple[]) {
  if (!leafletMap || !dashboard.value) return;
  for (const place of visiblePrivacyPlaces.value) {
    const coordinates = place.center_geojson?.coordinates;
    if (!coordinates) continue;
    const [lon, lat] = coordinates;
    const position: LatLngTuple = [lat, lon];
    visiblePoints.push(position);
    // The label is already masked server-side for non-precise levels, so the
    // tooltip never leaks a sensitive place name.
    L.circleMarker(position, {
      color: '#0f766e',
      fillColor: '#0f766e',
      fillOpacity: 0.88,
      radius: 10,
      weight: 3,
    })
      .bindTooltip(place.label || 'Sosta significativa')
      .addTo(leafletMap);
  }
}

function drawStopMarkers(
  segments: DashboardSegment[],
  visiblePoints: LatLngTuple[],
) {
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

function clearLocalFilters() {
  filters.activities = [];
  filters.place = '';
  resetTimeFilters();
}

function resetTimeFilters() {
  filters.from = tripStartInput.value;
  filters.to = tripEndInput.value;
}

function clampFromFilter() {
  filters.from = clampDateTimeValue(
    filters.from,
    tripStartInput.value,
    filters.to || tripEndInput.value,
  );
}

function clampToFilter() {
  filters.to = clampDateTimeValue(
    filters.to,
    filters.from || tripStartInput.value,
    tripEndInput.value,
  );
}

function clampDateTimeValue(value: string, min: string, max: string): string {
  let current = value || min || max;
  if (min && current < min) current = min;
  if (max && current > max) current = max;
  return current;
}

watch([userId, tripId], loadDashboard, { immediate: true });
watch(dashboard, () => {
  filters.activities = [];
  filters.place = '';
  resetTimeFilters();
});
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
  [
    dashboard,
    moveSegments,
    stopSegments,
    visiblePrivacyMoves,
    visiblePrivacyStops,
    visiblePrivacyPlaces,
    visibleMapLayer,
  ],
  () => nextTick(renderMap),
  { flush: 'post' },
);
onBeforeUnmount(destroyMap);
</script>

<template>
  <section class="page-stack" aria-labelledby="trip-dashboard-title">
    <nav class="breadcrumb breadcrumb-chain">
      <RouterLink :to="{ name: 'user-trips', params: { userId } }">
        <ArrowLeft :size="16" />
        <span>{{ ownerName }}</span>
      </RouterLink>
      <span>/</span>
      <span>Viaggio #{{ tripId }}</span>
    </nav>

    <div class="section-heading">
      <div>
        <p class="eyebrow">Dashboard Viaggio</p>
        <h2 id="trip-dashboard-title">Viaggio #{{ tripId }}</h2>
        <p v-if="dashboard">
          {{ dashboard.owner.email }} · {{ formatTripStatus(dashboard.trip.status) }}
        </p>
      </div>
      <RouterLink class="button-subtle link-button" :to="{ name: 'user-trips', params: { userId } }">
        <RouteIcon :size="18" />
        <span>Lista viaggi</span>
      </RouterLink>
    </div>

    <section v-if="loading" class="message-panel state-panel">
      <strong>Caricamento viaggio...</strong>
      <p>Preparazione di mappa, timeline e statistiche.</p>
    </section>
    <section v-else-if="error" class="message-panel state-panel error-panel">
      <strong>{{ error }}</strong>
      <p>Il dettaglio non e stato caricato.</p>
      <div class="state-actions">
        <button class="button-primary" type="button" @click="loadDashboard">
          Riprova
        </button>
        <RouterLink
          class="button-subtle link-button"
          :to="{ name: 'user-trips', params: { userId } }"
        >
          Lista viaggi
        </RouterLink>
      </div>
    </section>

    <div v-else-if="dashboard && stats" class="trip-dashboard-grid">
      <form class="filters-panel detail-filters" @submit.prevent>
        <div class="filters-grid detail-filters-grid">
          <label>
            Da
            <input
              v-model="filters.from"
              type="datetime-local"
              :min="tripStartInput"
              :max="filters.to || tripEndInput || undefined"
              @change="clampFromFilter"
            />
          </label>
          <label>
            A
            <input
              v-model="filters.to"
              type="datetime-local"
              :min="filters.from || tripStartInput"
              :max="tripEndInput || undefined"
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
            @click="clearLocalFilters"
          >
            <X :size="18" />
            <span>Pulisci</span>
          </button>
        </div>
      </form>

      <section class="map-panel" aria-label="Mappa del viaggio">
        <div class="map-toolbar" aria-label="Layer mappa">
          <button
            type="button"
            :class="{ active: visibleMapLayer === 'private' }"
            @click="visibleMapLayer = 'private'"
          >
            Privata
          </button>
          <button
            type="button"
            :class="{ active: visibleMapLayer === 'privacy-aware' }"
            @click="visibleMapLayer = 'privacy-aware'"
          >
            Privacy-aware
          </button>
          <button
            type="button"
            :class="{ active: visibleMapLayer === 'both' }"
            @click="visibleMapLayer = 'both'"
          >
            Entrambe
          </button>
        </div>
        <div class="map-legend">
          <span><i class="legend-line private-line"></i>Privata</span>
          <span><i class="legend-line privacy-line"></i>Privacy-aware</span>
          <span><i class="legend-dot stop-dot"></i>Sosta</span>
          <span><i class="legend-dot place-dot"></i>Luogo significativo</span>
          <strong>{{ dashboard.privacy_aware.level }}</strong>
        </div>
        <div ref="mapElement" class="trip-map"></div>
        <div v-if="!hasVisibleMapGeometry" class="map-empty">
          Traccia non disponibile
        </div>
      </section>

      <aside class="stats-panel" aria-label="Statistiche del viaggio">
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

      <section class="privacy-panel" aria-labelledby="privacy-title">
        <div class="section-heading compact-heading">
          <div>
            <p class="eyebrow">Confronto privacy</p>
            <h2 id="privacy-title">
              Vista {{ privacyLevelLabel(dashboard.privacy_aware.level) }}
            </h2>
          </div>
          <span
            v-if="!isProtectedLevel(dashboard.privacy_aware.level)"
            class="privacy-flag privacy-flag-warning"
          >
            Non protetto
          </span>
          <span v-else class="privacy-flag privacy-flag-safe">Protetto</span>
        </div>

        <div
          class="privacy-level-controls"
          role="group"
          aria-label="Anteprima livello privacy"
        >
          <button
            v-for="option in privacyLevelOptions"
            :key="option.value"
            type="button"
            :class="{ active: dashboard.privacy_aware.level === option.value }"
            :disabled="privacyLoading"
            @click="selectPrivacyLevel(option.value)"
          >
            <strong>{{ option.label }}</strong>
            <small>{{ option.cellLabel }}</small>
            <span
              v-if="option.value === dashboard.privacy_aware.default_level"
              class="privacy-default-chip"
            >
              Preferenza utente
            </span>
          </button>
        </div>

        <div class="privacy-metrics" aria-label="Metriche privacy">
          <div
            v-for="card in privacyMetricList"
            :key="card.key"
            class="privacy-metric"
          >
            <span>{{ card.label }}</span>
            <strong>{{ card.value }}</strong>
            <small>{{ card.hint }}</small>
          </div>
        </div>

        <div v-if="visiblePrivacyPlaces.length > 0" class="privacy-places">
          <p class="eyebrow">Luoghi significativi privacy-aware</p>
          <ul>
            <li v-for="(place, index) in visiblePrivacyPlaces" :key="index">
              <span class="activity-dot privacy-place-dot"></span>
              <span>{{ place.label }}</span>
              <small>{{ formatDuration(place.dwell_seconds) }}</small>
            </li>
          </ul>
        </div>
      </section>

      <section class="timeline-panel" aria-labelledby="timeline-title">
        <div class="section-heading compact-heading">
          <div>
            <p class="eyebrow">Diario</p>
            <h2 id="timeline-title">Timeline</h2>
            <p>{{ activeTimelineLabel }}</p>
          </div>
          <span class="muted-text">{{ activeTimelineSegments.length }} segmenti</span>
        </div>

        <div v-if="activeTimelineSegments.length === 0" class="message-panel state-panel">
          <strong>
            {{ hasLocalFilters ? 'Nessun segmento corrisponde ai filtri.' : 'Diario non ancora disponibile.' }}
          </strong>
          <p v-if="hasLocalFilters">Puoi pulire i filtri per tornare alla vista completa.</p>
          <button
            v-if="hasLocalFilters"
            class="button-subtle"
            type="button"
            @click="clearLocalFilters"
          >
            <X :size="18" />
            <span>Pulisci</span>
          </button>
        </div>
        <ol v-else class="timeline-list">
          <li
            v-for="segment in activeTimelineSegments"
            :key="`${segment.start_timestamp}-${segment.kind}`"
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

      <section class="diary-table-panel" aria-labelledby="diary-table-title">
        <div class="section-heading compact-heading">
          <div>
            <p class="eyebrow">Diario tabellare</p>
            <h2 id="diary-table-title">Segmenti</h2>
            <p>{{ activeTimelineLabel }}</p>
          </div>
          <span class="muted-text">{{ activeTimelineSegments.length }} righe</span>
        </div>

        <div v-if="activeTimelineSegments.length === 0" class="message-panel state-panel">
          Nessun segmento da mostrare.
        </div>
        <div v-else class="data-table diary-segments-table" role="table" aria-label="Segmenti del diario">
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
            v-for="segment in activeTimelineSegments"
            :key="`${segment.start_timestamp}-${segment.end_timestamp}-${segment.kind}-table`"
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
