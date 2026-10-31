"""A94: stream-block lazy metadata and observable/mutable counterexamples."""
from pathlib import Path
import re
import sys
import evidence as support


def main(compiler, output):
	e = support.Evidence(compiler, output, 'a94')
	source = support.ROOT/'examples/numerical-optimization-11/a94-metadata.astra'
	oracle = Path(__file__).with_name('metadata-oracle.c')
	e.inputs(source,oracle,Path(__file__))
	provider = e.output/'oracle.o'
	e.run(['clang','-std=c11','-O2','-ffp-contract=off','-fno-fast-math','-fno-builtin','-Wall','-Wextra','-Werror','-c',oracle,'-o',provider])
	text = source.read_text()
	mutated = e.output/'mutated.astra'; mutated.write_text(text.replace('f64 second=metadata.attenuation;', 'metadata.energy=energy+1.0;\n\tf64 second=metadata.attenuation;'))
	observed = e.output/'observed.astra'; observed.write_text('extern(C) void metadata_factory_event();\n'+text.replace('get { return 1.0/', 'get { metadata_factory_event(); return 1.0/'))
	outputs = {}
	for variant,selected,runenv in [('readonly',source,{}),('mutated',mutated,{'ASTRA_METADATA_MUTATED':'1'}),('observed',observed,{'ASTRA_EXPECT_FACTORIES':'1'})]:
		ssa = e.run([e.compiler,'--dump-ssa',selected], env={'ASTRA_EXPLAIN_OPTIMIZATIONS':'1'}).stdout
		assert ('stack-object' in ssa) == (variant == 'readonly')
		path = e.output/f'{variant}.ssa'; path.write_text(ssa); e.files(path)
		for level in (0,1,2):
			for mode in ('off','on'):
				env = {'ASTRA_TEST_OPTIMIZATIONS':mode}
				exe = e.output/f'{variant}-O{level}-{mode}'
				e.run([e.compiler,f'-O{level}',selected,'--link-object',provider,'-o',exe],env=env)
				binary = exe.with_suffix('.bin')
				result = e.run([exe],env=dict(runenv,ASTRA_NUMERICAL_OUTPUT=str(binary)),contains='numerical:A94:375')
				assert int(re.search(r'calloc=(\d+)',result.stdout)[1]) == (0 if variant == 'readonly' and mode == 'on' else 375)
				assert binary.stat().st_size == 375*8
				outputs.setdefault(variant,[]).append(binary.read_bytes())
				e.run(['valgrind','--quiet','--error-exitcode=91','--leak-check=full','--errors-for-leak-kinds=all',exe],env=runenv,contains='failed=0')
				ir = exe.with_suffix('.ll'); ir.write_text(e.run([e.compiler,'--dump-llvm',f'-O{level}',selected],env=env).stdout)
				assembly = exe.with_suffix('.asm'); assembly.write_text(e.run(['objdump','-dr',exe]).stdout)
				e.files(exe,binary,ir,assembly)
	for variant,values in outputs.items():
		assert all(value == values[0] for value in values), variant
	assert outputs['readonly'][0] == outputs['observed'][0]
	assert outputs['readonly'][0] != outputs['mutated'][0]
	e.files(source,oracle,provider,mutated,observed)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
