BUILD_TARGETS := $(addprefix build-,$(shell ls policy/))

.dapper:
	@echo Downloading dapper
	@curl -sL https://releases.rancher.com/dapper/latest/dapper-$$(uname -s)-$$(uname -m) > .dapper.tmp
	@@chmod +x .dapper.tmp
	@./.dapper.tmp -v
	@mv .dapper.tmp .dapper

$(BUILD_TARGETS): .dapper
	./.dapper -f Dockerfile.$(@:build-%=%).dapper ./policy/$(@:build-%=%)/scripts/build

clean:
	rm -rf dist/ Dockerfile.*.dapper[0-9]*

.PHONY: $(BUILD_TARGETS) clean
