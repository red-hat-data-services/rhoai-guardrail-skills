# ghcr.io/stbenjam/skillsaw:latest = skillsaw 0.23.0 (2026-11-07), pinned by digest
SKILLSAW_IMAGE ?= ghcr.io/stbenjam/skillsaw@sha256:24ec88be671a8daf57513c3ad7f4ca4a8b028e9517421132032826f73d8aab61

# Prefer podman only when actually usable (machine running), else docker.
# Override explicitly with e.g.: make lint CONTAINER_ENGINE=docker
CONTAINER_ENGINE ?= $(shell podman info >/dev/null 2>&1 && echo podman || echo docker)

# SELinux-enforcing hosts (Fedora/RHEL) need :Z to relabel the bind mount;
# auto-detected via getenforce, no-op elsewhere.
MOUNT_OPTIONS ?= ro$(shell getenforce 2>/dev/null | grep -q Enforcing && echo ',Z')

.PHONY: lint
lint:
	@$(CONTAINER_ENGINE) run --rm \
	  -v "$(CURDIR)":/workspace:$(MOUNT_OPTIONS) \
	  $(SKILLSAW_IMAGE) \
	  lint .agents/skills AGENTS.md
