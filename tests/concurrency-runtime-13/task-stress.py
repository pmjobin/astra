# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Pool migration under parallel owning tasks, failures, cancellation and shutdown."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def batch(workers):
	lines = ['{']
	for i in range(workers):
		lines += [f'int id{i}=round_id*{workers}+{i+1};var w{i}=new Work(id{i});var t{i}=calculate(move w{i},seed);']
	for i in range(workers):
		lines += [f'start(t{i});']
		if i < workers - 1:
			lines += ['try{']
	for i in reversed(range(workers)):
		lines += ['{bool failed=false;int result=0;',
			f'try{{result=await move t{i};}}catch(Error error){{failed=true;task_stress_caught(id{i});}}',
			f'if(failed!=(id{i}%3==0)){{throw new Error("missing checked failure");}}',
			f'if(!failed && result!=id{i}*17+seed){{throw new Error("wrong result");}}', '}']
		if i > 0:
			lines += [f'}}catch(Error error){{await cancel_and_join(move t{i-1});throw;}}']
	return lines + ['}']


def program(template, workers, seed, rounds=4):
	lines = [template, 'async void batch_round(int round_id,int seed) throws Error{', *batch(workers), '}',
		'async void batch() throws Error{',
		f'for(int round_id=0;round_id<{rounds};round_id=round_id+1){{await batch_round(round_id,{seed});}}']
	last = workers * rounds
	lines += [f'var a=new Work({last+1});var active=pending(move a);start(active);',
		f'try{{while(task_stress_ready({last+1})==0){{await delay_ticks(1);}}}}catch(Error error){{await cancel_and_join(move active);throw;}}',
		'await cancel_and_join(move active);',
		f'var b=new Work({last+2});var cold=pending(move b);await cancel_and_join(move cold);', '}',
		f'int main(){{task_stress_prepare({workers},{rounds});try{{',
		f'{{var executor=ThreadedExecutor.open({workers});var status=executor.run(batch());',
		'match(status){case ThreadedStatus.Completed():{}else:{return 81;}}}',
		f'{{var executor=ThreadedExecutor.open({workers});var w=new Work({last+3});var root=pending(move w);executor.start(root);',
		f'for(int spins=0;spins<10000 && task_stress_ready({last+3})==0;spins=spins+1){{executor.pump(1);}}',
		'executor.begin_shutdown();task_stress_shutdown_released();var status=executor.run(move root);',
		'match(status){case ThreadedStatus.Cancelled():{}else:{return 83;}}}',
		f'}}catch(Error error){{return 84;}}return task_stress_finish({last+3});}}']
	return '\n'.join(lines) + '\n'


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-task-stress')
	here = Path(__file__).parent
	providers = [ROOT / 'lib/runtime/async/threaded.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'task-stress-oracle.c']
	common = [ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra']
	links = []
	for source in providers:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		links += ['--link-object', obj]
	for workers in [2, 4, 8]:
		for seed in [1, 17]:
			source = e.output / f'pool-{workers}-{seed}.astra'
			source.write_text(program((here / 'task-stress.astra').read_text(), workers, seed))
			expected = f'task stress: {workers} simultaneous workers, 4 migrated batches, checked errors, cold/active/shutdown cleanup\n'
			for level in ['O0', 'O1', 'O2']:
				product = source.with_suffix('.' + level)
				e.run([e.compiler, '-' + level, source, *common, *links, '--link-library', 'pthread', '-o', product])
				e.run([product], stdout=expected, timeout=45)
				e.files(product)
			e.files(source)
	source = e.output / 'pool-4-17.astra'
	expected = 'task stress: 4 simultaneous workers, 4 migrated batches, checked errors, cold/active/shutdown cleanup\n'
	for sanitizer in ['address', 'thread']:
		instrument(e, 'task-stress', [source, *common], providers, expected, sanitizer)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'pool-8-17.O2'],
		stdout='task stress: 8 simultaneous workers, 4 migrated batches, checked errors, cold/active/shutdown cleanup\n', contains='ERROR SUMMARY: 0 errors', timeout=60)
	e.files(*providers, *common, here / 'task-stress.astra', Path(__file__), here / 'sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
