# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Owned field release traces, trap prefixes, optimization and machine evidence."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/own-field/fixtures'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
CASES = {
	'basic': '+1 -1',
	'multi': '+1 +2 +3 -3 -2 -1',
	'deinit': '+1 +2 D3 -2 -1',
	'borrow': '+1 -1',
	'replace': '+1 +2 -1 +3 -2 -3',
	'null': '+0 +1 +0 -1',
	'direct': '+1 -1 +0',
	'result': '+1 -1',
	'generic': '+1 +2 -1 -2',
	'alias': '+1 +2 -1 -2',
	'deinit-replace': '+1 D1 +2 -1 +3 -2 +4 -3 D4 -4',
	'deinit-trap': '+1 +2 -1 D0',
	'rhs-trap': '+1 D0',
	'receiver-trap': '',
	'receiver-move-trap': '+1',
	'constructor-trap': '+1 D0',
	'null-object': '',
	'branch': '+1 +2 -2 -1',
	'reentrant': '+1 +2 -1 +3 -2 -3',
}


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (list(map(str, argv)), result.returncode, result.stdout, result.stderr, output)
	return result.stdout


def identity_harness(name, ir, ssa):
	# Test-only native fastcc caller: retain a pointer for identity observations
	# without extending Astra's restrictions on borrows across owner transfer.
	functions = re.findall(r'\t\(function #(\d+) "([^"]+)"[^\n]*\n(.*?)(?=\n\t\)|\Z)', ssa, re.S)
	ids = {label: number for number, label, body in functions}
	factory = ids['factory' if name == 'generic' else 'forward']
	if name == 'generic':
		relay = next(number for number, label, body in functions if label.startswith('astra.gen.') and '(ownership-return %0)' in body)
		recursive = next(number for number, label, body in functions if label.startswith('astra.gen.') and '"depth"' in body)
		drop = next(number for number, label, body in functions if label.startswith('astra.gen.') and '(cleanup %0 via' in body)
		forward = f'%final = call fastcc ptr @astra.fn.{recursive}(ptr %unused, i32 9, ptr %relayed)'
		cleanup = f'call fastcc void @astra.fn.{drop}(ptr %final)'
	else:
		relay = ids['relay']
		forward = '%final = getelementptr i8, ptr %relayed, i64 0'
		cleanup = 'call fastcc void @astra.dtor.0(ptr %final)'
	wrapper = f"""
define i32 @main() {{
	%storage = alloca %astra.class.0, align 8
	%unused = alloca %astra.class.0, align 8
	store ptr null, ptr %unused, align 8
	%fresh = call fastcc ptr @astra.fn.{factory}(ptr %storage)
	%before = load ptr, ptr %fresh, align 8
	%relayed = call fastcc ptr @astra.fn.{relay}(ptr %unused, ptr %fresh)
	{forward}
	%after = load ptr, ptr %final, align 8
	%candidate = load ptr, ptr %unused, align 8
	%count = call i32 @of_live()
	%fresh.exact = icmp eq ptr %fresh, %storage
	%relay.exact = icmp eq ptr %relayed, %fresh
	%recursive.exact = icmp eq ptr %final, %fresh
	%handle.exact = icmp eq ptr %after, %before
	%candidate.unused = icmp eq ptr %candidate, null
	%one.live = icmp eq i32 %count, 1
	%a = and i1 %fresh.exact, %relay.exact
	%b = and i1 %recursive.exact, %handle.exact
	%c = and i1 %candidate.unused, %one.live
	%d = and i1 %a, %b
	%ok = and i1 %c, %d
	{cleanup}
	%left = call i32 @of_live()
	%empty = icmp eq i32 %left, 0
	%all = and i1 %ok, %empty
	%result = select i1 %all, i32 42, i32 1
	ret i32 %result
}}
"""
	return ir+wrapper


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', '-c', ROOT/'tests/own-field/companion.c', '-o', companion])
	records = dict(runs=[], deterministic=[], machine=[])
	for name, events in CASES.items():
		status = -signal.SIGILL if name.endswith('trap') else 42
		stdout = ''.join(event+'\n' for event in events.split())
		source = FIXTURES/f'own-field-{name}.astra'
		options = ['--vapi', FIXTURES/'resources.vapi']
		run([compiler, source, *options, '--link-object', companion, '-o', out/name])
		run([out/name], status, stdout)
		records['runs'].append(dict(name=name, status=status, output=stdout))
		dumps = {}
		for stage in STAGES:
			text = run([compiler, '--dump-'+stage, source, *([] if stage == 'syntax' else options)])
			assert text == run([compiler, '--dump-'+stage, source, *([] if stage == 'syntax' else options)])
			(out/(name+'.'+stage)).write_text(text)
			dumps[stage] = text
			records['deterministic'].append(name+':'+stage)
		ir = dumps['llvm']
		assert not re.search(r'\b(?:malloc|calloc|realloc|free|atexit|landingpad|personality|invoke|noalias)\b|llvm\.mem(?:cpy|move)|owner[._]header|destructor[._]pointer|active[._]field', ir), name
		assert not re.search(r'owned-field|OwnedField|OWNED_FIELD', dumps['ssa']+dumps['nabi']), name
		main_id = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		wrapped = ir+'\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		for mode in ['O0', 'O2', 'callable-O2-fma']:
			stem = name+'-'+mode
			input_ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', wrapped, flags=re.M) if mode == 'callable-O2-fma' else wrapped
			input_path = out/(stem+'-input.ll'); input_path.write_text(input_ir)
			path = out/(stem+'.ll'); obj = out/(stem+'.o'); exe = out/stem
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', input_path, '-o', path])
			run(['opt', '-passes=verify', '-disable-output', path])
			run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'callable-O2-fma' else []), path, '-o', obj])
			run(['cc', obj, companion, '-o', exe]); run([exe], status, stdout)
			machine = run(['objdump', '-dr', obj]); (out/(stem+'.machine')).write_text(machine)
			assert not re.search(r'\b(?:malloc|calloc|realloc|free|atexit)\b', machine), stem
			(out/(stem+'.symbols')).write_text(run(['readelf', '-h', '-Ws', obj]))
			records['machine'].append(stem)
			records['runs'].append(dict(name=stem, status=status, output=stdout))
	for name in ['result', 'generic']:
		ir = identity_harness(name, (out/(name+'.llvm')).read_text(), (out/(name+'.ssa')).read_text())
		for mode in ['O0', 'O2', 'callable-O2-fma']:
			stem = name+'-identity-'+mode
			input_ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M) if mode == 'callable-O2-fma' else ir
			input_path = out/(stem+'-input.ll'); input_path.write_text(input_ir)
			path = out/(stem+'.ll'); obj = out/(stem+'.o'); exe = out/stem
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', input_path, '-o', path])
			run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'callable-O2-fma' else []), path, '-o', obj])
			run(['cc', obj, companion, '-o', exe]); run([exe], 42, '+1\n-1\n')
			(out/(stem+'.machine')).write_text(run(['objdump', '-dr', obj]))
			records['machine'].append(stem)
			records['runs'].append(dict(name=stem, status=42, output='+1\n-1\n'))
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} exact executions; {len(records['machine'])} machine audits; {len(records['deterministic'])} deterministic stage comparisons")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
