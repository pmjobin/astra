#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
export CCACHE_DISABLE=1
ulimit -c 0
source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build_root="${HOME}/Workspace/codex/work/astra/build"
mode=${1:-focused}
case "$mode" in focused | regressions) ;; *)
	echo 'Use focused or regressions' >&2
	exit 2
	;;
esac
if [ -f "$build_root/meson-private/coredata.dat" ]; then
	meson setup --reconfigure "$build_root" "$source_root" -Dwerror=true -Dlinux_async=false
else
	meson setup "$build_root" "$source_root" -Dwerror=true -Db_pch=false -Dbuildtype=debug -Dlinux_async=false
fi
meson compile -C "$build_root" -j 1 astrac astra-struct-move-contracts
meson test -C "$build_root" --no-rebuild --print-errorlogs -j 1 --logbase struct-move-1-focused \
	struct-move-1-stage-contracts struct-move-1-native-execution
if [ "$mode" = regressions ]; then
	meson compile -C "$build_root" -j 1 astra-own-field-parser astra-own-field-semantic astra-obj-alloc-loans astra-obj-field-contracts \
		astra-error-heap astra-error-snapshot astra-error-exceptions astra-lazy-contracts astra-async-frames astra-async-virtual
	meson test -C "$build_root" --no-rebuild --print-errorlogs -j 2 --logbase struct-move-1-regressions \
		struct-agg-native-execution struct-copy-native-execution struct-abi-native-execution gen-struct-native-execution \
		obj-alloc-1-loan-contracts obj-alloc-1-native-execution obj-field-2-stage-contracts obj-field-2-native-execution \
		obj-life-native-execution obj-own-native-execution obj-ret-native-execution own-field-parser own-field-semantic own-field-native-execution own-field-negative \
		error-1-heap error-1-snapshot error-1-exceptions error-1-native-execution param-borrow-negative param-borrow-equivalence-execution \
		prop-native-execution lazy-1-contracts lazy-1-native-execution async-1-native-frames async-1-source-frame-execution
fi
