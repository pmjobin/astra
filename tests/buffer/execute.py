# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact owner traces, traps, O0/O2/FMA execution and retained machine evidence."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/buffer/fixtures'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
CASES = {
	'basic': 'A1:3:8 F1',
	'zero': '',
	'move': 'A1:3:8 F1',
	'replace': 'A1:3:8 A2:4:8 F1 A3:5:8 F2 F3',
	'borrow': 'A1:4:8 F1',
	'param': 'A1:3:8 A2:5:8 F1 F2',
	'result': 'A1:5:8 F1',
	'forward': 'A1:5:8 F1',
	'field': 'A1:4:8 A2:5:8 F1 A3:3:8 F2 F3',
	'field-mixed': 'R+1 A1:2:8 R+3 A2:4:4 M2 M4 F2 R-3 F1 R-1',
	'deinit': 'A1:1:8 M1 A2:2:8 F1 A3:3:8 F2 A4:4:8 F3 M4 F4',
	'scalars': 'A1:3:4 A2:3:8 A3:3:1 A4:3:8 F4 F3 F2 F1',
	'integer': 'A1:3:1 A2:3:1 A3:3:2 A4:3:2 A5:3:4 A6:3:4 F6 F5 F4 F3 F2 F1',
	'vector': 'A1:3:2 A2:3:16 A3:3:16 A4:3:2 F4 F3 F2 F1',
	'object-result': 'A1:9:8 F1',
	'generic-owner': 'A1:9:8 F1',
	'cad': 'A1:11:8 A2:11:8 F2 F1',
	'resource-replace': 'R+1 R+2 R-1 R+3 R-2 R+4 R-3 R+5 R-4 R+6 R-5 R-6 R+7 R+8 R-7 R-8 R+9 R-9',
	'alias': 'A1:3:8 A2:5:8 F1 F2',
	'field-move': 'A1:3:8 A2:5:8 F1 F2',
	'branch-replace': 'A1:2:4 A2:3:4 F1 F2 A3:2:4 F3 A4:3:4 F4 R+1 R+2 R-1 R-2 R+3 R-3 R+4 R-4',
	'rearm-result': 'A1:3:4 F1',
	'rearm': 'A1:2:4 A2:3:4 F2 A3:1:4 A4:2:4 F3 F1 F4',
	'param-move': 'A1:3:4 A2:4:4 F1 F2 A3:5:4 A4:6:4 F4 F3',
	'release': 'A1:3:4 F1 A2:4:4 A3:5:4 F2 A4:6:4 F4 F3',
	'mixed-call': 'A1:4:8 A2:2:4 A3:3:8 R+1 A4:1:8 M10 M20 M50 F3 M99 F4 R-1 F2 F1',
	'empty-field': 'A1:3:4 F1',
	'argument-trap': 'A1:3:4 M0',
	'resource-local-trap': 'R+1 M0',
	'bounds-lower': 'A1:3:8 M-1',
	'bounds-upper': 'A1:3:8 M3',
	'bounds-zero': '',
	'negative-count': 'M-1',
	'oom': 'OOM',
	'replace-trap': 'A1:3:8 OOM',
	'field-trap': 'A1:3:8 OOM',
	'deinit-trap': 'A1:3:8 A2:5:8 F1 M0',
	'constructor-trap': 'A1:3:8 M0',
	'null-allocation': '',
	'null-result': '',
	'null-receiver': 'A1:5:8',
	'resource-trap': 'R+1 M0',
}
TRAPS = {'bounds-lower', 'bounds-upper', 'bounds-zero', 'negative-count', 'oom', 'replace-trap', 'field-trap', 'deinit-trap', 'constructor-trap', 'null-receiver', 'null-allocation', 'null-result', 'resource-trap', 'resource-local-trap', 'argument-trap'}


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (list(map(str, argv)), result.returncode, result.stdout, result.stderr, output)
	return result.stdout


