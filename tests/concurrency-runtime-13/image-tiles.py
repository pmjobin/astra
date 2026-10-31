# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A109's actual pixel-owning Class under 2/4/8 workers and both seeds."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-image-tiles')
	here = Path(__file__).parent
	template = ROOT / 'examples/concurrency-runtime-13/a109-image-tiles.astra'
	providers = [ROOT / 'lib/runtime/runtime/threads-13.c', ROOT / 'lib/runtime/runtime/monitors-13.c', here / 'weak-race-oracle.c', here / 'image-tiles-oracle.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
	for workers in [2, 4, 8]:
		for seed in [1, 17]:
			lines = [template.read_text().split('int main()')[0],
				'extern(C) int race_prepare(int workers,int seed);extern(C) int app_tile_prepare(int count);',
				f'int main(){{race_prepare({workers},{seed});app_tile_prepare({workers});var tile=new Tile();var weak=tile.downgrade();']
			for i in range(workers):
				lines += [f'var w{i}=weak_clone(weak);var e{i}=new Observer(move w{i},{i});var t{i}=thread_bind(move e{i},process);']
			for i in range(workers):
				lines += [f'if(thread_start(t{i},4000)!=0){{return 81;}}']
			lines += ['race_parent_ready();release tile;race_parent_release();']
			for i in range(workers):
				lines += [f'if(thread_join(t{i})<0){{return 82;}}release t{i};']
			lines += ['var expired=weak.upgrade();if(expired!=null){return 83;}release weak;if(race_finish()!=0){return 84;}return app_finish(109);}']
			source = e.output / f'tiles-{workers}-{seed}.astra'; source.write_text('\n'.join(lines) + '\n')
			count = 'four' if workers == 4 else str(workers)
			expected = f'weak race: {count} native workers, one payload destruction, expired upgrade\nimage tiles: {workers} independently checked native worker checksums\n'
			for level in ['O0', 'O1', 'O2']:
				product = source.with_suffix('.' + level)
				e.run([e.compiler, '-' + level, source, *links, '--link-library', 'pthread', '-o', product])
				e.run([product], stdout=expected, timeout=30)
				e.files(product)
			e.files(source)
	source = e.output / 'tiles-8-17.astra'
	expected = 'weak race: 8 native workers, one payload destruction, expired upgrade\nimage tiles: 8 independently checked native worker checksums\n'
	for sanitizer in ['address', 'thread']:
		instrument(e, 'tiles', [source], providers, expected, sanitizer)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', source.with_suffix('.O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	e.files(template, *providers, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
