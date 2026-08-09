# Troubleshooting

This manual covers the spaces overlay, its yabai dependency, and the native window-thumbnail carousel.

The data path is:

1. items/spaces.lua asks yabai for the current spaces and windows.
2. helpers/space_windows.lua groups those windows by space and excludes minimized or hidden windows.
3. SketchyBar publishes the window IDs to the Mach service com.vision3.sketchybar.spaces.
4. helpers/spaces_overlay/ captures each window with ScreenCaptureKit and draws the carousel.

That means a failure can come from yabai, SketchyBar's Lua process, launchd, macOS permissions, or the capture API. Check them in that order.

## Quick recovery

Run this after restoring yabai permissions or changing its configuration:

~~~sh
launchctl print "gui/$(id -u)/com.asmvik.yabai"
yabai -m query --windows >/dev/null

make -C "$HOME/.config/sketchybar/helpers/spaces_overlay" install-service
sketchybar --reload
~~~

Move the pointer away from the spaces row, hover a card again, and wait one second. The reload is important: the carousel uses the latest window-ID snapshot published by SketchyBar.

## Identify the running programs

There are two separate services:

| Service | Purpose |
| --- | --- |
| com.asmvik.yabai | Supplies window/space state and performs focus operations. |
| com.vision3.sketchybar.spaces | Renders the native spaces row and window carousel. |

Inspect both jobs:

~~~sh
launchctl print "gui/$(id -u)/com.asmvik.yabai"
launchctl print "gui/$(id -u)/com.vision3.sketchybar.spaces"
~~~

The overlay should point to the bundled executable:

~~~text
.../helpers/spaces_overlay/bin/spaces_overlay.app/Contents/MacOS/spaces_overlay
~~~

The app bundle is intentional. It supplies the stable bundle identity used for Screen Recording permission and is signed with the stable designated identifier com.vision3.sketchybar.spaces by the spaces-overlay Makefile.

## yabai does not answer commands

### Symptoms

Typical symptoms are:

~~~text
yabai-msg: failed to connect to socket..
~~~

The spaces row may still be visible, but its window list is stale or empty. The carousel can then show old entries until SketchyBar is reloaded.

### Check the launchd job

~~~sh
launchctl print "gui/$(id -u)/com.asmvik.yabai" \
  | rg -n 'state =|program =|arguments =|config|pid =|last exit|reason'
~~~

The important part is that the arguments include the actual config file:

~~~text
program = /opt/homebrew/bin/yabai
arguments = {
    /opt/homebrew/bin/yabai
    --config
    $HOME/.config/yabai/yabairc
}
~~~

If the job is loaded but the query still fails, check the socket and process:

~~~sh
ls -l /tmp/yabai_"$(id -un)".socket
lsof -nP -a -U -c yabai
yabai -m query --windows
~~~

Do not treat the presence of the socket file alone as proof that yabai is healthy. The running process must be listening and respond to yabai -m query --windows.

### The config-path issue

The Homebrew symlink was not the problem. The failure came from launchd starting yabai without reliably resolving the expected configuration environment. A launch agent does not necessarily inherit the same shell setup as an interactive terminal, including HOME or XDG_CONFIG_HOME.

Passing the config explicitly removes that dependency. The yabai LaunchAgent should contain the equivalent of:

~~~xml
<key>ProgramArguments</key>
<array>
    <string>/opt/homebrew/bin/yabai</string>
    <string>--config</string>
    <string>/Users/your-user/.config/yabai/yabairc</string>
</array>
~~~

After changing the plist, reload the job:

~~~sh
launchctl bootout "gui/$(id -u)/com.asmvik.yabai"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.asmvik.yabai.plist"
yabai -m query --windows
~~~

Use launchctl print again to verify that the active job, not only the plist on disk, contains --config.

## /opt/homebrew/bin/yabai versus the Cellar path

Homebrew normally installs a versioned executable in its Cellar and creates a stable symlink in /opt/homebrew/bin:

~~~sh
ls -l /opt/homebrew/bin/yabai
realpath /opt/homebrew/bin/yabai
~~~

A result like this is normal:

~~~text
/opt/homebrew/bin/yabai -> ../Cellar/yabai/7.1.25/bin/yabai
/opt/homebrew/Cellar/yabai/7.1.25/bin/yabai
~~~

Those are not two yabai installations. The first path is the Homebrew-managed entry point; the second is the actual versioned file.

The symlink does not become stale merely because the real file is under Cellar. Homebrew updates the symlink when the formula changes. Check the target before assuming there are duplicate binaries:

~~~sh
command -v yabai
realpath "$(command -v yabai)"
~~~

### Why permissions can still look confusing

macOS privacy permissions are separate from shell path resolution. TCC can record an executable path and code-signing requirement, while a shell resolves a symlink to its Cellar target. A permission problem can therefore be caused by a changed executable, changed code signature, changed bundle identity, or an old path left in the privacy database. It is not automatically caused by the symlink.

Inspect the current binary's identity:

~~~sh
codesign -dv --verbose=4 "$(realpath /opt/homebrew/bin/yabai)" 2>&1 \
  | rg 'Executable=|Identifier=|CDHash=|TeamIdentifier='
codesign -d -r- "$(realpath /opt/homebrew/bin/yabai)" 2>&1
~~~

In this incident, the Accessibility permission was not stale: the TCC requirement matched yabai's current designated code-signing requirement. The value that looked like an old hash was the certificate leaf in the requirement, not yabai's CDHash.

## yabai Accessibility permission was disabled

yabai needs Accessibility permission to inspect and focus windows. If it is disabled while yabai is running, space/window controls can stop responding and the desktop can feel locked out.

