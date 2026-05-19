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

info() { printf "\n==> %s\n" "$*"; }
die()  { printf "\nError: %s\n" "$*" >&2; exit 1; }

info "Connecting to WiFi"
iwctl --passphrase "salahbedairr" station wlan0 connect "0" || true
sleep 4
ping -c 1 archlinux.org >/dev/null 2>&1 || die "No internet connection"
echo "Online!"

timedatectl set-ntp true

info "Formatting partitions"
mkfs.fat -F32 "$BOOT_DEV"
mkfs.fat -F32 "$EFI_DEV"
mkfs.ext4 -F -L archroot "$ROOT_DEV"

info "Mounting partitions"
mount "$ROOT_DEV" /mnt
mkdir -p /mnt/boot /mnt/efi
mount "$BOOT_DEV" /mnt/boot
mount "$EFI_DEV" /mnt/efi

info "Installing base system"
pacstrap -K /mnt \
  base linux linux-firmware intel-ucode \
  networkmanager iwd sudo vim git base-devel \
  linux-headers broadcom-wl grub efibootmgr fish \
  greetd tuigreet bluez bluez-utils \
  pipewire pipewire-pulse wireplumber pavucontrol alsa-utils \
  thermald power-profiles-daemon \
  gnome-keyring polkit-gnome gammastep geoclue \
  mesa vulkan-intel xdg-user-dirs xorg-xwayland \
  python python-pillow brightnessctl

genfstab -U /mnt >> /mnt/etc/fstab

info "Writing post-install script"
cat > /mnt/root/post-install.sh << EOF
#!/usr/bin/env bash
set -euo pipefail

TARGET_HOSTNAME='${TARGET_HOSTNAME}'
TARGET_USERNAME='${TARGET_USERNAME}'
TARGET_TIMEZONE='${TARGET_TIMEZONE}'
TARGET_LOCALE='${TARGET_LOCALE}'

info() { printf "\n==> %s\n" "\$*"; }

info "Locale, time, hostname"
ln -sf "/usr/share/zoneinfo/\${TARGET_TIMEZONE}" /etc/localtime
hwclock --systohc
sed -i "s/^#\${TARGET_LOCALE} UTF-8/\${TARGET_LOCALE} UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=\${TARGET_LOCALE}" > /etc/locale.conf
echo "\${TARGET_HOSTNAME}" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 \${TARGET_HOSTNAME}.localdomain \${TARGET_HOSTNAME}
HOSTS

info "Creating user"
if ! id -u "\${TARGET_USERNAME}" >/dev/null 2>&1; then
  useradd -m -G wheel,video,input -s /usr/bin/fish "\${TARGET_USERNAME}"
fi
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo "\${TARGET_USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL" > "/etc/sudoers.d/99-installer"
chmod 440 "/etc/sudoers.d/99-installer"

info "Apple keyboard"
mkdir -p /etc/modprobe.d
echo "options hid_apple fnmode=1 swap_opt_cmd=0" > /etc/modprobe.d/hid_apple.conf
mkinitcpio -P

info "greetd login manager"
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml << GREETD
[terminal]
vt = 1
[default_session]
command = "tuigreet --time --remember --cmd Hyprland"
user = "greeter"
GREETD

info "GRUB"
grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg

info "Enabling services"
systemctl enable NetworkManager bluetooth thermald power-profiles-daemon greetd

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

info "Cloning Caelestia"
su - "\${TARGET_USERNAME}" -c '
set -e
rm -rf ~/.local/share/caelestia
git clone --depth 1 https://github.com/caelestia-dots/caelestia.git ~/.local/share/caelestia
'

info "Installing Caelestia packages"
su - "\${TARGET_USERNAME}" -c '
set -e
cd ~/.local/share/caelestia
yay -Bi . --noconfirm --needed --answerclean None --answerdiff None --answeredit None
rm -f caelestia-meta-*.pkg.tar.zst
'

info "Installing extras"
su - "\${TARGET_USERNAME}" -c '
yay -S --needed --noconfirm --answerclean None --answerdiff None --answeredit None \
  mbpfan google-chrome
'

info "Mac fan control"
mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/macbook-thermal.conf << MODULES
applesmc
coretemp
MODULES
cat > /etc/mbpfan.conf << MBPFAN
[general]
low_temp = 63
high_temp = 66
max_temp = 86
polling_interval = 1
MBPFAN
systemctl enable mbpfan

