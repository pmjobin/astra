# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Audit DPTR storage, null guards, LLVM predecessors, machine code and memory."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import re
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import BASELINE, FIXTURES, ROOT, bindings


def run(argv, expected=0):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == expected, (argv, r.returncode, r.stdout, r.stderr)
	return r.stdout


def graphs(llvm):
	for function in re.findall(r'(?ms)^define [^\n]+\{\n(.*?)^}', llvm):
		blocks = {}
		for line in function.splitlines():
			label = re.match(r'^([\w.]+):', line)
			if label:
				block = label[1]
				blocks[block] = []
			elif line.strip():
				blocks[block].append(line.strip())
		yield blocks


def inspect(llvm):
	counts = {'phis': 0, 'guarded_phi_inputs': 0, 'null_guards': 0, 'memory_accesses': 0, 'allocas': 0}
	for blocks in graphs(llvm):
		incoming = {block: set() for block in blocks}
		for source, body in blocks.items():
			for target in re.findall(r'label %([\w.]+)', body[-1]):
				incoming[target].add(source)
		for block, body in blocks.items():
			for line in body:
				if ' = phi ' in line:
					predecessors = re.findall(r', %([\w.]+) \]', line)
					assert set(predecessors) == incoming[block] and len(predecessors) == len(set(predecessors)), (line, incoming[block])
					counts['phis'] += 1
					counts['guarded_phi_inputs'] += sum(p.endswith('.nonnull') for p in predecessors)
				counts['allocas'] += ' = alloca ' in line
				access = re.search(r'\b(?:load|store) (?:i8|i16|i32|float)(?:,| ).*\bptr ([%\w.]+)', line)
				if access:
					counts['memory_accesses'] += 1
					pointer = access[1]
					# Compiler-created allocas supply nonnull direct-local accesses.
					if not pointer.startswith('%storage'):
						assert block.endswith('.nonnull'), (block, line)
						assert len(incoming[block]) == 1
						guard = blocks[next(iter(incoming[block]))]
						stem = block.removesuffix('.nonnull')
						assert f'%{stem}.null = icmp eq ptr {pointer}, null' in guard or pointer == 'null' and guard[-1].startswith('br i1 true,'), (guard, line)
			if block.endswith('.nonnull'):
				counts['null_guards'] += 1
				stem = block.removesuffix('.nonnull')
				assert blocks[stem+'.trap'] == ['call void @llvm.trap()', 'unreachable']
				assert len(incoming[block]) == 1 and incoming[block] == incoming[stem+'.trap']
				guard = blocks[next(iter(incoming[block]))]
				assert guard[-1].endswith(f', label %{stem}.trap, label %{block}')
				assert re.search(r'\b(?:load|store) (?:i8|i16|i32|float)(?:,| )', body[0]), body
	return counts


