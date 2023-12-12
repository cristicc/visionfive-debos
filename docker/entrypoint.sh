#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Copyright (C) 2023 Cristian Ciocaltea <cristian.ciocaltea@gmail.com>
#
# Docker container entrypoint script.

log() {
    local level=$1
    shift
    logger -s -t entrypoint -p user.${level} -- $*
}

#
# Sanitize a string for logging purpose.
#
# arg1: input string
#
# NOTE: for the moment it just replaces '\n' with '|'.
#
sanitize_log() {
    printf "%s" "$1" | tr "\n" "|"
}

#
# Execute a command and control related logging.
#
# arg1: command
# argn: command args
#
# Returns the command exit code.
#
run_cmd() {
    local res err

    # Captures stderr, letting stdout through.
    exec 3>&1
    err=$("$@" 2>&1 1>&3)
    res=$?
    exec 3>&-

    [ ${res} -eq 0 ] ||
        log err "Command '$*' failed: $(sanitize_log "${err:-<no stderr msg>}")"

    return ${res}
}

#
# Test if the given argument is a function.
#
# arg1: Name of a function
#
is_function() {
    case "$(type -- "$1" 2>/dev/null)" in
    *function*) return 0 ;;
    esac
    return 1
}

#
# Variant of pidof using a regex matching on command string.
#
pidof_regex() {
    local quiet=0 regex p spid pids out_pids
    [ "$1" = "-q" ] && {
        quiet=1
        shift
    }

    regex=${1#^}
    [ "${regex}" = "$1" ] && regex=".*${regex}"
    [ "${regex%\$}" = "${regex}" ] && regex="${regex}.*"

    pids=$(busybox ps -o "pid,args")
    pids=$(printf "%s" "${pids}" | sed -nE "s/^\s*([0-9]+)\s${regex}/\1/gp")

    # Filter out pid of the current subshell and its parent.
    # WARNING: $$ always returns PID of the parent shell!
    # (grep "PPid" /proc/self/status)
    spid=$(sh -c 'echo ${PPID}')

    [ -n "${pids}" ] && {
        for p in ${pids}; do
            [ "${p}" != "$$" ] && [ "${p}" != "${spid}" ] && out_pids="${out_pids} ${p}"
        done
    }
    pids=${out_pids# }

    [ ${quiet} -eq 0 ] && printf "%s\n" "${pids}"

    [ -n "${pids}" ]
}

op_start_s2n_tftp() {
    local sdev=$1 sbaud=$2 user=${3:-nobody}

    pidof -q ser2net || {
        [ -n "${sdev}" ] && [ -n "${sbaud}" ] || {
            log err "Expecting sdev and/or sbaud"
            exit 1
        }

        run_cmd cp /etc/ser2net.yaml /tmp/ser2net.yaml
        run_cmd sed \
            -e "s/{PORT}/${SER2NET_PORT:-20000}/" \
            -e "s@{DEVICE}@${sdev}@" \
            -e "s/{BAUD}/${sbaud}/" \
            /etc/ser2net.yaml >/tmp/ser2net.yaml || exit $?

        run_cmd /usr/sbin/ser2net -c /tmp/ser2net.yaml || exit $?
    }

    pidof -q in.tftpd || {
        run_cmd mkdir -p ${PRJ_DIR}/work || exit $?

        run_cmd /usr/sbin/in.tftpd -Lvvv --user ${user} \
            --address 0.0.0.0:${TFTPD_PORT:-69} --secure -4 \
            ${PRJ_DIR}/work || exit $?
    }
}

#
# Start NFS related services.
# Default client access is rw, default write mode is async.
# See https://linux.die.net/man/5/exports for possible options.
#
op_start_nfs() {
    local export_dir host_filter access_flags sync_flags
    local port=${NFSD_PORT:-2049}

    while [ $# -gt 0 ]; do
        case $1 in
        --export_dir)
            shift
            export_dir=$1
            ;;
        --host)
            shift
            host_filter=$1
            ;;
        --read-only)
            access_flags=ro
            ;;
        --sync)
            sync_flags=sync
            ;;
        *)
            log err "Invalid nfsd arg: $1"
            exit 1
            ;;
        esac
        shift
    done

    # FIXME: normally not required for v4
    # Only used as workaround for an IPv6 related NFS bug.
    pidof -q rpcbind || {
        log info "Starting rpcbind"
        run_cmd /sbin/rpcbind -w || exit $?
    }

    # FIXME: rpc.nfsd is not detected as a process
    busybox netstat -tln | grep -q ":${port}\b" || {
        log info "Starting NFS server daemon"
        run_cmd /usr/sbin/rpc.nfsd --no-nfs-version 2 --no-nfs-version 3 \
            --no-udp --syslog --debug -p ${port} 8 || exit $?
    }

    pidof -q rpc.mountd && return 0

    #
    # /etc/exports is used by exportfs to give information to rpc.mountd.
    #
    # The exportfs command maintains the current table of exports for the
    # NFS server, which is kept in a file named /var/lib/nfs/etab. This is
    # further read by rpc.mountd when a client sends an NFS MOUNT request.
    #
    log info "Updating /etc/exports"
    run_cmd sed \
        -e "s@{{EXPORT}}@${export_dir:-${PRJ_DIR}/work/nfs/rootfs}@g" \
        -e "s/{{HOST}}/${host_filter:-*}/g" \
        -e "s/{{ACCESS}}/${access_flags:-rw}/g" \
        -e "s/{{SYNC}}/${sync_flags:-async}/g" \
        -i /etc/exports || exit $?

    log info "Dumping /etc/exports"
    log info </etc/exports

    # Sync /var/lib/nfs/etab with /etc/exports
    log info "Syncing NFS exports table"
    run_cmd /usr/sbin/exportfs -rv || exit $?
    log info "Dumping NFS exports table"
    /usr/sbin/exportfs -v | log info

    log info "Starting NFS mount daemon"
    # --exports-file /etc/exports
    run_cmd /usr/sbin/rpc.mountd --no-nfs-version 2 --no-nfs-version 3 \
        --no-udp --debug all || exit $?
}