info "Linking configs"
su - "\${TARGET_USERNAME}" -c '
set -e
repo=~/.local/share/caelestia
cfg=~/.config
mkdir -p "\$cfg"
rm -rf "\$cfg/hypr" "\$cfg/foot" "\$cfg/fish" "\$cfg/fastfetch" "\$cfg/uwsm" "\$cfg/btop"
rm -f "\$cfg/starship.toml"
ln -s "\$repo/hypr" "\$cfg/hypr"
ln -s "\$repo/foot" "\$cfg/foot"
ln -s "\$repo/fish" "\$cfg/fish"
ln -s "\$repo/fastfetch" "\$cfg/fastfetch"
ln -s "\$repo/uwsm" "\$cfg/uwsm"
ln -s "\$repo/btop" "\$cfg/btop"
ln -s "\$repo/starship.toml" "\$cfg/starship.toml"
chmod u+x "\$cfg/hypr/scripts/wsaction.fish"
'

info "User overrides"
su - "\${TARGET_USERNAME}" -c '
set -e
mkdir -p ~/.config/caelestia ~/Pictures/Wallpapers
cat > ~/.config/caelestia/hypr-vars.conf << HYPRVARS
\$workspaceSwipeFingers = 3
HYPRVARS
cat > ~/.config/caelestia/hypr-user.conf << HYPRUSER
monitor=eDP-1,highres,auto,2
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
bind=,XF86KbdBrightnessUp,exec,brightnessctl -d *kbd* set +10%
bind=,XF86KbdBrightnessDown,exec,brightnessctl -d *kbd* set 10%-
bind=,XF86MonBrightnessUp,exec,brightnessctl set +10%
bind=,XF86MonBrightnessDown,exec,brightnessctl set 10%-
HYPRUSER
'

info "Generating wallpaper"
su - "\${TARGET_USERNAME}" -c '
python - << PY
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
wall = Path.home() / "Pictures/Wallpapers/caelestia-default.png"
wall.parent.mkdir(parents=True, exist_ok=True)
w, h = 2560, 1600
img = Image.new("RGB", (w, h))
pix = img.load()
top, bottom = (255,248,246), (241,223,218)
for y in range(h):
    t = y/(h-1)
    r = int(top[0]*(1-t)+bottom[0]*t)
    g = int(top[1]*(1-t)+bottom[1]*t)
    b = int(top[2]*(1-t)+bottom[2]*t)
    for x in range(w): pix[x,y]=(r,g,b)
ov = Image.new("RGBA",(w,h),(0,0,0,0))
d = ImageDraw.Draw(ov)
d.ellipse((-220,1050,1100,2400),fill=(143,75,58,46))
d.ellipse((1450,-250,3000,1300),fill=(121,89,12,36))
d.rounded_rectangle((520,210,2050,1150),radius=120,fill=(255,255,255,34))
d.arc((760,470,1800,1510),start=200,end=332,fill=(119,87,79,150),width=8)
ov = ov.filter(ImageFilter.GaussianBlur(6))
img = Image.alpha_composite(img.convert("RGBA"),ov)
img.save(wall,"PNG")
PY
'

info "Seeding wallpaper and scheme"
su - "\${TARGET_USERNAME}" -c '
caelestia scheme set -n shadotheme || true
caelestia wallpaper -f "\$HOME/Pictures/Wallpapers/caelestia-default.png" || true
caelestia scheme set -n dynamic || true
xdg-user-dirs-update || true
'

chsh -s /usr/bin/fish "\${TARGET_USERNAME}"
rm -f /etc/sudoers.d/99-installer

info "Set root password"
passwd
info "Set password for \${TARGET_USERNAME}"
passwd "\${TARGET_USERNAME}"
EOF

chmod +x /mnt/root/post-install.sh

info "Running chroot config"
arch-chroot /mnt /bin/bash /root/post-install.sh

info "Cleanup"
rm -f /mnt/root/post-install.sh
umount -R /mnt

echo ""
echo "=============================="
echo " Done! Reboot -> hold Option"
echo " Choose EFI Boot"
echo " Login via greetd"
echo "=============================="
read -rp "Reboot now? [y/N]: " r
[[ "$r" =~ ^[Yy]$ ]] && reboot
INSTALL
bash ~/install.sh
