# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real Astra producer threads and an independently observed dedicated Actor."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def program(template, workers, seed, messages=128):
	lines = [template, 'int main(){', f'actor_stress_prepare({workers},{messages},{seed});',
		'var receiver=new Collector();var sender=actor_bind(move receiver,handle,8,"actor-stress");']
	for i in range(workers):
		lines += [f'var s{i}=sender.clone();var p{i}=new Producer(move s{i},{i});var t{i}=thread_bind(move p{i},produce);']
	for i in range(workers):
		lines += [f'if(thread_start(t{i},{messages})!=0){{return 81;}}']
	for i in range(workers):
		lines += [f'if(thread_join(t{i})!={messages}){{return 82;}}release t{i};']
	lines += ['actor_stress_wait();try{actor_shutdown(sender);}catch(Error error){return 83;}',
		'release sender;return actor_stress_finish();}']
	return '\n'.join(lines) + '\n'


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-actor-stress')
	here = Path(__file__).parent
	providers = [ROOT / 'lib/runtime/runtime/threads-13.c', ROOT / 'lib/runtime/runtime/actors-13.c', here / 'actor-stress-oracle.c']
	links = []
	for source in providers:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		links += ['--link-object', obj]
	for workers in [2, 4, 8]:
		for seed in [1, 17]:
			source = e.output / f'actor-{workers}-{seed}.astra'
			source.write_text(program((here / 'actor-stress.astra').read_text(), workers, seed))
			expected = f'native Actor: {workers} concurrent producers, {workers * 128} FIFO messages, all attempted owners retired\n'
			for level in ['O0', 'O1', 'O2']:
				product = source.with_suffix('.' + level)
				e.run([e.compiler, '-' + level, source, ROOT / 'lib/astra/base/errors.astra', *links, '--link-library', 'pthread', '-o', product])
				e.run([product], stdout=expected, timeout=30)
				e.files(product)
			e.files(source)
	source = e.output / 'actor-4-17.astra'
	expected = 'native Actor: 4 concurrent producers, 512 FIFO messages, all attempted owners retired\n'
	for sanitizer in ['address', 'thread']:
		instrument(e, 'actor-stress', [source, ROOT / 'lib/astra/base/errors.astra'], providers, expected, sanitizer)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'actor-8-17.O2'],
		stdout='native Actor: 8 concurrent producers, 1024 FIFO messages, all attempted owners retired\n', contains='ERROR SUMMARY: 0 errors', timeout=60)
	e.files(*providers, Path(__file__), here / 'actor-stress.astra', here / 'sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
