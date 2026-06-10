#!/usr/bin/env bash
# Local AI Image Generator - Linux setup
# Bash port of scripts/setup.ps1 for Ubuntu/Debian and other glibc Linux distros.
#
#   - Uses the system Node.js when it is new enough, otherwise downloads a
#     self-contained portable Node into app/tools/node-linux/.
#   - Installs the prebuilt stable-diffusion.cpp Vulkan backend (works on
#     NVIDIA / AMD / Intel GPUs via Vulkan, with a CPU fallback) into
#     app/backend/linux/.
#   - Reuses the prebuilt web UI in app/dist/. Pass --rebuild to rebuild it
#     from app/frontend/ (requires an npm install).
#
# Usage: scripts/setup.sh [--rebuild]

set -uo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(dirname -- "$SCRIPT_DIR")"
APP_DIR="$ROOT_DIR/app"
TOOLS_DIR="$APP_DIR/tools"
NODE_DIR="$TOOLS_DIR/node-linux"
BACKEND_DIR="$APP_DIR/backend/linux"
FRONTEND_DIR="$APP_DIR/frontend"
DIST_DIR="$APP_DIR/dist"
MODELS_DIR="$APP_DIR/models"
OUTPUTS_DIR="$APP_DIR/outputs"

# ── Pinned downloads (kept in sync with scripts/setup.ps1) ────────────────────
SD_RELEASE_TAG="master-669-2d40a8b"
SD_COMMIT="2d40a8b"
SD_VULKAN_ASSET="sd-master-${SD_COMMIT}-bin-Linux-Ubuntu-24.04-x86_64-vulkan.zip"
SD_VULKAN_URL="https://github.com/leejet/stable-diffusion.cpp/releases/download/${SD_RELEASE_TAG}/${SD_VULKAN_ASSET}"
NODE_VERSION="v22.12.0"
NODE_ASSET="node-${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_ASSET}"
MIN_NODE_MAJOR=18

REBUILD_UI=0
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD_UI=1 ;;
    -h|--help)
      echo "Usage: scripts/setup.sh [--rebuild]"
      echo "  --rebuild   Rebuild the web UI from app/frontend/ instead of using app/dist/."
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# ── Pretty output ─────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_CYAN=$'\033[36m'; C_DCYAN=$'\033[2;36m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_GRAY=$'\033[90m'; C_RESET=$'\033[0m'
else
  C_CYAN=""; C_DCYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_GRAY=""; C_RESET=""
fi

print_header() {
  echo
  echo "${C_CYAN}  ============================================================${C_RESET}"
  echo "${C_CYAN}   LOCAL AI IMAGE GENERATOR  -  Linux Setup${C_RESET}"
  echo "${C_DCYAN}   Self-contained  |  Vulkan GPU + CPU  |  No root required${C_RESET}"
  echo "${C_CYAN}  ============================================================${C_RESET}"
  echo
}
print_step() { echo; echo "${C_RESET}  [$1/$2] $3"; echo "${C_GRAY}  --------------------------------------------------------${C_RESET}"; }
print_ok()   { echo "${C_GREEN}   OK  $1${C_RESET}"; }
print_info() { echo "${C_CYAN}   >>  $1${C_RESET}"; }
print_warn() { echo "${C_YELLOW}   !!  $1${C_RESET}"; }
print_fail() { echo "${C_RED}   XX  $1${C_RESET}"; }
die() { print_fail "$1"; exit 1; }

