#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR"
HOME_DIR="$HOME"
CONFIG_ONLY=false
SKIP_PACKAGES=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  --configs-only   Symlink configs only (skip package bootstrap)
  --skip-packages  Alias for --configs-only
  --dry-run        Preview actions without changing the system
  -h, --help       Show this help

Environment:
  DOTFILES_DIR     Override dotfiles location (default: repo root)
EOF
}

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configs-only|--skip-packages)
      CONFIG_ONLY=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

detect_os() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo macos ;;
    *)
      echo "unsupported"
      ;;
  esac
}

OS="$(detect_os)"
if [[ "$OS" == "unsupported" ]]; then
  echo "Unsupported OS: $(uname -s)" >&2
  exit 1
fi

run_bootstrap() {
  if [[ "$CONFIG_ONLY" == true ]]; then
    log "Skipping package bootstrap (--configs-only)"
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    case "$OS" in
      linux) bash "$DOTFILES_DIR/bootstrap/linux-debian.sh" --dry-run ;;
      macos) bash "$DOTFILES_DIR/bootstrap/mac-homebrew.sh" --dry-run ;;
    esac
    return
  fi

  case "$OS" in
    linux) bash "$DOTFILES_DIR/bootstrap/linux-debian.sh" ;;
    macos) bash "$DOTFILES_DIR/bootstrap/mac-homebrew.sh" ;;
  esac
}

backup_if_regular_file() {
  local target=$1
  if [[ -e "$target" && ! -L "$target" ]]; then
    local backup="${target}.bak-pre-dotfiles"
    if [[ "$DRY_RUN" == true ]]; then
      log "[dry-run] backup $target -> $backup"
    else
      log "Backing up $target -> $backup"
      mv "$target" "$backup"
    fi
  fi
}

prepare_stow_targets() {
  backup_if_regular_file "$HOME_DIR/.bashrc"
  backup_if_regular_file "$HOME_DIR/.bash_aliases"
  backup_if_regular_file "$HOME_DIR/.zshrc"
  backup_if_regular_file "$HOME_DIR/.zsh_aliases"
  backup_if_regular_file "$HOME_DIR/.gitconfig"

  local cfg
  for cfg in yazi micro kitty glow tabby; do
    backup_if_regular_file "$HOME_DIR/.config/$cfg"
  done
}

link_tabby_config() {
  # Tabby on macOS reads ~/Library/Application Support/tabby/config.yaml
  # (Linux uses ~/.config/tabby via stow).
  [[ "$OS" != "macos" ]] && return

  local src="$DOTFILES_DIR/home/config/tabby/config.yaml"
  local dest_dir="$HOME_DIR/Library/Application Support/tabby"
  local dest="$dest_dir/config.yaml"

  if [[ ! -f "$src" ]]; then
    warn "Tabby config missing at $src — skipping"
    return
  fi

  log "Link Tabby config -> ~/Library/Application Support/tabby/config.yaml"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] ln -sf $src $dest"
    return
  fi

  mkdir -p "$dest_dir"
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    local backup="${dest}.bak-pre-dotfiles"
    log "Backing up $dest -> $backup"
    mv "$dest" "$backup"
  fi
  ln -sf "$src" "$dest"
}

stow_packages() {
  if ! command -v stow >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == true ]]; then
      log "[dry-run] stow not installed — would run stow after bootstrap"
      return
    fi
    echo "GNU stow is required but not installed." >&2
    exit 1
  fi

  local pkg
  for pkg in bash zsh git; do
    if [[ -d "$DOTFILES_DIR/home/$pkg" ]]; then
      if [[ "$OS" == "macos" && "$pkg" == "bash" ]]; then
        continue
      fi
      if [[ "$OS" == "linux" && "$pkg" == "zsh" ]]; then
        continue
      fi
      log "stow $pkg -> ~"
      if [[ "$DRY_RUN" == true ]]; then
        stow -n -v -t "$HOME_DIR" -d "$DOTFILES_DIR/home" "$pkg"
      else
        stow -v -t "$HOME_DIR" -d "$DOTFILES_DIR/home" "$pkg"
      fi
    fi
  done

  log "stow config -> ~/.config"
  if [[ "$DRY_RUN" == true ]]; then
    stow -n -v -t "$HOME_DIR/.config" -d "$DOTFILES_DIR/home" config
  else
    mkdir -p "$HOME_DIR/.config"
    stow -v -t "$HOME_DIR/.config" -d "$DOTFILES_DIR/home" config
  fi
}

link_ci_status() {
  local target="$DOTFILES_DIR/bin/ci-status.sh"
  local link="$HOME_DIR/.local/bin/ci-status"

  log "Link ci-status -> ~/.local/bin/ci-status"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] ln -sf $target $link"
    return
  fi

  mkdir -p "$HOME_DIR/.local/bin"
  ln -sf "$target" "$link"
  chmod +x "$target"
}

install_ci_config() {
  local example="$DOTFILES_DIR/config/ci-status.env.example"
  local dest="$HOME_DIR/.config/ci-status.env"

  if [[ -f "$dest" ]]; then
    log "Keeping existing ~/.config/ci-status.env"
    return
  fi

  log "Creating ~/.config/ci-status.env from example"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] cp $example $dest"
    return
  fi

  mkdir -p "$HOME_DIR/.config"
  cp "$example" "$dest"
}

setup_mac_zprofile() {
  [[ "$OS" != "macos" ]] && return

  local marker="# dotfiles zsh"
  local zprofile="$HOME_DIR/.zprofile"

  if [[ -f "$zprofile" ]] && grep -qF "$marker" "$zprofile"; then
    return
  fi

  log "Adding ~/.zprofile for zsh"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] append zsh login config to ~/.zprofile"
    return
  fi

  cat >>"$zprofile" <<EOF

$marker
export DOTFILES_DIR="$DOTFILES_DIR"
[[ -f "\$HOME/.zshrc" ]] && source "\$HOME/.zshrc"
EOF
}

print_post_install() {
  cat <<EOF

Dotfiles installed from: $DOTFILES_DIR

Next steps:
  1. Reload shell:  source ~/.bashrc   (Linux)  or  source ~/.zshrc   (macOS)
  2. Authenticate GitHub CLI:  gh auth login
  3. Customize CI dashboard:  ~/.config/ci-status.env
  4. Open Tabby (macOS) or kitty (Linux) and confirm JetBrainsMono Nerd Font

Custom commands:
  y              — yazi file manager (cd on quit)
  mdwatch FILE    — live markdown preview with glow
  view-actions   — watch GitHub Actions dashboard

Split shortcuts (kitty / Tabby):
  Ctrl+Shift+E   — vertical split
  Ctrl+Shift+O   — horizontal split
  Ctrl+Shift+W   — close split
  Alt+arrows     — navigate splits

Update workflow:
  cd ~/dotfiles && git pull && ./install.sh --configs-only
EOF
}

main() {
  log "Detected OS: $OS"
  log "Dotfiles dir: $DOTFILES_DIR"

  if ! command -v stow >/dev/null 2>&1 && [[ "$DRY_RUN" != true ]]; then
    warn "GNU stow not found — bootstrap will install it"
  fi

  run_bootstrap
  prepare_stow_targets
  stow_packages
  link_tabby_config
  link_ci_status
  install_ci_config
  setup_mac_zprofile

  if [[ "$DRY_RUN" == true ]]; then
    log "Dry run complete — no changes made."
  else
    print_post_install
  fi
}

main "$@"
