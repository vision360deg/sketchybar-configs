# SketchyBar Configuration

A macOS [SketchyBar](https://github.com/FelixKratz/SketchyBar) configuration written primarily in Lua with [SbarLua](https://github.com/FelixKratz/SbarLua). Native C event providers supply CPU data, menu integration, and reliable horizontal scrolling for the dynamic spaces viewport.

## Features

- Dynamic spaces viewport that uses the available bar width and avoids overlapping right-side widgets.
- Optional `spaces_max_width` override when a fixed maximum is preferred.
- Application icons on occupied spaces and only the space number on empty spaces.
- Vertical and native horizontal scrolling through spaces that do not fit in the viewport.
- Scroll handling across the spaces, spaces indicator, and front-app label without an extra visual scrollbar.
- Application menus, active-application label, calendar, CPU graph, Wi-Fi details, volume controls, battery status, and media controls.
- Popup previews and controls for spaces, network details, audio devices, battery information, and media playback.
- Automatic compilation of native helper binaries when the configuration loads.

## Requirements

### Required

- macOS with **Displays have separate Spaces** enabled in System Settings.
- [Homebrew](https://brew.sh/).
- [SketchyBar](https://github.com/FelixKratz/SketchyBar).
- [SbarLua](https://github.com/FelixKratz/SbarLua), installed under `~/.local/share/sketchybar_lua/`.
- Xcode Command Line Tools for compiling the C helpers.
- SF Pro and SF Mono, as configured in `helpers/default_font.lua`.
- [sketchybar-app-font](https://github.com/kvndrsslr/sketchybar-app-font) for application icons in spaces.

### Optional Integrations

- [yabai](https://github.com/koekeishiya/yabai) for focusing and destroying spaces with mouse clicks.
- [nowplaying-cli](https://github.com/kirtan-shah/nowplaying-cli) for previous, play/pause, and next media actions.
- [switchaudio-osx](https://github.com/deweller/switchaudio-osx) for listing and selecting output devices through `SwitchAudioSource`.

The bar still loads without these optional tools, but their related click actions will not work.

## Installation

### 1. Place the Configuration

Clone or copy this repository so that its root is located at:

```text
~/.config/sketchybar
```

SketchyBar should therefore find the entry point at `~/.config/sketchybar/sketchybarrc`.

### 2. Install SketchyBar and Build Tools

```sh
brew tap FelixKratz/formulae
brew install sketchybar
xcode-select --install
```

If the Command Line Tools are already installed, `xcode-select` reports that no additional installation is necessary.

### 3. Install SbarLua

```sh
(git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && cd /tmp/SbarLua && make install && rm -rf /tmp/SbarLua)
```

This configuration extends Lua's module path to load `~/.local/share/sketchybar_lua/sketchybar.so`.

### 4. Install Fonts

Install [sketchybar-app-font](https://github.com/kvndrsslr/sketchybar-app-font) for application glyphs. The default text configuration also expects SF Pro and SF Mono.

To use another installed font, edit `settings.lua`. A JetBrainsMono Nerd Font example is already included there.

### 5. Install Optional Commands

```sh
brew install nowplaying-cli switchaudio-osx
```

Install and configure `yabai` separately if you want space focus and destroy actions.

### 6. Build Native Helpers

```sh
make -C ~/.config/sketchybar/helpers
```

`helpers/init.lua` also runs the helper build whenever the configuration loads, so changed C sources are rebuilt automatically.

### 7. Start SketchyBar

```sh
brew services start sketchybar
sketchybar --reload
```

After editing the configuration, apply changes with:

```sh
sketchybar --reload
```

## Configuration

The main user-facing options are in `settings.lua`:

| Setting | Behavior |
| --- | --- |
| `paddings` | General item padding. |
| `group_paddings` | Spacing between grouped bar items. |
| `spaces_max_width` | Optional hard maximum for the spaces viewport. Leave it as `nil` to calculate the available width automatically. |
| `spaces_fallback_width` | Width used when the viewport geometry cannot be measured. |
| `spaces_horizontal_scroll_threshold` | Accumulated horizontal-scroll delta required before the viewport moves. Lower values increase sensitivity. |
| `spaces_horizontal_scroll_inverted` | Reverses the horizontal-scroll direction when set to `true`. |
| `icons` | Selects the configured icon set, such as `sf-symbols` or Nerd Font icons. |
| `font` | Selects the text and number font configuration. |

The configuration currently creates ten spaces in `items/spaces.lua`. Change `space_count` there if your setup uses a different number. Item loading order is controlled by `items/init.lua`.

## Controls

### Spaces and Menus

| Input | Action |
| --- | --- |
| Left-click a space | Focus the space through `yabai`. |
| Right-click a space | Destroy the space through `yabai`. |
| Middle/other-click a space | Toggle the space preview popup. |
| Vertical scroll over a space | Page the visible spaces window. |
| Horizontal scroll over the spaces region | Page the visible spaces window through the native helper. |
| Click the spaces indicator | Toggle between spaces and application menus. |
| Click the front-app label | Toggle between spaces and application menus. |

The horizontal-scroll region covers the visible spaces, the spaces indicator, and the front-app label. Scrolling outside this region is ignored by the spaces viewport.

### Widgets

- **Calendar:** Click to open the Calendar app.
- **System Monitor:** Click the current CPU, Memory, Energy, Disk, or Network metric to open the switcher. Selecting a metric replaces the bar item and persists across reloads. Network uses blue inbound and red outbound packet-history lines instead of byte-rate numbers. Select **Open Activity Monitor** to open the app on the matching tab.
- **Wi-Fi:** Click the icon or transfer indicators to toggle network details. Click a detail value to copy it to the clipboard.
- **Volume:** Click to open audio controls, scroll to change volume, or select an output device when `SwitchAudioSource` is installed.
- **Battery:** Click to toggle remaining-time and charging details.
- **Media:** Click the artwork to toggle playback controls. The transport buttons require `nowplaying-cli`.

#### Standalone System Metrics

Each system metric can also be loaded directly in `single` mode. It creates its own bracket and padding, and clicking it opens the matching Activity Monitor tab:

```lua
local memory = require("items.widgets.memory").new({
  mode = "single",
  name = "widgets.memory",
  position = "right",
})
```

Use `mode = "embedded"` when another module owns the bracket, padding, and click behavior. The default `items/widgets/system_monitor.lua` switcher uses this mode for all five metrics.

When Activity Monitor is already running, immediate tab selection uses macOS accessibility UI scripting. If it only activates without changing tabs, grant SketchyBar Accessibility permission in **System Settings → Privacy & Security → Accessibility**.

## Input Monitoring

The native horizontal-scroll event provider uses a macOS event tap. If horizontal gestures are not detected, grant **Input Monitoring** permission to:

```text
~/.config/sketchybar/helpers/event_providers/horizontal_scroll/bin/horizontal_scroll
```

Open **System Settings → Privacy & Security → Input Monitoring**, add or enable the helper, and then reload SketchyBar:

```sh
sketchybar --reload
```

If macOS does not retain permission after rebuilding the binary, remove the old entry, add the rebuilt helper again, and reload the bar.

## Project Structure

| Path | Purpose |
| --- | --- |
| `sketchybarrc` | Executable Lua entry point loaded by SketchyBar. |
| `init.lua` | Initializes SbarLua, loads the bar modules, and starts the event loop. |
| `bar.lua` | Configures the main bar geometry and appearance. |
| `default.lua` | Defines default item styling. |
| `settings.lua` | Contains user-facing spacing, viewport, icon, and font settings. |
| `colors.lua` | Defines the color palette. |
| `icons.lua` | Defines symbols used throughout the bar. |
| `items/` | Contains spaces, menus, front-app, calendar, media, and widget modules. |
| `helpers/` | Contains Lua helpers, application-icon mappings, native source code, and build files. |
| `helpers/event_providers/` | Contains native event providers for CPU, network, space-window, media, and horizontal-scroll events. |
| `helpers/menus/` | Contains the native application-menu helper. |

The item modules are loaded from `items/init.lua` in their intended bar order.

## Troubleshooting

### Rebuild and Reload

Rebuild every native helper and reload the configuration:

```sh
make -C ~/.config/sketchybar/helpers
sketchybar --reload
```

### Inspect SketchyBar Errors

When SketchyBar runs as a Homebrew service, follow its error log with:

```sh
tail -f "$(brew --prefix)/var/log/sketchybar/sketchybar.err.log"
```

### Horizontal Scrolling Does Not Work

- Confirm that the `horizontal_scroll` binary exists under `helpers/event_providers/horizontal_scroll/bin/`.
- Grant the binary Input Monitoring permission.
- Reload SketchyBar after changing permissions.
- Lower `spaces_horizontal_scroll_threshold` if gestures require too much movement.
- Toggle `spaces_horizontal_scroll_inverted` if the direction feels reversed.
- Keep the pointer over a visible space, the spaces indicator, or the front-app label while scrolling.

### Spaces Flicker or Resize Unexpectedly

- Leave `spaces_max_width = nil` for automatic sizing.
- Set `spaces_max_width` to a positive pixel width to cap the viewport explicitly.
- Adjust `spaces_fallback_width` if geometry is temporarily unavailable during startup.
- Check the error log for repeated helper failures or reload loops.

### Optional Actions Do Nothing

Verify that the corresponding executable is available:

```sh
command -v yabai
command -v nowplaying-cli
command -v SwitchAudioSource
```

Missing optional commands do not prevent the rest of the bar from running.

### Wi-Fi Details Are Empty

The Wi-Fi widget currently queries interface `en0`. Check the active hardware ports with:

```sh
networksetup -listallhardwareports
```

If Wi-Fi uses another interface, update the `en0` provider selection in `items/widgets/wifi.lua`. The embedded Network metric shares that provider.

### Icons or Text Are Missing

- Confirm that SF Pro, SF Mono, and `sketchybar-app-font` are installed.
- Reload SketchyBar after installing fonts.
- If using a Nerd Font, update both `icons` and `font` in `settings.lua`.

## Credits

This configuration is based on and inspired by [Felix Kratz's dotfiles](https://github.com/FelixKratz/dotfiles), especially the Lua/SbarLua SketchyBar setup and native helper architecture. Thanks to Felix Kratz and the SketchyBar community for the original work and examples that made this configuration possible.
