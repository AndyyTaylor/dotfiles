#!/usr/bin/env bash
# Symlink every config in this repo into place, so editing the live config edits
# the repo (and `git status` here shows what has drifted).
#
# Safe to re-run: already-correct links are skipped, and anything real that is in
# the way is moved to <path>.bak-YYYYmmddHHMMSS rather than deleted.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
OS="$(uname -s)"

link() {
    local src="$DOTFILES/$1" dst="$2"

    if [ ! -e "$src" ]; then
        printf '  !! missing in repo: %s\n' "$1"
        return
    fi
    if [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ]; then
        printf '  ok %s\n' "${dst/#$HOME/\~}"
        return
    fi

    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mv "$dst" "$dst.bak-$STAMP"
        printf '  ~~ backed up %s\n' "${dst/#$HOME/\~}"
    fi
    ln -s "$src" "$dst"
    printf '  -> %s\n' "${dst/#$HOME/\~}"
}

echo "neovim (whole dir, so lazy-lock.json stays tracked)"
link nvim "$CONFIG/nvim"

# the mac borrows nvim and a terminal, nothing else -- everything below this block
# is sway-desktop specific with no mac equivalent, and zsh/zshrc in particular is
# manjaro-only and would clobber a working ~/.zshrc.
if [ "$OS" = "Darwin" ]; then
    echo "kitty (mac terminal; foot is linux-only)"
    link kitty/kitty.conf "$CONFIG/kitty/kitty.conf"

    cat <<'NOTE'

done. kitty and nvim pick changes up on next launch.
first run on a new mac also needs:
  brew install neovim ripgrep fd lazygit
  brew install --cask kitty font-jetbrains-mono-nerd-font
NOTE
    exit 0
fi

echo "vscode (Code - OSS)"
link vscode/settings.json    "$CONFIG/Code - OSS/User/settings.json"
link vscode/keybindings.json "$CONFIG/Code - OSS/User/keybindings.json"
# forces XWayland: chromium refuses LCD subpixel text on wayland
link vscode/code-flags.conf  "$CONFIG/code-flags.conf"

# Per-file, not per-dir: these dirs also hold distro-shipped .example files and
# sway's generated wallpaper, which are not ours to own.
echo "sway"
for f in "$DOTFILES"/sway/config.d/*.conf; do
    link "sway/config.d/$(basename "$f")" "$CONFIG/sway/config.d/$(basename "$f")"
done
link sway/definitions.d/theme.conf "$CONFIG/sway/definitions.d/theme.conf"
link sway/idle.yaml                "$CONFIG/sway/idle.yaml"

echo "foot / waybar / fonts / gtklock"
link foot/foot.ini          "$CONFIG/foot/foot.ini"
link foot/foot-theme.ini    "$CONFIG/foot/foot-theme.ini"
link waybar/config.jsonc    "$CONFIG/waybar/config.jsonc"
link waybar/style.css       "$CONFIG/waybar/style.css"
link waybar/colors.css      "$CONFIG/waybar/colors.css"
link fontconfig/fonts.conf  "$CONFIG/fontconfig/fonts.conf"
link fontconfig/conf.d/51-monospace.conf "$CONFIG/fontconfig/conf.d/51-monospace.conf"
link gtklock/style.css      "$CONFIG/gtklock/style.css"

echo "scripts / shell"
link bin/lockscreen "$HOME/.local/bin/lockscreen"
link bin/nvim-vt    "$HOME/.local/bin/nvim-vt"
link zsh/zshrc      "$HOME/.zshrc"

cat <<'NOTE'

done. to apply without logging out:
  swaymsg reload                        # sway, waybar
  systemctl --user restart swayidle     # idle/lock timeouts
  fc-cache -r                           # fonts
foot / vscode / nvim pick changes up on next launch.
NOTE
