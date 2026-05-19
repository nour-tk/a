#!/usr/bin/env bash
set -euo pipefail

BOOT_PARTUUID="51E4667B-E38F-4715-AA56-D183EEAAC11C"
EFI_PARTUUID="BD8AE51D-0932-40BD-987B-40A854668F45"
ROOT_PARTUUID="9B907FC7-C067-47EF-A272-575E1AD07176"

DEFAULT_HOSTNAME="archmac"
DEFAULT_USERNAME="lirn"
DEFAULT_TIMEZONE="Africa/Cairo"
DEFAULT_LOCALE="en_US.UTF-8"

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

Connect first, then rerun the check:
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

prompt_value() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default]: " value
  printf "%s" "${value:-$default}"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this script as root from the Arch live USB."
}

require_tools() {
  local tools=(
    blkid lsblk ping mkfs.fat mkfs.ext4 mount umount pacstrap genfstab
    arch-chroot grub-install grub-mkconfig sed useradd passwd
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
    linux-headers broadcom-wl grub efibootmgr \
    fish
  genfstab -U /mnt >> /mnt/etc/fstab
}

write_postinstall_script() {
  cat > /mnt/root/post-install.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i 's/^#${LOCALE} UTF-8/${LOCALE} UTF-8/' /etc/locale.gen
locale-gen
printf 'LANG=${LOCALE}\n' > /etc/locale.conf
printf '${HOSTNAME}\n' > /etc/hostname

cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

if ! id -u '${USERNAME}' >/dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash '${USERNAME}'
fi

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
systemctl enable NetworkManager

grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
EOF

  chmod +x /mnt/root/post-install.sh
}

write_cae_script() {
  mkdir -p "/mnt/home/${USERNAME}"
  cat > "/mnt/home/${USERNAME}/setup-caelestia.sh" <<'EOF'
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

cat <<'MSG'

Caelestia install finished.

Next:
  1. Reboot
  2. Log in to a TTY
  3. Start Hyprland with: Hyprland

MSG
EOF

  chmod +x "/mnt/home/${USERNAME}/setup-caelestia.sh"
  arch-chroot /mnt chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/setup-caelestia.sh"
}

configure_system() {
  info "Configuring installed system"
  write_postinstall_script
  arch-chroot /mnt /bin/bash /root/post-install.sh

  info "Set the root password"
  arch-chroot /mnt passwd

  info "Set the password for ${USERNAME}"
  arch-chroot /mnt passwd "${USERNAME}"

  write_cae_script
}

finish_install() {
  info "Cleaning up mounts"
  rm -f /mnt/root/post-install.sh
  umount -R /mnt

  cat <<EOF

Base Arch install completed.

After reboot:
  1. Hold Option and choose EFI Boot
  2. Log in as ${USERNAME}
  3. Run: bash ~/setup-caelestia.sh

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

  HOSTNAME="$(prompt_value 'Hostname' "$DEFAULT_HOSTNAME")"
  USERNAME="$(prompt_value 'Username' "$DEFAULT_USERNAME")"
  TIMEZONE="$(prompt_value 'Timezone' "$DEFAULT_TIMEZONE")"
  LOCALE="$(prompt_value 'Locale' "$DEFAULT_LOCALE")"

  confirm_destruction
  format_targets
  mount_targets
  install_base
  configure_system
  finish_install
}

main "$@"
