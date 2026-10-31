# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise numeric/bool Actor channels, with independent C bit/value checks."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def program():
	cases = [('i8', '-128'), ('u8', '255'), ('i16', '-32768'), ('u16', '65535'),
		('int', '-2147483648'), ('u32', '4294967295'), ('i64', '-9223372036854775808'),
		('u64', '18446744073709551615'), ('isize', '-9223372036854775808'),
		('usize', '18446744073709551615'), ('bool', 'true'), ('f32', '-0.0'), ('f64', '-1.25')]
	lines = ['extern(C) int actor_scalar_signed(int id,i64 value);',
		'extern(C) int actor_scalar_unsigned(int id,u64 value);',
		'extern(C) int actor_scalar_float(int id,f64 value);',
		'extern(C) int actor_scalar_wait(int id);extern(C) int actor_scalar_drop();extern(C) int actor_scalar_finish();',
		'[Actor]class Inbox{init(){}deinit(){actor_scalar_drop();}}']
	for i, (kind, literal) in enumerate(cases):
		if kind == 'bool':
			expression = f'if(value){{return actor_scalar_signed({i},1);}}return actor_scalar_signed({i},0);'
		else:
			family, cast = ('float', 'f64') if kind in ('f32', 'f64') else ('unsigned', 'u64') if kind in ('u32', 'u64', 'usize') else ('signed', 'i64')
			expression = f'return actor_scalar_{family}({i},value as {cast});' if kind != cast else f'return actor_scalar_{family}({i},value);'
		lines += [f'int handler{i}(borrowed Inbox inbox,{kind} value){{{expression}}}']
	lines += ['int main(){try{']
	for i, (kind, literal) in enumerate(cases):
		lines += [f'{{var inbox=new Inbox();var sender=actor_bind(move inbox,handler{i},2,"actor-scalars");',
			f'{kind} message={literal};actor_send(sender,message);actor_scalar_wait({i});actor_shutdown(sender);}}']
	lines += ['}catch(Error error){return 81;}return actor_scalar_finish();}']
	return '\n'.join(lines) + '\n'


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-actor-scalars')
	here = Path(__file__).parent
	providers = [ROOT / 'lib/runtime/runtime/actors-13.c', here / 'actor-scalars-oracle.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
	source = e.output / 'scalars.astra'
	source.write_text(program())
	astra = [source, ROOT / 'lib/astra/base/errors.astra']
	expected = 'native Actor scalars: 13 exact numeric/bool types, signed zero, 64-bit extrema, joined cleanup\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / level
		e.run([e.compiler, '-' + level, *astra, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=30)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'scalars', astra, providers, expected, sanitizer)
	e.files(*astra, *providers, Path(__file__), here / 'sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
