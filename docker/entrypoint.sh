#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Copyright (C) 2023 Cristian Ciocaltea <cristian.ciocaltea@gmail.com>
#
# Docker container entrypoint script.

log() {
    local level=$1
    shift
    logger -s -t monitor -p user.${level} -- $*
}

#
# Sanitize a string for logging purpose.
#
# arg1: input string
#
# NOTE: for the moment it just replaces '\n' with '|'.
#
sanitize_log() {
    printf "%s" "$1" | tr '\n' '|'
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
# Start NFS related services.
# Default client access is rw, default write mode is async.
# See https://linux.die.net/man/5/exports for possible options.
#
start_nfs() {
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

    [ -n "${export_dir}" ] || {
        log err "Expecting export_dir"
        exit 1
    }

    run_cmd sed \
        -e "s@{{EXPORT}}@${export_dir}@g" \
        -e "s/{{HOST}}/${host_filter:-*}/g" \
        -e "s/{{ACCESS}}/${access_flags:-rw}/g" \
        -e "s/{{SYNC}}/${sync_flags:-async}/g" \
        -i /etc/exports || exit $?

    log info "Dumping /etc/exports"
    log info </etc/exports

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

    pidof -q rpc.mountd || {
        # Sync /var/lib/nfs/etab with /etc/exports
        log info "Updating table of exported NFS file systems"
        run_cmd /usr/sbin/exportfs -rv || exit $?
        log info "Executing exportfs -v"
        /usr/sbin/exportfs -v | log info

        log info "Starting NFS mount daemon"
        # --exports-file /etc/exports
        run_cmd /usr/sbin/rpc.mountd --no-nfs-version 2 --no-nfs-version 3 \
            --no-udp --debug all || exit $?
    }
}

stop_all() {
    local pids=${SLEEP_PID}

    log info "Terminating services.."

    # NFS mount daemon
    busybox kill -TERM $(pidof rpc.mountd) >/dev/null 2>&1
    # Unexport all exports listed in /etc/exports
    run_cmd /usr/sbin/exportfs -au
    # Stop all threads and thus close any open connections
    run_cmd /usr/sbin/rpc.nfsd 0

    # TFTPD & ser2net
    pids="${pids} $(pidof in.tftpd) $(pidof ser2net)"
    # NFSD
    pids="${pids} $(pidof rpc.nfsd) $(pidof rpcbind)"

    busybox kill -TERM ${pids} >/dev/null 2>&1
}

monitor() {
    while :; do
        log info "Waiting for signals.."
        sleep 2073600 &
        SLEEP_PID=$!
        wait
    done

    log info "Exit monitor"
    exit 0
}

unset SLEEP_PID
trap "stop_all; exit 0" INT TERM

case $1 in
monitor | start_nfs | stop_all)
    "$@"
    exit $?
    ;;
esac

[ -n "$1" ] || {
    log err "Expecting command"
    exit 1
}

log info "Executing command:" "$*"
exec "$@"
