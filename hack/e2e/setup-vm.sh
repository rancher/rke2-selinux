#!/bin/bash
#
# End-to-end test for rke2-selinux. Runs as root inside a fresh VM (see Makefile e2e-% target):
#   1. installs the locally built RPM from /tmp/rke2-selinux.rpm;
#   2. installs RKE2 (tarball method) with SELinux enabled and waits for the cluster to be ready;
#   3. verifies process and file contexts and fails on any AVC denial involving RKE2 types.

set -euxo pipefail

# Override with: make e2e-<distro> INSTALL_RKE2_VERSION=vX.Y.Z+rke2rN
INSTALL_RKE2_VERSION="${INSTALL_RKE2_VERSION:-v1.35.10+rke2r1}"

RPM_PATH=/tmp/rke2-selinux.rpm
RKE2_DATA_DIR=/var/lib/rancher/rke2

# The tarball installer puts rke2 in /usr/local/bin and kubectl ships in the data dir.
# Neither is in sudo's secure_path on EL.
export PATH="${PATH}:/usr/local/bin:${RKE2_DATA_DIR}/bin"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Denials whose source or target is one of these types are attributed to rke2-selinux
# and fail the test. RKE2 itself, containerd and the kubelet run as container_runtime_t.
AVC_PATTERN='context=[^ ]*:(container_runtime_t|rke2_[a-z0-9_]+):'

function fail() {
    echo "ERROR: $*" >&2
    exit 1
}

function isSUSE() {
    grep -qi "suse" /etc/os-release
}

function dumpDiagnostics() {
    set +e
    echo "> Diagnostics"
    getenforce
    kubectl get nodes,pods -A -o wide
    journalctl -u rke2-server --no-pager | tail -n 200
    ausearch -m AVC,USER_AVC,SELINUX_ERR -ts boot
}

function checkSELinuxEnforcing() {
    echo "> Check SELinux status"
    getenforce | grep -qx Enforcing || fail "SELinux is not enforcing: $(getenforce)"
}

function installPolicy() {
    echo "> Installing rke2-selinux from ${RPM_PATH}"
    if isSUSE; then
        zypper -n --gpg-auto-import-keys install audit setools-console
        systemctl enable --now auditd
        # Install rke2-selinux on its own, as users would: container-selinux is pulled in as a
        # dependency in the same transaction, so scriptlet ordering issues are caught.
        zypper -n --gpg-auto-import-keys install --allow-unsigned-rpm "${RPM_PATH}"
    else
        # Best effort: some kernel modules used by the CNI live here on GenericCloud images,
        # but the package matching the running kernel may no longer be in the repos.
        dnf install -y "kernel-modules-extra-$(uname -r)" || echo "WARN: kernel-modules-extra-$(uname -r) not available"
        # Test against the latest container-selinux and selinux-policy available for the distro.
        dnf install -y --best --allowerasing container-selinux selinux-policy
        dnf install -y audit setools-console
        systemctl enable --now auditd
        dnf install -y "${RPM_PATH}"
    fi
}

function verifyPolicy() {
    echo "> Verify rke2-selinux installation"
    local expected installed
    expected=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "${RPM_PATH}")
    installed=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}' rke2-selinux) || fail "rke2-selinux RPM is not installed"
    [[ "${installed}" == "${expected}" ]] || fail "installed ${installed}, expected ${expected}"

    # The spec scriptlets exit 0 on failure, so check the module was actually loaded.
    semodule -l | awk '{print $1}' | grep -qx rke2 || fail "rke2 SELinux module not loaded"

    local t
    for t in rke2_service_t rke2_service_db_t rke2_tls_t rke2_service_db_file_t; do
        seinfo -t "${t}" | grep -qw "${t}" || fail "SELinux type ${t} unknown"
    done
    echo "rke2-selinux ${installed} verified."
}

function installRKE2() {
    echo "> Installing RKE2 ${INSTALL_RKE2_VERSION}"
    mkdir -p /etc/rancher/rke2
    cat > /etc/rancher/rke2/config.yaml <<EOF
selinux: true
write-kubeconfig-mode: "0644"
EOF

    # Tarball method: the RPM method would replace the local rke2-selinux with the one from
    # rpm.rancher.io, as rke2-common requires a released rke2-selinux version.
    curl -sfL https://get.rke2.io -o /tmp/install.sh
    INSTALL_RKE2_METHOD=tar INSTALL_RKE2_VERSION="${INSTALL_RKE2_VERSION}" sh /tmp/install.sh
    rm -f /tmp/install.sh

    # rke2-server is Type=notify: this returns once the apiserver is up and the kubeconfig written.
    systemctl enable --now rke2-server.service
}

