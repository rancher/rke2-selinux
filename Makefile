BUILD_TARGETS := $(addprefix build-,$(shell ls policy/))

# One Lima template per policy under hack/e2e/<policy>.yaml.
DISTROS := $(patsubst hack/e2e/%.yaml,%,$(wildcard hack/e2e/*.yaml))
E2E_TARGETS := $(addprefix e2e-,$(DISTROS))
LIMA_DEBUG ?=
LIMA_CPUS ?= 4
LIMA_MEMORY ?= 8
# Optional, defaults to the version pinned in hack/e2e/setup-vm.sh.
INSTALL_RKE2_VERSION ?=

$(BUILD_TARGETS):
	docker buildx build \
      --target result --output=. \
      --build-arg TAG="${TAG}" \
      --build-arg SCRIPT=build \
			-f Dockerfile.$(@:build-%=%) .

clean:
	rm -rf dist/

# Lima instance name, expanded within the e2e-% recipes.
VM = rke2-selinux-$*

e2e: $(E2E_TARGETS)

# Build the policy, then install it with RKE2 in a fresh VM (eg. make e2e-centos9).
# On failure the VM is kept for debugging: limactl shell rke2-selinux-<distro>
$(E2E_TARGETS): e2e-%:
	rm -rf dist/$*
	$(MAKE) build-$*

	-limactl delete -f $(VM) 2>/dev/null
	limactl start $(LIMA_DEBUG) --tty=false --cpus $(LIMA_CPUS) --memory $(LIMA_MEMORY) --plain \
		--name=$(VM) hack/e2e/$*.yaml

	limactl cp dist/$*/noarch/rke2-selinux-*.noarch.rpm $(VM):/tmp/rke2-selinux.rpm
	limactl cp hack/e2e/setup-vm.sh $(VM):/tmp/setup-vm.sh
	limactl shell $(VM) sudo \
		$(if $(INSTALL_RKE2_VERSION),INSTALL_RKE2_VERSION=$(INSTALL_RKE2_VERSION)) /tmp/setup-vm.sh

	limactl delete -f $(VM)

$(addsuffix -clean,$(E2E_TARGETS)): e2e-%-clean:
	limactl delete -f $(VM)

.PHONY: $(BUILD_TARGETS) clean e2e $(E2E_TARGETS) $(addsuffix -clean,$(E2E_TARGETS))
