import { defineConfig } from "vite";
import solid from "vite-plugin-solid";

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST;

// Web sources live in `frontend/`; the build output goes to `dist/` at the
// project root, which Tauri serves via `frontendDist: "../dist"`.
// https://vite.dev/config/
export default defineConfig(async () => ({
  root: "frontend",
  publicDir: "public",
  plugins: [solid()],

  // Prevent Vite from obscuring Rust errors.
  clearScreen: false,

  build: {
    outDir: "../dist",
    emptyOutDir: true,
    target: "esnext",
  },

  // Tauri expects a fixed port and fails if it is not available.
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // Tell Vite to ignore watching the Rust side.
      ignored: ["**/src-tauri/**", "**/crates/**", "**/target/**"],
    },
  },
}));
