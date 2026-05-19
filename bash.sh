cat > ~/chroot.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="archmac"
USERNAME="lirn"
TIMEZONE="Africa/Cairo"
LOCALE="en_US.UTF-8"

info() { printf "\n==> %s\n" "$*"; }

cat > /mnt/root/post-install.sh << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
sed -i 's/^#${LOCALE} UTF-8/${LOCALE} UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=${LOCALE}' > /etc/locale.conf
echo '${HOSTNAME}' > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS
useradd -m -G wheel -s /bin/bash '${USERNAME}' 2>/dev/null || true
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
systemctl enable NetworkManager
grub-install --target=x86_64-efi --efi-directory=/efi --boot-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg
SCRIPT

chmod +x /mnt/root/post-install.sh
info "Running post-install inside chroot"
arch-chroot /mnt /bin/bash /root/post-install.sh

info "Set root password"
arch-chroot /mnt passwd

info "Set password for ${USERNAME}"
arch-chroot /mnt passwd "${USERNAME}"

info "Cleaning up and unmounting"
rm -f /mnt/root/post-install.sh
umount -R /mnt

echo ""
echo "All done! Reboot and hold Option key, choose EFI Boot."
echo "Then log in and run: bash ~/setup-caelestia.sh"
EOF
bash ~/chroot.sh
