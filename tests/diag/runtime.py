# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent rendering, eager effects, ownership and installed-source seams."""
from pathlib import Path
import json
import random
import struct
import sys

sys.dont_write_bytecode = True
from qualify import HERE, LIB, ROOT, MODES, COMMANDS, cc, machine, process, report, run, sha, write_json


def rendering(out):
	out.mkdir()
	rng = random.Random(7601)
	cases = [(b'', 0, b'', b''), (b'file\0tail', -2**31, b'"quoted"\\path\n\r\t', bytes(range(128))), ('français e\u0301 😀'.encode(), 2**31-1, b'%s%n', b'A\0B'), (b'f', -1, b'x', b'x' * 131072)]
	for _ in range(96):
		cases.append((rng.randbytes(rng.randrange(0, 100)), rng.randrange(-2**31, 2**31), rng.randbytes(rng.randrange(0, 200)), rng.randbytes(rng.randrange(0, 2048))))
	rows = []
	for host in ['gcc', 'clang']:
		exe = out / ('render-' + host); cc(host, HERE / 'render.c', exe)
		for i, (file, line, expression, message) in enumerate(cases):
			vector = struct.pack('<i', line) + b''.join(struct.pack('<I', len(data)) + data for data in [file, expression, message]); expected = report(file, line, expression, message)
			(out / f'vector-{i:03}.bin').write_bytes(vector)
			p = process([exe], input=vector); assert p.returncode == 0 and p.stdout == expected and not p.stderr
			if i < 4:
				fatal = process([exe, 'fatal'], input=vector); assert fatal.returncode < 0 and fatal.stderr == expected and not fatal.stdout
				(out / f'fatal-{i:03}-{host}.stderr').write_bytes(fatal.stderr)
			rows.append(dict(host=host, case=i, bytes=len(expected), sha256=sha(expected)))
		for kind in range(6):
			p = process([exe, 'shape', kind]); assert p.returncode < 0 and p.stderr == b'Astra assertion failed: invalid diagnostic text view\n' and not p.stdout
			rows.append(dict(host=host, shape=kind, status=p.returncode))
	write_json(out / 'results.json', rows)
	return rows


def effects(build, out):
	out.mkdir()
	prefix = '''extern(C) int diag_mark(int value);
extern(C) int diag_zero();
bool flag(int id,bool value){diag_mark(id);return value;}
int integer(int id){diag_mark(id);return 91;}
string text(int id){diag_mark(id);return "provided";}
string trap_text(){diag_mark(84);var zero=diag_zero();var n=1/zero;diag_mark(n);return "unreachable";}
bool invoke(){assert_message(flag(67,true),text(77));return true;}
'''
	cases = [
		('eager-true', 'assert_message(flag(67,true),text(77),text(70),integer(76),text(69));', b'ACMFLEZ', None),
		('eager-false', 'assert_message(flag(67,false),text(77),text(70),integer(76),text(69));', b'ACMFLE', report(b'provided', 91, b'provided', b'provided')),
		('auto-false', 'assert_message(flag(67,false),text(77));', b'ACM', report(b'auto-false.astra', 8, b'flag(67,false)', b'provided')),
		('earlier-trap', 'assert_message(flag(67,true),trap_text(),text(70),integer(76),text(69));', b'ACT', b''),
		('short-skip', 'if(false && invoke()){return 1;}if(true || invoke()){diag_mark(83);}', b'ASZ', None),
		('surrounding', 'if(flag(66,true) && invoke()){diag_mark(68);}', b'ABCMDZ', None),
	]
	rows = []
	for host in ['gcc', 'clang']:
		cc(host, HERE / 'effects.c', out / ('effects-' + host + '.o'), ['-c'])
		cc(host, LIB / 'platform/diagnostics-hosted.c', out / ('provider-' + host + '.o'), ['-c'])
	for name, body, expected, failure in cases:
		path = out / (name + '.astra'); path.write_text(prefix + 'int main(){diag_mark(65);' + body + 'diag_mark(90);return 0;}')
		ir_path = out / (name + '.entry.ll'); run([build / 'tests/diag/astra-diag-llvm', '--emit', ir_path, path.name, LIB / 'base/diagnostics.astra'], cwd=out)
		for mode in MODES:
			obj = machine(ir_path.read_bytes(), out / (name + '-' + mode), mode)
			for host in ['gcc', 'clang']:
				exe = out / f'{name}-{mode}-{host}'; run(['/usr/bin/' + host, obj, out / ('effects-' + host + '.o'), out / ('provider-' + host + '.o'), '-o', exe]); p = process([exe])
				assert (p.returncode == 0 if failure is None else p.returncode < 0) and p.stdout == expected and p.stderr == (failure or b''), (name, mode, host, p.returncode, p.stdout, p.stderr)
				exe.with_suffix('.stdout').write_bytes(p.stdout); exe.with_suffix('.stderr').write_bytes(p.stderr)
				rows.append(dict(name=name, host=host, mode=mode, status=p.returncode, stdout=p.stdout.decode(), executable=str(exe)))
	write_json(out / 'results.json', rows)
	return rows


