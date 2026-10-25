.PHONY: lint test

# The tests run the opstruss and the tools that mise.toml pins, ahead of any
# others in PATH. OPSTRUSS=<path> tests another opstruss, such as a build
# of a source checkout.
OPSTRUSS ?= $(shell mise which opstruss)
export PATH := $(abspath $(dir $(OPSTRUSS))):$(shell mise bin-paths | tr '\n' ':')$(PATH)

TESTS := $(wildcard tests/*/*.txtar)

lint:
	shellcheck $(wildcard lib/*.sh plugins/*/*.sh)
	actionlint

test:
	testscript -e CATALOG=$(CURDIR) $(TESTS)
