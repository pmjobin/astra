#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PM_CODEX_BUILD_DIR=${PM_CODEX_BUILD_DIR:-"$HOME/Workspace/codex/work/astra/build"}
export PM_CODEX_BUILD_DIR CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1
# This retained recipe validates routing and debug/Werror/no-PCH/linux_async=false,
# builds the source-refreshed compiler, and runs the named 75-test selection.
sh "$source_dir/tests/language-runtime-4/verify.sh"
meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$source_dir"
meson compile -C "$PM_CODEX_BUILD_DIR" -j 4 astrac \
	astra-retained-proof astra-checked-closure-proof astra-record-proof astra-payload-proof
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 2 \
	--print-errorlogs --logbase interop-async-5 \
	interop-async-5-retained-proof interop-async-5-retained \
	interop-async-5-checked-proof interop-async-5-checked \
	interop-async-5-record-proof interop-async-5-record \
	interop-async-5-payload-proof interop-async-5-payload interop-async-5-importer
python3 "$source_dir/tests/interop-async-5/timer-check.py" \
	"$PM_CODEX_BUILD_DIR/astrac" \
	"$PM_CODEX_BUILD_DIR/tests/interop-async-5/timer"
# Linux execution tests require an existing matching private liburing >=2.15.
# Override ASTRA_LIBURING_PREFIX for a different existing prefix. Exit 77 is an
# environment skip, never evidence for I2/A37--A40 PASS.
