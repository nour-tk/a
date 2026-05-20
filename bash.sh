cat > ~/install.sh << 'INSTALL'
#!/usr/bin/env bash
set -euo pipefail

BOOT_DEV="/dev/nvme0n1p3"
EFI_DEV="/dev/nvme0n1p6"
ROOT_DEV="/dev/nvme0n1p4"
TARGET_HOSTNAME="archmac"
TARGET_USERNAME="lirn"
TARGET_TIMEZONE="Africa/Cairo"
TARGET_LOCALE="en_US.UTF-8"

info() { printf "\n\e[1;34m==> %s\e[0m\n" "$*"; }
die()  { printf "\nError: %s\n" "$*" >&2; exit 1; }

info "Loading Broadcom WiFi driver"
modprobe -r b43 ssb wl 2>/dev/null || true
modprobe wl 2>/dev/null || true
sleep 2
rfkill unblock all 2>/dev/null || true
sleep 1

info "Bringing up WiFi"
WIFI_DEV=$(ip link | awk -F': ' '/^[0-9]+: w/{print $2; exit}')
echo "WiFi device: ${WIFI_DEV:-none}"
if [[ -n "${WIFI_DEV:-}" ]]; then
  ip link set "$WIFI_DEV" up 2>/dev/null || true
  wpa_supplicant -B -i "$WIFI_DEV" -c <(wpa_passphrase "0" "salahbedairr") 2>/dev/null || \
  wpa_supplicant -B -i "$WIFI_DEV" -c <(wpa_passphrase "arti" "alta1234") 2>/dev/null || true
  sleep 4
  dhcpcd "$WIFI_DEV" 2>/dev/null || dhclient "$WIFI_DEV" 2>/dev/null || true
  sleep 3
fi

ping -c 1 archlinux.org >/dev/null 2>&1 || die "No internet - connect manually then rerun"
echo "Online!"

info "Refreshing mirrors"
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true

timedatectl set-ntp true

info "Unmounting"
umount -R /mnt 2>/dev/null || true

info "Formatting"
mkfs.fat -F32 "$BOOT_DEV"
mkfs.fat -F32 "$EFI_DEV"
mkfs.ext4 -F -L archroot "$ROOT_DEV"

info "Mounting"
mount "$ROOT_DEV" /mnt
mkdir -p /mnt/boot /mnt/efi
mount "$BOOT_DEV" /mnt/boot
mount "$EFI_DEV" /mnt/efi

info "Installing base system"
pacstrap -K /mnt \
  base linux linux-firmware intel-ucode \
  networkmanager iwd sudo vim git base-devel \
  linux-headers broadcom-wl grub efibootmgr fish \
  greetd bluez bluez-utils \
  pipewire pipewire-pulse wireplumber pavucontrol alsa-utils \
  thermald power-profiles-daemon \
  gnome-keyring polkit-gnome gammastep geoclue \
  mesa vulkan-intel xdg-user-dirs xorg-xwayland \
  python python-pillow brightnessctl \
  libinput xf86-input-libinput wl-clipboard

genfstab -U /mnt >> /mnt/etc/fstab

info "Configuring system"
arch-chroot /mnt /bin/bash << EOF
set -euo pipefail

ln -sf /usr/share/zoneinfo/$TARGET_TIMEZONE /etc/localtime
hwclock --systohc
sed -i "s/^#$TARGET_LOCALE UTF-8/$TARGET_LOCALE UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=$TARGET_LOCALE" > /etc/locale.conf
echo "$TARGET_HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 $TARGET_HOSTNAME.localdomain $TARGET_HOSTNAME
HOSTS

useradd -m -G wheel,video,input -s /usr/bin/fish $TARGET_USERNAME 2>/dev/null || true
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "$TARGET_USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-installer
chmod 440 /etc/sudoers.d/99-installer

mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/hid_apple.conf << APPLE
options hid_apple fnmode=1
options hid_apple iso_layout=0
options hid_apple swap_opt_cmd=0
APPLE

mkdir -p /etc/tmpfiles.d
echo "w /sys/class/leds/smc::kbd_backlight/brightness - - - - 100" > /etc/tmpfiles.d/kbd-backlight.conf

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/30-touchpad.conf << TRACKPAD
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "TappingDrag" "on"
    Option "TappingDragLock" "on"
    Option "NaturalScrolling" "true"
    Option "ScrollMethod" "twofinger"
    Option "ClickMethod" "clickfinger"
    Option "DisableWhileTyping" "true"
EndSection
TRACKPAD

mkinitcpio -P

mkdir -p /etc/greetd
cat > /etc/greetd/config.toml << GREETD
[terminal]
vt = 1
[default_session]
command = "tuigreet --time --remember --cmd Hyprland"
user = "greeter"
GREETD

grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager bluetooth thermald power-profiles-daemon greetd

mkdir -p /etc/modules-load.d
printf 'applesmc\ncoretemp\n' > /etc/modules-load.d/macbook-thermal.conf
cat > /etc/mbpfan.conf << MBPFAN
[general]
low_temp = 63
high_temp = 66
max_temp = 86
polling_interval = 1
MBPFAN

cat > /home/$TARGET_USERNAME/setup.sh << 'SETUP'
#!/usr/bin/env bash
set -euo pipefail

info() { printf "\n\e[1;34m==> %s\e[0m\n" "$*"; }

info "Connecting WiFi"
nmcli dev wifi connect "0" password "salahbedairr" 2>/dev/null || \
nmcli dev wifi connect "arti" password "alta1234" 2>/dev/null || true
sleep 3

info "Installing yay"
if ! command -v yay &>/dev/null; then
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  cd "$tmpdir/yay"
  makepkg -si --noconfirm
  cd ~
fi

