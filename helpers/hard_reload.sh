#!/bin/zsh
# Long-press action of the Spaces toggle. Revives yabai when it stopped
# answering or lost the Accessibility references of windows on a visible space,
# restarts the spaces overlay service, then reloads SketchyBar.
set -u
setopt pipefail

YABAI_BIN=${YABAI_BIN:-/opt/homebrew/bin/yabai}
JQ_BIN=${JQ_BIN:-/opt/homebrew/bin/jq}
LAUNCHCTL_BIN=${LAUNCHCTL_BIN:-/bin/launchctl}
SKETCHYBAR_BIN=${SKETCHYBAR_BIN:-/opt/homebrew/bin/sketchybar}
OVERLAY_SERVICE=${OVERLAY_SERVICE:-com.vision3.sketchybar.spaces}
LOCK_FILE=${LOCK_FILE:-${TMPDIR:-/tmp}/sketchybar-hard-reload.lock}
LOG_FILE=${LOG_FILE:-$HOME/Library/Logs/SketchyBar/hard-reload.log}
QUERY_TIMEOUT=${QUERY_TIMEOUT:-2}
YABAI_START_TIMEOUT=${YABAI_START_TIMEOUT:-15}

export USER=${USER:-$(/usr/bin/id -un)}

log() {
  mkdir -p "${LOG_FILE:h}" 2>/dev/null
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null
}

# A wedged yabai never answers its socket, so every query needs a deadline.
yabai_query() {
  /usr/bin/perl -e 'alarm shift; exec @ARGV or exit 127' \
    "$QUERY_TIMEOUT" "$YABAI_BIN" -m query "$@" 2>/dev/null
}

# Prints why yabai must restart; prints nothing when it is healthy. yabai has no
# reference for windows on spaces it has not visited since it started, so only a
# visible space without references shows that yabai lost Accessibility state.
yabai_restart_reason() {
  local spaces windows
  spaces=$(yabai_query --spaces) || { print "not answering"; return; }
  windows=$(yabai_query --windows) || { print "not answering"; return; }
  print -r -- "$spaces"$'\n'"$windows" | "$JQ_BIN" -se '
    (.[0] | map(select(."is-visible" == true) | .index)) as $visible
    | any(.[1][];
        ."has-ax-reference" == false
        and ."is-minimized" != true
        and ."is-hidden" != true
        and (.space | IN($visible[])))
  ' >/dev/null 2>&1
  case $? in
    0) print "lost Accessibility references on a visible space" ;;
    1) ;;
    *) print "returned unreadable state" ;;
  esac
}

restart_yabai() {
  log "restarting yabai: $1"
  "$YABAI_BIN" --restart-service >>"$LOG_FILE" 2>&1 || log "yabai --restart-service failed"
  local deadline=$((SECONDS + YABAI_START_TIMEOUT))
  until yabai_query --displays >/dev/null; do
    if (( SECONDS >= deadline )); then
      log "yabai still not answering after ${YABAI_START_TIMEOUT}s"
      return
    fi
    sleep 0.25
  done
}

main() {
  # flock on an fd this shell holds: the kernel drops it when the script exits or
  # is killed, so an interrupted reload cannot block later long presses.
  local lock_fd
  exec {lock_fd}>>"$LOCK_FILE"
  if ! /usr/bin/lockf -s -t 0 "$lock_fd"; then
    log "reload already running; ignoring long press"
    return
  fi

  local reason
  reason=$(yabai_restart_reason)
  [[ -n $reason ]] && restart_yabai "$reason"

  "$LAUNCHCTL_BIN" kickstart -k "gui/$(/usr/bin/id -u)/$OVERLAY_SERVICE" >>"$LOG_FILE" 2>&1 \
    || log "overlay restart failed"
  "$SKETCHYBAR_BIN" --reload >>"$LOG_FILE" 2>&1 || log "sketchybar --reload failed"
  log "reloaded"
}

main
