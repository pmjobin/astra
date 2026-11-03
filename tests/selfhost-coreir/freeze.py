#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh maintained-test reference; campaign intake freezes remain immutable."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
from corpus import additional

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('semadmit_corpus', ROOT/'tests/selfhost-semadmit/corpus.py')
semadmit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(semadmit)


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'admission', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	assert not a.runtime.resolve().is_relative_to(ROOT)
	a.runtime.mkdir(parents=True, exist_ok=False)
	commands = []
	def run(argv, leaf, name):
		t = time.monotonic()
		r = subprocess.run(list(map(str, argv)), capture_output=True)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-t))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		return r
	for group, cases in [('frozen', semadmit.cases()), ('additional-frozen', additional())]:
		directory = a.runtime/group
		directory.mkdir()
		items = []
		for entry in cases:
			item = dict(entry)
			leaf = directory/item['name']
			leaf.mkdir()
			path = Path(item.get('original_path', leaf/'input.astra'))
			if 'original_path' not in item: path.write_text(item['source']+'\n')
			item['paths'] = [str(path)]
			item['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
			run([a.compiler, '--check', path], leaf, '--check')
			core = run([a.compiler, '--dump-core', path], leaf, 'core')
			admission = run([a.admission, '--admit', path], leaf, 'admission')
			assert admission.returncode in (0, 1, 3), (item['name'], admission.returncode)
			item['core_status'] = 4 if admission.returncode == 1 else admission.returncode
			if item['core_status'] == 0: assert core.returncode == 0
			if group == 'additional-frozen': assert item['status'] == item['core_status']
			items.append(item)
		(directory/'frozen.json').write_text(json.dumps(items, indent=2)+'\n')
	(a.runtime/'tools.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (a.compiler, a.admission)}, indent=2)+'\n')


if __name__ == '__main__':
	main()
