#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Copyright (C) 2022 Cristian Ciocaltea <cristian.ciocaltea@gmail.com>
#
# Utility script to manage a Docker image & container which provides
# a toolchain for building software targeting the VisionFive SBC.

SCRIPT_DIR=$(readlink -mn "$0")
SCRIPT_DIR=${SCRIPT_DIR%/*}

PRJ_DIR=$(readlink -mn "${SCRIPT_DIR}/..")
PRJ_SER2NET_PORT=10050
PRJ_TFTPD_PORT=10069
PRJ_NFSD_PORT=12049

#
# Help
#
print_usage() {
    cat <<EOM
Usage: ${0##*/} [OPTION]... COMMAND
Helper script to automate Docker container creation for building VisionFive sources.

Options:
  -h, --help        Display this help text and exit.

  -p, --project_dir DIR
                    Set project directory to a custom location.

Commands:
  build             Build docker image.

  run [--new] [--nfs] [--interactive] [STTY [BAUD]]
                    Run docker container. Pass '--new' to ensure a new container
                    instance is created, i.e. any existing container is removed.
                    Pass '--nfs' to start an NFS service.
                    Pass '-i' or '--interactive' to open a console terminal in
                    the container.
                    Optionally, a host serial device STTY can be added to the
                    container. This will also start a TFTP server.

  exec [COMMAND]    Execute a command in the container.
  stop              Stop docker container.
  status            Show docker container status.
EOM
}

#
# arg1: container name
# arg2: operation - run, exec, stop, status
# arg3..argn: optional arguments to run/exec operations
#
manage_container() {
    local container=$1 op=$2
    shift 2

    local status
    status=$(docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null)

    [ "${op}" = "status" ] && {
        printf "'%s' container status: %s\n" "${container}" "${status:-N/A}"
        return 0
    }

    [ "${op}" = "stop" ] && {
        [ "${status}" = "running" ] && {
            printf "Stopping container %s\n" "${container}"
            docker stop ${container}
        }
        return 0
    }

    local flag_new flag_nfs flag_inter sdev sbaud run_args run_cmd
    [ "${op}" = "run" ] && {
        while [ $# -gt 0 ]; do
            case $1 in
            --new)
                flag_new=y
                ;;
            --nfs)
                flag_nfs=y
                ;;
            -i | --interactive)
                flag_inter=y
                ;;
            -*)
                printf "Uknown option: %s\n" "$1" 2>&1
                return 1
                ;;
            *)
                sdev=$1
                sbaud=${2:-115200}
                break
                ;;
            esac

            shift
        done

        [ -n "${flag_new}" ] && [ -n "${status}" ] && {
            printf "Removing container %s\n" "${container}"
            docker stop ${container} >/dev/null
            docker rm ${container} || {
                printf "Failed to remove existing container\n" 2>&1
                return 1
            }
            unset status
        }

        [ -n "${sdev}" ] && {
            run_args="--device=${sdev} -p 0.0.0.0:${PRJ_SER2NET_PORT}:${PRJ_SER2NET_PORT}/tcp"
            run_args="${run_args} -p 0.0.0.0:69:${PRJ_TFTPD_PORT}/udp"
            set -- op_start_s2n_tftp "${sdev}" "${sbaud}" "$(id -u -n)"
        }

        [ -n "${flag_nfs}" ] && {
            run_args="${run_args} -p 0.0.0.0:2049:${PRJ_NFSD_PORT}/tcp"
            run_cmd="/usr/local/bin/entrypoint.sh op_start_nfs --read-only"
        }
    }

    [ -z "${status}" ] && {
        printf "Creating container %s\n" "${container}"
        docker run --name ${container} -h ${container} \
            --mount "type=bind,source=${PRJ_DIR},destination=${PRJ_DIR}" \
            ${run_args} \
            --log-driver local --log-opt max-size=10m --log-opt max-file=3 \
            --detach ${IMAGE_NAME} "$@" || return 1

        status=$(docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null)
        [ "${status}" = "running" ] || {
            printf "Container %s is not running!\n" "${container}"
            return 1
        }
    }

    [ "${status}" = "running" ] || {
        printf "Starting container %s\n" "${container}"
        docker start ${container}
    }

    [ -n "${run_cmd}" ] &&
        docker exec --detach ${container} ${run_cmd}

    [ -n "${flag_inter}" ] && op="exec" && set -- bash

    [ "${op}" = "exec" ] &&
        exec docker exec -it ${container} "${@:-bash}"

    return 0
}

#
# Main
#
IMAGE_NAME=visionfive/cross
CONTAINER_NAME=visionfive-build

while [ $# -gt 0 ]; do
    case $1 in
    -h | --help)
        print_usage
        exit 0
        ;;

    -p | --project_dir)
        shift
        [ -n "$1" ] || {
            print_usage
            exit 1
        }

        PRJ_DIR=$(readlink -mn "$1")
        [ -d "${PRJ_DIR}" ] || {
            printf "Invalid project directory: %s\n" "${PRJ_DIR}" 2>&1
            exit 1
        }
        ;;

    -*)
        printf "Invalid option: %s\n" "$1" 2>&1
        print_usage
        exit 1
        ;;

    build)
        #--no-cache
        docker build \
            --build-arg HOST_USER=$(id -u -n) \
            --build-arg HOST_UID=$(id -u) \
            --build-arg HOST_GID=$(id -g) \
            --build-arg HOST_UUCP_GID=$(getent group uucp | cut -d: -f3) \
            --build-arg PRJ_DIR=${PRJ_DIR} \
            --build-arg SER2NET_PORT=${PRJ_SER2NET_PORT} \
            --build-arg TFTPD_PORT=${PRJ_TFTPD_PORT} \
            --build-arg NFSD_PORT=${PRJ_NFSD_PORT} \
            -t ${IMAGE_NAME} ${SCRIPT_DIR}
        exit $?
        ;;

    run | exec | stop | status)
        manage_container ${CONTAINER_NAME} "$@"
        exit $?
        ;;

    *)
        print_usage
        exit 1
        ;;
    esac

    shift
done

print_usage

# vim: et sts=4 sw=4
