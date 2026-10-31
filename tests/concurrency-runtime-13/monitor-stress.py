# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real contending monitor calls, including nested checked-error unlocks."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def program(workers, seed, iterations=2000):
	accepted = sum((i + seed) % 17 != 0 for i in range(iterations))
	lines = [
		'extern(C) int thread_oracle_arrive(int expected);',
		'extern(C) int thread_oracle_destroy();extern(C) int thread_oracle_finish(int expected);',
		'[Monitor]class Ledger{private int value;init(){this.value=0;}',
		'void add(int n)throws Error{if(n%17==0){throw new Error("rejected credit");}this.value=this.value+1;}',
		'void credit(int n)throws Error{this.add(n);}int read(){return this.value;}}',
		'class Work{owned Shared<Ledger> ledger;int workers;int seed;',
		'init(owned Shared<Ledger> ledger,int workers,int seed){this.ledger=move ledger;this.workers=workers;this.seed=seed;}',
		'deinit(){thread_oracle_destroy();}}',
		'void credit(borrowed Ledger ledger,int n)throws Error{ledger.credit(n);}',
		'int read(borrowed Ledger ledger){return ledger.read();}',
		'int run(borrowed Work work,int iterations){var ledger=shared_clone(work.ledger);',
		'thread_oracle_arrive(work.workers);int accepted=0;',
		'for(int i=0;i<iterations;i=i+1){try{credit(shared_borrow(ledger),i+work.seed);accepted=accepted+1;}catch(Error error){}}',
		'return accepted;}',
		'int main(){var unique=new Ledger();var root=shared_acquire(move unique);',
	]
	for i in range(workers):
		lines += [f'var c{i}=shared_clone(root);var e{i}=new Work(move c{i},{workers},{seed});var t{i}=thread_bind(move e{i},run);']
	for i in range(workers):
		lines += [f'if(thread_start(t{i},{iterations})!=0){{return 81;}}']
	for i in range(workers):
		lines += [f'if(thread_join(t{i})!={accepted}){{return 82;}}release t{i};']
	lines += [f'if(read(shared_borrow(root))!={workers * accepted}){{return 83;}}release root;return thread_oracle_finish({workers});', '}']
	return '\n'.join(lines) + '\n'


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-monitor-stress')
	here = Path(__file__).parent
	providers = [ROOT / 'lib/runtime/runtime/threads-13.c', ROOT / 'lib/runtime/runtime/monitors-13.c', here / 'thread-oracle.c']
	links = []
	for source in providers:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		links += ['--link-object', obj]
	for workers in [2, 4, 8]:
		for seed in [1, 17]:
			source = e.output / f'monitor-{workers}-{seed}.astra'
			source.write_text(program(workers, seed))
			expected = f'native threads: {workers} simultaneous identities, {workers} exact environment destructions\n'
			for level in ['O0', 'O1', 'O2']:
				product = source.with_suffix('.' + level)
				e.run([e.compiler, '-' + level, source, ROOT / 'lib/astra/base/errors.astra', *links, '--link-library', 'pthread', '-o', product])
				e.run([product], stdout=expected, timeout=30)
				e.files(product)
			e.files(source)
	source = e.output / 'monitor-4-17.astra'
	for sanitizer in ['address', 'thread']:
		instrument(e, 'monitor-errors', [source, ROOT / 'lib/astra/base/errors.astra'], providers,
			'native threads: 4 simultaneous identities, 4 exact environment destructions\n', sanitizer)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'monitor-8-17.O2'],
		stdout='native threads: 8 simultaneous identities, 8 exact environment destructions\n', contains='ERROR SUMMARY: 0 errors', timeout=60)
	e.files(*providers, Path(__file__), here / 'sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
