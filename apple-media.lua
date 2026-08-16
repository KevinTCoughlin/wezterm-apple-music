-- apple-media.lua
-- Apple Media status bar plugin for WezTerm
-- Supports: Apple Music, Apple Podcasts, Apple TV
-- https://github.com/KevinTCoughlin/wezterm-apple-music
--
-- Usage:
--   local apple_media = require("plugins.apple-media")
--   apple_media.apply_to_config(config)
--   apple_media.setup_keys(config)

local wezterm = require("wezterm")
local M = {}
local FIELD_SEPARATOR = string.char(31)

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

local defaults = {
  update_interval = 500,
  scroll_width = 30,
  scroll_padding = "  ·  ",

  colors = {
    eq = "#7aa2f7",
    track = "#c0caf5",
    controls = "#7dcfff",
    play = "#9ece6a",
    pause = "#f7768e",
    volume = "#bb9af7",
    music = "#7aa2f7",
    podcast = "#e0af68",
    tv = "#f7768e",
    date = "#565f89",
  },

  eq_style = "thin",
  show_volume = true,
  show_controls = true,
  show_app_icon = true,
  show_date = true,
  date_format = "%a %b %-d %H:%M",
}

-------------------------------------------------------------------------------
-- Equalizer Styles
-------------------------------------------------------------------------------

local EQ_STYLES = {
  thin = { "▏▎▍", "▎▍▌", "▍▌▋", "▌▋▊", "▋▊▉", "▊▉▊", "▉▊▋", "▊▋▌", "▋▌▍", "▌▍▎", "▍▎▏", "▎▏▎" },
  classic = { "▁▃▅", "▂▅▃", "▃▂▅", "▅▃▂", "▃▅▃", "▂▃▅" },
  dots = { "●○●", "○●○", "●●○", "○●●", "●○○", "○○●" },
  mini = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  wave = { "∿∿∿", "∾∿∿", "∿∾∿", "∿∿∾" },
}

-------------------------------------------------------------------------------
-- Icons (Nerd Font)
-------------------------------------------------------------------------------

local ICONS = {
  music = "󰎆",
  podcast = "󰦔",
  tv = "󰕼",
  prev = "󰒮",
  play = "󰐊",
  pause = "󰏤",
  next = "󰒭",
  vol_mute = "󰖁",
  vol_low = "󰕿",
  vol_med = "󰖀",
  vol_high = "󰕾",
}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local state = {
  position = 0,
  last_track = "",
  eq_frame = 1,
  is_playing = false,
  app = nil,
}
local warned_unsupported = false
local query_error_reported = false

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function get_volume_icon(vol)
  if vol == 0 then return ICONS.vol_mute
  elseif vol <= 33 then return ICONS.vol_low
  elseif vol <= 66 then return ICONS.vol_med
  else return ICONS.vol_high end
end

local function is_macos()
  return type(wezterm.target_triple) == "string"
    and wezterm.target_triple:find("apple%-darwin") ~= nil
end

local function utf8_len(value)
  local _, count = value:gsub("[^\128-\191]", "")
  return count
end

local function utf8_sub(value, first, last)
  local start_byte = utf8.offset(value, first)
  if not start_byte then return "" end
  local end_byte = utf8.offset(value, last + 1)
  return value:sub(start_byte, end_byte and (end_byte - 1) or -1)
end

local function merge_opts(user_opts)
  local opts = {}
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      opts[k] = {}
      for kk, vv in pairs(v) do opts[k][kk] = vv end
      if user_opts and user_opts[k] then
        for kk, vv in pairs(user_opts[k]) do opts[k][kk] = vv end
      end
    else
      if user_opts and user_opts[k] ~= nil then
        opts[k] = user_opts[k]
      else
        opts[k] = v
      end
    end
  end
  return opts
end

-------------------------------------------------------------------------------
-- Media Detection
-------------------------------------------------------------------------------

