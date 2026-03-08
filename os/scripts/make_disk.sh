#!/bin/bash -e
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"

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



parse_args(){
    unset DISK
    unset ENABLE_ROOT
    unset FORCE
    CONFIG_DIR="${SCRIPT_DIR}/../config"
    CONFIG="${CONFIG_DIR}/default.env"
    ACTION="create"
    while [[ "$#" -gt "0" ]]; do
        case "$1" in
            -b|--backup) ACTION="backup";;
            -c|--config) shift
                if [[ -e "$1" ]]; then
                    CONFIG=$1
                elif [[ -e "${CONFIG_DIR}/$1" ]]; then
                    CONFIG="${CONFIG_DIR}/$1"
                elif [[ -e "${CONFIG_DIR}/$1.env" ]]; then
                    CONFIG="${CONFIG_DIR}/$1.env"
                else
                    usage "Config file not found: $1"
                fi
            ;;
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



log(){
    log_n "$1\n"
}

log_n(){
    echo -en "$(date +%H:%M:%S)\t$1"
}



init(){
    # Making sure the script is run as root
    if [[ "$UID" != "0" ]]; then
        echo "[ERROR] Run with sudo" >&2
        exit 1
    fi

    source "${CONFIG}"
    IMAGES_DIR="${SCRIPT_DIR}/../images"
    TMP_DIR="${SCRIPT_DIR}/../tmp"
}



list_disks(){
    lsblk -l -o NAME,TYPE | grep -E "\sdisk$" | cut -d" " -f1
}


wait_for_disk(){
    # Wait for the disk to be inserted
    DISK_COUNT="$(list_disks | wc -l)"
    DISK_LIST="$(list_disks | sed "s:.*:^\0$:" | tr "\n" "|")"
    DISK_LIST="${DISK_LIST%?}"
    log "Insert the disk to continue"
    while [[ $(list_disks | wc -l) -eq "${DISK_COUNT}" ]]; do
        sleep 1
    done
    DISK="/dev/$(list_disks | grep -E -v $DISK_LIST)"

    # Give the OS some time to automount partitions
    sleep 10
}


get_disk(){
    if [[ -n "${DISK}" ]]; then
        if [[ ! -e "${DISK}" ]]; then
            echo "${DISK} not found" >&2
            exit 1
        fi
    else
        wait_for_disk
    fi

    # Check that the boot disk was not found by mistakea
    if [[ $(df | grep "${DISK}" | grep -c "/boot") != "0" ]]; then
        echo "Something unexpected happened. Try again." >&2
        exit 1
    fi
}


choose_distribution(){
    TYPE="server"
    IMAGE_URL="https://cdimage.ubuntu.com/releases/${version_id}/release/ubuntu-${version_id}-preinstalled-${TYPE}-arm64+raspi.img.xz"
    IMAGE_PATH="${IMAGES_DIR}/ubuntu-${version_id}-${TYPE}.img.xz"
}


download_image(){
    log "# Get image"
    if [[ ! -e "${IMAGE_PATH}" ]]; then
        log "Downloading image..."
        mkdir -p "${IMAGES_DIR}"
        curl -o "${IMAGE_PATH}" "${IMAGE_URL}"
    fi
    log "OK"
}


