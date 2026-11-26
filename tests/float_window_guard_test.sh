#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/../helpers/float_window_guard.sh"
# The guard keeps windows below the bar: the display's top plus its TOP_INSET.
INSET=$(sed -n 's/^TOP_INSET=//p' "$GUARD")
[ -n "$INSET" ] || {
  printf '%s\n' 'TOP_INSET not found in the guard' >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$actual" = "$expected" ] || {
    printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
    exit 1
  }
}

assert_eq "10 $((INSET + 10)) 100 100 0 0" \
  "$("$GUARD" --clamp 10 $((INSET + 10)) 100 100 0 0 1440 900 1 1 0 1 0 0 1 1)"
assert_eq "10 $INSET 100 100 1 0" \
  "$("$GUARD" --clamp 10 0 100 100 0 0 1440 900 1 1 0 1 0 0 1 1)"
assert_eq "10 $INSET 100 $((900 - INSET)) 1 1" \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 1 0 1 0 0 1 1)"
assert_eq "10 $INSET 100 900 1 0" \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 1 0 1 0 0 1 0)"
assert_eq 'skip' \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 1 1 1 0 0 1 1)"
assert_eq 'skip' \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 0 0 1 0 0 1 1)"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cp "$SCRIPT_DIR/float_window_guard_test_mock.sh" "$TMP_DIR/yabai"
chmod +x "$TMP_DIR/yabai"

COMMAND_LOG="$TMP_DIR/commands"
PATH="$TMP_DIR:$PATH" \
  FLOAT_WINDOW_GUARD_TEST_LOG="$COMMAND_LOG" \
  "$GUARD" 42

if ! grep -Fq -- "window 42 --move abs:0:$INSET" "$COMMAND_LOG"; then
  printf '%s\n' 'expected float-space window to be moved below the bar' >&2
  exit 1
fi

printf '%s\n' 'float_window_guard_test: PASS'
