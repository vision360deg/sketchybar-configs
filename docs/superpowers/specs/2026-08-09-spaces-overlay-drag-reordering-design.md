# Spaces Overlay Drag Reordering

## Goal

Allow a user to drag a space card in the native spaces overlay to change the
real macOS Mission Control order through yabai. A normal left click must still
focus a space, and right click must still destroy one.

## Scope and behavior

- Dragging starts only after the pointer moves beyond a small threshold (4 pt).
- A press and release without crossing that threshold remains a normal
  left-click and focuses the space on mouse-up.
- While dragging, the source card is rendered as a translucent card following
  the pointer and its original position becomes a visible insertion gap.
- The insertion position is determined by the horizontal midpoint of the
  other cards. The pointer before a card inserts before it; after the final
  midpoint inserts at the end.
- Releasing over a valid insertion position issues one direct move command:
  `yabai -m space <source> --move <destination>`.
  `<destination>` is the desired final 1-based position, not an intermediate
  neighbor. The command does not require focusing the dragged space.
- Releasing without a valid destination, or returning the card to its current
  position, cancels without invoking yabai.
- Right-click behavior is unchanged and never starts a drag.
- The first implementation supports reordering spaces on the same display.
  Yabai rejects cross-display moves; the overlay will leave the order unchanged
  if that command fails.
- The overlay does not maintain a second persistent order. After a successful
  move, the existing SketchyBar/yabai refresh path updates the numeric indexes
  and app labels from yabai’s state.

No new persistence, settings, keyboard modifiers, or drag-and-drop data
providers are needed.

## Architecture

### Native AppKit overlay (`SpacesView.swift`)

`SpacesView` owns a small drag state containing the source space, pointer-down
location, current pointer location, and calculated destination. Mouse handling
is split across `mouseDown`, `mouseDragged`, and `mouseUp`:

1. `mouseDown` records the source card and starting point without immediately
   focusing it.
2. `mouseDragged` crosses the threshold, enters drag mode, updates the
   destination, and invalidates drawing.
3. `mouseUp` focuses the source for a click or runs the direct yabai move for a
   valid drag, then clears the state.

The existing item layout remains the source of truth for hit testing and card
geometry. A pure reorder helper will calculate a final index from the pointer
position and item frames so the insertion behavior can be unit tested without
constructing an AppKit window.

The existing asynchronous process helper will be extended to run the move
command and inspect its exit status. It will discard stdout/stderr like the
current focus and destroy commands. On a successful move only, it will trigger the
`spaces_order_changed` SketchyBar event through the environment's `sketchybar`
executable; a failed command will not trigger a local reorder.

### State refresh (`items/spaces.lua`)

The native overlay continues to receive snapshots through the existing Mach
transport. `items/spaces.lua` will subscribe to the targeted
`spaces_order_changed` event, query all yabai windows once, rebuild the app
icon labels grouped by their current `.space` index, and send a fresh snapshot.
This keeps labels attached to their actual spaces after indexes change and
reuses the existing yabai query and SketchyBar event model rather than adding
a new Mach payload.

If a move is rejected (for example, because the spaces are on different
displays or yabai lacks the required scripting addition), no local order is
changed and no targeted refresh is triggered. Any refresh that is requested
uses yabai’s current query result as its sole source of truth.

## Visual and interaction details

- Normal cards retain their current selected/inactive styling.
- The dragged card uses the same geometry and text as the source card with
  reduced alpha, so the user can identify it while moving.
- The source slot is represented by a gap/placeholder; other cards are laid
  out as the current order with the source removed and the gap at the current
  destination.
- Existing scrolling remains available when not dragging. Dragging does not
  add automatic edge scrolling in this first slice; the user can scroll to the
  relevant range before starting a drag.
- Existing clipping, selection-following, and overlay visibility behavior are
  unchanged.

## Error handling and constraints

- A malformed or missing snapshot leaves the view unchanged, as it does today.
- A drag with no source card, no destination, or no positional change is a
  no-op.
- Yabai move failures are ignored at the UI layer, consistent with the current
  focus/destroy process handling. The subsequent snapshot remains authoritative.
- Real space movement depends on yabai support and the system permissions it
  requires; this feature does not attempt to emulate reordering when yabai
  rejects the operation.
- Existing multi-display behavior is preserved; cross-display reorder is not
  promised by this feature.

## Testing

Add focused Swift tests for the pure reorder helper covering:

- pointer before the first card;
- insertion between cards;
- insertion after the last card;
- source removal and final-index adjustment;
- dropping back into the source position;
- invalid/empty layouts.

Retain all existing snapshot, scroll, policy, and Lua toggle tests. Add a Lua
assertion for the targeted post-move refresh event and label rebuild. Build the
native helper and run the overlay test target;
also run the repository’s existing shell/Lua tests where available.

## Out of scope

- Reordering spaces across displays.
- Automatic edge scrolling while dragging.
- Persistent custom labels or a second logical ordering layer.
- Dragging spaces into the menus view or other bar items.
