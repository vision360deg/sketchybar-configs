# Troubleshooting

This manual covers the spaces overlay, its yabai dependency, and the native window-thumbnail carousel.

The data path is:

1. items/spaces.lua reads displays, spaces, and windows from yabai in one query (helpers/yabai_state.lua). It runs on SketchyBar's space, display, and window events and on the `spaces_refresh` event that the `sketchybar_spaces_*` signals in yabairc trigger.
2. helpers/space_windows.lua groups those windows by space and excludes minimized, hidden, and just-destroyed windows.
3. SketchyBar publishes the window IDs to the Mach service com.vision3.sketchybar.spaces.
4. helpers/spaces_overlay/ captures each window with ScreenCaptureKit and draws the carousel.

That means a failure can come from yabai, SketchyBar's Lua process, launchd, macOS permissions, or the capture API. Check them in that order.

## Quick recovery

Hold the spaces indicator until it shows the reload arrow, then release. `helpers/hard_reload.sh` restarts yabai when it does not answer within two seconds or has lost the Accessibility references of windows on a visible space, restarts the overlay service, and reloads SketchyBar. Each run is logged to `~/Library/Logs/SketchyBar/hard-reload.log`.

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
.../helpers/spaces_overlay/bin/SpacesOverlay.app/Contents/MacOS/SpacesOverlay
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

The carousel deliberately falls back to the application icon and window title when ScreenCaptureKit cannot provide an image. This usually means the active overlay executable does not have Screen Recording permission, even if another SpacesOverlay entry is enabled.

### Grant permission to the active app

Check which executable launchd actually runs:

~~~sh
launchctl print "gui/$(id -u)/com.vision3.sketchybar.spaces" \
  | rg -n 'program =|arguments =|spaces_overlay'
~~~

Grant Screen Recording permission to the bundled SpacesOverlay.app shown by that job at System Settings → Privacy & Security → Screen Recording. Then restart the same service:

~~~sh
make -C "$HOME/.config/sketchybar/helpers/spaces_overlay" install-service
sketchybar --reload
~~~

### Why two SpacesOverlay entries appeared

During development the service existed first as a standalone executable and later as a bundled app. macOS retained the old Screen Recording entry while the new bundle was added, so Settings showed both:

- an old raw spaces_overlay executable entry;
- the current SpacesOverlay.app bundle entry.

They are different TCC clients even though they run related source code. Keep the permission for the bundled executable used by the current LaunchAgent and remove the obsolete raw entry in System Settings. Do not grant permission to an executable that launchctl print does not show as active.

The bundle uses a stable identifier and designated requirement so rebuilding it does not intentionally create a new privacy identity each time. If macOS still prompts after a rebuild, first verify the active path and bundle identity rather than repeatedly toggling permissions:

~~~sh
codesign -dv --verbose=4 \
  "$HOME/.config/sketchybar/helpers/spaces_overlay/bin/SpacesOverlay.app" 2>&1 \
  | rg 'Identifier=|CDHash='
~~~

The expected identifier is:

~~~text
com.vision3.sketchybar.spaces
~~~

If Screen Recording still displays the retired `spaces_overlay.app` name after
the bundle is renamed, reset only this app's Screen Recording approval, restart
the service, then hover a space card to register the current client:

~~~sh
tccutil reset ScreenCapture com.vision3.sketchybar.spaces
make -C "$HOME/.config/sketchybar/helpers/spaces_overlay" install-service
sketchybar --reload
~~~

Re-enable `SpacesOverlay` in System Settings → Privacy & Security → Screen
Recording. This reset revokes the current approval until it is enabled again.

## Clicking a space card does not switch spaces

