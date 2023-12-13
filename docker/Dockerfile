FROM debian:11.2-slim

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y autoconf autopoint autotools-dev \
        b4 bash-completion bc bison busybox cpio \
        debhelper dpkg-dev dwarves flex gcc gcc-riscv64-linux-gnu \
        git gettext kmod \
        libelf-dev libcap2-bin libncurses-dev libssl-dev \
        make pkg-config \
        nfs-common nfs-kernel-server \
        python3 python3-pexpect python3-pip python3-serial \
        rsync ser2net swig telnet tftpd-hpa u-boot-tools \
        xz-utils zstd && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install --upgrade dtschema yamllint

COPY exports ser2net.yaml /etc/
COPY entrypoint.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/entrypoint.sh

ARG HOST_USER=riscdev
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG HOST_UUCP_GID=986
ARG PRJ_DIR=/home/${HOST_USER}/visionfive
ARG SER2NET_PORT=10050
ARG TFTPD_PORT=10069
ARG NFSD_PORT=12049

ENV PATH=/home/${HOST_USER}/local/bin:/usr/local/bin:${PATH}
ENV LANG C.UTF-8
ENV PRJ_DIR=${PRJ_DIR}
ENV SER2NET_PORT=${SER2NET_PORT}
ENV TFTPD_PORT=${TFTPD_PORT}
ENV NFSD_PORT=${NFSD_PORT}

EXPOSE ${SER2NET_PORT}/tcp
EXPOSE ${TFTPD_PORT}/udp
EXPOSE ${NFSD_PORT}/tcp

# TODO: restrict capabilities to mandatory only
RUN setcap "cap_net_raw,cap_net_bind_service,cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap=+ep" /bin/busybox
RUN setcap "cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_setfcap=+ep" /usr/sbin/in.tftpd

# TODO: using setcap on NFS services doesn't seem to work, need to run as root
# RUN setcap "cap_net_raw,cap_net_bind_service,cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_setfcap+ep" /sbin/rpcbind
# RUN setcap "cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_setfcap+ep" /usr/sbin/rpc.nfsd
# RUN setcap "cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_setfcap+ep" /usr/sbin/rpc.mountd
RUN setcap "cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_setgid,cap_setuid,cap_setpcap,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap=+ep" /usr/sbin/exportfs

RUN groupadd -g ${HOST_GID} ${HOST_USER} && \
    groupmod -g ${HOST_UUCP_GID} uucp && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} -G uucp ${HOST_USER} && \
    echo 'alias kmake="make -j $(($(nproc)+1)) O=build ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- LOCALVERSION=\"\""' \
        >> /home/${HOST_USER}/.bash_aliases

RUN mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery && \
    echo "rpc_pipefs    /var/lib/nfs/rpc_pipefs rpc_pipefs      defaults        0       0" >> /etc/fstab && \
    echo "nfsd  /proc/fs/nfsd   nfsd    defaults        0       0" >> /etc/fstab

USER ${HOST_USER}
RUN mkdir -p ${PRJ_DIR}
WORKDIR ${PRJ_DIR}
VOLUME ${PRJ_DIR}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["monitor"]