> **Important:** Stop yabai before disabling, removing, or changing its Accessibility permission. Do not toggle the permission off while the yabai LaunchAgent is still running. Boot the job out first, then change the permission, and only bootstrap yabai again after permission has been restored. Skipping this order can leave the desktop effectively locked out of normal window interaction.

Recover it as follows:

1. Stop the yabai LaunchAgent so it is not repeatedly restarting while permission is changed.

   ~~~sh
   launchctl bootout "gui/$(id -u)/com.asmvik.yabai"
   ~~~

2. Open System Settings → Privacy & Security → Accessibility.
3. Re-enable yabai. If it is missing, add the path resolved by:

   ~~~sh
   realpath /opt/homebrew/bin/yabai
   ~~~

4. Bootstrap the LaunchAgent again:

   ~~~sh
   launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.asmvik.yabai.plist"
   ~~~

5. Verify the service before reloading SketchyBar:

   ~~~sh
   yabai -m query --windows >/dev/null && echo "yabai is responding"
   ~~~

Do not remove Accessibility permission as a first diagnostic step. If you must change it, use the stop-first sequence above.

## Carousel shows app icons instead of window images

The carousel deliberately falls back to the application icon and window title when ScreenCaptureKit cannot provide an image. This usually means the active overlay executable does not have Screen Recording permission, even if another spaces_overlay entry is enabled.

### Grant permission to the active app

Check which executable launchd actually runs:

~~~sh
launchctl print "gui/$(id -u)/com.vision3.sketchybar.spaces" \
  | rg -n 'program =|arguments =|spaces_overlay'
~~~

Grant Screen Recording permission to the bundled spaces_overlay.app shown by that job at System Settings → Privacy & Security → Screen Recording. Then restart the same service:

~~~sh
make -C "$HOME/.config/sketchybar/helpers/spaces_overlay" install-service
sketchybar --reload
~~~

### Why two spaces_overlay entries appeared

During development the service existed first as a standalone executable and later as a bundled app. macOS retained the old Screen Recording entry while the new bundle was added, so Settings showed both:

- an old raw spaces_overlay executable entry;
- the current spaces_overlay.app bundle entry.

They are different TCC clients even though they run related source code. Keep the permission for the bundled executable used by the current LaunchAgent and remove the obsolete raw entry in System Settings. Do not grant permission to an executable that launchctl print does not show as active.

The bundle uses a stable identifier and designated requirement so rebuilding it does not intentionally create a new privacy identity each time. If macOS still prompts after a rebuild, first verify the active path and bundle identity rather than repeatedly toggling permissions:

~~~sh
codesign -dv --verbose=4 \
  "$HOME/.config/sketchybar/helpers/spaces_overlay/bin/spaces_overlay.app" 2>&1 \
  | rg 'Identifier=|CDHash='
~~~

The expected identifier is:

~~~text
com.vision3.sketchybar.spaces
~~~

## Carousel includes minimized windows

The carousel must not use is-visible as its filter. yabai reports windows on other spaces as not visible on the current desktop, even when those windows are normal and should appear when their own space card is hovered.

The correct filters are:

- exclude is-minimized == true;
- exclude is-hidden == true;
- keep normal windows from other spaces, even when their current-desktop is-visible value is false.

The Lua refresh command requests the two relevant flags:

~~~sh
yabai -m query --windows \
  | /opt/homebrew/bin/jq -r '.[] | [(.space // 0), (.id // 0), (.app // ""), (.["is-minimized"] // false), (.["is-hidden"] // false)] | @tsv'
~~~

The parser in helpers/space_windows.lua drops records with either flag set to true before they are published to the overlay.

Verify the source data directly:

~~~sh
yabai -m query --windows \
  | /opt/homebrew/bin/jq -r '.[] | [(.space // 0), (.id // 0), (.app // ""), (.["is-minimized"] // false), (.["is-hidden"] // false)] | @tsv' \
  | awk -F '\t' '$4 == "true" || $5 == "true"'
~~~

The command above lists windows that should be excluded. After confirming yabai responds, reload SketchyBar and hover again. If the carousel still contains one of those IDs, the bar is showing an old snapshot; if the command itself fails, fix yabai first.

## Screen Recording permission keeps prompting

Use this order:

1. Confirm the LaunchAgent runs the bundled app, not an old standalone executable.
2. Confirm the Screen Recording permission is enabled for that bundle.
3. Rebuild/reinstall with the repository Makefile:

   ~~~sh
   make -C "$HOME/.config/sketchybar/helpers/spaces_overlay" install-service
   ~~~

4. Reload SketchyBar:

   ~~~sh
   sketchybar --reload
   ~~~

5. Move off the space card and hover it again.

If the carousel opens but contains only icons, the service is running but capture failed. If no carousel appears, inspect the service and Mach log instead:

~~~sh
launchctl print "gui/$(id -u)/com.vision3.sketchybar.spaces"
tail -n 100 "$HOME/Library/Logs/SketchyBar/spaces-overlay.err.log"
~~~

Log timestamps matter. A log containing old diagnostics does not prove that the current process is failing; check its modification time:

~~~sh
stat -f '%Sm %z %N' "$HOME/Library/Logs/SketchyBar/spaces-overlay.err.log"
~~~

## Verification commands

Run the focused regression tests after changing the window-list filter or overlay model:

~~~sh
lua tests/space_windows_test.lua
lua tests/space_labels_test.lua
lua helpers/spaces_overlay/test/SpacesToggleTests.lua
make -C "$HOME/.config/sketchybar/helpers/spaces_overlay" test
~~~

Check Lua syntax and whitespace errors:

~~~sh
luac -p helpers/space_windows.lua items/spaces.lua tests/space_windows_test.lua
git diff --check
~~~

These tests verify the parser and native model. They do not replace a live check of yabai, TCC permissions, or a real hover/capture on the desktop.
