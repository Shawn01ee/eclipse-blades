#!/usr/bin/env python3
"""Godot 웹 내보내기에 즉시 PWA 갱신 동작을 반복 가능하게 추가한다."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "build" / "web"
HTML = WEB / "index.html"
WORKER = WEB / "index.service.worker.js"

UPDATE_SCRIPT = """<script data-eclipse-update-manager>
(() => {
  if (!("serviceWorker" in navigator)) return;
  const hadController = navigator.serviceWorker.controller !== null;
  let reloading = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (!hadController || reloading) return;
    reloading = true;
    location.reload();
  });
  addEventListener("load", async () => {
    try {
      const registration = await navigator.serviceWorker.register("index.service.worker.js");
      await registration.update();
      setInterval(() => registration.update(), 60000);
    } catch (error) {
      console.warn("Update check unavailable", error);
    }
  });
})();
</script>"""

WORKER_UPDATE = """
// Eclipse Blades: activate a freshly deployed build immediately and take over
// existing tabs. The page reloads once on controllerchange, so its HTML, WASM,
// PCK and simulation build ID always come from the same deployment.
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
"""


def main() -> None:
    html = HTML.read_text(encoding="utf-8")
    if "data-eclipse-update-manager" not in html:
        html = html.replace("\t</head>", UPDATE_SCRIPT + "\n\t</head>", 1)
    HTML.write_text(html.rstrip() + "\n", encoding="utf-8")

    worker = WORKER.read_text(encoding="utf-8")
    if "Eclipse Blades: activate a freshly deployed build immediately" not in worker:
        worker = worker.rstrip() + "\n" + WORKER_UPDATE
    WORKER.write_text(worker.rstrip() + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
