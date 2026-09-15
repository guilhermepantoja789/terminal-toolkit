#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_FILE="$DOTFILES_DIR/packages/linux-debian.txt"

log() { printf '==> %s\n' "$*"; }

if [[ "${1:-}" == "--dry-run" ]]; then
  log "[dry-run] Would run: sudo apt update"
  log "[dry-run] Would install: $(grep -v '^#' "$PACKAGES_FILE" | grep -v '^$' | tr '\n' ' ')"
  log "[dry-run] Would install watchexec via cargo if available"
  log "[dry-run] Would install or update yazi in ~/.local/bin"
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "bootstrap/linux-debian.sh requires apt (Debian/Ubuntu)." >&2
  exit 1
fi

mapfile -t PACKAGES < <(grep -v '^#' "$PACKAGES_FILE" | grep -v '^$')
log "Installing apt packages..."
sudo apt-get update
sudo apt-get install -y "${PACKAGES[@]}"

if command -v cargo >/dev/null 2>&1; then
  if ! command -v watchexec >/dev/null 2>&1; then
    log "Installing watchexec via cargo..."
    cargo install watchexec-cli
  fi
else
  log "cargo not found — skipping watchexec (install rustup to enable)"
fi

resolve_yazi_version() {
  if [[ -n "${YAZI_VERSION:-}" ]]; then
    printf '%s' "$YAZI_VERSION"
    return
  fi
  local tag=""
  if command -v jq >/dev/null 2>&1; then
    tag="$(curl -fsSL https://api.github.com/repos/sxyazi/yazi/releases/latest | jq -r '.tag_name // empty' 2>/dev/null || true)"
  fi
  tag="${tag#v}"
  if [[ -z "$tag" || "$tag" == "null" ]]; then
    tag="26.9.1"
  fi
  printf '%s' "$tag"
}

yazi_installed_version() {
  yazi --version 2>/dev/null | awk '/Version:/ { print $2; exit }'
}

install_or_update_yazi() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) YAZI_ARCH="x86_64" ;;
    aarch64) YAZI_ARCH="aarch64" ;;
    *)
      echo "Unsupported architecture for yazi: $ARCH" >&2
      exit 1
      ;;
  esac

  local wanted current
  wanted="$(resolve_yazi_version)"
  current="$(yazi_installed_version)"
  if command -v yazi >/dev/null 2>&1 && [[ -n "$current" && "$current" == "$wanted" ]]; then
    log "yazi $current already installed"
    return
  fi

  log "Installing yazi $wanted to ~/.local/bin (was: ${current:-missing})..."
  mkdir -p "$HOME/.local/bin"
  YAZI_URL="https://github.com/sxyazi/yazi/releases/download/v${wanted}/yazi-${YAZI_ARCH}-unknown-linux-musl.zip"

  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL "$YAZI_URL" -o "$tmpdir/yazi.zip"
  unzip -qo "$tmpdir/yazi.zip" -d "$tmpdir"
  install -m 755 "$tmpdir/yazi-${YAZI_ARCH}-unknown-linux-musl/yazi" "$HOME/.local/bin/yazi"
  rm -rf "$tmpdir"
  log "yazi installed to ~/.local/bin/yazi"
}

install_or_update_yazi

log "Linux bootstrap complete."
