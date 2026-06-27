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
  log "[dry-run] Would install yazi to ~/.local/bin if missing"
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
  log "cargo not found — install rustup or run with --with-rust (skipped watchexec)"
fi

if ! command -v yazi >/dev/null 2>&1; then
  log "Installing yazi to ~/.local/bin..."
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) YAZI_ARCH="x86_64" ;;
    aarch64) YAZI_ARCH="aarch64" ;;
    *)
      echo "Unsupported architecture for yazi: $ARCH" >&2
      exit 1
      ;;
  esac

  YAZI_VERSION="${YAZI_VERSION:-26.5.6}"
  YAZI_URL="https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-${YAZI_ARCH}-unknown-linux-musl.zip"

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  curl -fsSL "$YAZI_URL" -o "$TMPDIR/yazi.zip"
  unzip -qo "$TMPDIR/yazi.zip" -d "$TMPDIR"
  install -m 755 "$TMPDIR/yazi-${YAZI_ARCH}-unknown-linux-musl/yazi" "$HOME/.local/bin/yazi"
  log "yazi installed to ~/.local/bin/yazi"
fi

log "Linux bootstrap complete."
