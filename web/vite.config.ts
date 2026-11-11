import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

// Content Security Policy for the built site (GitHub Pages has no way to send headers). Only on
// build: the dev server injects inline scripts for hot reload. The desktop app sets the same policy
// in src-tauri/tauri.conf.json. connect-src allows any HTTPS host so a self-hosted sync server works.
const CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "font-src 'self' data:",
  "connect-src 'self' https:",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'none'",
].join('; ');

const csp = (): Plugin => ({
  name: 'framescan-csp',
  apply: 'build',
  transformIndexHtml: html => html.replace('<head>', `<head>\n    <meta http-equiv="Content-Security-Policy" content="${CSP}" />`),
});

// `base` is relative so the same build works on GitHub Pages (a sub-path) and inside the Tauri desktop app.
export default defineConfig({
  base: './',
  plugins: [react(), csp()],
  server: { port: 5173, strictPort: true },
  build: { outDir: 'dist', target: 'es2022', chunkSizeWarningLimit: 600 }, // three.js loads on its own, only for the 3D view
});
