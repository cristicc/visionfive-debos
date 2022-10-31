FROM debian:11.2-slim

RUN apt update && apt upgrade -y && \
    apt install -y autoconf autopoint autotools-dev \
        b4 bash-completion bc bison cpio \
        dpkg-dev dwarves flex gcc gcc-riscv64-linux-gnu \
        git gettext kmod libelf-dev libncurses-dev libssl-dev \
        make pkg-config python3 python3-pip \
        rsync swig xz-utils zstd && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install --upgrade dtschema yamllint

ARG HOST_USER=riscdev
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG PRJ_DIR=/home/${HOST_USER}/visionfive

ENV PATH=${PATH}:/home/${HOST_USER}/local/bin
ENV LANG C.UTF-8

RUN groupadd -g ${HOST_GID} ${HOST_USER} && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} ${HOST_USER} && \
    echo 'alias kmake="make -j $(($(nproc)+1)) O=build ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- LOCALVERSION=\"\""' \
        >> /home/${HOST_USER}/.bash_aliases

USER ${HOST_USER}
RUN mkdir -p ${PRJ_DIR}
WORKDIR ${PRJ_DIR}
VOLUME ${PRJ_DIR}

CMD ["/bin/bash"]
