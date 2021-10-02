#!/bin/bash -e
set -o pipefail
set -x
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"

ask() {
    local TYPE="$1"
    local MODE="$2"
    local VAR="$3"
    local PROMPT="$4"
    local DEFAULT="$5"

    local PAD
    local INPUT
    local READ_ARGS

    [[ -n "${!VAR}" ]] && DEFAULT="${!VAR}"

    case "$TYPE" in
        value)
            PROMPT="${PROMPT}$([[ -n "${DEFAULT}" ]] && echo -e " [${DEFAULT}]" || true)"
            ;;
        secret)
            READ_ARGS="-s"
            PROMPT="${PROMPT}$([[ -n "${DEFAULT}" ]] && echo -e " [press enter to use existing value]")"
            ;;
        *)
            echo "Unsupported type: $TYPE" >&2
            exit 1
            ;;
    esac
    case "$MODE" in
        mandatory) ;;
        optional)
            PAD="-"
            ;;
        *)
            echo "Unsupported mode: $MODE" >&2
            exit 1
            ;;
    esac

    read ${READ_ARGS} -p "${PROMPT}: " INPUT

    case "$TYPE" in
        secret)
            echo
            INPUT="$( encode_secret "${INPUT}" )"
            ;;
    esac
    export $VAR="${INPUT:-$DEFAULT}"
    [[ -z "${!VAR}${PAD}" ]] && echo "Invalid value: Do not leave blank" && exit 1
    VAR_LIST="${VAR_LIST} ${VAR}"
}

generate(){
    CONFIG_TEMPLATE="${SCRIPT_DIR}/user-data.in.ign"
    CONFIG="${SCRIPT_DIR}/tmp/user-data.secret.ign"
    mkdir -p "$(dirname "${CONFIG}")"

    ask value mandatory HOST_NAME "hostname" "rpi"
    ask value mandatory DEFAULT_USER "user" "pi"

    SSH_CIPHER="ed25519"
    SSH_PRIVATE_IDENTITY="${HOME}/.ssh/id_${SSH_CIPHER}"
    SSH_PUBLIC_IDENTITY="${SSH_PRIVATE_IDENTITY}.pub"
    if [[ ! -e "$SSH_PUBLIC_IDENTITY" ]]; then
        echo "Generating a key pair for SSH"
        echo "


" | ssh-keygen -a 100 -f "${SSH_PRIVATE_IDENTITY}" -o -t "${SSH_CIPHER}" -C "${USER}@$(date +"%Y%m%d")"
    fi
    export SSH_PUBLIC_KEY="$(cat $SSH_PUBLIC_IDENTITY)"

    envsubst < "$CONFIG_TEMPLATE" > "$CONFIG"
    chmod 600 "$CONFIG"
}

generate
echo
echo "[OK]"
