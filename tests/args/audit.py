# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Dependency/old-byte controls and unsuppressed memory classifications."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from qualify import ROOT, HERE, LIB, STAGES, run, process, sha


def object_file(ir, out, mode):
	out.with_suffix('.input.ll').write_bytes(ir)
	run(['opt', '-passes=verify' if mode in ['O0', 'preserved'] else '-passes=default<O2>', '-S', out.with_suffix('.input.ll'), '-o', out.with_suffix('.ll')])
	run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), out.with_suffix('.ll'), '-o', out.with_suffix('.o')])
	return out.with_suffix('.o')


def dependencies(build, baseline, out):
	out.mkdir(parents=True, exist_ok=True); rows = []
	controls = dict(scalar='int f(int n){return n+2;} int main(){return f(40);}', text='int size(string x){return x.byte_length;} int main(){return size("a\\0é");}', numeric='int sum(int[] a){a[0]=a[0]+1;return a[0];} int main(){int[2] a={1,2};return sum(slice(a));}')
	for name, source in controls.items():
		path = out / (name + '.astra'); path.write_text(source)
		old = run([baseline / 'astrac', '--dump-llvm', path]); new = run([build / 'astrac', '--dump-llvm', path]); assert old == new
		ssa = run([build / 'astrac', '--dump-ssa', path]); ordinal = re.search(rb'\(function #(\d+) "main"', ssa)[1].decode()
		wrapper = f'\ndefine i32 @main() {{\n\t%r = call fastcc i32 @astra.fn.{ordinal}()\n\tret i32 %r\n}}\n'.encode()
		for mode in ['O0', 'O2', 'fma', 'preserved']:
			a = object_file(old + wrapper, out / (name+'-baseline-'+mode), mode); b = object_file(new + wrapper, out / (name+'-candidate-'+mode), mode)
			assert a.read_bytes() == b.read_bytes(); rows.append(dict(control=name, mode=mode, object_sha256=sha(b.read_bytes()), byte_identical=True))
		binary = out / name; run([build / 'astrac', path, '-o', binary]); rows.append(dict(program=name, undefined=run(['nm', '-u', binary]).decode(), dynamic=run(['readelf', '-d', binary]).decode()))
		# Internal freestanding seam: no public object-only or freestanding CLI mode.
	ir = run([build / 'astrac', '--dump-llvm', HERE / 'fixtures/native.astra']); ssa = run([build / 'astrac', '--dump-ssa', HERE / 'fixtures/native.astra']); ordinal = re.search(rb'\(function #(\d+) "consume"', ssa)[1].decode()
	ir += f'''\n@input.a = private constant [3 x i8] c"a\\00b"
@input.b = private constant [3 x i8] c"a\\00b"
@input.table = private constant [2 x {{ptr, i32}}] [{{ptr, i32}} {{ptr @input.a, i32 3}}, {{ptr, i32}} {{ptr @input.b, i32 3}}]
define void @_start() noreturn {{
\t%r = call fastcc i32 @astra.fn.{ordinal}(ptr @input.table, i32 2, ptr @input.table, i32 2, i32 1)
\t%bad = icmp ne i32 %r, 3
\t%status = zext i1 %bad to i64
\tcall void asm sideeffect "syscall", "{{rax}},{{rdi}},~{{rcx}},~{{r11}},~{{memory}}"(i64 60, i64 %status)
\tunreachable
}}
'''.encode()
	for mode in ['O0', 'O2']:
		obj = object_file(ir, out / ('freestanding-' + mode), mode); exe = out / ('freestanding-' + mode); run(['ld', obj, '-o', exe]); run([exe]); assert run(['nm', '-u', exe]) == b''; rows.append(dict(program='native-only-freestanding', mode=mode, undefined='', object_sha256=sha(obj.read_bytes())))
	for name, sources, extra in [('args-count', [out / 'args-count.astra'], []), ('args-output', [ROOT / 'examples/args/echo.astra', LIB / 'hosted/text.astra'], ['--link-object', build / 'lib/astra/text-posix.o'])]:
		(out / 'args-count.astra').write_text('int main(string[] a){return len(a);}')
		exe = out / name; run([build / 'astrac', *sources, '--link-object', build / 'lib/astra/args-posix.o', *extra, '-o', exe]); undefined = run(['nm', '-u', exe]); assert all(item not in undefined for item in [b'g_object', b'g_malloc', b'LLVM'])
		rows.append(dict(program=name, undefined=undefined.decode(), dynamic=run(['readelf', '-d', exe]).decode()))
	combined = build / 'args-1/effects/effects-O2-gcc-normal'; rows.append(dict(program='args-output-owned-baselib-instrumented', undefined=run(['nm', '-u', combined]).decode(), dynamic=run(['readelf', '-d', combined]).decode()))
	(out / 'dependencies.json').write_text(json.dumps(rows, indent='\t') + '\n'); return rows


