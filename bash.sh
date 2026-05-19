cat > ~/setup-caelestia.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

sudo pacman -Syu --needed \
  mesa vulkan-intel \
  pipewire pipewire-pulse wireplumber pavucontrol alsa-utils \
  thermald power-profiles-daemon \
  hyprland xdg-desktop-portal-hyprland \
  foot fish fastfetch btop jq eza papirus-icon-theme qt6-wayland

sudo systemctl enable --now thermald power-profiles-daemon

if ! command -v yay >/dev/null 2>&1; then
  tmpdir="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  cd "$tmpdir/yay"
  makepkg -si
fi

yay -S --needed caelestia-shell caelestia-cli

if [[ ! -d "$HOME/.local/share/caelestia" ]]; then
  git clone https://github.com/caelestia-dots/caelestia.git "$HOME/.local/share/caelestia"
fi

fish "$HOME/.local/share/caelestia/install.fish"
EOF
bash ~/setup-caelestia.sh
