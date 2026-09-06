# Dotfiles — zsh (macOS default)

[[ -o interactive ]] || return

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY

if [[ -f ~/.zsh_aliases ]]; then
  source ~/.zsh_aliases
fi

# Resolve repo root: valid env → install pin → this symlink (stow) → ~/dotfiles
if [[ -n "${DOTFILES_DIR:-}" && ! -f "$DOTFILES_DIR/lib/shell-common.sh" ]]; then
  unset DOTFILES_DIR
fi
if [[ -z "${DOTFILES_DIR:-}" && -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-dir" ]]; then
  DOTFILES_DIR="$(tr -d '\n' <"${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-dir")"
fi
if [[ -z "${DOTFILES_DIR:-}" || ! -f "${DOTFILES_DIR}/lib/shell-common.sh" ]]; then
  _dotfiles_zshrc="${ZDOTDIR:-$HOME}/.zshrc"
  if [[ -L "$_dotfiles_zshrc" ]]; then
    _dotfiles_real="${_dotfiles_zshrc:A}"
    if [[ -n "$_dotfiles_real" && -f "${_dotfiles_real:h}/../../lib/shell-common.sh" ]]; then
      DOTFILES_DIR="${_dotfiles_real:h}/../.."
      DOTFILES_DIR="${DOTFILES_DIR:A}"
    fi
  fi
  unset _dotfiles_zshrc _dotfiles_real
fi
export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

if [[ -f "$DOTFILES_DIR/lib/shell-common.sh" ]]; then
  source "$DOTFILES_DIR/lib/shell-common.sh"
  setup_prompt_zsh
fi

# Machine-local overrides (Herd, libpq, etc.) — not versioned
if [[ -f ~/.zshrc.local ]]; then
  source ~/.zshrc.local
fi
