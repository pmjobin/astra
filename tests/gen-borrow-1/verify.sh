#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
scope=${1:-focused}
case "$scope" in focused | regressions) ;; *)
	echo 'usage: verify.sh [focused|regressions]' >&2
	exit 2
	;;
esac
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PM_CODEX_BUILD_DIR=${PM_CODEX_BUILD_DIR:-"$HOME/Workspace/codex/work/astra/build"}
export CCACHE_DISABLE=1
case "$PM_CODEX_BUILD_DIR/" in "$source_dir/"*)
	echo 'build must be outside source' >&2
	exit 2
	;;
esac
if [ -f "$PM_CODEX_BUILD_DIR/meson-info/meson-info.json" ]; then
	python3 - "$PM_CODEX_BUILD_DIR/meson-info/meson-info.json" "$source_dir" <<'PY'
import json, pathlib, sys
info = json.loads(pathlib.Path(sys.argv[1]).read_text())
if pathlib.Path(info['directories']['source']).resolve() != pathlib.Path(sys.argv[2]).resolve():
    raise SystemExit('existing build belongs to another source checkout; revalidate routing first')
PY
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_dir"
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_dir" -Dwerror=true
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-gen-borrow-contracts
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs --logbase gen-borrow-1-focused \
	gen-borrow-1-contracts gen-borrow-1-native-execution gen-borrow-1-negative gen-borrow-1-no-llvm
if [ "$scope" = regressions ]; then
	meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 \
		astra-gen-own-semantic astra-gen-own-core astra-gen-own-monomorphizer \
		astra-gen-own-concrete-core astra-gen-own-cfg astra-gen-own-ssa astra-gen-own-nabi astra-gen-own-pipeline \
		astra-gen-semantic astra-gen-pipeline astra-gen-cap-semantic astra-gen-struct-semantic astra-gen-struct-pipeline \
		astra-cohort-semantic astra-gen-copy-pipeline astra-gen-slice-pipeline \
		astra-gen-buffer-semantic astra-gen-buffer-pipeline astra-gen-infer-semantic astra-gen-infer-pipeline \
		astra-resource-tests astra-obj-own-semantic astra-obj-own-pipeline astra-obj-life-pipeline \
		astra-obj-alloc-loans astra-struct-move-contracts astra-error-heap astra-lazy-contracts astra-async-frames
	# This existing qualification driver deliberately refuses an existing output
	# directory. Keep prior evidence and give this bounded replay fresh output.
	buffer_run=$(mktemp -d "$PM_CODEX_BUILD_DIR/tests/gen-borrow-1/buffer-replay.XXXXXX")
	python3 "$source_dir/tests/gen-buffer-1/negative.py" "$PM_CODEX_BUILD_DIR/astrac" "$buffer_run/negative"
	meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs --logbase gen-borrow-1-regressions \
		gen-own-semantic gen-own-core-standalone gen-own-monomorphizer-standalone gen-own-concrete-core-standalone \
		gen-own-cfg-standalone gen-own-ssa-standalone gen-own-nabi-standalone gen-own-pipeline gen-own-native-execution \
		gen-semantic gen-pipeline gen-cap-semantic gen-struct-semantic gen-struct-pipeline \
		gen-copy-semantic gen-copy-pipeline gen-slice-semantic gen-slice-pipeline gen-buffer-semantic gen-buffer-pipeline \
		gen-infer-semantic gen-infer-pipeline gen-infer-negative param-borrow-negative param-borrow-equivalence-execution \
		resources obj-own-semantic obj-own-pipeline obj-life-pipeline obj-alloc-1-loan-contracts obj-alloc-1-native-execution \
		struct-move-1-stage-contracts struct-move-1-native-execution error-1-heap error-1-native-execution \
		async-1-native-frames async-1-source-frame-execution lazy-1-contracts lazy-1-native-execution
fi
