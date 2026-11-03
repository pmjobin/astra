#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze or verify independent authored inputs; retain original corpus bytes."""
import argparse
import hashlib
import json
from pathlib import Path
from corpus import CASES, C_WITNESSES, TRACES

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--reuse', type=Path)
	p.add_argument('--legacy', type=Path, required=True)
	a = p.parse_args()
	assert not a.runtime.resolve().is_relative_to(ROOT)
	a.runtime.mkdir(parents=True, exist_ok=False)
	legacy = json.loads((a.legacy/'selection.json').read_text())
	assert len(legacy) == 24 and len({x['source_sha256'] for x in legacy}) == 24
	assert all(sha(x['source_path']) == x['source_sha256'] for x in legacy)
	old = {x['name']: x for x in json.loads((a.reuse/'selection.json').read_text())} if a.reuse else {}
	items = []
	for name, (family, text) in CASES.items():
		data = (text+'\n').encode()
		if a.reuse:
			item = old[name]
			source = Path(item['source_path'])
			assert source.read_bytes() == data and sha(source) == item['source_sha256']
		else:
			source = a.runtime/(name+'.astra'); source.write_bytes(data)
		if name in C_WITNESSES:
			companion = source.with_suffix('.c')
			if a.reuse:
				assert companion.read_text() == C_WITNESSES[name]
			else:
				companion.write_text(C_WITNESSES[name])
		items.append(dict(name=name, family=family, source_path=str(source), source_sha256=sha(source),
			expected_exit=0, expected_stdout='', expected_stderr='', expected_trace=TRACES.get(name, [])))
	source = ROOT/'tests/struct-copy/fixtures/struct-copy-nested.astra'
	assert sha(source) == '3a9a22bc6ffabfd498a05d54af9994b5719b8dd936b864be6c035004925a54f0'
	items.append(dict(name='existing-nested', family='memory', source_path=str(source), source_sha256=sha(source),
		expected_exit=0, expected_stdout='', expected_stderr='', expected_trace=[]))
	assert len(items) == 15 and len({x['source_sha256'] for x in [*legacy, *items]}) == 39
	(a.runtime/'selection.json').write_text(json.dumps(items, indent=2)+'\n')
	(a.runtime/'identity.json').write_text(json.dumps(dict(original_executions=24, additions=14,
		existing_nested=1, distinct_programs_per_profile=39, legacy_selection_sha256=sha(a.legacy/'selection.json'),
		corpus_source_sha256=sha(Path(__file__).with_name('corpus.py'))), indent=2)+'\n')
	print('Frozen 24 original + 14 new + unchanged existing-nested inputs')


if __name__ == '__main__':
	main()
