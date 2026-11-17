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


def qualification_inputs(work):
	"""Refuse before costly builds when independent oracle inputs are absent."""
	blockers = []
	c0 = work/'build/selfhost27b/c0-recovery-safealloc2/astrac'
	if not c0.is_file() or c0.is_symlink() or sha(c0) != '19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6':
		blockers.append('Independent qualification requires the authenticated rebuilt C0 oracle and its compatible runtime; the 27-D seed does not replace that oracle')
	oracle = work/'runtime/selfhost27c-dev20/inputs.json'
	if not oracle.is_file() or oracle.is_symlink():
		blockers.append('Independent qualification requires the immutable Git-checked 27-C oracle source closure; hosted acquisition/portable routing is not yet implemented')
	else:
		try:
			row = json.loads(oracle.read_text())
			valid = row['format'] == 'astra-current-inputs/1' and row['revision'] == '20cb5de631b0ea583a1e0516d2603d9e5f77cc0c'
			valid = valid and bool(row['inputs']) and all(Path(path).is_file() and not Path(path).is_symlink() and Path(path).resolve().is_relative_to((work/'runtime').resolve()) and sha(path) == digest for path, digest in row['inputs'].items())
			if not valid:
				blockers.append('Independent qualification oracle source closure is missing, modified or routed outside the selected work root')
		except (OSError, ValueError, KeyError, TypeError):
			blockers.append('Independent qualification oracle source manifest is invalid')
	return blockers


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--require-distribution', action='store_true')
	p.add_argument('--require-qualification-inputs', action='store_true')
	a = p.parse_args()
	seed = json.loads((ROOT/'tools/ci/seed-linux.json').read_text())
	blockers = []
	if platform.system() != 'Linux' or platform.machine().lower() not in ('x86_64', 'amd64'):
		blockers += ['No authenticated native Windows seed or Windows rebuild receipt', 'compiler/driver/arguments.c requires Linux x86-64 ELF init-array argument transport', 'compiler/backend/llvm/capi.c restricts the target machine to Linux', 'compiler/driver/doc-launch.c resolves /proc/self/exe; native Windows launcher/CRT/provider port required', 'No Windows installer or native install/run/uninstall evidence']
	if a.require_distribution and not seed['url']:
		blockers.append('Seed bytes are locally authenticated; no owner-authorized immutable distribution URL is configured')
	if a.require_qualification_inputs:
		blockers.extend(qualification_inputs(ROOT.parent/'codex/work/astra'))
	row = dict(status='BLOCKED' if blockers else 'PLATFORM_PROBE_ONLY', host=platform.platform(), system=platform.system(), machine=platform.machine(), python=sys.version, runner={key:os.environ.get(key) for key in ('ImageOS', 'ImageVersion', 'RUNNER_OS', 'RUNNER_ARCH', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA')}, tools={name:shutil.which(name) for name in ('cc', 'clang', 'llvm-config', 'cl', 'link', 'iscc', 'valgrind')}, disk_free_bytes=shutil.disk_usage(a.output.parent if a.output.parent.exists() else Path.cwd()).free, seed_manifest_sha256=sha(ROOT/'tools/ci/seed-linux.json'), blockers=blockers, hosted_execution=bool(os.environ.get('GITHUB_ACTIONS') == 'true'))
	write(a.output, row)
	print(json.dumps(row, indent=2))
	return 78 if blockers else 0


if __name__ == '__main__':
	sys.exit(main())
