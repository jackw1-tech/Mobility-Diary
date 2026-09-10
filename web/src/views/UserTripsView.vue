<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue';
import { RouterLink, useRoute } from 'vue-router';
import { ArrowLeft, RefreshCw, Route as RouteIcon, Search, X } from 'lucide-vue-next';
import DailyDashboardPanel from '../components/DailyDashboardPanel.vue';
import { ApiError } from '../services/apiClient';
import {
  fetchUserMotionStats,
  fetchUserTrips,
  type WebMotionStats,
  type WebTripFilters,
  type WebUserTripsResponse,
} from '../services/usersApi';
import {
  displayName,
  formatDateTime,
  formatDistance,
  formatTripStatus,
} from '../utils/formatters';
import { activityLabel } from '../utils/tripDashboard';

const route = useRoute();
const result = ref<WebUserTripsResponse | null>(null);
const loading = ref(false);
const error = ref('');
const motionStats = ref<WebMotionStats[]>([]);
const motionStatsLoading = ref(false);
const motionStatsError = ref('');
const motionAxes = [
  { key: 'accel_x', label: 'Accel X' },
  { key: 'accel_y', label: 'Accel Y' },
  { key: 'accel_z', label: 'Accel Z' },
  { key: 'gyro_x', label: 'Gyro X' },
  { key: 'gyro_y', label: 'Gyro Y' },
  { key: 'gyro_z', label: 'Gyro Z' },
] as const;

function formatAxisStats(stats: { mean: number; std: number }): string {
  return `${stats.mean.toFixed(2)} ± ${stats.std.toFixed(2)}`;
}
const emptyFilters: Required<WebTripFilters> = {
  from: '',
  to: '',
  status: '',
  processed: '',
  has_track: '',
};
const filters = reactive({ ...emptyFilters });

const userId = computed(() => {
  const value = route.params.userId;
  return Array.isArray(value) ? value[0] : String(value ?? '');
});

const owner = computed(() => result.value?.owner ?? null);
const trips = computed(() => result.value?.trips ?? []);
const ownerTitle = computed(() => {
  if (!owner.value) return `Utente #${userId.value}`;
  return displayName(owner.value.first_name, owner.value.last_name, owner.value.email);
});

const hasActiveFilters = computed(() => Object.values(filters).some(Boolean));
const emptyMessage = computed(() => (
  hasActiveFilters.value
    ? 'Nessun viaggio corrisponde ai filtri applicati.'
    : 'Questo utente non ha ancora viaggi.'
));

async function loadTrips() {
  if (!userId.value) return;
  loading.value = true;
  error.value = '';
  try {
    result.value = await fetchUserTrips(userId.value, filters);
  } catch (unknownError) {
    error.value = unknownError instanceof ApiError
      ? unknownError.message
      : 'Viaggi non disponibili';
  } finally {
    loading.value = false;
  }
}

function clearFilters() {
  Object.assign(filters, emptyFilters);
  void loadTrips();
}

async function loadMotionStats() {
  if (!userId.value) return;
  motionStatsLoading.value = true;
  motionStatsError.value = '';
  try {
    motionStats.value = await fetchUserMotionStats(userId.value);
  } catch (unknownError) {
    motionStatsError.value = unknownError instanceof ApiError
      ? unknownError.message
      : 'Statistiche motorie non disponibili';
  } finally {
    motionStatsLoading.value = false;
  }
}

watch(userId, () => {
  result.value = null;
  motionStats.value = [];
  void loadTrips();
  void loadMotionStats();
}, { immediate: true });
</script>

