#!/bin/zsh
set -u
setopt pipefail

YABAI_BIN=${YABAI_BIN:-/opt/homebrew/bin/yabai}
JQ_BIN=${JQ_BIN:-/opt/homebrew/bin/jq}
LAUNCHCTL_BIN=${LAUNCHCTL_BIN:-/bin/launchctl}
SKETCHYBAR_BIN=${SKETCHYBAR_BIN:-/opt/homebrew/bin/sketchybar}
SERVICE_NAME=com.vision3.sketchybar.spaces
RECOVERY_LOCK_DIR=${RECOVERY_LOCK_DIR:-${TMPDIR:-/tmp}/sketchybar-spaces-ax-recovery.lock}
RECOVERY_LOG=${RECOVERY_LOG:-${HOME}/Library/Logs/SketchyBar/spaces-ax-recovery.log}
LOCK_WAIT_SECONDS=${LOCK_WAIT_SECONDS:-15}
YABAI_WAIT_SECONDS=${YABAI_WAIT_SECONDS:-5}

log() {
  local message="$1"
  mkdir -p "${RECOVERY_LOG:h}" 2>/dev/null || true
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $message" \
    >> "$RECOVERY_LOG" 2>/dev/null || true
}

trigger_toggle() {
  "$SKETCHYBAR_BIN" --trigger swap_menus_and_spaces >/dev/null 2>&1 || \
    log "SketchyBar toggle trigger returned nonzero"
}

acquire_lock() {
  local deadline=$((SECONDS + LOCK_WAIT_SECONDS))
  while ! mkdir "$RECOVERY_LOCK_DIR" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      log "recovery lock timed out; preserving click toggle"
      return 1
    fi
    sleep 0.05
  done
  return 0
}

release_lock() {
  rmdir "$RECOVERY_LOCK_DIR" 2>/dev/null || true
}

has_stale_windows() {
  local windows jq_status
  if ! windows=$("$YABAI_BIN" -m query --windows 2>/dev/null); then
    log "yabai window query failed"
    return 2
  fi

  print -r -- "$windows" |
    "$JQ_BIN" -e '
      any(.[];
        ((.id // 0) > 0)
        and ((.space // 0) > 0)
        and ((."is-minimized" // false) == false)
        and ((."is-hidden" // false) == false)
        and (has("has-ax-reference") and .["has-ax-reference"] == false)
      )
    ' >/dev/null 2>/dev/null
  jq_status=$?

  if (( jq_status == 0 )); then return 0; fi
  if (( jq_status == 1 )); then return 1; fi
  log "yabai window payload could not be parsed"
  return 2
}

wait_for_yabai() {
  local deadline=$((SECONDS + YABAI_WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if "$YABAI_BIN" -m query --windows >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

recover() {
  log "stale AX state detected; restarting yabai"
  "$YABAI_BIN" --restart-service >>"$RECOVERY_LOG" 2>&1 || \
    log "yabai restart returned nonzero"

  if ! wait_for_yabai; then
    log "yabai did not become responsive before timeout"
  fi

  "$LAUNCHCTL_BIN" kickstart -k "gui/$('/usr/bin/id' -u)/$SERVICE_NAME" \
    >>"$RECOVERY_LOG" 2>&1 || log "SpacesOverlay restart returned nonzero"
  "$SKETCHYBAR_BIN" --reload >>"$RECOVERY_LOG" 2>&1 || \
    log "SketchyBar reload returned nonzero"
}

main() {
  if acquire_lock; then
    trap release_lock EXIT INT TERM
    has_stale_windows
    local query_status=$?
    case "$query_status" in
      0) recover ;;
      1) ;;
      2) log "skipping recovery after diagnostic failure" ;;
    esac
    release_lock
  fi

  trigger_toggle
}

main
exit 0
