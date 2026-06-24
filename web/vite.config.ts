import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

const railwayApiTarget = 'https://django-api-production-df02.up.railway.app';

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: railwayApiTarget,
        changeOrigin: true,
      },
    },
  },
});
