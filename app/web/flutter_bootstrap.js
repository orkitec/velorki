{{flutter_js}}
{{flutter_build_config}}

// The planner runs in the element device_gate.mjs makes below the site's
// header (Flutter's embedded mode), not over the whole page.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async (engineInitializer) => {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.getElementById('velorki-app') ?? undefined,
    });
    await appRunner.runApp();
  },
});
