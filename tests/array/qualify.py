# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproducible ARRAY-1 object, bounds, golden, firewall and memory audits."""
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
from execute import ROOT, FIXTURES

BASELINE = 'e996d382a319e0f60464f8c31341c5793a121803'


def run(argv):
	r = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == 0, (argv, r.returncode, r.stdout, r.stderr)
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
	assert 'getelementptr inbounds' not in llvm and not re.search(r'\b(?:poison|undef|ptrtoint|inttoptr)\b', llvm)
	counts = dict(allocas=0, geps=0, dynamic_geps=0, bounds_guards=0, phi_inputs=0, guarded_phi_inputs=0)
	for blocks in graphs(llvm):
		incoming = {b: set() for b in blocks}
		for b, body in blocks.items():
			for target in re.findall(r'label %([\w.]+)', body[-1]):
				incoming[target].add(b)
		entry = next(iter(blocks))
		dominators = {b: ({entry} if b == entry else set(blocks)) for b in blocks}
		changed = True
		while changed:
			changed = False
			for b in blocks:
				if b == entry:
					continue
				new = {b} | (set.intersection(*(dominators[p] for p in incoming[b])) if incoming[b] else set())
				if new != dominators[b]:
					dominators[b] = new
					changed = True
		definitions = {}
		for b, body in blocks.items():
			for position, line in enumerate(body):
				definition = re.match(r'(%[\w.]+) = (.*)', line)
				if definition:
					definitions[definition[1]] = (b, position, definition[2])
		for b, body in blocks.items():
			if b.startswith('bounds') and b.endswith('.valid'):
				counts['bounds_guards'] += 1
				stem = b.removesuffix('.valid')
				assert blocks[stem+'.trap'] == ['call void @llvm.trap()', 'unreachable']
				assert len(incoming[b]) == 1 and incoming[b] == incoming[stem+'.trap']
				assert blocks[next(iter(incoming[b]))][-1].endswith(f', label %{stem}.trap, label %{b}')
			for position, line in enumerate(body):
				counts['allocas'] += ' = alloca [' in line
				if ' = phi ' in line:
					predecessors = re.findall(r', %([\w.]+) \]', line)
					assert set(predecessors) == incoming[b], (line, incoming[b])
					counts['phi_inputs'] += len(predecessors)
					counts['guarded_phi_inputs'] += sum(p.startswith('bounds') and p.endswith('.valid') for p in predecessors)
				gep = re.search(r'getelementptr \[(\d+) x .+\], ptr (%storage\d+), i64 0, i64 ([%\w.]+)', line)
				if not gep:
					continue
				counts['geps'] += 1
				length = int(gep[1])
				index = gep[3]
				if not index.startswith('%'):
					assert 0 <= int(index) < length
					continue
				counts['dynamic_geps'] += 1
				definition_block, definition_position, definition = definitions[index]
				assert definition_block in dominators[b] and (definition_block != b or definition_position < position)
				normalization = re.fullmatch(r'zext i(8|16|32) (%[\w.]+) to i64', definition)
				assert normalization, definition
				original = normalization[2]
				# Each audited dynamic access has its own original-domain check;
				# allow a RHS expression region between the check and final GEP.
				valid = []
				for guard in dominators[definition_block]:
					if not guard.startswith('bounds') or not guard.endswith('.valid'):
						continue
					check = '\n'.join(blocks[next(iter(incoming[guard]))])
					upper = re.search(r'icmp (sge|uge) i\d+ '+re.escape(original)+r', '+str(length)+r'\b', check)
					if upper:
						if upper[1] == 'sge':
							assert re.search(r'icmp slt i\d+ '+re.escape(original)+r', 0\b', check)
						valid.append(guard)
				assert valid, (b, line, definition)
	return counts


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT/f'tests/resource/fixtures/resource-{name}.vapi']]