def audit(build, out):
	rows = []
	for name in FIXTURES:
		source = ROOT/f'tests/dptr/fixtures/dptr-{name}.astra'
		options = bindings() if name == 'ownership' else []
		stages = {stage: run([build/'astrac', '--dump-'+stage, source, *(options if stage != 'syntax' else [])]) for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']}
		llvm, ssa = stages['llvm'], stages['ssa']
		assert not re.search(r'\b(?:ptrtoint|inttoptr|getelementptr|volatile|atomic|fast|nsz|reassoc|contract)\b', llvm)
		assert not re.search(r'\b(?:noalias|readonly|writeonly|dereferenceable)\b', llvm)
		counts = inspect(llvm)
		assert counts['allocas'] == len(re.findall(r'^\t\t\(storage ', ssa, re.M))
		if name == 'basic':
			ordinary = re.search(r'(?ms)^define [^\n]+@astra.fn.2\([^\n]+\{\n(.*?)^}', llvm)[1]
			assert 'phi i32' in ordinary and not re.search(r'\b(?:alloca|load|store)\b', ordinary)
		if name == 'widths':
			for physical in ['i8', 'i16', 'i32']:
				assert 'load '+physical in llvm and 'store '+physical in llvm and 'alloca '+physical in llvm
			assert not re.search(r'\b(?:sext|zext|trunc)\b', llvm)
		if name == 'f32':
			assert 'load float' in llvm and 'store float' in llvm and 'alloca float' in llvm
		if name == 'loop':
			assert counts['guarded_phi_inputs'] >= 4
		stem = out/name
		for stage, text in stages.items():
			stem.with_suffix('.ll' if stage == 'llvm' else '.'+stage).write_text(text)
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['opt', '-passes=verify', '-disable-output', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		stem.with_suffix('.machine').write_text(run(['objdump', '-dr', stem.with_suffix('.o')]))
		stem.with_suffix('.symbols').write_text(run(['nm', '-a', stem.with_suffix('.o')]))
		stem.with_suffix('.elf').write_text(run(['readelf', '-aW', stem.with_suffix('.o')]))
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		assert all('astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line for line in undefined.splitlines()), undefined
		linked = run(['ldd', build/'tests/dptr/execution'/name])
		stem.with_suffix('.ldd').write_text(linked)
		assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		stem.with_suffix('.executable-machine').write_text(run(['objdump', '-d', build/'tests/dptr/execution'/name]))
		# An audit-only C main calls the exact native fastcc no-argument main.
		# Parameter functions stay observable under O2; there is no C T* boundary.
		visible = re.sub(r'^define internal fastcc ', 'define fastcc ', llvm, flags=re.M)
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		visible += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		public = out/(name+'-audit-input.ll')
		public.write_text(visible)
		optimized = out/(name+'-O2.ll')
		run(['opt', '-passes=default<O2>', '-S', public, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		obj = out/(name+'-O2.o')
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		(out/(name+'-O2.machine')).write_text(run(['objdump', '-dr', obj]))
		exe = out/(name+'-O2')
		run(['cc', obj, *([build/'tests/cabi/companion.o'] if name == 'ownership' else []), '-o', exe])
		assert run([exe]) == ''
		rows.append({'fixture': name, **counts})
	for name in ['trap-int-read', 'trap-int-write', 'trap-f32-read', 'trap-f32-write']:
		llvm = run([build/'astrac', '--dump-llvm', build/'tests/dptr/execution'/(name+'.astra')])
		assert inspect(llvm)['null_guards'] == 1
		(out/(name+'.ll')).write_text(llvm)
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			before = subprocess.run(['git', 'show', BASELINE+':'+path], cwd=ROOT, capture_output=True, check=True).stdout
			assert (ROOT/path).read_bytes() == before, path
			goldens += 1
	for path in ['bootstrap/nabi/native-model.vala', 'bootstrap/nabi/native-builder.vala', 'bootstrap/nabi/native-verifier.vala', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/operators.vala', 'bootstrap/semantic/integer-value.vala', 'bootstrap/semantic/f32-value.vala', 'bootstrap/semantic/integer-conversion.vala', 'bootstrap/semantic/vector-primitives.vala', 'bootstrap/semantic/vector-dsp.vala', 'bootstrap/semantic/vector-dot.vala', 'bootstrap/cfg/predecessors.vala', 'bootstrap/ssa/dominance.vala', 'bootstrap/backend/llvm/llvm-scalar-lowering.vala']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	for directory in ['semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/directory).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.|LanePlace', code), path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text())) and all(test['result'] == 'OK' for test in tests)
	names = [test['name'].split(':')[-1] for test in tests]
	tap = [test for test in tests if re.search(r'^1\.\.\d+', test.get('stdout', ''), re.M)]
	summary = {'meson_tests': len(tests), 'tap_suites': len(tap), 'tap_cases': sum(int(re.search(r'^1\.\.(\d+)', test['stdout'], re.M)[1]) for test in tap), 'dptr_tests': sum(name.startswith('dptr-') for name in names), 'firewalls': sum(name.endswith('-no-llvm') for name in names), 'llvm_linkage': sum(name.endswith('-links-qualified-llvm') for name in names)}
	(out/'test-results.json').write_text(json.dumps(summary, indent='\t')+'\n')
	result = {'baseline': BASELINE, 'workloads': rows, 'baseline_goldens_unchanged': goldens, 'strict_generated_c_commands': len(generated), 'llvm': run(['llvm-config', '--version']).strip(), 'host': run(['uname', '-m']).strip(), 'default_and_O2_runtime': True}
	(out/'audit-results.json').write_text(json.dumps(result, indent='\t')+'\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	logs = out/'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'dptr-semantic-standalone', 'dptr-core-standalone', 'dptr-cfg-standalone', 'dptr-ssa-standalone', 'dptr-abi-standalone', 'dptr-pipeline', 'dptr-llvm', 'typed-pointers', 'borrows', 'cabi-standalone', 'vapi', 'resources', 'semantic', 'core', 'cfg'}
	jobs = []
	for test in json.loads((build/'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			jobs.append((test['name'], test['cmd'], test['workdir'] or str(build), dict(os.environ, **test['env']), 0))
	for name in FIXTURES+['matrices', 'eager-bool', 'trap-int-read', 'trap-int-write', 'trap-f32-read', 'trap-f32-write', 'trap-effects']:
		jobs.append(('run-'+name, [str(build/'tests/dptr/execution'/name)], str(ROOT), dict(os.environ), -signal.SIGILL if name.startswith('trap-') else 0))
	for name in ['basic', 'borrow', 'loop', 'alias', 'call', 'f32', 'integration', 'ownership']:
		options = [*bindings(), '--link-object', build/'tests/cabi/companion.o'] if name == 'ownership' else []
		jobs.append(('compile-'+name, [str(build/'astrac'), str(ROOT/f'tests/dptr/fixtures/dptr-{name}.astra'), *map(str, options), '-o', str(logs/name)], str(ROOT), dict(os.environ), 0))
	for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		jobs.append(('dump-'+stage, [str(build/'astrac'), '--dump-'+stage, str(ROOT/'tests/dptr/fixtures/dptr-basic.astra')], str(ROOT), dict(os.environ), 0))
	flags = ['--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99']
	def measure(job):
		name, argv, cwd, env, expected = job
		command = ['valgrind', *flags, '--log-file='+str(logs/(name+'.log')), *argv]
		r = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
		(logs/(name+'.stdout')).write_text(r.stdout)
		(logs/(name+'.stderr')).write_text(r.stderr)
		text = (logs/(name+'.log')).read_text()
		assert 'ERROR SUMMARY:' in text, name
		def number(pattern):
			m = re.search(pattern, text)
			return int(m[1].replace(',', '')) if m else 0
		return {'name': name, 'command': command, 'exit': r.returncode, 'expected': expected, 'errors': number(r'ERROR SUMMARY: ([\d,]+) errors'), 'definite': number(r'definitely lost: ([\d,]+) bytes'), 'indirect': number(r'indirectly lost: ([\d,]+) bytes'), 'possible': number(r'possibly lost: ([\d,]+) bytes'), 'reachable': number(r'still reachable: ([\d,]+) bytes')}
	rows = []
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure, job) for job in jobs]):
			row = future.result()
			rows.append(row)
			(logs/'results.json').write_text(json.dumps(sorted(rows, key=lambda r: r['name']), indent='\t')+'\n')
			print(json.dumps({k: v for k, v in row.items() if k != 'command'}), flush=True)
	issues = [r['name'] for r in rows if r['exit'] != r['expected'] or r['errors'] or r['definite'] or r['indirect'] or r['possible']]
	assert len(rows) == len(jobs) == 48
	(logs/'completion.json').write_text(json.dumps({'measured': len(rows), 'requires_investigation': issues}, indent='\t')+'\n')
	print(json.dumps({'measured': len(rows), 'requires_investigation': issues}), flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build/'qualification-dptr'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
