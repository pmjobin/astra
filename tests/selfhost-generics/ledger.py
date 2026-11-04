#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound whole-compiler node observations, including unvisited nodes."""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
INITIAL = '5cd200f8210482835f1ff80182a59fb1532801ba'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--phase', choices=('before', 'after'), required=True)
	p.add_argument('--target-root', type=Path, help='Observe an exact retained source snapshot with the current consumer')
	p.add_argument('--implementation-root', type=Path, help='Compile an exact retained implementation snapshot for a before/after comparison')
	p.add_argument('--class-storage', action='store_true', help='Observe the explicitly authorized private Class-storage profile')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	spec = importlib.util.spec_from_file_location('typecore_build', ROOT/'tests/selfhost-typecore/build.py')
	base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
	root = ROOT
	if a.phase == 'before':
		root = a.runtime/'initial-source'
		paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', INITIAL, 'compiler', 'lib/astra', 'lib/runtime/platform', 'tests/selfhost-parser/controls.astra', 'tests/selfhost-parser/cursors.astra'], cwd=ROOT, text=True).splitlines()
		for path in paths:
			out = root/path; out.parent.mkdir(parents=True, exist_ok=True)
			out.write_bytes(subprocess.check_output(['git', 'show', INITIAL+':'+path], cwd=ROOT))
	base.ROOT = a.implementation_root.resolve() if a.implementation_root else root
	commands = []
	def capture(argv, name, details=None):
		if argv is None:
			(a.runtime/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True)
		if name.startswith(('ownflow-', *base.PROVIDERS)):
			assert r.returncode == 0, r.stderr.decode(errors='replace')[:3000]
		return r.stdout
	products = base.build(a.compiler.resolve(), a.build.resolve(), capture, ('O0',), with_flow=True, consumer=Path(__file__).with_suffix('.astra'), product_prefix='astra-ledger-', link_inputs=[Path(__file__), ROOT/'tests/selfhost-typecore/build.py'])
	(a.runtime/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	target_root = a.target_root.resolve() if a.target_root else root
	inputs = [*sorted((target_root/'compiler').rglob('*.astra')), *[target_root/f'lib/astra/{name}.astra' for name in base.LIBRARIES]]
	identities = {str(path): dict(relative=str(path.relative_to(target_root)), bytes=path.stat().st_size, sha256=sha(path)) for path in inputs}
	(a.runtime/'inputs.json').write_text(json.dumps(identities, indent=2)+'\n')
	profile = ['--class-storage'] if a.class_storage else []
	data = capture(['/usr/bin/time', '-v', a.build/'astra-ledger-O0', *profile, *inputs], 'whole-compiler')
	assert all(sha(path) == value['sha256'] for path, value in identities.items())
	decls, nodes, flow = {}, [], []
	for line in data.decode().splitlines():
		r = line.split()
		if not r: continue
		if r[0] == 'SOURCE':
			path = bytes.fromhex(r[1]).decode(); raw = bytes(map(int, r[2:]))
			identities[path] = dict(relative=path, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), synthetic_source_hex=raw.hex(), provenance='actual retained parser source backing')
		elif r[0] == 'DECL':
			path = bytes.fromhex(r[6]).decode()
			decls[int(r[1])] = dict(kind=int(r[2]), node=int(r[3]), owner=int(r[4]), name=bytes.fromhex(r[5]).decode(), path=path, start=int(r[7]), end=int(r[8]), source_sha256=identities[path]['sha256'])
		elif r[0] == 'NODE':
			path = bytes.fromhex(r[7]).decode()
			nodes.append(dict(node=int(r[1]), syntax_kind=int(r[2]), function_symbol=int(r[3]), type=int(r[4]), flags=int(r[5]), deferred=int(r[6]), path=path, start=int(r[8]), end=int(r[9]), source_sha256=identities[path]['sha256']))
		else:
			flow.append(line)
	assert nodes and len(nodes) == len({n['node'] for n in nodes})
	failed = any(x.startswith('CHECKED_ERROR ') for x in flow)
	reason_authority = target_root/'compiler/semantic/typecore-port.json'
	reasons = json.loads(reason_authority.read_text())['deferred_reasons']
	for row in nodes:
		row['function'] = decls.get(row['function_symbol'])
		row['deferred_reason'] = reasons.get(str(row['deferred']), 'specific syntax family '+str(row['syntax_kind']) if row['deferred'] >= 100 else None)
		row['disposition'] = ('TYPE_DEFERRED_'+str(row['deferred']) if row['deferred'] else 'TYPE_RECORDED_WITHOUT_WHOLE_PROGRAM_ADMISSION' if row['type'] else 'NO_CHECKED_USE_RECORDED')
		row['program_checked_error'] = failed
	files = []
	for path, identity in identities.items():
		selected = [n for n in nodes if n['path'] == path]
		files.append(dict(path=path, **identity, nodes=len(selected), dispositions=dict(Counter(n['disposition'] for n in selected))))
	diagnostics = []
	for line in flow:
		values = line.split()
		if values[0] == 'CHECKED_ERROR':
			diagnostics.append(dict(kind='CHECKED_ERROR', path=bytes.fromhex(values[1]).decode(), start=int(values[2]), end=int(values[3]), message=bytes.fromhex(values[4]).decode()))
		if values[0] == 'DEFER':
			diagnostics.append(dict(kind='DEFERRED', reason=values[1], code=int(values[2]), path=bytes.fromhex(values[3]).decode(), start=int(values[4]), end=int(values[5])))
	result = dict(format='astra-whole-source-ledger/1', phase=a.phase, initial_commit=INITIAL if a.phase == 'before' else None, component_sha256=sha(a.build/'astra-ledger-O0'), files=files, declarations=decls, nodes=nodes, raw_flow=flow, diagnostics=diagnostics, reason_authority=dict(path=str(reason_authority), sha256=sha(reason_authority), reasons=reasons), limitations='Zero typed use is not acceptance. It may name a structural syntax node or a node unvisited after the recorded first error. Deferred and typed observations do not imply Flow/IR/LLVM admission. Original and current whole compiler remain unqualified.')
	(a.runtime/'ledger.json').write_text(json.dumps(result, indent=2)+'\n')
	print(a.phase, len(files), 'files', len(nodes), 'original parsed nodes; full-source disposition preserved')


if __name__ == '__main__':
	main()
