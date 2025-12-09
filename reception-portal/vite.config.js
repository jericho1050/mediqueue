import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 3000,
    proxy: {
      '/admit': {
        target: 'http://triage-api:4000',
        changeOrigin: true
      },
      '/health': {
        target: 'http://triage-api:4000',
        changeOrigin: true
      }
    }
  },
  preview: {
    host: '0.0.0.0',
    port: 3000
  }
})
