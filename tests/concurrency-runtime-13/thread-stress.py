# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual native workers rendezvous through an independent pthread observer."""
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def program(workers, seed):
	lines = [
		'extern(C) int thread_oracle_arrive(int expected);',
		'extern(C) int thread_oracle_destroy();',
		'extern(C) int thread_oracle_finish(int expected);',
		'class E{int bias;int workers;init(int b,int w){this.bias=b;this.workers=w;}',
		'deinit(){thread_oracle_destroy();}}',
		'int run(borrowed E e,int n){thread_oracle_arrive(e.workers);',
		'int sum=e.bias;for(int i=0;i<n;i=i+1){sum=sum+i;}return sum;}',
		'int main(){',
	]
	for index in range(workers):
		lines += [f'var e{index}=new E({seed + index},{workers});',
			f'var t{index}=thread_bind(move e{index},run);']
	for index in range(workers):
		lines += [f'if(thread_start(t{index},{100 + index})!=0){{return 81;}}']
	for index in range(workers):
		expected = seed + index + (100 + index) * (99 + index) // 2
		lines += [f'if(thread_join(t{index})!={expected}){{return 82;}}',
			f'release t{index};']
	lines += [f'return thread_oracle_finish({workers});', '}']
	return '\n'.join(lines) + '\n'


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-thread-stress')
	here = Path(__file__).parent
	runtime = ROOT / 'lib/runtime/runtime/threads-13.c'
	provider = e.output / 'provider.o'
	oracle = e.output / 'oracle.o'
	for source, obj in [(runtime, provider), (here / 'thread-oracle.c', oracle)]:
		e.run(['clang', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
			'-pedantic', '-pthread', '-c', source, '-o', obj])
	for workers in [2, 4, 8]:
		for seed in [0, 17]:
			source = e.output / f'workers-{workers}-seed-{seed}.astra'
			source.write_text(program(workers, seed))
			expected = f'native threads: {workers} simultaneous identities, {workers} exact environment destructions\n'
			for level in ['O0', 'O1', 'O2']:
				product = source.with_suffix('.' + level)
				e.run([e.compiler, '-' + level, source, '--link-object', provider,
					'--link-object', oracle, '--link-library', 'pthread', '-o', product])
				e.run([product], stdout=expected, timeout=20)
				e.files(product)
			e.files(source)

			# Instrument the actual emitted Astra memory operations, including the
			# environment carrier and entry thunk, in addition to the C provider.
	source = e.output / 'workers-4-seed-17.astra'
	target = dict(line.split('=', 1) for line in e.run([e.compiler, '--target-info']).stdout.splitlines() if '=' in line)
	text = e.run([e.compiler, '-O1', '--dump-llvm', source]).stdout
	assert re.search(r'^define .*?@main\(', text, flags=re.M)
	text = f'target datalayout = "{target["data-layout"]}"\ntarget triple = "{target["target"]}"\n' + text
	text = re.sub(r'^(define .*?)\s*\{\s*$', r'\1 sanitize_thread {', text, flags=re.M)
	raw, instrumented, obj, product = [e.output / ('thread-tsan' + suffix) for suffix in ['.ll', '-instrumented.ll', '.o', '']]
	raw.write_text(text)
	e.run(['opt', '-passes=default<O1>,tsan-module,function(tsan)', '-S', raw, '-o', instrumented])
	assert '__tsan_read' in instrumented.read_text() and '__tsan_write' in instrumented.read_text()
	e.run(['llc', '-O1', '-filetype=obj', '-relocation-model=pic', instrumented, '-o', obj])
	e.run(['clang', '-O1', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror',
		'-pedantic', '-pthread', '-fsanitize=thread', obj, runtime,
		here / 'thread-oracle.c', '-o', product])
	e.run([product], stdout='native threads: 4 simultaneous identities, 4 exact environment destructions\n',
		timeout=30, env={'TSAN_OPTIONS': 'halt_on_error=1'})
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99',
		'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
		e.output / 'workers-8-seed-17.O2'],
		stdout='native threads: 8 simultaneous identities, 8 exact environment destructions\n', contains='ERROR SUMMARY: 0 errors')
	e.files(runtime, runtime.with_suffix('.h'), here / 'thread-oracle.c', Path(__file__), raw, instrumented, obj, product)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
