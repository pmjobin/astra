#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Run directly from the coordinator repository with external outputs.
set -eu
export CCACHE_DISABLE=1
ulimit -c 0
: "${PM_CODEX_BUILD_DIR:?set the external managed build directory}"
source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PM_CODEX_BUILD_DIR=$(realpath -m -- "$PM_CODEX_BUILD_DIR")
case "$PM_CODEX_BUILD_DIR" in "$source_root" | "$source_root"/*)
	echo 'Build output must be outside the source tree' >&2
	exit 2
	;;
esac
mode=${1:-focused}
case "$mode" in focused | regressions) ;; *)
	echo 'Use focused or regressions' >&2
	exit 2
	;;
esac
if [ -f "$PM_CODEX_BUILD_DIR/meson-private/coredata.dat" ]; then
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_root" -Dwerror=true -Dlinux_async=false
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_root" -Dwerror=true -Db_pch=false -Dbuildtype=debug -Dlinux_async=false
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-obj-field-contracts astra-async-virtual
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs -j 1 --logbase obj-field-2-focused \
	obj-field-2-stage-contracts obj-field-2-native-execution
if [ "$mode" = regressions ]; then
	meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astra-obj-alloc-loans \
		astra-error-heap astra-error-snapshot astra-lazy-contracts astra-async-frames astra-async-virtual
	meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs -j 2 --logbase obj-field-2-regressions \
		obj-alloc-1-loan-contracts obj-alloc-1-native-execution \
		obj-life-native-execution obj-own-native-execution obj-ret-native-execution own-field-native-execution own-field-negative \
		error-1-heap error-1-snapshot error-1-native-execution param-borrow-negative \
		param-borrow-equivalence-execution prop-native-execution lazy-1-contracts lazy-1-native-execution \
		async-1-native-frames async-1-source-frame-execution
fi
