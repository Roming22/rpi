#!/bin/bash -e
set -o pipefail
set -x
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"

ask(){
    VAR="$1"
    DEFAULT="$2"
    PROMPT="$1"
    [[ -z "${DEFAULT}" ]] || PROMPT="${PROMPT} [${DEFAULT}]"
    read -r -p "${PROMPT}: " ANSWER
    echo "${VAR}: ${ANSWER:-$DEFAULT}" >> "${CONFIG}"
}

generate(){
    CONFIG="${SCRIPT_DIR}/tmp/user-data.secret"
    mkdir -p "$(dirname "${CONFIG}")"
    [[ -e "${CONFIG}" ]] && rm "${CONFIG}"
    touch "${CONFIG}"
    chmod 600 "${CONFIG}"

    ask host.name "rpi"
    ask default_user "user"

    SSH_CIPHER="ed25519"
    SSH_PRIVATE_IDENTITY="${HOME}/.ssh/id_${SSH_CIPHER}"
    SSH_PUBLIC_IDENTITY="${SSH_PRIVATE_IDENTITY}.pub"
    if [[ ! -e "$SSH_PUBLIC_IDENTITY" ]]; then
        echo "Generating a key pair for SSH"
        echo "


" | ssh-keygen -a 100 -f "${SSH_PRIVATE_IDENTITY}" -o -t "${SSH_CIPHER}" -C "${USER}@$(date +"%Y%m%d")"
    fi
    echo "default_user.ssh.authorized_keys: $(cat "$SSH_PUBLIC_IDENTITY" | cut -d" " -f1,2)" >> $CONFIG
}

generate
echo
echo "[OK]"
