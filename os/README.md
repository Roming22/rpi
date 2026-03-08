# Automate the setup the boot disk for a Raspberry Pi

## OS

Automate the creation of a bootable USB/SD-Card drive for a Raspberry Pi 4, with the required configuration to run containers.

## Usage

* Create a config file in `./os/config` for the new server.
* Plug the disk/SSD card/USB key.
* Run `./os/setup.sh -c CONFIG_NAME -d DISK_PATH` to create the boot disk.
* Follow the instruction on screen.
* Plug the drive in your Rapsberry Pi and power it on. The device should NOT be used until it has completed the first boot setup and rebooted. 
* You can monitor the first boot with `ssh $USER@$IP sudo tail -f /var/log/cloud-init-output.log` where `$USER` is the value of `username` in `tmp/user-data.secret` and `$IP` is the IP of the device on the network.
