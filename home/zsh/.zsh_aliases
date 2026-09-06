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

# VMs (libvirt/KVM) — CLI em ~/Projects/virtual-machines
alias vm='$HOME/Projects/virtual-machines/bin/vm'

# Debian 13 limpo (headless, só SSH)
alias debian='vm ssh debian'
alias debian-on='vm start debian'
alias debian-off='vm stop debian'
alias debian-status='vm status debian'

# Windows CI / Tauri
alias vm-on='vm start build-vm'
alias vm-off='vm stop build-vm'
alias vm-status='vm status build-vm'
