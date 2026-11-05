#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze explicit tracked source/build inputs without changing source routing."""
import argparse
import json
from pathlib import Path
import shutil
from state import ROOT, RUNTIME, git, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--name', required=True); a = p.parse_args()
	assert '/' not in a.name and a.name.startswith('source-v')
	output = RUNTIME/a.name; output.mkdir(exist_ok=False); identities = {}
	for name in git('ls-files', 'compiler', 'lib/astra', 'lib/runtime/platform', 'tests').splitlines():
		if name.startswith('tests/') and not name.startswith('tests/selfhost-'): continue
		path = ROOT/name; assert path.is_file() and not path.is_symlink()
		target = output/name; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, target); identities[name] = sha(path)
	output.with_suffix('.json').write_text(json.dumps(identities, indent=2)+'\n')
	print(output, len(identities), 'exact source/build inputs')


if __name__ == '__main__':
	main()
