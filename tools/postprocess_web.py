#!/usr/bin/env python3
"""웹 내보내기에서 예전 PWA 서비스워커 잔여물을 제거하고 무캐시 정책을 검증한다."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "build" / "web"
HTML = WEB / "index.html"
LEGACY_PWA_FILES = (
    "index.service.worker.js",
    "index.manifest.json",
)


def main() -> None:
    html = HTML.read_text(encoding="utf-8")
    if '"serviceWorker":"index.service.worker.js"' in html:
        raise RuntimeError("웹 내보내기에 서비스워커가 다시 활성화되었습니다.")
    if "getRegistrations()" not in html or ".unregister()" not in html:
        raise RuntimeError("기존 서비스워커 해제 스크립트가 웹 HTML에 없습니다.")

    for name in LEGACY_PWA_FILES:
        path = WEB / name
        if path.exists():
            path.unlink()


if __name__ == "__main__":
    main()
