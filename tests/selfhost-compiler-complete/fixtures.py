#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Prepare byte-exact read-only inherited inputs; never count them as new runs."""
import argparse
import json
from pathlib import Path
import shutil

from run import WORK, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime-root', type=Path, required=True)
	a = p.parse_args()
	assert a.runtime_root.is_absolute() and a.runtime_root.resolve().is_relative_to((WORK/'runtime').resolve())
	assert a.runtime_root.is_dir()
	prior = WORK/'runtime/effects25-r5-resume'
	name = 'error-order-oracles-source1'
	oracle = json.loads((prior/name/'result.json').read_text())
	files = [name+'/'+leaf for leaf in ('result.json', 'provider.c', 'observe.c')]
	files += [name+'/'+row['name']+'.astra' for row in oracle['programs']]
	files += ['native-frontiers-errororacle2-'+mode+'/result.json' for mode in ('O0', 'O2')]
	rows = []
	for name in files:
		source, target = prior/name, a.runtime_root/name
		assert source.is_file() and not source.is_symlink()
		target.parent.mkdir(exist_ok=True)
		if target.exists():
			assert not target.is_symlink() and sha(target) == sha(source)
		else:
			shutil.copy2(source, target)
			target.chmod(0o444)
		assert target.stat().st_mode & 0o222 == 0
		rows.append(dict(original=str(source), original_sha256=sha(source), snapshot=str(target), snapshot_sha256=sha(target), bytes=target.stat().st_size, mode=oct(target.stat().st_mode & 0o777)))
	write(a.runtime_root/'reference-fixture-seed.json', dict(status='READ_ONLY_BYTE_EXACT_INPUTS', files=rows, limitation='Historical expected-value/input records only. All original files and references remain unchanged. Copied result records are not fresh execution receipts; provider/C0/Astra products and command logs must be generated separately in current task leaves. The first raw O2 campaign failed before these inputs were prepared; its failures remain failed.'))
	print(len(rows), 'read-only inherited input files prepared; zero new execution credit', flush=True)


if __name__ == '__main__':
	main()
