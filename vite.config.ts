import { defineConfig } from 'vite';
import cesium from 'vite-plugin-cesium';

export default defineConfig({
  base: './',
  plugins: [
    cesium(),
    {
      name: 'cesium-base-url-first',
      transformIndexHtml: {
        order: 'post',
        handler(html: string) {
          const tag = `<script>window.CESIUM_BASE_URL = new URL('cesium/', document.baseURI).href;</script>`;
          const stripped = html.replace(tag, '');
          return stripped.replace('<head>', `<head>\n    ${tag}`);
        },
      },
    },
  ],
  build: {
    target: 'es2022',
    sourcemap: false,
    chunkSizeWarningLimit: 2500,
  },
  preview: {
    host: '127.0.0.1',
  },
});
