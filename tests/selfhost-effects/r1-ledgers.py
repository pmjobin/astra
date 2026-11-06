#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh complete node/kind/source/span ledgers against the frozen predecessor."""
import argparse
import json
from pathlib import Path
import time
from state import ROOT, read, sha, bounded_run, population, digest

BASE = ROOT.parent/'codex/work/astra'
RUNTIME = BASE/'runtime/effects25-r1'
BUILD = BASE/'build/effects25-r1'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path); a = p.parse_args()
	component = a.component or BUILD/('compiler-v1-'+a.mode)/('astra-llvm-'+a.mode)
	identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
	assert all(sha(p) == h for group in ('sources', 'tools') for p, h in identity['identity'][group].items())
	results = {}
	for name, reference in read(BASE/'runtime/genref24'/('cohorts-v3-'+a.mode+'.json')).items():
		leaf = RUNTIME/('ledger-v1-'+a.mode+'-'+name); directory = BUILD/leaf.name
		argv = reference['collector']['argv'].copy()
		for flag, value in [('--component', component), ('--build', directory), ('--runtime', leaf)]: argv[argv.index(flag)+1] = str(value)
		start = time.monotonic()
		r = bounded_run(argv, cwd=ROOT, capture_output=True, timeout=300)
		assert leaf.is_dir()
		(leaf/'collector.stdout').write_bytes(r.stdout); (leaf/'collector.stderr').write_bytes(r.stderr)
		assert r.returncode == 0, r.stderr[-2500:]
		old = read(BASE/'runtime/effects25'/('ledger-v1-'+a.mode+'-'+name)/'ledger.json')
		new = read(leaf/'ledger.json'); actual = population(new); expected = population(old)
		assert actual == expected and new['component_sha256'] == sha(component)
		rows = {row['node']:row for row in new['nodes']}
		trace = read(BASE/'runtime/effects25'/('trace-full-v1-'+a.mode)/'result.json')[name]
		for key, deferred in [('local_use', 17), ('initializer', 17), ('move', 19)]:
			row = rows[int(trace[key][0])]
			assert (row['type'], row['flags'], row['deferred']) == (int(trace[key][1]), 4, deferred)
		results[name] = dict(argv=argv, exit=r.returncode, seconds=time.monotonic()-start, files=len(new['files']), nodes=len(new['nodes']), population_sha256=digest(actual[0]), node_identity_sha256=digest(actual[1]), ledger_sha256=sha(leaf/'ledger.json'), component_sha256=sha(component), classification='Every original parsed source/kind/node/span identity freshly compared; typed observations remain distinct from ownership/native admission')
		(RUNTIME/('ledgers-v1-'+a.mode+'.json')).write_text(json.dumps(results, indent=2)+'\n')
		print(a.mode, name, len(new['nodes']), 'fresh complete node identity matched', flush=True)
		del old, new, actual, expected, rows


if __name__ == '__main__':
	main()
