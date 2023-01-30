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
PRJ_TFTPD_PORT=10069

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

  run [--new] [STTY]
                    Run docker container. Pass '--new' to ensure a new container
                    instance is created, i.e. any existing container is removed.
                    Optionally, a host serial device STTY can be added to the
                    container. This will also start a TFTP server.

  exec [COMMAND]    Execute a command in the container.
  stop              Stop docker container.
  status            Show docker container status.
EOM
}

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
        [ "${status}" = "running" ] && docker stop ${container}
        return 0
    }

    local run_args run_cmd
    [ "${op}" = "run" ] && {
        [ "$1" = "--new" ] && {
            shift
            [ -n "${status}" ] && {
                docker stop ${container} >/dev/null
                docker rm ${container} || {
                    printf "Failed to remove existing container\n" 2>&1
                    return 1
                }
                unset status
            }
        }
        [ -n "$1" ] && {
            run_args="--device=$1 -p 0.0.0.0:69:${PRJ_TFTPD_PORT}/udp"
            # run_args="-p 0.0.0.0:69:${PRJ_TFTPD_PORT}/udp"
            run_cmd="busybox syslogd -n -O /dev/stdout &"
            run_cmd="${run_cmd} mkdir -p ${PRJ_DIR}/work &&"
            run_cmd="${run_cmd} /usr/sbin/in.tftpd -Lvvv --user cristi --address 0.0.0.0:${PRJ_TFTPD_PORT} --secure -4 ${PRJ_DIR}/work &"
            run_cmd="${run_cmd} exec bash"

            set -- /bin/sh -c "${run_cmd}"
        }
    }

    [ -z "${status}" ] &&
        exec docker run --name ${container} -h ${container} \
            --mount "type=bind,source=${PRJ_DIR},destination=${PRJ_DIR}" \
            ${run_args} \
            --log-driver local --log-opt max-size=10m --log-opt max-file=3 \
            -it ${IMAGE_NAME} "$@"

    [ "${status}" = "running" ] ||
        exec docker start -ai ${container}

    [ "${op}" != "exec" ] ||
        exec docker exec -it ${container} "${@:-bash}"
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
            --build-arg TFTPD_PORT=${PRJ_TFTPD_PORT} \
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