local function get_media_info()
  if not is_macos() then
    if not warned_unsupported then
      wezterm.log_error("wezterm-apple-music is only supported on macOS")
      warned_unsupported = true
    end
    return nil
  end

  local ok, out, err = wezterm.run_child_process({
    "osascript", "-e", [[
      -- Check Music
      tell application "System Events"
        if exists process "Music" then
          tell application "Music"
            if player state is playing then
              set vol to sound volume
              set trackName to name of current track
              set artistName to artist of current track
              set isPlaying to (player state is playing)
              set sep to ASCII character 31
              return "music" & sep & isPlaying & sep & vol & sep & trackName & sep & artistName
            end if
          end tell
        end if
      end tell

      -- Check Podcasts
      tell application "System Events"
        if exists process "Podcasts" then
          tell application "Podcasts"
            if player state is playing then
              set vol to sound volume
              set epName to name of current episode
              set showName to name of (show of current episode)
              set isPlaying to (player state is playing)
              set sep to ASCII character 31
              return "podcast" & sep & isPlaying & sep & vol & sep & epName & sep & showName
            end if
          end tell
        end if
      end tell

      -- Check TV
      tell application "System Events"
        if exists process "TV" then
          tell application "TV"
            if player state is playing then
              set vol to sound volume
              set vidName to name of current track
              set showName to ""
              try
                set showName to show of current track
              end try
              if showName is "" then set showName to album of current track
              set isPlaying to (player state is playing)
              set sep to ASCII character 31
              return "tv" & sep & isPlaying & sep & vol & sep & vidName & sep & showName
            end if
          end tell
        end if
      end tell

      -- Fall back to a paused app only when nothing is playing.
      tell application "System Events"
        if exists process "Music" then
          tell application "Music"
            if player state is paused then
              set sep to ASCII character 31
              return "music" & sep & false & sep & sound volume & sep & name of current track & sep & artist of current track
            end if
          end tell
        end if
        if exists process "Podcasts" then
          tell application "Podcasts"
            if player state is paused then
              set sep to ASCII character 31
              return "podcast" & sep & false & sep & sound volume & sep & name of current episode & sep & name of (show of current episode)
            end if
          end tell
        end if
        if exists process "TV" then
          tell application "TV"
            if player state is paused then
              set sep to ASCII character 31
              set showName to ""
              try
                set showName to show of current track
              end try
              if showName is "" then set showName to album of current track
              return "tv" & sep & false & sep & sound volume & sep & name of current track & sep & showName
            end if
          end tell
        end if
      end tell

      return "OFF"
    ]]
  })

  if not ok then
    if not query_error_reported then
      wezterm.log_error("Apple media query failed: " .. (err or "unknown error"))
      query_error_reported = true
    end
    return nil
  end
  query_error_reported = false
  local result = out:gsub("^%s*(.-)%s*$", "%1")
  if result == "OFF" or result == "" then return nil end

  local sep = FIELD_SEPARATOR:gsub("(%W)", "%%%1")
  local app, playing, vol, title, subtitle =
    result:match("^([^" .. sep .. "]+)" .. sep .. "([^" .. sep .. "]+)" .. sep
      .. "([^" .. sep .. "]+)" .. sep .. "([^" .. sep .. "]*)" .. sep .. "(.*)$")
  if not app then return nil end

  return {
    app = app,
    playing = playing == "true",
    volume = tonumber(vol) or 0,
    title = title or "",
    subtitle = subtitle or "",
  }
end

local MEDIA_COMMANDS = {
  playpause = "playpause",
  next = "next track",
  previous = "previous track",
  volume_up = [[
    set newVolume to sound volume + 10
    if newVolume > 100 then set newVolume to 100
    set sound volume to newVolume
  ]],
  volume_down = [[
    set newVolume to sound volume - 10
    if newVolume < 0 then set newVolume to 0
    set sound volume to newVolume
  ]],
}

local function media_command(command)
  local script_command = assert(MEDIA_COMMANDS[command], "unknown media command")
  return wezterm.action_callback(function()
    if not is_macos() then return end
    local ok, _, err = wezterm.run_child_process({ "osascript", "-e", [[
      tell application "System Events"
        if exists process "Music" then
          tell application "Music"
            if player state is playing then
              ]] .. script_command .. [[
              return
            end if
          end tell
        end if
        if exists process "Podcasts" then
          tell application "Podcasts"
            if player state is playing then
              ]] .. script_command .. [[
              return
            end if
          end tell
        end if
        if exists process "TV" then
          tell application "TV"
            if player state is playing then
              ]] .. script_command .. [[
              return
            end if
          end tell
        end if
        if exists process "Music" then
          tell application "Music"
            if player state is paused then
              ]] .. script_command .. [[
              return
            end if
          end tell
        end if
        if exists process "Podcasts" then
          tell application "Podcasts"
            if player state is paused then
              ]] .. script_command .. [[
              return
            end if
          end tell
        end if
        if exists process "TV" then
          tell application "TV"
            if player state is paused then
              ]] .. script_command .. [[
              return
            end if
          end tell
        end if
      end tell
    ]] })
    if not ok then
      wezterm.log_error("Apple media command failed: " .. (err or command))
    end
  end)
