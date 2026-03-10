ifeq ($(OS),Windows_NT)
# Override if your environment exposes bash under another name/path:
#   make WIN_BASH=bash.exe lint
#   make WIN_BASH=C:/tools/git/bin/bash.exe ci
WIN_BASH_AUTO := $(strip $(shell powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows/detect-bash.ps1))
WIN_BASH ?= $(WIN_BASH_AUTO)
ifeq ($(strip $(WIN_BASH)),)
$(error unable to detect bash.exe; set WIN_BASH=C:/path/to/bash.exe)
endif
override SHELL := $(WIN_BASH)
override MAKESHELL := $(WIN_BASH)
else
SHELL := /usr/bin/env bash
endif
.SHELLFLAGS := -eu -o pipefail -c

SHELL_SOURCES := xray-reality.sh lib.sh install.sh config.sh service.sh health.sh export.sh scripts/measure-stealth.sh scripts/release.sh scripts/check-release-consistency.sh scripts/release-policy-gate.sh scripts/check-dead-functions.sh scripts/check-workflow-pinning.sh scripts/check-security-baseline.sh scripts/check-docs-commands.sh scripts/check-shell-complexity.sh scripts/check-shellcheck-advisory.sh scripts/lab/*.sh modules/lib/*.sh modules/config/*.sh modules/install/*.sh tests/e2e/*.sh
TEST_SOURCES := tests/*.sh
MARKDOWN_SOURCES := README.md README.ru.md .github/CONTRIBUTING.md .github/CONTRIBUTING.ru.md .github/SECURITY.md .github/SECURITY.ru.md docs/en/*.md docs/ru/*.md
WORKFLOWS := .github/workflows/ci.yml .github/workflows/nightly-smoke.yml .github/workflows/release.yml .github/workflows/packages.yml .github/workflows/os-matrix-smoke.yml

.PHONY: lint test release-check audit audit-deep ci ci-fast ci-full lab-smoke vm-lab-prepare vm-lab-smoke

lint:
	command -v shellcheck >/dev/null
	command -v bashate >/dev/null
	command -v shfmt >/dev/null
	command -v actionlint >/dev/null
	shellcheck -x -e SC1091 $(SHELL_SOURCES) $(TEST_SOURCES)
	bashate -i E003,E006,E042,E043 $(SHELL_SOURCES) $(TEST_SOURCES)
	shfmt -d -i 4 -ci -sr $(SHELL_SOURCES) $(TEST_SOURCES)
	actionlint -oneline $(WORKFLOWS)
	bash scripts/check-dead-functions.sh
	bash scripts/check-shell-complexity.sh
	bash scripts/check-workflow-pinning.sh
	bash scripts/check-security-baseline.sh
	bash scripts/check-docs-commands.sh
	if command -v markdownlint >/dev/null; then \
		NODE_OPTIONS=--no-deprecation markdownlint --config .markdownlint.json $(MARKDOWN_SOURCES); \
	elif command -v npx >/dev/null; then \
		NODE_OPTIONS=--no-deprecation npx --yes markdownlint-cli@0.41.0 --config .markdownlint.json $(MARKDOWN_SOURCES); \
	else \
		echo "markdownlint and npx are required for markdown lint" >&2; \
		exit 1; \
	fi

test:
	command -v bats >/dev/null
	LANG="$${LANG:-C.UTF-8}" LC_ALL="$${LC_ALL:-C.UTF-8}" bats tests/bats

release-check:
	bash scripts/check-release-consistency.sh

audit:
	bash scripts/check-workflow-pinning.sh
	bash scripts/check-security-baseline.sh
	bash scripts/check-docs-commands.sh

audit-deep: ci
	bash scripts/check-shellcheck-advisory.sh

ci-fast: lint test release-check

ci: ci-fast audit

ci-full: ci audit-deep

lab-smoke:
	bash scripts/lab/run-container-smoke.sh

vm-lab-prepare:
	bash scripts/lab/prepare-vm-smoke.sh

vm-lab-smoke:
	bash scripts/lab/run-vm-lifecycle-smoke.sh
