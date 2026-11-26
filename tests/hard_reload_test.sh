#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
helper="$repo_dir/helpers/hard_reload.sh"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hard-reload-test.XXXXXX")
fake_bin="$temp_dir/bin"
log_file="$temp_dir/commands.log"
spaces_fixture="$temp_dir/spaces.json"
windows_fixture="$temp_dir/windows.json"
restarted_marker="$temp_dir/restarted"
lock_file="$temp_dir/reload.lock"

cleanup() { rm -rf "$temp_dir"; }
trap cleanup EXIT
mkdir -p "$fake_bin"

cat > "$fake_bin/yabai" <<EOF
#!/bin/zsh
print -r -- "yabai:\$*" >> "$log_file"
if [[ \$1 == --restart-service ]]; then
  : > "$restarted_marker"
  exit 0
fi
if [[ \${FAKE_YABAI_HANG:-0} == 1 && ! -e "$restarted_marker" ]]; then
  exec sleep 10
fi
case "\$*" in
  *--spaces*) cat "$spaces_fixture" ;;
  *--windows*) cat "$windows_fixture" ;;
  *) print '[]' ;;
esac
EOF

cat > "$fake_bin/launchctl" <<EOF
#!/bin/zsh
print -r -- "launchctl:\$*" >> "$log_file"
EOF

cat > "$fake_bin/sketchybar" <<EOF
#!/bin/zsh
print -r -- "sketchybar:\$*" >> "$log_file"
EOF

chmod +x "$fake_bin"/*

print -r -- '[{"index":1,"is-visible":true},{"index":2,"is-visible":false}]' > "$spaces_fixture"

run_helper() {
  : > "$log_file"
  rm -f "$restarted_marker"
  YABAI_BIN="$fake_bin/yabai" \
    LAUNCHCTL_BIN="$fake_bin/launchctl" \
    SKETCHYBAR_BIN="$fake_bin/sketchybar" \
    LOCK_FILE="$lock_file" \
    LOG_FILE="$temp_dir/reload.log" \
    QUERY_TIMEOUT=1 \
    YABAI_START_TIMEOUT=3 \
    /bin/zsh "$helper"
}

has_line() { grep -F -q -- "$1" "$log_file"; }

assert_reloaded_without_restart() {
  ! has_line "yabai:--restart-service" || { print -u2 "unexpected yabai restart: $1"; exit 1; }
  has_line "launchctl:kickstart -k" || { print -u2 "overlay not restarted: $1"; exit 1; }
  has_line "sketchybar:--reload" || { print -u2 "bar not reloaded: $1"; exit 1; }
}

assert_restart_then_reload() {
  local restart reload
  restart=$(grep -n -F -- "yabai:--restart-service" "$log_file" | head -1 | cut -d: -f1)
  reload=$(grep -n -F -- "sketchybar:--reload" "$log_file" | head -1 | cut -d: -f1)
  [[ -n $restart && -n $reload && $restart -lt $reload ]] \
    || { print -u2 "expected yabai restart before reload: $1"; cat "$log_file" >&2; exit 1; }
}

print -r -- '[{"id":1,"space":1,"has-ax-reference":true,"is-minimized":false,"is-hidden":false}]' \
  > "$windows_fixture"
run_helper
assert_reloaded_without_restart "healthy yabai"

# yabai cannot reference windows on spaces it has not visited since it started.
print -r -- '[{"id":2,"space":2,"has-ax-reference":false,"is-minimized":false,"is-hidden":false}]' \
  > "$windows_fixture"
run_helper
assert_reloaded_without_restart "unreferenced window on a hidden space"

print -r -- '[{"id":3,"space":1,"has-ax-reference":false,"is-minimized":false,"is-hidden":false}]' \
  > "$windows_fixture"
run_helper
assert_restart_then_reload "unreferenced window on a visible space"

print -r -- '[{"id":1,"space":1,"has-ax-reference":true,"is-minimized":false,"is-hidden":false}]' \
  > "$windows_fixture"
started=$SECONDS
FAKE_YABAI_HANG=1 run_helper
(( SECONDS - started < 8 )) || { print -u2 "hung yabai blocked the reload"; exit 1; }
assert_restart_then_reload "hung yabai"

/usr/bin/lockf -k "$lock_file" sleep 30 &
holder=$!
sleep 0.3
run_helper
! has_line "sketchybar:--reload" || { print -u2 "concurrent reload was not skipped"; exit 1; }
kill "$holder"
wait "$holder" 2>/dev/null || true

# The lock file outlives a killed reload; only a live holder may block.
[[ -e $lock_file ]]
run_helper
has_line "sketchybar:--reload" || { print -u2 "leftover lock file blocked the reload"; exit 1; }

print "hard reload tests passed"
