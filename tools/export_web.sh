#!/bin/bash
# 웹(HTML5) 빌드 → build/web/. 로컬 확인은 아래 서버로.
# 사전: Godot 에디터에서 [편집기 > 내보내기 템플릿 관리 > 다운로드·설치] 1회 필요.
set -e
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/web
echo "== 리소스 임포트 =="
"$GODOT" --headless --path . --import
echo "== 웹 릴리스 내보내기 =="
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
echo "완료 → build/web/index.html"
echo
echo "로컬 확인 (COOP/COEP 헤더 포함 서버):"
echo "  python3 tools/serve_web.py"
echo "그 뒤 브라우저에서 http://localhost:8060 (같은 와이파이면 폰에서 http://<맥IP>:8060)"
