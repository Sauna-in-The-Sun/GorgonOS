#!/bin/bash

set -e

TARGET_DISK="/dev/sda"
CRYPT_NAME="gorgon_crypt"
LUKS_KEY="/tmp/luks.key"
MAPPER="/dev/mapper/$CRYPT_NAME"
HOSTNAME="gorgonos"
USERNAME="gorgonuser"
SWAP_SIZE="8G"

echo "[WARNING] This will ERASE ALL DATA on $TARGET_DISK!"
read -p "Confirm disk (Type YES to continue): " CONFIRM
[[ "$CONFIRM" != "YES" ]] && exit 1

if [ -d /sys/firmware/efi ]; then
  BOOT_MODE="uefi"
else
  BOOT_MODE="bios"
fi

dd if=/dev/urandom of=$LUKS_KEY bs=512 count=8 iflag=fullblock
chmod 600 $LUKS_KEY

parted --script "$TARGET_DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 1GiB \
    set 1 esp on \
    mkpart primary linux-swap 1GiB 9GiB \
    mkpart primary 9GiB 100%

cryptsetup luksFormat --key-file $LUKS_KEY "${TARGET_DISK}3"
cryptsetup open --key-file $LUKS_KEY "${TARGET_DISK}3" $CRYPT_NAME

mkswap "${TARGET_DISK}2"
swapon "${TARGET_DISK}2"

mkfs.fat -F32 "${TARGET_DISK}1" -n EFI
mkfs.btrfs -f $MAPPER -L GORGONROOT

mount -o compress=zstd $MAPPER /mnt
mkdir -p /mnt/boot/efi
mount "${TARGET_DISK}1" /mnt/boot/efi

debootstrap noble /mnt http://archive.ubuntu.com/ubuntu

echo "$HOSTNAME" > /mnt/etc/hostname

chroot /mnt useradd -m -s /bin/bash "$USERNAME"
echo "Set password for $USERNAME:"
chroot /mnt passwd "$USERNAME"
echo "Set root password:"
chroot /mnt passwd root

echo "$CRYPT_NAME UUID=$(blkid -s UUID -o value ${TARGET_DISK}3) $LUKS_KEY luks,discard" > /mnt/etc/crypttab

cat > /mnt/etc/fstab <<EOF
UUID=$(blkid -s UUID -o value $MAPPER) /  btrfs  compress=zstd  0 1
UUID=$(blkid -s UUID -o value ${TARGET_DISK}1) /boot/efi vfat umask=0077 0 1
UUID=$(blkid -s UUID -o value ${TARGET_DISK}2) none swap sw 0 0
EOF

echo "RESUME=UUID=$(blkid -s UUID -o value ${TARGET_DISK}2)" > /mnt/etc/initramfs-tools/conf.d/resume

chroot /mnt apt update
chroot /mnt apt install -y cryptsetup-initramfs grub-efi-amd64 shim-signed linux-image-generic

chroot /mnt apt install -y ubuntu-drivers-common mesa-utils vulkan-tools
chroot /mnt ubuntu-drivers autoinstall

chroot /mnt apt install -y nvidia-cuda-toolkit

chroot /mnt dpkg --add-architecture i386
chroot /mnt apt update
chroot /mnt apt install -y wine64 wine32 libwine libwine:i386 fonts-wine winetricks

chroot /mnt apt install -y build-essential cmake git llvm clang pkg-config \
    libglvnd-dev libsdl2-dev libvulkan-dev libopenal-dev

chroot /mnt apt install -y steam lutris gamemode

chroot /mnt apt install -y obs-studio

chroot /mnt apt install -y irqbalance tuned
chroot /mnt systemctl enable irqbalance
chroot /mnt systemctl enable tuned
echo "vm.swappiness=10" >> /mnt/etc/sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /mnt/etc/sysctl.conf

cat > /mnt/etc/default/cpufrequtils <<EOF
GOVERNOR=performance
EOF
chroot /mnt systemctl enable cpufrequtils

echo "net.core.rmem_max=16777216" >> /mnt/etc/sysctl.conf
echo "net.core.wmem_max=16777216" >> /mnt/etc/sysctl.conf

echo "ACTION==\"add|change\", KERNEL==\"sd*[!0-9]|nvme*\", ATTR{queue/scheduler}=\"kyber\"" > /mnt/etc/udev/rules.d/60-ioscheduler.rules

