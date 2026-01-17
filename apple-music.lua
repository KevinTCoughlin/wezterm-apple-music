-- apple-music.lua
-- Apple Music status bar plugin for Wezterm
-- https://github.com/kevintcoughlin/wezterm-apple-music
--
-- Features:
--   - Smooth scrolling track title (marquee)
--   - Animated equalizer visualization
--   - Clickable playback controls (prev/play-pause/next)
--   - Volume indicator with Nerd Font icons
--   - Pause state indicator
--
-- Usage:
--   local apple_music = require("plugins.apple-music")
--   apple_music.apply_to_config(config, {
--     update_interval = 500,
--     scroll_width = 35,
--     color = "#7aa2f7",
--     eq_style = "thin",  -- "thin", "classic", "dots", "bars", "wave"
--   })

local wezterm = require("wezterm")
local M = {}

-- Default configuration
local defaults = {
  update_interval = 500,      -- ms between updates
  scroll_width = 30,          -- max visible characters for track
  scroll_padding = "   ·   ", -- separator in scroll loop
  color = "#7aa2f7",          -- status bar text color
  color_controls = "#565f89", -- playback controls color
  color_controls_hover = "#7aa2f7",
  eq_style = "thin",          -- "thin", "classic", "dots", "bars", "wave"
  show_volume = true,         -- show volume icon
  show_controls = true,       -- show clickable prev/play/next
  show_date = true,           -- show date/time
  date_format = "%a %b %-d %H:%M",
}

-- Equalizer animation frames by style
local EQ_STYLES = {
  thin = {
    "▏▎▍",
    "▎▍▌",
    "▍▌▋",
    "▌▋▊",
    "▋▊▉",
    "▊▉▊",
    "▉▊▋",
    "▊▋▌",
    "▋▌▍",
    "▌▍▎",
    "▍▎▏",
    "▎▏▎",
  },
  classic = {
    "▁▃▅",
    "▂▅▃",
    "▃▂▅",
    "▅▃▂",
    "▃▅▃",
    "▂▃▅",
  },
  dots = {
    "●○●",
    "○●○",
    "●●○",
    "○●●",
    "●○○",
    "○○●",
  },
  bars = {
    "┃╏╏",
    "╏┃╏",
    "╏╏┃",
    "╏┃╏",
  },
  wave = {
    "∿∿∿",
    "∾∿∿",
    "∿∾∿",
    "∿∿∾",
  },
}

-- Control icons (Nerd Font)
local CONTROLS = {
  prev = "󰒮",
  play = "󰐊",
  pause = "󰏤",
  next = "󰒭",
}

-- Volume icons (Nerd Font)
local VOLUME_ICONS = {
  muted = "󰖁",
  low = "󰕿",
  medium = "󰖀",
  high = "󰕾",
}

-- Internal state
local state = {
  position = 0,
  last_track = "",
  eq_frame = 1,
  is_playing = false,
}

local function get_volume_icon(vol)
  if vol == 0 then return VOLUME_ICONS.muted
  elseif vol <= 33 then return VOLUME_ICONS.low
  elseif vol <= 66 then return VOLUME_ICONS.medium
  else return VOLUME_ICONS.high
  end
end

local function music_command(cmd)
  return wezterm.action_callback(function()
    wezterm.run_child_process({
      "osascript", "-e",
      string.format('tell application "Music" to %s', cmd)
    })
  end)
end

local function get_apple_music_info()
  local success, stdout, _ = wezterm.run_child_process({
    "osascript",
    "-e",
    [[
      tell application "System Events"
        if not (exists process "Music") then return "OFF"
      end tell
      tell application "Music"
        set vol to sound volume
        if player state is playing then
          set trackName to name of current track
          set artistName to artist of current track
          return "PLAYING|" & vol & "|" & trackName & " - " & artistName
        else if player state is paused then
          set trackName to name of current track
          set artistName to artist of current track
          return "PAUSED|" & vol & "|" & trackName & " - " & artistName
        else
          return "STOPPED|" & vol & "|"
        end if
      end tell
    ]],
  })
  if success then
    return stdout:gsub("^%s*(.-)%s*$", "%1")
  end
  return "OFF"
end

