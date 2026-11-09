import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import fs from "fs";
import type { Plugin } from "vite";

// DEV ONLY (`npm run dev`, never a build): serves saved real replies from SUNNY_FX_DIR at /__fx/, so the web's
// pages can be checked on real numbers without signing in (`?fx`, src/web/lib/data.ts). Nothing from that folder
// is ever copied into the repo or a deploy.
function sunnyFixtures(): Plugin {
  return {
    name: "sunny-fixtures",
    apply: "serve",
    configureServer(server) {
      const dir = process.env.SUNNY_FX_DIR;
      if (!dir) return;
      server.middlewares.use("/__fx", (req, res) => {
        const rel = decodeURIComponent((req.url || "/").split("?")[0]).replace(/^\/+/, "");
        const file = path.resolve(dir, rel);
        if (!file.startsWith(path.resolve(dir)) || !fs.existsSync(file)) { res.statusCode = 404; res.end("missing"); return; }
        res.setHeader("Content-Type", "application/json");
        fs.createReadStream(file).pipe(res);
      });
    },
  };
}

// https://vitejs.dev/config/
export default defineConfig(() => ({
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [react(), sunnyFixtures()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
    dedupe: ["react", "react-dom", "react/jsx-runtime", "react/jsx-dev-runtime"],
  },
  build: {
    // Split heavy third-party libs into their own chunks so they cache
    // independently of app code. A small change to a component shouldn't
    // bust the cache on a 200 KB charts library.
    rollupOptions: {
      output: {
        manualChunks: {
          react: ["react", "react-dom", "react-router-dom"],
          query: ["@tanstack/react-query"],
          supabase: ["@supabase/supabase-js"],
        },
      },
    },
    // Larger chunk warning threshold — we know charts/dnd are inherently big.
    chunkSizeWarningLimit: 600,
  },
}));
