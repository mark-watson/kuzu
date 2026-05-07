# Helper frontend to cmake.
# Tip: to see the actual commands that will be run for any target, use `make -n <target>`.
#
# Simplified for Python + C-library (future Common Lisp CFFI) workflows.

.DEFAULT_GOAL := release
.PHONY: \
	release relwithdebinfo debug \
	python python-debug python-install pytest pytest-debug \
	c-lib swi-prolog \
	install \
	clean-python-api clean
.ONESHELL:
.SHELLFLAGS = -ec

BUILD_TYPE ?=
BUILD_PATH ?=
EXTRA_CMAKE_FLAGS ?=
PREFIX ?= install

ifeq ($(shell uname -s 2>/dev/null),Linux)
	NUM_THREADS ?= $(shell expr $(shell nproc) \* 2 / 3)
else ifeq ($(shell uname -s 2>/dev/null),Darwin)
	NUM_THREADS ?= $(shell expr $(shell sysctl -n hw.ncpu) \* 2 / 3)
else
	NUM_THREADS ?= 1
endif
export CMAKE_BUILD_PARALLEL_LEVEL=$(NUM_THREADS)

# Shared library extension
ifeq ($(shell uname -s 2>/dev/null),Darwin)
	SHARED_EXT ?= dylib
else
	SHARED_EXT ?= so
endif

ifeq ($(OS),Windows_NT)
	GEN ?= Ninja
	SHELL := cmd.exe
	.SHELLFLAGS := /c
endif

ifdef GEN
	CMAKE_FLAGS += -G "$(GEN)"
endif

ifdef EXTRA_CMAKE_FLAGS
	CMAKE_FLAGS += $(EXTRA_CMAKE_FLAGS)
endif

# Skip single-file-header generation (scripts/ pruned from this fork)
CMAKE_FLAGS += -DBUILD_SINGLE_FILE_HEADER=FALSE

# ── Core build targets ──────────────────────────────────────────────


release:
	$(call run-cmake-release,)

relwithdebinfo:
	$(call run-cmake-relwithdebinfo,)

debug:
	$(call run-cmake-debug,)

# ── Python targets ──────────────────────────────────────────────────

python:
	$(call run-cmake-release, -DBUILD_PYTHON=TRUE -DBUILD_SHELL=FALSE)

python-debug:
	$(call run-cmake-debug, -DBUILD_PYTHON=TRUE)

pytest: python
	cmake -E env PYTHONPATH=tools/python_api/build python3 -m pytest -vv tools/python_api/test

pytest-debug: python-debug
	cmake -E env PYTHONPATH=tools/python_api/build python3 -m pytest -vv tools/python_api/test

python-install: python  ## Build and install kuzu Python package globally via uv
	uv pip install --system .

# ── C shared library (for Common Lisp CFFI, etc.) ──────────────────

c-lib: cffi-wrapper  ## Build libkuzu shared library + CFFI wrapper
	@echo ""
	@echo "✓ libkuzu built in build/release/src/"
	@echo "  Link with -lkuzu and include src/include/c_api/kuzu.h"

cffi-wrapper: release  ## Build thin C wrapper for CL CFFI (avoids struct-by-value)
	$(CC) -shared -o build/$(call get-build-path,Release)/src/libkuzu_cffi.$(SHARED_EXT) \
		kuzu_cffi_wrapper.c -Isrc/include \
		-Lbuild/$(call get-build-path,Release)/src -lkuzu

swi-prolog: release  ## Build SWI-Prolog foreign library bridge
	swipl-ld -shared -o build/$(call get-build-path,Release)/src/kuzu_swi \
		kuzu_swi.c -Isrc/include \
		-Lbuild/$(call get-build-path,Release)/src -lkuzu \
		-Wl,-rpath,@loader_path


# ── Installation ────────────────────────────────────────────────────

install:
	cmake --install build/$(call get-build-path,Release) --prefix $(PREFIX)

# ── Cleaning ────────────────────────────────────────────────────────

clean-python-api:
	cmake -E rm -rf tools/python_api/build

clean: clean-python-api
	cmake -E rm -rf build

# ── CMake utility functions ─────────────────────────────────────────

lowercase = $(if $(filter Release,$(1)),release,$(if $(filter RelWithDebInfo,$(1)),relwithdebinfo,$(if $(filter Debug,$(1)),debug,$(1))))
get-build-type = $(if $(BUILD_TYPE),$(BUILD_TYPE),$1)
get-build-path = $(if $(BUILD_PATH),$(BUILD_PATH),$(call lowercase,$(call get-build-type,$(1))))

define config-cmake
	cmake -B build/$(call get-build-path,$1) -DCMAKE_BUILD_TYPE=$(call get-build-type,$1) $2 $(CMAKE_FLAGS) $(EXTRA_CMAKE_FLAGS) .
endef

define build-cmake
	cmake --build build/$(call get-build-path,$1) --config $(call get-build-type,$1)
endef

define run-cmake
	$(call config-cmake,$1,$2)
	$(call build-cmake,$1)
endef

define run-cmake-debug
	$(call run-cmake,Debug,$1)
endef

define build-cmake-release
	$(call build-cmake,Release,$1)
endef

define build-cmake-relwithdebinfo
	$(call build-cmake,RelWithDebInfo,$1)
endef

define config-cmake-release
	$(call config-cmake,Release,$1)
endef

define config-cmake-relwithdebinfo
	$(call config-cmake,RelWithDebInfo,$1)
endef

define run-cmake-release
	$(call config-cmake-release,$1)
	$(call build-cmake-release,$1)
endef

define run-cmake-relwithdebinfo
	$(call config-cmake-relwithdebinfo,$1)
	$(call build-cmake-relwithdebinfo,$1)
endef
