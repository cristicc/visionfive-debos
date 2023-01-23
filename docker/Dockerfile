FROM debian:11.2-slim

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y autoconf autopoint autotools-dev \
        b4 bash-completion bc bison busybox cpio \
        dpkg-dev dwarves flex gcc gcc-riscv64-linux-gnu \
        git gettext kmod \
        libelf-dev libcap2-bin libncurses-dev libssl-dev \
        make pkg-config \
        python3 python3-pexpect python3-pip python3-serial \
        rsync swig tftpd-hpa u-boot-tools xz-utils zstd && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install --upgrade dtschema yamllint

ARG HOST_USER=riscdev
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG HOST_UUCP_GID=986
ARG PRJ_DIR=/home/${HOST_USER}/visionfive
ARG TFTPD_PORT=10069

ENV PATH=${PATH}:/home/${HOST_USER}/local/bin
ENV LANG C.UTF-8

RUN setcap 'cap_net_raw,cap_net_bind_service,cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap=+ep' /bin/busybox
RUN setcap 'cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_setfcap=+ep' /usr/sbin/in.tftpd

RUN groupadd -g ${HOST_GID} ${HOST_USER} && \
    groupmod -g ${HOST_UUCP_GID} uucp && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} -G uucp ${HOST_USER} && \
    echo 'alias kmake="make -j $(($(nproc)+1)) O=build ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- LOCALVERSION=\"\""' \
        >> /home/${HOST_USER}/.bash_aliases

EXPOSE ${TFTPD_PORT}/udp

USER ${HOST_USER}
RUN mkdir -p ${PRJ_DIR}
WORKDIR ${PRJ_DIR}
VOLUME ${PRJ_DIR}

CMD ["/bin/bash"]
