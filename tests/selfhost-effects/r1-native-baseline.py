#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh native replay of the pinned predecessor, separate from R1 qualification."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
from state import ROOT, bounded_run, sha, read, load_module

BASE = load_module('r1_baseline_state', ROOT/'tests/selfhost-effects/r1-state.py').BASE

BASE_PATH = ROOT.parent/'codex/work/astra'
PRIOR = BASE_PATH/'runtime/effects25'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	leaf = BASE_PATH/'runtime/effects25-r1'/('native-baseline-'+a.mode); leaf.mkdir(exist_ok=False)
	build = BASE_PATH/'build/effects25-r1'/('native-baseline-'+a.mode); build.mkdir(parents=True, exist_ok=False)
	old = read(PRIOR/('inherited-v1-'+a.mode)/'result.json'); assert len(old['programs']) == 202
	commands = read(PRIOR/('inherited-v1-'+a.mode)/'commands.json'); index = {}
	for command in commands:
		for word in command['argv']: index.setdefault(word, []).append(command)
	component = commands[0]['argv'][0]
	identity = read(Path(component).with_suffix('.identity.json')); assert sha(component) == identity['sha256']
	for group in ('sources', 'tools'):
		for path, expected in identity['identity'][group].items():
			if sha(path) == expected: continue
			assert group == 'sources' and Path(path).is_relative_to(ROOT)
			data = __import__('subprocess').check_output(['git', 'show', BASE+':'+str(Path(path).relative_to(ROOT))], cwd=ROOT)
			assert hashlib.sha256(data).hexdigest() == expected
	fresh_commands = []; rows = []; env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	def run(argv, name):
		start = time.monotonic(); label = str(len(fresh_commands))+'-'+name
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=env, timeout=180)
		out = leaf/(label+'.stdout'); err = leaf/(label+'.stderr'); out.write_bytes(r.stdout); err.write_bytes(r.stderr)
		fresh_commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(out), stderr_sha256=sha(err)))
		(leaf/'commands.json').write_text(json.dumps(fresh_commands, indent=2)+'\n'); return r
	for ordinal, row in enumerate(old['programs']):
		products = row.get('fresh_products', row.get('products'))
		assert all(sha(p['path']) == p['sha256'] for p in row['sources'])
		assert all(sha(p['path']) == p['sha256'] for p in products.values())
		raw = products['raw']; argv = next(c['argv'].copy() for c in index[raw['path']] if any(w.endswith('llvm-raw') for w in c['argv']))
		path = build/(str(ordinal)+'.raw.ll'); argv[argv.index(raw['path'])] = str(path)
		assert run(argv, 'emit').returncode == 0 and sha(path) == raw['sha256']
		assert run(['llvm-as', path, '-o', build/(str(ordinal)+'.bc')], 'assemble').returncode == 0
		assert run(['opt', '-passes=verify', '-disable-output', path], 'verify').returncode == 0
		obj = build/(str(ordinal)+'.o'); elf = build/str(ordinal)
		object_argv = [w.replace('llvm-raw', 'emit-obj') if w.endswith('llvm-raw') else str(obj) if w == str(path) else w for w in argv]
		assert run(object_argv, 'object').returncode == 0
		old_elf = products.get('native', products.get('executable'))
		link = next(c['argv'] for c in index[old_elf['path']] if '-o' in c['argv'] and c['argv'][c['argv'].index('-o')+1] == old_elf['path'] and products['object']['path'] in c['argv'])
		link = [str(obj) if w == products['object']['path'] else str(elf) if w == old_elf['path'] else w for w in link]
		assert run(link, 'link').returncode == 0
		control = next(c for c in index[old_elf['path']] if c['argv'] == [old_elf['path']])
		r = run([elf], 'execute')
		assert r.returncode == control['exit'] and hashlib.sha256(r.stdout).hexdigest() == control['stdout_sha256'] and hashlib.sha256(r.stderr).hexdigest() == control['stderr_sha256']
		assert elf.read_bytes().startswith(b'\x7fELF')
		rows.append(dict(name=row['name'], sources=row['sources'], IR_identical=True, exit=r.returncode, products={k: dict(path=str(v), sha256=sha(v)) for k, v in [('raw', path), ('object', obj), ('native', elf)]}))
		(leaf/'programs.json').write_text(json.dumps(rows, indent=2)+'\n')
		if ordinal % 20 == 0: print(a.mode, ordinal+1, 'fresh predecessor source/LLVM/ELF replay', flush=True)
	assert len({tuple(s['sha256'] for s in r['sources']) for r in rows}) == 202
	result = dict(status='PREDECESSOR_BASELINE_REPRODUCED', revision=BASE, mode=a.mode, component_sha256=sha(component), programs=rows, native_source_identities=202, distinct_ELF_hashes=len({r['products']['native']['sha256'] for r in rows}), limitation='Pinned predecessor compiler; this baseline does not qualify the changed R1 compiler or any new recoverable effect emitter')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(a.mode, 202, 'source identities', result['distinct_ELF_hashes'], 'ELF hashes', flush=True)


if __name__ == '__main__':
	main()
