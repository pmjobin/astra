# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual last-strong release and weak upgrades across 2/4/8 workers and seeds."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def program(template, workers, seed):
	lines = [template.split('int main()')[0], 'extern(C) int race_prepare(int workers,int seed);',
		f'int main(){{race_prepare({workers},{seed});var tile=new Tile(17);var weak=tile.downgrade();']
	for i in range(workers):
		lines += [f'var w{i}=weak_clone(weak);var e{i}=new Observer(move w{i});var t{i}=thread_bind(move e{i},run);']
	for i in range(workers):
		lines += [f'if(thread_start(t{i},4000)!=0){{return 81;}}']
	lines += ['race_parent_ready();release tile;race_parent_release();']
	for i in range(workers):
		lines += [f'if(thread_join(t{i})<0){{return 82;}}release t{i};']
	lines += ['var expired=weak_upgrade(weak);if(expired!=null){return 83;}release weak;return race_finish();}']
	return '\n'.join(lines) + '\n'


def expected(workers):
	count = 'four' if workers == 4 else str(workers)
	return f'weak race: {count} native workers, one payload destruction, expired upgrade\n'


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-weak-stress')
	here = Path(__file__).parent
	providers = [ROOT / 'lib/runtime/runtime/threads-13.c', ROOT / 'lib/runtime/runtime/monitors-13.c', here / 'weak-race-oracle.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
	for workers in [2, 4, 8]:
		for seed in [1, 17]:
			source = e.output / f'weak-{workers}-{seed}.astra'
			source.write_text(program((here / 'weak-race.astra').read_text(), workers, seed))
			for level in ['O0', 'O1', 'O2']:
				product = source.with_suffix('.' + level)
				e.run([e.compiler, '-' + level, source, *links, '--link-library', 'pthread', '-o', product])
				e.run([product], stdout=expected(workers), timeout=30)
				e.files(product)
			e.files(source)
	source = e.output / 'weak-4-17.astra'
	for sanitizer in ['address', 'thread']:
		instrument(e, 'weak-race', [source], providers, expected(4), sanitizer)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'weak-8-17.O2'], stdout=expected(8), contains='ERROR SUMMARY: 0 errors', timeout=60)
	e.files(*providers, here / 'weak-race.astra', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
