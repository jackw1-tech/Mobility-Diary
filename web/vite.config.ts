import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

const localComposeGateway = 'http://localhost:8080';

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: localComposeGateway,
        changeOrigin: true,
      },
    },
  },
});
