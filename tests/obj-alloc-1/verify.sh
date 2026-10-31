#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Run directly from the real repository with an external build directory.
set -eu
# Keep transient compiler checks independent of the host ccache.
export CCACHE_DISABLE=1
: "${PM_CODEX_BUILD_DIR:?set the external managed build directory}"
source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mode=${1:-focused}
case "$mode" in focused | regressions) ;; *)
	echo 'Use focused or regressions' >&2
	exit 2
	;;
esac
if [ -f "$PM_CODEX_BUILD_DIR/meson-private/coredata.dat" ]; then
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_root"
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_root"
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-obj-alloc-loans
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs \
	--logbase obj-alloc-1-focused obj-alloc-1-loan-contracts obj-alloc-1-native-execution
if [ "$mode" = regressions ]; then
	meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 \
		astra-error-heap astra-error-snapshot astra-lazy-contracts \
		astra-async-frames astra-async-virtual
	meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs -j 2 \
		--logbase obj-alloc-1-regressions \
		error-1-heap error-1-snapshot error-1-native-execution \
		obj-life-native-execution obj-own-native-execution obj-ret-native-execution \
		own-field-native-execution param-borrow-negative param-borrow-equivalence-execution \
		prop-native-execution lazy-1-contracts lazy-1-native-execution \
		async-1-native-frames async-1-source-frame-execution
fi