chroot /mnt apt install -y calamares-settings-ubuntu calamares

mkdir -p /mnt/etc/calamares
cat > /mnt/etc/calamares/settings.conf <<EOF
modules-search: [ local ]
instances:
- id:       users
  module:   users
  config:   users.conf
- id:       partition
  module:   partition
  config:   partition.conf
- id:       unpackfs
  module:   unpackfs
  config:   unpackfs.conf
- id:       machineid
  module:   machineid
  config:   machineid.conf
- id:       fstab
  module:   fstab
  config:   fstab.conf
- id:       locale
  module:   locale
  config:   locale.conf
- id:       keyboard
  module:   keyboard
  config:   keyboard.conf
- id:       localecfg
  module:   localecfg
  config:   localecfg.conf
- id:       luksbootkeyfile
  module:   luksbootkeyfile
  config:   luksbootkeyfile.conf
- id:       plymouthcfg
  module:   plymouthcfg
  config:   plymouthcfg.conf
- id:       grubcfg
  module:   grubcfg
  config:   grubcfg.conf
- id:       bootloader
  module:   bootloader
  config:   bootloader.conf
- id:       packages
  module:   packages
  config:   packages.conf
- id:       displaymanager
  module:   displaymanager
  config:   displaymanager.conf
- id:       initramfscfg
  module:   initramfscfg
  config:   initramfscfg.conf
- id:       initramfs
  module:   initramfs
  config:   initramfs.conf
- id:       shellprocess
  module:   shellprocess
  config:   shellprocess.conf
branding: gorgon
prompt-install: true
dont-chroot: false
EOF

mkdir -p /mnt/usr/share/calamares/branding/gorgon
cat > /mnt/usr/share/calamares/branding/gorgon/branding.desc <<EOF
componentName:  GorgonOS
slideshow:      slideshow.qml
style:          
windowTitle:    GorgonOS Installer
strings:
    productName:         GorgonOS
    shortProductName:    GorgonOS
    version:             1.0
    shortVersion:        1.0
    versionedName:       GorgonOS 1.0
    shortVersionedName:  GorgonOS 1.0
    bootloaderEntryName: GorgonOS
    productUrl:          https://gorgonos.org/
    supportUrl:          https://gorgonos.org/support/
    knownIssuesUrl:      https://gorgonos.org/known-issues/
    releaseNotesUrl:     https://gorgonos.org/release-notes/
images:
    productLogo:         "gorgon-logo.png"
    productIcon:         "gorgon-icon.png"
    productWelcome:      "welcome.png"
slideshowAPI: 1
EOF

touch /mnt/usr/share/calamares/branding/gorgon/gorgon-logo.png
touch /mnt/usr/share/calamares/branding/gorgon/gorgon-icon.png
touch /mnt/usr/share/calamares/branding/gorgon/welcome.png

chroot /mnt apt install -y cinnamon-desktop-environment nemo nemo-fileroller \
    mint-meta-cinnamon mint-meta-mate mint-themes mint-y-icons \
    lightdm slick-greeter synaptic gnome-software \
    firefox thunderbird vlc celluloid gnome-terminal \
    arc-theme papirus-icon-theme

chroot /mnt systemctl enable lightdm

mkdir -p /mnt/etc/lightdm
cat > /mnt/etc/lightdm/lightdm.conf <<EOF
[Seat:*]
greeter-session=slick-greeter
user-session=cinnamon
EOF

mkdir -p /mnt/home/$USERNAME/.config/autostart
cat > /mnt/home/$USERNAME/.config/autostart/FirstSetup.desktop <<EOF
[Desktop Entry]
Type=Application
Name=First Setup Wizard
Exec=/usr/bin/gorgon-first-setup
X-GNOME-Autostart-enabled=true
EOF

chroot /mnt apt install -y plymouth plymouth-themes
chroot /mnt plymouth-set-default-theme -R solar

mkdir -p /mnt/home/$USERNAME/.config/gtk-3.0
cat > /mnt/home/$USERNAME/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Sans 10
EOF

cp /mnt/home/$USERNAME/.config/gtk-3.0/settings.ini /mnt/home/$USERNAME/.config/gtk-4.0/settings.ini

