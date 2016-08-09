#!/bin/bash

: ${SYSLOG_TAG:=}
: ${SYSLOG_FACILITY:=local0}
: ${DEBUG:=0}
: ${LOG_DEBUG:=0}
: ${SETTINGS_FILE:=/app/settings.env}

if [ -n "$SYSLOG_TAG" ]; then
    log_pipe=/tmp/bash_log_pipe_$(date +%s)_${RANDOM}.tmp
    trap "rm -f $log_pipe" EXIT
    mknod $log_pipe p
    while read a_line_; do _log info "$a_line_"; done <$log_pipe &
    exec 1>&-
    exec 1>$log_pipe
    exec 2>&1
fi

_log() {
    local level=$1; shift;
    if [ $# -gt 0 ]; then
        if [ -n "$SYSLOG_TAG" ]; then
            logger -t "${SYSLOG_TAG}" -p "${SYSLOG_FACILITY}.${level}" -- "$@";
        else
            echo -E "$(date "+%Y-%m-%dT%H:%M:%S") [$level] $@"
        fi
    fi
}

bail() {
    _log error "$@. Exiting...";
    exit 1;
}

info() {
    _log info "$@";
}

debug() {
    [ "0$LOG_DEBUG" -eq 1 ] &>/dev/null && _log debug "$@" ||:
}

set_debug() {
    [ "0$DEBUG" -eq 1 ] &>/dev/null && set -x ||:
}

check_command() {
    if [ -n "$1" ] && ! which "$1" &>/dev/null; then
        echo "Command '$1' not found"
        exit 1;
    fi
    return 0;
}

file_exists() {
    [ -n "$1" -a -f "$1" ]
}

file_not_exists() {
    [ -n "$1" -a ! -f "$1" ]
}

bail_file_exists() {
    file_not_exists "$1" || bail "$1 already exists; not overwriting"
}

bail_file_not_exists() {
    file_exists "$1" || bail "$1 could not be found"
}

fn_exists() {
    [[ $(type -t "$1") == function ]]
}

# check if the given value is not empty and is a number
is_number() {
    [ "$1" -eq "$1" ] &>/dev/null
}

load_settings_file() {
    if [ -f "${SETTINGS_FILE}" ]; then
        set -a
        source "${SETTINGS_FILE}"
        set +a
    fi
}

check_command logger
