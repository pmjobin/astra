# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Force cancel-before-timer admission; retain a timeout fault control."""
from pathlib import Path
import runpy
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-task-cancel-control')
	here = Path(__file__).parent
	generate = runpy.run_path(str(here / 'task-stress.py'))['program']
	source = e.output / 'cancel-before-timer.astra'
	text = generate((here / 'task-stress.astra').read_text(), 2, 1)
	source.write_text(text.replace('int main(){', 'export(C) int run_task_stress(){') + '\nint main(){return run_task_stress();}\n')
	obj = e.output / 'source.o'
	e.run([e.compiler, '-O2', '-c', source, ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra', '-o', obj])
	runtime = ROOT / 'lib/runtime/async/threaded.c'
	entry = e.output / 'entry.c'
	entry.write_text('extern int run_task_stress(void);int main(void){return run_task_stress();}\n')
	providers = [ROOT / 'lib/runtime/platform/text-posix.c', here / 'task-stress-oracle.c', entry]
	flags = ['-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread']
	product = e.output / 'restored'
	e.run(['cc', *flags, obj, runtime, *providers, '-o', product])
	expected = 'task stress: 2 simultaneous workers, 4 migrated batches, checked errors, cold/active/shutdown cleanup\n'
	for _ in range(100):
		e.run([product], stdout=expected, timeout=10)
	worker = runtime.parent / 'worker17.c'
	text = worker.read_text()
	wakeup = '\t\tif (task->cancellation) {\n\t\t\tregistration(task)->timer = 0;\n\t\t\tschedule(task);\n\t\t}'
	assert text.count(wakeup) == 1
	mutant_root = e.output / 'lost-cancellation-runtime'; mutant_root.mkdir(exist_ok=True)
	closure = ['threaded.c', 'task-core17.c', 'worker17.c', 'task-api17.c', 'virtual.h', 'provider.h']
	for name in closure: shutil.copyfile(runtime.parent / name, mutant_root / name)
	(mutant_root / 'worker17.c').write_text(text.replace(wakeup, ''))
	mutant = mutant_root / 'threaded.c'
	fault = e.output / 'mutant'
	e.run(['cc', *flags, '-I' + str(runtime.parent), obj, mutant, *providers, '-o', fault])
	e.run(['timeout', '3', fault], expected=124, stdout='', timeout=10)
	e.run([product], stdout=expected, timeout=10)
	e.files(source, obj, *[runtime.parent / name for name in closure], *providers, *[mutant_root / name for name in closure], Path(__file__), here / 'task-stress.py', here / 'task-stress.astra')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
