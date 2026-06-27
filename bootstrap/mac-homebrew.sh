#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BREWFILE="$DOTFILES_DIR/packages/mac-brew.txt"

log() { printf '==> %s\n' "$*"; }

if [[ "${1:-}" == "--dry-run" ]]; then
  log "[dry-run] Would install Homebrew packages from $BREWFILE"
  log "[dry-run] Would install font-jetbrains-mono-nerd-font"
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

log "Installing brew packages..."
brew bundle install --file="$BREWFILE"

if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
  log "Installing JetBrainsMono Nerd Font..."
  brew install --cask font-jetbrains-mono-nerd-font
fi

log "macOS bootstrap complete."
