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
PM_CODEX_RUNTIME_DIR=${PM_CODEX_RUNTIME_DIR:-"$HOME/Workspace/codex/work/astra/runtime"}
export PM_CODEX_BUILD_DIR PM_CODEX_RUNTIME_DIR CCACHE_DISABLE=1
python3 - "$PM_CODEX_BUILD_DIR" "$PM_CODEX_RUNTIME_DIR" "$source_dir" <<'PY'
from pathlib import Path
import json, sys
build, runtime, source = [Path(p).resolve() for p in sys.argv[1:]]
assert not build.is_relative_to(source) and not runtime.is_relative_to(source), 'outputs must be external'
info = build / 'meson-info'
if info.exists():
    assert Path(json.loads((info / 'meson-info.json').read_text())['directories']['source']).resolve() == source, 'revalidate build routing'
    opts = {r['name']: r['value'] for r in json.loads((info / 'intro-buildoptions.json').read_text())}
    assert {k: opts[k] for k in ['buildtype', 'werror', 'b_pch', 'linux_async']} == dict(buildtype='debug', werror=True, b_pch=False, linux_async=False)
PY
if [ -f "$PM_CODEX_BUILD_DIR/meson-info/meson-info.json" ]; then
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_dir"
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_dir" -Dbuildtype=debug -Dwerror=true -Db_pch=false -Dlinux_async=false
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-args-llvm astra-byte-builder-contracts
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 1 --print-errorlogs --logbase text-own-1b-focused \
	text-own-1b-contracts text-own-1b-native-execution text-own-1b-source-refusals
if [ "$scope" = regressions ]; then
	sh "$source_dir/tests/gen-member-1a/verify.sh" regressions
	meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astra-own-swap-core astra-own-swap-cfg astra-own-swap-ssa astra-own-swap-llvm
	meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 1 --print-errorlogs --logbase text-own-1b-swap \
		own-swap-core own-swap-cfg own-swap-ssa own-swap-llvm own-swap-source
fi