mkdir -p /mnt/usr/share/gorgon-control-center
cat > /mnt/usr/bin/gorgon-control-center <<'EOF'
#!/bin/bash
while true; do
    status=$(systemctl is-active gamemoded.service)
    if [ "$status" = "active" ]; then
        game_status="Disable Gaming Mode"
        game_desc="Turn off performance optimizations to avoid anti-cheat issues"
    else
        game_status="Enable Gaming Mode"
        game_desc="Optimize system for gaming (may trigger anti-cheat systems)"
    fi
    
    choice=$(zenity --list --title="GorgonOS Control Center" \
        --width=600 --height=400 \
        --column="Option" --column="Description" \
        "System Info" "Display system information" \
        "Driver Manager" "Manage hardware drivers" \
        "Update System" "Update system packages" \
        "Theme Settings" "Change light/dark theme" \
        "$game_status" "$game_desc" \
        "Power Tools" "Adjust TDP, fan control, and power settings" \
        "Controller Setup" "Configure gamepads and controllers" \
        "Backup Tool" "Create system backup" \
        "Exit" "Close Control Center")
    
    case $choice in
        "System Info")
            inxi -Fxxxz | zenity --text-info --width=800 --height=600
            ;;
        "Driver Manager")
            software-properties-gtk --open-tab=4 | zenity --progress --pulsate --no-cancel --auto-close
            ;;
        "Update System")
            x-terminal-emulator -e "sudo apt update && sudo apt upgrade"
            ;;
        "Theme Settings")
            theme_choice=$(zenity --list --title="Select Theme" \
                --column="Theme" "Dark Mode" "Light Mode" "Auto (Follow System)")
            
            case $theme_choice in
                "Dark Mode")
                    gsettings set org.cinnamon.desktop.interface gtk-theme 'Arc-Dark'
                    gsettings set org.cinnamon.desktop.interface icon-theme 'Papirus-Dark'
                    ;;
                "Light Mode")
                    gsettings set org.cinnamon.desktop.interface gtk-theme 'Arc'
                    gsettings set org.cinnamon.desktop.interface icon-theme 'Papirus'
                    ;;
                "Auto (Follow System)")
                    gsettings set org.cinnamon.desktop.interface gtk-theme 'Arc-Dark'
                    gsettings set org.cinnamon.desktop.interface icon-theme 'Papirus-Dark'
                    ;;
            esac
            ;;
        "Enable Gaming Mode")
            pkexec systemctl start gamemoded.service
            pkexec systemctl enable gamemoded.service
            zenity --info --text="Gaming mode activated!\n\nNote: Some anti-cheat systems may detect this optimization. Disable if you encounter issues."
            ;;
        "Disable Gaming Mode")
            pkexec systemctl stop gamemoded.service
            pkexec systemctl disable gamemoded.service
            zenity --info --text="Gaming mode deactivated!\n\nAnti-cheat systems should no longer detect optimizations."
            ;;
        "Power Tools")
            gorgon-power-tools
            ;;
        "Controller Setup")
            gorgon-controller-setup
            ;;
        "Backup Tool")
            zenity --info --text="Backup tool will be available in next version"
            ;;
        "Exit"|*)
            exit 0
            ;;
    esac
done
EOF

chmod +x /mnt/usr/bin/gorgon-control-center

cat > /mnt/usr/share/applications/gorgon-control-center.desktop <<EOF
[Desktop Entry]
Name=Gorgon Control Center
Comment=System Settings and Control Panel
Exec=gorgon-control-center
Icon=system-settings
Terminal=false
Type=Application
Categories=System;Settings;
EOF

mkdir -p /mnt/usr/share/gorgon-menu
cat > /mnt/usr/share/cinnamon/applets/gorgon-menu@example.com/applet.js <<'EOF'
const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const St = imports.gi.St;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const Main = imports.ui.main;

function GorgonMenuApplet(orientation, panel_height, instance_id) {
    this._init(orientation, panel_height, instance_id);
}