def memory(build, baseline, out, installation):
	out.mkdir(parents=True, exist_ok=True); qualified = build / 'args-1/qualification'; effects = build / 'args-1/effects'; jobs = []
	for stage in ['semantic', 'core', 'cfg', 'ssa', 'nabi', 'pipeline', 'llvm']:
		jobs.append(('stage-'+stage, [build / 'tests/args' / ('astra-args-'+stage), '--tap'], 0, 'normal', False))
	for stage in STAGES:
		jobs.append(('compiler-'+stage, [build / 'astrac', '--dump-'+stage, HERE / 'fixtures/native.astra'], 0, 'normal', False))
	for host in ['gcc', 'clang']:
		jobs.append(('provider-'+host, [qualified / ('provider-'+host)], 0, 'normal', False))
		jobs.append(('zero-wrapper-'+host, [effects / ('zero-wrapper-'+host)], 0, 'normal', False))
		for mode in ['O0', 'O2', 'fma', 'preserved']:
			jobs.append(('native-'+mode+'-'+host, [qualified / ('native-'+mode+'-'+host)], 0, 'normal', False))
			jobs.append(('snapshot-output-'+mode+'-'+host, [qualified / ('snapshot-output-'+mode+'-'+host)], 0, 'normal', False))
			jobs.append(('effects-'+mode+'-'+host, [effects / ('effects-'+mode+'-'+host+'-normal'), 'aé'], 0, 'normal', False))
	for category, kind, arguments, status, full in [('handled-output-failure', 'normal', ['aé'], 1, True), ('invalid-input', 'normal', [b'\xff'], 2, False), ('allocation-failure', 'allocation-failure', ['valid'], 3, False), ('intentional-fatal', 'trap', ['aé'], None, False)]:
		jobs.append((category, [effects / ('effects-O0-gcc-'+kind), *arguments], status, category, full))
	installed = json.loads(installation.read_text()); jobs.append(('installed-consumer', [installed['consumer'], 'é', ''], 0, 'normal', False)); jobs.append(('installed-compiler', [installed['compiler'], '--dump-llvm', HERE/'fixtures/native.astra'], 0, 'normal', False))
	control = out / 'ordinary-name-control.astra'; control.write_text('int f(){'+''.join('int C%d=0;'%n for n in range(5001))+'return 0;}')
	jobs += [('baseline-name-control', [baseline/'astrac', '--dump-semantics', control], 99, 'inherited-glib', False), ('candidate-name-control', [build/'astrac', '--dump-semantics', control], 99, 'inherited-glib', False)]
	def measure(job):
		name, args, status, category, full = job; log = out / (name+'.log')
		command = ['valgrind', '--vgdb=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=99', '--log-file='+str(log), *[a if isinstance(a, bytes) else str(a) for a in args]]
		if full:
			with open('/dev/full', 'wb') as stream:
				p = subprocess.run(command, stdout=stream, stderr=subprocess.PIPE, timeout=600, cwd=ROOT)
		else:
			p = subprocess.run(command, capture_output=True, timeout=600, cwd=ROOT)
		text = log.read_text(); assert 'ERROR SUMMARY:' in text
		def number(pattern):
			match = re.search(pattern, text); return int(match[1].replace(',', '')) if match else 0
		row = dict(name=name, category=category, status=p.returncode, errors=number(r'ERROR SUMMARY: ([\d,]+) errors'), definite=number(r'definitely lost: ([\d,]+) bytes'), indirect=number(r'indirectly lost: ([\d,]+) bytes'), possible=number(r'possibly lost: ([\d,]+) bytes'), reachable=number(r'still reachable: ([\d,]+) bytes'), suppressed=number(r'suppressed: ([\d,]+) bytes'), allocations=number(r'total heap usage: ([\d,]+) allocs'))
		(out / (name+'.stderr')).write_bytes(p.stderr); assert row['suppressed'] == 0
		if category == 'inherited-glib':
			assert row['errors'] == 2 and row['definite'] == 49152 and row['indirect'] == row['possible'] == 0 and 'g_quark_from_string' in text and 'call_init' in text, row
		else:
			assert row['errors'] == row['definite'] == row['indirect'] == row['possible'] == 0, row
		assert p.returncode < 0 if category == 'intentional-fatal' else p.returncode == status, row
		return row
	with ThreadPoolExecutor(max_workers=3) as pool:
		rows = list(pool.map(measure, jobs))
	(out / 'memory.json').write_text(json.dumps(rows, indent='\t') + '\n'); return rows


if __name__ == '__main__':
	parser = argparse.ArgumentParser(); parser.add_argument('build', type=Path); parser.add_argument('baseline', type=Path); parser.add_argument('out', type=Path); parser.add_argument('--installation', type=Path); args = parser.parse_args()
	if args.installation:
		memory(args.build.resolve(), args.baseline.resolve(), args.out.resolve(), args.installation.resolve())
	else:
		dependencies(args.build.resolve(), args.baseline.resolve(), args.out.resolve())
	print('ARGS-1 audit PASS')
