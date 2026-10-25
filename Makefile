.PHONY: lint test

# The tests run the opstruss and the tools that mise.toml pins, ahead of any
# others in PATH. OPSTRUSS=<path> tests another opstruss, such as a build
# of a source checkout.
OPSTRUSS ?= $(shell mise which opstruss)
export PATH := $(abspath $(dir $(OPSTRUSS))):$(shell mise bin-paths | tr '\n' ':')$(PATH)

# The Docker CLI finds its compose plugin and its contexts there, also in a
# test that sets HOME to a directory of its own.
DOCKER_CONFIG ?= $(HOME)/.docker
export DOCKER_CONFIG

# The tests of compose need a Docker daemon, which the macOS runners of
# GitHub lack.
TESTS := $(wildcard tests/*/*.txtar)
DOCKER := $(shell docker info >/dev/null 2>&1 && echo yes)
ifneq ($(DOCKER),yes)
SKIPPED := $(filter tests/compose/%,$(TESTS))
TESTS := $(filter-out $(SKIPPED),$(TESTS))
endif

lint:
	shellcheck $(wildcard lib/*.sh plugins/*/*.sh)
	actionlint

test:
	$(if $(SKIPPED),@echo 'skipped without a Docker daemon: $(SKIPPED)')
	testscript -e CATALOG=$(CURDIR) -e DOCKER_CONFIG $(TESTS)
