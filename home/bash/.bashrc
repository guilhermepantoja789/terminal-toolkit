# Dotfiles — bash (Debian/Linux)

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
