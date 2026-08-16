local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(source:match("^(.*[/\\])"), "unable to determine plugin directory")

return dofile(directory .. "../apple-media.lua")
