#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze exact original SSA inputs and predeclared independent expectations."""
import argparse
import hashlib
import json
from pathlib import Path
from corpus import NUMERIC, SELECTION, TRACES


def sha(data):
	return hashlib.sha256(data).hexdigest()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--predecessor', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	old = json.loads((a.predecessor/'cases.json').read_text())
	assert len(old) == 80
	selected = []
	for category, names in SELECTION.items():
		for name in names:
			item = next(x for x in old if x['name'] == name)
			assert item['core_status'] == 0 and len(item['paths']) == 1
			assert sha(Path(item['paths'][0]).read_bytes()) == item['sha256']
			selected.append(dict(name=name, category=category, source_path=item['paths'][0], source_sha256=item['sha256'], expected_exit=255 if name == 'scalar-control' else 0, expected_stdout='', expected_stderr='', expected_trace=TRACES.get(name)))
	for name, text in NUMERIC.items():
		path = a.runtime/(name+'.astra'); path.write_text(text)
		selected.append(dict(name=name, category='numeric', source_path=str(path), source_sha256=sha(path.read_bytes()), expected_exit=0, expected_stdout='', expected_stderr='', expected_trace=None))
	assert len(selected) == len({x['source_sha256'] for x in selected}) == 24
	(a.runtime/'selection.json').write_text(json.dumps(selected, indent=2)+'\n')
	(a.runtime/'predecessor.json').write_text(json.dumps(old, indent=2)+'\n')
	print('frozen',len(selected),'unique execution cases and',len(old),'predecessor statuses')


if __name__ == '__main__':
	main()
