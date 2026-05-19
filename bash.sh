cat > ~/bash.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

BOOT_DEV="/dev/nvme0n1p3"
EFI_DEV="/dev/nvme0n1p6"
ROOT_DEV="/dev/nvme0n1p4"

DEFAULT_HOSTNAME="archmac"
DEFAULT_USERNAME="lirn"
DEFAULT_TIMEZONE="Africa/Cairo"
DEFAULT_LOCALE="en_US.UTF-8"

info() { printf "\n==> %s\n" "$*"; }
die()  { printf "\nError: %s\n" "$*" >&2; exit 1; }

prompt_value() {
  local prompt="$1" default="$2" value
  read -r -p "$prompt [$default]: " value
  printf "%s" "${value:-$default}"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root."
}

ensure_online() {
  ping -c 1 -W 3 archlinux.org >/dev/null 2>&1 || die "No internet."
}

show_plan() {
  info "Target partitions"
  printf "BOOT=%s\nEFI=%s\nROOT=%s\n" "$BOOT_DEV" "$EFI_DEV" "$ROOT_DEV"
  lsblk -o NAME,SIZE,FSTYPE,LABEL "$BOOT_DEV" "$EFI_DEV" "$ROOT_DEV"
}

confirm_destruction() {
  cat <<MSG

This will ERASE and reinstall on:
  $BOOT_DEV -> /boot
  $EFI_DEV  -> /efi
  $ROOT_DEV -> /

macOS partitions will NOT be touched.

MSG
  local answer
  read -r -p "Type ERASE to continue: " answer
  [[ "$answer" == "ERASE" ]] || die "Cancelled."
}

format_targets() {
  info "Formatting"
  mkfs.fat -F 32 "$BOOT_DEV"
  mkfs.fat -F 32 "$EFI_DEV"
  mkfs.ext4 -L archroot "$ROOT_DEV"
}

mount_targets() {
  info "Mounting"
  mount "$ROOT_DEV" /mnt
  mkdir -p /mnt/boot /mnt/efi
  mount "$BOOT_DEV" /mnt/boot
  mount "$EFI_DEV" /mnt/efi
}

install_base() {
  info "Installing base system"
  pacstrap -K /mnt \
    base linux linux-firmware intel-ucode \
    networkmanager iwd sudo vim git base-devel \
    linux-headers broadcom-wl grub efibootmgr fish
  genfstab -U /mnt >> /mnt/etc/fstab
}

write_postinstall_script() {
  cat > /mnt/root/post-install.sh <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i 's/^#${LOCALE} UTF-8/${LOCALE} UTF-8/' /etc/locale.gen
locale-gen
printf 'LANG=${LOCALE}\n' > /etc/locale.conf
printf '${HOSTNAME}\n' > /etc/hostname
cat > /etc/hosts <<HOSTS
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
SCRIPT
  chmod +x /mnt/root/post-install.sh
}

write_cae_script() {
  mkdir -p "/mnt/home/${USERNAME}"
  cat > "/mnt/home/${USERNAME}/setup-caelestia.sh" <<'CSCRIPT'
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
CSCRIPT
  chmod +x "/mnt/home/${USERNAME}/setup-caelestia.sh"
  arch-chroot /mnt chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/setup-caelestia.sh"
}

configure_system() {
  info "Configuring system"
  write_postinstall_script
  arch-chroot /mnt /bin/bash /root/post-install.sh
  info "Set root password"
  arch-chroot /mnt passwd
  info "Set password for ${USERNAME}"
  arch-chroot /mnt passwd "${USERNAME}"
  write_cae_script
}

finish_install() {
  info "Cleaning up"
  rm -f /mnt/root/post-install.sh
  umount -R /mnt
  cat <<MSG

Done! After reboot:
  1. Hold Option -> choose EFI Boot
  2. Log in as ${USERNAME}
  3. Run: bash ~/setup-caelestia.sh

MSG
  read -r -p "Reboot now? [y/N]: " r
  [[ "$r" =~ ^[Yy]$ ]] && reboot
}

main() {
  require_root
  timedatectl set-ntp true
  ensure_online
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
EOF
bash ~/bash.sh
