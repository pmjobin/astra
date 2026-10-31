"""A93: executed nonescape/early-return and deliberately escaping ownership."""
from pathlib import Path
import re
import sys
import evidence as support


def main(compiler, output):
	e = support.Evidence(compiler, output, 'a93')
	source = support.ROOT/'examples/numerical-optimization-11/a93-packet.astra'
	oracle = Path(__file__).with_name('packet-oracle.c')
	e.inputs(source, oracle, Path(__file__))
	provider = e.output/'oracle.o'
	e.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-fast-math', '-fno-builtin', '-Wall', '-Wextra', '-Werror', '-c', oracle, '-o', provider])
	escaping = e.output/'escape.astra'
	text = source.read_text().replace('f64 transform_packet(int sequence,f64 sample){\n\towned Packet11 packet=new Packet11(sequence,sample);', 'owned Packet11 make_packet(int sequence,f64 sample){var packet=new Packet11(sequence,sample);return move packet;}\nf64 transform_packet(int sequence,f64 sample){\n\towned Packet11 packet=make_packet(sequence,sample);')
	assert text != source.read_text()
	escaping.write_text(text)
	data = []
	for variant, selected in [('local', source), ('escape', escaping)]:
		ssa = e.run([e.compiler, '--dump-ssa', selected], env={'ASTRA_EXPLAIN_OPTIMIZATIONS':'1'}).stdout
		assert ('stack-object' in ssa) == (variant == 'local')
		(e.output/f'{variant}.ssa').write_text(ssa)
		for level in (0, 1, 2):
			for mode in ('off', 'on'):
				env = {'ASTRA_TEST_OPTIMIZATIONS':mode}
				exe = e.output/f'{variant}-O{level}-{mode}'
				e.run([e.compiler, f'-O{level}', selected, '--link-object', provider, '-o', exe], env=env)
				binary = exe.with_suffix('.bin')
				result = e.run([exe], env={'ASTRA_NUMERICAL_OUTPUT':str(binary)}, contains='numerical:A93:48000 retired=48000')
				count = int(re.search(r'calloc=(\d+)', result.stdout)[1])
				assert count == (0 if mode == 'on' and variant == 'local' else 48000), result.stdout
				assert binary.stat().st_size == 48000*8
				data.append(binary.read_bytes())
				e.run(['valgrind', '--quiet', '--error-exitcode=91', '--leak-check=full', '--errors-for-leak-kinds=all', exe], contains='failed=0')
				ir = e.output/f'{variant}-O{level}-{mode}.ll'
				ir.write_text(e.run([e.compiler, '--dump-llvm', f'-O{level}', selected], env=env).stdout)
				assembly = exe.with_suffix('.asm'); assembly.write_text(e.run(['objdump','-dr',exe]).stdout)
				e.files(exe,binary,ir,assembly)
	assert all(value == data[0] for value in data)
	e.files(source,oracle,provider,escaping)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
