# Shared shell setup for bash and zsh (sourced from dotfiles).

: "${DOTFILES_DIR:=$HOME/dotfiles}"

export PATH="$HOME/.local/bin:$HOME/.config/composer/vendor/bin:$PATH"
export EDITOR="micro"
export VISUAL="micro"

# Optional runtimes (no-op if not installed)
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
export NVM_DIR="$HOME/.config/nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
if [[ -n "${BASH_VERSION:-}" && -s "$NVM_DIR/bash_completion" ]]; then
  . "$NVM_DIR/bash_completion"
fi

parse_git_branch() {
  git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

# SSH_CONNECTION: client_ip client_port server_ip server_port
# Prefer server IP (host you landed on); fall back to client IP from SSH_CLIENT.
# Portable across bash and zsh (zsh does not split unquoted words by default).
ssh_connection_ip() {
  local ip="" rest
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    rest="${SSH_CONNECTION}"
    # skip client_ip
    rest="${rest#* }"
    # skip client_port
    rest="${rest#* }"
    # server_ip is next field
    ip="${rest%% *}"
  elif [[ -n "${SSH_CLIENT:-}" ]]; then
    ip="${SSH_CLIENT%% *}"
  fi
  printf '%s' "$ip"
}

if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]]; then
  export SSH_SESSION=yes
  SSH_REMOTE_IP="$(ssh_connection_ip)"
  export SSH_REMOTE_IP
else
  export SSH_SESSION=no
  SSH_REMOTE_IP=""
  export SSH_REMOTE_IP
fi

y() {
  local tmp
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

mdwatch() {
  if [[ -z "${1:-}" ]]; then
    echo "Erro: Você precisa informar o arquivo."
    echo "Uso: mdwatch <arquivo.md>"
    return 1
  fi

  local theme cols
  theme="${XDG_CONFIG_HOME:-$HOME/.config}/glow/tema-flow.json"
  cols="$(tput cols 2>/dev/null || echo 80)"
  # Pass args after -- so filenames with spaces/quotes are safe.
  watchexec -c -e md -- env CLICOLOR_FORCE=1 glow -s "$theme" -w "$cols" "$1"
}

alias view-actions='watch -c -n 15 -- "$HOME/.local/bin/ci-status"'

setup_prompt_bash() {
  local COLOR_USER="\[\e[93m\]"
  local COLOR_DIR="\[\e[35m\]"
  local COLOR_GIT="\[\e[31m\]"
  local COLOR_RESET="\[\e[0m\]"
  local COLOR_SSH="\[\e[33m\]"
  local ssh_indicator=""

  if [[ "$SSH_SESSION" == "yes" ]]; then
    if [[ -n "${SSH_REMOTE_IP:-}" ]]; then
      ssh_indicator="${COLOR_SSH}[SSH ${SSH_REMOTE_IP}]${COLOR_RESET} "
    else
      ssh_indicator="${COLOR_SSH}[SSH]${COLOR_RESET} "
    fi
  fi

  PS1="${ssh_indicator}${COLOR_USER}\u${COLOR_RESET}:${COLOR_DIR}\W${COLOR_RESET}${COLOR_GIT}\$(parse_git_branch)${COLOR_RESET} \$ "
}

setup_prompt_zsh() {
  autoload -Uz colors && colors
  setopt PROMPT_SUBST

  zssh_indicator=""
  if [[ "$SSH_SESSION" == "yes" ]]; then
    if [[ -n "${SSH_REMOTE_IP:-}" ]]; then
      zssh_indicator="%F{yellow}[SSH ${SSH_REMOTE_IP}]%f "
    else
      zssh_indicator='%F{yellow}[SSH]%f '
    fi
  fi

  # Username: bright yellow (pairs with Phanes gold accents)
  PROMPT="${zssh_indicator}%F{11}%n%f:%F{magenta}%1~%f%F{red}\$(parse_git_branch)%f \$ "
}
