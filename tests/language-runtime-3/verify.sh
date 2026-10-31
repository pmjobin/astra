#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PM_CODEX_BUILD_DIR=${PM_CODEX_BUILD_DIR:-"$HOME/Workspace/codex/work/astra/build"}
export CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1
python3 - "$source_dir" "$PM_CODEX_BUILD_DIR" <<'PY'
from pathlib import Path
import json, sys
source, build = [Path(x).resolve() for x in sys.argv[1:]]
assert not build.is_relative_to(source)
if (build/'meson-info/meson-info.json').exists():
    assert Path(json.loads((build/'meson-info/meson-info.json').read_text())['directories']['source']).resolve() == source
    options = {x['name']:x['value'] for x in json.loads((build/'meson-info/intro-buildoptions.json').read_text())}
    assert {k:options[k] for k in ['buildtype','werror','b_pch','linux_async']} == dict(buildtype='debug',werror=True,b_pch=False,linux_async=False)
PY
if [ -f "$PM_CODEX_BUILD_DIR/meson-info/meson-info.json" ]; then
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_dir"
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_dir" -Dbuildtype=debug -Dwerror=true -Db_pch=false -Dlinux_async=false
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 4 astrac astra-dispatch-proof astra-cabi-record-proof astra-property-borrow-proof
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 2 --print-errorlogs --logbase language-runtime-3 \
	language-runtime-3-dispatch-proof cabi-record-proof property-borrow-proof \
	language-runtime-3-dispatch language-runtime-3-callable language-runtime-3-properties \
	language-runtime-3-cabi language-runtime-3-applications
