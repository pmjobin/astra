# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public FP policy checks with independent strict C arithmetic and receipts."""
from pathlib import Path
import re
import json
import sys

import evidence as support
ROOT = support.ROOT


def main(compiler, output):
	e = support.Evidence(compiler, output, 'policies')
	base = ROOT/'tests/numerical-optimization-11'
	provider = e.output/'floating-oracle.o'
	e.inputs(base/'floating-oracle.c',ROOT/'examples/numerical-optimization-11/a92-policies.astra',Path(__file__))
	e.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror', '-c', base/'floating-oracle.c', '-o', provider])
	source = ROOT/'examples/numerical-optimization-11/a92-policies.astra'
	for stage in ('semantics', 'core', 'cfg', 'ssa', 'nabi'):
		text = e.run([e.compiler, '--dump-'+stage, source]).stdout
		assert 'floating-policy permissions=' in text, stage
		(e.output/('policies.'+stage)).write_text(text)
	for level in (0, 1, 2):
		exe = e.output/f'policies-O{level}'
		e.run([e.compiler, f'-O{level}', source, '--link-object', provider, '--link-library', 'm', '-o', exe])
		metrics=e.output/f'policies-O{level}-errors.json'
		e.run([exe], stdout='floating-oracle:7435 observations\n',env={'ASTRA_FP_METRICS':str(metrics)})
		assert sum(row['count'] for row in json.loads(metrics.read_text())['modes'])==7435
		e.files(metrics)
		text = e.run([e.compiler, '--dump-llvm', f'-O{level}', source]).stdout
		assert not re.search(r'\b(?:fast|afn)\b', text)
		if level == 0:
			for flag in ('contract', 'reassoc', 'arcp', 'nnan', 'ninf', 'nsz'):
				assert re.search(r'\b'+flag+r'\b', text), flag
		(e.output/f'policies-O{level}.ll').write_text(text)
		(e.output/f'policies-O{level}.asm').write_text(e.run(['objdump', '-dr', exe]).stdout)
		e.run(['valgrind', '--quiet', '--error-exitcode=91', '--leak-check=full', exe], stdout='floating-oracle:7435 observations\n')
		e.files(exe)
		# Feature-tuned audit is separate from public default-CPU compilation.
	fma_source=base/'fma.astra'
	e.inputs(fma_source)
	cpu=Path('/proc/cpuinfo').read_text()
	assert ' fma ' in cpu and ' avx ' in cpu
	ssa=e.run([e.compiler,'--dump-ssa',fma_source]).stdout
	ordinal=re.search(r'\(function #(\d+) "main"',ssa).group(1)
	raw=e.output/'fma-input.ll';optimized=e.output/'fma-optimized.ll';obj=e.output/'fma.o';exe=e.output/'fma-audit'
	text=e.run([e.compiler,'--dump-llvm','-O0',fma_source]).stdout
	text+='\ndeclare i32 @fp_require_fused(i32)\ndefine i32 @main(){\n%app=call fastcc i32 @astra.fn.'+ordinal+'()\n%fused=call i32 @fp_require_fused(i32 1)\n%result=or i32 %app,%fused\nret i32 %result\n}\n'
	raw.write_text(text)
	e.run(['opt','-passes=default<O2>','-S',raw,'-o',optimized])
	e.run(['opt','-passes=verify','-disable-output',optimized])
	e.run(['llc','-O2','-mattr=+avx,+fma','-filetype=obj','-relocation-model=pic',optimized,'-o',obj])
	assembly=e.run(['objdump','-dr',obj]).stdout
	assert re.search(r'\bv(?:fmadd|fmsub|fnmadd|fnmsub)',assembly)
	(e.output/'fma.asm').write_text(assembly)
	e.run(['clang',obj,provider,'-lm','-o',exe])
	fused_metrics=e.output/'fma-errors.json'
	e.run([exe],stdout='floating-oracle:4 observations\nfused-contraction-observed\n',env={'ASTRA_FP_METRICS':str(fused_metrics)})
	assert json.loads(fused_metrics.read_text())['fused_observations']>=1
	e.files(fused_metrics)
	e.run(['valgrind','--quiet','--error-exitcode=91','--leak-check=full',exe],stdout='floating-oracle:4 observations\nfused-contraction-observed\n')
	e.files(raw,optimized,obj,exe,e.output/'fma.asm')
	for name, annotation, signature, message in [
		('unknown', 'unknown="on"', 'f64 f(f64 a){return a+a;}', 'unknown FloatingPoint'),
		('value', 'contract="maybe"', 'f64 f(f64 a){return a+a;}', 'unknown FloatingPoint'),
		('duplicate', 'contract="on",contract="off"', 'f64 f(f64 a){return a+a;}', 'duplicate'),
		('strict', 'strict="on",contract="on"', 'f64 f(f64 a){return a+a;}', 'cannot combine strict'),
		('conflict', 'finite="on",no_nan="off"', 'f64 f(f64 a){return a+a;}', 'conflicting FloatingPoint'),
		('integer', 'contract="on"', 'int f(int a){return a+a;}', 'floating signature'),
		('foreign', 'contract="on"', 'extern(C) f64 f(f64 a);', 'native free function'),
	]:
		bad, product = e.output/(name+'.astra'), e.output/(name+'.o')
		bad.write_text('[FloatingPoint('+annotation+')]\n'+signature+'\n')
		e.run([e.compiler, '-c', bad, '-o', product], expected=1, contains=message)
		assert not product.exists()
	for i, value in enumerate(('0.0/0.0', '1.0/0.0', '1.0e300', '0.0')):
		bad, product = e.output/f'domain-{i}.astra', e.output/f'domain-{i}'
		bad.write_text('[FloatingPoint(finite="on")]\nf64 f(f64 x){return 1.0/x;}\nint main(){f64 x=f('+value+');if(x==0.0){return 1;}return 0;}\n')
		e.run([e.compiler, bad, '-o', product])
		r = e.run([product], expected=-4)
		assert not r.stdout
	e.files(source, base/'floating-oracle.c', provider)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
