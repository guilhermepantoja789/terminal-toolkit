#!/usr/bin/env bash
# Refresh CI dashboard repo list from GitHub (org repos with workflows > 0).
# Default: rewrite config/ci-status.env.example and ~/.config/ci-status.env.
# Existing REPOS order is kept; new repos are appended; gone repos are dropped.
set -euo pipefail

resolve_repo_root() {
  local src="${BASH_SOURCE[0]}"
  local dir
  while [[ -L "$src" ]]; do
    dir="$(cd "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  dir="$(cd "$(dirname "$src")/.." && pwd)"
  if [[ -f "$dir/config/ci-status.env.example" ]]; then
    printf '%s' "$dir"
    return
  fi
  if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-dir" ]]; then
    dir="$(tr -d '\n' <"${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles-dir")"
    if [[ -f "$dir/config/ci-status.env.example" ]]; then
      printf '%s' "$dir"
      return
    fi
  fi
  echo "Could not locate repo (config/ci-status.env.example)" >&2
  exit 1
}

REPO_ROOT="$(resolve_repo_root)"
EXAMPLE="$REPO_ROOT/config/ci-status.env.example"
LIVE="${CI_STATUS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ci-status.env}"

FROM_EXAMPLE=false
EXAMPLE_ONLY=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: sync-ci-repos [OPTIONS]

Update the view-actions repo list (ORG repos with GitHub Actions workflows).

Options:
  --from-example   Copy config/ci-status.env.example -> ~/.config/ci-status.env
  --example-only   Write the example file only (do not touch the live env)
  --dry-run        Print the repo list without writing files
  -h, --help       Show this help
EOF
}

log() { printf '==> %s\n' "$*"; }

is_in() {
  local needle=$1
  shift
  local x
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-example) FROM_EXAMPLE=true ;;
    --example-only) EXAMPLE_ONLY=true ;;
    --dry-run) DRY_RUN=true ;;
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

if [[ "$FROM_EXAMPLE" == true ]]; then
  if [[ ! -f "$EXAMPLE" ]]; then
    echo "Missing $EXAMPLE" >&2
    exit 1
  fi
  log "Copy example -> $LIVE"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] cp $EXAMPLE $LIVE"
    exit 0
  fi
  mkdir -p "$(dirname "$LIVE")"
  cp "$EXAMPLE" "$LIVE"
  log "Updated $LIVE"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "sync-ci-repos requires gh and jq" >&2
  exit 1
fi

ORG=""
EXISTING=()
if [[ -f "$EXAMPLE" ]]; then
  # shellcheck source=/dev/null
  source "$EXAMPLE"
  if declare -p REPOS >/dev/null 2>&1; then
    EXISTING=("${REPOS[@]}")
  fi
fi
if [[ -z "${ORG:-}" ]]; then
  echo "ORG not set — edit $EXAMPLE first" >&2
  exit 1
fi

log "Listing $ORG repos with GitHub Actions..."

with_wf=()
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  count="$(gh api "repos/$ORG/$name/actions/workflows" --jq '.total_count' 2>/dev/null || echo 0)"
  if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
    with_wf+=("$name")
  fi
done < <(gh repo list "$ORG" --limit 200 --json name,isArchived --jq '.[] | select(.isArchived|not) | .name' | sort)

if ((${#with_wf[@]} == 0)); then
  echo "No repos with workflows found for $ORG" >&2
  exit 1
fi

merged=()
if ((${#EXISTING[@]} > 0)); then
  for r in "${EXISTING[@]}"; do
    if is_in "$r" "${with_wf[@]}"; then
      merged+=("$r")
    fi
  done
fi
for r in "${with_wf[@]}"; do
  # Bash 3.2 + set -u: "${merged[@]}" is unbound when empty.
  if ((${#merged[@]} > 0)) && is_in "$r" "${merged[@]}"; then
    continue
  fi
  merged+=("$r")
done

write_env() {
  local dest=$1
  {
    echo "# Copy to ~/.config/ci-status.env and customize."
    echo "# install.sh creates ~/.config/ci-status.env from this file on first run."
    echo "# Só repos ${ORG} com GitHub Actions (workflows > 0)."
    echo "# Atualize com: sync-ci-repos"
    echo
    echo "ORG=${ORG}"
    echo "REPOS=("
    local i=0
    local line=""
    local r
    for r in "${merged[@]}"; do
      if [[ -z "$line" ]]; then
        line="$r"
      else
        line+=" $r"
      fi
      i=$((i + 1))
      if (( i % 4 == 0 )); then
        printf '  %s\n' "$line"
        line=""
      fi
    done
    if [[ -n "$line" ]]; then
      printf '  %s\n' "$line"
    fi
    echo ")"
  } >"$dest"
}

log "Repos (${#merged[@]}): ${merged[*]}"

if [[ "$DRY_RUN" == true ]]; then
  log "[dry-run] would write $EXAMPLE"
  if [[ "$EXAMPLE_ONLY" != true ]]; then
    log "[dry-run] would write $LIVE"
  fi
  exit 0
fi

write_env "$EXAMPLE"
log "Updated $EXAMPLE"

if [[ "$EXAMPLE_ONLY" != true ]]; then
  mkdir -p "$(dirname "$LIVE")"
  write_env "$LIVE"
  log "Updated $LIVE"
fi
