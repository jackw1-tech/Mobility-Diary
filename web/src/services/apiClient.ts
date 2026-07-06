import { authSession } from './authSession.js';

const API_BASE_URL =
  import.meta.env?.VITE_API_BASE_URL?.replace(/\/$/, '') ??
  '/api';

export class ApiError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

type RequestOptions = {
  method?: string;
  body?: unknown;
  token?: string | null;
};

type AuthResponse = {
  access_token: string;
  refresh_token: string;
};

let refreshInFlight: Promise<boolean> | null = null;

export async function sendJson<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const { method = 'GET', body } = options;
  const token = options.token === undefined ? authSession.accessToken() : options.token;

  const { response, payload } = await requestJson(path, { method, body, token });
  if (response.ok) return payload as T;

  if (response.status === 401 && token !== null && await refreshWebSession()) {
    const retry = await requestJson(path, {
      method,
      body,
      token: authSession.accessToken(),
    });
    if (retry.response.ok) return retry.payload as T;
    throw apiError(retry.payload, retry.response.status);
  }

  throw apiError(payload, response.status);
}

async function requestJson(
  path: string,
  { method, body, token }: Required<RequestOptions>,
): Promise<{ response: Response; payload: unknown }> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method,
    headers: {
      Accept: 'application/json',
      ...(body == null ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body == null ? undefined : JSON.stringify(body),
  });

  const payload = await readPayload(response);
  return { response, payload };
}

async function refreshWebSession(): Promise<boolean> {
  const refreshToken = authSession.refreshToken();
  if (!refreshToken) return false;

  refreshInFlight ??= performRefresh(refreshToken).finally(() => {
    refreshInFlight = null;
  });
  return refreshInFlight;
}

async function performRefresh(refreshToken: string): Promise<boolean> {
  try {
    const { response, payload } = await requestJson('/web/auth/refresh', {
      method: 'POST',
      body: { refresh_token: refreshToken },
      token: null,
    });
    if (!response.ok || !isAuthResponse(payload)) {
      authSession.clear();
      return false;
    }
    authSession.save({
      accessToken: payload.access_token,
      refreshToken: payload.refresh_token,
    });
    return true;
  } catch {
    authSession.clear();
    return false;
  }
}

function isAuthResponse(payload: unknown): payload is AuthResponse {
  return Boolean(
    payload &&
    typeof payload === 'object' &&
    'access_token' in payload &&
    typeof payload.access_token === 'string' &&
    'refresh_token' in payload &&
    typeof payload.refresh_token === 'string',
  );
}

function apiError(payload: unknown, status: number): ApiError {
  return new ApiError(errorMessage(payload, status), status);
}

async function readPayload(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

function errorMessage(payload: unknown, status: number): string {
  if (
    payload &&
    typeof payload === 'object' &&
    'detail' in payload &&
    typeof payload.detail === 'string'
  ) {
    return payload.detail;
  }
  return `Richiesta non riuscita (${status})`;
}
