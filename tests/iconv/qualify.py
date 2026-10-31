# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce integer conversion IR, machine, ABI/firewall and Valgrind audits."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import FIXTURES, ROOT, bindings

BASELINE = 'e0a23c9b4f99be579197ce469d224dc6bb33081e'
spec = importlib.util.spec_from_file_location('astra_scalar_qualification', ROOT / 'tests/f32/qualify.py')
scalar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scalar)


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
	return result.stdout


def audit(build, out):
	rows = []
	for name in FIXTURES:
		source = ROOT / f'tests/iconv/fixtures/iconv-{name}.astra'
		options = bindings() if name == 'ownership' else []
		stages = {stage: run([build / 'astrac', '--dump-' + stage, source, *options]) for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']}
		llvm, ssa = stages['llvm'], stages['ssa']
		assert not re.search(r'\b(?:ptrtoint|inttoptr|sitofp|uitofp|fptosi|fptoui|bitcast)\b', llvm), name
		assert not re.search(r'\b(?:alloca|load|store) <', llvm), name
		assert not re.search(r'LanePlace|lane-place|extractelement|insertelement|sext|zext|trunc', ssa), name
		counts = scalar.predecessors(llvm)
		counts['vector_phis'] = len(re.findall(r' = phi <', llvm))
		counts['scalar_conversions'] = len(re.findall(r' = integer-convert\b', ssa))
		counts['vector_conversions'] = len(re.findall(r' = integer-vector-convert\b', ssa))
		if name == 'control':
			assert counts['vector_phis'] >= 2
		if name == 'vector':
			assert 'icmp slt <16 x i8>' in llvm and 'icmp ult <16 x i8>' in llvm
		if name == 'values':
			assert counts['scalar_conversions'] == 8 and counts['vector_conversions'] == 4
			assert not re.search(r'\b(?:extractelement|insertelement|add|mul|sdiv|udiv|br|alloca|load|store)\b', llvm)
			assert 'storage' not in ssa and 'vector-extract' not in ssa and 'vector-insert' not in ssa
			for op in ['sext i8', 'zext i8', 'trunc i16', 'sext <8 x i8>', 'zext <8 x i8>', 'trunc <8 x i16>']:
				assert op in llvm
			assert 'ret i8 %p0' in llvm and 'ret <16 x i8> %p0' in llvm
			assert 'vector-v4' in stages['nabi']
		stem = out / name
		for stage, dump in stages.items():
			stem.with_suffix('.ll' if stage == 'llvm' else '.' + stage).write_text(dump)
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		stem.with_suffix('.machine').write_text(run(['objdump', '-dr', stem.with_suffix('.o')]))
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		assert all('astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line for line in undefined.splitlines()), (name, undefined)
		stem.with_suffix('.symbols').write_text(run(['nm', '-a', stem.with_suffix('.o')]))
		stem.with_suffix('.elf').write_text(run(['readelf', '-aW', stem.with_suffix('.o')]))
		executable = build / 'tests/iconv/execution' / name
		linked = run(['ldd', executable])
		stem.with_suffix('.ldd').write_text(linked)
		assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		stem.with_suffix('.executable-machine').write_text(run(['objdump', '-d', executable]))
		rows.append({'fixture': name, **counts})
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			before = subprocess.run(['git', 'show', BASELINE + ':' + path], cwd=ROOT, capture_output=True, check=True).stdout
			assert (ROOT / path).read_bytes() == before, path
			goldens += 1
	for path in ['bootstrap/nabi', 'bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/cfg/predecessors.vala', 'bootstrap/ssa/dominance.vala', 'bootstrap/semantic/types.vala', 'bootstrap/semantic/operators.vala', 'bootstrap/semantic/int-value.vala', 'bootstrap/semantic/f32-value.vala', 'bootstrap/semantic/vector-primitives.vala', 'bootstrap/backend/llvm/llvm-target-machine.vala', 'bootstrap/backend/llvm/llvm-scalar-lowering.vala']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	for directory in ['semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT / 'bootstrap' / directory).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.', code), path
			assert 'LanePlace' not in code, path
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	result = {'baseline': BASELINE, 'workloads': rows, 'baseline_goldens_unchanged': goldens, 'strict_generated_c_commands': len(generated), 'whole_vector_conversions': True, 'upstream_llvm_free': True, 'nabi_cabi_vapi_unchanged': True, 'llvm': run(['llvm-config', '--version']).strip(), 'host': run(['uname', '-m']).strip()}
	log = build / 'meson-logs/testlog.json'
	if log.exists():
		tests = [json.loads(line) for line in log.read_text().splitlines()]
		for test in tests:
			test['name'] = test['name'].split(':')[-1]
		tap = [test for test in tests if re.search(r'^1\.\.\d+', test.get('stdout', ''), re.M)]
		summary = {'meson_tests': len(tests), 'results': sorted(set(test['result'] for test in tests)), 'tap_suites': len(tap), 'tap_cases': sum(int(re.search(r'^1\.\.(\d+)', test['stdout'], re.M)[1]) for test in tap), 'firewalls': sum(test['name'].endswith('-no-llvm') for test in tests), 'llvm_linkage': sum(test['name'].endswith('-links-qualified-llvm') for test in tests), 'negative_firewalls': sum(test['name'] in ['firewall-rejects-llvm-backend', 'llvm-linkage-rejects-frontend'] for test in tests), 'iconv_tests': sum(test['name'].startswith('iconv-') for test in tests)}
		(out / 'test-results.json').write_text(json.dumps(summary, indent='\t') + '\n')
	(out / 'audit-results.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	logs = out / 'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'iconv-semantic-standalone', 'iconv-integer-value-standalone', 'iconv-core-standalone', 'iconv-cfg-standalone', 'iconv-ssa-standalone', 'iconv-pipeline', 'iconv-llvm', 'vec-nabi-standalone', 'cabi-standalone', 'vapi', 'semantic', 'core', 'cfg'}
	jobs = []
	for test in json.loads((build / 'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			jobs.append((test['name'], test['cmd'], test['workdir'] or str(build), dict(os.environ, **test['env'])))
	for name in FIXTURES + ['oracle']:
		jobs.append(('run-' + name, [str(build / 'tests/iconv/execution' / name)], str(ROOT), dict(os.environ)))
	jobs.append(('oracle-generator', [str(build / 'tests/iconv/astra-iconv-oracle'), '--emit-runtime'], str(ROOT), dict(os.environ)))
	for name in FIXTURES:
		options = [*bindings(), '--link-object', build / 'tests/cabi/companion.o'] if name == 'ownership' else []
		jobs.append(('compile-' + name, [str(build / 'astrac'), str(ROOT / f'tests/iconv/fixtures/iconv-{name}.astra'), *map(str, options), '-o', str(logs / name)], str(ROOT), dict(os.environ)))
	for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		jobs.append(('dump-' + stage, [str(build / 'astrac'), '--dump-' + stage, str(ROOT / 'tests/iconv/fixtures/iconv-values.astra')], str(ROOT), dict(os.environ)))
	flags = ['--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99']
	def measure(job):
		name, argv, cwd, env = job
		command = ['valgrind', *flags, '--log-file=' + str(logs / (name + '.log')), *argv]
		result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs / (name + '.stdout')).write_text(result.stdout)
		(logs / (name + '.stderr')).write_text(result.stderr)
		text = (logs / (name + '.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			match = re.search(pattern, text)
			return int(match[1].replace(',', '')) if match else 0
		return {'name': name, 'command': command, 'exit': result.returncode, 'errors': number(r'ERROR SUMMARY: ([\d,]+) errors'), 'definite': number(r'definitely lost: ([\d,]+) bytes'), 'indirect': number(r'indirectly lost: ([\d,]+) bytes'), 'possible': number(r'possibly lost: ([\d,]+) bytes'), 'reachable': number(r'still reachable: ([\d,]+) bytes')}
	rows = []
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure, job) for job in jobs]):
			row = future.result()
			rows.append(row)
			(logs / 'results.json').write_text(json.dumps(sorted(rows, key=lambda row: row['name']), indent='\t') + '\n')
			print(json.dumps({key: value for key, value in row.items() if key != 'command'}), flush=True)
	issues = [row['name'] for row in rows if row['exit'] or row['errors'] or row['definite'] or row['indirect'] or row['possible']]
	print(json.dumps({'measured': len(rows), 'requires_investigation': issues}), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build / 'qualification-iconv'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
