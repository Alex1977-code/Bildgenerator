{{flutter_js}}
{{flutter_build_config}}

// CanvasKit lokal aus dem Build laden statt vom gstatic-CDN –
// macht die App als PWA vollständig selbst gehostet.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
