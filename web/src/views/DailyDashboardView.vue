<script setup lang="ts">
import { computed } from 'vue';
import { RouterLink, useRoute } from 'vue-router';
import { ArrowLeft } from 'lucide-vue-next';
import DailyDashboardPanel from '../components/DailyDashboardPanel.vue';

const route = useRoute();

const userId = computed(() => route.params.userId?.toString() ?? '');
const day = computed(() => route.params.day?.toString() ?? new Date().toISOString().slice(0, 10));
</script>

<template>
  <section class="page-stack" aria-labelledby="daily-dashboard-title">
    <nav class="breadcrumb breadcrumb-chain">
      <RouterLink :to="{ name: 'user-trips', params: { userId } }">
        <ArrowLeft :size="16" />
        <span>Viaggi utente</span>
      </RouterLink>
      <span>/</span>
      <span>{{ day }}</span>
    </nav>

    <DailyDashboardPanel :user-id="userId" :initial-day="day" />
  </section>
</template>