def ownership(build, out, output=False):
	out.mkdir()
	name = 'ownership-output' if output else 'ownership'
	source = out / (name + '.astra'); text = (HERE / 'fixtures/ownership.astra').read_bytes()
	if output:
		text = text.replace(b'\tassert_message(', b'\tif (!print(args[1])) { return 2; } assert_message(')
	source.write_bytes(text)
	input_ir = out / (name + '.entry.ll'); run([build / 'tests/diag/astra-diag-llvm', '--emit', input_ir, source.name, LIB / 'base/diagnostics.astra', *([LIB / 'hosted/text.astra'] if output else []), '--vapi', HERE / 'fixtures/ownership.vapi'], cwd=out)
	ir = input_ir.read_bytes(); assert b'astra_host_args_prepare_v0' in ir and b'astra_host_args_dispose_v0' in ir
	rows = []
	for host in ['gcc', 'clang']:
		cc(host, LIB / 'platform/args-posix.c', out / ('args-' + host + '.o'), ['-c', '-Dmalloc=diag_snapshot_alloc', '-Dfree=diag_snapshot_free'])
		cc(host, LIB / 'platform/diagnostics-hosted.c', out / ('provider-' + host + '.o'), ['-c'])
		if output:
			cc(host, LIB / 'platform/text-posix.c', out / ('text-' + host + '.o'), ['-c'])
	for mode in MODES:
		obj = machine(ir, out / (name + '-' + mode), mode)
		for host in ['gcc', 'clang']:
			exe = out / (name + '-' + mode + '-' + host)
			cc(host, HERE / 'ownership.c', exe, [obj, out / ('args-' + host + '.o'), out / ('provider-' + host + '.o'), *([out / ('text-' + host + '.o')] if output else []), '-Wl,--wrap=calloc', '-Wl,--wrap=free', '-Wl,--wrap=astra_diag_assert_fail_v0'])
			for arg, trace in [('ok', b'AERUrRBCMcbrD'), ('fatal é %s%n', b'AERUrRBCF')]:
				if output:
					trace = trace.replace(b'BC', b'BC' + arg.encode())
				p = process([exe, arg]); assert p.stdout == trace and (p.returncode == 0 if arg == 'ok' else p.returncode < 0), (arg, mode, host, p.returncode, p.stdout, p.stderr)
				assert p.stderr == (b'' if arg == 'ok' else report(source.name.encode(), 22, b'args[1] == "ok"', arg.encode())), p.stderr
				(out / (exe.name + ('-success' if arg == 'ok' else '-fatal') + '.stdout')).write_bytes(p.stdout)
				(out / (exe.name + ('-success' if arg == 'ok' else '-fatal') + '.stderr')).write_bytes(p.stderr)
				rows.append(dict(host=host, mode=mode, argument=arg, status=p.returncode, trace=p.stdout.decode(), executable=str(exe)))
	write_json(out / 'results.json', rows)
	return rows


def qualify(build, out):
	build = build.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=False)
	try:
		result = dict(rendering=rendering(out / 'rendering'), effects=effects(build, out / 'effects'), ownership=ownership(build, out / 'ownership'), ownership_output=ownership(build, out / 'ownership-output', True))
		write_json(out / 'results.json', result)
	finally:
		write_json(out / 'commands.json', COMMANDS)
	print('DIAG-1 renderer and effect qualification PASS')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
