umount -R /mnt 2>/dev/null || true
mount /dev/nvme0n1p4 /mnt
mount /dev/nvme0n1p3 /mnt/boot
mount /dev/nvme0n1p6 /mnt/efi

arch-chroot /mnt /bin/bash << 'CHROOT'
# Install yay using bash explicitly
su - lirn -s /bin/bash -c '
set -e
tmpdir=$(mktemp -d)
git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
cd "$tmpdir/yay"
makepkg -si --noconfirm
'

# Install AUR packages
su - lirn -s /bin/bash -c '
yay -S --needed --noconfirm --answerclean None --answerdiff None --answeredit None \
  tuigreet caelestia-shell caelestia-cli google-chrome mbpfan
'

# Configure greetd
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1
[default_session]
command = "tuigreet --time --remember --cmd Hyprland"
user = "greeter"
EOF

# Mac fan
mkdir -p /etc/modules-load.d
printf 'applesmc\ncoretemp\n' > /etc/modules-load.d/macbook-thermal.conf
cat > /etc/mbpfan.conf << 'EOF'
[general]
low_temp = 63
high_temp = 66
max_temp = 86
polling_interval = 1
EOF
systemctl enable mbpfan

# Clone and link caelestia
su - lirn -s /bin/bash -c '
set -e
rm -rf ~/.local/share/caelestia
git clone --depth 1 https://github.com/caelestia-dots/caelestia.git ~/.local/share/caelestia
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

mkdir -p ~/.config/caelestia ~/Pictures/Wallpapers
cat > ~/.config/caelestia/hypr-vars.conf << EOF
\$workspaceSwipeFingers = 3
EOF
cat > ~/.config/caelestia/hypr-user.conf << EOF
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
misc { vrr = 0 }
bind=,XF86KbdBrightnessUp,exec,brightnessctl -d *kbd* set +10%
bind=,XF86KbdBrightnessDown,exec,brightnessctl -d *kbd* set 10%-
bind=,XF86MonBrightnessUp,exec,brightnessctl set +10%
bind=,XF86MonBrightnessDown,exec,brightnessctl set 10%-
EOF
'

# Wallpaper
su - lirn -s /bin/bash -c '
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
caelestia wallpaper -f "$HOME/Pictures/Wallpapers/caelestia-default.png" || true
caelestia scheme set -n dynamic || true
'

chsh -s /usr/bin/fish lirn

echo "Set lirn password:"
passwd lirn
CHROOT

umount -R /mnt
echo "Done! Reboot and hold Option key."
