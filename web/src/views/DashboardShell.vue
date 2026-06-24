<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { RouterLink, RouterView } from 'vue-router';
import { LogOut, ShieldCheck } from 'lucide-vue-next';
import { useAuth } from '../composables/useAuth';

const { state, hydrate, logout } = useAuth();

const userLabel = computed(() => {
  if (!state.user) return 'Operatore Web';
  const fullName = [state.user.first_name, state.user.last_name]
    .filter(Boolean)
    .join(' ');
  return fullName || state.user.email;
});

onMounted(() => {
  void hydrate();
});
</script>

<template>
  <div class="dashboard-shell">
    <header class="topbar">
      <div class="brand-row compact">
        <div class="brand-mark">MD</div>
        <div>
          <p class="eyebrow">Vista Staff Globale</p>
          <h1>Mobility Diary</h1>
        </div>
      </div>

      <div class="operator-chip">
        <ShieldCheck :size="16" />
        <span>{{ userLabel }}</span>
      </div>

      <button class="button-subtle" type="button" @click="logout">
        <LogOut :size="18" />
        <span>Esci</span>
      </button>
    </header>

    <main class="workspace">
      <nav class="breadcrumb" aria-label="Percorso">
        <RouterLink :to="{ name: 'users' }">Utenti</RouterLink>
      </nav>
      <RouterView />
    </main>
  </div>
</template>
