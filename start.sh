#!/usr/bin/env bash
# Local AI Image Generator - Linux launcher
# Bash port of start.bat. Runs first-time setup if needed, starts the local
# web server + stable-diffusion.cpp backend manager, and opens the browser.

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
APP_DIR="$ROOT_DIR/app"
SETUP="$ROOT_DIR/scripts/setup.sh"
SERVE="$ROOT_DIR/scripts/serve.cjs"
DIST="$APP_DIR/dist/index.html"
BACKEND_BIN="$APP_DIR/backend/linux/sd-vulkan"
BACKEND_LIB="$APP_DIR/backend/linux/libstable-diffusion.so"
FRONTEND_PORT="${FRONTEND_PORT:-1420}"

if [ -t 1 ]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
  C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi

# Resolve the node binary: portable copy first, then system node.
resolve_node() {
  if [ -x "$APP_DIR/tools/node-linux/bin/node" ]; then
    echo "$APP_DIR/tools/node-linux/bin/node"
  else
    command -v node || true
  fi
}

# ── Decide whether setup is required ──────────────────────────────────────────
NODE_BIN="$(resolve_node)"
SETUP_REASON=""
[ -z "$NODE_BIN" ]            && SETUP_REASON="Node.js is missing."
[ -f "$DIST" ]   || SETUP_REASON="Web UI build is missing."
{ [ -x "$BACKEND_BIN" ] && [ -f "$BACKEND_LIB" ]; } || SETUP_REASON="The Vulkan backend is not installed."

if [ -n "$SETUP_REASON" ]; then
  echo
  echo "${C_CYAN}  ============================================================${C_RESET}"
  echo "${C_CYAN}   LOCAL AI IMAGE GENERATOR  |  Setup needed${C_RESET}"
  echo "${C_CYAN}  ============================================================${C_RESET}"
  echo "   Reason: $SETUP_REASON"
  echo "   Models are not downloaded during setup — add them in the app."
  echo
  bash "$SETUP" || { echo "${C_RED}  Setup failed. See the output above.${C_RESET}"; exit 1; }
  NODE_BIN="$(resolve_node)"
fi

[ -n "$NODE_BIN" ] || { echo "${C_RED}  Could not find Node.js even after setup.${C_RESET}"; exit 1; }

# ── Clear any previous server holding the frontend port ───────────────────────
if pgrep -f "serve.cjs" >/dev/null 2>&1; then
  echo "${C_YELLOW}  Stopping a previous image-generator server...${C_RESET}"
  pkill -f "serve.cjs" 2>/dev/null || true
  sleep 1
fi

# ── Launch server (serve.cjs manages the sd-vulkan backend) ───────────────────
echo
echo "${C_CYAN}  ============================================================${C_RESET}"
echo "${C_CYAN}   LOCAL AI IMAGE GENERATOR  |  Launching...${C_RESET}"
echo "${C_CYAN}  ============================================================${C_RESET}"
echo

FRONTEND_PORT="$FRONTEND_PORT" "$NODE_BIN" "$SERVE" &
SERVER_PID=$!

cleanup() {
  trap - INT TERM EXIT   # disarm so this runs only once
  echo
  echo "  Shutting down..."
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  echo "  Done. Goodbye!"
}
trap cleanup INT TERM EXIT

# ── Wait for the server to bind, then open the browser ────────────────────────
ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "${C_RED}  Server exited during startup. See the log above.${C_RESET}"
    trap - EXIT
    exit 1
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "http://127.0.0.1:${FRONTEND_PORT}/api/health" >/dev/null 2>&1 && { ready=1; break; }
  else
    "$NODE_BIN" -e "require('http').get('http://127.0.0.1:${FRONTEND_PORT}/api/health',r=>process.exit(0)).on('error',()=>process.exit(1))" 2>/dev/null && { ready=1; break; }
  fi
  sleep 0.5
done

URL="http://localhost:${FRONTEND_PORT}"
if [ "$ready" -eq 1 ]; then
  if command -v xdg-open >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    echo "  Opening browser at $URL"
    xdg-open "$URL" >/dev/null 2>&1 || true
  else
    echo "  Open this URL in your browser:  $URL"
  fi
else
  echo "${C_YELLOW}  Server is taking longer than expected; try opening $URL manually.${C_RESET}"
fi

echo
echo "${C_GREEN}  ============================================================${C_RESET}"
echo "${C_GREEN}   Running!${C_RESET}"
echo "${C_GREEN}   Web UI:  $URL${C_RESET}"
echo "${C_GREEN}   Backend: auto-selected by the app (starts at 8080)${C_RESET}"
echo
echo "   Press Ctrl+C to stop all services."
echo "${C_GREEN}  ============================================================${C_RESET}"
echo

# Stream server logs and keep running until the server stops or Ctrl+C.
wait "$SERVER_PID"
