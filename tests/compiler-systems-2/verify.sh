#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PM_CODEX_BUILD_DIR=${PM_CODEX_BUILD_DIR:-"$HOME/Workspace/codex/work/astra/build"}
PM_CODEX_RUNTIME_DIR=${PM_CODEX_RUNTIME_DIR:-"$HOME/Workspace/codex/work/astra/runtime/native-current"}
export PM_CODEX_BUILD_DIR PM_CODEX_RUNTIME_DIR CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1
python3 - "$source_dir" "$PM_CODEX_BUILD_DIR" "$PM_CODEX_RUNTIME_DIR" <<'PY'
from pathlib import Path
import json, sys
source, build, runtime = [Path(x).resolve() for x in sys.argv[1:]]
assert not build.is_relative_to(source) and not runtime.is_relative_to(source)
info = build/'meson-info'
if info.exists():
    assert Path(json.loads((info/'meson-info.json').read_text())['directories']['source']).resolve() == source
    options = {x['name']:x['value'] for x in json.loads((info/'intro-buildoptions.json').read_text())}
    assert {k:options[k] for k in ['buildtype','werror','b_pch','linux_async']} == dict(buildtype='debug',werror=True,b_pch=False,linux_async=False)
PY
if [ -f "$PM_CODEX_BUILD_DIR/meson-info/meson-info.json" ]; then
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_dir"
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_dir" -Dbuildtype=debug -Dwerror=true -Db_pch=false -Dlinux_async=false
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-args-llvm \
	astra-public-optimizer-contracts astra-wide-values astra-wide-values-ubsan \
	astra-wide-verifier astra-wide-llvm \
	astra-cabi-buffer-standalone astra-cabi-buffer-pipeline astra-cabi-buffer-provider
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 1 --print-errorlogs --logbase compiler-systems-2 \
	wide-values wide-values-ubsan wide-ssa-verifier wide-llvm-verifier wide-public-execution \
	cabi-buffer-standalone cabi-buffer-pipeline cabi-buffer-provider cabi-buffer-qualification \
	modules-1-scopes-execution compiler-systems-2-optimizer-contracts \
	compiler-systems-2-applications compiler-systems-2-predecessor-public-O2
