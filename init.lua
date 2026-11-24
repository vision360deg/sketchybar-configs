-- SbarLua prints SketchyBar's replies with printf, and sbar.exec forks this
-- process. When stdout is a file it is block-buffered, so every exec child would
-- flush its copy of the unwritten output again on exit, repeating old messages
-- in the log. Line buffering writes each message once.
io.stdout:setvbuf("line")

-- Require the sketchybar module
sbar = require("sketchybar")

-- Set the bar name, if you are using another bar instance than sketchybar
-- sbar.set_bar_name("bottom_bar")

-- Bundle the entire initial configuration into a single message to sketchybar
sbar.begin_config()
require("bar")
require("default")
require("items")
sbar.end_config()

-- Run the event loop of the sketchybar module (without this there will be no
-- callback functions executed in the lua module)
sbar.event_loop()
