#!/bin/bash -e
set -o pipefail

usage() {
    ERROR="$1"
    [[ -z "${ERROR}" ]] || echo "$ERROR"
    echo "
Options:
  -d,--disk DISK    disk on which to install the OS
  -f,--force        do not ask for any confirmation
  -r,--enable-root  enable SSH to the root user. Should only be used to debug
                    issues with cloud-init.
  -h,--help         show this message
  -v,--verbose      increase verbose level
"
    [[ -n "${ERROR}" ]] && exit 0 || exit 1
}


SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
DISK="$1"
IMAGES_DIR="${SCRIPT_DIR}/../images"
TMP_DIR="${SCRIPT_DIR}/tmp"

if [[ ! -e "${SCRIPT_DIR}/tmp/user-data.secret" ]]; then
    echo 'Run "./os/configure.sh" first' >&2
    exit 1
fi

# Making sure the script is run as root
if [[ "$UID" != "0" ]]; then
    echo "Run with sudo" >&2
    exit 1
fi

source "${SCRIPT_DIR}/../utils.env"


parse_args(){
    unset DISK
    unset ENABLE_ROOT
    unset FORCE
    ACTION="install"
    while [[ "$#" -gt "0" ]]; do
        case "$1" in
            -b|--backup) ACTION="backup";;
            -d|--disk) DISK=$2; shift ;;
            -f|--force) FORCE="1" ;;
            -r|--enable-root) ENABLE_ROOT="1" ;;
            -h|--help) usage ;;
            -v|--verbose) set -x ;;
            *) usage "Unknown option: $1" ;;
        esac
        shift
    done
}


choose_distribution(){
    VERSION="21.04"
    TYPE="server"
    IMAGE_URL="https://cdimage.ubuntu.com/releases/${VERSION}/release/ubuntu-${VERSION}-preinstalled-${TYPE}-arm64+raspi.img.xz"
    IMAGE_PATH="${IMAGES_DIR}/ubuntu-${VERSION}-${TYPE}.img.xz"
}


download_image(){
    if [[ ! -e "${IMAGE_PATH}" ]]; then
        log "Downloading image..."
        mkdir -p "${IMAGES_DIR}"
        curl -o "${IMAGE_PATH}" "${IMAGE_URL}"
    fi
}


create_user_data(){
    USER_DATA_TEMPLATE="${SCRIPT_DIR}/user-data.yml"
    USER_DATA_SECRET="${SCRIPT_DIR}/tmp/user-data.secret"
    USER_DATA="${SCRIPT_DIR}/tmp/user-data"

    cp "${USER_DATA_TEMPLATE}" "${USER_DATA}"

    IFS_OLD="${IFS}"
    IFS=$'\n'
    for VAR in $(grep -E "{{ *.* *}}" "${USER_DATA}" | sed -s "s:.*\${{ *\([^ }]*\) *}}.*:\1:"); do
        VALUE=$(grep -E "^${VAR}:" "${USER_DATA_SECRET}" | cut -d: -f2- | sed -e "s:^ *::")
        sed -i -e "s:\${{ *${VAR} *}}:${VALUE}:" "${USER_DATA}"
    done
    IFS="${IFS_OLD}"

    if [[ -n "$ENABLE_ROOT" ]]; then
        SALT="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 42 | head -n 1 || true)"
        ROOT_USER=$(echo "
  # Enable the root user (ONLY use when debugging cloud-init issues)\n
  - name: root\n
    ssh-authorized-keys:\n
      - $(grep "default_user.ssh.authorized_keys" "${USER_DATA_SECRET}" | cut -d" " -f 2-)" | tr -d '\n\r')
        sed -i -e "s%^users:$%\0\n$ROOT_USER%" ${USER_DATA}
    fi
}


copy_image(){
    unmount_partitions
    log "Copying image to device..."

    # Warn user before wiping the disk
    get_user_confirmation

    # Write image to disk
    xzcat "$IMAGE_PATH" | dd bs=4M of="${DISK}" status=progress
    sync

    # Refresh disk info
    partprobe "${DISK}"
}


mount_partitions(){
    mkdir -p "${TMP_DIR}"
    for PART in system-boot writeable; do
        PART_NUM="$(( PART_NUM+1 ))"
        mkdir -p "${TMP_DIR}/${PART}"
        mount "$(ls "${DISK}${PART_NUM}" || ls "${DISK}p${PART_NUM}")" "${TMP_DIR}/${PART}"
    done
}


configure_first_boot(){
    log "Configuring first boot process..."
    mount_partitions

    # Copy the user-data to the disk
    mv "${USER_DATA}" "${TMP_DIR}/system-boot/"

    # Prepare system for docker/k8s
    sed -i -e "s:rootwait:cgroup_memory=1 cgroup_enable=memory \0:" ${TMP_DIR}/system-boot/cmdline.txt
    sync
}


cleanup(){
    unmount_partitions
    for PART in system-boot writeable; do
        rm -rf "${TMP_DIR}/${PART}"
    done
}


install(){
    choose_distribution
    download_image
    create_user_data
    get_disk
    copy_image
    configure_first_boot
    cleanup
}



if [ "$0" = "$BASH_SOURCE" ]; then
    main $@
fi
