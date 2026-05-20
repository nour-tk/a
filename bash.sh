# 1. Create directories
mkdir -p ~/.config/caelestia ~/Pictures/Wallpapers

# 2. Write the vars configuration file
cat > ~/.config/caelestia/hypr-vars.conf << 'HYPRVARS'
$workspaceSwipeFingers = 3
HYPRVARS

# 3. Write the user configuration file
cat > ~/.config/caelestia/hypr-user.conf << 'HYPRUSER'
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

$mod = SUPER

bind=$mod,Q,killactive
bind=$mod,F,fullscreen,0
bind=$mod,M,fullscreen,1
bind=$mod,Tab,cyclenext
bind=$mod SHIFT,Tab,cyclenext,prev
bind=$mod,Left,workspace,e-1
bind=$mod,Right,workspace,e+1
bind=$mod,Up,overview:toggle
bind=$mod,Space,exec,rofi -show drun
bind=$mod,Return,exec,foot
bind=,XF86MonBrightnessUp,exec,brightnessctl set +10%
bind=,XF86MonBrightnessDown,exec,brightnessctl set 10%-
bind=,XF86KbdBrightnessUp,exec,brightnessctl -d smc::kbd_backlight set +10%
bind=,XF86KbdBrightnessDown,exec,brightnessctl -d smc::kbd_backlight set 10%-
bind=,XF86AudioRaiseVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind=,XF86AudioLowerVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind=,XF86AudioMute,exec,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
HYPRUSER

# 4. Finish theme configuration and services
caelestia scheme set -n shadotheme || true
caelestia scheme set -n dynamic || true
xdg-user-dirs-update || true
sudo systemctl enable --now mbpfan
sudo brightnessctl -d smc::kbd_backlight set 50% || true

# 5. Boot into your new graphical desktop!
sudo systemctl restart greetd
