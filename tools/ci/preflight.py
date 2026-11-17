#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Record actual runner identity and refuse missing native bootstrap contracts."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import sys

from common import ROOT, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--require-distribution', action='store_true')
	a = p.parse_args()
	seed = json.loads((ROOT/'tools/ci/seed-linux.json').read_text())
	blockers = []
	if platform.system() != 'Linux' or platform.machine().lower() not in ('x86_64', 'amd64'):
		blockers += ['No authenticated native Windows seed or Windows rebuild receipt', 'compiler/driver/arguments.c requires Linux x86-64 ELF init-array argument transport', 'compiler/backend/llvm/capi.c restricts the target machine to Linux', 'compiler/driver/doc-launch.c resolves /proc/self/exe; native Windows launcher/CRT/provider port required', 'No Windows installer or native install/run/uninstall evidence']
	if a.require_distribution and not seed['url']:
		blockers.append('Seed bytes are locally authenticated; no owner-authorized immutable distribution URL is configured')
	row = dict(status='BLOCKED' if blockers else 'PLATFORM_PROBE_ONLY', host=platform.platform(), system=platform.system(), machine=platform.machine(), python=sys.version, runner={key:os.environ.get(key) for key in ('ImageOS', 'ImageVersion', 'RUNNER_OS', 'RUNNER_ARCH', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA')}, tools={name:shutil.which(name) for name in ('cc', 'clang', 'llvm-config', 'cl', 'link', 'iscc', 'valgrind')}, disk_free_bytes=shutil.disk_usage(a.output.parent if a.output.parent.exists() else Path.cwd()).free, seed_manifest_sha256=sha(ROOT/'tools/ci/seed-linux.json'), blockers=blockers, hosted_execution=bool(os.environ.get('GITHUB_ACTIONS') == 'true'))
	write(a.output, row)
	print(json.dumps(row, indent=2))
	return 78 if blockers else 0


if __name__ == '__main__':
	sys.exit(main())
