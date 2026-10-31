# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit opt-in outcomes through staged and relocated installed compilers."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['types.astra', 'produce.astra', 'consume.astra', 'main.astra']
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']

def main(build, output):
	output.mkdir(parents=True, exist_ok=True)
	def run(argv):
		result = subprocess.run(list(map(str, argv)), cwd=output, capture_output=True, env={**os.environ, 'CCACHE_DISABLE':'1'})
		assert result.returncode == 0 and not result.stderr, (argv, result.returncode, result.stderr.decode())
		return result.stdout
	options = {row['name']:row['value'] for row in json.loads(run(['meson','introspect',build,'--buildoptions']))}
	stage = output / 'stage'; relocated = output / 'relocated'
	assert not stage.exists() and not relocated.exists(), 'reuse only the known completed install output after validation summary'
	run(['meson','install','-C',build,'--no-rebuild','--destdir',stage])
	prefix = stage / Path(options['prefix']).relative_to('/')
	def selected(option):
		path = Path(options[option]); return path.relative_to(options['prefix']) if path.is_absolute() else path
	canonical = {}; rows = []; binary_hash = None
	for route in ['staged','relocated']:
		if route == 'relocated':
			shutil.move(prefix, relocated); prefix = relocated
		compiler = prefix / selected('bindir') / 'astrac'; data = prefix / selected('datadir') / 'astra'
		assert compiler.read_bytes() == (build / 'astrac').read_bytes()
		for name in SOURCES:
			assert (data / 'examples/owning-enums' / name).read_bytes() == (ROOT / 'examples/owning-enums' / name).read_bytes()
			shutil.copyfile(data / 'examples/owning-enums' / name, output / name)
		outcomes = data / 'base/outcomes.astra'; assert outcomes.read_bytes() == (ROOT / 'lib/astra/base/outcomes.astra').read_bytes()
		shutil.copyfile(outcomes, output / 'outcomes.astra')
		for order in itertools.permutations(SOURCES):
			for stage_name in STAGES:
				payload = run([compiler,'--dump-'+stage_name,*order,'outcomes.astra']); digest = hashlib.sha256(payload).hexdigest()
				if stage_name not in canonical:
					canonical[stage_name] = digest
				assert canonical[stage_name] == digest, (route,order,stage_name)
			run([compiler,*order,'outcomes.astra','-o',output / 'consumer'])
			digest = hashlib.sha256((output / 'consumer').read_bytes()).hexdigest()
			if binary_hash is None:
				binary_hash = digest
			assert digest == binary_hash
			assert not run([output / 'consumer'])
			rows.append({'route':route,'order':order,'binary_sha256':digest})
	(output / 'checks.json').write_text(json.dumps({'source_orders':len(rows),'stage_comparisons':len(rows)*len(STAGES),'rows':rows,'canonical':canonical}, indent=2)+'\n')
	print('48 installed source orders and 432 identical stage comparisons')

if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
