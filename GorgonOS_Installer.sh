#!/bin/bash
# GorgonOS Full Installer Script
# Author: Neofilisoft
# GorgonOS: Game+Dev Focused Distro based on Ubuntu/Debian
# Version: GorgonOS 1.0
# Note: Use on Live ISO only (with sudo)

set -e

### CONFIGURATION ###
HOSTNAME=gorgonos
USERNAME=dev
TARGET_DISK="/dev/sda"
OLD_SUBVOL="@gorgon1"
NEW_SUBVOL="@gorgon2"

### PARTITIONING & FORMATTING ###
echo "[INFO] Partitioning $TARGET_DISK..."
parted --script "$TARGET_DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 512MiB \
    set 1 esp on \
    mkpart primary btrfs 512MiB 100%

mkfs.fat -F32 "${TARGET_DISK}1" -n EFI
mkfs.btrfs -f "${TARGET_DISK}2" -L GORGONROOT

### MOUNT TARGET ###
echo "[INFO] Mounting Btrfs volumes..."
mount -o compress=zstd,subvolid=0 "${TARGET_DISK}2" /mnt
btrfs subvolume create /mnt/$NEW_SUBVOL
mount -o compress=zstd,subvol=$NEW_SUBVOL "${TARGET_DISK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${TARGET_DISK}1" /mnt/boot/efi

### BASE INSTALL ###
echo "[INFO] Installing base system..."
debootstrap --arch amd64 noble /mnt http://archive.ubuntu.com/ubuntu

### SYSTEM CONFIG ###
echo "$HOSTNAME" > /mnt/etc/hostname
echo "127.0.1.1 $HOSTNAME" >> /mnt/etc/hosts

### FSTAB + BOOTLOADER ###
echo "[INFO] Generating fstab and installing bootloader..."
UUID_ROOT=$(blkid -s UUID -o value "${TARGET_DISK}2")
echo "UUID=$UUID_ROOT / btrfs compress=zstd,subvol=$NEW_SUBVOL 0 1" > /mnt/etc/fstab
echo "UUID=$(blkid -s UUID -o value ${TARGET_DISK}1) /boot/efi vfat umask=0077 0 1" >> /mnt/etc/fstab

mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

chroot /mnt /bin/bash <<EOF
apt update && apt install -y linux-image-generic systemd systemd-boot grub-efi-amd64 shim sudo curl wget network-manager
bootctl install
echo "default gorgon.conf" > /boot/loader/loader.conf
echo "title   GorgonOS 2" > /boot/loader/entries/gorgon.conf
echo "linux   /vmlinuz" >> /boot/loader/entries/gorgon.conf
echo "initrd  /initrd.img" >> /boot/loader/entries/gorgon.conf
echo "options root=UUID=$UUID_ROOT rootflags=subvol=$NEW_SUBVOL rw quiet splash" >> /boot/loader/entries/gorgon.conf
EOF

### USER SETUP ###
echo "[INFO] Creating user $USERNAME"
chroot /mnt useradd -m -s /bin/bash $USERNAME
chroot /mnt passwd $USERNAME
chroot /mnt usermod -aG sudo $USERNAME

### POST-INSTALL TOOLS ###
echo "[INFO] Installing Dev & Gaming Tools..."
chroot /mnt apt install -y steam lutris git build-essential clang godot3 code python3-pip flatpak gnome-session gnome-shell vim neovim

### GAME PLATFORM SUPPORT ###
echo "[INFO] Installing Wine, Proton dependencies, and Epic Games launcher support..."
chroot /mnt dpkg --add-architecture i386
chroot /mnt apt update
chroot /mnt apt install -y wine64 wine32 libwine libwine:i386 fonts-wine winetricks
chroot /mnt apt install -y cabextract unzip python3-venv

### SNAPSHOT SYSTEM ###
echo "[INFO] Creating btrfs snapshot"
mount -o subvolid=0 "${TARGET_DISK}2" /mnt_full
btrfs subvolume snapshot /mnt_full/$NEW_SUBVOL /mnt_full/${NEW_SUBVOL}_snapshot
umount /mnt_full

### CLEANUP ###
echo "[INFO] Unmounting..."
umount -R /mnt
echo "[DONE] GorgonOS 2 installed successfully on $TARGET_DISK with subvol $NEW_SUBVOL"

exit 0
