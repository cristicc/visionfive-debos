#!/bin/sh

set -e

SCRIPT_DIR=$(realpath "$0")
SCRIPT_DIR=${SCRIPT_DIR%/*}

INSTALL_DIR=${SCRIPT_DIR}/../work/debos

DEBOS_IMAGE=godebos/debos
docker image inspect ${DEBOS_IMAGE} >/dev/null 2>&1 || {
    echo "Pulling debos docker image"
    docker pull ${DEBOS_IMAGE}
}

if [ -f "${INSTALL_DIR}/rootfs-base.tar" ]; then
    echo "Using existing rootfs base"
    DEV_OPTS="-t use_rootfs_base:yes"
else
    DEV_OPTS="-t use_rootfs_base:create"
fi

DEV_OPTS="${DEV_OPTS} -t create_image:yes"
#DEBUG_OPTS="--debug-shell --verbose"

echo "Syncing build resources"
alias rsync='rsync -av --omit-dir-times --info=flist0,stats0,remove --out-format=" %i %n"'

mkdir -p ${INSTALL_DIR} && cd ${INSTALL_DIR}
rsync --exclude="/${0##*/}" ${SCRIPT_DIR}/ ${INSTALL_DIR}/

BIN_DIR=${INSTALL_DIR}/scripts/bin
mkdir -p ${BIN_DIR}
rsync ${INSTALL_DIR}/../linux/linux-image-*_riscv64.deb ${BIN_DIR}/
rsync ${INSTALL_DIR}/../grub/dist/grubriscv64.efi ${BIN_DIR}/

IMG_FILE=${INSTALL_DIR}/debian-riscv64.img.gz
rm -rf "${IMG_FILE}"

docker run --device /dev/kvm -u $(id -u) -w /recipes \
    --mount "type=bind,source=$(pwd),destination=/recipes" \
    --security-opt label=disable --rm -it \
    ${DEBOS_IMAGE} ${DEV_OPTS} ${DEBUG_OPTS} "$@" \
    debimage-riscv64.yaml

[ -f "$IMG_FILE" ] && {
    IMG_FILE=$(realpath "${IMG_FILE}")
    printf "Created disk img: %s\n" "${IMG_FILE}"
}
