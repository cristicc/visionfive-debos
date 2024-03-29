#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Copyright (C) 2022 Cristian Ciocaltea <cristian.ciocaltea@gmail.com>

set -e

# Clean downloaded packages
#apt-get clean -qy

# Install kernel packages
if ls /tmp/script/bin/linux-*.deb 1>/dev/null 2>&1; then
    echo "Installing kernel packages"
    apt-get install -qy --reinstall /tmp/script/bin/linux-*.deb
fi

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
echo "Configuring GRUB"

cat >/boot/grub.cfg <<EOF
set default=0
set timeout_style=menu
set timeout=2

set debug="linux,loader,mm"
set term="vt100"
EOF

for ver in /boot/vmlinuz-*; do
    ver=${ver##*vmlinuz-}
    cat >>/boot/grub.cfg <<EOB

menuentry 'Debian kernel ${ver}' {
    linux /boot/vmlinuz-${ver} root=/dev/mmcblk0p3 rw console=tty0 console=ttyS0,115200 earlycon stmmaceth=chain_mode:1 selinux=0 LANG=en_US.UTF-8
    devicetree /usr/lib/linux-image-${ver}/starfive/jh7100-starfive-visionfive-v1.dtb
    initrd /boot/initrd.img-${ver}
}
EOB
done

# Copy GRUB EFI binary
mkdir -p /boot/efi/EFI/boot
# TODO: find solutions for moving 'bin' subfolder out of 'scripts'
install -m 0644 /tmp/script/bin/grubriscv64.efi /boot/efi/EFI/boot/

echo "Configuring system"

# Configure fstab
cat <<EOF >/etc/fstab
tmpfs /tmp tmpfs mode=1777,strictatime,nosuid,nodev,size=1G 0 0
# /dev/mmcblk0p2 /boot/efi vfat umask=0077 0 1
EOF

# Configure networking
cat >/etc/hosts <<'EOF'
127.0.0.1	localhost
::1	localhost ip6-localhost ip6-loopback
fe00::0	ip6-localnet
ff00::0	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
127.0.0.1	visionfive
EOF

mkdir -p /etc/systemd/network
cat >/etc/systemd/network/wired.network <<'EOF'
# https://www.debian.org/doc/manuals/debian-reference/ch05.en.html
#
# Run the following command after any changes to this file:
# systemctl restart systemd-networkd systemd-resolved

[Match]
Name=e*
KernelCommandLine=!nfsroot

[Network]
DHCP=yes
EOF

mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/fallback_dns.conf <<'EOF'
[Resolve]
FallbackDNS=8.8.8.8
EOF

systemctl enable systemd-networkd systemd-resolved

# Set root password
echo "root:root" | chpasswd

# Allow SSH root login
echo "PermitRootLogin=yes" >>/etc/ssh/sshd_config

# Change hostname
echo "visionfive" >/etc/hostname

# Synchronize cached writes to persistent storage
sync

echo "Done"
