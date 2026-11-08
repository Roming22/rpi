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
                         (apt pause/facts/resume always unless --skip-tags always;
                         tags: bootstrap, docker, cluster, argocd, always)
  --skip-tags TAGS       comma-separated Ansible skip-tags to pass through
  --help                 show this message
  -v,--verbose           shell set -x and ansible-playbook -v
"
    [[ -n "${ERROR}" ]] && exit 1 || exit 0
}



parse_args(){
    HOSTS=()
    ANSIBLE_TAGS=""
    ANSIBLE_SKIP_TAGS=""
    VERBOSE=0
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
            -v|--verbose) VERBOSE=1; set -x ;;
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
        -i "${ANSIBLE_DIR}/hosts.yml"
        "${ANSIBLE_DIR}/sites.yml"
        --limit "$host"
    )
    [[ "${VERBOSE}" -eq 1 ]] && args+=(-v)
    [[ -n "${ANSIBLE_TAGS}" ]] && args+=(--tags "${ANSIBLE_TAGS}")
    [[ -n "${ANSIBLE_SKIP_TAGS}" ]] && args+=(--skip-tags "${ANSIBLE_SKIP_TAGS}")
    "${args[@]}"
}



get_kubeconfig(){
    mkdir -p "${HOME}/.kube"
    local dest="${HOME}/.kube/config.${host}"
    scp "${host}:.kube/config" "${dest}"
    # Only point the default kubeconfig at this host for single-host runs.
    if [[ "${#HOSTS[@]}" -eq 1 ]]; then
        ln -fs "config.${host}" "${HOME}/.kube/config"
    else
        log "Saved kubeconfig to ${dest} (multi-host run; left ~/.kube/config unchanged)"
    fi
}



print_cluster_info(){
    local kubeconfig="${HOME}/.kube/config.${host}"
    echo; echo "[Nodes]"
    kubectl --kubeconfig="${kubeconfig}" get nodes
    echo; echo "[Deployments]"
    kubectl --kubeconfig="${kubeconfig}" get deployment --all-namespaces
}



print_access_info(){
    local kubeconfig="${HOME}/.kube/config.${host}"
    local kc=(kubectl --kubeconfig="${kubeconfig}")
    local argocd_password="unavailable"
    local headlamp_token="unavailable"
    local b64

    if "${kc[@]}" -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
        b64="$("${kc[@]}" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}')"
        argocd_password="$(printf '%s' "${b64}" | base64 -d)"
    fi
    if "${kc[@]}" -n kube-system get secret headlamp-admin >/dev/null 2>&1; then
        b64="$("${kc[@]}" -n kube-system get secret headlamp-admin -o jsonpath='{.data.token}')"
        headlamp_token="$(printf '%s' "${b64}" | base64 -d)"
    fi

    echo
    echo "[Access]"
    echo "ArgoCD:"
    echo "  URL: https://argocd.${host}"
    echo "  Username: admin"
    echo "  Password: ${argocd_password}"
    echo "Headlamp:"
    echo "  URL: https://${host}"
    echo "  Token: ${headlamp_token}"
}



install_collections(){
    if ansible-galaxy collection list 2>/dev/null | grep -qE 'ansible\.posix'; then
        return 0
    fi
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
        if ssh "$host" test -f .kube/config; then
            get_kubeconfig
            print_cluster_info
            print_access_info
        else
            log "No kubeconfig on ${host} yet (skipped scp)"
        fi
        echo
    done
    log "All hosts deployed"

    echo "Done"
}



if [ "$0" = "$BASH_SOURCE" ]; then
    main "$@"
fi
