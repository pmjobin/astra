# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# COPR invokes this from the pinned SCM checkout, passing outdir and spec.
.PHONY: srpm
srpm:
	@test -n "$(outdir)"
	@test "$(spec)" = "packaging/rpm/astrac.spec"
	@command -v rpmbuild >/dev/null || dnf -y install rpm-build
	python3 -B tools/ci/copr_source.py --commit "$$(git rev-parse HEAD)" --output "$(outdir)" --spec "$(spec)"
