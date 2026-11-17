# rke2-selinux
RKE2 selinux policy repository

## Signing Keys

- https://rpm.rancher.io/public.key
- https://rpm-testing.rancher.io/public.key

## Versioning/Tagging

The version parsing logic for `rancher/rke2-selinux` expects tags to be of a certain format (that directly correlates to RPM naming)

The tag format should be as follows: `v{rke2-selinux version}.{rpm channel}.{rpm release}` where 

rke2-selinux-version is like `0.1`, `0.2`, etc.
rpm channel is like `testing`, `latest`, `stable`
rpm release is like `1`, `2`

rpm release should index from `1` for released RPM's

The following list shows the expected tag to (example) transformation for RPM's

|Tag|Tree State|Output RPM|RPM Channel|Notes|
|:--|:---------|:---------|:----------|:----|
| master (no tag) | Clean | `rke2-selinux-0.0~0d52f7d8-0.el7_8.noarch.rpm` | Testing ||
| master (no tag) | Dirty | `rke2-selinux-0.0~0d52f7d8-0.el7_8.noarch.rpm` | Testing ||
| v0.2.testing.1 | Clean | `rke2-selinux-0.2-1.el7_8.noarch.rpm` | Testing ||
| v0.2.latest.1 | Clean | `rke2-selinux-0.2-1.el7_8.noarch.rpm` | Latest ||
| v0.2.latest.2 | Clean | `rke2-selinux-0.2-2.el7_8.noarch.rpm` | Latest ||

## Development

Building requires Docker with `buildx`. End-to-end tests require [Lima](https://lima-vm.io) and QEMU.

| Command                      | Description                                                 |
| :--------------------------- | :---------------------------------------------------------- |
| `make build-<policy>`        | Build a single policy (e.g. `make build-centos9`)           |
| `make e2e`                   | Run end-to-end tests for all policies                       |
| `make e2e-<policy>`          | Run end-to-end tests in a VM (e.g. `make e2e-centos9`)      |
| `make e2e-<policy>-clean`    | Delete the VM left behind by a failed run                   |

Artefacts are written to `dist/<policy>/`.

The end-to-end test (`hack/e2e/setup-vm.sh`) builds the policy, boots a VM from `hack/e2e/<policy>.yaml`,
installs the RPM, installs RKE2 with `selinux: true` and checks that:

- the RPM and the `rke2` module are installed and its types are known;
- RKE2, containerd and the kubelet run as `container_runtime_t`, etcd as `rke2_service_db_t` and the
  control-plane static pods as `rke2_service_t`;
- RKE2 files (binaries, data dir, TLS, etcd data and snapshots, logs, CNI) have the expected labels;
- there are no AVC denials involving `container_runtime_t` or `rke2_*` types.

Every policy has an end-to-end test except `slemicro` (SLE Micro 5.x): there is no freely available
cloud-init image for it, and it is transactional. The `sle` policy is tested on openSUSE Leap 16.

Use `INSTALL_RKE2_VERSION` to test against another RKE2 release (e.g. `make e2e-centos9 INSTALL_RKE2_VERSION=v1.36.6+rke2r1`).
