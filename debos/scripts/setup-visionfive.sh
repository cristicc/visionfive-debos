#!/bin/sh

set -e

export NEEDRESTART_MODE=a
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

# Clean downloaded packages
#apt-get clean -qy

# Install kernel packages
echo "Installing kernel packages"
apt-get install -qy --reinstall /tmp/script/bin/linux-*.deb
# TODO: should not be necessary to manually call update-initramfs
#update-initramfs -c -k all

# Configure u-boot
#
# TODO: check upstream support and simplify the config below
# - https://github.com/starfive-tech/u-boot/pull/31
# - https://github.com/starfive-tech/u-boot/pull/32
#
echo "Configuring U-Boot"

cat >/boot/uEnv.txt <<EOF
fdt_high=0xffffffffffffffff
initrd_high=0xffffffffffffffff

scriptaddr=0x88100000
script_offset_f=0x1fff000
script_size_f=0x1000

kernel_addr_r=0x84000000
kernel_comp_addr_r=0x90000000
kernel_comp_size=0x10000000

fdt_addr_r=0x88000000
ramdisk_addr_r=0x88300000

# Fix wrong fdtfile name
fdtfile=starfive/jh7100-starfive-visionfive-v1.dtb

# Move DHCP after MMC to speed up booting
boot_targets=mmc0 dhcp

bootcmd=load mmc 0:2 0xa0000000 /EFI/boot/grubriscv64.efi; bootefi 0xa0000000
bootcmd_mmc0=devnum=0; run mmc_boot

ipaddr=192.168.120.200
netmask=255.255.255.0
EOF

# Configure GRUB
# TODO: generate menu entries based on kernel images found in /boot
echo "Configuring GRUB"

cat >/boot/grub.cfg <<EOF
set default=0
set timeout_style=menu
set timeout=2

set debug="linux,loader,mm"
set term="vt100"

menuentry 'Debian kernel 6.1 for visionfive' {
    linux /boot/vmlinuz-6.1.0-rc1-visionfive root=/dev/mmcblk0p3 rw console=tty0 console=ttyS0,115200 earlycon rootwait stmmaceth=chain_mode:1 selinux=0 LANG=en_US.UTF-8
    devicetree /usr/lib/linux-image-6.1.0-rc1-visionfive/starfive/jh7100-starfive-visionfive-v1.dtb
    initrd /boot/initrd.img-6.1.0-rc1-visionfive
}
EOF

# Copy GRUB EFI binary
mkdir -p /boot/efi/EFI/boot
# TODO: find solutions for moving 'bin' subfolder out of 'scripts'
install -m 0644 /tmp/script/bin/grubriscv64.efi /boot/efi/EFI/boot/

echo "Configuring system"

# Configure fstab
cat <<EOF >/etc/fstab
/dev/mmcblk0p2 /boot/efi vfat umask=0077 0 1
EOF

# Configure network
mkdir -p /etc/network
cat >>/etc/network/interfaces <<EOF
allow-hotplug eth0
iface eth0 inet dhcp
EOF

# Set root password
echo "root:root" | chpasswd

# Change hostname
echo visionfive >/etc/hostname

# sync disks
sync

echo "Done"
