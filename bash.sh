cat > ~/fix.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

info() { printf "\n==> %s\n" "$*"; }
die()  { printf "\nError: %s\n" "$*" >&2; exit 1; }

info "Reloading partition table"
partprobe /dev/nvme0n1
sleep 2

info "Mounting"
mount /dev/nvme0n1p4 /mnt
mkdir -p /mnt/boot /mnt/efi
mount /dev/nvme0n1p3 /mnt/boot
mount /dev/nvme0n1p6 /mnt/efi

info "Installing base system"
pacstrap -K /mnt \
  base linux linux-firmware intel-ucode \
  networkmanager iwd sudo vim git base-devel \
  linux-headers broadcom-wl grub efibootmgr fish

info "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

info "Done! Run the chroot steps next."
EOF
bash ~/fix.sh
