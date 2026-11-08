#!/bin/bash -e
set -o errexit
set -o nounset
set -o pipefail

usage() {
    ERROR="${1:-}"
    [[ -z "${ERROR}" ]] || echo "$ERROR" >&2
    echo "
Usage: $(basename "$0") HOST

Print ArgoCD and Headlamp access info for HOST using ~/.kube/config.HOST
"
    [[ -n "${ERROR}" ]] && exit 1 || exit 0
}

[[ "$#" -eq 1 ]] || usage "Expected exactly one HOST"
[[ "$1" != "--help" && "$1" != "-h" ]] || usage

host="$1"
kubeconfig="${HOME}/.kube/config.${host}"
[[ -f "${kubeconfig}" ]] || { echo "Missing kubeconfig: ${kubeconfig}" >&2; exit 1; }

kc=(kubectl --kubeconfig="${kubeconfig}")
argocd_password="unavailable"
headlamp_token="unavailable"

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
