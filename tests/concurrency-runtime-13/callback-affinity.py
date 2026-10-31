# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact C callback entry and confinement for local versus transferable captures."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-callback-affinity')
	here = Path(__file__).parent
	astra = [here / 'callback-affinity.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/runtime/threads-13.c', ROOT / 'lib/runtime/runtime/monitors-13.c', here / 'callback-affinity-oracle.c']
	flags = ['-Wl,--wrap=astra_thread_register', '-Wl,--wrap=astra_thread_retire']
	expected = 'C callback boundary: four retained contexts, foreign worker entry, caught native error, joined retirement; local ThreadBound callback preserved\n'
	entry = e.output / 'entry.c'
	entry.write_text('extern int run_callback_affinity(void);int main(void){return run_callback_affinity();}\n')
	source = e.output / 'callback.astra'
	source.write_text(astra[0].read_text().replace('int main() {', 'export(C) int run_callback_affinity() {') + '\nint main(){return run_callback_affinity();}\n')
	astra = [source, *astra[1:]]
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / (level + '.o'); product = e.output / level
		e.run([e.compiler, '-' + level, '-c', *astra, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, entry, *flags, '-o', product])
		e.run([product], stdout=expected, timeout=20)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'callback', astra, providers, expected, sanitizer, flags)
	local = '[ThreadBound]class Local{private int value;init(){this.value=7;}int read(){return this.value;}}'
	direct = local + 'int event(borrowed Local env,int n){return env.read()+n;}'
	nested = local + 'class Env{owned Local child;init(owned Local child){this.child=move child;}}int inspect(borrowed Local child){return child.read();}int event(borrowed Env env,int n){return inspect(env.child)+n;}'
	for name, prefix, creation in [('direct', direct, 'var env=new Local();'), ('nested', nested, 'var child=new Local();var env=new Env(move child);')]:
		for operation, binding, diagnostic in [('thread', 'thread_bind', 'Send environment'), ('retained', 'closure_bind', 'retained callback cannot capture thread-bound state')]:
			negative = e.output / (name + '-' + operation + '.astra')
			tail = 'return retained_register(f,0);' if operation == 'retained' else 'return 0;'
			negative.write_text(prefix + 'int main(){' + creation + f'var f={binding}(move env,event);' + tail + '}\n')
			refusal = e.run([e.compiler, '--check', negative], expected=1, contains=diagnostic)
			assert ': error:' in refusal.stderr and 'internal' not in refusal.stderr.lower()
			e.files(negative)
	e.files(*astra, *providers, Path(__file__), entry, here / 'callback-affinity.astra')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
