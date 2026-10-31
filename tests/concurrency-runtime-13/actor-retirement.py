# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent cancellation/shutdown witness and deterministic omitted-wait fault."""
from pathlib import Path
import signal
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-actor-retirement')
	here = Path(__file__).parent
	runtime = ROOT / 'lib/runtime/runtime/actors-13.c'
	witness = here / 'actor-retirement.c'
	flags = ['-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-Wl,--wrap=pthread_cond_wait']
	expected = 'Actor runtime supplement: shutdown waits for concurrent queued-message retirement\n'
	for sanitizer in [None, 'address,undefined', 'thread']:
		product = e.output / (sanitizer or 'plain')
		extra = ['-fsanitize=' + sanitizer] if sanitizer else []
		e.run(['clang', *flags, *extra, runtime, witness, '-o', product])
		e.run([product], stdout=expected, timeout=20)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'plain'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=30)
	text = runtime.read_text()
	wait = '\twhile (actor->retiring)\n\t\trequire(pthread_cond_wait(&actor->changed, &actor->lock) == 0);'
	assert text.count(wait) == 1
	mutant = e.output / 'omitted-retirement-wait.c'
	mutant.write_text(text.replace(wait, ''))
	product = e.output / 'mutant'
	e.run(['clang', *flags, '-I' + str(runtime.parent), mutant, witness, '-o', product])
	e.run([product], expected=-signal.SIGABRT, contains='drops[1]', timeout=20)
	e.files(runtime, runtime.with_suffix('.h'), witness, mutant, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
