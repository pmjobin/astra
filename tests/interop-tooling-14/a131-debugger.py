#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A131: real O0/O2 Source debugger reads across closure/async/module/C frames."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	args = parser.parse_args()
	compiler, output = args.compiler.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='a131-', dir=output))
	sources = ROOT / 'examples/interop-tooling-14/a131'
	lib = ROOT / 'lib/astra'
	rows = []
	receipt = {'application': 'A131', 'compiler_sha256': sha(compiler), 'checks': rows,
		'sources': {p.name: sha(p) for p in sources.iterdir() if p.is_file()}}
	def run(command, *, contains='', env=None):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during qualification'
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', **(env or {})))
		rows.append({'command': list(map(str, command)), 'environment': env or {}, 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == 0 and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	for name in ('main.astra', 'math.astra', 'provider.c'):
		shutil.copyfile(sources / name, work / name)
	flags = ['-std=c11', '-O0', '-g', '-gdwarf-4', '-Wall', '-Wextra', '-Werror', '-pedantic']
	objects = []
	for name, source in [('provider', work / 'provider.c'), ('virtual', lib / 'async/virtual.c'), ('retained', lib / 'interop/retained.c')]:
		obj = work / (name + '.o')
		run(['clang', *flags, '-c', source, '-o', obj])
		objects += ['--link-object', obj]
	commands = work / 'inspect.gdb'
	source_line = next(i for i, line in enumerate((work / 'main.astra').read_text().splitlines(), 1) if 'if (record_probe(' in line)
	commands.write_text('''set pagination off
set confirm off
set debuginfod enabled off
python
import gdb, os
errors, hits, exits, source_hits = [], [], [], []
gdb.events.exited.connect(lambda event: exits.append(event.exit_code))
def source_frame(variable, filename):
	frame = gdb.newest_frame().older()
	while frame:
		sal = frame.find_sal()
		if sal.symtab and sal.symtab.filename.endswith(filename):
			try:
				value = frame.read_var(variable)
				if not value.is_optimized_out:
					frame.select()
					return value
			except gdb.error:
				pass
		frame = frame.older()
	raise AssertionError('no backed Source variable ' + variable + ' in ' + filename)
class Inspect(gdb.Breakpoint):
	def stop(self):
		try:
			foreign = gdb.newest_frame()
			stage = int(foreign.read_var('stage'))
			if stage not in range(5):
				return False
			print(gdb.execute('bt', to_string=True))
			if stage == 0:
				sample = source_frame('sample', 'main.astra')
				assert int(sample['category']) == 7 and int(sample['count']) == 11 and float(sample['total']) == 3.5
			elif stage == 1:
				capture = source_frame('capture', 'main.astra').dereference()
				assert int(capture['gain']) == 7 and int(capture['calls']) == 1
			elif stage == 2:
				assert int(source_frame('seed', 'main.astra')) == 11
			elif stage == 3:
				assert bool(source_frame('fail', 'main.astra')) == bool(int(os.environ.get('A131_FAIL', '0')))
			else:
				assert int(source_frame('corrected', 'math.astra')) == 42
			hits.append(stage)
			print('PASS Source debug stage=' + str(stage))
		except Exception as error:
			errors.append(str(error)); print('FAIL Source debug: ' + str(error))
		return False
for name in ('a131_record', 'a131_integer', 'a131_marker'):
	Inspect(name)
class SourceStop(gdb.Breakpoint):
	def stop(self):
		try:
			sample = gdb.newest_frame().read_var('sample')
			assert int(sample['category']) == 7 and int(sample['count']) == 11 and float(sample['total']) == 3.5
			source_hits.append(True)
			print('PASS explicit Source line breakpoint and aggregate')
		except Exception as error:
			errors.append(str(error))
		self.enabled = False
		return False
SourceStop('main.astra:__SOURCE_LINE__')
end
run
python
if errors or sorted(hits) != [0, 1, 2, 3, 4] or exits != [0] or source_hits != [True]:
	print('FAIL A131 debugger', errors, hits, exits)
	gdb.execute('quit 1')
print('PASS A131 debugger: Source aggregate closure-environment async-frame checked-parameter native-module foreign-stacks real-process-exit')
end
'''.replace('__SOURCE_LINE__', str(source_line)))
	for level in ('0', '1', '2'):
		module = work / ('math-O' + level + '.asti')
		run([compiler, '-g', '-O' + level, '--module', 'Debug131', '--emit-interface', module,
			'--native-export', 'Debug131.module_adjust', '-c', work / 'math.astra', '-o', work / ('math-O' + level + '.o')])
		binary = work / ('witness-O' + level)
		run([compiler, '-g', '-O' + level, '--import-module', module, work / 'main.astra',
			lib / 'base/errors.astra', lib / 'async/virtual.astra', *objects, '-o', binary])
		run(['llvm-dwarfdump', '--verify', binary], contains='No errors.')
		dependencies = run(['readelf', '-d', binary])
		assert not any(name in dependencies for name in ('libgobject', 'libglib', 'libLLVM', 'liburing', 'libstdc++'))
		for mode in ('0', '1'):
			environment = {'A131_FAIL': mode}
			run([binary], contains='PASS A131:', env=environment)
			if level in ('0', '2'):
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--errors-for-leak-kinds=all',
					'--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors', env=environment)
				run(['gdb', '-q', '-nx', '--batch', '-x', commands, binary], contains='PASS A131 debugger:', env=environment)
		receipt.setdefault('variants', []).append({'optimization': level, 'binary_sha256': sha(binary),
			'module_sha256': sha(module), 'module_object_sha256': sha(work / ('math-O' + level + '.o'))})
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: A131 real aggregate/closure/async/module debugger and lifetime; {len(rows)} commands; evidence {work}')


if __name__ == '__main__':
	main()
