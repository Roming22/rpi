#!/bin/bash -e
# Install ansible
set -o pipefail

install_ansible(){
	command -v ansible >/dev/null 2>&1 || sudo dnf install -y ansible
	ansible-galaxy collection install ansible.posix
	ansible-galaxy collection install community.general
}

install_ansible