def identity_harness(name, ir, ssa):
	functions = re.findall(r'\t\(function #(\d+) "([^"]+)"[^\n]*\n(.*?)(?=\n\t\)|\Z)', ssa, re.S)
	ids = {label: number for number, label, body in functions}
	if name == 'forward':
		return ir+f'''
declare i32 @bb_live()
define i32 @main() {{
	%made = call fastcc {{ ptr, i32 }} @astra.fn.{ids['again']}(i32 5)
	%before = extractvalue {{ ptr, i32 }} %made, 0
	%length = extractvalue {{ ptr, i32 }} %made, 1
	%last = getelementptr double, ptr %before, i32 4
	store double 8.5, ptr %last
	%once = call fastcc {{ ptr, i32 }} @astra.fn.{ids['relay']}(ptr %before, i32 %length)
	%middle = extractvalue {{ ptr, i32 }} %once, 0
	%middle.length = extractvalue {{ ptr, i32 }} %once, 1
	%twice = call fastcc {{ ptr, i32 }} @astra.fn.{ids['relay']}(ptr %middle, i32 %middle.length)
	%after = extractvalue {{ ptr, i32 }} %twice, 0
	%after.length = extractvalue {{ ptr, i32 }} %twice, 1
	%last.after = getelementptr double, ptr %after, i32 4
	%value = load double, ptr %last.after
	%count = call i32 @bb_live()
	%a = icmp eq ptr %before, %middle
	%b = icmp eq ptr %middle, %after
	%c = icmp eq i32 %after.length, 5
	%d = icmp eq i32 %count, 1
	%e = fcmp oeq double %value, 8.5
	%ab = and i1 %a, %b
	%cd = and i1 %c, %d
	%abcd = and i1 %ab, %cd
	%ok = and i1 %abcd, %e
	call void @free(ptr %after) nobuiltin
	%result = select i1 %ok, i32 0, i32 1
	ret i32 %result
}}
'''
	if name == 'generic-owner':
		relay = next(number for number, label, body in functions if label.startswith('astra.gen.') and '(ownership-return %0)' in body)
		recursive = next(number for number, label, body in functions if label.startswith('astra.gen.') and '"depth"' in body)
		drop = next(number for number, label, body in functions if label.startswith('astra.gen.') and '(cleanup %0 via' in body)
		factory = f"@astra.fn.{ids['factory']}(ptr %storage)"
		forward = f'%final = call fastcc ptr @astra.fn.{recursive}(ptr %unused, i32 9, ptr %relayed)'
		cleanup = f'call fastcc void @astra.fn.{drop}(ptr %final)'
	else:
		relay = ids['relay']; factory = f"@astra.fn.{ids['forward']}(ptr %storage, i32 9)"
		forward = '%final = getelementptr i8, ptr %relayed, i64 0'; cleanup = 'call fastcc void @astra.dtor.0(ptr %final)'
	return ir+f'''
declare i32 @bb_live()
define i32 @main() {{
	%storage = alloca %astra.class.0, align 8
	%unused = alloca %astra.class.0, align 8
	store {{ ptr, i32 }} zeroinitializer, ptr %unused
	%fresh = call fastcc ptr {factory}
	%before = load {{ ptr, i32 }}, ptr %fresh
	%before.base = extractvalue {{ ptr, i32 }} %before, 0
	%before.length = extractvalue {{ ptr, i32 }} %before, 1
	%relayed = call fastcc ptr @astra.fn.{relay}(ptr %unused, ptr %fresh)
	{forward}
	%after = load {{ ptr, i32 }}, ptr %final
	%after.base = extractvalue {{ ptr, i32 }} %after, 0
	%after.length = extractvalue {{ ptr, i32 }} %after, 1
	%candidate = load ptr, ptr %unused
	%count = call i32 @bb_live()
	%fresh.exact = icmp eq ptr %fresh, %storage
	%relay.exact = icmp eq ptr %relayed, %fresh
	%recursive.exact = icmp eq ptr %final, %fresh
	%base.exact = icmp eq ptr %after.base, %before.base
	%length.exact = icmp eq i32 %after.length, %before.length
	%length.nine = icmp eq i32 %after.length, 9
	%candidate.unused = icmp eq ptr %candidate, null
	%one.live = icmp eq i32 %count, 1
	%a = and i1 %fresh.exact, %relay.exact
	%b = and i1 %recursive.exact, %base.exact
	%c = and i1 %length.exact, %length.nine
	%d = and i1 %candidate.unused, %one.live
	%ab = and i1 %a, %b
	%cd = and i1 %c, %d
	%ok = and i1 %ab, %cd
	{cleanup}
	%left = call i32 @bb_live()
	%empty = icmp eq i32 %left, 0
	%all = and i1 %ok, %empty
	%result = select i1 %all, i32 0, i32 1
	ret i32 %result
}}
'''


