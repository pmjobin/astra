# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Distinct monitor locks progress concurrently; unsafe nesting/views are refused."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-monitor-pair')
	here = Path(__file__).parent
	astra = [here / 'monitor-pair.astra']
	providers = [ROOT / 'lib/runtime/runtime/threads-13.c', ROOT / 'lib/runtime/runtime/monitors-13.c', here / 'thread-oracle.c', here / 'monitor-pair-oracle.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
	expected = 'native threads: 4 simultaneous identities, 4 exact environment destructions\nmonitors: two independently progressing protected objects, exact counters and cleanup\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / level
		e.run([e.compiler, '-' + level, *astra, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=20)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'monitor-pair', astra, providers, expected, sanitizer)
	refusals = {
		'nested-order': ('[Monitor]class Counter{private int n;init(){this.n=0;}int add(){this.n=this.n+1;return this.n;}int transfer(Counter peer){return peer.add();}}int main(){return 0;}', 'cross-object monitor nesting requires a qualified ordered-lock operation'),
		'public-state': ('[Monitor]class Counter{int n;init(){this.n=0;}}int main(){return 0;}', 'private'),
		'escaped-view': ('class Child{init(){}}[Monitor]class Counter{private owned Child child;init(){var child=new Child();this.child=move child;}property borrowed Child view{get{return this.child;}}}int main(){return 0;}', 'Monitor property cannot expose a protected borrow'),
	}
	for name, (text, diagnostic) in refusals.items():
		source = e.output / (name + '.astra'); source.write_text(text + '\n')
		refusal = e.run([e.compiler, '--check', source], expected=1, contains=diagnostic)
		assert ': error:' in refusal.stderr and 'internal' not in refusal.stderr.lower()
		e.files(source)
	e.files(*astra, *providers, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
