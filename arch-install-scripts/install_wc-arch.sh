#!/bin/bash

# Arch Linux install script by SERVCUBED
# Source: https://github.com/SERVCUBED/linux-install-scripts/
# Run this from the Arch Linux installer live-USB
# Disclaimer: Use this script at your own will. It has not even been tested.
#  I am not responsible for anything which happens to your system as a
#  result of using this script, good or bad.

function checkEFIBoot
  {
    efiboot= [ -e /sys/firmware/efi/efivars ]
    if [ efiboot ]; then echo "EFI boot available"
    else echo "EFI boot unavailable"
    fi
  }


function checkNetwork
  {
    if [ $(curl -s https://servc.eu/p/success) = "success" ]; then echo "Network connected"
    else echo "Network disconnected"
    fi
  }


function mountPartitions
  {
    lsblk
    echo "Enter drive partition letter. Leave blank to not mount"

    echo "/ mount drive: "; read root
    if [ "${root}" != "" ]; then
        mount ${root} /mnt
    fi

    echo "/boot/ mount drive: "; read boot
    if [ "${boot}" != "" ]; then
        if [ ! -d /mnt/boot ]; then mkdir /mnt/boot; fi
        mount ${boot} /mnt/boot
    fi

    if [ efiboot ]; then
        echo "/boot/efi/ mount drive: "; read bootefi
        if [ "${bootefi}" != "" ]; then
            if [ ! -d /mnt/boot/efi ]; then mkdir -p /mnt/boot/efi; fi
            mount ${bootefi} /mnt/boot/efi
        fi
    fi

    echo "/home/ mount drive: "; read home
    if [ "${home}" != "" ]; then
        if [ ! -d /mnt/home ]; then mkdir /mnt/home; fi
        mount ${home} /mnt/home
    fi
  }


function doLocaleSetup
  {
    ln -sf /usr/share/zoneinfo/Europe/London /mnt/etc/localtime
    arch-chroot /mnt hwclock --systohc

    sed -ri "s/#(en_[G|U].\.UTF-8.+)/\1/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen

    echo "LANG=en_GB.UTF-8" > /mnt/etc/locale.conf

    curl https://servc.eu/p/sslf/keymaps/dvorak-ukp.map.gz -o \
        /mnt/usr/share/kbd/keymaps/i386/dvorak/dvorak-ukp.map.gz
    echo "KEYMAP=dvorak-ukp" > /mnt/etc/vconsole.conf

    if [ ! -e /mnt/etc/X11/xorg.conf.d ]; then mkdir -p /mnt/etc/X11/xorg.conf.d; fi
    cat << EOF > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "gb,gb"
	Option "XkbVariant" "dvorakukp,"
EndSection
EOF

    echo "Hostname:"; read hostname
    echo ${hostname} > /mnt/etc/hostname
    cat << EOF > /mnt/etc/hosts
127.0.0.1	localhost
::1 	localhost
127.0.0.1	${hostname}.localdomain	${hostname}
EOF
  }


function makeUser
  {
    # To be run under chroot
    echo "Username:"; read username
    useradd --create-home ${username}
    passwd ${username}
    usermod -aG wheel ${username}
    sed -ri "0,/^# %wheel/ s//%wheel/" /etc/sudoers
  }


function installUserPkg
  {
    # To be run under chroot

    echo "Enabling multilib"
    sed -rei "s/#([multilib])/\1\nInclude = \/etc\/pacman.d\/mirrorlist/" /etc/pacman.conf

    which yay > /dev/null
    if [ $? -ne 0 ]; then
        echo "Non-root user:"; read user
        cd /home/${user}
        echo "Installing Yay..."
        pacman -S --noconfirm --needed git
        sudo -u ${user} git clone https://aur.archlinux.org/yay.git
        cd yay
        sudo -u ${user} makepkg -s
        pacman -U yay*.pkg.tar.xz
    fi

    echo "Extra yay arguments:"; read extra
    echo "Installing packages"
    if [ "${extra}" = "" ]; then
        yay -Sy --noconfirm --needed - < /wc-arch-pkglist.txt
    else
        yay -Sy --noconfirm --needed - ${extra} < /wc-arch-pkglist.txt
    fi

    if [ -e /usr/bin/zsh ]; then chsh -s /usr/bin/zsh; fi
  }


function installGRUB
  {
    # To be run under chroot

    lsblk
    echo "Install to disk:"; read disk

    pacman -Sy grub

    echo "Installing BIOS GRUB"
    grub-install --target=i386-pc ${disk}

    if [ efiboot ]; then
        echo "Installing UEFI GRUB"
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=BOOT
    fi

    echo "Generating GRUB configuration file"
    grub-mkconfig -o /boot/grub/grub.cfg
  }


function menu
  {
    cat << EOF
Before you run this:
* Check installer keyboard layout
* Connect to the internet
* Format/create partitions
* (Optional) mount config drive
Menu:
1) Mount partitions
2) Install base and base-devel
3) Generate fstab
4) Set locale and time zone
5) Configure mirrors
6) Make initramfs
7) Chroot and run manual commands
8) Create user and configure Sudo
9) Set root password (Optional)
10) Install user packages
11) Install GRUB
12) Exit
After you run this:
* Copy configs

Enter choice:
EOF

    read choice
    case ${choice} in
        1)
            mountPartitions
            ;;
        2)
            pacstrap /mnt base base-devel
            ;;
        3)
            genfstab -U /mnt >> /mnt/etc/fstab
            ;;
        4)
            doLocaleSetup
            ;;
        5)
            vim /mnt/etc/pacman.d/mirrorlist
            ;;
        6)
            arch-chroot /mnt mkinitcpio -p linux
            ;;
        7)
            arch-chroot /mnt
            ;;
        8)
            cp "$0" /mnt/install_wc-arch.sh
            arch-chroot /mnt /bin/bash /install_wc-arch.sh newuserchroot
            rm -i /mnt/install_wc-arch.sh
            ;;
        9)
            arch-chroot /mnt passwd
            ;;
        10)
            cp "$0" /mnt/install_wc-arch.sh
            cp "$(dirname $0)/wc-arch-pkglist.txt" /mnt/wc-arch-pkglist.txt
            arch-chroot /mnt /bin/bash /install_wc-arch.sh installuserpkgchroot
            rm -i /mnt/install_wc-arch.sh /mnt/wc-arch-pkglist.txt
            ;;
        10)
            cp "$0" /mnt/install_wc-arch.sh
            arch-chroot /mnt /bin/bash /install_wc-arch.sh installbootloader
            rm -i /mnt/install_wc-arch.sh
            ;;
        11)
            exit
    esac
  }


if [ "$1" = "newuserchroot" ]; then
    makeUser
    exit
fi
if [ "$1" = "installuserpkgchroot" ]; then
    installUserPkg
    exit
fi
if [ "$1" = "installbootloader" ]; then
    installGRUB
    exit
fi

timedatectl set-ntp true
checkEFIBoot
checkNetwork

while true; do
    menu
done
