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
  -h,--host HOST    host to deploy, can be specified multiple times
                    defaults to all hosts
  --help            show this message
  -v,--verbose      increase verbose level
"
    [[ -n "${ERROR}" ]] && exit 0 || exit 1
}



parse_args(){
    HOSTS=()
    while [[ "$#" -gt "0" ]]; do
        case "$1" in
            -h|--host) HOSTS+=("$2"); shift ;;
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
    ansible-playbook -v -i "${ANSIBLE_DIR}/hosts.yml" "${ANSIBLE_DIR}/sites.yml" --limit "$host"
}



get_kubeconfig(){
    mkdir -p "${HOME}/.kube"
    scp "${host}:.kube/config" "${HOME}/.kube/config.${host}"
    ln -fs "${HOME}/.kube/config.${host}" "${HOME}/.kube/config"
}



print_cluster_info(){
    echo; echo "[Nodes]"
    kubectl get nodes
    echo; echo "[Deployments]"
    kubectl get deployment --all-namespaces
}



main(){
    parse_args "$@"
    ANSIBLE_DIR="${SCRIPT_DIR}/ansible"

    reset
    HOSTS=("${HOSTS[@]:-$(ansible -i server/k3d/ansible/hosts.yml all --list-hosts 2>/dev/null | tail -n +2 | sed 's/^[[:space:]]*//')}")
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
    main $@
fi
