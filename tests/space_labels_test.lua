package.path = "./?.lua;./?/init.lua;" .. package.path

local labels = require("helpers.space_labels")

local rebuilt = labels.rebuild("1\tSafari\n1\tSafari\n2\tTerminal\n1\tUnknown\n", 3)
assert(#rebuilt[1] == 2 and rebuilt[1][1] == "Safari" and rebuilt[1][2] == "Unknown",
       "deduplicates and preserves app names on space one")
assert(#rebuilt[2] == 1 and rebuilt[2][1] == "Terminal",
       "preserves app names on space two")
assert(#rebuilt[3] == 0, "empty spaces remain empty")
assert(labels.serialize(rebuilt[1]) == "Safari\31Unknown",
       "serializes app names with the unit separator")

local malformed = labels.rebuild("bad\n0\tSafari\n4\tTerminal\n", 3)
assert(#malformed[1] == 0 and #malformed[2] == 0 and #malformed[3] == 0,
       "ignores malformed and out-of-range rows")

local content_width = labels.content_width({
  { "Safari" },
  { "Docker", "Sublime Text" },
  {},
})
assert(math.abs(content_width - 218.08) < 0.001,
       "calculates card content width from app counts")
assert(labels.content_width({}) == 0, "empty app content has zero width")
assert(math.abs(labels.content_width({ { "Safari" }, {}, {}, {} }, 2) - 126.04) < 0.001,
       "ignores inactive space capacity when calculating width")

print("space label tests passed")
