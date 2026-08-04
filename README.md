# dotfiles

Linux desktop config, symlinked into place so the live config *is* the repo.

Machine: Framework Desktop (Ryzen AI Max+ 395 / Strix Halo, Radeon 8060S),
Manjaro Sway edition, 1440p dual monitors.

## install

```sh
git clone https://github.com/AndyyTaylor/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Re-runnable: correct links are skipped, anything real in the way is backed up to
`<path>.bak-<timestamp>`. Editing e.g. `~/.config/nvim/lua/config/keymaps.lua`
now edits `nvim/lua/config/keymaps.lua` here, so `git status` shows config drift.

## layout

| path | links to | notes |
|---|---|---|
| `nvim/` | `~/.config/nvim` | LazyVim v16 + LSP/theme/terminal-pane setup; whole dir, `lazy-lock.json` tracked |
| `vscode/` | `~/.config/Code - OSS/User/` | settings + keybindings; `code-flags.conf` goes to `~/.config` |
| `sway/` | `~/.config/sway/` | `config.d/*.conf`, `definitions.d/theme.conf`, `idle.yaml` — per-file, the dirs also hold distro `.example`s |
| `foot/` | `~/.config/foot/` | terminal (server mode; sway launches `footclient`) |
| `waybar/` | `~/.config/waybar/` | bar layered over the Manjaro template |
| `fontconfig/` | `~/.config/fontconfig/` | subpixel RGB + monospace alias |
| `gtklock/` | `~/.config/gtklock/` | lock screen styling |
| `bin/` | `~/.local/bin/` | `lockscreen` (fan-RGB-aware lock wrapper), `nvim-vt` (CPU-rendered nvim on a spare VT) |
| `zsh/zshrc` | `~/.zshrc` | |

Not in here: anything needing root (`/etc/environment` for FreeType stem
darkening, `/etc/sudoers.d/framework-rgb`, GRUB cmdline for GTT size), and
Manjaro's own `/etc/sway` templates that these files layer over.

## gotchas worth remembering

- **nvim colorscheme must be `catppuccin-mocha`, not `catppuccin`** — nvim 0.12
  ships its own `catppuccin.vim` that shadows the plugin and ignores
  `color_overrides` (the flattened `#010101` backgrounds silently revert).
- **foot's `include=` needs an absolute path** — `~` is not expanded, and a bad
  include crash-loops the foot *server*, killing every terminal window at once.
- **VS Code needs `--ozone-platform=x11`** — on Wayland, Chromium refuses LCD
  subpixel text, so it renders visibly blurrier than everything else.
- **sway theme reload rewrites things** — the theme's `90-enable-theme.conf`
  regenerates the wallpaper on *every* reload; `20-output.conf` repaints black
  afterwards. Never reload with `config.d/` files moved aside.
