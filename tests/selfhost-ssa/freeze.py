#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze independent input identities and fresh predecessor/C0 observations."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from corpus import cases


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'predecessor', 'cfg', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	items = json.loads((a.predecessor/'cases.json').read_text())
	assert len(items) == 61
	items += json.loads((a.predecessor/'supplemental.json').read_text())
	assert len(items) == 62
	for item in cases():
		path = a.runtime/(item['name']+'.astra')
		path.write_text(item['source']+'\n')
		item.update(paths=[str(path)], sha256=sha(path), new=True)
		items.append(item)
	commands = []
	for item in items:
		for path in item['paths']:
			assert sha(path) == item['sha256']
		for mode in ('O0', 'O2'):
			exe = a.cfg/('astra-cfg-'+mode)
			identity = json.loads(exe.with_suffix('.identity.json').read_text())
			assert sha(exe) == identity['sha256']
			assert all(sha(path) == h for path, h in identity['identity']['sources'].items())
			for stage in ('--admit', '--core', '--cfg'):
				name = item['name']+'-'+mode+'-'+stage[2:]
				start = time.monotonic()
				r = subprocess.run([exe, stage, *item['paths']], capture_output=True)
				(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
				(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
				commands.append(dict(argv=[str(exe), stage, *item['paths']], exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
				(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
				if stage != '--admit':
					assert r.returncode == item['core_status'], (name, r.returncode, r.stderr)
		name = item['name']+'-C0-ssa'
		start = time.monotonic()
		r = subprocess.run([a.compiler, '--dump-ssa', *item['paths']], capture_output=True)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=[str(a.compiler), '--dump-ssa', *item['paths']], exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		if item['core_status'] == 0:
			assert r.returncode == 0, (name, r.stderr)
		print(item['name'], item['core_status'], flush=True)
	(a.runtime/'cases.json').write_text(json.dumps(items, indent=2)+'\n')
	(a.runtime/'tools.json').write_text(json.dumps({str(x): sha(x) for x in (a.compiler, a.cfg/'astra-cfg-O0', a.cfg/'astra-cfg-O2')}, indent=2)+'\n')


if __name__ == '__main__':
	main()