end

-------------------------------------------------------------------------------
-- Status Builder
-------------------------------------------------------------------------------

local function build_status(opts)
  local info = get_media_info()
  if not info then
    state = { position = 0, last_track = "", eq_frame = 1, is_playing = false, app = nil }
    return nil
  end

  state.is_playing = info.playing
  state.app = info.app

  local display = info.title
  if info.subtitle and info.subtitle ~= "" then
    display = display .. " — " .. info.subtitle
  end

  if display ~= state.last_track then
    state.last_track = display
    state.position = 0
  end

  local eq_frames = EQ_STYLES[opts.eq_style] or EQ_STYLES.thin
  local eq = state.is_playing and eq_frames[state.eq_frame] or "⏸"
  if state.is_playing then
    state.eq_frame = (state.eq_frame % #eq_frames) + 1
  end

  local visible
  local display_length = utf8_len(display)
  local padding_length = utf8_len(opts.scroll_padding)
  if display_length <= opts.scroll_width then
    visible = display
  else
    local scroll = display .. opts.scroll_padding .. display
    visible = utf8_sub(scroll, state.position + 1, state.position + opts.scroll_width)
    state.position = (state.position + 1) % (display_length + padding_length)
  end

  return {
    app = info.app,
    eq = eq,
    display = visible,
    volume = info.volume,
    playing = info.playing,
  }
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function M.apply_to_config(config, user_opts)
  local opts = merge_opts(user_opts)
  opts.update_interval = math.max(100, tonumber(opts.update_interval) or defaults.update_interval)
  opts.scroll_width = math.max(1, math.floor(tonumber(opts.scroll_width) or defaults.scroll_width))
  if type(opts.scroll_padding) ~= "string" or opts.scroll_padding == "" then
    opts.scroll_padding = defaults.scroll_padding
  end
  config.status_update_interval = opts.update_interval

  wezterm.on("update-status", function(window, pane)
    local m = build_status(opts)
    local e = {}
    local colors = opts.colors

    if m then
      -- App icon
      if opts.show_app_icon then
        local icon = ICONS.music
        local icon_color = colors.music
        if m.app == "podcast" then
          icon = ICONS.podcast
          icon_color = colors.podcast
        elseif m.app == "tv" then
          icon = ICONS.tv
          icon_color = colors.tv
        end
        table.insert(e, { Foreground = { Color = icon_color } })
        table.insert(e, { Text = icon .. " " })
      end

      -- Equalizer
      table.insert(e, { Foreground = { Color = colors.eq } })
      table.insert(e, { Text = m.eq .. "  " })

      -- Controls
      if opts.show_controls then
        table.insert(e, { Foreground = { Color = colors.controls } })
        table.insert(e, { Text = ICONS.prev .. " " })

        table.insert(e, { Foreground = { Color = m.playing and colors.pause or colors.play } })
        table.insert(e, { Text = (m.playing and ICONS.pause or ICONS.play) .. " " })

        table.insert(e, { Foreground = { Color = colors.controls } })
        table.insert(e, { Text = ICONS.next .. "  " })
      end

      -- Track/Episode/Video
      table.insert(e, { Foreground = { Color = colors.track } })
      table.insert(e, { Text = m.display })

      -- Volume
      if opts.show_volume then
        table.insert(e, { Foreground = { Color = colors.volume } })
        table.insert(e, { Text = "  " .. get_volume_icon(m.volume) })
      end

      table.insert(e, { Foreground = { Color = colors.date } })
      table.insert(e, { Text = "  │  " })
    end

    if opts.show_date then
      table.insert(e, { Foreground = { Color = colors.date } })
      table.insert(e, { Text = wezterm.strftime(opts.date_format) .. "  " })
    end

    window:set_right_status(#e > 0 and wezterm.format(e) or "")
  end)
end

function M.setup_keys(config, mods)
  mods = mods or "LEADER"
  local keys = config.keys or {}

  local bindings = {
    { key = "m", cmd = "playpause" },
    { key = ">", shift = true, cmd = "next" },
    { key = "<", shift = true, cmd = "previous" },
    { key = "+", shift = true, cmd = "volume_up" },
    { key = "_", shift = true, cmd = "volume_down" },
  }

  for _, b in ipairs(bindings) do
    table.insert(keys, {
      key = b.key,
      mods = b.shift and (mods .. "|SHIFT") or mods,
      action = media_command(b.cmd),
    })
  end

  config.keys = keys
end

return M
