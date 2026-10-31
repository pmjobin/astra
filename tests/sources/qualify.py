# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Multi-source canonical stages, all 120 CAD permutations, and native behavior."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path('tests/sources/fixtures')
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
CASES = {
	'simple': '', 'recursion': '', 'structs': '', 'objects': 'M10', 'generics': '',
	'ownership': 'R+1 A1:3:8 M1 R-1 R+2 F1 R-2 R+3 R-3',
	'cad': 'A1:4:8 A2:4:8 F2 F1', 'foreign': '',
	'partition': 'R+1 A1:3:8 M6 M6 F1 M2 R-1 R+2 A2:1:8 F2 R-2',
}


def run(argv, output=None, cwd=ROOT):
	p = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert p.returncode == 0 and not p.stderr and (output is None or p.stdout == output), (argv, p.returncode, p.stdout, p.stderr, output)
	return p.stdout


def inputs(name):
	return sorted((FIXTURES/name).glob('*.astra'))


def vapi(name, stage):
	return ['--vapi', 'tests/param-borrow/fixtures/runtime.vapi'] if name in ['objects', 'ownership', 'partition'] and stage != 'syntax' else []


def dump(compiler, name, stage, paths=None):
	return run([compiler, '--dump-'+stage, *(inputs(name) if paths is None else paths), *vapi(name, stage)])


def machine(ir, name, mode, out, companion, expected):
	inp = out/(name+'-'+mode+'-input.ll'); inp.write_text(ir)
	optimized = out/(name+'-'+mode+'.ll'); obj = out/(name+'-'+mode+'.o'); exe = out/(name+'-'+mode)
	run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', optimized])
	run(['opt', '-passes=verify', '-disable-output', optimized])
	run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), optimized, '-o', obj])
	if name.startswith('simple'):
		assert run(['nm', '-u', obj]) == '', 'freestanding program acquired runtime symbols'
	run(['cc', obj, companion, *([out/'exports.o'] if name.startswith('foreign') else []), '-Wl,--wrap=calloc,--wrap=free', '-o', exe])
	run([exe], expected)
	assembly = run(['objdump', '-dr', obj]).split('Disassembly of section', 1)[1]
	(out/(name+'-'+mode+'.machine')).write_text(assembly)
	return assembly


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'; run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/sources/companion.c', '-o', companion])
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/sources/exports.c', '-o', out/'exports.o'])
	records = dict(stages=[], permutations=[], partition=[], runs=[], machine_pairs=[], goldens=[])
	for name, events in CASES.items():
		dumps = {}
		for stage in STAGES:
			data = dump(compiler, name, stage)
			assert data == dump(compiler, name, stage), (name, stage, 'fresh-process determinism')
			(out/(name+'.'+stage)).write_text(data)
			records['stages'].append(dict(name=name, stage=stage, sha256=hashlib.sha256(data.encode()).hexdigest()))
			dumps[stage] = data
			golden = ROOT/'tests/sources/goldens'/(name+('.ll' if stage == 'llvm' else '.'+stage))
			if golden.exists():
				assert data == golden.read_text(), (name, stage, 'golden changed')
				records['goldens'].append(str(golden.relative_to(ROOT)))
			if name == 'partition' and stage != 'syntax':
				control = run([compiler, '--dump-'+stage, 'tests/param-borrow/fixtures/param-borrow-owned-control.astra', *vapi(name, stage)])
				assert data == control, (stage, 'mechanical partition changed program')
				records['partition'].append(stage)
				# Both syntax boundaries and all post-syntax stages are exhaustive for CAD.
		orders = itertools.permutations(inputs(name)) if name in ['cad', 'generics'] else [tuple(reversed(inputs(name)))]
		for order in orders:
			for stage in STAGES:
				assert dump(compiler, name, stage, order) == dumps[stage], (name, stage, order)
			records['permutations'].append(dict(name=name, order=[str(p) for p in order], stages=len(STAGES)))
		if name == 'generics':
			assert dumps['instances'].count('(generic-instance #') == 3
			assert '(origin #0 "identity") (type-arguments int) (requests 2)' in dumps['instances']
			assert dumps['instances'].count('(generic-struct-instance #') == 1
			assert '(application Box<f64>) (concrete-struct #0) (state COMPLETE) (requests 2)' in dumps['instances']
			assert len(re.findall(r'^define ', dumps['llvm'], re.M)) == 6
		assert '.astra' not in dumps['llvm'] and 'source_filename = "astra.scalar"' in dumps['llvm']
		main_id = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapper = '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		trace = ''.join(event+'\n' for event in events.split())
		for mode in ['O0', 'O2', 'fma']:
			first = machine(dumps['llvm']+wrapper, name, mode, out, companion, trace)
			second = machine(dump(compiler, name, 'llvm', reversed(inputs(name)))+wrapper, name+'-reversed', mode, out, companion, trace)
			assert first == second, (name, mode, 'instructions or relocations depend on CLI order')
			records['runs'] += [name+'-'+mode, name+'-reversed-'+mode]
			records['machine_pairs'].append(name+':'+mode)
			# Driver linking cannot request allocator wrapping; a plain freestanding
			# source set exercises executable production without the trace companion.
	for name in ['simple', 'cad', 'foreign']:
		exe = out/(name+'-cli'); run([compiler, *inputs(name), *(['--link-object', out/'exports.o'] if name == 'foreign' else []), '-o', exe]); run([exe], '')
		# Direct caller-provided ObjectStorage identity across context/factory/use.
	ir = (out/'objects.llvm').read_text(); ssa = (out/'objects.ssa').read_text()
	ids = {name: number for number, name in re.findall(r'\(function #(\d+) "([^"]+)"', ssa)}
	harness = f'''
define i32 @main() {{
	%storage = alloca %astra.class.0, align 8
	%result = call fastcc ptr @astra.fn.{ids['make']}(ptr %storage, i32 7)
	%same = icmp eq ptr %result, %storage
	%status = call fastcc i32 @astra.fn.{ids['inspect']}(ptr %result)
	%value = load i32, ptr %storage
	%mutated = icmp eq i32 %value, 8
	%success = icmp eq i32 %status, 8
	%a = and i1 %same, %mutated
	%ok = and i1 %a, %success
	%exit = select i1 %ok, i32 0, i32 1
	call fastcc void @astra.dtor.0(ptr %storage)
	ret i32 %exit
}}
'''
	for mode in ['O0', 'O2', 'fma']:
		machine(ir+harness, 'object-storage-identity', mode, out, companion, 'M8\n'); records['runs'].append('object-storage-identity-'+mode)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(json.dumps({key: len(value) for key, value in records.items()}))


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