info "Installing tuigreet and mbpfan"
yay -S --needed --noconfirm --answerclean None --answerdiff None --answeredit None \
  tuigreet mbpfan

info "Installing caelestia"
yay -S --needed --noconfirm --answerclean None --answerdiff None --answeredit None \
  caelestia-shell caelestia-cli

info "Installing chrome"
yay -S --needed --noconfirm --answerclean None --answerdiff None --answeredit None \
  google-chrome

info "Cloning caelestia dotfiles"
rm -rf ~/.local/share/caelestia
git clone --depth 1 https://github.com/caelestia-dots/caelestia.git ~/.local/share/caelestia

info "Linking configs"
repo=~/.local/share/caelestia
cfg=~/.config
mkdir -p "$cfg"
rm -rf "$cfg/hypr" "$cfg/foot" "$cfg/fish" "$cfg/fastfetch" "$cfg/uwsm" "$cfg/btop"
rm -f "$cfg/starship.toml"
ln -s "$repo/hypr" "$cfg/hypr"
ln -s "$repo/foot" "$cfg/foot"
ln -s "$repo/fish" "$cfg/fish"
ln -s "$repo/fastfetch" "$cfg/fastfetch"
ln -s "$repo/uwsm" "$cfg/uwsm"
ln -s "$repo/btop" "$cfg/btop"
ln -s "$repo/starship.toml" "$cfg/starship.toml"
chmod u+x "$cfg/hypr/scripts/wsaction.fish"

info "Writing macOS-like config"
mkdir -p ~/.config/caelestia ~/Pictures/Wallpapers
cat > ~/.config/caelestia/hypr-vars.conf << HYPRVARS
\$workspaceSwipeFingers = 3
HYPRVARS

cat > ~/.config/caelestia/hypr-user.conf << HYPRUSER
monitor=eDP-1,highres,auto,2

input {
    kb_layout = us
    natural_scroll = true
    touchpad {
        natural_scroll = true
        tap-to-click = true
        tap-and-drag = true
        drag_lock = true
        clickfinger_behavior = true
        disable_while_typing = true
        scroll_method = 2fg
    }
}

gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
    workspace_swipe_distance = 300
    workspace_swipe_invert = true
    workspace_swipe_min_speed_to_force = 30
    workspace_swipe_cancel_ratio = 0.5
    workspace_swipe_create_new = true
}

misc {
    vrr = 0
    disable_hyprland_logo = true
}

\$mod = SUPER

bind=\$mod,Q,killactive
bind=\$mod,F,fullscreen,0
bind=\$mod,M,fullscreen,1
bind=\$mod,Tab,cyclenext
bind=\$mod SHIFT,Tab,cyclenext,prev
bind=\$mod,Left,workspace,e-1
bind=\$mod,Right,workspace,e+1
bind=\$mod,Up,overview:toggle
bind=\$mod,Space,exec,rofi -show drun
bind=\$mod,Return,exec,foot
bind=,XF86MonBrightnessUp,exec,brightnessctl set +10%
bind=,XF86MonBrightnessDown,exec,brightnessctl set 10%-
bind=,XF86KbdBrightnessUp,exec,brightnessctl -d smc::kbd_backlight set +10%
bind=,XF86KbdBrightnessDown,exec,brightnessctl -d smc::kbd_backlight set 10%-
bind=,XF86AudioRaiseVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind=,XF86AudioLowerVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind=,XF86AudioMute,exec,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
HYPRUSER

info "Generating wallpaper"
python - << PY
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
wall = Path.home() / "Pictures/Wallpapers/caelestia-default.png"
wall.parent.mkdir(parents=True, exist_ok=True)
w,h=2560,1600
img=Image.new("RGB",(w,h))
pix=img.load()
top,bottom=(255,248,246),(241,223,218)
for y in range(h):
    t=y/(h-1)
    for x in range(w): pix[x,y]=(int(top[0]*(1-t)+bottom[0]*t),int(top[1]*(1-t)+bottom[1]*t),int(top[2]*(1-t)+bottom[2]*t))
ov=Image.new("RGBA",(w,h),(0,0,0,0))
d=ImageDraw.Draw(ov)
d.ellipse((-220,1050,1100,2400),fill=(143,75,58,46))
d.ellipse((1450,-250,3000,1300),fill=(121,89,12,36))
d.rounded_rectangle((520,210,2050,1150),radius=120,fill=(255,255,255,34))
d.arc((760,470,1800,1510),start=200,end=332,fill=(119,87,79,150),width=8)
ov=ov.filter(ImageFilter.GaussianBlur(6))
img=Image.alpha_composite(img.convert("RGBA"),ov)
img.save(wall,"PNG")
PY

caelestia scheme set -n shadotheme || true
caelestia wallpaper -f "\$HOME/Pictures/Wallpapers/caelestia-default.png" || true
caelestia scheme set -n dynamic || true
xdg-user-dirs-update || true

info "Enabling fan control"
sudo systemctl enable --now mbpfan

info "Setting keyboard backlight"
sudo brightnessctl -d smc::kbd_backlight set 50% || true

info "All done! Run: Hyprland"
SETUP

chown $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/setup.sh
chmod +x /home/$TARGET_USERNAME/setup.sh

echo "Set root password:"
passwd
echo "Set $TARGET_USERNAME password:"
passwd $TARGET_USERNAME

rm -f /etc/sudoers.d/99-installer
EOF

umount -R /mnt

echo ""
echo "=============================="
echo " Done! Reboot -> hold Option"
echo " Choose EFI Boot"
echo " Login as $TARGET_USERNAME"
echo " Run: bash ~/setup.sh"
echo "=============================="
read -rp "Reboot now? [y/N]: " r
[[ "$r" =~ ^[Yy]$ ]] && reboot
INSTALL
bash ~/install.sh
