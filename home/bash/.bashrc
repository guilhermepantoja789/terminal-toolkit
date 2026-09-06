# Dotfiles — bash (Debian/Linux)

# PATH before the interactive-only return so `debian` / `vm` work in bash -c too.
export PATH="$HOME/.local/bin:$PATH"

case $- in
  *i*) ;;
  *) return ;;
esac

HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

if [[ -z "${debian_chroot:-}" && -r /etc/debian_chroot ]]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

if [[ -x /usr/bin/dircolors ]]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

if [[ -f ~/.bash_aliases ]]; then
  . ~/.bash_aliases
fi

if ! shopt -oq posix; then
  if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    . /usr/share/bash-completion/bash_completion
  elif [[ -f /etc/bash_completion ]]; then
    . /etc/bash_completion
  fi
fi

# Resolve repo root: valid env → install pin → this symlink (stow) → ~/dotfiles
if [[ -n "${DOTFILES_DIR:-}" && ! -f "$DOTFILES_DIR/lib/shell-common.sh" ]]; then
  unset DOTFILES_DIR
fi
if [[ -z "${DOTFILES_DIR:-}" && -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-dir" ]]; then
  DOTFILES_DIR="$(tr -d '\n' <"${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-dir")"
fi
if [[ -z "${DOTFILES_DIR:-}" || ! -f "${DOTFILES_DIR}/lib/shell-common.sh" ]]; then
  _dotfiles_bashrc="${BASH_SOURCE[0]:-$HOME/.bashrc}"
  if [[ -L "$_dotfiles_bashrc" ]]; then
    _dotfiles_real="$(readlink -f "$_dotfiles_bashrc" 2>/dev/null || true)"
    if [[ -n "$_dotfiles_real" && -f "$(dirname "$_dotfiles_real")/../../lib/shell-common.sh" ]]; then
      DOTFILES_DIR="$(cd "$(dirname "$_dotfiles_real")/../.." && pwd)"
    fi
  fi
  unset _dotfiles_bashrc _dotfiles_real
fi
export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

if [[ -f "$DOTFILES_DIR/lib/shell-common.sh" ]]; then
  # shellcheck source=/dev/null
  . "$DOTFILES_DIR/lib/shell-common.sh"
  setup_prompt_bash
fi

# Machine-local overrides — not versioned
if [[ -f ~/.bashrc.local ]]; then
  # shellcheck source=/dev/null
  . ~/.bashrc.local
fi

# Flow Sistemas — flowctl
alias flowctl='/home/guilhermepantoja/Projects/flow-sistemas/flow-ops/bin/flowctl'
