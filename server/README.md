# Server

Automate the deployment of a server.

## Deploy

* In [`k3d/ansible/hosts.yml`](k3d/ansible/hosts.yml), set `ansible_host` to the node's IP for first bootstrap (DNS/mDNS may not work yet):

  ```yaml
  k3d0.iot:
    ansible_host: 192.168.x.x
  ```

* Run `./tools/container/run.sh ./server/k3d/run.sh`
