#!/bin/bash -e
# Install ansible
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.."; pwd)"
COLLECTIONS_REQUIREMENTS="${REPO_ROOT}/tools/ansible/requirements.yml"

install_ansible(){
	command -v ansible >/dev/null 2>&1 || sudo dnf install -y ansible
	ansible-galaxy collection install -r "${COLLECTIONS_REQUIREMENTS}"
}

install_ansible
