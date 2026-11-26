#!/bin/zsh
# Runs every test in the repository and prints one PASS/FAIL line per test.
# Exits non-zero when any test fails.
set -u

cd "${0:A:h:h}" || exit 1
overlay=helpers/spaces_overlay
app=$overlay/bin/SpacesOverlay.app
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
failed=0

run() {
  local name=$1 output
  shift
  if output=$("$@" 2>&1); then
    print -r -- "PASS  $name"
  else
    print -r -- "FAIL  $name"
    print -r -- "$output" | tail -n 5 | sed 's/^/      /'
    failed=$((failed + 1))
  fi
}

# swift_test <test.swift> [overlay sources...]: compiles them together and runs the test.
swift_test() {
  local binary=$build_dir/${1:t:r}
  xcrun swiftc -parse-as-library -framework AppKit -framework CoreGraphics "$@" -o "$binary" &&
    "$binary"
}

# The icon test compares the built executable's Finder icon with the app's icon file.
icon_test() {
  local binary=$build_dir/spaces_overlay_icon_test
  xcrun swiftc -parse-as-library -framework AppKit tests/spaces_overlay_icon_test.swift -o "$binary" &&
    "$binary" "$app" "$app/Contents/MacOS/SpacesOverlay" "$app/Contents/Resources/SpacesOverlay.icns"
}

c_test() {
  local binary=$build_dir/${1:t:r}
  cc -Wall "$1" -o "$binary" && "$binary"
}

for test_file in tests/*.lua $overlay/test/SpacesToggleTests.lua; do
  run "$test_file" lua "$test_file"
done
run tests/float_window_guard_test.sh sh tests/float_window_guard_test.sh
run tests/hard_reload_test.sh zsh tests/hard_reload_test.sh
run tests/spaces_overlay_icon_test.sh zsh tests/spaces_overlay_icon_test.sh
run tests/spaces_overlay_icon_test.swift icon_test
run tests/spaces_overlay_config_snapshot_test.swift \
  swift_test tests/spaces_overlay_config_snapshot_test.swift $overlay/OverlayState.swift
run tests/spaces_overlay_fullscreen_test.swift \
  swift_test tests/spaces_overlay_fullscreen_test.swift $overlay/OverlayState.swift \
    $overlay/WindowCarouselModel.swift $overlay/OverlayWindowPolicy.swift $overlay/SpacesView.swift
run "make -C $overlay test test-reorder" make -C $overlay test test-reorder
run tests/network_load/network_load_test.c c_test tests/network_load/network_load_test.c

if (( failed > 0 )); then
  print -r -- "$failed failed"
  exit 1
fi
print -r -- "all tests passed"
