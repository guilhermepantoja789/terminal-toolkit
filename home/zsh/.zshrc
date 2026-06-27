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

export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
if [[ -f "$DOTFILES_DIR/lib/shell-common.sh" ]]; then
  source "$DOTFILES_DIR/lib/shell-common.sh"
  setup_prompt_zsh
fi
