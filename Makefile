CENTOS7_TARGETS := $(addprefix centos7-,$(shell ls policy/centos7/scripts))
CENTOS8_TARGETS := $(addprefix centos8-,$(shell ls policy/centos8/scripts))
MICROOS_TARGETS := $(addprefix microos-,$(shell ls policy/microos/scripts))
SLEMICRO_TARGETS := $(addprefix slemicro-,$(shell ls policy/slemicro/scripts))
COREOS_TARGETS := $(addprefix coreos-,$(shell ls policy/coreos/scripts))

.dapper:
	@echo Downloading dapper
	@curl -sL https://releases.rancher.com/dapper/latest/dapper-$$(uname -s)-$$(uname -m) > .dapper.tmp
	@@chmod +x .dapper.tmp
	@./.dapper.tmp -v
	@mv .dapper.tmp .dapper

$(CENTOS7_TARGETS): .dapper
	./.dapper -f Dockerfile.centos7.dapper $(@:centos7-%=%)

$(CENTOS8_TARGETS): .dapper
	./.dapper -f Dockerfile.centos8.dapper $(@:centos8-%=%)

$(MICROOS_TARGETS): .dapper
	./.dapper -f Dockerfile.microos.dapper $(@:microos-%=%)

$(SLEMICRO_TARGETS): .dapper
	./.dapper -f Dockerfile.slemicro.dapper $(@:slemicro-%=%)

$(COREOS_TARGETS): .dapper
	./.dapper -f Dockerfile.coreos.dapper $(@:coreos-%=%)

clean:
	rm -rf dist/ Dockerfile.*.dapper[0-9]*

.PHONY: $(CENTOS7_TARGETS) $(CENTOS8_TARGETS) $(MICROOS_TARGETS) clean
