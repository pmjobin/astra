"""A95: dynamic and exact dispatch, generic facts, Closure/Shared/Weak lifetime."""
from pathlib import Path
import sys
import evidence as support


def main(compiler, output):
	e = support.Evidence(compiler,output,'a95')
	source = support.ROOT/'examples/numerical-optimization-11/a95-pipeline.astra'
	oracle = Path(__file__).with_name('pipeline-oracle.c')
	e.inputs(source,oracle,Path(__file__))
	provider = e.output/'oracle.o'
	e.run(['clang','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',oracle,'-o',provider])
	ssa = e.run([e.compiler,'--dump-ssa',source],env={'ASTRA_EXPLAIN_OPTIMIZATIONS':'1'}).stdout
	assert '(exact-call function=#1 ' in ssa
	assert '(exact-call function=#2 ' not in ssa, 'runtime-selected interface argument must stay dynamic'
	assert ssa.count('(shared-elision ') == 1, 'observed/field-based clones must retain balancing operations'
	path = e.output/'pipeline.ssa'; path.write_text(ssa); e.files(path)
	values = []
	for level in (0,1,2):
		for mode in ('off','on'):
			env = {'ASTRA_TEST_OPTIMIZATIONS':mode}
			exe = e.output/f'a95-O{level}-{mode}'
			e.run([e.compiler,f'-O{level}',source,'--link-object',provider,'-o',exe],env=env)
			binary = exe.with_suffix('.bin')
			e.run([exe],env={'ASTRA_NUMERICAL_OUTPUT':str(binary)},contains='numerical:A95:12000 created=1 destroyed=1 failed=0')
			assert binary.stat().st_size == 12000*4
			values.append(binary.read_bytes())
			e.run(['valgrind','--quiet','--error-exitcode=91','--leak-check=full','--errors-for-leak-kinds=all',exe],contains='failed=0')
			ir = exe.with_suffix('.ll'); ir.write_text(e.run([e.compiler,'--dump-llvm',f'-O{level}',source],env=env).stdout)
			assembly = exe.with_suffix('.asm'); assembly.write_text(e.run(['objdump','-dr',exe]).stdout)
			e.files(exe,binary,ir,assembly)
	assert all(value == values[0] for value in values)
	bad = e.output/'use-after-release.astra'; bad.write_text(source.read_text().replace('release function;','release function;\n\tint invalid=closure_invoke(function,1);'))
	e.run([e.compiler,'-c',bad,'-o',e.output/'bad.o'],expected=1,contains='after')
	assert not (e.output/'bad.o').exists()
	e.files(source,oracle,provider,bad)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
