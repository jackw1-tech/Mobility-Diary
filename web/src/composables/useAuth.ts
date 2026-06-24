import { reactive } from 'vue';
import { useRouter } from 'vue-router';
import {
  loadCurrentUser,
  login as loginRequest,
  logout as logoutRequest,
  refreshSession,
  type WebUser,
} from '../services/authApi';
import { authSession } from '../services/authSession';

type AuthState = {
  user: WebUser | null;
  loading: boolean;
};

const state = reactive<AuthState>({
  user: null,
  loading: false,
});

export function useAuth() {
  const router = useRouter();

  async function login(email: string, password: string): Promise<void> {
    state.loading = true;
    try {
      state.user = await loginRequest(email, password);
    } finally {
      state.loading = false;
    }
  }

  async function hydrate(): Promise<void> {
    if (state.user || !authSession.hasTokens()) return;

    state.loading = true;
    try {
      state.user = await loadCurrentUser();
    } catch {
      try {
        state.user = await refreshSession();
      } catch {
        authSession.clear();
        state.user = null;
      }
    } finally {
      state.loading = false;
    }
  }

  async function logout(): Promise<void> {
    await logoutRequest();
    state.user = null;
    await router.push({ name: 'login' });
  }

  return {
    state,
    hydrate,
    login,
    logout,
  };
}
