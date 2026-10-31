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
from execute import ROOT, FIXTURES, CASES, STAGES, run

LEGACY = {'semantic', 'core', 'cfg'}




def write(path, value):
	path.write_text(json.dumps(value, indent='\t')+'\n')


def audit(build, out, independent):
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'astrac.p/' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	assert independent is not None and (independent/'astrac').exists()
	execution = build/'tests/gen-own/execution'; native = json.loads((execution/'results.json').read_text())
	deterministic = []
	for name in [*CASES, 'unused']:
		source = execution/'unused.astra' if name == 'unused' else FIXTURES/f'gen-own-{name}.astra'
		for stage in STAGES:
			options = [] if name == 'unused' or stage == 'syntax' else ['--vapi', FIXTURES/'ownership.vapi']
			data = run([independent/'astrac', '--dump-'+stage, source, *options]).encode()
			assert data == (execution/(name+'.'+stage)).read_bytes(), (name, stage)
			deterministic.append(dict(fixture=name, stage=stage, sha256=hashlib.sha256(data).hexdigest()))
	for stage in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
			if stage in ['cfg', 'ssa', 'nabi']:
				assert not re.search(r'GenericOwnership|TypeParameterType|CoreGeneric', code), path
			if stage == 'core' and path.name != 'builder.vala':
				assert not re.search(r'SemanticAnalyzer|CheckedGeneric|Astra\.Syntax', code), path
	backend = '\n'.join(path.read_text() for path in (ROOT/'bootstrap/backend').rglob('*.vala'))
	assert not re.search(r'GenericOwnership|TypeParameterType', backend)
	authority = (ROOT/'bootstrap/semantic/generic-capabilities.vala').read_text()
	assert authority.count('static uint capabilities_of') == 1
	assert not (ROOT/'bootstrap/nabi/native-model.vala').read_text().find('NativeGenericOwner') >= 0
	write(out/'independent-determinism.json', deterministic)
	print(json.dumps(dict(scope='current independently built compiler comparison', comparisons=len(deterministic))), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?', '', text, flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)', text, flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+', 'ADDRESS', re.sub(r'loss record [\d,]+ of [\d,]+', 'loss record', record)) for record in records]


def memory(build, out, baseline):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True); jobs = []
	stages = {'gen-own-'+name for name in ['parser', 'semantic', 'core-standalone', 'monomorphizer-standalone', 'concrete-core-standalone', 'cfg-standalone', 'ssa-standalone', 'nabi-standalone', 'pipeline', 'llvm']}
	for root, prefix, names in [(build, '', stages | LEGACY), (baseline, 'baseline-', LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'], test['cmd'], test['workdir'] or str(root), dict(os.environ, **test['env']), 0))
	execution = build/'tests/gen-own/execution'
	for name in ['drop-resource', 'drop-object', 'relay', 'recursive', 'null', 'multi', 'order', 'class-nodeinit']:
		for stage in ['semantics', 'core', 'instances', 'cfg', 'ssa']:
			jobs.append(('dump-'+name+'-'+stage, [str(build/'astrac'), '--dump-'+stage, str(FIXTURES/f'gen-own-{name}.astra'), '--vapi', str(FIXTURES/'ownership.vapi')], str(ROOT), os.environ, 0))
	jobs.append(('unused-invalid', [str(build/'astrac'), '--dump-semantics', str(FIXTURES/'gen-own-invalid.astra')], str(ROOT), os.environ, 1))
	for name in ['drop-resource-O2', 'drop-object-O2', 'relay-O2', 'recursive-O2', 'null-O2', 'class-nodeinit-O2', 'conditional-O2', 'multi-callable-O2-fma', 'order-O2', 'f64-owner-bits-callable-O2-fma', 'identity-recurse-Counter-callable-O2-fma', 'identity-relay-Resource-O2', 'identity-relay-Empty-O2']:
		jobs.append(('run-'+name, [str(execution/name)], str(ROOT), os.environ, 42))

	def measure(job):
		name, argv, cwd, env, status = job
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(logs/(name+'.log')), *argv]
		result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs/(name+'.stdout')).write_text(result.stdout); (logs/(name+'.stderr')).write_text(result.stderr)
		text = (logs/(name+'.log')).read_text(); assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text); return int(match[1].replace(',', '')) if match else 0
		return dict(name=name, exit=result.returncode, expected=status, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) from'), reachable=number(r'still reachable: ([\d,]+) bytes'), lost_records=losses(text))

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
			assert row['exit'] == row['expected'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == row['suppressed'] == 0, row
	summary = dict(current_runs=len(rows)-len(LEGACY), baseline_runs=len(LEGACY), matching_legacy_startup_losses=len(LEGACY), new_astra_errors=0, new_astra_lost_bytes=0)
	write(logs/'summary.json', summary); print(json.dumps(summary), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('--independent-build', type=Path); parser.add_argument('--baseline-build', type=Path); parser.add_argument('--memory', action='store_true'); args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-gen-own'; out.mkdir(exist_ok=True)
	if args.memory:
		assert args.baseline_build is not None
		memory(build, out, args.baseline_build.resolve())
	else:
		audit(build, out, args.independent_build.resolve() if args.independent_build else None)
