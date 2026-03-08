#!/bin/bash -e
set -o pipefail

usage() {
    ERROR="$1"
    [[ -z "${ERROR}" ]] || echo "$ERROR"
    echo "
Options:
  -c,--config CONFIG    configuration file
                        defaults to ./config/default.env
  -d,--disk DISK        disk on which to install the OS
  -f,--force            do not ask for any confirmation
  -r,--enable-root      enable SSH to the root user. Should only be used to debug
                        issues with cloud-init.
  -h,--help             show this message
  -v,--verbose          increase verbose level
"
    [[ -n "${ERROR}" ]] && exit 0 || exit 1
}


SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"


parse_args(){
    unset DISK
    unset ENABLE_ROOT
    unset FORCE
    CONFIG_ARGS=()
    MAKE_DISK_ARGS=()
    while [[ "$#" -gt "0" ]]; do
        case "$1" in
            -b|--backup) ACTION="backup";;
            -c|--config)
                CONFIG_ARGS+=("$1" "$2")
                MAKE_DISK_ARGS+=("$1" "$2")
                shift ;;
            -d|--disk) MAKE_DISK_ARGS+=("$1" "$2"); shift ;;
            -f|--force) MAKE_DISK_ARGS+=("$1") ;;
            -r|--enable-root) MAKE_DISK_ARGS+=("$1") ;;
            -h|--help) usage ;;
            -v|--verbose)
                set -x
                CONFIG_ARGS+=("$1")
                MAKE_DISK_ARGS+=("$1")
                ;;
            *) usage "Unknown option: $1" ;;
        esac
        shift
    done
}

main(){
    parse_args "$@"

    $SCRIPT_DIR/scripts/configure.sh "${CONFIG_ARGS[@]}"
    sudo $SCRIPT_DIR/scripts/make_disk.sh "${MAKE_DISK_ARGS[@]}"
}


if [ "$0" = "$BASH_SOURCE" ]; then
    main $@
fi
