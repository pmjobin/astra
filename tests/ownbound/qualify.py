# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce OWNBOUND-1 object and memory audits with the qualified host tools."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BASELINE = 'fd181d8835a88476e622b2605f474cf5b7602d6a'
FIXTURES = ['consume', 'pass', 'null', 'release', 'move', 'borrow', 'rearm', 'multi', 'root-order', 'nested', 'order', 'recurse', 'mutual', 'result', 'terminating', 'branches', 'loop', 'shortcircuit', 'borrow-move', 'trap']


def run(argv, cwd=ROOT, env=None):
	result = subprocess.run([str(arg) for arg in argv], cwd=cwd, env=env, capture_output=True, text=True)
	if result.returncode:
		raise RuntimeError(f'{argv}: exit {result.returncode}\n{result.stdout}\n{result.stderr}')
	return result.stdout


def bindings(name):
	paths = [ROOT / f'tests/resource/fixtures/resource-{kind}.vapi' for kind in ['types', 'api']]
	paths.append(ROOT / 'tests/ownbound/fixtures/ownbound-extra.vapi')
	return [arg for path in paths for arg in ['--vapi', path]]


def audit(build, out):
	rows = []
	for name in FIXTURES + ['contract']:
		source = ROOT / f'tests/ownbound/fixtures/ownbound-{name}.astra'
		stem = out / f'ownbound-{name}'
		llvm = run([build / 'astrac', '--dump-llvm', source, *bindings(name)])
		for forbidden in ['alloca', 'ptrtoint', 'inttoptr', 'load ptr', 'store ptr', 'Resource', 'Device', 'descriptor', 'type_tag', 'refcount', 'retain', 'malloc']:
			assert forbidden not in llvm, (name, forbidden)
		assert not re.search(r'call\b[^\n]*%[\w.]+\(', llvm), name
		# Source parameter/result count determines the complete physical signature.
		declarations = re.findall(r'(?m)^(?:owned )?(void|int|bool|Resource) (\w+)\(([^)]*)\) \{', source.read_text())
		definitions = re.findall(r'define internal fastcc (void|i32|i1|ptr) @astra.fn.\d+\(([^)]*)\)', llvm)
		assert len(declarations) == len(definitions), name
		physical = {'void': 'void', 'int': 'i32', 'bool': 'i1', 'Resource': 'ptr'}
		for (result, _, params), (lowered_result, lowered_params) in zip(declarations, definitions):
			expected = [physical[param.strip().split()[-2]] for param in params.split(',') if param.strip()]
			actual = [param.strip().split()[0] for param in lowered_params.split(',') if param.strip()]
			assert lowered_result == physical[result] and actual == expected, (name, expected, actual)
		stem.with_suffix('.ll').write_text(llvm)
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		for tool, flags in [('nm', ['-a']), ('readelf', ['-aW']), ('objdump', ['-dr'])]:
			stem.with_suffix('.' + tool).write_text(run([tool, *flags, stem.with_suffix('.o')]))
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		for line in undefined.splitlines():
			assert 'astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line, (name, line)
		if name in FIXTURES:
			run([build / 'astrac', source, *bindings(name), '--link-object', build / 'tests/cabi/companion.o', '-o', stem])
			if name == 'trap':
				assert subprocess.run([stem], capture_output=True).returncode < 0
			else:
				assert run([stem]) == ''
			linked = run(['ldd', stem])
			stem.with_suffix('.ldd').write_text(linked)
			assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		rows.append({'fixture': name, 'llvm_verified': True, 'object_audited': True, 'executed': name in FIXTURES})
	entry_rejections = []
	for name, source in [('parameter', 'int main(owned Resource r) { return 0; }'), ('result', 'owned Resource main() { return null; }')]:
		path = out / ('invalid-entry-' + name + '.astra')
		path.write_text(source + '\n')
		result = subprocess.run([str(build / 'astrac'), str(path), *map(str, bindings(name)), '--link-object', str(build / 'tests/cabi/companion.o'), '-o', str(out / ('invalid-entry-' + name))], capture_output=True, text=True)
		assert result.returncode == 1 and 'main' in result.stderr and not (out / ('invalid-entry-' + name)).exists(), result.stderr
		entry_rejections.append({'form': name, 'diagnostic': result.stderr.strip()})
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix not in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			continue
		original = subprocess.run(['git', 'show', BASELINE + ':' + path], cwd=ROOT, capture_output=True, check=True).stdout
		assert (ROOT / path).read_bytes() == original, path
		goldens += 1
	commands = json.loads((build / 'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	for path in ['bootstrap/backend/llvm', 'bootstrap/nabi', 'bootstrap/vapi', 'bootstrap/foreign']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	result = {'workloads': rows, 'baseline_goldens_unchanged': goldens, 'strict_generated_c_commands': len(generated), 'entry_rejections': entry_rejections}
	(out / 'audit-results.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	assert (out / 'audit-results.json').exists(), 'Run the object audit first'
	logs = out / 'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'owned-boundaries', 'owned-boundaries-llvm', 'ownbound-semantic-standalone', 'ownbound-core-standalone', 'ownbound-cfg-standalone', 'ownbound-ssa-standalone', 'ownbound-abi-standalone', 'ownbound-ownership-flow-standalone', 'resources', 'resources-llvm', 'resource-semantic-standalone', 'resource-core-standalone', 'resource-cfg-standalone', 'resource-ssa-standalone', 'resource-abi-standalone', 'resource-ownership-flow-standalone', 'ownership-flow-standalone', 'vapi-frontend', 'vapi', 'semantic', 'core', 'cfg', 'ssa', 'core-standalone', 'cfg-standalone', 'ssa-standalone', 'nabi', 'nabi-standalone', 'cabi', 'cabi-standalone', 'ownership', 'moves', 'owner-borrows', 'releases', 'rearms', 'native-execution'}
	jobs = []
	for test in json.loads((build / 'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			args = test['cmd'] + (['-p', '/exec/ownbound'] if test['name'] == 'native-execution' else [])
			jobs.append((test['name'], args, test['workdir'] or str(build), dict(os.environ, **test['env']), 0))
	for name in FIXTURES:
		if name == 'trap':
			continue
		jobs.append(('run-' + name, [str(out / ('ownbound-' + name))], str(ROOT), dict(os.environ), 0))
		jobs.append(('compile-' + name, [str(build / 'astrac'), str(ROOT / f'tests/ownbound/fixtures/ownbound-{name}.astra'), *map(str, bindings(name)), '--link-object', str(build / 'tests/cabi/companion.o'), '-o', str(logs / ('ownbound-' + name))], str(ROOT), dict(os.environ), 0))
	for mode in ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']:
		jobs.append((mode[2:], [str(build / 'astrac'), mode, str(ROOT / 'tests/ownbound/fixtures/ownbound-contract.astra'), *map(str, bindings('contract'))], str(ROOT), dict(os.environ), 0))
	jobs.append(('reject-later-borrow', [str(build / 'astrac'), '--check', str(ROOT / 'tests/ownbound/fixtures/ownbound-invalid.astra'), *map(str, bindings('two-types'))], str(ROOT), dict(os.environ), 1))
	flags = ['--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99']

	def measure(job):
		name, args, cwd, env, expected = job
		command = ['valgrind', *flags, '--log-file=' + str(logs / (name + '.log')), *args]
		result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs / (name + '.stdout')).write_text(result.stdout)
		(logs / (name + '.stderr')).write_text(result.stderr)
		log = (logs / (name + '.log')).read_text()
		assert 'ERROR SUMMARY:' in log, name

		def number(pattern):
			match = re.search(pattern, log)
			return int(match[1].replace(',', '')) if match else 0

		return {'name': name, 'command': command, 'exit': result.returncode, 'expected': expected, 'errors': number(r'ERROR SUMMARY: ([\d,]+) errors'), 'definite': number(r'definitely lost: ([\d,]+) bytes'), 'indirect': number(r'indirectly lost: ([\d,]+) bytes'), 'possible': number(r'possibly lost: ([\d,]+) bytes'), 'reachable': number(r'still reachable: ([\d,]+) bytes')}

	results = []
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure, job) for job in jobs]):
			row = future.result()
			results.append(row)
			print(json.dumps({key: value for key, value in row.items() if key != 'command'}), flush=True)
			(logs / 'results.json').write_text(json.dumps(sorted(results, key=lambda row: row['name']), indent='\t') + '\n')
			# Every nonzero result is reported for investigation; no leak suppression or
			# assumed baseline exemption is applied by this measurement script.
	issues = [row['name'] for row in results if row['exit'] != row['expected'] or row['errors'] or row['definite'] or row['indirect'] or row['possible']]
	print(json.dumps({'measured': len(results), 'requires_investigation': issues}), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build / 'qualification'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
