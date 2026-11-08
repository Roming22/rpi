#!/bin/bash -e
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"

usage() {
    ERROR="${1:-}"
    [[ -z "${ERROR}" ]] || echo "$ERROR" >&2
    echo "
Options:
  -h,--host HOST         host to deploy, can be specified multiple times
                         defaults to all hosts
  --tags TAGS            comma-separated Ansible tags to pass through
  --skip-tags TAGS       comma-separated Ansible skip-tags to pass through
  --help                 show this message
  -v,--verbose           increase shell verbose level (set -x)
"
    [[ -n "${ERROR}" ]] && exit 1 || exit 0
}



parse_args(){
    HOSTS=()
    ANSIBLE_TAGS=""
    ANSIBLE_SKIP_TAGS=""
    while [[ "$#" -gt "0" ]]; do
        case "$1" in
            -h|--host)
                [[ "$#" -ge 2 ]] || usage "Missing value for $1"
                HOSTS+=("$2"); shift ;;
            --tags)
                [[ "$#" -ge 2 ]] || usage "Missing value for $1"
                ANSIBLE_TAGS="$2"; shift ;;
            --skip-tags)
                [[ "$#" -ge 2 ]] || usage "Missing value for $1"
                ANSIBLE_SKIP_TAGS="$2"; shift ;;
            --help) usage ;;
            -v|--verbose) set -x ;;
            *) usage "Unknown option: $1" ;;
        esac
        shift
    done
}


log(){
    echo "$(date +%H:%M:%S) $1"
}



run_ansible(){
    local args=(
        ansible-playbook
        -v
        -i "${ANSIBLE_DIR}/hosts.yml"
        "${ANSIBLE_DIR}/sites.yml"
        --limit "$host"
    )
    [[ -n "${ANSIBLE_TAGS}" ]] && args+=(--tags "${ANSIBLE_TAGS}")
    [[ -n "${ANSIBLE_SKIP_TAGS}" ]] && args+=(--skip-tags "${ANSIBLE_SKIP_TAGS}")
    "${args[@]}"
}



get_kubeconfig(){
    mkdir -p "${HOME}/.kube"
    scp "${host}:.kube/config" "${HOME}/.kube/config.${host}"
    ln -fs "config.${host}" "${HOME}/.kube/config"
}



print_cluster_info(){
    echo; echo "[Nodes]"
    kubectl get nodes
    echo; echo "[Deployments]"
    kubectl get deployment --all-namespaces
}



install_collections(){
    log "# Installing Ansible collections"
    ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yml"
}

list_inventory_hosts(){
    ansible -i "${ANSIBLE_DIR}/hosts.yml" all --list-hosts \
        | tail -n +2 \
        | sed 's/^[[:space:]]*//' \
        | sed '/^$/d'
}

main(){
    parse_args "$@"
    ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"

    install_collections

    if [[ "${#HOSTS[@]}" -eq 0 ]]; then
        mapfile -t HOSTS < <(list_inventory_hosts)
    fi
    if [[ "${#HOSTS[@]}" -eq 0 || -z "${HOSTS[0]:-}" ]]; then
        echo "No hosts found in inventory ${ANSIBLE_DIR}/hosts.yml" >&2
        exit 1
    fi

    for host in "${HOSTS[@]}"; do
        log "# Running ansible on ${host}"
        run_ansible
        get_kubeconfig
        print_cluster_info
        echo
    done
    log "All hosts deployed"

    echo "Done"
}



if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
