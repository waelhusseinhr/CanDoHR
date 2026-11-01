import { bindings, defineConfig, defineWorker } from "cf/config";

export default defineConfig({
  accountId: "cd54a788a204d1515eb3b3224cd9594a",
  worker: defineWorker({
    name: "candohr",
    domains: ["candohr.ca", "www.candohr.ca"],
    entrypoint: "vinext/server/fetch-handler",
    compatibilityDate: "2026-10-30",
    compatibilityFlags: ["nodejs_compat"],
    assets: {
      htmlHandling: "none",
      notFoundHandling: "none",
      runWorkerFirst: ["/*", "!/_next/static/*", "!/*/_next/static/*"],
    },
    env: {
      ASSETS: bindings.assets(),
      IMAGES: bindings.images(),
      // Hyperdrive config "candohr". Query caching is disabled on that config.
      HYPERDRIVE: bindings.hyperdrive({ id: "78a5fcc7d00d4dc3ae0562d8a2f1e3ff" }),
    },
  }),
});