GorgonMenuApplet.prototype = {
    __proto__: Applet.IconApplet.prototype,

    _init: function(orientation, panel_height, instance_id) {
        Applet.IconApplet.prototype._init.call(this, orientation, panel_height, instance_id);
        
        this.set_applet_icon_name("start-here-symbolic");
        this.set_applet_tooltip(_("Gorgon Menu"));
        
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);
        
        let item;
        
        item = new PopupMenu.PopupMenuItem("Control Center");
        item.connect('activate', () => {
            GLib.spawn_command_line_async('gorgon-control-center');
        });
        this.menu.addMenuItem(item);
        
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        
        const appSys = Cinnamon.AppSystem.get_default();
        const apps = appSys.get_installed();
        
        const categories = {};
        apps.forEach(app => {
            const category = app.get_category() || "Other";
            if (!categories[category]) {
                categories[category] = [];
            }
            categories[category].push(app);
        });
        
        Object.keys(categories).sort().forEach(category => {
            const section = new PopupMenu.PopupSubMenuMenuItem(category);
            categories[category].forEach(app => {
                const item = new PopupMenu.PopupMenuItem(app.get_name());
                item.connect('activate', () => app.launch());
                section.menu.addMenuItem(item);
            });
            this.menu.addMenuItem(section);
        });
        
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        
        item = new PopupMenu.PopupMenuItem("Big Picture Mode");
        item.connect('activate', () => GLib.spawn_command_line_async('steam -bigpicture'));
        this.menu.addMenuItem(item);
        
        item = new PopupMenu.PopupMenuItem("Power Off");
        item.connect('activate', () => Main.Util.spawnCommandLine("systemctl poweroff"));
        this.menu.addMenuItem(item);
    },
    
    on_applet_clicked: function() {
        this.menu.toggle();
    }
};

function main(metadata, orientation, panel_height, instance_id) {
    return new GorgonMenuApplet(orientation, panel_height, instance_id);
}
EOF

cat > /mnt/usr/bin/gorgon-power-tools <<'EOF'
#!/bin/bash
choices=("Performance: Maximum power (15W+)" "Balanced: Optimal balance (10-15W)" "Power Saver: Extended battery (5-10W)")

selection=$(zenity --list --title="Gorgon Power Tools" --text="Select power profile" \
    --column="Profile" --column="Description" "${choices[@]}" --height=250)

case $selection in
    Performance*)
        pkexec ryzenadj --power-limit=28,28 --fast-limit=30 --slow-limit=28
        pkexec cpupower frequency-set -g performance
        zenity --info --text="Performance mode activated: TDP increased to 28W"
        ;;
    Balanced*)
        pkexec ryzenadj --power-limit=15,15 --fast-limit=20 --slow-limit=15
        pkexec cpupower frequency-set -g schedutil
        zenity --info --text="Balanced mode activated: TDP set to 15W"
        ;;
    Power*)
        pkexec ryzenadj --power-limit=8,8 --fast-limit=10 --slow-limit=8
        pkexec cpupower frequency-set -g powersave
        zenity --info --text="Power Saver mode activated: TDP reduced to 8W"
        ;;
esac
EOF
chmod +x /mnt/usr/bin/gorgon-power-tools

cat > /mnt/usr/bin/gorgon-controller-setup <<'EOF'
#!/bin/bash
zenity --info --title="Controller Setup" --text="Connect your controller now. Press any button to continue."
controllers=$(ls /dev/input/js* 2>/dev/null | wc -l)

if [ $controllers -eq 0 ]; then
    zenity --error --text="No controllers detected!"
    exit 1
fi

zenity --info --text="$controllers controller(s) detected. Configuration complete!"
EOF
chmod +x /mnt/usr/bin/gorgon-controller-setup

chroot /mnt apt install -y jstest-gtk steam-devices
chroot /mnt wget https://github.com/FlyGoat/RyzenAdj/archive/master.zip
chroot /mnt unzip master.zip
chroot /mnt cd RyzenAdj-master && chroot /mnt mkdir build && chroot /mnt cd build && chroot /mnt cmake -DCMAKE_BUILD_TYPE=Release .. && chroot /mnt make && chroot /mnt make install

chroot /mnt update-initramfs -u -k all

if [ "$BOOT_MODE" = "uefi" ]; then
  chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GorgonOS
else
  chroot /mnt grub-install "$TARGET_DISK"
fi
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

shred -u $LUKS_KEY
swapoff "${TARGET_DISK}2"
umount -R /mnt
cryptsetup close $CRYPT_NAME

echo "[SUCCESS] GorgonOS installed! Reboot and remove installation media."