On macOS 27, yabai cannot switch spaces without its scripting addition, which needs SIP partially disabled. yabai then posts synthetic trackpad swipes to the Dock, and macOS 27 ignores them: `yabai -m space --focus` exits 0 and nothing happens. yabai 7.1.25, the latest release, predates macOS 27; see also [yabai #2842](https://github.com/asmvik/yabai/issues/2842).

A space card click therefore does not use `space --focus`. The overlay triggers the SketchyBar event `spaces_focus`, and items/spaces.lua focuses the space's display first, then:

- the space's last focused window, else its first one, among the windows yabai holds an Accessibility reference for; focusing a window still switches to its space;
- for a space without such a window (empty, or only windows yabai has no reference for), `helpers/switch_desktop/bin/switch_desktop N`, which presses Mission Control's "Switch to Desktop N" shortcut as configured in System Settings. The same happens when the window focus fails, for example because the window just closed.

macOS numbers these desktops across all displays in the order of yabai's space indices. Enable "Switch to Desktop N" for every desktop in System Settings → Keyboard → Keyboard Shortcuts → Mission Control; macOS lists one entry per existing desktop. A desktop without an enabled shortcut cannot be switched to by clicking while yabai has no window on it to focus.

The helper posts the key press, which requires Accessibility permission. SketchyBar runs it, so it uses SketchyBar's permission, which the application menus need as well. Failures are written to the SketchyBar error log:

~~~sh
grep switch_desktop "$(brew --prefix)/var/log/sketchybar/sketchybar.err.log" | tail
~~~

Exit code 69 means the desktop has no enabled shortcut, 77 that the calling app may not post events. Run it from a terminal to test a shortcut; the terminal then needs Accessibility itself:

~~~sh
~/.config/sketchybar/helpers/switch_desktop/bin/switch_desktop 2
~~~

Check whether yabai can switch spaces; run this from any space except 2:

~~~sh
yabai -m space --focus 2; sleep 1; yabai -m query --spaces --space | jq .index
~~~

If the printed index is not 2, space focus is broken; window focus (`yabai -m window --focus <id>`) still works.

## Spaces do not update after a window closes

Check that yabai still has the spaces signals. They are registered by yabairc, so they come back whenever yabai restarts; signals added at runtime do not survive a restart:

~~~sh
yabai -m signal --list | jq -r '.[].label' | grep sketchybar_spaces
~~~

Seventeen labels should be listed. If they are missing, merge the `sketchybar_spaces_*` block from `yabai/config/yabairc` into `~/.config/yabai/yabairc` and restart yabai.

Then check the SketchyBar log:

~~~sh
grep -E 'spaces: |Lua:' "$(brew --prefix)/var/log/sketchybar/sketchybar.out.log" | tail
~~~

`spaces: yabai query failed; retrying every 2s` means yabai stopped answering; the overlay keeps its last state until a query succeeds again. A `[!] Lua:` error inside `helpers/space_windows.lua` aborts a refresh before anything reaches the overlay.

## Which windows the carousel lists

The carousel must not use is-visible as its filter. yabai reports windows on other spaces as not visible on the current desktop, even when those windows are normal and should appear when their own space card is hovered.

helpers/space_windows.lua applies these filters:

- exclude is-minimized == true;
- exclude is-hidden == true;
- exclude a window yabai just reported through its window_destroyed signal, while the window server still lists it;
- exclude has-ax-reference == false on a space that is visible on any display: yabai references every window there, so an unreferenced one is still closing;
- keep has-ax-reference == false on other spaces: yabai only gets references for windows on spaces it has visited since it started.

Verify the source data directly:

~~~sh
yabai -m query --windows \
  | /opt/homebrew/bin/jq -r '.[] | [.space, .id, .app, ."is-minimized", ."is-hidden", ."has-ax-reference"] | @tsv'
~~~

After confirming yabai responds, hover the card again. If the carousel still contains a window that the filters above exclude, the overlay is showing an old snapshot; if the command itself fails, fix yabai first.

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
lua tests/yabai_state_test.lua
lua tests/space_labels_test.lua
lua tests/spaces_overlay_display_groups_test.lua
lua helpers/spaces_overlay/test/SpacesToggleTests.lua
zsh tests/hard_reload_test.sh
make -C "$HOME/.config/sketchybar/helpers/spaces_overlay" test
~~~

Check Lua syntax and whitespace errors:

~~~sh
luac -p helpers/space_windows.lua helpers/yabai_state.lua items/spaces.lua tests/space_windows_test.lua
git diff --check
~~~

These tests verify the parser and native model. They do not replace a live check of yabai, TCC permissions, or a real hover/capture on the desktop.
