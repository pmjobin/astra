#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain exact compiler and recipe inputs for reproducible external builds."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	assert a.output.resolve().is_relative_to(ROOT.parent/'codex/work/astra/runtime/textclass17')
	a.output.mkdir(parents=True, exist_ok=False)
	paths = subprocess.check_output(['git', 'ls-files', '-z', 'compiler', 'lib/astra', 'lib/runtime/platform', 'tests'], cwd=ROOT).split(b'\0')
	identities = {}
	for raw in paths:
		if not raw: continue
		name = raw.decode(); source = ROOT/name
		if name.startswith('tests/') and not name.startswith('tests/selfhost-'): continue
		assert source.is_file() and not source.is_symlink()
		target = a.output/name; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
		identities[name] = hashlib.sha256(target.read_bytes()).hexdigest()
	a.output.with_suffix('.json').write_text(json.dumps(identities, indent=2)+'\n')
	print(len(identities), 'exact source and recipe inputs frozen')


if __name__ == '__main__':
	main()
