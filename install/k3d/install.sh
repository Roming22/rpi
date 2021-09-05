#!/bin/bash -e
SCRIPT_DIR="$(dirname "$(realpath $0)")"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
TARGET="192.168.72.90"
reset
date
cd "${ANSIBLE_DIR}"
ansible-playbook -v -i "hosts.yml" "sites.yml"
cd - 2>/dev/null
mkdir -p "${HOME}/.kube"
scp "${TARGET}:.kube/config" "${HOME}/.kube/config"
echo; echo "[Nodes]"
kubectl get nodes
echo; echo "[Deployments]"
kubectl get deployment --all-namespaces
date
