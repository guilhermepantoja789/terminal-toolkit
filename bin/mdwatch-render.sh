#!/usr/bin/env sh
# One-shot glow render for mdwatch. Reads live TTY width so wrap tracks the window.
set -eu

theme=${1:-}
file=${2:-}
if [ -z "$file" ]; then
  echo "Uso: mdwatch-render <tema.json> <arquivo.md>" >&2
  exit 1
fi

cols=
{ cols=$(stty size < /dev/tty | awk '{print $2}'); } 2>/dev/null || true
case "$cols" in
  ''|0|*[!0-9]*) cols=$(tput cols 2>/dev/null) || true ;;
esac
case "$cols" in
  ''|0|*[!0-9]*) cols=${COLUMNS:-80} ;;
esac

if [ -n "$theme" ] && [ -f "$theme" ]; then
  CLICOLOR_FORCE=1 exec glow -s "$theme" -w "$cols" "$file"
fi
CLICOLOR_FORCE=1 exec glow -w "$cols" "$file"
