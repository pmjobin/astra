# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Selected emitted carrier costs; no whole-program zero-overhead claim."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	def run(argv):
		p = subprocess.run(list(map(str, argv)), capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		assert p.returncode == 0 and not p.stderr, (argv, p)
		return p.stdout
	sources = [ROOT / 'examples/enums' / name for name in ('types.astra','validate.astra','policy.astra','main.astra')]
	ir = run([compiler, '--dump-llvm', *sources]); ssa = run([compiler, '--dump-ssa', *sources])
	ordinal = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
	carrier_rows = [line.strip() for line in ir.splitlines() if 'alloca' in line and 'sum.slot' in line]
	counts = dict(stack_carrier_allocations=len(carrier_rows), all_store_instructions=len(re.findall(r'^\s*store ', ir, re.M)), complete_copies=len(re.findall(r'call void @llvm.memcpy', ir)), initialized_carriers=len(re.findall(r'call void @llvm.memset', ir)), tag_dispatches=len(re.findall(r'^\s*switch i32', ir, re.M)), native_calls=len(re.findall(r'call fastcc', ir)))
	assert counts['stack_carrier_allocations'] and counts['complete_copies'] and counts['tag_dispatches']
	ir += '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.' + ordinal + '()\n\tret i32 %r\n}\n'
	rows = []
	for mode in ('O0','O2','preserved-O2'):
		inp, final, obj, exe = [out / (mode + suffix) for suffix in ('-input.ll','.ll','.o','')]
		selected = re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M) if mode=='preserved-O2' else ir
		inp.write_text(selected)
		if mode=='O0':
			final.write_text(selected)
		else:
			run(['opt','-passes=default<O2>','-S',inp,'-o',final])
		run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',final,'-o',obj]); run(['cc',obj,'-o',exe]); assert not run([exe])
		machine = run(['objdump','-dr',obj]); (out / (mode + '.machine.txt')).write_text(machine)
		rows.append(dict(mode=mode, object_bytes=obj.stat().st_size, executable_bytes=exe.stat().st_size, sections=run(['size',obj]), undefined_symbols=run(['nm','-u',obj]), materialized_carriers=final.read_text().count('alloca'), memcpy_calls=len(re.findall(r'call.*@llvm.memcpy',final.read_text())), machine_calls=len(re.findall(r'\bcall',machine)), stack_instructions=[line.strip() for line in machine.splitlines() if re.search(r'\b(push|pop|sub.*%rsp|add.*%rsp)',line)]))
	assert all(not re.search(r'\b(malloc|calloc|realloc|free)\b',row['undefined_symbols']) for row in rows)
	(out / 'results.json').write_text(json.dumps(dict(source_counts=counts, carrier_allocations=carrier_rows, modes=rows, scope='Static instructions and selected target frames; no universal stack, runtime-copy-frequency, C-layout or zero-overhead claim.'),indent='\t') + '\n')
	print(json.dumps(counts))


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
