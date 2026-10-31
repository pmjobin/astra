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
	python3 - "$PM_CODEX_BUILD_DIR/meson-info" "$source_dir" <<'PY'
from pathlib import Path
import json, sys
p = Path(sys.argv[1])
assert Path(json.loads((p/'meson-info.json').read_text())['directories']['source']).resolve() == Path(sys.argv[2]).resolve(), 'revalidate build source routing'
options = {x['name']: x['value'] for x in json.loads((p/'intro-buildoptions.json').read_text()) if x['name'] in ['buildtype', 'werror', 'b_pch', 'linux_async']}
assert options == dict(buildtype='debug', werror=True, b_pch=False, linux_async=False), options
PY
	meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_dir"
else
	meson setup "$PM_CODEX_BUILD_DIR" "$source_dir" -Dbuildtype=debug -Dwerror=true -Db_pch=false -Dlinux_async=false
fi
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-args-llvm
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 1 --print-errorlogs --logbase app-diag-collection-0 app-diag-collection-0
if [ "$scope" = regressions ]; then
	meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astra-gen-local-contracts astra-gen-borrow-contracts astra-gen-buffer-pipeline astra-gen-slice-pipeline astra-obj-own-pipeline astra-text-semantic astra-error-snapshot astra-error-heap
	meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 2 --print-errorlogs --logbase app-diag-baseline \
		gen-own-2d-contracts gen-own-2d-native-execution gen-borrow-1-contracts gen-buffer-pipeline gen-slice-pipeline obj-own-pipeline text-semantic error-1-snapshot error-1-heap
fi
