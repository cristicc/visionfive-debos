#!/bin/sh

SCRIPT_DIR=$(readlink -mn "$0")
SCRIPT_DIR=${SCRIPT_DIR%/*}

PRJ_DIR=$(readlink -mn "${SCRIPT_DIR}/..")

#
# Help
#
print_usage() {
    cat <<EOM
Usage: ${0##*/} [OPTION]... COMMAND
Helper script to automate Docker container creation for building VisionFive sources.

Options:
  -h, --help        Display this help text and exit

Commands:
  build             Build docker image
  run               Run docker container
  exec [COMMAND]    Execute a command in the container
  stop              Stop docker container
EOM
}

manage_container() {
    local container=$1 op=$2
    shift 2

    local status
    status=$(docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null)

    [ "${op}" = "stop" ] && {
        [ "${status}" = "running" ] && docker stop ${container}
        return 0
    }

    [ -z "${status}" ] &&
        exec docker run --name ${container} -h ${container} \
            --mount "type=bind,source=${PRJ_DIR},destination=${PRJ_DIR}" \
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
    -*)
        print_usage
        exit 1
        ;;

    build)
        #--no-cache
        docker build \
            --build-arg HOST_USER=$(id -u -n) \
            --build-arg HOST_UID=$(id -u) \
            --build-arg HOST_GID=$(id -g) \
            --build-arg PRJ_DIR=${PRJ_DIR} \
            -t ${IMAGE_NAME} ${SCRIPT_DIR}
        exit $?
        ;;

    run | exec | stop)
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
