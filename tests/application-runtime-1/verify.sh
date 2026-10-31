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
assert not build.is_relative_to(source) and not runtime.is_relative_to(source)
if (build / 'meson-info/meson-info.json').exists():
    info = json.loads((build / 'meson-info/meson-info.json').read_text())
    assert Path(info['directories']['source']).resolve() == source
    options = {o['name']: o['value'] for o in json.loads((build / 'meson-info/intro-buildoptions.json').read_text())}
    assert {k:options[k] for k in ['buildtype','werror','b_pch','linux_async']} == dict(buildtype='debug', werror=True, b_pch=False, linux_async=False)
PY
if [ -f "$PM_CODEX_BUILD_DIR/meson-info/meson-info.json" ]; then
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_dir"
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_dir" -Dbuildtype=debug -Dwerror=true -Db_pch=false -Dlinux_async=false
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-args-llvm astra-application-contracts
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 1 --print-errorlogs --logbase application-runtime-1 \
	application-runtime-1-contracts application-runtime-1-execution
if [ "$scope" = regressions ]; then
	sh "$source_dir/tests/text-own-1b/verify.sh" regressions
fi
