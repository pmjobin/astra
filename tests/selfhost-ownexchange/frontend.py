#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh small-source Flow observations using an exact source-ledger consumer."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', required=True); p.add_argument('--name', required=True); p.add_argument('--negative', type=str, required=True); p.add_argument('--benign-methods', action='store_true'); a = p.parse_args()
	leaf = RUNTIME/a.name; leaf.mkdir(exist_ok=False); rows = []
	items = read(RUNTIME/'corpus-v1/selection.json')
	items += [dict(name=path.stem, sources=[dict(path=str(path), sha256=sha(path))], expected_rejection=True) for path in sorted((RUNTIME/a.negative).glob('*.astra'))]
	for row in items:
		if a.benign_methods and not row['name'].startswith('pending-'): continue
		sources = [source['path'] for source in row['sources']]
		if a.benign_methods and row['name'].startswith('pending-'):
			path = leaf/(row['name']+'.astra'); path.write_text(Path(sources[0]).read_text().replace('swap(this.data, this.other);', '')); sources = [str(path)]
		argv = [a.component, '--class-storage', *sources]; start = time.monotonic()
		with (leaf/(row['name']+'.stdout')).open('xb') as out, (leaf/(row['name']+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(row['name']+'.time'), *argv], cwd=ROOT, stdout=out, stderr=err, timeout=120)
		lines = (leaf/(row['name']+'.stdout')).read_text().splitlines(); diagnostics = [line for line in lines if line.startswith(('STATUS ', 'CHECKED_ERROR ', 'DIAGNOSTIC ', 'DEFER '))]
		rows.append(dict(name=row['name'], argv=argv, exit=r.returncode, start=start, end=time.monotonic(), diagnostics=diagnostics, sources=row['sources'], expected_rejection=row.get('expected_rejection',False), component_sha256=sha(a.component)))
		(leaf/'observations.json').write_text(json.dumps(rows, indent=2)+'\n'); print(row['name'],r.returncode,flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='OBSERVED', observations=rows, limitation='Source-ledger Flow observation only, not a Core/SSA/native qualification.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
