import { resolve } from 'node:path'

import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
// Multi-page rather than a router.
//
// GitHub Pages serves files, and knows nothing about client-side routes: a
// visitor arriving straight at /download.html from a search result or a shared
// link would get a 404 from an app that only has one HTML file. Every page here
// is a real document with its own title, description and canonical URL, which
// is also what a search engine wants.
export default defineConfig({
  plugins: [react()],
  base: '/trustiq-uae/',
  build: {
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, 'index.html'),
        download: resolve(import.meta.dirname, 'download.html'),
        product: resolve(import.meta.dirname, 'product.html'),
        trust: resolve(import.meta.dirname, 'trust.html'),
        business: resolve(import.meta.dirname, 'business.html'),
        about: resolve(import.meta.dirname, 'about.html'),
      },
    },
  },
})
