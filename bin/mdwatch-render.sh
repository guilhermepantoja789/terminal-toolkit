#!/usr/bin/env sh
# One-shot glow render for mdwatch. Reads live TTY width so wrap tracks the window.
# Under watchexec, /dev/tty is often wrong — pass the invoking terminal as $3.
set -eu

theme=${1:-}
file=${2:-}
tty_dev=${3:-}
if [ -z "$file" ]; then
  echo "Uso: mdwatch-render <tema.json> <arquivo.md> [tty]" >&2
  exit 1
fi

cols=
if [ -n "$tty_dev" ] && [ -r "$tty_dev" ]; then
  { cols=$(stty size < "$tty_dev" | awk '{print $2}'); } 2>/dev/null || true
fi
case "$cols" in
  ''|0|*[!0-9]*) { cols=$(stty size < /dev/tty | awk '{print $2}'); } 2>/dev/null || true ;;
esac
case "$cols" in
  ''|0|*[!0-9]*) cols=$(tput cols 2>/dev/null) || true ;;
esac
case "$cols" in
  ''|0|*[!0-9]*)
    case "${COLUMNS:-}" in
      ''|0|*[!0-9]*) cols=80 ;;
      *) cols=$COLUMNS ;;
    esac
    ;;
esac

if [ -n "$theme" ] && [ -f "$theme" ]; then
  CLICOLOR_FORCE=1 exec glow -s "$theme" -w "$cols" "$file"
fi
CLICOLOR_FORCE=1 exec glow -w "$cols" "$file"