# ── Download helper (curl preferred, wget fallback) ──────────────────────────
download() {
  local url="$1" dest="$2" label="$3"
  print_info "Downloading: $label"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --progress-bar -o "$dest" "$url" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$dest" "$url" || return 1
  else
    print_fail "Neither curl nor wget is installed. Install one and re-run setup."
    return 1
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
print_header

# Only x86_64 has prebuilt stable-diffusion.cpp Linux binaries in this release.
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
  die "Unsupported architecture '$ARCH'. The prebuilt backend is x86_64-only. Build stable-diffusion.cpp from source for $ARCH and place 'sd-server' + 'libstable-diffusion.so' in app/backend/linux/."
fi

mkdir -p "$TOOLS_DIR" "$BACKEND_DIR" "$MODELS_DIR" "$OUTPUTS_DIR"

STEPS=3
[ "$REBUILD_UI" -eq 1 ] && STEPS=4
[ ! -f "$DIST_DIR/index.html" ] && STEPS=4

# ── Step 1: Node.js ───────────────────────────────────────────────────────────
print_step 1 "$STEPS" "Setting up Node.js"

NODE_BIN=""
NPM_BIN=""

if [ -x "$NODE_DIR/bin/node" ]; then
  NODE_BIN="$NODE_DIR/bin/node"
  NPM_BIN="$NODE_DIR/bin/npm"
  print_ok "Portable Node.js already present: $("$NODE_BIN" --version)"
else
  sys_node="$(command -v node || true)"
  sys_major=0
  if [ -n "$sys_node" ]; then
    sys_major="$("$sys_node" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  fi
  if [ -n "$sys_node" ] && [ "$sys_major" -ge "$MIN_NODE_MAJOR" ] 2>/dev/null; then
    NODE_BIN="$sys_node"
    NPM_BIN="$(command -v npm || true)"
    print_ok "Using system Node.js $("$NODE_BIN" --version) ($sys_node)"
    [ -z "$NPM_BIN" ] && print_warn "system npm not found; it is only needed for --rebuild."
  else
    if [ -n "$sys_node" ]; then
      print_info "System Node.js $("$sys_node" --version) is older than v${MIN_NODE_MAJOR}; installing a portable copy."
    else
      print_info "No system Node.js found; installing a portable copy under app/tools/node-linux/."
    fi
    node_tar="$TOOLS_DIR/node.tar.xz"
    download "$NODE_URL" "$node_tar" "Node.js ${NODE_VERSION} LTS (portable)" || die "Could not download Node.js."
    print_info "Extracting Node.js..."
    rm -rf "$NODE_DIR" "$TOOLS_DIR/node-${NODE_VERSION}-linux-x64"
    tar -xf "$node_tar" -C "$TOOLS_DIR" || die "Failed to extract Node.js archive."
    mv "$TOOLS_DIR/node-${NODE_VERSION}-linux-x64" "$NODE_DIR" || die "Failed to place portable Node.js."
    rm -f "$node_tar"
    [ -x "$NODE_DIR/bin/node" ] || die "Portable Node.js install is incomplete."
    NODE_BIN="$NODE_DIR/bin/node"
    NPM_BIN="$NODE_DIR/bin/npm"
    print_ok "Portable Node.js ready: $("$NODE_BIN" --version)"
  fi
fi

# ── Step 2: stable-diffusion.cpp Vulkan backend ──────────────────────────────
print_step 2 "$STEPS" "Setting up stable-diffusion.cpp Vulkan backend (app/backend/linux/)"

# Informational GPU detection (the Vulkan binary covers all of these + CPU).
# Capture lspci into a variable first: piping into `grep -q` under `pipefail`
# makes lspci die with SIGPIPE and falsely reports failure.
gpu_list="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  print_info "NVIDIA GPU with a working driver detected (Vulkan-accelerated)."
elif [ -n "$gpu_list" ]; then
  gpu_line="$(printf '%s\n' "$gpu_list" | head -1 | sed -E 's/^[0-9a-fA-F:.]+ [^:]*: //; s/ \(rev [0-9a-fA-F]+\)$//')"
  print_info "GPU detected: ${gpu_line:-unknown} (Vulkan-accelerated where supported)."
else
  print_info "No discrete GPU detected; the backend will run on CPU."
fi

SD_BIN="$BACKEND_DIR/sd-vulkan"
SD_LIB="$BACKEND_DIR/libstable-diffusion.so"

if [ -x "$SD_BIN" ] && [ -f "$SD_LIB" ]; then
  print_ok "Vulkan backend binaries already present."
else
  backend_zip="$TOOLS_DIR/sd-vulkan-linux.zip"
  download "$SD_VULKAN_URL" "$backend_zip" "stable-diffusion.cpp Vulkan backend (Linux x86_64)" \
    || die "Could not download the Vulkan backend."
  command -v unzip >/dev/null 2>&1 || die "'unzip' is required. Install it: sudo apt install unzip"
  tmp_ext="$TOOLS_DIR/sd-linux-temp"
  rm -rf "$tmp_ext"; mkdir -p "$tmp_ext"
  print_info "Extracting backend..."
  unzip -o -q "$backend_zip" -d "$tmp_ext" || die "Failed to extract the backend archive."
  rm -f "$backend_zip"

  # The release ships sd-server, sd-cli and libstable-diffusion.so at the archive root.
  src_server="$(find "$tmp_ext" -type f -name 'sd-server' | head -1)"
  src_lib="$(find "$tmp_ext" -type f -name 'libstable-diffusion.so' | head -1)"
  [ -n "$src_server" ] || die "sd-server not found inside the backend archive."
  [ -n "$src_lib" ]    || die "libstable-diffusion.so not found inside the backend archive."

  cp -f "$src_server" "$SD_BIN"
  cp -f "$src_lib" "$SD_LIB"
  src_cli="$(find "$tmp_ext" -type f -name 'sd-cli' | head -1)"
  [ -n "$src_cli" ] && cp -f "$src_cli" "$BACKEND_DIR/sd-cli"
  # Copy any additional shared objects the build may ship.
  find "$tmp_ext" -type f -name '*.so*' -exec cp -f {} "$BACKEND_DIR/" \;
  rm -rf "$tmp_ext"
  chmod +x "$SD_BIN" "$BACKEND_DIR/sd-cli" 2>/dev/null || true

  [ -x "$SD_BIN" ] && [ -f "$SD_LIB" ] || die "Failed to install backend binaries into app/backend/linux/."
  print_ok "Vulkan backend installed."
fi

# Validate the binary actually loads its shared library, and report GPU vs CPU.
print_info "Verifying backend..."
probe_out="$(LD_LIBRARY_PATH="$BACKEND_DIR" timeout 15 "$SD_BIN" \
  --backend vulkan --params-backend vulkan \
  --model "$BACKEND_DIR/__probe_missing__.safetensors" --listen-port 18082 2>&1 || true)"
if grep -q "error while loading shared libraries" <<<"$probe_out"; then
  die "Backend cannot load libstable-diffusion.so. Re-run setup; if it persists your glibc may be too old for this build."
fi
if grep -qi "Vulkan devices" <<<"$probe_out"; then
  dev="$(grep -oiE '= .*\(radv[^)]*\)|= [^|]+' <<<"$probe_out" | head -1 | sed 's/^= //')"
  print_ok "Backend OK — Vulkan device: ${dev:-detected}"
else
  print_warn "Backend OK, but no Vulkan GPU was detected. The app will run on CPU."
fi

# ── Step 3: Web UI ────────────────────────────────────────────────────────────
if [ "$REBUILD_UI" -eq 0 ] && [ -f "$DIST_DIR/index.html" ]; then
  print_step 3 "$STEPS" "Web UI"
  print_ok "Using prebuilt UI in app/dist/ (pass --rebuild to rebuild from source)."
else
  print_step 3 "$STEPS" "Installing web UI dependencies (app/frontend/)"
  [ -n "$NPM_BIN" ] && [ -x "$NPM_BIN" ] || NPM_BIN="$(command -v npm || true)"
  [ -n "$NPM_BIN" ] || die "npm is required to build the UI. Install Node.js/npm, or restore app/dist/ and omit --rebuild."

  # Make sure 'node' is discoverable by npm (matters for portable Node).
  export PATH="$(dirname -- "$NODE_BIN"):$PATH"

  ( cd "$FRONTEND_DIR" && "$NPM_BIN" install --prefer-offline ) || die "npm install failed."
  print_ok "Dependencies installed."

  print_step 4 "$STEPS" "Building web UI -> app/dist/"
  ( cd "$FRONTEND_DIR" && "$NPM_BIN" run build ) || die "UI build failed."
  print_ok "Web UI built."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo "${C_GREEN}  ============================================================${C_RESET}"
echo "${C_GREEN}   Setup complete! Launch with:  ./start.sh${C_RESET}"
echo "${C_GREEN}  ============================================================${C_RESET}"
echo