<template>
  <section class="page-stack" aria-labelledby="trips-title">
    <nav class="breadcrumb">
      <RouterLink :to="{ name: 'users' }">
        <ArrowLeft :size="16" />
        <span>Utenti</span>
      </RouterLink>
    </nav>

    <div class="section-heading">
      <div>
        <p class="eyebrow">Viaggi del Proprietario</p>
        <h2 id="trips-title">{{ ownerTitle }}</h2>
        <p v-if="owner">{{ owner.email }}</p>
      </div>
      <button class="button-subtle" type="button" @click="loadTrips">
        <RefreshCw :size="18" />
        <span>Aggiorna</span>
      </button>
    </div>

    <form class="filters-panel" @submit.prevent="loadTrips">
      <div class="filters-grid">
        <label>
          Da
          <input v-model="filters.from" type="datetime-local" />
        </label>
        <label>
          A
          <input v-model="filters.to" type="datetime-local" />
        </label>
        <label>
          Stato
          <select v-model="filters.status">
            <option value="">Tutti</option>
            <option value="OPEN">Aperti</option>
            <option value="CLOSED">Chiusi</option>
            <option value="PROCESSED">Processati</option>
          </select>
        </label>
        <label>
          Processato
          <select v-model="filters.processed">
            <option value="">Tutti</option>
            <option value="true">Si</option>
            <option value="false">No</option>
          </select>
        </label>
        <label>
          Traccia
          <select v-model="filters.has_track">
            <option value="">Tutte</option>
            <option value="true">Presente</option>
            <option value="false">Assente</option>
          </select>
        </label>
      </div>

      <div class="filters-actions">
        <button class="button-primary" type="submit" :disabled="loading">
          <Search :size="18" />
          <span>Applica</span>
        </button>
        <button class="button-subtle" type="button" :disabled="loading" @click="clearFilters">
          <X :size="18" />
          <span>Pulisci</span>
        </button>
      </div>
    </form>

    <div v-if="loading" class="message-panel">Caricamento viaggi...</div>
    <div v-else-if="error" class="message-panel error-panel">{{ error }}</div>
    <div v-else-if="trips.length === 0" class="message-panel">{{ emptyMessage }}</div>

    <div v-else class="data-table" role="table" aria-label="Viaggi del proprietario">
      <div class="table-row trips-row table-header" role="row">
        <span>Viaggio</span>
        <span>Inizio</span>
        <span>Fine</span>
        <span>Stato</span>
        <span>Distanza</span>
        <span>Processato</span>
        <span>Traccia</span>
      </div>

      <RouterLink
        v-for="trip in trips"
        :key="trip.id"
        class="table-row trips-row table-link"
        role="row"
        :to="{ name: 'trip-dashboard', params: { userId, tripId: trip.id } }"
      >
        <span>
          <strong>#{{ trip.id }}</strong>
          <small>{{ trip.status }}</small>
        </span>
        <span>{{ formatDateTime(trip.started_at) }}</span>
        <span>{{ formatDateTime(trip.ended_at, 'Aperto') }}</span>
        <span>
          <span class="status-pill" :class="{ muted: trip.status !== 'PROCESSED' }">
            {{ formatTripStatus(trip.status) }}
          </span>
        </span>
        <span>{{ formatDistance(trip.distance_meters) }}</span>
        <span>{{ trip.processed ? 'Si' : 'No' }}</span>
        <span>{{ trip.has_track ? 'Presente' : 'Assente' }}</span>
      </RouterLink>
    </div>

    <div v-if="owner" class="hint-panel">
      <RouteIcon :size="18" />
      <span>{{ owner.trip_count }} viaggi totali per questo Proprietario del Viaggio.</span>
    </div>

    <section class="diary-table-panel" aria-labelledby="motion-stats-title">
      <div class="section-heading compact-heading">
        <div>
          <p class="eyebrow">Qualità dati · HAR</p>
          <h2 id="motion-stats-title">Accelerometro e giroscopio per modalità</h2>
          <p>Media ± deviazione standard su tutti i segmenti di movimento di questo utente.</p>
        </div>
      </div>

      <div v-if="motionStatsLoading" class="message-panel state-panel">
        Calcolo statistiche in corso...
      </div>
      <div v-else-if="motionStatsError" class="message-panel error-panel">
        {{ motionStatsError }}
      </div>
      <div v-else-if="motionStats.length === 0" class="message-panel state-panel">
        Nessun segmento di movimento con dati sensore per questo utente.
      </div>
      <div v-else class="data-table motion-stats-table" role="table" aria-label="Statistiche motorie per modalità">
        <div class="table-row motion-stats-row table-header" role="row">
          <span>Modalità</span>
          <span>Campioni</span>
          <span v-for="axis in motionAxes" :key="axis.key">{{ axis.label }}</span>
        </div>
        <div
          v-for="stats in motionStats"
          :key="stats.activity_label"
          class="table-row motion-stats-row"
          role="row"
        >
          <span>{{ activityLabel(stats.activity_label) }}</span>
          <span>{{ stats.sample_count }}</span>
          <span v-for="axis in motionAxes" :key="axis.key">
            {{ formatAxisStats(stats[axis.key]) }}
          </span>
        </div>
      </div>
    </section>

    <DailyDashboardPanel :user-id="userId" />
  </section>
</template>
