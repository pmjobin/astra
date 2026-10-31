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
export PM_CODEX_BUILD_DIR CCACHE_DISABLE=1
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
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-gen-forward-contracts
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs --logbase gen-own-2b-focused \
	gen-own-2b-contracts gen-own-2b-native-execution gen-own-2b-negative gen-own-2b-no-llvm
if [ "$scope" = regressions ]; then
	sh "$source_dir/tests/gen-own-2a/verify.sh" regressions
fi
