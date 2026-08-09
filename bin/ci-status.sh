#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CI_STATUS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ci-status.env}"
if [[ -f "$CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG"
fi

# Bash 3.2 + set -u: unset REPOS would abort on ${#REPOS[@]}.
if [[ -z "${ORG:-}" ]] || ! declare -p REPOS >/dev/null 2>&1 || [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "ORG/REPOS not configured — copy config/ci-status.env.example to ~/.config/ci-status.env" >&2
  exit 1
fi

# ANSI colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_GREEN='\033[32m'
C_RED='\033[31m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_GRAY='\033[90m'

GH_JSON_FIELDS='status,conclusion,displayTitle,url,workflowName,headBranch,startedAt,updatedAt,createdAt,event'

# Fixed widths (visible chars) — avoids BSD/GNU `column` miscounting ANSI escapes.
W_REPO=22
W_STATUS=14
W_BRANCH=18
W_DURATION=8
W_STARTED=11
W_WORKFLOW=26

_date_cmd() {
  if command -v gdate >/dev/null 2>&1; then
    echo gdate
  else
    echo date
  fi
}

to_epoch() {
  local ts=$1
  [[ -z "$ts" || "$ts" == "null" ]] && return 1

  local dcmd
  dcmd=$(_date_cmd)

  if [[ "$dcmd" == "gdate" ]]; then
    gdate -d "$ts" +%s 2>/dev/null && return 0
  fi

  # GNU date
  if date -d "@0" +%s >/dev/null 2>&1; then
    date -d "$ts" +%s 2>/dev/null && return 0
  fi

  # BSD date (macOS): strip fractional seconds and trailing Z
  local normalized="${ts%%.*}"
  normalized="${normalized%Z}"
  date -j -f "%Y-%m-%dT%H:%M:%S" "$normalized" +%s 2>/dev/null
}

fmt_started() {
  local ts=$1
  local epoch
  epoch=$(to_epoch "$ts") || { printf '—'; return 0; }

  local dcmd
  dcmd=$(_date_cmd)

  if [[ "$dcmd" == "gdate" ]]; then
    gdate -d "@$epoch" '+%d/%m %H:%M' 2>/dev/null && return 0
  fi

  if date -d "@0" +%s >/dev/null 2>&1; then
    date -d "@$epoch" '+%d/%m %H:%M' 2>/dev/null && return 0
  fi

  # BSD date
  date -r "$epoch" '+%d/%m %H:%M' 2>/dev/null || printf '—'
}

fmt_duration() {
  local s=$1
  if (( s < 0 )); then s=0; fi
  if (( s < 60 )); then
    printf '%ds' "$s"
  elif (( s < 3600 )); then
    printf '%dm %02ds' $((s / 60)) $((s % 60))
  else
    printf '%dh %02dm' $((s / 3600)) $(((s % 3600) / 60))
  fi
}

run_duration_secs() {
  local status=$1 started=$2 updated=$3
  local start_epoch end_epoch now

  start_epoch=$(to_epoch "$started") || return 1

  case "$status" in
    in_progress|requested|waiting|pending|queued)
      now=$(date +%s)
      echo $((now - start_epoch))
      ;;
    *)
      end_epoch=$(to_epoch "$updated") || return 1
      echo $((end_epoch - start_epoch))
      ;;
  esac
}

status_priority() {
  local status=$1 conclusion=$2
  case "$status" in
    in_progress|requested|waiting|pending) echo 0 ;;
    queued) echo 1 ;;
    completed)
      case "$conclusion" in
        failure|cancelled|timed_out|startup_failure|action_required) echo 2 ;;
        success) echo 3 ;;
        *) echo 4 ;;
      esac
      ;;
    *) echo 5 ;;
  esac
}

