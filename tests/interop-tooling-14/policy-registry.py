#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify registry availability against real parser/semantic/IR/native behavior."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='policies-', dir=output))
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows}
	def run(command, expected=0, contains=''):
		assert hashlib.sha256(compiler.read_bytes()).hexdigest() == receipt['compiler_sha256'], 'compiler changed during qualification'
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	listing = run([compiler, '--policy-registry'], contains='astra-policy-registry/1')
	items = [line.split('\t') for line in listing.splitlines()[2:]]
	assert len({i[0] for i in items}) == len(items) == len({i[1] for i in items})
	by_name = {i[1]: i for i in items}
	assert by_name['Shared'][2] == 'AVAILABLE_SELECTED_PROFILE'
	for name in ['CImport', 'CExport', 'COMImport', 'COMExport', 'GObjectImport', 'GObjectExport']:
		assert by_name[name][2] == 'AVAILABLE_SELECTED_PROFILE'
	for name in ['Tracked', 'Observable', 'Memoized']:
		assert by_name[name][2] == 'RESERVED_UNIMPLEMENTED'
		# Commuting accepted concurrency attributes preserve every existing stage.
	paths = []
	for i, attrs in enumerate(('[Shared, Monitor]', '[Monitor, Shared]', '[Monitor][Shared]')):
		p = work / f'order-{i}.astra'
		p.write_text(attrs + ' class Registry14 { private int value; init() { this.value = 40; } int read() { return this.value; } }\n'
			'int main() { var cell = new Registry14(); return cell.read() - 40; }\n')
		paths.append(p)
	for mode in ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		dumps = [run([compiler, mode, path]) for path in paths]
		assert dumps[0] == dumps[1] == dumps[2], mode
		# Native singleton policy remains valid independently of foreign factories.
		# A foreign factory has no authority to invent process-anchor shutdown.
	singleton_body = ''' class Configuration14 {
	private int value;
	init(int value) { this.value = value; }
	int read() { return this.value; }
	deinit() { policy14_destroy(this.value); }
}
extern(C) int policy14_destroy(int value);
extern(C) int policy14_finish();
int main() {
	var root = new Configuration14(17);
	var again = new Configuration14(99);
	if (root.read() != 17 || again.read() != 17) { return 1; }
	var weak = root.downgrade();
	var busy = singleton_shutdown(root);
	if (busy != null) { return 2; }
	release again;
	var retired = singleton_shutdown(root);
	if (retired == null || retired.read() != 17) { return 3; }
	release root; release retired;
	var expired = weak.upgrade();
	if (expired != null) { return 4; }
	release weak;
	return policy14_finish();
}
'''
	oracle = work / 'singleton-oracle.c'
	oracle.write_text('#include <stdint.h>\nstatic int32_t destroyed, bad;\nint32_t policy14_destroy(int32_t value) { ++destroyed; bad += value != 17; return 0; }\nint32_t policy14_finish(void) { return destroyed != 1 || bad; }\n')
	links = []
	for source in [oracle, *[ROOT / 'lib/runtime/runtime' / (name + '-13.c') for name in ('threads', 'monitors', 'singletons')]]:
		obj = work / (source.stem + '.o')
		run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		links += ['--link-object', obj]
	singletons = []
	for i, order in enumerate(itertools.permutations(('Shared', 'Monitor', 'Singleton'))):
		path = work / f'singleton-{i}.astra'
		path.write_text('[' + ','.join(order) + ']' + singleton_body)
		singletons.append(path)
		for level in ('0', '2'):
			binary = work / f'singleton-{i}-O{level}'
			run([compiler, '-O' + level, path, *links, '--link-library', 'pthread', '-o', binary])
			run([binary])
			if i == 0:
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--errors-for-leak-kinds=all', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for mode in ('--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm'):
		dumps = [run([compiler, mode, path]) for path in singletons]
		assert all(text == dumps[0] for text in dumps), mode
		# Existing CCode dispatch still invokes its independently defined libc ABI.
	c_source = work / 'c-import.astra'
	c_source.write_text('[CCode(cname = "abs")] extern(C) int magnitude(int value);\nint main() { return magnitude(-41) - 41; }\n')
	for level in ('0', '2'):
		product = work / ('c-O' + level)
		run([compiler, '-O' + level, c_source, '-o', product])
		run([product])
	bad = work / 'invalid.astra'
	for source, reason in [
		('[Shared, Shared] class T {}', 'duplicate'),
		('[Shared(value="x")] class T {}', 'take no arguments'),
		('[Monitor] int f() { return 0; }', 'require a native Class'),
		('[Actor, Monitor] class T {}', 'invalid concurrency declaration policy identity'),
		('[CImport] int f() { return 0; }', 'foreign declarations have no body'),
		('[COMExport] class T {}', 'requires an explicit Class CExport bridge'),
		('[UnknownSafetyClaim] class T {}', 'unsupported declaration attribute')]:
		bad.write_text(source)
		run([compiler, '--check', bad], expected=1, contains=reason)
	class_text = (ROOT / 'tests/interop-tooling-14/c-class/counter.astra').read_text()
	for text, reason in [
		(class_text.replace('[Shared]', '[Shared,Monitor,Singleton]'), 'plain Shared or Shared Monitor heap root'),
		(class_text.replace('[Shared]', '[Shared,Actor]'), 'Actor requires its exclusive dedicated-executor policy'),
		(class_text.replace('[Shared]', '[Shared,ThreadBound]'), 'plain Shared or Shared Monitor heap root'),
		(class_text.replace('class Counter14 {', 'class Counter14<T> {'), 'generic'),
	]:
		bad.write_text(text)
		run([compiler, '--check', bad], expected=1, contains=reason)
	run([compiler, '--policy-registry', c_source], expected=2)
	run([compiler, '--check', c_source])
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} registry, commuting policy, stage, native C and refusal commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
