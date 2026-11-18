# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# COPR invokes this from the pinned SCM checkout, passing outdir and spec.
ASTRA_RHEL9_SEED ?= $(wildcard tools/ci/seeds/astra-rhel9-llvm22-x86_64.elf)

.PHONY: srpm
srpm:
	@test -n "$(outdir)"
	@if ! command -v git >/dev/null || ! command -v python3 >/dev/null || ! command -v rpmbuild >/dev/null; then dnf -y install git python3 rpm-build; fi
	python3 -B tools/ci/copr_source.py --commit "$$(git rev-parse HEAD)" --output "$(outdir)" --spec "$(spec)" $(if $(ASTRA_RHEL9_SEED),--rhel9-seed "$(ASTRA_RHEL9_SEED)")
