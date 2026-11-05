#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute new source-bound programs, mutants, and the full inherited closure."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, read, sha


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--name', required=True); p.add_argument('--gate', choices=('new', 'mutations', 'inherited-native', 'inherited-text', 'inherited-indexpath', 'family', 'resource', 'mutations-local', 'twins', 'extras'), required=True); a = p.parse_args()
	assert a.name.replace('-', '').isalnum()
	leaf = RUNTIME/a.name; build = BUILD/a.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert identity['sha256'] == sha(a.component)
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	commands = []
	def run(argv, name, expected=0):
		start = time.monotonic(); environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('VALGRIND_OPTS', None)
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=ROOT, stdout=out, stderr=err, timeout=2400, env=environment)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == expected, str(leaf/(name+'.stderr'))
	selection = RUNTIME/'corpus-v1/selection.json'
	if a.gate in ('new', 'inherited-indexpath', 'family', 'twins', 'extras'):
		if a.gate == 'new': items = read(selection)
		elif a.gate == 'family': items = read(RUNTIME/'family-v3/selection.json')
		elif a.gate == 'twins': items = read(RUNTIME/'twins-v2/selection.json')
		elif a.gate == 'extras': items = read(RUNTIME/'extras-v1/selection.json')
		else:
			items = [item for name in ('frozen-v2', 'supplemental-v1', 'supplemental-growth-v1', 'operation-v1') for item in read(PRIOR/name/'selection.json') if item['name'] != 'original-CfgWalk']
		selection = leaf/'selection.json'; selection.write_text(json.dumps(items, indent=2)+'\n')
		assert len(items) == dict(new=14, family=6, twins=2, extras=2, **{'inherited-indexpath':15})[a.gate]
		run([sys.executable, '-B', ROOT/'tests/selfhost-classstorage/run.py', '--compiler', C0, '--compiler-sha256', sha(C0), '--component', a.component, '--mode', a.mode, '--selection', selection, '--build', build/'products', '--runtime', leaf/'observations'], 'native')
		rows = read(leaf/'observations/results.json'); assert len(rows) == len(items) and all(row['baseline_complete'] for row in rows)
		assert len({tuple(source['sha256'] for source in row['sources']) for row in rows}) == len(rows)
		for row in items:
			for stage in ('core', 'cfg'):
				run([a.component, '--classstorage-'+stage, a.mode, build/'unused', *[source['path'] for source in row['sources']]], row['name']+'-'+stage)
	elif a.gate == 'resource':
		row = next(row for row in read(PRIOR/'frozen-v2/selection.json') if row['name'] == 'original-CfgWalk'); sources = [source['path'] for source in row['sources']]
		for stage in ('core', 'cfg'): run([a.component, '--classstorage-'+stage, a.mode, build/'unused', *sources], 'complete-CfgWalk-'+stage)
		run([a.component, '--classstorage-ssa', a.mode, build/'unused', *sources], 'complete-CfgWalk-ssa', 2)
		assert b'native ABI SSA 2 2' in (leaf/'complete-CfgWalk-ssa.stderr').read_bytes()
	elif a.gate in ('mutations', 'mutations-local'):
		row = next(row for row in read(selection) if row['name'] == 'two-fields'); sources = [s['path'] for s in row['sources']]
		if a.gate == 'mutations-local':
			from corpus import BOX
			path = leaf/'local-mutations.astra'; path.write_text(BOX+'int main() { var box = new Box(); var a = new int[2]; var b = new int[3]; a[0] = 7; b[0] = 9; swap(a, b); if (a[0] != 9 || b[0] != 7) return 99; return 16; }\n'); sources = [path]
		output = build/'preserved.o'; native = build/'preserved-native'
		run([a.component, '--classstorage-emit-obj', a.mode, output, *sources], 'valid-object'); run(['gcc', output, '-o', native], 'valid-link'); run([native], 'valid-execute', row['expected_exit'])
		object_sha = sha(output); native_sha = sha(native)
		run([a.component, '--classstorage-ownexchange-mutations', a.mode, output, *sources], 'mutations')
		data = (leaf/'mutations.stdout').read_text(); assert data.count('OWNEXCHANGE_MODEL_MUTATION ') == 26 and data.count('OWNEXCHANGE_PHYSICAL_MUTATION ') == 11 and data.count(' LLVM_VALID ') == 11
		assert sha(output) == object_sha and sha(native) == native_sha
		(leaf/'mutations.json').write_text(json.dumps(dict(model=26, LLVM_valid_physical=11, total=37, object_sha256=object_sha, native_sha256=native_sha), indent=2)+'\n')
	else:
		group = 'predecessor-native-O2' if a.gate == 'inherited-native' else 'predecessor-text-O2'
		for row in read(PRIOR/'qualification-final'/group/'commands.json'):
			argv = row['argv'].copy(); name = row['name'].removesuffix('O2')+a.mode
			if '--reuse-mutations' in argv:
				at = argv.index('--reuse-mutations'); del argv[at:at+2]
			for flag, value in [('--mode', a.mode), ('--component', a.component), ('--build', build/name), ('--runtime', leaf/name)]: argv[argv.index(flag)+1] = str(value)
			run(argv, name); assert read(leaf/name/'result.json')['status'] == 'PASS'
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', gate=a.gate, mode=a.mode, component_sha256=sha(a.component), identity_sha256=sha(a.component.with_suffix('.identity.json')), recipe_sha256=sha(__file__), commands=commands, limitation='Only this named gate is established; historical proof results remain historical.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
