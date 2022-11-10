#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Copyright (C) 2022 Cristian Ciocaltea <cristian.ciocaltea@gmail.com>

set -e

SCRIPT_DIR=$(readlink -mn "$0")
SCRIPT_DIR=${SCRIPT_DIR%/*}

cd "${1:-.}"

export ARCH=riscv
export CROSS_COMPILE=riscv64-linux-gnu-

MODULES="adler32 affs afs afsplitter archelp bfs blocklist boot cat chain cmp cmp_test configfile cpio_be cpio crc64 ctz_test datehook date datetime diskfilter disk div div_test dm_nv echo efifwsetup efi_gop efinet elf eval exfat exfctest ext2 extcmd fat fdt file fshelp functional_test geli gettext gptsync gzio halt hashsum hello help hexdump iso9660 jfs json keystatus ldm linux loadenv loopback lsefimmap lsefi lsefisystab lsmmap ls lssal lzopio macbless macho memdisk memrw minicmd mmap mpi msdospart mul_test net newc normal odc offsetio part_gpt part_msdos parttool priority_queue probe procfs progress read reboot regexp scsi search_fs_file search_fs_uuid search_label search serial setjmp setjmp_test sfs shift_test sleep sleep_test strtoull_test syslinuxcfg tar terminal terminfo test_blockarg testload test testspeed tftp tga time trig tr true udf xzio zstd"
INSTALL_DIR=$(pwd)/dist

[ -x ./configure ] || ./bootstrap
./configure --target=riscv64-linux-gnu --with-platform=efi --prefix=${INSTALL_DIR}
make -j $(($(nproc) + 1)) install

cd ${INSTALL_DIR}
./bin/grub-mkimage -v -o grubriscv64.efi -O riscv64-efi -p efi \
    -c "${SCRIPT_DIR}/default.cfg" ${MODULES}

printf "Successfully built GRUB2 image: %s\n" "${INSTALL_DIR}/grubriscv64.efi"