def audit(build, out):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text())), 'Wait for the complete Meson run before starting qualification'
	assert all(test['result'] == 'OK' for test in tests), 'Investigate failed Meson tests before qualification'
	rows = []
	for name in FIXTURES:
		options = bindings() if name == 'ownership' else []
		stages = {stage: run([build/'astrac', '--dump-'+stage, ROOT/f'tests/array/fixtures/array-{name}.astra', *options]) for stage in ['core', 'cfg', 'ssa', 'nabi', 'llvm']}
		assert all('array-initialize' in stages[s] and 'array-element-place' in stages[s] for s in ['core', 'cfg', 'ssa'])
		assert not re.search(r'LanePlace|ArrayValue|array-value|\(parameter[^\n]*\[', stages['ssa'])
		llvm = stages['llvm']
		counts = inspect(llvm)
		if name == 'loop':
			assert counts['guarded_phi_inputs'] >= 3
		for stage, text in stages.items():
			(out/(name+('.ll' if stage == 'llvm' else '.'+stage))).write_text(text)
		stem = out/name
		run(['llvm-as', stem.with_suffix('.ll'), '-o', stem.with_suffix('.bc')])
		run(['opt', '-passes=verify', '-disable-output', stem.with_suffix('.bc')])
		run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', stem.with_suffix('.bc'), '-o', stem.with_suffix('.o')])
		stem.with_suffix('.machine').write_text(run(['objdump', '-dr', stem.with_suffix('.o')]))
		stem.with_suffix('.symbols').write_text(run(['nm', '-a', stem.with_suffix('.o')]))
		stem.with_suffix('.elf').write_text(run(['readelf', '-aW', stem.with_suffix('.o')]))
		undefined = run(['nm', '-u', stem.with_suffix('.o')])
		assert all('astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line for line in undefined.splitlines()), undefined
		linked = run(['ldd', build/'tests/array/execution'/name])
		assert not any(word in linked.lower() for word in ['glib', 'gobject', 'llvm'])
		stem.with_suffix('.ldd').write_text(linked)
		visible = re.sub(r'^define internal fastcc ', 'define fastcc ', llvm, flags=re.M)
		main_id = re.search(r'\(function #(\d+) "main" -> int', stages['ssa'])[1]
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
		rows.append(dict(fixture=name, **counts))
	goldens = 0
	for path in run(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'tests']).splitlines():
		if Path(path).suffix in {'.syntax', '.semantics', '.core', '.cfg', '.ssa', '.nabi', '.cabi', '.ll', '.stderr'}:
			before = subprocess.run(['git', 'show', BASELINE+':'+path], cwd=ROOT, capture_output=True, check=True).stdout
			assert (ROOT/path).read_bytes() == before, path
			goldens += 1
	for path in ['bootstrap/nabi', 'bootstrap/cabi', 'bootstrap/vapi', 'bootstrap/foreign', 'bootstrap/semantic/operators.vala', 'bootstrap/semantic/integer-value.vala', 'bootstrap/semantic/f32-value.vala', 'bootstrap/semantic/integer-conversion.vala', 'bootstrap/semantic/vector-primitives.vala', 'bootstrap/semantic/vector-dsp.vala', 'bootstrap/semantic/vector-dot.vala', 'bootstrap/cfg/predecessors.vala', 'bootstrap/ssa/dominance.vala', 'bootstrap/ssa/ssa-memory.vala']:
		assert run(['git', 'diff', BASELINE, '--', path]) == '', path
	for directory in ['syntax', 'semantic', 'core', 'cfg', 'ssa', 'nabi']:
		for path in (ROOT/'bootstrap'/directory).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(), flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.|LanePlace|CoreArrayValue|SsaArrayValue', code), path
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	names = [test['name'].split(':')[-1] for test in tests]
	tap = [test for test in tests if re.search(r'^1\.\.\d+', test.get('stdout', ''), re.M)]
	summary = dict(meson_tests=len(tests), tap_suites=len(tap), tap_cases=sum(int(re.search(r'^1\.\.(\d+)', test['stdout'], re.M)[1]) for test in tap), array_tests=sum(name.startswith('array-') for name in names), firewalls=sum(name.endswith('-no-llvm') for name in names), llvm_linkage=sum(name.endswith('-links-qualified-llvm') for name in names))
	alignment = next(test for test in tests if test['name'].endswith(':array-llvm'))['stdout']
	pairs = re.findall(r'LLVM memory alignment (\d+) equals target ABI alignment (\d+)', alignment)
	assert len(pairs) == 189 and all(a == b for a, b in pairs)
	result = dict(baseline=BASELINE, workloads=rows, baseline_goldens_unchanged=goldens, strict_generated_c_commands=len(generated), alignment_checks=len(pairs), llvm=run(['llvm-config', '--version']).strip(), host=run(['uname', '-m']).strip(), **summary)
	(out/'audit-results.json').write_text(json.dumps(result, indent='\t')+'\n')
	print(json.dumps(result), flush=True)


def memory(build, out):
	logs = out/'valgrind'
	logs.mkdir(exist_ok=True)
	selected = {'array-semantic-standalone', 'array-core-standalone', 'array-cfg-standalone', 'array-ssa-standalone', 'array-pipeline', 'array-llvm', 'resources', 'semantic', 'core', 'cfg', 'nabi-standalone', 'cabi-standalone', 'vapi'}
	jobs = []
	for test in json.loads((build/'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			jobs.append((test['name'], test['cmd'], test['workdir'] or str(build), dict(os.environ, **test['env']), 0))
	results = json.loads((build/'tests/array/execution/results.json').read_text())
	for name in [*FIXTURES, 'matrix', 'captured-index', *results['traps']]:
		jobs.append(('run-'+name, [str(build/'tests/array/execution'/name)], str(ROOT), dict(os.environ), -signal.SIGILL if name.startswith('trap-') else 0))
	for name in FIXTURES:
		options = [*bindings(), '--link-object', build/'tests/cabi/companion.o'] if name == 'ownership' else []
		jobs.append(('compile-'+name, [str(build/'astrac'), str(ROOT/f'tests/array/fixtures/array-{name}.astra'), *map(str, options), '-o', str(logs/name)], str(ROOT), dict(os.environ), 0))
	for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		jobs.append(('dump-'+stage, [str(build/'astrac'), '--dump-'+stage, str(ROOT/'tests/array/fixtures/array-vector.astra')], str(ROOT), dict(os.environ), 0))
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
		return dict(name=name, command=command, exit=r.returncode, expected=expected, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), reachable=number(r'still reachable: ([\d,]+) bytes'))
	rows = []
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure, job) for job in jobs]):
			row = future.result()
			rows.append(row)
			(logs/'results.json').write_text(json.dumps(sorted(rows, key=lambda r: r['name']), indent='\t')+'\n')
			print(json.dumps({k: v for k, v in row.items() if k != 'command'}), flush=True)
	for row in rows:
		if row['name'] in ['semantic', 'core', 'cfg']:
			assert row['exit'] == 99 and row['errors'] == 1 and row['definite'] == 16384 and row['indirect'] == row['possible'] == 0, row
			assert 'call_init' in (logs/(row['name']+'.log')).read_text()
		else:
			assert row['exit'] == row['expected'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0, row
	assert (logs/'run-trap-effects.stdout').read_text() == 'I'
	(logs/'completion.json').write_text(json.dumps(dict(measured=len(rows)))+'\n')


if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument('build', type=Path)
	parser.add_argument('--memory', action='store_true')
	args = parser.parse_args()
	build = args.build.resolve()
	out = build/'qualification-array'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build, out)