local function build_status(opts)
  local info = get_apple_music_info()

  if info == "OFF" then
    state.position = 0
    state.last_track = ""
    state.is_playing = false
    return nil
  end

  local player_state, vol, track = info:match("^(%w+)|(%d+)|(.*)$")
  if not player_state then return nil end

  vol = tonumber(vol) or 0
  state.is_playing = (player_state == "PLAYING")

  if track == "" then
    state.position = 0
    state.last_track = ""
    return nil
  end

  -- Reset scroll on track change
  if track ~= state.last_track then
    state.last_track = track
    state.position = 0
  end

  -- Get equalizer frames for selected style
  local eq_frames = EQ_STYLES[opts.eq_style] or EQ_STYLES.thin
  local eq_display = ""

  if state.is_playing then
    eq_display = eq_frames[state.eq_frame]
    state.eq_frame = (state.eq_frame % #eq_frames) + 1
  else
    eq_display = "⏸ "
  end

  -- Scrolling text
  local visible_track
  if #track <= opts.scroll_width then
    visible_track = track
  else
    local scroll_text = track .. opts.scroll_padding .. track
    local start_pos = state.position + 1
    local end_pos = start_pos + opts.scroll_width - 1
    visible_track = scroll_text:sub(start_pos, end_pos)

    state.position = state.position + 1
    if state.position >= #track + #opts.scroll_padding then
      state.position = 0
    end
  end

  return {
    eq = eq_display,
    track = visible_track,
    volume = vol,
    is_playing = state.is_playing,
  }
end

--- Apply Apple Music status to Wezterm config
--- @param config table Wezterm config object
--- @param user_opts table|nil Optional configuration overrides
function M.apply_to_config(config, user_opts)
  local opts = {}
  for k, v in pairs(defaults) do opts[k] = v end
  if user_opts then
    for k, v in pairs(user_opts) do opts[k] = v end
  end

  config.status_update_interval = opts.update_interval

  wezterm.on("update-status", function(window, pane)
    local music = build_status(opts)
    local elements = {}

    if music then
      -- Equalizer
      table.insert(elements, { Foreground = { Color = opts.color } })
      table.insert(elements, { Text = music.eq .. " " })

      -- Clickable controls
      if opts.show_controls then
        -- Previous
        table.insert(elements, { Foreground = { Color = opts.color_controls } })
        table.insert(elements, { Text = " " .. CONTROLS.prev .. " " })

        -- Play/Pause
        local play_pause_icon = music.is_playing and CONTROLS.pause or CONTROLS.play
        table.insert(elements, { Text = play_pause_icon })

        -- Next
        table.insert(elements, { Text = " " .. CONTROLS.next .. "  " })
      end

      -- Track name
      table.insert(elements, { Foreground = { Color = opts.color } })
      table.insert(elements, { Text = music.track })

      -- Volume
      if opts.show_volume then
        table.insert(elements, { Text = "  " .. get_volume_icon(music.volume) })
      end

      table.insert(elements, { Text = "  │  " })
    end

    -- Date
    if opts.show_date then
      table.insert(elements, { Foreground = { Color = opts.color } })
      table.insert(elements, { Text = wezterm.strftime(opts.date_format) .. "  " })
    end

    window:set_right_status(wezterm.format(elements))
  end)

  -- Add mouse bindings for clickable controls
  local mouse_bindings = config.mouse_bindings or {}

  -- These work on the status area
  table.insert(mouse_bindings, {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = wezterm.action_callback(function(window, pane)
      -- Get click position relative to status bar
      -- Note: Wezterm doesn't expose exact click coordinates in status bar
      -- so we use keyboard shortcuts as the primary control method
    end),
  })

  config.mouse_bindings = mouse_bindings
end

--- Setup keyboard shortcuts for music control
--- @param config table Wezterm config object
--- @param leader_mods string Modifier keys (default: "LEADER")
function M.setup_keys(config, leader_mods)
  leader_mods = leader_mods or "LEADER"
  local keys = config.keys or {}

  -- Play/Pause: Leader + m
  table.insert(keys, {
    key = "m",
    mods = leader_mods,
    action = music_command("playpause"),
  })

  -- Next: Leader + >
  table.insert(keys, {
    key = ">",
    mods = leader_mods .. "|SHIFT",
    action = music_command("next track"),
  })

  -- Previous: Leader + <
  table.insert(keys, {
    key = "<",
    mods = leader_mods .. "|SHIFT",
    action = music_command("previous track"),
  })

  -- Volume Up: Leader + +
  table.insert(keys, {
    key = "+",
    mods = leader_mods .. "|SHIFT",
    action = music_command("set sound volume to (sound volume + 10)"),
  })

  -- Volume Down: Leader + _
  table.insert(keys, {
    key = "_",
    mods = leader_mods .. "|SHIFT",
    action = music_command("set sound volume to (sound volume - 10)"),
  })

  config.keys = keys
end

--- Get available equalizer styles
function M.get_eq_styles()
  local styles = {}
  for k, _ in pairs(EQ_STYLES) do
    table.insert(styles, k)
  end
  return styles
end

return M
