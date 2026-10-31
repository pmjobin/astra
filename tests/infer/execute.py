# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit/inferred canonical stage equivalence and independent runtime effects."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/infer/fixtures'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
CASES = {
	'scalars': '', 'literals': '', 'conversions': '', 'pointers': '', 'vectors': '', 'structs': '', 'generic-struct': '', 'generic-result': '',
	'resource': 'R+1 R+2 R-1 M2 R-2 R+3 R-3', 'object': 'M9', 'constructor': 'M4', 'generic-owner': 'R+1 M2 R-1',
	'buffer': 'A1:3:8 A2:4:8 F1 A3:2:8 M2 F3 F2 A4:1:8 F4', 'move': 'A1:3:8 R+1 R-1 F1',
	'property-method': '', 'foreign': '', 'slice-loop': '', 'cad': 'A1:3:8 F1',
}


def run(argv, output=None):
	p = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert p.returncode == 0 and not p.stderr and (output is None or p.stdout == output), (argv, p.returncode, p.stdout, p.stderr, output)
	return p.stdout


def execute(ir, stem, out, companion, trace, records):
	for mode in ['O0', 'O2', 'fma']:
		name = stem+'-'+mode
		inp = out/(name+'-input.ll'); inp.write_text(ir)
		optimized = out/(name+'.ll'); obj = out/(name+'.o'); exe = out/name
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), optimized, '-o', obj])
		run(['cc', obj, companion, '-Wl,--wrap=calloc,--wrap=free', '-o', exe])
		run([exe], trace)
		machine = run(['objdump', '-dr', obj]); (out/(name+'.machine')).write_text(machine)
		records['runs'].append(dict(name=name, status=0, trace=trace))


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/infer/companion.c', '-o', companion])
	records = dict(runs=[], pairs=[], deterministic=[], machine_pairs=[])
	for name, events in CASES.items():
		trace = ''.join(event+'\n' for event in events.split())
		dumps = {}
		for stage in STAGES:
			pair = []
			for prefix in ['infer', 'explicit']:
				args = [compiler, '--dump-'+stage, FIXTURES/(prefix+'-'+name+'.astra')] + ([] if stage == 'syntax' else ['--vapi', FIXTURES/'runtime.vapi'])
				text = run(args)
				assert text == run(args), (name, stage, prefix, 'fresh-process determinism')
				(out/(prefix+'-'+name+'.'+stage)).write_text(text)
				pair.append(text)
				records['deterministic'].append(prefix+'-'+name+':'+stage)
			if stage != 'syntax':
				assert pair[0] == pair[1], (name, stage, 'explicit/inferred equivalence')
				records['pairs'].append(dict(name=name, stage=stage, sha256=hashlib.sha256(pair[0].encode()).hexdigest()))
			dumps[stage] = pair[0]
		assert not re.search(r'VarType|AutoType|InferredType|inferred-local', dumps['core']+dumps['cfg']+dumps['ssa'])
		if name == 'buffer':
			assert 'native-buffer-deallocate' in dumps['core'] and 'buffer-v8' in dumps['nabi']
		if name == 'literals':
			assert '0x3FF0000000000001' in dumps['llvm'] and '0x3ff0000000000001' in dumps['semantics']
		main_id = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapper = '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		for prefix in ['infer', 'explicit']:
			execute((out/(prefix+'-'+name+'.llvm')).read_text()+wrapper, prefix+'-'+name, out, companion, trace, records)
		for mode in ['O0', 'O2', 'fma']:
			# ELF metadata contains the file name. Disassembled instructions and
			# relocations after the objdump header are the comparison authority.
			machines = [(out/(prefix+'-'+name+'-'+mode+'.machine')).read_text().split('Disassembly of section', 1)[1] for prefix in ['infer', 'explicit']]
			assert machines[0] == machines[1], (name, mode, 'machine equivalence')
			records['machine_pairs'].append(name+':'+mode)
			# This caller owns the storage whose address make_image must return. The
			# inferred owner inside inspect must mutate precisely those same bytes.
	ir = (out/'infer-object.llvm').read_text()
	ssa = (out/'infer-object.ssa').read_text()
	ids = {name: number for number, name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
	harness = f'''
define i32 @main() {{
	%storage = alloca %astra.class.0, align 8
	%result = call fastcc ptr @astra.fn.{ids['make_image']}(ptr %storage, i32 7)
	%same = icmp eq ptr %result, %storage
	%status = call fastcc i32 @astra.fn.{ids['inspect']}(ptr %result)
	%value = load i32, ptr %storage
	%mutated = icmp eq i32 %value, 9
	%success = icmp eq i32 %status, 0
	%a = and i1 %same, %mutated
	%ok = and i1 %a, %success
	%exit = select i1 %ok, i32 0, i32 1
	ret i32 %exit
}}
'''
	execute(ir+harness, 'object-storage-identity', out, companion, 'M9\n', records)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} exact executions; {len(records['pairs'])} stage pairs; {len(records['deterministic'])} fresh-process comparisons; {len(records['machine_pairs'])} machine pairs")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
