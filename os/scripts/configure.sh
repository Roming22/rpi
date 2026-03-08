#!/bin/bash -e
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"

usage() {
    ERROR="$1"
    [[ -z "${ERROR}" ]] || echo "$ERROR"
    echo "Create the configuration file(s) that will be used to configure the image.

Options:
  -c,--config CONFIG    configuration file
                        defaults to ./config/default.env
  -h,--help             show this message
  -v,--verbose          increase verbose level
"
    [[ -n "${ERROR}" ]] && exit 0 || exit 1
}



parse_args(){
    CONFIG_DIR="${SCRIPT_DIR}/../config"
    CONFIG="${CONFIG_DIR}/default.env"
    while [[ "$#" -gt "0" ]]; do
        case "$1" in
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



configure_image(){
    log "# Configuring image"
    source "${CONFIG}"
    IMAGE_CONFIG="${SCRIPT_DIR}/../tmp/user-data.secret"
    mkdir -p "$(dirname "${IMAGE_CONFIG}")"
    cat <<EOF > "${IMAGE_CONFIG}"
host.name: ${hostname}
default_user: ${username}
EOF
    chmod 600 "${IMAGE_CONFIG}"

    SSH_CIPHER="ed25519"
    SSH_PRIVATE_IDENTITY="${HOME}/.ssh/id_${SSH_CIPHER}"
    SSH_PUBLIC_IDENTITY="${SSH_PRIVATE_IDENTITY}.pub"
    if [[ ! -e "$SSH_PUBLIC_IDENTITY" ]]; then
        echo "Generating a key pair for SSH"
        echo "


" | ssh-keygen -a 100 -f "${SSH_PRIVATE_IDENTITY}" -o -t "${SSH_CIPHER}" -C "$(whoami)@$(date +"%Y%m%d")"
    fi
    echo "default_user.ssh.authorized_keys: $(cat "$SSH_PUBLIC_IDENTITY" | cut -d" " -f1,2)" >> $IMAGE_CONFIG

    # Ensure SSH config uses $username by default for this host
    mkdir -p "${HOME}/.ssh"
    SSH_CONFIG="${HOME}/.ssh/config"
    if [[ ! -f "${SSH_CONFIG}" ]] || ! grep -qE "^Host[[:space:]]${hostname}([[:space:]]|\$)" "${SSH_CONFIG}" 2>/dev/null; then
        cat >> "${SSH_CONFIG}" <<SSHEOF

Host ${hostname}
    User ${username}
SSHEOF
        echo "Added ${hostname} to ~/.ssh/config (User ${username})"
    else
        # Update existing Host block: set or correct User
        awk -v hostname="${hostname}" -v username="${username}" '
            /^Host[[:space:]]/ {
                if (in_block && !user_done) print "    User " username
                in_block = ($1 == "Host" && $2 == hostname)
                user_done = 0
            }
            in_block && /^[[:space:]]*User[[:space:]]/ {
                print "    User " username
                user_done = 1
                next
            }
            END { if (in_block && !user_done) print "    User " username }
            { print }
        ' "${SSH_CONFIG}" > "${SSH_CONFIG}.tmp" && mv "${SSH_CONFIG}.tmp" "${SSH_CONFIG}"
        echo "Updated ${hostname} in ~/.ssh/config (User ${username})"
    fi

    log "OK"
}


main(){
    parse_args "$@"

    configure_image

    echo "[Done]"
}


if [ "$0" = "$BASH_SOURCE" ]; then
    main $@
fi
