alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

# Kitty only — Tabby/other terminals use normal ssh
if [[ -n "${KITTY_WINDOW_ID:-}" ]] && command -v kitten >/dev/null 2>&1; then
  alias ssh='kitten ssh'
fi

alias hs='history 1000 | grep'
