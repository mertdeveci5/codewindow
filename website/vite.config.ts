import path from "node:path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

export default defineConfig(({ mode }) => ({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "./src"),
    },
  },
  optimizeDeps: {
    // Keep Base UI's CommonJS sync-store shims out of Vite's nested pre-bundle.
    exclude: ["@base-ui/react"],
    include: [
      "@base-ui/react > use-sync-external-store/shim",
      "@base-ui/react > use-sync-external-store/shim/with-selector",
    ],
  },
  server: {
    port: 5173,
  },
  build: {
    sourcemap: mode !== "production",
  },
}))
