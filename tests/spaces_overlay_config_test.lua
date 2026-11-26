local config = dofile("helpers/spaces_overlay/config.lua")

assert(config.rearrange_spaces == false,
       "space rearranging is disabled by default")

print("spaces overlay config tests passed")
