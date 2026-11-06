#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the observer on byte-exact cohorts and retain the producer chain."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import bounded_run, ROOT, RUNTIME, PRIOR, COHORTS, INPUT, C0, sha, read


def parse(path):
	tables = {}
	for line in path.read_text().splitlines():
		row = line.split()
		if row: tables.setdefault(row[0], []).append(row[1:])
	return tables


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--full-cli', action='store_true'); p.add_argument('--mode', choices=('O0', 'O2'), default='O0'); a = p.parse_args()
	leaf = RUNTIME/('trace-'+a.version); leaf.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	for path, expected in identity['identity']['sources'].items():
		source = Path(path)
		if source.is_relative_to(ROOT) and source.suffix in ('.astra', '.py'):
			target = leaf/'implementation'/source.relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(source.read_bytes()); assert sha(target) == expected
	results = {}
	for name in COHORTS:
		old = read(INPUT/'reference/report/GENREF24-NEXT-BLOCKER-O0.json')['cohorts'][name]
		inputs = read(PRIOR/'cohorts-v3-O0.json')[name]['independent_consumer']['argv'][6:]
		prefix = ['--effects-trace', a.mode, str(leaf/'unused')] if a.full_cli else []
		argv = [str(a.component), *prefix, *inputs]; start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
		assert r.returncode == 0, (leaf/(name+'.stderr')).read_text()[-3000:]
		tables = parse(leaf/(name+'.stdout'))
		local_id = old['argument']['binding_target']; argument_id = old['argument']['node']
		local = next(row for row in tables['LOCAL'] if int(row[0]) == local_id)
		producer = next(row for row in tables['PRODUCER'] if int(row[0]) == local_id)
		# INITIALIZER and LOCAL_USE are adjacent in the lossless stream; bind by
		# byte span within the exact local declaration rather than name guessing.
		local_use = next(row for row in tables['LOCAL_USE'] if int(row[0]) == int(local[1]))
		initializers = [row for row in tables['INITIALIZER'] if row[4] == local_use[4] and int(local_use[5]) <= int(row[5]) and int(row[6]) <= int(local_use[6])]
		assert len(initializers) == 1
		initializer = initializers[0]
		declaration = next(row for row in tables['DECLARATION'] if row[0] == producer[1])
		signature = next(row for row in tables['SIGNATURE'] if row[0] == producer[1])
		types = {int(row[0]): list(map(int, row[1:])) for row in tables['TYPE']}
		callable_type = types[int(signature[2])]; success_type, success_flags = callable_type[3:5]
		move = next(row for row in tables['MOVE'] if int(row[0]) == argument_id)
		assert int(next(row for row in tables['MOVE_TARGET'] if int(row[0]) == argument_id)[1]) == local_id
		source = Path(old['source']); data = source.read_bytes(); assert sha(source) == old['source_sha256']
		assert data[old['span'][0]:old['span'][1]] == b'index.graphs.append(move graph)'
		assert data[int(initializer[5]):int(initializer[6])].startswith(b'flow_graph(')
		assert callable_type[0] == 25 and success_type > 0 and success_flags & 4 and int(signature[4]) & 64
		assert types[success_type][0] == 31 and int(signature[3]) > 0
		results[name] = dict(component_sha256=sha(a.component), seconds=time.monotonic()-start, source=str(source), source_sha256=sha(source), consumer=tables['CONSUMER'], local=list(local), local_use=list(local_use), initializer=list(initializer), initializer_bytes=data[int(initializer[5]):int(initializer[6])].decode(), producer=list(producer), declaration=list(declaration), signature=list(signature), success_type=success_type, success_flags=success_flags, success_nominal=types[success_type], error_type=types[int(signature[3])], move=list(move), predecessor_append_evidence=old, pending='No initialized/moved state is proved while effect admission and obligation 19 remain outstanding.', Flow_status=tables.get('STATUS'), Flow_verifier_stops=tables.get('FLOW_VERIFY_STOP'), source_signatures=tables.get('SOURCE_SIGNATURE'), stdout_sha256=sha(leaf/(name+'.stdout')))
		(leaf/'result.json').write_text(json.dumps(results, indent=2)+'\n')
		print(name, 'signature success', success_type, success_flags, 'local', local[5], 'initializer', initializer[1:4], 'move', move[1:4], flush=True)


if __name__ == '__main__':
	main()
