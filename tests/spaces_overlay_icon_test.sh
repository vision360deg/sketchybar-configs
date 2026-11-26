#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
overlay_dir="$root_dir/helpers/spaces_overlay"
app_path="$overlay_dir/bin/SpacesOverlay.app"
binary_path="$app_path/Contents/MacOS/SpacesOverlay"

finder_info_hex="$(xattr -p -x com.apple.FinderInfo "$binary_path" 2>/dev/null | tr -d ' \n')"
if [[ "${finder_info_hex:16:4}" != "0400" ]]; then
  print -u2 "FAIL: executable is missing Finder's custom-icon flag"
  exit 1
fi

resource_fork_hex="$(xattr -p -x com.apple.ResourceFork "$binary_path" 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]')"
if (( ${#resource_fork_hex} < 8192 )) || [[ "$resource_fork_hex" != *69636e73* ]]; then
  print -u2 "FAIL: executable custom icon resource is missing or invalid"
  exit 1
fi

codesign --verify --deep --ignore-resources "$app_path"
print "spaces overlay executable Finder icon test passed"