# Prints: icon<TAB>label<TAB>color_code (no reset)
status_parts() {
  local status=$1 conclusion=$2
  local icon label color

  case "$status" in
    in_progress|requested|waiting|pending)
      icon='⟳'; label='em execução'; color=$C_YELLOW ;;
    queued)
      icon='○'; label='na fila'; color=$C_BLUE ;;
    completed)
      case "$conclusion" in
        success)
          icon='✓'; label='sucesso'; color=$C_GREEN ;;
        failure|startup_failure)
          icon='✗'; label='falha'; color=$C_RED ;;
        cancelled)
          icon='—'; label='cancelada'; color=$C_GRAY ;;
        timed_out)
          icon='✗'; label='timeout'; color=$C_RED ;;
        skipped)
          icon='—'; label='ignorada'; color=$C_GRAY ;;
        *)
          icon='·'; label="${conclusion:-concluída}"; color=$C_DIM ;;
      esac
      ;;
    *)
      icon='?'; label="${status:-?}"; color=$C_DIM ;;
  esac

  printf '%s\t%s\t%s' "$icon" "$label" "$color"
}

truncate_str() {
  local str=$1 max=$2
  if ((${#str} > max)); then
    printf '%s…' "${str:0:$((max - 1))}"
  else
    printf '%s' "$str"
  fi
}

# Pad/truncate to exact visible width (no ANSI).
pad_field() {
  local str=$1 width=$2
  str=$(truncate_str "$str" "$width")
  printf '%-*s' "$width" "$str"
}

fetch_repo() {
  local repo=$1 out=$2
  local json duration_secs duration_str started_str

  json=$(gh run list -R "$ORG/$repo" -L 1 \
    --json "$GH_JSON_FIELDS" 2>/dev/null || true)

  if [[ -z "$json" || "$json" == "[]" || "$json" == "null" ]]; then
    jq -n --arg repo "$repo" '{repo: $repo, empty: true}' >"$out"
    return 0
  fi

  local run
  run=$(jq -c '.[0]' <<<"$json" 2>/dev/null || true)

  if [[ -z "$run" || "$run" == "null" ]]; then
    jq -n --arg repo "$repo" '{repo: $repo, empty: true}' >"$out"
    return 0
  fi

  local status conclusion started updated created
  status=$(jq -r '.status // ""' <<<"$run")
  conclusion=$(jq -r '.conclusion // ""' <<<"$run")
  started=$(jq -r '.startedAt // ""' <<<"$run")
  updated=$(jq -r '.updatedAt // ""' <<<"$run")
  created=$(jq -r '.createdAt // ""' <<<"$run")

  # GitHub often leaves startedAt null while queued; fall back to createdAt.
  if [[ -z "$started" || "$started" == "null" ]]; then
    started=$created
  fi

  duration_secs="-"
  duration_str="—"
  if duration_secs=$(run_duration_secs "$status" "$started" "$updated" 2>/dev/null); then
    duration_str=$(fmt_duration "$duration_secs")
  else
    duration_secs="-"
  fi

  started_str=$(fmt_started "$started")

  jq -c \
    --arg repo "$repo" \
    --arg duration_str "$duration_str" \
    --arg duration_secs "$duration_secs" \
    --arg started_str "$started_str" \
    --arg priority "$(status_priority "$status" "$conclusion")" \
    '. + {
      repo: $repo,
      empty: false,
      duration_str: $duration_str,
      duration_secs: $duration_secs,
      started_str: $started_str,
      priority: ($priority | tonumber)
    }' <<<"$run" >"$out"
}

print_header() {
  local now pad
  now=$(date '+%H:%M:%S')
  printf '%bGitHub Actions — %s%b' "$C_BOLD" "$ORG" "$C_RESET"
  pad=$((60 - ${#ORG} - 18))
  if (( pad < 1 )); then pad=1; fi
  printf '%*s' "$pad" ''
  printf '%bAtualizado: %s%b\n' "$C_DIM" "$now" "$C_RESET"
  printf '%b' "$C_DIM"
  printf '─%.0s' {1..80}
  printf '%b\n' "$C_RESET"
}

print_summary_line() {
  local running=$1 success=$2 failed=$3 queued=$4 empty=$5
  local parts=()

  (( running > 0 )) && parts+=("${C_YELLOW}⟳ ${running} em execução${C_RESET}")
  (( success > 0 )) && parts+=("${C_GREEN}✓ ${success} ok${C_RESET}")
  (( failed > 0 )) && parts+=("${C_RED}✗ ${failed} falha${C_RESET}")
  (( queued > 0 )) && parts+=("${C_BLUE}○ ${queued} na fila${C_RESET}")
  (( empty > 0 )) && parts+=("${C_GRAY}— ${empty} sem runs${C_RESET}")

  if ((${#parts[@]} == 0)); then
    echo "  (nenhum dado)"
    return
  fi

  local joined=""
  local part
  for part in "${parts[@]}"; do
    if [[ -n "$joined" ]]; then joined+="   "; fi
    joined+="$part"
  done
  printf '  %b\n' "$joined"
}

print_footer() {
  local running_count=$1 longest_running=$2 completed_count=$3 avg_completed=$4
  printf '\n%b' "$C_DIM"
  printf '─%.0s' {1..80}
  printf '%b\n' "$C_RESET"

  if (( running_count > 0 )); then
    printf 'Em execução: %b%d runs%b' "$C_YELLOW" "$running_count" "$C_RESET"
    if [[ "$longest_running" != "-" ]]; then
      printf ' (mais longa: %s)' "$(fmt_duration "$longest_running")"
    fi
  else
    printf 'Em execução: %b0 runs%b' "$C_DIM" "$C_RESET"
  fi

  if (( completed_count > 0 )); then
    printf '   Média concluídas: %s' "$(fmt_duration "$avg_completed")"
  fi
  echo
}

print_table_header() {
  printf '%b%s  %s  %s  %s  %s  %s%b\n' \
    "$C_DIM" \
    "$(pad_field "REPO" "$W_REPO")" \
    "$(pad_field "STATUS" "$W_STATUS")" \
    "$(pad_field "BRANCH" "$W_BRANCH")" \
    "$(pad_field "DURAÇÃO" "$W_DURATION")" \
    "$(pad_field "INÍCIO" "$W_STARTED")" \
    "$(pad_field "WORKFLOW" "$W_WORKFLOW")" \
    "$C_RESET"
}

# Pad the plain label to fixed width, then wrap ANSI color.
format_status_col() {
  local status=$1 conclusion=$2
  local icon label color plain padded
  IFS=$'\t' read -r icon label color <<<"$(status_parts "$status" "$conclusion")"
  plain="$icon $label"
  padded=$(pad_field "$plain" "$W_STATUS")
  printf '%b%s%b' "$color" "$padded" "$C_RESET"
}

main() {
  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  local repo
  for repo in "${REPOS[@]}"; do
    fetch_repo "$repo" "$tmpdir/$repo" &
  done
  # set -e: a single failed fetch must not abort the dashboard.
  wait || true

  local rows=()
  local running=0 success=0 failed=0 queued=0 empty=0
  local longest_running=0 completed_total=0 completed_count=0

  for repo in "${REPOS[@]}"; do
    local file="$tmpdir/$repo"
    [[ -f "$file" ]] || continue

    local data
    data=$(<"$file")
    [[ -n "$data" ]] || continue

    if [[ "$(jq -r '.empty // false' <<<"$data")" == "true" ]]; then
      ((empty++)) || true
      rows+=("$(jq -c '{priority: 5, repo, empty: true}' <<<"$data")")
      continue
    fi

    local status conclusion duration_secs
    status=$(jq -r '.status // ""' <<<"$data")
    conclusion=$(jq -r '.conclusion // ""' <<<"$data")
    duration_secs=$(jq -r '.duration_secs // "-"' <<<"$data")

    case "$status" in
      in_progress|requested|waiting|pending)
        ((running++)) || true
        if [[ "$duration_secs" =~ ^[0-9]+$ ]] && (( duration_secs > longest_running )); then
          longest_running=$duration_secs
        fi
        ;;
      queued) ((queued++)) || true ;;
      completed)
        case "$conclusion" in
          success)
            ((success++)) || true
            if [[ "$duration_secs" =~ ^[0-9]+$ ]]; then
              completed_total=$((completed_total + duration_secs))
              ((completed_count++)) || true
            fi
            ;;
          failure|cancelled|timed_out|startup_failure|action_required)
            ((failed++)) || true
            ;;
        esac
        ;;
    esac

    rows+=("$data")
  done

  print_header
  print_summary_line "$running" "$success" "$failed" "$queued" "$empty"
  echo
  print_table_header

  local sorted=""
  if ((${#rows[@]} > 0)); then
    # Bash 3.2 + set -u: "${rows[@]}" is unbound when the array is empty.
    sorted=$(printf '%s\n' "${rows[@]}" | jq -sc 'sort_by(.priority, .repo) | .[]')
  fi

  local item repo_name status_col branch_short duration_str started_str workflow_short
  local url status conclusion

  if [[ -n "$sorted" ]]; then
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue

      repo_name=$(jq -r '.repo' <<<"$item")

      if [[ "$(jq -r '.empty // false' <<<"$item")" == "true" ]]; then
        status_col=$(printf '%b%s%b' "$C_GRAY" "$(pad_field "— sem runs" "$W_STATUS")" "$C_RESET")
        printf '%s  %s  %s  %s  %s  %s\n' \
          "$(pad_field "$repo_name" "$W_REPO")" \
          "$status_col" \
          "$(pad_field "—" "$W_BRANCH")" \
          "$(pad_field "—" "$W_DURATION")" \
          "$(pad_field "—" "$W_STARTED")" \
          "$(pad_field "—" "$W_WORKFLOW")"
        continue
      fi

      status=$(jq -r '.status // ""' <<<"$item")
      conclusion=$(jq -r '.conclusion // ""' <<<"$item")
      duration_str=$(jq -r '.duration_str // "—"' <<<"$item")
      started_str=$(jq -r '.started_str // "—"' <<<"$item")
      branch_short=$(truncate_str "$(jq -r '.headBranch // "—"' <<<"$item")" "$W_BRANCH")
      workflow_short=$(truncate_str "$(jq -r '.workflowName // "—"' <<<"$item")" "$W_WORKFLOW")
      status_col=$(format_status_col "$status" "$conclusion")

      printf '%s  %s  %s  %s  %s  %s\n' \
        "$(pad_field "$repo_name" "$W_REPO")" \
        "$status_col" \
        "$(pad_field "$branch_short" "$W_BRANCH")" \
        "$(pad_field "$duration_str" "$W_DURATION")" \
        "$(pad_field "$started_str" "$W_STARTED")" \
        "$(pad_field "$workflow_short" "$W_WORKFLOW")"
    done <<<"$sorted"
  fi

  local show_url=0
  if [[ -n "$sorted" ]]; then
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      [[ "$(jq -r '.empty // false' <<<"$item")" == "true" ]] && continue

      repo_name=$(jq -r '.repo' <<<"$item")
      status=$(jq -r '.status // ""' <<<"$item")
      conclusion=$(jq -r '.conclusion // ""' <<<"$item")
      url=$(jq -r '.url // ""' <<<"$item")

      [[ -z "$url" || "$url" == "null" ]] && continue
      if [[ "$status" != "completed" || "$conclusion" != "success" ]]; then
        printf '%b  %s → %s%b\n' "$C_DIM" "$repo_name" "$url" "$C_RESET"
        show_url=1
      fi
    done <<<"$sorted"
  fi
  (( show_url )) && echo

  local avg_completed=0
  if (( completed_count > 0 )); then
    avg_completed=$((completed_total / completed_count))
  fi

  local longest_display="-"
  if (( longest_running > 0 )); then
    longest_display=$longest_running
  fi

  print_footer "$running" "$longest_display" "$completed_count" "$avg_completed"
}

main "$@"
