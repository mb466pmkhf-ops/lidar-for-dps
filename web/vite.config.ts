import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// `base` is relative so the same build works on GitHub Pages (a sub-path) and inside the Tauri desktop app.
export default defineConfig({
  base: './',
  plugins: [react()],
  server: { port: 5173, strictPort: true },
  build: { outDir: 'dist', target: 'es2022' },
});
