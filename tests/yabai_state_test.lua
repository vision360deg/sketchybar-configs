package.path = "./?.lua;./?/init.lua;" .. package.path

local yabai_state = require("helpers.yabai_state")

local output = table.concat({
  "D\t1\t0\t0\t1440\t900\ttrue",
  "D\t2\t156\t-1080\t1920\t1080\tfalse",
  "S\t1\t1\ttrue\ttrue",
  "S\t2\t1\tfalse\tfalse",
  "S\t3\t2\ttrue\tfalse",
  "W\t1\t889\tWezTerm\tfalse\tfalse\ttrue\ttrue\t1",
  "W\t2\t5159\tOrca\tfalse\ttrue\tfalse\tfalse\t1",
  "W\t3\t77\t\tfalse\tfalse\tfalse\t\t2",
  "END",
}, "\n") .. "\n"

local state = yabai_state.parse(output)
assert(state, "parses a complete snapshot")
assert(state.displays[2].y == -1080 and state.displays[2].width == 1920,
       "keeps display frames, including negative origins")
assert(state.displays[1].focused and not state.displays[2].focused,
       "reads display focus")
assert(#state.spaces == 3 and state.spaces[3].display == 2,
       "maps spaces to displays")
assert(state.spaces[1].focused and state.spaces[3].visible and not state.spaces[3].focused,
       "separates the visible space of each display from the focused one")
assert(state.windows[1].focused and state.windows[1].ax_reference,
       "reads window focus and Accessibility reference")
assert(state.windows[2].hidden and not state.windows[2].ax_reference,
       "reads hidden windows without a reference")
assert(state.windows[3].app == "" and state.windows[3].ax_reference,
       "treats a missing reference field as referenced")

assert(yabai_state.parse(output:gsub("END\n$", "")) == nil,
       "rejects output without the END sentinel")
assert(yabai_state.parse("") == nil, "rejects empty output from an unreachable yabai")
assert(yabai_state.parse({}) == nil, "rejects output SbarLua decoded as JSON")
assert(yabai_state.parse("D\t1\t0\t0\t1440\t900\ttrue\nEND\n") == nil,
       "rejects a snapshot without spaces")

print("yabai state tests passed")
