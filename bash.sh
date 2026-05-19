#!/usr/bin/env bash
set -euo pipefail

BOOT_PARTUUID="51E4667B-E38F-4715-AA56-D183EEAAC11C"
EFI_PARTUUID="BD8AE51D-0932-40BD-987B-40A854668F45"
ROOT_PARTUUID="9B907FC7-C067-47EF-A272-575E1AD07176"

TARGET_HOSTNAME="${TARGET_HOSTNAME:-archmac}"
TARGET_USERNAME="${TARGET_USERNAME:-lirn}"
TARGET_TIMEZONE="${TARGET_TIMEZONE:-Africa/Cairo}"
TARGET_LOCALE="${TARGET_LOCALE:-en_US.UTF-8}"

info() {
  printf "\n==> %s\n" "$*"
}

die() {
  printf "\nError: %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

resolve_part() {
  local partuuid="$1"
  blkid -t "PARTUUID=${partuuid}" -o device 2>/dev/null || true
}

ensure_online() {
  if ping -c 1 -W 3 archlinux.org >/dev/null 2>&1; then
    return
  fi

  cat <<'EOF'

No working internet connection was detected.

Connect Wi-Fi first:
  iwctl
  device list
  station <wifi_device> scan
  station <wifi_device> get-networks
  station <wifi_device> connect "Your WiFi Name"
  exit

EOF

  read -r -p "Press Enter after networking is working..."
  ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || die "Still no internet connection."
}

maybe_reexec_from_tmp() {
  local src mount_dev
  src="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  mount_dev="$(df "$src" 2>/dev/null | awk 'END {print $1}')"

  if [[ "$mount_dev" == "$BOOT_DEV" || "$mount_dev" == "$EFI_DEV" || "$mount_dev" == "$ROOT_DEV" ]]; then
    cp "$src" /tmp/bash.sh
    chmod +x /tmp/bash.sh
    exec /bin/bash /tmp/bash.sh
  fi
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this script as root from the Arch live USB."
}

require_tools() {
  local tools=(
    blkid lsblk ping mkfs.fat mkfs.ext4 mount umount pacstrap genfstab
    arch-chroot grub-install grub-mkconfig sed useradd passwd chown
  )
  local tool
  for tool in "${tools[@]}"; do
    need_cmd "$tool"
  done
}

discover_partitions() {
  BOOT_DEV="$(resolve_part "$BOOT_PARTUUID")"
  EFI_DEV="$(resolve_part "$EFI_PARTUUID")"
  ROOT_DEV="$(resolve_part "$ROOT_PARTUUID")"

  [[ -n "$BOOT_DEV" && -b "$BOOT_DEV" ]] || die "Could not find BOOT partition."
  [[ -n "$EFI_DEV" && -b "$EFI_DEV" ]] || die "Could not find EFI partition."
  [[ -n "$ROOT_DEV" && -b "$ROOT_DEV" ]] || die "Could not find ROOT partition."
}

show_plan() {
  info "Detected target partitions"
  printf "BOOT=%s\nEFI=%s\nROOT=%s\n" "$BOOT_DEV" "$EFI_DEV" "$ROOT_DEV"
  lsblk -o NAME,SIZE,FSTYPE,PARTUUID "$BOOT_DEV" "$EFI_DEV" "$ROOT_DEV"

  cat <<EOF

Install plan:
  Hostname: ${TARGET_HOSTNAME}
  Username: ${TARGET_USERNAME}
  Timezone: ${TARGET_TIMEZONE}
  Locale:   ${TARGET_LOCALE}

EOF
}

confirm_destruction() {
  cat <<EOF

This script will erase and reinstall Linux on:
  $BOOT_DEV  -> /boot
  $EFI_DEV   -> /efi
  $ROOT_DEV  -> /

It will not touch the macOS APFS partitions.

EOF

  local answer
  read -r -p "Type ERASE to continue: " answer
  [[ "$answer" == "ERASE" ]] || die "Cancelled."
}

format_targets() {
  info "Formatting target partitions"
  mkfs.fat -F 32 "$BOOT_DEV"
  mkfs.fat -F 32 "$EFI_DEV"
  mkfs.ext4 -L archroot "$ROOT_DEV"
}

mount_targets() {
  info "Mounting target partitions"
  mount "$ROOT_DEV" /mnt
  mkdir -p /mnt/boot /mnt/efi
  mount "$BOOT_DEV" /mnt/boot
  mount "$EFI_DEV" /mnt/efi
}

install_base() {
  info "Installing base Arch system"
  pacstrap -K /mnt \
    base linux linux-firmware intel-ucode \
    networkmanager iwd sudo vim git base-devel \
    linux-headers broadcom-wl grub efibootmgr fish \
    greetd tuigreet bluez bluez-utils \
    pipewire pipewire-pulse wireplumber pavucontrol alsa-utils \
    thermald power-profiles-daemon \
    gnome-keyring polkit-gnome gammastep geoclue \
    mesa vulkan-intel xdg-user-dirs xorg-xwayland \
    python python-pillow

  genfstab -U /mnt >> /mnt/etc/fstab
}

write_postinstall_script() {
  cat > /mnt/root/post-install.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

TARGET_HOSTNAME='${TARGET_HOSTNAME}'
TARGET_USERNAME='${TARGET_USERNAME}'
TARGET_TIMEZONE='${TARGET_TIMEZONE}'
TARGET_LOCALE='${TARGET_LOCALE}'

info() {
  printf "\n==> %s\n" "\$*"
}

info "Configuring locale, time and hostname"
ln -sf "/usr/share/zoneinfo/\${TARGET_TIMEZONE}" /etc/localtime
hwclock --systohc
sed -i "s/^#\${TARGET_LOCALE} UTF-8/\${TARGET_LOCALE} UTF-8/" /etc/locale.gen
locale-gen
printf 'LANG=%s\n' "\${TARGET_LOCALE}" > /etc/locale.conf
printf '%s\n' "\${TARGET_HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 \${TARGET_HOSTNAME}.localdomain \${TARGET_HOSTNAME}
HOSTS

if ! id -u "\${TARGET_USERNAME}" >/dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash "\${TARGET_USERNAME}"
fi

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "\${TARGET_USERNAME}" > "/etc/sudoers.d/99-\${TARGET_USERNAME}-installer"
chmod 440 "/etc/sudoers.d/99-\${TARGET_USERNAME}-installer"

info "Configuring Apple keyboard defaults"
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/hid_apple.conf <<'APPLE'
options hid_apple fnmode=1 swap_opt_cmd=0
APPLE
mkinitcpio -P

info "Configuring greetd login"
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd Hyprland"
user = "greeter"
GREETD

grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable thermald
systemctl enable power-profiles-daemon
systemctl enable greetd

info "Installing yay"
su - "\${TARGET_USERNAME}" -c '
set -e
tmpdir=\$(mktemp -d)
git clone https://aur.archlinux.org/yay.git "\$tmpdir/yay"
cd "\$tmpdir/yay"
makepkg -si --noconfirm
yay -Y --gendb --noconfirm
yay -Y --devel --save --noconfirm
'

info "Cloning Caelestia dotfiles"
su - "\${TARGET_USERNAME}" -c '
set -e
mkdir -p ~/.local/share
if [ -d ~/.local/share/caelestia/.git ]; then
  git -C ~/.local/share/caelestia pull --ff-only
else
  rm -rf ~/.local/share/caelestia
  git clone --depth 1 https://github.com/caelestia-dots/caelestia.git ~/.local/share/caelestia
fi
'

info "Installing Caelestia packages"
su - "\${TARGET_USERNAME}" -c '
set -e
cd ~/.local/share/caelestia
yay -Bi . --noconfirm --needed --answerclean None --answerdiff None --answeredit None
rm -f caelestia-meta-*.pkg.tar.zst
'

info "Installing Mac fan control"
su - "\${TARGET_USERNAME}" -c '
set -e
yay -S --needed --noconfirm --answerclean None --answerdiff None --answeredit None mbpfan
'

info "Configuring Mac fan control"
mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/macbook-thermal.conf <<'MODULES'
applesmc
coretemp
MODULES

cat > /etc/mbpfan.conf <<'MBPFAN'
[general]
low_temp = 63
high_temp = 66
max_temp = 86
polling_interval = 1
MBPFAN

systemctl enable mbpfan

info "Linking Caelestia configs"
su - "\${TARGET_USERNAME}" -c '
set -e
repo=~/.local/share/caelestia
config=\${XDG_CONFIG_HOME:-\$HOME/.config}

mkdir -p "\$config"
rm -rf "\$config/hypr" "\$config/foot" "\$config/fish" "\$config/fastfetch" "\$config/uwsm" "\$config/btop"
rm -f "\$config/starship.toml"

ln -s "\$repo/hypr" "\$config/hypr"
ln -s "\$repo/foot" "\$config/foot"
ln -s "\$repo/fish" "\$config/fish"
ln -s "\$repo/fastfetch" "\$config/fastfetch"
ln -s "\$repo/uwsm" "\$config/uwsm"
ln -s "\$repo/btop" "\$config/btop"
ln -s "\$repo/starship.toml" "\$config/starship.toml"
chmod u+x "\$config/hypr/scripts/wsaction.fish"
'

info "Writing user overrides"
su - "\${TARGET_USERNAME}" -c '
set -e
mkdir -p ~/.config/caelestia ~/Pictures/Wallpapers
cat > ~/.config/caelestia/hypr-vars.conf <<HYPRVARS
\$workspaceSwipeFingers = 3
HYPRVARS

cat > ~/.config/caelestia/hypr-user.conf <<HYPRUSER
input {
    natural_scroll = true

    touchpad {
        natural_scroll = true
        tap-to-click = true
        tap-and-drag = true
        drag_lock = true
        clickfinger_behavior = true
    }
}

misc {
    vrr = 0
}
HYPRUSER
'

info "Generating fallback wallpaper"
su - "\${TARGET_USERNAME}" -c '
set -e
python - <<PY
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

wall = Path.home() / "Pictures" / "Wallpapers" / "caelestia-default.png"
wall.parent.mkdir(parents=True, exist_ok=True)
w, h = 2560, 1600
img = Image.new("RGB", (w, h))
pix = img.load()
top = (255, 248, 246)
bottom = (241, 223, 218)
for y in range(h):
    t = y / (h - 1)
    r = int(top[0] * (1 - t) + bottom[0] * t)
    g = int(top[1] * (1 - t) + bottom[1] * t)
    b = int(top[2] * (1 - t) + bottom[2] * t)
    for x in range(w):
        pix[x, y] = (r, g, b)

overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
draw = ImageDraw.Draw(overlay)
draw.ellipse((-220, 1050, 1100, 2400), fill=(143, 75, 58, 46))
draw.ellipse((1450, -250, 3000, 1300), fill=(121, 89, 12, 36))
draw.rounded_rectangle((520, 210, 2050, 1150), radius=120, fill=(255, 255, 255, 34))
draw.arc((760, 470, 1800, 1510), start=200, end=332, fill=(119, 87, 79, 150), width=8)
overlay = overlay.filter(ImageFilter.GaussianBlur(6))
img = Image.alpha_composite(img.convert("RGBA"), overlay)
img.save(wall, "PNG")
PY
'

info "Seeding Caelestia wallpaper and scheme"
su - "\${TARGET_USERNAME}" -c '
set -e
caelestia scheme set -n shadotheme
caelestia wallpaper -f "$HOME/Pictures/Wallpapers/caelestia-default.png"
caelestia scheme set -n dynamic
'

info "Refreshing XDG user dirs"
su - "\${TARGET_USERNAME}" -c '
set -e
xdg-user-dirs-update || true
'

chsh -s /usr/bin/fish "\${TARGET_USERNAME}"

rm -f "/etc/sudoers.d/99-\${TARGET_USERNAME}-installer"

info "Set the root password"
passwd

info "Set the password for \${TARGET_USERNAME}"
passwd "\${TARGET_USERNAME}"
EOF

  chmod +x /mnt/root/post-install.sh
}

configure_system() {
  info "Configuring installed system and full Caelestia setup"
  write_postinstall_script
  arch-chroot /mnt /bin/bash /root/post-install.sh
}

finish_install() {
  info "Cleaning up mounts"
  rm -f /mnt/root/post-install.sh
  umount -R /mnt

  cat <<EOF

Install completed.

Next:
  1. Reboot
  2. Hold Option and choose EFI Boot
  3. Log in via the greetd screen

EOF

  local reboot_answer
  read -r -p "Reboot now? [y/N]: " reboot_answer
  if [[ "${reboot_answer}" =~ ^[Yy]$ ]]; then
    reboot
  fi
}

main() {
  require_root
  require_tools
  timedatectl set-ntp true
  ensure_online
  discover_partitions
  maybe_reexec_from_tmp
  show_plan
  confirm_destruction
  format_targets
  mount_targets
  install_base
  configure_system
  finish_install
}

main "$@"