op_stop_all() {
    local pids="$*"

    log info "Terminating services.."

    # NFS mount daemon
    busybox kill -TERM $(pidof rpc.mountd) >/dev/null 2>&1
    # Unexport all exports listed in /etc/exports
    run_cmd /usr/sbin/exportfs -au
    # Stop all threads and thus close any open connections
    run_cmd /usr/sbin/rpc.nfsd 0

    # Additional NFS related services
    pids="${pids} $(pidof rpc.nfsd) $(pidof rpcbind)"
    # TFTPD & ser2net
    pids="${pids} $(pidof in.tftpd) $(pidof ser2net)"

    busybox kill -TERM ${pids} >/dev/null 2>&1
}

monitor_ctl() {
    local monitor_pid
    # {entrypoint.sh} /bin/sh docker/entrypoint.sh monitor start
    monitor_pid=$(pidof_regex "^\{${0##*/}\}.*${0##*/} monitor( start)?\$")

    case ${1:-start} in
    stop)
        [ -n "${monitor_pid}" ] || {
            log info "monitor already stopped"
            return 0
        }
        busybox kill -TERM ${monitor_pid}
        ;;

    status)
        [ -n "${monitor_pid}" ]
        ;;

    start | *)
        [ -n "${monitor_pid}" ] && {
            log info "monitor already running"
            return 0
        }

        log info "Starting monitor"
        unset MONITOR_SLEEP_PID
        trap 'op_stop_all ${MONITOR_SLEEP_PID}; exit 0' INT TERM

        while :; do
            log info "Waiting for signals.."
            sleep 2073600 &
            MONITOR_SLEEP_PID=$!
            wait
        done
        ;;
    esac

    return $?
}

process_op() {
    local op=$1 func

    log info "Processing operation ${op}"
    func=$(printf "%s" "${op}" | tr "-" "_")

    is_function ${func} || {
        log err "Unknown operation: ${op}"
        exit 1
    }

    # Start monitor if not already running
    monitor_ctl status || {
        sleep 1
        monitor_ctl status || nohup "$0" monitor &
    }

    shift
    ${func} "$@"
}

# Ensure syslogd & monitor are always running
pidof_regex -q "^busybox syslogd\b.*stdout\$" || {
    busybox syslogd -n -O /dev/stdout &
}

# Args parser
case $1 in
op_* | op-*)
    process_op "$@"
    exit $?
    ;;
monitor)
    monitor_ctl $2
    exit $?
    ;;
-h | --help)
    log info "Docker entrypoint script"
    exit 0
    ;;
-*)
    log err "Invalid option: $1"
    exit 1
    ;;
esac

[ -n "$1" ] || {
    log err "Expecting command"
    exit 1
}

log info "Executing command:" "$*"
exec "$@"
