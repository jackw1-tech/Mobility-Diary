<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { RouterLink } from 'vue-router';
import { ChevronRight, RefreshCw, Users } from 'lucide-vue-next';
import { ApiError } from '../services/apiClient';
import { fetchUsers, type WebUserSummary } from '../services/usersApi';
import { displayName, formatDateTime, formatDistance } from '../utils/formatters';

const users = ref<WebUserSummary[]>([]);
const loading = ref(false);
const error = ref('');

async function loadUsers() {
  loading.value = true;
  error.value = '';
  try {
    users.value = await fetchUsers();
  } catch (unknownError) {
    error.value = unknownError instanceof ApiError
      ? unknownError.message
      : 'Utenti non disponibili';
  } finally {
    loading.value = false;
  }
}

onMounted(loadUsers);
</script>

<template>
  <section class="page-stack" aria-labelledby="users-title">
    <div class="section-heading">
      <div>
        <p class="eyebrow">Proprietari del Viaggio</p>
        <h2 id="users-title">Utenti</h2>
      </div>
      <button class="button-subtle" type="button" @click="loadUsers">
        <RefreshCw :size="18" />
        <span>Aggiorna</span>
      </button>
    </div>

    <div v-if="loading" class="message-panel">Caricamento utenti...</div>
    <div v-else-if="error" class="message-panel error-panel">{{ error }}</div>
    <div v-else-if="users.length === 0" class="message-panel">
      Nessun utente analizzabile.
    </div>

    <div v-else class="data-table" role="table" aria-label="Utenti analizzabili">
      <div class="table-row table-header" role="row">
        <span>Utente</span>
        <span>Stato</span>
        <span>Viaggi</span>
        <span>Processati</span>
        <span>Ultimo viaggio</span>
        <span>Distanza</span>
        <span></span>
      </div>

      <RouterLink
        v-for="user in users"
        :key="user.id"
        class="table-row table-link"
        role="row"
        :to="{ name: 'user-trips', params: { userId: user.id } }"
      >
        <span>
          <strong>{{ displayName(user.first_name, user.last_name, user.email) }}</strong>
          <small>{{ user.email }}</small>
        </span>
        <span>
          <span class="status-pill" :class="{ muted: !user.is_active }">
            {{ user.is_active ? 'Attivo' : 'Disattivo' }}
          </span>
        </span>
        <span>{{ user.trip_count }}</span>
        <span>{{ user.processed_trip_count }}</span>
        <span>{{ formatDateTime(user.latest_trip_started_at) }}</span>
        <span>{{ formatDistance(user.total_distance_meters) }}</span>
        <span class="row-action"><ChevronRight :size="18" /></span>
      </RouterLink>
    </div>

    <div class="hint-panel">
      <Users :size="18" />
      <span>Gli Operatori Web e gli account staff sono esclusi da questa vista.</span>
    </div>
  </section>
</template>
