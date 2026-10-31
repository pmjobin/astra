# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public refusal controls for the selected storage and failure contracts."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence

REGION = '[Allocator(kind="region",domain="negative",capacity="128",blocks="4")]'
BOX = 'class Box{int value;init(int value){this.value=value;}deinit(){}}'


def main(compiler, output):
	e = Evidence(compiler, output, 'allocation-refusals')
	cases = {
		'try-default': (BOX + 'int main(){var b=try_new Box(1);return 0;}', 'explicit checked allocation policy'),
		'bad-alignment': ('[Align(bytes="3")]' + BOX + 'int main(){return 0;}', 'supported power of two'),
		'huge-alignment': ('[Align(bytes="8192")]' + BOX + 'int main(){return 0;}', 'supported power of two'),
		'negative-budget': (REGION.replace('"128"', '"-1"') + BOX + 'int main(){return 0;}', 'unsigned decimal'),
		'pool-stride': (REGION.replace('"region"', '"pool"').replace('"128"', '"120"') + BOX + 'int main(){return 0;}', 'invalid allocator'),
		'static-slots': (REGION.replace('"region"', '"static"') + BOX + 'int main(){return 0;}', 'invalid allocator'),
		'static-zero-slots': (REGION.replace('"region"', '"static"').replace('"4"', '"0"') + BOX + 'int main(){return 0;}', 'invalid allocator'),
		'custom-same-hooks': ('[Allocator(kind="custom",capacity="128",blocks="4",allocate="same",release="same")]' + BOX + 'int main(){return 0;}', 'invalid allocator'),
		'conflicting-domain': (REGION + BOX + REGION.replace('"128"', '"256"') + BOX.replace('Box', 'Other') + 'int main(){return 0;}', 'conflicting allocator'),
		'custom-missing-code': ('[Allocator(kind="custom",capacity="128",blocks="4",allocate="place",release="retire")]' + BOX + 'int main(){return 0;}', 'exact native C exports'),
		'reserved-provider': ('extern(C) int astra_alloc12_release();int main(){return 0;}', 'compiler-private allocation'),
		'repr-class': ('[Repr(layout="C")]' + BOX + 'int main(){return 0;}', 'native Class layout'),
		'repr-bool': ('[Repr(layout="C")]struct Wire{bool b;}int main(){return 0;}', 'natural scalar POD'),
		'repr-pointer': ('[Repr(layout="C")]struct Wire{void* p;}int main(){return 0;}', 'natural scalar POD'),
		'repr-overalignment': ('[Repr(layout="C")][Align(bytes="16")]struct Wire{i64 value;}int main(){return 0;}', 'natural C alignment'),
		'align-record-alone': ('[Align(bytes="8")]struct Wire{i64 value;}int main(){return 0;}', 'Align alone'),
		'borrow-escape': (REGION + BOX + 'owned Box escape(borrowed Box b){return move b;}int main(){return 0;}', 'nontransferable'),
		'lexical-escape': (REGION + BOX + 'owned Box escape(){Box b=Box.init(1);return move b;}int main(){return 0;}', 'nontransferable'),
		'use-after-move': (REGION + BOX + 'int main(){var a=new Box(1);var b=move a;return a.value;}', 'moved'),
		'nullable-nonnull': (REGION + BOX + 'int main(){owned nonnull Box b=try_new Box(1);return b.value;}', 'current non-null proof'),
	}
	for name, (source, diagnostic) in cases.items():
		fixture = e.output / (name + '.astra')
		fixture.write_text(source + '\n')
		result = e.run([e.compiler, '--dump-ssa', fixture], expected=1, contains=diagnostic)
		assert 'internal error' not in result.stderr.lower()
		e.files(fixture)
		# Approved M17 migration: this exact historical program now has a checked
		# caller-preserving admission contract. Keep all other refusal cases intact.
	positive = e.output / 'try-owned-input.astra'
	positive.write_text(BOX + REGION + 'class Holder{owned Box child;init(owned Box child){this.child=move child;}}int main(){var b=new Box(1);var h=try_new Holder(move b);return 0;}\n')
	e.run([e.compiler, '--dump-ssa', positive], contains='fallible-input-restore')
	links = []
	for name in ['allocation-12', 'allocation-12-host']:
		provider = ROOT / 'lib/runtime/runtime' / (name + '.c'); obj = e.output / (name + '.o')
		e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', provider, '-o', obj]); links += ['--link-object', obj]; e.files(provider, obj)
	for level in [0, 2]:
		product = e.output / ('try-owned-input-O' + str(level))
		e.run([e.compiler, '-O' + str(level), positive, *links, '-o', product]); e.run([product], stdout=''); e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'try-owned-input-O2'], stdout='', contains='ERROR SUMMARY: 0 errors')
	e.files(positive)
	unused = e.output / 'unused-policy.astra'
	unused.write_text(REGION + BOX + 'int main(){return 42;}\n')
	for level in (0, 2):
		ir = e.run([e.compiler, f'-O{level}', '--dump-llvm', unused]).stdout
		assert 'astra_alloc12_' not in ir, 'an unused policy must add no allocation runtime or domain storage'
		product = e.output / f'unused-policy-O{level}'
		e.run([e.compiler, f'-O{level}', unused, '-o', product])
		e.run([product], expected=42, stdout='')
		symbols = e.run(['nm', product]).stdout
		assert 'astra_alloc12_' not in symbols
		e.files(product)
	e.files(unused)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
