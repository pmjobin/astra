# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit/inferred canonical stage equivalence and independent runtime effects."""
from pathlib import Path
import hashlib
import json
import itertools
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/gen-infer/fixtures'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
CASES = {
	'basic': '', 'f32': '', 'f64': '', 'bool': '', 'vector': '', 'mask': '', 'pointer': '', 'multi': '', 'capabilities': '',
	'nested': '', 'literals': '', 'outer': '', 'outer-capabilities': '', 'owned-resource': 'R+1 R-1', 'owned-class': 'M7',
	'outer-owned': 'R+1 R-1 M8', 'recursive': '', 'method-property': '', 'flow': 'R+1 R-1 M9 R+2 R+3 R-3 R-2 R+4 R+5 R-4 R-5',
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
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/gen-infer/companion.c', '-o', companion])
	records = dict(runs=[], pairs=[], deterministic=[], machine_pairs=[], permutations=[], freestanding=[])
	for name, events in CASES.items():
		trace = ''.join(event+'\n' for event in events.split())
		dumps = {}
		for stage in STAGES:
			pair = []
			for prefix in ['gen-infer', 'explicit']:
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
		assert not re.search(r'TypeVariable|InferredGenericType|GenericCallInference|generic-args-origin', dumps['core']+dumps['cfg']+dumps['ssa'])
		if name == 'literals':
			assert '0x3FF0000000000001' in dumps['llvm'] and '0x3ff0000000000001' in dumps['semantics']
		main_id = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapper = '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		for prefix in ['gen-infer', 'explicit']:
			execute((out/(prefix+'-'+name+'.llvm')).read_text()+wrapper, prefix+'-'+name, out, companion, trace, records)
		for mode in ['O0', 'O2', 'fma']:
			# ELF metadata contains the file name. Disassembled instructions and
			# relocations after the objdump header are the comparison authority.
			machines = [(out/(prefix+'-'+name+'-'+mode+'.machine')).read_text().split('Disassembly of section', 1)[1] for prefix in ['gen-infer', 'explicit']]
			assert machines[0] == machines[1], (name, mode, 'machine equivalence')
			records['machine_pairs'].append(name+':'+mode)
			# The existing GEN-OWN ABI returns the transferred pointer, even when the
			# caller also supplies unused candidate storage. Observe exact storage identity.
	ir = (out/'gen-infer-owned-class.llvm').read_text()
	ssa = (out/'gen-infer-owned-class.ssa').read_text()
	ids = {name: number for number, name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
	harness = f'''
define i32 @main() {{
	%source = alloca %astra.class.0, align 8
	%candidate = alloca %astra.class.0, align 8
	store i32 7, ptr %source
	%result = call fastcc ptr @astra.fn.{ids['forward']}(ptr %candidate, ptr %source)
	%same = icmp eq ptr %result, %source
	%exit = select i1 %same, i32 0, i32 1
	call fastcc void @astra.dtor.0(ptr %result)
	ret i32 %exit
}}
'''
	execute(ir+harness, 'object-storage-identity', out, companion, 'M7\n', records)
	for name in ['gen-infer-multisource', 'outer-multisource']:
		paths = sorted((FIXTURES/name).glob('*.astra'))
		dumps = {stage: run([compiler,'--dump-'+stage,*paths]) for stage in STAGES}
		for stage,data in dumps.items():
			(out/(name+'.'+stage)).write_text(data)
		for order in itertools.permutations(paths):
			for stage,data in dumps.items():
				assert data == run([compiler,'--dump-'+stage,*order]), (name,stage,order)
			records['permutations'].append(dict(name=name,order=[p.name for p in order],stages=len(STAGES)))
		instances = dumps['instances']
		assert len(re.findall(r'\(origin #\d+ "identity"\) \(type-arguments int\)', instances)) == 1, instances
		assert re.search(r'\(origin #\d+ "identity"\) \(type-arguments int\) \(requests 2\)', instances), instances
		if name == 'gen-infer-multisource':
			assert instances.count('(generic-instance #') == 1
			# Moving every file to another directory must not alter semantic keys.
		moved = out/(name+'-relocated'); moved.mkdir(exist_ok=True)
		for path in paths:
			(moved/path.name).write_text(path.read_text())
		for stage in STAGES[1:]:
			assert dumps[stage] == run([compiler,'--dump-'+stage,*sorted(moved.glob('*.astra'))]), (name,stage,'path entered identity')
	paths = sorted((FIXTURES/'freestanding').glob('*.astra'))
	ir = run([compiler,'--dump-llvm',*paths]); ssa=run([compiler,'--dump-ssa',*paths])
	main_id=re.search(r'\(function #(\d+) "main" -> int',ssa)[1]
	wrapper='\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
	execute(ir+wrapper, 'freestanding', out, companion, '', records)
	for mode in ['O0','O2','fma']:
		assert run(['nm','-u',out/('freestanding-'+mode+'.o')]) == ''
		records['freestanding'].append(mode)
	run([compiler,*paths,'-o',out/'freestanding-cli']); run([out/'freestanding-cli'],'')
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} exact executions; {len(records['pairs'])} stage pairs; {len(records['deterministic'])} fresh-process comparisons; {len(records['machine_pairs'])} machine pairs")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
