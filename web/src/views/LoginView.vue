<script setup lang="ts">
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { LogIn } from 'lucide-vue-next';
import { ApiError } from '../services/apiClient';
import { useAuth } from '../composables/useAuth';

const router = useRouter();
const route = useRoute();
const { login, state } = useAuth();

const email = ref('');
const password = ref('');
const error = ref('');

const canSubmit = computed(() => {
  return email.value.trim().length > 0 && password.value.length > 0;
});

async function submit() {
  if (!canSubmit.value || state.loading) return;
  error.value = '';

  try {
    await login(email.value, password.value);
    const next = typeof route.query.next === 'string' ? route.query.next : '/';
    await router.push(next);
  } catch (unknownError) {
    if (unknownError instanceof ApiError) {
      error.value = unknownError.message;
      return;
    }
    error.value = 'Accesso non riuscito';
  }
}
</script>

<template>
  <main class="login-page">
    <section class="login-panel" aria-labelledby="login-title">
      <div class="brand-row">
        <div class="brand-mark">MD</div>
        <div>
          <p class="eyebrow">Piattaforma Web</p>
          <h1 id="login-title">Mobility Diary</h1>
        </div>
      </div>

      <form class="login-form" @submit.prevent="submit">
        <label>
          Email staff
          <input
            v-model="email"
            autocomplete="username"
            name="email"
            type="email"
            placeholder="nome@example.com"
          />
        </label>

        <label>
          Password
          <input
            v-model="password"
            autocomplete="current-password"
            name="password"
            type="password"
            placeholder="Password"
          />
        </label>

        <p v-if="error" class="form-error" role="alert">{{ error }}</p>

        <button class="button-primary" type="submit" :disabled="!canSubmit || state.loading">
          <LogIn :size="18" />
          <span>{{ state.loading ? 'Accesso in corso' : 'Accedi' }}</span>
        </button>
      </form>
    </section>
  </main>
</template>
