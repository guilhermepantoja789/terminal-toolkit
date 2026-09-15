#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "${DOTFILES_DIR:-$SCRIPT_DIR}" && pwd)"
HOME_DIR="$HOME"
CONFIG_ONLY=false
REFRESH_CI_CONFIG=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  --configs-only        Symlink configs only (skip package bootstrap)
  --skip-packages       Alias for --configs-only
  --refresh-ci-config   Replace ~/.config/ci-status.env from the example
  --dry-run             Preview actions without changing the system
  -h, --help            Show this help

Environment:
  DOTFILES_DIR          Override dotfiles location (default: this script's repo)
EOF
}

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configs-only|--skip-packages)
      CONFIG_ONLY=true
      ;;
    --refresh-ci-config)
      REFRESH_CI_CONFIG=true
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

# Glow on macOS may still read ~/Library/Preferences/glow/glow.yml (width: 80)
# even when ~/.config/glow is stowed. Neutralize that pin so mdwatch can wrap to TTY size.
fix_macos_glow_prefs() {
  [[ "$OS" != "macos" ]] && return

  local prefs="$HOME_DIR/Library/Preferences/glow/glow.yml"
  [[ -f "$prefs" ]] || return

  if grep -qE '^[[:space:]]*width:[[:space:]]*80[[:space:]]*$' "$prefs" 2>/dev/null; then
    log "Unpin glow width in ~/Library/Preferences/glow/glow.yml (was 80)"
    if [[ "$DRY_RUN" == true ]]; then
      log "[dry-run] set width: 0 in $prefs"
      return
    fi
    local tmp
    tmp="$(mktemp)"
    sed 's/^[[:space:]]*width:[[:space:]]*80[[:space:]]*$/width: 0/' "$prefs" >"$tmp"
    mv "$tmp" "$prefs"
  fi
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

link_bin_scripts() {
  local src name link
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] link bin/*.sh -> ~/.local/bin"
    return
  fi

  mkdir -p "$HOME_DIR/.local/bin"
  for src in "$DOTFILES_DIR"/bin/*.sh; do
    [[ -f "$src" ]] || continue
    name="$(basename "$src" .sh)"
    link="$HOME_DIR/.local/bin/$name"
    log "Link $name -> ~/.local/bin/$name"
    ln -sf "$src" "$link"
    chmod +x "$src"
  done
}

install_ci_config() {
  local example="$DOTFILES_DIR/config/ci-status.env.example"
  local dest="$HOME_DIR/.config/ci-status.env"

  if [[ -f "$dest" && "$REFRESH_CI_CONFIG" != true ]]; then
    log "Keeping existing ~/.config/ci-status.env (use --refresh-ci-config or sync-ci-repos)"
    return
  fi

  if [[ "$REFRESH_CI_CONFIG" == true && -f "$dest" ]]; then
    log "Refreshing ~/.config/ci-status.env from example"
  else
    log "Creating ~/.config/ci-status.env from example"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] cp $example $dest"
    return
  fi

  mkdir -p "$HOME_DIR/.config"
  cp "$example" "$dest"
}

install_local_shell_overrides() {
  local example dest
  if [[ "$OS" == "linux" ]]; then
    example="$DOTFILES_DIR/config/bashrc.local.example"
    dest="$HOME_DIR/.bashrc.local"
  else
    example="$DOTFILES_DIR/config/zshrc.local.example"
    dest="$HOME_DIR/.zshrc.local"
  fi

  [[ -f "$example" ]] || return 0
  if [[ -f "$dest" ]]; then
    log "Keeping existing $dest"
    return
  fi

  log "Creating $dest from example"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] cp $example $dest"
    return
  fi
  cp "$example" "$dest"
}

pin_dotfiles_dir() {
  # Persist absolute repo path so shells work even when the repo is not at ~/dotfiles.
  local pin="$HOME_DIR/.config/dotfiles-dir"

  log "Pin DOTFILES_DIR -> ~/.config/dotfiles-dir"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] write $DOTFILES_DIR to $pin"
    return
  fi

  mkdir -p "$HOME_DIR/.config"
  printf '%s\n' "$DOTFILES_DIR" >"$pin"
}

setup_mac_zprofile() {
  [[ "$OS" != "macos" ]] && return

  local marker="# dotfiles zsh"
  local zprofile="$HOME_DIR/.zprofile"

  if [[ -f "$zprofile" ]] && grep -qF "$marker" "$zprofile"; then
    # Keep pin in sync when re-installing from a moved checkout.
    if grep -qF 'export DOTFILES_DIR=' "$zprofile"; then
      if [[ "$DRY_RUN" == true ]]; then
        log "[dry-run] refresh DOTFILES_DIR in ~/.zprofile"
      else
        # portable in-place refresh of the export line
        local tmp
        tmp="$(mktemp)"
        sed "s|^export DOTFILES_DIR=.*|export DOTFILES_DIR=\"$DOTFILES_DIR\"|" "$zprofile" >"$tmp"
        mv "$tmp" "$zprofile"
      fi
    fi
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
     (refresh list: sync-ci-repos   or   ./install.sh --refresh-ci-config)
  4. Open Tabby (macOS) or kitty (Linux) and confirm JetBrainsMono Nerd Font

Custom commands:
  y              — yazi file manager (cd on quit)
  mdwatch FILE    — live markdown preview with glow
  view-actions   — watch GitHub Actions dashboard
  sync-ci-repos  — refresh CI repo list from GitHub

Split shortcuts (kitty / Tabby):
  Ctrl+Shift+E   — vertical split
  Ctrl+Shift+O   — horizontal split
  Ctrl+Shift+W   — close split
  Alt+arrows     — navigate splits

Update workflow:
  cd \"\$DOTFILES_DIR\" && git pull && ./install.sh --configs-only
  source ~/.bashrc   (Linux)  or  source ~/.zshrc   (macOS)
  # packages + yazi binary: ./install.sh
EOF
}

main() {
  log "Detected OS: $OS"
  log "Dotfiles dir: $DOTFILES_DIR"

  if [[ ! -f "$DOTFILES_DIR/lib/shell-common.sh" ]]; then
    echo "DOTFILES_DIR is not this repo: $DOTFILES_DIR" >&2
    exit 1
  fi

  if ! command -v stow >/dev/null 2>&1 && [[ "$DRY_RUN" != true ]]; then
    warn "GNU stow not found — bootstrap will install it"
  fi

  run_bootstrap
  prepare_stow_targets
  stow_packages
  link_tabby_config
  fix_macos_glow_prefs
  link_bin_scripts
  install_ci_config
  install_local_shell_overrides
  pin_dotfiles_dir
  setup_mac_zprofile

  if [[ "$DRY_RUN" == true ]]; then
    log "Dry run complete — no changes made."
  else
    print_post_install
  fi
}

main "$@"
