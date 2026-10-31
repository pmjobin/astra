# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise approved specialization and opaque native dependency boundaries."""
from pathlib import Path
import hashlib
import json
import os
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import time

from units import metadata, reseal


ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_path, output_path):
	compiler = Path(compiler_path).resolve(strict=True)
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='bounds-', dir=output))
	receipt = dict(format='astra-m15-resource-bounds/1', compiler_sha256=sha(compiler),
		recipes={name: sha(Path(__file__).with_name(name)) for name in ['bounds.py', 'units.py']},
		checks=[], sources={}, products={})

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')

	def run(argv, expected=0, diagnostic=None, memory=False):
		argv = list(map(str, argv))
		measurement = out / ('usage-' + str(len(receipt['checks'])) + '.txt')
		command = ['/usr/bin/time', '-f', '%e %M', '-o', str(measurement), *argv]
		started = time.perf_counter()
		process = subprocess.Popen(command, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
			start_new_session=True,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS=''))
		try:
			stdout, stderr = process.communicate(timeout=180)
		except BaseException:
			# The timing wrapper and compiler belong to this invocation. Retire
			# both on failure instead of leaving its compiler running as an orphan.
			try:
				os.killpg(process.pid, signal.SIGTERM)
			except ProcessLookupError:
				pass
			try:
				process.communicate(timeout=5)
			except subprocess.TimeoutExpired:
				try:
					os.killpg(process.pid, signal.SIGKILL)
				except ProcessLookupError:
					pass
				process.communicate()
			raise
		result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
		passed = result.returncode == expected and not result.stdout
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(word not in result.stderr for word in [b'assertion', b'CRITICAL', b'internal error'])
		elif memory:
			passed &= all(word in result.stderr for word in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		usage = measurement.read_text().splitlines()[-1].split()
		row = dict(argv=argv, exit=result.returncode, expected_exit=expected,
			elapsed_seconds=time.perf_counter() - started, peak_rss_kib=int(usage[1]),
			stderr=result.stderr.decode(errors='replace'), passed=bool(passed))
		if memory:
			match = re.search(rb'total heap usage: ([\d,]+) allocs, ([\d,]+) frees, ([\d,]+) bytes allocated', result.stderr)
			assert match
			row['target_heap_usage'] = dict(zip(['allocations', 'frees', 'bytes_allocated'],
				[int(value.replace(b',', b'')) for value in match.groups()]))
		receipt['checks'].append(row)
		save()
		assert passed, dict(check=len(receipt['checks']) - 1, receipt=str(out / 'checks.json'),
			exit=result.returncode, stderr=row['stderr'])

	def source(name, text):
		path = out / name
		path.write_text(text)
		receipt['sources'][name] = sha(path)
		return path

	def specialization(count, extra_class=False):
		if count > 1025:
			text = 'int choose<A,B,C,D,E,F,G,H,I,J,K,L,M,N,O>(int value){return value;}\n'
			keys = [','.join('bool' if index & (1 << bit) else 'int' for bit in range(15))
				for index in range(count)]
		else:
			text = 'int choose<T>(int value){return value;}\n'
			text += ''.join('struct Tag%d{int value;}\n' % index for index in range(count))
			keys = ['Tag' + str(index) for index in range(count)]
		if extra_class:
			text += 'class Marker<T>{T value;init(T value){this.value=value;}}\n'
		text += 'int main(){int result=0;\n'
		if extra_class:
			text += 'var marker=new Marker<int>(0);\n'
		text += ''.join('result=choose<' + key + '>(result);\n' for key in keys)
		# Repeated requests for one canonical instance must not consume the budget.
		text += 'result=choose<' + keys[0] + '>(result);return result;}\n'
		return source('instances-%d-%s.astra' % (count, extra_class), text)

	witness = specialization(1025)
	for level in range(3):
		native = out / ('instances-O' + str(level))
		run([compiler, '-O' + str(level), witness, '-o', native])
		receipt['products'][native.name] = dict(sha256=sha(native), bytes=native.stat().st_size)
		run([native])
		run(['valgrind', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
			'--error-exitcode=99', native], memory=True)
		# Core combines the Class, method, record, enum and function inventories.
	run([compiler, '--check', specialization(16383, extra_class=True)])
	run([compiler, '--check', specialization(16384, extra_class=True)], expected=1,
		diagnostic='at most 16384 closed instances; requesting choose<')
	run([compiler, '--check', specialization(16384)])
	run([compiler, '--check', specialization(16385)], expected=1,
		diagnostic='at most 16384 closed declaration requests')
	for depth in [128, 129]:
		type_name = 'Phantom<' * depth + 'int' + '>' * depth
		witness = source('type-depth-%d.astra' % depth,
			'struct Phantom<T>{int tag;}void touch<T>(){}int main(){touch<' + type_name + '>();return 0;}\n')
		run([compiler, '--check', witness], expected=int(depth > 128),
			diagnostic='type-expression depth 128' if depth > 128 else None)
		if depth == 128:
			for level in range(3):
				native = out / ('depth-O' + str(level))
				run([compiler, '-O' + str(level), witness, '-o', native])
				receipt['products'][native.name] = dict(sha256=sha(native), bytes=native.stat().st_size)
				run([native])
				run(['valgrind', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
					'--error-exitcode=99', native], memory=True)
	growth = source('expanding-arguments.astra',
		'struct Phantom<T>{int tag;}void grow<T>(){grow<Phantom<T>>();}int main(){grow<int>();return 0;}\n')
	run([compiler, '--check', growth], expected=1, diagnostic='type-expression depth 128')
	print('specialization boundaries passed', flush=True)

	producers = out / 'producer-sources'
	producers.mkdir()
	interfaces = []
	for index in range(257):
		module = 'BoundUnit' + str(index)
		path = producers / (module + '.astra')
		value = 'BoundUnit%d.value()+1' % (index - 1) if 0 < index <= 64 else str(index)
		if 65 <= index <= 255:
			value = 'BoundUnit0.value()+BoundUnit1.value()+BoundUnit2.value()-3+' + str(index)
		path.write_text('namespace ' + module + ';\nint value(){return ' + value + ';}\n')
		receipt['sources'][str(path.relative_to(out))] = sha(path)
		interface = out / ('unit-%03d.asti' % index)
		implementation = interface.with_suffix('.o')
		imports = ['--import-module', interfaces[index - 1]] if 0 < index <= 64 else []
		if 65 <= index <= 255:
			dependencies = interfaces[:3]
			if index == 65:
				alias = out / 'alias-000.asti'
				shutil.copyfile(interfaces[0], alias)
				receipt['products'][alias.name] = dict(sha256=sha(alias), bytes=alias.stat().st_size)
				dependencies = [alias, *interfaces[1:3]]
			imports = [item for path in dependencies for item in ['--import-module', path]]
		run([compiler, '-O2', '-c', '--module', module, '--emit-interface', interface,
			'--native-export', module + '.value', *imports, path, '-o', implementation])
		for product in [interface, implementation]:
			receipt['products'][product.name] = dict(sha256=sha(product), bytes=product.stat().st_size)
		interfaces.append(interface)
		if index % 32 == 0:
			print('native units built:', index + 1, flush=True)
	receipt['positive_dependency_graph'] = dict(units=256, interface_paths=257,
		depth_edges=64, edges=64 + 191 * 3, exact_alias_diamond=True)
	# Compilation after this point sees declaration artifacts and real objects only.
	producers.rename(out / 'hidden-producer-sources')
	consumer = source('consumer.astra', 'int main(){int result=BoundUnit64.value();\n' +
		''.join('result=result+BoundUnit%d.value();\n' % index for index in range(65, 256)) +
		'if(result!=%d){return 1;}return 0;}\n' % (64 + sum(range(65, 256))))
	imports = [item for path in interfaces[64:256] for item in ['--import-module', path]]
	for level in range(3):
		native = out / ('units-O' + str(level))
		run([compiler, '-O' + str(level), *imports, consumer, '-o', native])
		receipt['products'][native.name] = dict(sha256=sha(native), bytes=native.stat().st_size)
		run([native])
		run(['valgrind', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
			'--error-exitcode=99', native], memory=True)
	run([compiler, '--check', *imports, '--import-module', interfaces[256], consumer],
		expected=1, diagnostic='dependency graph exceeds 256 native units')
	# A producer itself participates in both depth and unit-count limits.
	too_deep = source('too-deep.astra', 'namespace TooDeep;int value(){return BoundUnit64.value();}\n')
	run([compiler, '-c', '--module', 'TooDeep', '--emit-interface', out / 'too-deep.asti',
		'--native-export', 'TooDeep.value', '--import-module', interfaces[64], too_deep,
		'-o', out / 'too-deep.o'], expected=1, diagnostic='dependency depth exceeds 64 edges for producer TooDeep')
	too_wide = source('too-wide.astra', 'namespace TooWide;int value(){return 0;}\n')
	wide_imports = [item for path in [interfaces[63], *interfaces[65:257]] for item in ['--import-module', path]]
	run([compiler, '-c', '--module', 'TooWide', '--emit-interface', out / 'too-wide.asti',
		'--native-export', 'TooWide.value', *wide_imports, too_wide, '-o', out / 'too-wide.o'],
		expected=1, diagnostic='dependency graph exceeds 256 native units including producer')
	# Independent metadata mutation: a cached subtree must retain its full depth.
	groups = metadata(interfaces[255].read_text())
	dependency = metadata(interfaces[64].read_text())
	groups['dependency BoundUnit64'] = dict(interface=interfaces[64].name,
		interface_sha256=sha(interfaces[64]), object_sha256=dependency['object']['sha256'],
		abi_identity=dependency['abi']['identity'])
	mutant = out / 'z-overdepth.asti'
	mutant.write_text(reseal(groups))
	for prefix in [[], ['--import-module', interfaces[64]]]:
		run([compiler, '--check', *prefix, '--import-module', mutant, consumer],
			expected=1, diagnostic='dependency depth exceeds 64 edges')
	assert not (out / 'too-deep.o').exists() and not (out / 'too-wide.o').exists()
	assert sha(compiler) == receipt['compiler_sha256']
	save()
	print(json.dumps(dict(receipt=str(out / 'checks.json'), checks=len(receipt['checks']),
		memory_runs=9, passed=True)), flush=True)


if __name__ == '__main__':
	main(*sys.argv[1:])
