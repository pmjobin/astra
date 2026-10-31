# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact C float/double transport, separate compilation and retained machine evidence."""
from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/cabi-fp/fixtures'
CASES = ['cabi-f32-import', 'cabi-f32-export', 'cabi-f64-import', 'cabi-f64-export', 'cabi-fp-vapi', 'cabi-fp-mixed', 'cabi-fp-order', 'cabi-fp-trap', 'cabi-fp-trap-f32', 'cabi-fp-trap-f64', 'cabi-fp-struct-native', 'cabi-fp-arithmetic', 'cabi-fp-chain']
STAGES = ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'
PATTERNS = {
	'f32': ['00000000', '80000000', '00000001', '007fffff', '00800000', '3f800001', 'c0490fdb', '7f7fffff', '7f800000', 'ff800000', '7fc01234', 'ffc05678'],
	'f64': ['0000000000000000', '8000000000000000', '0000000000000001', '000fffffffffffff', '0010000000000000', '3ff0000000000001', 'c00921fb54442d18', '7fefffffffffffff', '7ff0000000000000', 'fff0000000000000', '7ff8000000001234', 'fff8000000005678'],
}


def run(args, trap=False, status=0):
	r = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert (r.returncode < 0 if trap else r.returncode == status), (args, r)
	if status == 0:
		assert r.stderr == '', (args, r.stderr)
	return r.stdout


def options(name):
	return ['--vapi', FIXTURES/'cabi-fp.vapi'] if name == 'cabi-fp-vapi' else []


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records = dict(runs=[], deterministic=[], machine=[], patterns=PATTERNS, process_arguments_excluded=True)
	companions = {}
	for mode in ['O0', 'O2']:
		for kind, macro in [('import', ''), ('f32', 'ASTRA_TEST_REVERSE32'), ('f64', 'ASTRA_TEST_REVERSE64'), ('chain', 'ASTRA_TEST_MIXED')]:
			obj = out/f'companion-{kind}-{mode}.o'
			run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-'+mode, '-fno-inline', *(['-D'+macro] if macro else []), '-c', ROOT/'tests/cabi-fp/companion.c', '-o', obj])
			companions[kind, mode] = obj
	for name in CASES:
		source = FIXTURES/(name+'.astra'); trap = '-trap' in name
		kind = 'f32' if name == 'cabi-f32-export' else 'f64' if name == 'cabi-f64-export' else 'chain' if name == 'cabi-fp-chain' else 'import'
		binary = out/(name+'-native')
		run([compiler, source, *options(name), '--link-object', companions[kind, 'O0'], '-o', binary])
		assert run([binary], trap=trap) == ''; records['runs'].append(name+'-native')
		stages = {stage: run([compiler, '--dump-'+stage, source, *options(name)]) for stage in STAGES}
		for stage, text in stages.items():
			(out/(name+'.'+stage)).write_text(text)
			assert text == run([compiler, '--dump-'+stage, source, *options(name)]), (name, stage)
			records['deterministic'].append(name+':'+stage)
		ir = stages['llvm']
		assert not re.search(FLAGS, ir) and not re.search(r'\b(?:fpext|fptrunc)\b|bitcast (?:double|float)\b|bitcast i(?:32|64) .* to (?:float|double)', ir), name
		assert not re.search(r'@(?:malloc|calloc|realloc|g_malloc)|readnone|readonly|memory\(none\)', ir), name
		assert '(c-abi scalar-fp-v2' in stages['cabi'], name
		if name.startswith('cabi-f32'):
			assert '(native-abi scalar-fp-v3' in stages['nabi'] and '(semantic f32) (c-type float)' in stages['cabi']
			assert 'declare float @c_echo32(float)' in ir and 'call float @c_echo32(float' in ir
		if name.startswith('cabi-f64'):
			assert '(native-abi fp64-v6' in stages['nabi'] and '(semantic f64) (c-type double)' in stages['cabi']
			assert 'declare double @c_echo(double)' in ir and 'call double @c_echo(double' in ir
		if name.endswith('-export'):
			assert ('define float @astra_echo32(float' if 'f32' in name else 'define double @astra_echo(double') in ir
		if name == 'cabi-fp-mixed':
			assert 'declare i32 @c_mix(i32, float, double, ptr, double, i32)' in ir
		if name == 'cabi-fp-struct-native':
			assert '(native-abi aggregate-v7' in stages['nabi'] and 'call float @c_echo32(float' in ir and 'call double @c_echo(double' in ir
		if name != 'cabi-fp-arithmetic':
			assert not re.search(r'\bf(?:add|sub|mul|div)\b', ir), name
		main_id = re.search(r'\(function #(\d+) "main" -> int', stages['ssa'])[1]
		wrapped = ir+'\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %r\n}\n'
		for mode in ['O0', 'O2', 'preserved-O2-fma']:
			prefix = out/(name+'-'+mode); inp = prefix.with_suffix('.input.ll'); ll = prefix.with_suffix('.ll'); obj = prefix.with_suffix('.o')
			text = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', wrapped, flags=re.M) if mode == 'preserved-O2-fma' else wrapped
			inp.write_text(text)
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', ll])
			run(['opt', '-passes=verify', '-disable-output', ll])
			optimized = ll.read_text(); assert not re.search(FLAGS, optimized), name
			assert not re.search(r'\b(?:fpext|fptrunc)\b|bitcast (?:double|float)\b|bitcast i(?:32|64) .* to (?:float|double)', optimized), name
			run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'preserved-O2-fma' else []), ll, '-o', obj])
			run(['cc', obj, companions[kind, 'O0' if mode == 'O0' else 'O2'], '-o', prefix])
			assert run([prefix], trap=trap) == ''; records['runs'].append(prefix.name)
			machine = run(['objdump', '-dr', obj]); prefix.with_suffix('.machine').write_text(machine)
			prefix.with_suffix('.symbols').write_text(run(['readelf', '-Ws', obj]))
			assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', machine), name
			records['machine'].append(prefix.name)
			if mode == 'preserved-O2-fma' and ('import' in name or 'export' in name or name in ['cabi-fp-mixed', 'cabi-fp-struct-native']):
				assert re.search(r'\b(?:call|jmp)\b', machine) and re.search(r'c_echo|c_mix', machine), name
		assert not re.search(r'libglib|libgobject|libLLVM', run(['ldd', binary]))
		# Public executable driver still requires exactly int main().
	for i, declaration in enumerate(['int main(int count,void* values){return 0;}', 'int main(int count){return 0;}', 'f64 main(){return 1.0;}', 'f32 main(){return 1.0;}']):
		source = out/f'bad-entry-{i}.astra'; source.write_text(declaration)
		run([compiler, source, '-o', out/'invalid-entry'], status=1)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; 12 patterns per width; both directions and chained mixed transport; {len(records['deterministic'])} fresh-process comparisons; {len(records['machine'])} machine audits")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
