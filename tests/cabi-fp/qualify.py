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
from execute import ROOT, FIXTURES, CASES, STAGES, options, run

LEGACY = {'semantic', 'core', 'cfg'}




def write(path, value):
	path.write_text(json.dumps(value, indent='\t')+'\n')


def audit(build, out, independent):
	commands = json.loads((build/'compile_commands.json').read_text()); generated = [row for row in commands if row['file'].endswith('.c') and 'astrac.p/' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	execution = build/'tests/cabi-fp/execution'; native = json.loads((execution/'results.json').read_text()); deterministic = []
	assert independent is not None and (independent/'astrac').exists()
	for name in CASES:
		for stage in STAGES:
			data = run([independent/'astrac', '--dump-'+stage, FIXTURES/(name+'.astra'), *options(name)]).encode()
			assert data == (execution/(name+'.'+stage)).read_bytes(), (name, stage)
			deterministic.append(dict(fixture=name, stage=stage, sha256=hashlib.sha256(data).hexdigest()))
	write(out/'independent-determinism.json', deterministic)
	print(json.dumps(dict(scope='current independently built compiler comparison', comparisons=len(deterministic))), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True); jobs = []
	stages = {'cabi-fp-'+name for name in ['semantic', 'core-standalone', 'cfg-standalone', 'ssa-standalone', 'standalone', 'pipeline', 'llvm']} | {'cabi', 'cabi-standalone', 'vapi', 'vapi-frontend'}
	for root, prefix, names in [(build, '', stages | LEGACY), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env'])))
	for name in ['cabi-f32-import', 'cabi-f32-export', 'cabi-f64-import', 'cabi-f64-export', 'cabi-fp-vapi', 'cabi-fp-mixed', 'cabi-fp-struct-native', 'cabi-fp-chain']:
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'cabi']:
			jobs.append(('dump-'+name+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(FIXTURES/(name+'.astra')), *map(str, options(name))], str(ROOT), os.environ))
		for mode in ['O0', 'preserved-O2-fma']:
			jobs.append(('run-'+name+'-'+mode, [str(build/'tests/cabi-fp/execution'/(name+'-'+mode))], str(ROOT), os.environ))

	def measure(job):
		name, argv, cwd, env = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		r = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True); (logs/(name+'.stdout')).write_text(r.stdout); (logs/(name+'.stderr')).write_text(r.stderr)
		text = (logs/(name+'.log')).read_text(); assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text); return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, exit=r.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) from'), lost_records=losses(text))

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure, jobs))
	write(logs/'results.json', rows); by_name = {row['name']: row for row in rows}
	for row in rows:
		if row['name'].removeprefix('baseline-') in LEGACY:
			assert row['exit'] == 99 and row['errors'] == 1 and row['definite'] == 16384 and row['indirect'] == row['possible'] == row['suppressed'] == 0, row
			assert len(row['lost_records']) == 1 and 'g_malloc' in row['lost_records'][0] and 'call_init' in row['lost_records'][0], row
			if not row['name'].startswith('baseline-'):
				assert row['lost_records'] == by_name['baseline-'+row['name']]['lost_records'], row
		else:
			assert row['exit'] == row['errors'] == row['definite'] == row['indirect'] == row['possible'] == row['suppressed'] == 0, row
	summary = dict(current_runs=len(rows)-len(LEGACY), baseline_runs=len(LEGACY), matching_legacy_startup_losses=len(LEGACY), new_astra_errors=0, new_astra_lost_bytes=0)
	write(logs/'summary.json', summary); print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('--independent-build', type=Path); parser.add_argument('--baseline-build', type=Path); parser.add_argument('--memory', action='store_true'); args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-cabi-fp'; out.mkdir(exist_ok=True)
	if args.memory:
		assert args.baseline_build is not None
		memory(build, out, args.baseline_build.resolve())
	else:
		audit(build, out, args.independent_build.resolve() if args.independent_build else None)
