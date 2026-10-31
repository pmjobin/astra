# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact old-feature controls and measured record/provider object costs."""
from pathlib import Path
import json
import re
import sys

sys.dont_write_bytecode = True
from execute import ROOT, STAGES, run


sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
from output_paths import current_output

def object_row(name, obj, out):
	sizes = run(['size', '-A', obj]); symbols = run(['nm', '-u', obj])
	(out/(name+'.size')).write_text(sizes); (out/(name+'.undefined')).write_text(symbols)
	(out/(name+'.machine')).write_text(run(['objdump', '-dr', obj])); (out/(name+'.symbols')).write_text(run(['readelf', '-h', '-Ws', '-r', obj]))
	sections = {name: int(size) for name, size in re.findall(r'^(\.\S+)\s+(\d+)\s+\d+', sizes, re.M)}
	return dict(name=name, object=str(obj), sections=sections, code=sum(size for name, size in sections.items() if name.startswith('.text')), data=sum(size for name, size in sections.items() if name.startswith(('.data', '.rodata', '.bss'))), undefined=[line.split()[-1] for line in symbols.splitlines()])


def qualify(build, baseline, out):
	out.mkdir(parents=True, exist_ok=False); rows = []; controls = []
	sources = {'scalar': 'int f(int x){return x+1;}', 'struct': 'struct S{int x;f64 y;}S f(S value){S saved=value;return saved;}', 'numeric-buffer': 'owned f64[] f(int count){return new f64[count];}', 'text': 'int f(string value){return value.byte_length;}', 'diagnostic': 'void f(bool condition){assert_that(condition);}' }
	for name, source in sources.items():
		(out/(name+'.astra')).write_text(source+'\n')
		inputs = [name+'.astra', *([ROOT/'lib/astra/base/diagnostics.astra'] if name == 'diagnostic' else [])]
		for stage in STAGES:
			old = run([baseline/'astrac', '--dump-'+stage, *inputs], out); current = run([build/'astrac', '--dump-'+stage, *inputs], out)
			(out/(name+'.baseline.'+stage)).write_text(old); (out/(name+'.candidate.'+stage)).write_text(current); assert old == current, (name, stage)
			controls.append(name+':'+stage)
		ir = (out/(name+'.candidate.llvm')).read_text()
		if name in ['scalar', 'struct']:
			assert 'alloca' not in ir
			# Retain physical functions through optimization in this internal object seam.
		ir = re.sub(r'^define internal fastcc ', 'define fastcc ', ir, flags=re.M)
		for mode in ['O0', 'O2', 'fma', 'preserved']:
			stem = name+'-'+mode; inp, opt, obj = out/(stem+'-input.ll'), out/(stem+'.ll'), out/(stem+'.o')
			inp.write_text(re.sub(r'^define fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M) if mode == 'preserved' else ir)
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp.name, '-o', opt.name], out); run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), opt.name, '-o', obj.name], out)
			rows.append(object_row(stem, obj, out))
	evidence = build/'tests/struct-elem-1'
	for group, names, modes in [('machine', ['borrowed', 'call-entry'], ['O0', 'O2', 'preserved']), ('execution', ['matrix', 'compose', 'owned', 'mixed', 'mixed-leaves', 'identity', 'boundary'], ['O0', 'O2', 'O2-fma', 'preserved-O2'])]:
		for name in names:
			for mode in modes:
				stem = name+'-'+mode; rows.append(object_row(stem, current_output(evidence / group)/(stem+'.o'), out))
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		rows.append(object_row('client-'+mode, (current_output(evidence / 'client') / 'machine')/(mode+'.o'), out))
	for name in ['args-posix.o', 'text-posix.o', 'diagnostics-hosted.o', 'diagnostics-trap.o', 'failure-trap.o', 'failure-hosted.o']:
		rows.append(object_row('provider-'+name, build/'lib/astra'/name, out))
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		executable = (current_output(evidence / 'client') / 'machine')/(mode+'-gcc')
		(out/('client-'+mode+'.dynamic')).write_text(run(['readelf', '-d', executable]))
	(out/'results.json').write_text(json.dumps(dict(unchanged_controls=controls, objects=rows), indent='\t')+'\n')
	print(f'{len(controls)} exact baseline/candidate stage controls; {len(rows)} measured objects with actual sections/imports')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