create_user_data(){
    log "# Create user data"
    USER_DATA_TEMPLATE="${SCRIPT_DIR}/../data/user-data.yml"
    USER_DATA_SECRET="${TMP_DIR}/user-data.secret"
    USER_DATA="${TMP_DIR}/user-data"

    cp "${USER_DATA_TEMPLATE}" "${USER_DATA}"

    IFS_OLD="${IFS}"
    IFS=$'\n'
    for VAR in $(grep -E "{{ *.* *}}" "${USER_DATA}" | sed -s "s:.*\${{ *\([^ }]*\) *}}.*:\1:"); do
        VALUE=$(grep -E "^${VAR}:" "${USER_DATA_SECRET}" | cut -d: -f2- | sed -e "s:^ *::")
        sed -i -e "s:\${{ *${VAR} *}}:${VALUE}:" "${USER_DATA}"
    done
    IFS="${IFS_OLD}"

    if [[ -n "${ENABLE_ROOT:-}" ]]; then
        SALT="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 42 | head -n 1 || true)"
        ROOT_USER=$(echo "
  # Enable the root user (ONLY use when debugging cloud-init issues)\n
  - name: root\n
    ssh-authorized-keys:\n
      - $(grep "default_user.ssh.authorized_keys" "${USER_DATA_SECRET}" | cut -d" " -f 2-)" | tr -d '\n\r')
        sed -i -e "s%^users:$%\0\n$ROOT_USER%" ${USER_DATA}
    fi  
    log "OK"
}


get_partitions(){
    df | grep -E "^${DISK}p?[0-9]+\s" | cut -d" " -f1
}


unmount_partitions(){
    if [[ "$(get_partitions | wc -l)" != "0" ]]; then
        for PARTITION in "$(get_partitions)"; do
            umount -l $PARTITION
            umount -f $PARTITION || true
        done
    fi
    
}


copy_image(){
    unmount_partitions
    log "# Copying image to device"

    # Warn user before wiping the disk
    echo "All data on $DISK is going to be lost."
    while true; do
        [[ -z "${FORCE:-}" ]] || break
        read -r -p "Do you want to continue? [y|N]: " ANSWER
        case "${ANSWER}" in
            y|Y) break ;;
            n|N|"") echo "[Interrupted]"; exit 0;;
        esac
    done

    # Write image to disk
    log "Writing image to disk..."
    xzcat "$IMAGE_PATH" | dd bs=4M of="${DISK}" status=progress
    sync

    # Refresh disk info
    log "Refreshing disk info"
    partprobe "${DISK}"

    log "OK"
}


mount_partitions(){
    mkdir -p "${TMP_DIR}"
    PART_NUM=0
    for PART in system-boot writeable; do
        PART_NUM="$(( PART_NUM+1 ))"
        mkdir -p "${TMP_DIR}/${PART}"
        log "Mounting ${PART} to ${TMP_DIR}/${PART}"
        mount "$(ls "${DISK}${PART_NUM}" || ls "${DISK}p${PART_NUM}")" "${TMP_DIR}/${PART}"
    done
}


configure_first_boot(){
    log "# Configuring first boot process"
    mount_partitions

    # Copy the user-data to the disk
    mv "${USER_DATA}" "${TMP_DIR}/system-boot/"

    # Prepare system for docker/k8s
    sed -i -e "s:rootwait:cgroup_memory=1 cgroup_enable=memory \0:" ${TMP_DIR}/system-boot/current/cmdline.txt
    sync
    log "OK"
}


cleanup(){
    log "# Cleaning up"
    unmount_partitions
    for PART in system-boot writeable; do
        rm -rf "${TMP_DIR}/${PART}"
    done
    log "OK"
}


backup(){
    log "# Backing up image"
    get_disk
    log "Backing up image to ${TMP_DIR}/rpi.img.xz"
    sudo dd if="${DISK}" status=progress | xz > ${TMP_DIR}/rpi.img.xz
    log "OK"
}


create(){
    choose_distribution
    download_image
    create_user_data
    get_disk
    copy_image
    configure_first_boot
    cleanup
}


main(){
    parse_args "$@"

    init

    case "$ACTION" in
        backup) backup;;
        create) create;;
        "")
            "[ERROR] No action set"
            exit 1
            ;;
        *)
            "[ERROR] Unknown action: $ACTION"
            exit 1
            ;;
    esac

    log "The device is ejected and can be safely removed."
    echo
    echo "[OK]"
}


if [ "$0" = "$BASH_SOURCE" ]; then
    main $@
fi
