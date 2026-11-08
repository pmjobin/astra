#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual Error argument/allocation/base/field order, compared with C0."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--component', type=Path)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	identity = None
	if a.component:
		identity = read(a.component.with_suffix('.identity.json'))
		assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('error_order_native_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('error-order-native-'+a.version+'-'+a.mode)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands, programs = [], []
	def run(argv, name, environment=None, allowed=(0,)):
		argv = list(map(str, argv))
		env = dict(os.environ, CCACHE_DISABLE='1')
		for key in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
			env.pop(key, None)
		invocation = ['/usr/bin/env', *[key+'='+str(value) for key, value in environment.items()], *argv] if environment else argv
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *invocation], cwd=build, env=env, capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=invocation, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stderr[-2000:])
		return r
	oracle_leaf = paths.RUNTIME/'error-order-oracles-source1'
	oracle = read(oracle_leaf/'result.json')
	provider = oracle_leaf/'provider.c'
	observer = oracle_leaf/'observe.c'
	assert sha(provider) == oracle['provider_source_sha256'] and sha(observer) == oracle['interposer_source_sha256']
	obj, library = build/'provider.o', build/'observe.so'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj], 'provider-build')
	run(['cc', '-std=c11', '-O2', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror', observer, '-o', library], 'observer-build')
	for row in oracle['programs']:
		name = row['name']
		source = oracle_leaf/(name+'.astra')
		assert sha(source) == row['source_sha256']
		inputs = [source, ROOT/'lib/astra/base/errors.astra']
		expected = next(profile for profile in row['profiles'] if profile['mode'] == a.mode)
		c0 = build/(name+'-C0')
		run([C0, '-'+a.mode, *inputs, '--link-object', obj, '-o', c0], name+'-C0-build')
		products = [('C0', c0)]
		result = dict(name=name, domain='ERROR_EVALUATION_ORDER', inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], provider_sha256=sha(provider), source_C0_oracle_sha256=sha(oracle_leaf/'result.json'), emit_exit=None, observations=[])
		if a.component:
			physical = build/(name+'.ll')
			physical.write_text('Error order native output sentinel\n')
			sentinel = sha(physical)
			emitted = run([a.component, '--native', physical, *inputs], name+'-Astra-emit', allowed=(*range(9), 132, -4))
			result['emit_exit'] = emitted.returncode
			if emitted.returncode == 0:
				run(['opt', '-passes=verify', '-disable-output', physical], name+'-Astra-verify')
				optimized, native_obj, native = build/(name+'-optimized.ll'), build/(name+'.o'), build/(name+'-Astra')
				run(['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized], name+'-Astra-optimize')
				run(['opt', '-passes=verify', '-disable-output', optimized], name+'-Astra-optimized-verify')
				run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', native_obj], name+'-Astra-object')
				run(['cc', '-no-pie', native_obj, obj, '-o', native], name+'-Astra-link')
				result.update(raw_LLVM_sha256=sha(physical), optimized_LLVM_sha256=sha(optimized))
				products.append(('Astra', native))
			else:
				result['destination_preserved'] = sha(physical) == sentinel
				assert result['destination_preserved']
		for producer, exe in products:
			label = name+'-'+producer
			observed = run([exe], label+'-execute', allowed=(42,))
			assert observed.stdout.decode() == expected['stdout']
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], label+'-memory', allowed=(42,))
			assert memory.stdout == observed.stdout and all(marker in memory.stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			trace = run([exe], label+'-allocation-trace', {'LD_PRELOAD':library}, (42,))
			assert trace.stdout == observed.stdout
			events = [line for line in trace.stderr.decode().splitlines() if line.startswith('R4 ')]
			failures = []
			for control in expected['failures']:
				size = control['size']
				failure = run([exe], label+'-fail-'+str(size), {'LD_PRELOAD':library, 'ASTRA_R4_FAIL_SIZE':size}, (132, -4))
				assert failure.stdout.decode() == control['observed_stdout'] and ('R4 X 0 '+str(size)+'\n').encode() in failure.stderr
				failures.append(dict(size=size, exit=failure.returncode, stdout=failure.stdout.decode(), events=[line for line in failure.stderr.decode().splitlines() if line.startswith('R4 ')], returning_memory_credit=False))
			result['observations'].append(dict(producer=producer, ELF_sha256=sha(exe), exit=42, returning_clean_memory=True, allocation_events=events, failures=failures))
		if len(result['observations']) == 2:
			c0_row, astra_row = result['observations']
			assert c0_row['allocation_events'] == astra_row['allocation_events'] and c0_row['failures'] == astra_row['failures']
		programs.append(result)
		(leaf/'result.json').write_text(json.dumps(dict(status='ERROR_ORDER_NATIVE_OBSERVATIONS' if a.component else 'INDEPENDENT_C0_ERROR_ORDER', profile=a.mode, component_sha256=sha(a.component) if a.component else None, programs=programs, limitation='Fresh unchanged C0 source execution and exact allocation/fatal/order comparisons. Unsuppressed returning Valgrind runs without allocation interposition. Fatal runs have no returning memory credit. Source stage stops remain explicit; no overall milestone qualification is implied.'), indent=2)+'\n')
		print(name, 'C0/native order and memory matched' if len(result['observations']) == 2 else 'C0 executed; Astra '+str(result['emit_exit']), flush=True)
	if a.component:
		assert all(len(row['observations']) == 2 for row in programs), 'Actual Error order source frontiers remain.'


if __name__ == '__main__':
	main()
