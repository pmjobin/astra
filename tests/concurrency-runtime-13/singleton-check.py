# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Process singleton racing first access, checked retry and anchor teardown."""
from pathlib import Path
import resource
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	e = Evidence(compiler, output, 'concurrency-singleton')
	here = Path(__file__).parent
	sources = [ROOT / 'lib/runtime/runtime' / (name + '-13.c') for name in ['threads', 'monitors', 'singletons']]
	sources += [here / 'thread-oracle.c', here / 'singleton-oracle.c']
	links = []
	for source in sources:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj])
		links += ['--link-object', obj]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / level
		e.run([e.compiler, '-' + level, here / 'singleton.astra', ROOT / 'lib/astra/base/errors.astra', *links, '--link-library', 'pthread', '-o', product])
		expected = 'singleton: failed initialization retried, one racing publication, quiescent shutdown\nnative threads: 4 simultaneous identities, 4 exact environment destructions\n'
		e.run([product], stdout=expected, timeout=30)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
		# These are source programs, not calls to a simulated registry. A fatal
		# contract violation must terminate promptly rather than wait on itself.
	for name, text in {
		'recursive': '[Shared,Monitor,Singleton]class Configuration{private int n;init(int n){this.n=n;var again=new Configuration(n);}int read(){return this.n;}}int main(){var root=new Configuration(7);return root.read();}',
		'closed': '[Shared,Monitor,Singleton]class Configuration{private int n;init(int n){this.n=n;}int read(){return this.n;}}int main(){var root=new Configuration(7);var retired=singleton_shutdown(root);release retired;release root;var again=new Configuration(9);return again.read();}',
	}.items():
		source = e.output / (name + '.astra'); source.write_text(text + '\n')
		for level in ['O0', 'O1', 'O2']:
			product = e.output / (name + '-' + level)
			e.run([e.compiler, '-' + level, source, *links, '--link-library', 'pthread', '-o', product])
			e.run([product], expected=-6, stdout='', timeout=5)
		e.files(source)
	refusals = {
		'scope': ('[Singleton]class Configuration{init(){}}int main(){return 0;}', 'process Singleton requires exact Shared, Monitor, Singleton'),
		'state': ('class Child{init(){}}[Shared,Monitor,Singleton]class Configuration{private owned Child child;init(){var c=new Child();this.child=move c;}}int main(){return 0;}', 'copied numeric state'),
		'suspension': ('[Monitor]class Counter{private int n;init(){this.n=0;}async int read()throws Error{await delay_ticks(1);return this.n;}}int main(){return 0;}', 'async methods and virtual async slots are excluded'),
	}
	for name, (text, diagnostic) in refusals.items():
		source = e.output / (name + '-refused.astra'); source.write_text(text + '\n')
		extra = [ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/async/virtual.astra'] if name == 'suspension' else []
		refusal = e.run([e.compiler, '--check', source, *extra], expected=1, contains=diagnostic)
		assert ': error:' in refusal.stderr and 'internal' not in refusal.stderr.lower()
		e.files(source)
	e.files(*sources, here / 'singleton.astra', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
