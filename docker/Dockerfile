FROM debian:11.2-slim

ARG HOST_USER=riscdev
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG PRJ_DIR=/home/${HOST_USER}/visionfive

ENV LANG C.UTF-8

RUN groupadd -g ${HOST_GID} ${HOST_USER} && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} ${HOST_USER}

RUN apt update && apt upgrade -y && \
    apt install -y bash-completion bc bison cpio \
        dpkg-dev dwarves flex gcc gcc-riscv64-linux-gnu \
        git kmod libelf-dev libncurses-dev libssl-dev make python3 \
        rsync xz-utils zstd && \
    rm -rf /var/lib/apt/lists/*

USER ${HOST_USER}
RUN mkdir -p ${PRJ_DIR}
WORKDIR ${PRJ_DIR}
VOLUME ${PRJ_DIR}

CMD ["/bin/bash"]
