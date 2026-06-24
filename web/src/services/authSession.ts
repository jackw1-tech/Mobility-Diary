const ACCESS_TOKEN_KEY = 'mobility_web_access_token';
const REFRESH_TOKEN_KEY = 'mobility_web_refresh_token';

export const authSession = {
  accessToken(): string | null {
    return localStorage.getItem(ACCESS_TOKEN_KEY);
  },

  refreshToken(): string | null {
    return localStorage.getItem(REFRESH_TOKEN_KEY);
  },

  hasTokens(): boolean {
    return Boolean(this.accessToken() && this.refreshToken());
  },

  save(tokens: { accessToken: string; refreshToken: string }): void {
    localStorage.setItem(ACCESS_TOKEN_KEY, tokens.accessToken);
    localStorage.setItem(REFRESH_TOKEN_KEY, tokens.refreshToken);
  },

  clear(): void {
    localStorage.removeItem(ACCESS_TOKEN_KEY);
    localStorage.removeItem(REFRESH_TOKEN_KEY);
  },
};
