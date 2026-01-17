# Wezterm Apple Music Plugin

A Wezterm status bar plugin for Apple Music with smooth scrolling track titles, animated equalizer, and playback controls.

## Features

- **Smooth scrolling** - Marquee effect for long track titles
- **Animated equalizer** - Multiple styles (thin, classic, dots, bars, wave)
- **Playback controls** - Visual prev/play-pause/next buttons
- **Volume indicator** - Nerd Font icons showing current level
- **Pause state** - Shows ⏸ when paused
- **Keyboard shortcuts** - Full playback control via leader key

## Requirements

- macOS with Apple Music
- Wezterm
- Nerd Font (for icons)

## Installation

Copy `apple-music.lua` to your Wezterm config plugins directory:

```
~/.config/wezterm/plugins/apple-music.lua
```

## Usage

In your `wezterm.lua`:

```lua
local apple_music = require("plugins.apple-music")

-- Apply to config with options
apple_music.apply_to_config(config, {
  update_interval = 500,      -- ms between updates
  scroll_width = 30,          -- max visible characters
  eq_style = "thin",          -- equalizer style
  color = "#7aa2f7",          -- status text color
  show_controls = true,       -- show prev/play/next
  show_volume = true,         -- show volume icon
})

-- Setup keyboard shortcuts
apple_music.setup_keys(config)
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `update_interval` | 500 | Refresh rate in ms |
| `scroll_width` | 30 | Max visible track characters |
| `scroll_padding` | `"   ·   "` | Separator in scroll loop |
| `color` | `"#7aa2f7"` | Main text color |
| `color_controls` | `"#565f89"` | Control icons color |
| `eq_style` | `"thin"` | Equalizer animation style |
| `show_volume` | true | Show volume icon |
| `show_controls` | true | Show playback controls |
| `show_date` | true | Show date/time |
| `date_format` | `"%a %b %-d %H:%M"` | strftime format |

## Equalizer Styles

- `thin` - Thin growing bars: `▏▎▍`
- `classic` - Block bars: `▁▃▅`
- `dots` - Bouncing dots: `●○●`
- `bars` - Line bars: `┃╏╏`
- `wave` - Wave pattern: `∿∿∿`

## Keyboard Shortcuts

After calling `apple_music.setup_keys(config)`:

| Binding | Action |
|---------|--------|
| `C-a m` | Play/Pause |
| `C-a >` | Next track |
| `C-a <` | Previous track |
| `C-a +` | Volume up |
| `C-a _` | Volume down |

## License

MIT
