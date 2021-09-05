#!/bin/bash -e
SCRIPT_DIR="$(dirname "$(realpath $0)")"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
TARGET="192.168.72.90"
reset
date
ansible-playbook -v -i "${ANSIBLE_DIR}/hosts.yml" "${ANSIBLE_DIR}/sites.yml"
scp "${TARGET}:.kube/config" "${HOME}/.kube/config"
echo; echo "[Nodes]"
kubectl get nodes
echo; echo "[Deployments]"
kubectl get deployment --all-namespaces
date
