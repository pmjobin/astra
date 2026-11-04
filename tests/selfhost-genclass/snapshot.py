#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze explicit implementation inputs without mutating retained builds."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args(); output = a.output.resolve()
	assert output.is_relative_to(ROOT.parent/'codex/work/astra/runtime/genclass16')
	output.mkdir(parents=True, exist_ok=False)
	paths = subprocess.check_output(['git', 'ls-files', 'compiler', 'lib/astra', 'lib/runtime/platform', 'tests/selfhost-coreir', 'tests/selfhost-cfg', 'tests/selfhost-ssa', 'tests/selfhost-llvm', 'tests/selfhost-generics', 'tests/selfhost-classstorage', 'tests/selfhost-parser/controls.astra', 'tests/selfhost-parser/cursors.astra'], cwd=ROOT, text=True).splitlines()
	paths += [str(path.relative_to(ROOT)) for path in (ROOT/'tests/selfhost-genclass').glob('*') if path.is_file()]
	identities = {}
	for name in sorted(set(paths)):
		source = ROOT/name; assert source.is_file() and not source.is_symlink()
		target = output/name; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
		identities[name] = hashlib.sha256(target.read_bytes()).hexdigest()
	output.with_suffix('.json').write_text(json.dumps(identities, indent=2)+'\n')
	print(len(identities), 'explicit source inputs frozen at', output)


if __name__ == '__main__':
	main()
