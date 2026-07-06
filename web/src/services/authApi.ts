import { sendJson } from './apiClient.js';
import { authSession } from './authSession.js';

export type WebUser = {
  id: number;
  email: string;
  first_name: string;
  last_name: string;
  is_staff: boolean;
  is_superuser: boolean;
};

type AuthResponse = {
  user: WebUser;
  access_token: string;
  refresh_token: string;
  token_type: 'Bearer';
  access_expires_at: string;
  refresh_expires_at: string;
};

export async function login(email: string, password: string): Promise<WebUser> {
  return saveAuthResponse(await sendJson<AuthResponse>('/web/auth/login', {
    method: 'POST',
    body: { email, password },
    token: null,
  }));
}

export async function loadCurrentUser(): Promise<WebUser> {
  return sendJson<WebUser>('/web/auth/me');
}

export async function refreshSession(): Promise<WebUser | null> {
  const refreshToken = authSession.refreshToken();
  if (!refreshToken) return null;

  return saveAuthResponse(await sendJson<AuthResponse>('/web/auth/refresh', {
    method: 'POST',
    body: { refresh_token: refreshToken },
    token: null,
  }));
}

export async function logout(): Promise<void> {
  const refreshToken = authSession.refreshToken();
  try {
    if (refreshToken) {
      await sendJson('/web/auth/logout', {
        method: 'POST',
        body: { refresh_token: refreshToken },
        token: null,
      });
    }
  } finally {
    authSession.clear();
  }
}

function saveAuthResponse(response: AuthResponse): WebUser {
  authSession.save({
    accessToken: response.access_token,
    refreshToken: response.refresh_token,
  });
  return response.user;
}
