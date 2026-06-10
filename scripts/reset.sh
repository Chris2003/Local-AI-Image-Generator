#!/usr/bin/env bash
# scripts/reset.sh
# Bash port of scripts/reset.ps1. Removes downloaded runtime/build artifacts so
# setup can start clean. Your models (app/models) and generated images
# (app/outputs) are always preserved. The prebuilt UI in app/dist is kept too,
# so the app can relaunch without an npm rebuild.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(dirname -- "$SCRIPT_DIR")"
APP_DIR="$ROOT_DIR/app"

if [ -t 1 ]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi

echo
echo "${C_YELLOW}  ============================================================${C_RESET}"
echo "${C_YELLOW}   Resetting Local AI Image Generator (Linux)...${C_RESET}"
echo "${C_YELLOW}  ============================================================${C_RESET}"
echo

# Stop a running server so files can be removed.
if pgrep -f "serve.cjs" >/dev/null 2>&1; then
  echo "${C_CYAN}   >> Stopping running server...${C_RESET}"
  pkill -f "serve.cjs" 2>/dev/null || true
  sleep 1
fi

remove() {
  local target="$1" label="$2"
  if [ -e "$target" ]; then
    echo "${C_CYAN}   >> Removing $label...${C_RESET}"
    rm -rf "$target"
  fi
}

remove "$APP_DIR/tools"                       "portable Node.js (app/tools)"
remove "$APP_DIR/backend"                     "backend binaries (app/backend)"
remove "$APP_DIR/frontend/node_modules"       "frontend node_modules"
remove "$APP_DIR/frontend/package-lock.json"  "frontend package-lock.json"

[ -d "$APP_DIR/models" ]  && echo "${C_CYAN}   >> Preserving downloaded models in app/models.${C_RESET}"
[ -d "$APP_DIR/outputs" ] && echo "${C_CYAN}   >> Preserving generated images in app/outputs.${C_RESET}"
[ -f "$APP_DIR/dist/index.html" ] && echo "${C_CYAN}   >> Preserving prebuilt UI in app/dist.${C_RESET}"

echo
echo "${C_GREEN}  ============================================================${C_RESET}"
echo "${C_GREEN}   Reset complete. Run ./start.sh to set up again.${C_RESET}"
echo "${C_GREEN}  ============================================================${C_RESET}"
echo
