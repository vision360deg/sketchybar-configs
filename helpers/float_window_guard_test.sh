#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/float_window_guard.sh"

assert_eq() {
  expected=$1
  actual=$2
  [ "$actual" = "$expected" ] || {
    printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
    exit 1
  }
}

assert_eq '10 40 100 100 0 0' \
  "$("$GUARD" --clamp 10 40 100 100 0 0 1440 900 1 1 0 1 0 0 1 1)"
assert_eq '10 30 100 100 1 0' \
  "$("$GUARD" --clamp 10 0 100 100 0 0 1440 900 1 1 0 1 0 0 1 1)"
assert_eq '10 30 100 870 1 1' \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 1 0 1 0 0 1 1)"
assert_eq '10 30 100 900 1 0' \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 1 0 1 0 0 1 0)"
assert_eq 'skip' \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 1 1 1 0 0 1 1)"
assert_eq 'skip' \
  "$("$GUARD" --clamp 10 0 100 900 0 0 1440 900 1 0 0 1 0 0 1 1)"

printf '%s\n' 'float_window_guard_test: PASS'
