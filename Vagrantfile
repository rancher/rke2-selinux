# -*- mode: ruby -*-
# vi: set ft=ruby :

CPUS = (ENV['VAGRANT_RKE2_SELINUX_CPUS'] || 2).to_i
MEMORY = (ENV['VAGRANT_RKE2_SELINUX_MEMORY'] || 2048).to_i

# Adapted from https://github.com/containerd/containerd/pull/4451
Vagrant.configure("2") do |config|
  config.vm.box = "centos/7"
  config.vm.provider :virtualbox do |v|
    config.vm.box_url = "https://cloud.centos.org/centos/7/vagrant/x86_64/images/CentOS-7-x86_64-Vagrant-2004_01.VirtualBox.box"
    v.memory = MEMORY
    v.cpus = CPUS
  end
  config.vm.provider :libvirt do |v|
    config.vm.box_url = "https://cloud.centos.org/centos/7/vagrant/x86_64/images/CentOS-7-x86_64-Vagrant-2004_01.LibVirt.box"
    v.memory = MEMORY
    v.cpus = CPUS
  end

  # Disabled by default. To run:
  #   vagrant up --provision-with=upgrade-packages
  # To upgrade only specific packages:
  #   UPGRADE_PACKAGES=selinux vagrant up --provision-with=upgrade-packages
  #
  config.vm.provision "upgrade-packages", type: "shell", run: "never" do |sh|
    sh.upload_path = "/tmp/vagrant-upgrade-packages"
    sh.env = {
        'UPGRADE_PACKAGES': ENV['UPGRADE_PACKAGES'],
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        yum -y upgrade ${UPGRADE_PACKAGES}
    SHELL
  end

  # Disabled by default. To run:
  #   vagrant provision --provision-with=kernel-mainline
  config.vm.provision "kernel-mainline", type: "shell", run: "never" do |sh|
    sh.upload_path = "/tmp/vagrant-kernel-mainline"
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        yum -y install \
            https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel -y install kernel-ml
        sed -i -e "s|GRUB_DEFAULT.*$|GRUB_DEFAULT=0|" /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg
    SHELL
    sh.reboot = true
  end

  # To re-run, installing CNI from RPM:
  #   INSTALL_PACKAGES="containernetworking-plugins" vagrant up --provision-with=install-packages
  #
  config.vm.provision "install-packages", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-install-packages"
    sh.env = {
        'INSTALL_PACKAGES': ENV['INSTALL_PACKAGES'],
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        yum -y install \
            bzip2 \
            container-selinux \
            curl \
            gcc \
            git \
            iptables \
            libseccomp-devel \
            libselinux-devel \
            lsof \
            make \
            selinux-policy-devel \
            socat \
            ${INSTALL_PACKAGES}
    SHELL
  end

  config.vm.provision "install-policy", type: "shell", run: "always" do |sh|
    sh.upload_path = "/tmp/vagrant-install-policy"
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        pushd /vagrant
        yum install -y yum-utils rpm-build
        yum-builddep -y container-selinux
        yum -y remove rke2-selinux
        # TODO build
        yum -y install ./dist/centos7/noarch/*.rpm
    SHELL
  end

  # To re-run this provisioner, installing a different version of go:
  #   GO_VERSION="1.15rc2" vagrant up --provision-with=install-golang
  #
  config.vm.provision "install-golang", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-install-golang"
    sh.env = {
        'GO_VERSION': ENV['GO_VERSION'] || "1.13.15",
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        curl -fsSL "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" | tar Cxz /usr/lib
        ln -fnsv /usr/lib/go/bin/{go,gofmt} /usr/bin
    SHELL
  end

  config.vm.provision "install-runc", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-install-runc"
    sh.env = {
        'GOPATH': "/usr",
        'RUNC_VERSION': ENV['RUNC_VERSION'] || "v1.0.0-rc92",
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        go get -d github.com/opencontainers/runc
        pushd ${GOPATH}/src/github.com/opencontainers/runc
        git checkout ${RUNC_VERSION}
        make BUILDTAGS='apparmor seccomp selinux' runc
        make BINDIR=${GOPATH}/bin install
        type runc
        runc --version
        restorecon -v $(type -ap runc)
    SHELL
  end

  config.vm.provision "install-cni", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-install-cni"
    sh.env = {
        'GOPATH': "/usr",
        'CNI_DIR': "/opt/cni",
        'CNI_CONFIG_DIR': "/etc/cni/net.d",
        'CNI_PLUGINS_VERSION': ENV['CNI_PLUGINS_VERSION'] || "v0.7.6",
        'CNI_PLUGINS_BINARIES': 'bridge dhcp flannel host-device host-local ipvlan loopback macvlan portmap ptp tuning vlan',
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        go get -d github.com/containernetworking/plugins/...
        pushd "$GOPATH"/src/github.com/containernetworking/plugins
        git checkout $CNI_PLUGINS_VERSION
        FASTBUILD=true ./build.sh
        sudo mkdir -p $CNI_DIR
        sudo cp -r ./bin $CNI_DIR
        sudo mkdir -p $CNI_CONFIG_DIR
        PATH=/opt/cni/bin:$PATH type ${CNI_PLUGINS_BINARIES} || true
        cat <<EOF | sudo tee $CNI_CONFIG_DIR/10-containerd-net.conflist
{
  "cniVersion": "0.3.1",
  "name": "containerd-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "promiscMode": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.88.0.0/16",
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
EOF
    SHELL
  end

  config.vm.provision "install-containerd", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-install-containerd"
    sh.env = {
        'GOPATH': "/usr",
        'CONTAINERD_REPO': ENV['CONTAINERD_REPO'] || "github.com/rancher/containerd",
        'CONTAINERD_VERSION': ENV['CONTAINERD_VERSION'] || "v1.3.6-k3s2",
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        if [ ! -d ${GOPATH}/src/github.com/containerd/containerd ]; then
            git clone https://${CONTAINERD_REPO}.git ${GOPATH}/src/github.com/containerd/containerd
        fi
        pushd ${GOPATH}/src/github.com/containerd/containerd
        git checkout ${CONTAINERD_VERSION}
        make PACKAGE=${CONTAINERD_REPO} \
             DESTDIR=${GOPATH} \
             BUILDTAGS="seccomp selinux no_aufs no_btrfs no_devmapper no_zfs" \
            binaries install
        type containerd
        containerd --version
        restorecon -v /usr/bin/{containerd,containerd-shim*}
    SHELL
  end

  config.vm.provision "install-cri-tools", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-install-cri-tools"
    sh.env = {
        'GOPATH': "/usr",
        'CRI_TOOLS_VERSION': ENV['CRI_TOOLS_VERSION'] || 'master',
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        go get -u github.com/onsi/ginkgo/ginkgo
        go get -d github.com/kubernetes-sigs/cri-tools/...
        pushd ${GOPATH}/src/github.com/kubernetes-sigs/cri-tools
        git checkout $CRI_TOOLS_VERSION
        make
        sudo make BINDIR=${GOPATH}/bin install
        cat << EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
EOF
        type crictl critest ginkgo
        critest --version
    SHELL
  end

  # SELinux is Enforcing by default.
  # To set SELinux as Disabled on a VM that has already been provisioned:
  #   SELINUX=Disabled vagrant up --provision-with=selinux
  # To set SELinux as Permissive on a VM that has already been provsioned
  #   SELINUX=Permissive vagrant up --provision-with=selinux
  config.vm.provision "selinux", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-selinux"
    sh.env = {
        'SELINUX': ENV['SELINUX'] || "Enforcing"
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail

        if ! type -p getenforce setenforce &>/dev/null; then
          echo SELinux is Disabled
          exit 0
        fi

        case "${SELINUX}" in
          Disabled)
            if mountpoint -q /sys/fs/selinux; then
              setenforce 0
              umount -v /sys/fs/selinux
            fi
            ;;
          Enforcing)
            mountpoint -q /sys/fs/selinux || mount -o rw,relatime -t selinuxfs selinuxfs /sys/fs/selinux
            setenforce 1
            ;;
          Permissive)
            mountpoint -q /sys/fs/selinux || mount -o rw,relatime -t selinuxfs selinuxfs /sys/fs/selinux
            setenforce 0
            ;;
          *)
            echo "SELinux mode not supported: ${SELINUX}" >&2
            exit 1
            ;;
        esac

        echo SELinux is $(getenforce)
    SHELL
  end

  # SELinux is permissive by default (via provisioning) in this VM. To re-run with SELinux enforcing:
  #   vagrant up --provision-with=selinux-enforcing,test-cri
  #
  config.vm.provision "test-cri", type: "shell", run: "never" do |sh|
    sh.upload_path = "/tmp/test-cri"
    sh.env = {
        'CRITEST_ARGS': ENV['CRITEST_ARGS'],
    }
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        cat << EOF > /vagrant/containerd.service
[Unit]
Description=rke2 containerd
Documentation=https://github.com/rancher/rke2
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd \
    -c /var/lib/rancher/rke2/agent/etc/containerd/config.toml \
    -a /run/k3s/containerd/containerd.sock \
    --state /run/k3s/containerd \
    --root /var/lib/rancher/rke2/agent/containerd \


Delegate=yes
KillMode=process
Restart=always
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=1048576
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF
        systemctl disable --now containerd || true
        rm -rf /var/lib/rancher/rke2 /run/rke2
        enable_selinux=false
        if [[ $(getenforce) != Disabled ]]; then
          enable_selinux=true
        fi
        mkdir -p /var/lib/rancher/rke2/agent/etc/containerd
        cat << EOF | sudo tee /var/lib/rancher/rke2/agent/etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    enable_selinux = ${enable_selinux}
EOF
        chcon -v -t container_unit_file_t /vagrant/containerd.service
        systemctl enable --now /vagrant/containerd.service
        function cleanup()
        {
            journalctl -u containerd > /tmp/containerd.log
            systemctl stop containerd
        }
        trap cleanup EXIT
        ctr --address /run/k3s/containerd/containerd.sock version
        critest --parallel=$(nproc) --ginkgo.skip='runtime should support HostIpc is true' ${CRITEST_ARGS}
    SHELL
  end

  config.vm.provision "rke2", type: "shell", run: "once" do |sh|
    sh.upload_path = "/tmp/vagrant-rke2"
    sh.inline = <<~SHELL
        #!/usr/bin/env bash
        set -eux -o pipefail
        curl -sfL https://get.rke2.io | sh -
    SHELL
  end

end
