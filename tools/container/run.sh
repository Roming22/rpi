#!/bin/bash -e
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IMAGE_NAME="rpi-dev"
CONTAINER_NAME="rpi-dev"

detect_runtime() {
    if command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    else
        echo "error: podman or docker is required" >&2
        exit 1
    fi
}

build() {
    "${RUNTIME}" build \
        -f "${SCRIPT_DIR}/Containerfile" \
        -t "${IMAGE_NAME}" \
        "${PROJECT_ROOT}"
}

run() {
    local -a security_opts=()
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
        # Network mounts (e.g. NAS) cannot be relabeled with :z/:Z.
        security_opts=(--security-opt label=disable)
    fi

    if [[ $# -eq 0 ]]; then
        set -- bash
    fi

    mkdir -p "${HOME}/.kube"

    "${RUNTIME}" run -it --rm \
        --name "${CONTAINER_NAME}" \
        --user root \
        "${security_opts[@]}" \
        -v "${PROJECT_ROOT}:/workspace" \
        -v "${HOME}/.kube:/root/.kube" \
        -v "${HOME}/.ssh:/root/.ssh" \
        -e TERM="${TERM:-xterm}" \
        "${IMAGE_NAME}" \
        bash -lc 'cd /workspace && exec "$@"' bash "$@"
}

main() {
    detect_runtime
    build
    run "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