function waitForCluster() {
    echo "> Waiting for the cluster to be ready"
    local node c
    node=$(hostname)
    kubectl wait --for=create "node/${node}" --timeout=240s
    kubectl wait --for=condition=ready "node/${node}" --timeout=300s

    for c in etcd kube-apiserver kube-controller-manager kube-scheduler; do
        kubectl wait --for=create -n kube-system "pod/${c}-${node}" --timeout=240s
        kubectl wait --for=condition=ready -n kube-system "pod/${c}-${node}" --timeout=240s
    done

    kubectl wait --for=create -n kube-system daemonset/rke2-canal --timeout=240s
    kubectl rollout status -n kube-system daemonset/rke2-canal --timeout=300s
    kubectl wait --for=create -n kube-system deployment/rke2-coredns-rke2-coredns --timeout=240s
    kubectl rollout status -n kube-system deployment/rke2-coredns-rke2-coredns --timeout=300s

    # Helm install jobs for the packaged charts, then every workload they created.
    kubectl wait --for=condition=complete -n kube-system job --all --timeout=600s
    kubectl wait --for=condition=ready -n kube-system pod --all \
        --field-selector=status.phase!=Succeeded,status.phase!=Failed --timeout=300s

    kubectl get nodes,pods -A -o wide
}

# checkProcessContext PROCESS_NAME EXPECTED_TYPE
# Every running process with that name must run in EXPECTED_TYPE.
function checkProcessContext() {
    local proc="$1" expected="$2"
    local labels label
    # ps truncates comm to 15 characters (e.g. kube-controller-manager).
    labels=$(ps -eo label=,comm= | awk -v p="${proc:0:15}" '$2 == p {print $1}' | sort -u)
    [[ -n "${labels}" ]] || fail "no running process named ${proc}"

    for label in ${labels}; do
        [[ "$(cut -d: -f3 <<<"${label}")" == "${expected}" ]] || fail "process ${proc} runs as ${label}, expected type ${expected}"
    done
    echo "process ${proc}: ${expected}"
}

# checkFileContext EXPECTED_TYPE PATH...
function checkFileContext() {
    local expected="$1"; shift
    local path ctx
    for path in "$@"; do
        ctx=$(stat -c %C "${path}") || fail "${path} does not exist"
        [[ "$(cut -d: -f3 <<<"${ctx}")" == "${expected}" ]] || fail "${path} is labeled ${ctx}, expected type ${expected}"
        echo "file ${path}: ${expected}"
    done
}

function verifyProcessContexts() {
    echo "> Verify process contexts"
    checkProcessContext rke2 container_runtime_t
    checkProcessContext containerd container_runtime_t
    checkProcessContext kubelet container_runtime_t
    checkProcessContext etcd rke2_service_db_t
    checkProcessContext kube-apiserver rke2_service_t
    checkProcessContext kube-controller-manager rke2_service_t
    checkProcessContext kube-scheduler rke2_service_t
}

function verifyFileContexts() {
    echo "> Verify file contexts"
    checkFileContext container_runtime_exec_t /usr/local/bin/rke2 ${RKE2_DATA_DIR}/data/*/bin/containerd
    checkFileContext container_unit_file_t /usr/local/lib/systemd/system/rke2-server.service
    checkFileContext container_var_lib_t ${RKE2_DATA_DIR}
    checkFileContext container_config_t ${RKE2_DATA_DIR}/data/*/charts
    checkFileContext rke2_tls_t ${RKE2_DATA_DIR}/server/tls ${RKE2_DATA_DIR}/server/tls/server-ca.crt
    checkFileContext rke2_service_db_file_t ${RKE2_DATA_DIR}/server/db ${RKE2_DATA_DIR}/server/db/etcd
    checkFileContext container_log_t \
        ${RKE2_DATA_DIR}/server/logs \
        ${RKE2_DATA_DIR}/agent/logs/kubelet.log \
        ${RKE2_DATA_DIR}/agent/containerd/containerd.log
    checkFileContext container_var_run_t /run/k3s
    checkFileContext container_file_t /etc/cni /etc/cni/net.d /opt/cni /opt/cni/bin

    # Informational: list paths whose type differs from the file context database.
    restorecon -Rnv ${RKE2_DATA_DIR} /etc/cni /opt/cni /usr/local/bin/rke2 || true
}

function verifyEtcdSnapshot() {
    echo "> Verify etcd snapshot"
    rke2 etcd-snapshot save --name e2e
    checkFileContext rke2_service_db_file_t ${RKE2_DATA_DIR}/server/db/snapshots ${RKE2_DATA_DIR}/server/db/snapshots/e2e-*
}

function verifyNoAVCs() {
    echo "> Look for AVC denials"
    local avcs relevant
    avcs=$(ausearch -m AVC,USER_AVC,SELINUX_ERR -ts boot 2>/dev/null || true)
    if [[ -n "${avcs}" ]]; then
        echo "All AVCs since boot (informational):"
        echo "${avcs}"
    fi

    relevant=$(grep -E "${AVC_PATTERN}" <<<"${avcs}" || true)
    [[ -z "${relevant}" ]] || fail "AVC denials involving RKE2 types:"$'\n'"${relevant}"
    echo "No AVC denials involving RKE2 types."
}

function main() {
    checkSELinuxEnforcing
    installPolicy
    verifyPolicy
    installRKE2
    waitForCluster
    verifyProcessContexts
    verifyFileContexts
    verifyEtcdSnapshot
    verifyNoAVCs
}

trap 'rc=$?; if [[ ${rc} -ne 0 ]]; then dumpDiagnostics; fi; exit ${rc}' EXIT

main
