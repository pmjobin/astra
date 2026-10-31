# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real compiler-owned thread carriers; explicit source and native ABI refusals."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-thread-carriers')
	sources = Path(__file__).parent
	runtime = ROOT / 'lib/runtime/runtime/threads-13.c'
	provider = e.output / 'provider.o'
	e.run(['clang', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
		'-pedantic', '-pthread', '-c', runtime, '-o', provider])
	for level in ['O0', 'O1', 'O2']:
		product = e.output / level
		e.run([e.compiler, '-' + level, sources / 'threads.astra',
			'--link-object', provider, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout='', timeout=20)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99',
		'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
		e.output / 'O2'], stdout='', contains='ERROR SUMMARY: 0 errors')

	prefix = 'class E{int n;init(){this.n=1;}}int run(borrowed E e,int n){return e.n+n;}'
	refusals = {
		'thread-bound': ('[ThreadBound]' + prefix + 'int main(){var e=new E();var t=thread_bind(move e,run);return 0;}', 'Send environment'),
		'local-borrow': (prefix + 'int main(){var e=E.init();var t=thread_bind(move e,run);return 0;}', 'independently heap-allocated'),
		'direct-invoke': (prefix + 'int main(){var e=new E();var t=thread_bind(move e,run);return closure_invoke(t,1);}', 'live exact typed closure'),
		'wrong-provider': (prefix + 'int main(){var e=new E();var t=thread_bind(move e,run);return retained_register(t,0);}', 'live exact owned or borrowed'),
		'ordinary-closure': (prefix + 'int main(){var e=new E();var t=closure_bind(move e,run);return thread_start(t,0);}', 'live exact owned or borrowed'),
		'copy-handle': (prefix + 'int main(){var e=new E();var t=thread_bind(move e,run);var copy=t;return 0;}', 'cannot be copied'),
	}
	for name, (text, diagnostic) in refusals.items():
		source = e.output / (name + '.astra')
		source.write_text(text + '\n')
		e.run([e.compiler, '--check', source], expected=1, contains=diagnostic)
	e.files(runtime, runtime.with_suffix('.h'), sources / 'threads.astra', provider, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
