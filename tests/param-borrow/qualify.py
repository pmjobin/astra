# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Current independent stage/layout checks and explicit memory comparisons."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import CASES, FIXTURES, ROOT, STAGES, run



def write(path, data):
	path.write_text(json.dumps(data, indent='\t')+'\n')




def audit(build, independent, out):
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'astrac.p/' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	comparisons = []
	for name in CASES:
		for prefix in ['param-borrow', 'explicit']:
			for stage in STAGES:
				args = ['--dump-'+stage, FIXTURES/(prefix+'-'+name+'.astra')] + ([] if stage == 'syntax' else ['--vapi', FIXTURES/'runtime.vapi'])
				data = run([independent/'astrac', *args]).encode()
				assert data == (build/'tests/param-borrow/execution'/(prefix+'-'+name+'.'+stage)).read_bytes(), (name, prefix, stage)
				comparisons.append(dict(name=prefix+'-'+name, stage=stage, sha256=hashlib.sha256(data).hexdigest()))
	write(out/'independent-determinism.json', comparisons)
	print(json.dumps(dict(scope='current independently built compiler comparison', comparisons=len(comparisons))), flush=True)


def memory(build, out):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	for stage in ['semantic', 'pipeline', 'llvm']:
		jobs.append(('test-'+stage, [build/f'tests/param-borrow/astra-param-borrow-{stage}', '--tap'], None))
	for name in CASES:
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			jobs.append(('dump-'+name+'-'+stage, [build/'astrac', '--dump-'+stage, FIXTURES/('param-borrow-'+name+'.astra'), '--vapi', FIXTURES/'runtime.vapi'], None))
		for prefix in ['param-borrow', 'explicit']:
			for mode in ['O0', 'O2']:
				jobs.append(('run-'+prefix+'-'+name+'-'+mode, [build/'tests/param-borrow/execution'/(prefix+'-'+name+'-'+mode)], ''.join(event+'\n' for event in CASES[name].split())))
	for mode in ['O0', 'O2']:
		jobs.append(('identity-'+mode, [build/'tests/param-borrow/execution'/('object-storage-identity-'+mode)], 'M8\n'))

	def measure(job):
		name, argv, expected = job
		path = logs/(name+'.log')
		p = subprocess.run(list(map(str, ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(path), *argv])), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(logs/(name+'.stdout')).write_text(p.stdout); (logs/(name+'.stderr')).write_text(p.stderr)
		text = path.read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, exit=p.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), output_matches=expected is None or expected == p.stdout)

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write(logs/'results.json', rows)
	assert all(row['exit'] == row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0 and row['output_matches'] for row in rows), [row for row in rows if row['exit'] or row['errors'] or not row['output_matches']]
	summary = dict(runs=len(rows), new_astra_errors=0, definite=0, indirect=0, possible=0)
	write(logs/'summary.json', summary)
	print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--independent-build', type=Path)
	parser.add_argument('--baseline-build', type=Path, default=ROOT/'build-infer-1-final')
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-param-borrow'; out.mkdir(exist_ok=True)
	if args.memory:
		memory(build, out)
	else:
		assert args.independent_build
		audit(build, args.independent_build.resolve(), out)
