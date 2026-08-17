local root = arg[1] or "."
local separator = string.char(31)
local handlers = {}
local calls = {}

local wezterm = {
  target_triple = "aarch64-apple-darwin",
  action_callback = function(callback) return callback end,
  format = function(elements) return elements end,
  log_error = function() end,
  on = function(name, callback) handlers[name] = callback end,
  run_child_process = function(command)
    table.insert(calls, command)
    return true, table.concat({ "music", "true", "55", "Café | 東京", "Björk" }, separator), ""
  end,
  strftime = function() return "DATE" end,
}

package.preload.wezterm = function() return wezterm end
local media = assert(loadfile(root .. "/apple-media.lua"))()
local config = {}
media.apply_to_config(config, {
  scroll_width = 6,
  show_controls = false,
  show_date = false,
  show_volume = false,
})

local status
handlers["update-status"]({
  set_right_status = function(_, value) status = value end,
}, {})
assert(type(status) == "table" and #status > 0, "expected formatted media status")
for _, element in ipairs(status) do
  if type(element) == "table" and element.Text then
    assert(utf8.len(element.Text), "status contains invalid UTF-8")
  end
end

media.setup_keys(config)
assert(#config.keys == 5, "expected five default media bindings")
config.keys[2].action()
assert(calls[#calls][3]:find("next track", 1, true), "next binding used the wrong command")

wezterm.target_triple = "x86_64-unknown-linux-gnu"
local process_count = #calls
handlers["update-status"]({
  set_right_status = function(_, value) status = value end,
}, {})
assert(status == "", "unsupported platforms must clear stale status")
assert(#calls == process_count, "unsupported platforms must not spawn osascript")

assert(loadfile(root .. "/apple-music.lua"))()
print("ok")
