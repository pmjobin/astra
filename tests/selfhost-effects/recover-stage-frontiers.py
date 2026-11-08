#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run actual stage consumers on exact already-observed C0 runtime inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--observer', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--fixtures', type=Path, action='append', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	identity = read(a.observer.with_suffix('.identity.json'))
	assert sha(a.observer) == identity['sha256']
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('runtime_stage_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('runtime-stages-'+a.version)
	leaf.mkdir()
	commands, programs = [], []
	for fixtures in a.fixtures:
		witness = read(fixtures)
		for row in witness['programs']:
			assert all(sha(source['path']) == source['sha256'] for source in row['inputs'])
			name = str(len(programs))+'-'+row['name']
			argv = [a.observer]
			if not a.observer.name.startswith('astra-shared-stage-'):
				argv += ['--shared-stages']
			argv += [source['path'] for source in row['inputs']]
			argv = list(map(str, argv))
			start = time.monotonic()
			r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=paths.BUILD, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
			(leaf/(name+'.stdout')).write_bytes(r.stdout)
			(leaf/(name+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
			(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			assert r.returncode in (*range(8), 42, 132, -4), (name, r.returncode)
			boundary = None
			leaves = []
			lines = r.stdout.decode(errors='replace').splitlines()
			for i, line in enumerate(lines):
				if line.startswith('FLOW_LEAF '):
					operation, opcode, source_node, type_id = map(int, line.split()[1:])
					file_hex, first, last = lines[i+1].split()
					source = Path(bytes.fromhex(file_hex).decode())
					assert str(source) in {entry['path'] for entry in row['inputs']}
					first, last = int(first), int(last)
					data = source.read_bytes()
					assert 0 <= first <= last <= len(data)
					leaves.append(dict(stage='Flow consumer diagnostic', operation=operation, opcode=opcode, source_node=source_node, type_id=type_id, path=str(source), first=first, last=last, sha256=hashlib.sha256(data[first:last]).hexdigest()))
				if line.startswith('SHARED_FLOW '):
					status, node = map(int, line.split()[1:])
					if node > 0:
						file_hex, first, last = lines[i+1].split()
						source = Path(bytes.fromhex(file_hex).decode())
						assert str(source) in {entry['path'] for entry in row['inputs']}
						first, last = int(first), int(last)
						data = source.read_bytes()
						assert 0 <= first <= last <= len(data)
						boundary = dict(stage='Flow', status=status, node=node, path=str(source), first=first, last=last, sha256=hashlib.sha256(data[first:last]).hexdigest())
			valid = r.returncode == 42 and b'SHARED_SSA_VALID' in r.stdout
			programs.append(dict(name=row['name'], domain=row['domain'], fixture_receipt=str(fixtures), fixture_sha256=sha(fixtures), inputs=row['inputs'], exit=r.returncode, Flow_Core_CFG_SSA_valid=valid, source_boundary=boundary, verification_failure_leaves=leaves, semantic_markers=[line for line in lines if line.startswith('SEMANTIC ')], stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
			(leaf/'result.json').write_text(json.dumps(dict(status='ACTUAL_RUNTIME_SOURCE_STAGES', observer_sha256=sha(a.observer), observer_identity_sha256=sha(a.observer.with_suffix('.identity.json')), programs=programs, Astra_native_execution_credit=0, limitation='Actual source/Flow/Core/CFG/SSA consumers and mutation twins over the exact C0-observed source inputs. Full originals and exact reduced views remain separate. Crashes, stopped stages and unqualified owners remain explicit; no target LLVM/ELF or original-function execution credit.'), indent=2)+'\n')
			print(name, 'Flow/Core/CFG/SSA valid' if valid else 'stage stop '+str(r.returncode), flush=True)


if __name__ == '__main__':
	main()