def execute_ir(out, companion, records, name, wrapped, status, trace):
	for mode in ['O0', 'O2', 'callable-O2-fma']:
		stem = name+'-'+mode
		input_ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', wrapped, flags=re.M) if mode == 'callable-O2-fma' else wrapped
		inp = out/(stem+'-input.ll'); inp.write_text(input_ir)
		path = out/(stem+'.ll'); obj = out/(stem+'.o'); exe = out/stem
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', path])
		run(['opt', '-passes=verify', '-disable-output', path])
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'callable-O2-fma' else []), path, '-o', obj])
		run(['cc', obj, companion, '-Wl,--wrap=calloc,--wrap=free', '-o', exe]); run([exe], status, trace)
		machine = run(['objdump', '-dr', obj]); (out/(stem+'.machine')).write_text(machine)
		assert not re.search(r'\b(?:memcpy|memmove|realloc|malloc)\b', machine), stem
		(out/(stem+'.symbols')).write_text(run(['readelf', '-h', '-Ws', obj]))
		records['machine'].append(stem); records['runs'].append(dict(name=stem, status=status, output=trace))


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/buffer/companion.c', '-o', companion])
	records = dict(runs=[], deterministic=[], machine=[])
	for name, events in CASES.items():
		source = FIXTURES/('buffer-'+name+'.astra')
		status = -signal.SIGILL if name in TRAPS else 0
		trace = ''.join(event+'\n' for event in events.split())
		dumps = {}
		for stage in STAGES:
			args = [compiler, '--dump-'+stage, source] + ([] if stage == 'syntax' else ['--vapi', FIXTURES/'runtime.vapi'])
			text = run(args)
			assert text == run(args), (name, stage, 'fresh-process nondeterminism')
			(out/(name+'.'+stage)).write_text(text); dumps[stage] = text
			records['deterministic'].append(name+':'+stage)
		ir = dumps['llvm']
		assert not re.search(r'llvm\.mem(?:cpy|move)|\b(?:malloc|realloc|atexit|landingpad|personality|invoke)\b', ir), name
		if name not in {'resource-replace', 'resource-trap', 'resource-local-trap'}:
			assert 'native-buffer-deallocate' in dumps['core'] and 'calloc' not in dumps['core'] and 'free' not in dumps['core']
			assert 'llvm.umul.with.overflow.i64' in ir and 'nobuiltin' in ir
		main_id = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapped = ir+'\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		execute_ir(out, companion, records, name, wrapped, status, trace)
	for name in ['forward', 'object-result', 'generic-owner']:
		execute_ir(out, companion, records, name+'-identity', identity_harness(name, (out/(name+'.llvm')).read_text(), (out/(name+'.ssa')).read_text()), 0, 'A1:5:8\nF1\n' if name == 'forward' else 'A1:9:8\nF1\n')
	overflow = run([compiler.parent/'tests/buffer/astra-buffer-llvm', '--dump-overflow'])
	(out/'overflow.llvm').write_text(overflow)
	execute_ir(out, companion, records, 'overflow', overflow, -signal.SIGILL, '')
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} exact executions; {len(records['machine'])} machine audits; {len(records['deterministic'])} repeated-process stage comparisons")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
