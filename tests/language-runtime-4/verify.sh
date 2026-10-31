#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PM_CODEX_BUILD_DIR=${PM_CODEX_BUILD_DIR:-"$HOME/Workspace/codex/work/astra/build"}
export PM_CODEX_BUILD_DIR CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1
# The retained recipe verifies source/build routing and debug/Werror/no-PCH.
sh "$source_dir/tests/language-runtime-3/verify.sh"
python3 - "$source_dir" "$PM_CODEX_BUILD_DIR" <<'PY'
from pathlib import Path
import json, sys
source, build = map(Path, sys.argv[1:])
matrix = json.loads((source/'tests/language-runtime-4/features.json').read_text())
registered = {entry['name'] for entry in json.loads((build/'meson-info/intro-tests.json').read_text())}
assert all(name in registered for cases in matrix['features'].values() for name in cases)
assert len(matrix['applications']) == 8
assert all((source/path).is_file() for path in matrix['applications'].values())
PY
meson compile -C "$PM_CODEX_BUILD_DIR" -j 4 astrac \
	astra-callable-value-proof astra-closure-value-proof astra-shared-lifetime-proof
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 2 \
	--print-errorlogs --logbase language-runtime-4 \
	language-runtime-4-callable-proof language-runtime-4-callable \
	language-runtime-4-closure-proof language-runtime-4-closure \
	shared-1b-contracts shared-1b-native shared-1b-applications \
	language-runtime-4-events language-runtime-4-report
python3 "$source_dir/tests/language-runtime-3/regressions.py" "$PM_CODEX_BUILD_DIR"
