# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import sys
from support import Evidence, ROOT

ARENA_INPUTS = ['--vapi', ROOT/'lib/bindings/memory/packet-resource.vapi', ROOT/'lib/astra/base/errors.astra',
	ROOT/'lib/astra/memory/byte-arena.astra', ROOT/'lib/astra/memory/packet-arena.astra',
	ROOT/'examples/systems-dsp-9/packet-api.astra']


def main(compiler, output):
	e = Evidence(compiler, output, 'arena')
	provider = e.output/'packet-provider.o'
	e.run(['clang', '-D_GNU_SOURCE', '-std=c11', '-Wall', '-Wextra', '-Werror', '-g', '-c', ROOT/'examples/systems-dsp-9/packet-provider.c', '-o', provider])
	observer = e.output/'allocation-observer.o'
	e.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-g', '-c', ROOT/'tests/systems-dsp-9/allocation-observer.c', '-o', observer])
	for app, expected in [('a68-packet-queue.astra', 'packets:8 closed:8\n'), ('a70-stream.astra', 'packets:1 closed:1\n')]:
		for level in (0, 1, 2):
			exe = e.output/(app.removesuffix('.astra')+f'-O{level}')
			obj = e.output/(app.removesuffix('.astra')+f'-O{level}.o')
			e.run([e.compiler, f'-O{level}', '--entry-object', *ARENA_INPUTS, ROOT/'examples/systems-dsp-9'/app, '-o', obj])
			e.run(['clang', obj, provider, observer, '-Wl,--wrap=malloc,--wrap=calloc,--wrap=realloc', '-o', exe])
			e.run([exe], stdout=expected)
			if level in (0, 2):
				e.run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', exe], stdout=expected, contains='All heap blocks were freed')
			libraries = e.run(['readelf', '-d', exe]).stdout
			assert not any(name in libraries for name in ['libglib', 'libgobject', 'liburing', 'libLLVM'])
			e.files(exe)
			if level == 2:
				sanitized = e.output/(app.removesuffix('.astra')+'-asan')
				e.run(['clang', '-D_GNU_SOURCE', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', obj,
					ROOT/'examples/systems-dsp-9/packet-provider.c', ROOT/'tests/systems-dsp-9/allocation-observer.c',
					'-Wl,--wrap=malloc,--wrap=calloc,--wrap=realloc', '-o', sanitized])
				e.run([sanitized], stdout=expected, env=dict(ASAN_OPTIONS='detect_leaks=1:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1'))
				e.files(sanitized)
	for level in (0, 2):
		exe = e.output/f'typed-fields-O{level}'
		e.run([e.compiler, f'-O{level}', ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/memory/byte-arena.astra', ROOT/'tests/systems-dsp-9/arena-typed.astra', '-o', exe])
		e.run([exe], stdout='')
		e.files(exe)
		# Same typed definitions and application through a reversed public source list.
	exe = e.output/'a68-reversed'
	e.run([e.compiler, '-O2', '--entry-object', *ARENA_INPUTS[:2], ROOT/'examples/systems-dsp-9/a68-packet-queue.astra', *reversed(ARENA_INPUTS[2:]), '-o', e.output/'reversed.o'])
	e.run(['clang', e.output/'reversed.o', provider, observer, '-Wl,--wrap=malloc,--wrap=calloc,--wrap=realloc', '-o', exe])
	e.run([exe], stdout='packets:8 closed:8\n')
	# Independent runtime guard corruption: the original rejects an unaligned
	# typed field before writing any byte; the mutant must fail the application.
	mutant = e.output/'byte-arena-no-typed-guard.astra'
	text = (ROOT/'lib/astra/memory/byte-arena.astra').read_text()
	condition = 'if (index < 0 || index % width != 0 || this.starts[slot] % width != 0 || this.sizes[slot] < width || index > this.sizes[slot] - width)'
	assert text.count(condition) == 1
	mutant.write_text(text.replace(condition, 'if (false)'))
	exe = e.output/'typed-guard-mutant'
	e.run([e.compiler, '-O2', ROOT/'lib/astra/base/errors.astra', mutant, ROOT/'tests/systems-dsp-9/arena-typed.astra', '-o', exe])
	e.run([exe], expected=4, stdout='')
	e.run([e.output/'typed-fields-O2'], stdout='')
	for name, text, message in [
		('copy-resource', 'int main(){owned PacketResource r=packet_open(1);owned PacketResource copy=r;return 0;}', 'owned'),
		('private-escape', 'int main(){try{var a=packet_arena(8);var p=a.storage;return 0;}catch(ArenaError e){return 1;}}', 'private'),
		('moved-arena', 'void consume(owned PacketArena a){} int main(){try{var a=packet_arena(8);consume(move a);return a.count();}catch(ArenaError e){return 1;}}', 'moved'),
		('wrong-record', 'struct Wrong{u64 tag;}int main(){try{var a=packet_arena(8);Wrong p={tag=1};owned PacketResource r=packet_open(1);a.append(p,move r);return 0;}catch(ArenaError e){return 1;}}', 'ArenaPacket'),
	]:
		bad, product = e.output/(name+'.astra'), e.output/(name+'.o')
		bad.write_text(text+'\n')
		e.run([e.compiler, '-c', *ARENA_INPUTS, bad, '-o', product], expected=1, contains=message)
		assert not product.exists()
	bad = e.output/'a70-missing-explicit-conversion.astra'
	bad.write_text((ROOT/'examples/systems-dsp-9/a70-stream.astra').read_text().replace('clipped[0] as u32', 'clipped[0]'))
	product = e.output/'a70-invalid.o'
	e.run([e.compiler, '-c', *ARENA_INPUTS, bad, '-o', product], expected=1, contains='exact u32 or u64')
	assert not product.exists()
	e.files(*[p for p in ARENA_INPUTS if not str(p).startswith('--')], ROOT/'examples/systems-dsp-9/a68-packet-queue.astra', ROOT/'examples/systems-dsp-9/a70-stream.astra', ROOT/'examples/systems-dsp-9/packet-provider.c')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
