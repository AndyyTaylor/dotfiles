# dotfiles

Linux desktop config, symlinked into place so the live config *is* the repo.
The mac shares `nvim/` and gets `kitty/` in place of foot; nothing else.

Machines:

- Framework Desktop (Ryzen AI Max+ 395 / Strix Halo, Radeon 8060S), Manjaro Sway
  edition, 1440p dual monitors — everything here.
- MacBook (Apple silicon) — `nvim/` + `kitty/` only. `install.sh` detects Darwin
  and stops after those two, so sway/waybar/foot/`zshrc` never land on it.

## install

```sh
git clone https://github.com/AndyyTaylor/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Re-runnable: correct links are skipped, anything real in the way is backed up to
`<path>.bak-<timestamp>`. Editing e.g. `~/.config/nvim/lua/config/keymaps.lua`
now edits `nvim/lua/config/keymaps.lua` here, so `git status` shows config drift.

The mac has no package set of its own, so a fresh one also needs:

```sh
brew install neovim ripgrep fd lazygit
brew install --cask kitty font-jetbrains-mono-nerd-font
```

`clangd` needs no install there — the Xcode command line tools ship one, and its
resource dir matches the toolchain the C++ build uses, which is the same reason
`clangd.lua` pins the system binary over a Mason-managed one on Linux.

## layout

| path | links to | notes |
|---|---|---|
| `nvim/` | `~/.config/nvim` | both OSes. LazyVim v16 + LSP/theme/terminal-pane setup; whole dir, `lazy-lock.json` tracked |
| `kitty/` | `~/.config/kitty/` | mac only. terminal; nerd font named explicitly (no fontconfig on macos) + foot's palette |
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
- **macos has no fontconfig**, so the `monospace` → `JetBrainsMono NF` alias in
  `fontconfig/` does nothing there. `kitty/kitty.conf` names the family outright;
  without it every nvim devicon is a tofu box.
- **second machine: `:Lazy restore`, not `:Lazy sync`** — `sync` updates plugins
  past the tracked `lazy-lock.json` and rewrites it, so the two machines drift
  apart on first launch. `restore` installs at the locked commits and leaves the
  lockfile clean.
- **VS Code needs `--ozone-platform=x11`** — on Wayland, Chromium refuses LCD
  subpixel text, so it renders visibly blurrier than everything else.
- **sway theme reload rewrites things** — the theme's `90-enable-theme.conf`
  regenerates the wallpaper on *every* reload; `20-output.conf` repaints black
  afterwards. Never reload with `config.d/` files moved aside.
