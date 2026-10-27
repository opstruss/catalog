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

# The tests of compose that start containers need a Docker daemon, which
# the macOS runners of GitHub lack; inputs.txtar needs only the docker CLI,
# and nocompose.txtar not even that.
TESTS := $(wildcard tests/*/*.txtar)
DOCKER := $(shell docker info >/dev/null 2>&1 && echo yes)
ifneq ($(DOCKER),yes)
SKIPPED := $(filter-out tests/compose/inputs.txtar tests/compose/nocompose.txtar,$(filter tests/compose/%,$(TESTS)))
TESTS := $(filter-out $(SKIPPED),$(TESTS))
endif

# check-extra-masked-returns finds a command whose failure a $(...) in an
# argument hides, as cmd "$(sha256 file)".
lint:
	shellcheck -o check-extra-masked-returns $(wildcard lib/*.sh plugins/*/*.sh examples/*/*.sh)
	actionlint

test:
	$(if $(SKIPPED),@echo 'skipped without a Docker daemon: $(SKIPPED)')
	testscript -e CATALOG=$(CURDIR) -e DOCKER_CONFIG $(TESTS)
