rke2-selinux for el7
---

The Vagrant box in use supports these providers:
- `libvirt`
- `virtualbox`
- `vmware_desktop`

To spin up a VM to test locally built rke2-selinux RPM:
```shell
cp -vf ../../dist/centos7/noarch/*.rpm .
INSTALL_PACKAGES=/vagrant/rke2-selinux-*.noarch.rpm vagrant up
```
