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
  filterSegments,
  segmentSeconds,
  summarizeTrip,
} from '../utils/tripDashboard';

const route = useRoute();
const dashboard = ref<WebTripDashboard | null>(null);
const loading = ref(false);
const error = ref('');
const mapElement = ref<HTMLElement | null>(null);
const filters = reactive({
  activities: [] as string[],
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
const activityOptions = computed(() => (
  activityFilterOptions(dashboard.value?.diary.segments ?? [])
));
const hasLocalFilters = computed(() => (
  filters.activities.length > 0 || Boolean(filters.from || filters.to)
));
const visibleSegments = computed(() => (
  filterSegments(dashboard.value?.diary.segments ?? [], filters)
));
const stats = computed(() => (
  dashboard.value
    ? summarizeTrip(dashboard.value.trip, visibleSegments.value, {
      durationMode: hasLocalFilters.value ? 'segments' : 'trip',
    })
    : null
));
const statCards = computed(() => {
  if (!stats.value) return [];
  return [
    { icon: Clock, label: 'Durata totale', value: formatDuration(stats.value.totalDurationSeconds) },
    { icon: RouteIcon, label: 'Movimento', value: formatDuration(stats.value.movementSeconds) },
    { icon: MapPinned, label: 'Soste', value: formatDuration(stats.value.stoppedSeconds) },
    { icon: BarChart3, label: 'Distanza movimento', value: formatDistance(stats.value.movementDistanceMeters) },
  ];
});
const tripStartInput = computed(() => formatDateTimeInput(dashboard.value?.trip.started_at));
const tripEndInput = computed(() => formatDateTimeInput(dashboard.value?.trip.ended_at));
const hasVisibleMapGeometry = computed(() => Boolean(
  dashboard.value?.track.geojson || moveSegments.value.some((segment) => segment.path_geojson),
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

function renderMap() {
  destroyMap();
  if (!mapElement.value || !dashboard.value) return;

  const map = L.map(mapElement.value, { scrollWheelZoom: false });
  leafletMap = map;
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors',
  }).addTo(map);

  const visiblePoints: LatLngTuple[] = [];
  drawLine(dashboard.value.track.geojson, '#000000', 5, 0.65, visiblePoints);
  for (const segment of moveSegments.value) {
    drawLine(
      segment.path_geojson ?? null,
      activityColor(segment.activity_label),
      6,
      0.9,
      visiblePoints,
    );
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
) {
  if (!geojson?.coordinates.length || !leafletMap) return;
  const points = geojson.coordinates.map(([lon, lat]) => [lat, lon] as LatLngTuple);
  visiblePoints.push(...points);
  L.polyline(points, { color, opacity, weight }).addTo(leafletMap);
}

function destroyMap() {
  leafletMap?.remove();
  leafletMap = null;
}

function clearLocalFilters() {
  filters.activities = [];
  filters.from = '';
  filters.to = '';
}

watch([userId, tripId], loadDashboard, { immediate: true });
watch(dashboard, clearLocalFilters);
watch([dashboard, moveSegments], () => nextTick(renderMap), { flush: 'post' });
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
              :max="tripEndInput || undefined"
            />
          </label>
          <label>
            A
            <input
              v-model="filters.to"
              type="datetime-local"
              :min="tripStartInput"
              :max="tripEndInput || undefined"
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

      <section class="timeline-panel" aria-labelledby="timeline-title">
        <div class="section-heading compact-heading">
          <div>
            <p class="eyebrow">Diario</p>
            <h2 id="timeline-title">Timeline</h2>
          </div>
          <span class="muted-text">{{ visibleSegments.length }} segmenti</span>
        </div>

        <div v-if="visibleSegments.length === 0" class="message-panel state-panel">
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
            v-for="segment in visibleSegments"
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
                  : 'Sosta rilevata' }}
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
    </div>
  </section>
</template>
