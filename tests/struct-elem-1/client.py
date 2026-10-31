# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Four-source numerical consumer, installed relocation and exact source labels."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import re
import resource
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT/'lib/astra'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
SOURCES = ['types.astra', 'state.astra', 'processing.astra', 'main.astra']
LIBRARIES = ['base/diagnostics.astra', 'base/clamp.astra', 'base/contracts.astra', 'hosted/text.astra']
PROVIDERS = ['args-posix.o', 'text-posix.o', 'diagnostics-hosted.o', 'failure-trap.o']
COMMANDS = []
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def sha(data):
	return hashlib.sha256(data).hexdigest()


def library_file(library, name):
	# Source bindings and installed bindings have different maintained roots.
	root = ROOT/'lib/bindings' if library == LIB and name.endswith('.vapi') else library
	return root/name


def process(args, cwd, **kwargs):
	args = list(map(str, args)); COMMANDS.append(dict(argv=args, cwd=str(cwd)))
	return subprocess.run(args, cwd=cwd, env=dict(os.environ, CCACHE_DISABLE='1'), **kwargs)


def run(args, cwd):
	p = process(args, cwd, capture_output=True)
	assert p.returncode == 0 and not p.stderr, (args, p.returncode, p.stdout[-2000:], p.stderr[-4000:])
	return p.stdout


def report(file, line, expression, message=''):
	return f'Astra assertion failed\n  file: "{file}"\n  line: {line}\n  expression: "{expression}"\n  message: "{message}"\n'.encode()


def permutations(compiler, library, support, out):
	out.mkdir(parents=True, exist_ok=False); client = out/'client'; client.mkdir()
	for name in SOURCES:
		shutil.copyfile(ROOT/'examples/struct-elements'/name, client/name)
	for name in [*LIBRARIES, 'hosted/math.vapi']:
		(client/name).parent.mkdir(exist_ok=True); shutil.copyfile(library_file(library, name), client/name)
	inputs = [*LIBRARIES, '--vapi', 'hosted/math.vapi']
	links = [part for name in PROVIDERS for part in ['--link-object', support/name]] + ['--link-library', 'm']
	canonical = {stage: run([compiler, '--dump-'+stage, *SOURCES, *(LIBRARIES if stage == 'syntax' else inputs)], client) for stage in STAGES}
	for stage, data in canonical.items():
		(out/('canonical.'+stage)).write_bytes(data)
	rows = []
	for i, order in enumerate(itertools.permutations(SOURCES)):
		for stage in STAGES:
			assert run([compiler, '--dump-'+stage, *order, *(LIBRARIES if stage == 'syntax' else inputs)], client) == canonical[stage], (i, order, stage)
		exe = client/('consumer-'+str(i)); run([compiler, *order, *inputs, *links, '-o', exe], client)
		success = process([exe], client, capture_output=True); assert success.returncode == 0 and success.stdout == b'record kernels: 16 -> 17; snapshot preserved\n' and not success.stderr
		forced = process([exe, 'bad'], client, capture_output=True); assert forced.returncode == -6 and not forced.stdout and forced.stderr == report('main.astra', 18, 'selected[0].weight == 0.5d', 'forced record result failure')
		with open('/dev/full', 'wb') as sink:
			failed = process([exe], client, stdout=sink, stderr=subprocess.PIPE); assert failed.returncode == 2 and not failed.stderr
		(out/(f'consumer-{i}.stdout')).write_bytes(success.stdout); (out/(f'consumer-{i}.stderr')).write_bytes(forced.stderr)
		rows.append(dict(order=list(order), executable_sha256=sha(exe.read_bytes()), normal=success.returncode, forced=forced.returncode, handled_output_failure=failed.returncode, stdout_sha256=sha(success.stdout), diagnostic_sha256=sha(forced.stderr)))
		# A second forced failure specifically checks the projected receiver call site.
	main = (client/'main.astra').read_text().replace('selected[0].demand(selected[0].weight == 1.0d);', 'selected[0].demand(selected[0].weight == 0.5d);')
	(client/'method-failure.astra').write_text(main); exe = client/'method-failure'
	run([compiler, *SOURCES[:3], 'method-failure.astra', *inputs, *links, '-o', exe], client)
	p = process([exe], client, capture_output=True); assert p.returncode == -6 and p.stderr == report('method-failure.astra', 17, 'selected[0].weight == 0.5d') and not p.stdout
	(out/'method-failure.stderr').write_bytes(p.stderr)
	(out/'permutations.json').write_text(json.dumps(rows, indent='\t')+'\n')
	return canonical, rows


def machine_client(build, client, support, out):
	out.mkdir(); rows = []; emitter = build/'tests/struct-elem-1/astra-struct-elements-llvm'
	entry = out/'client-entry.ll'; run([emitter, '--emit', entry, *SOURCES, *LIBRARIES, '--vapi', 'hosted/math.vapi'], client)
	ir = entry.read_text()
	for mode in ['O0', 'O2', 'fma', 'preserved']:
		inp, opt, obj = out/(mode+'-input.ll'), out/(mode+'.ll'), out/(mode+'.o')
		inp.write_text(re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M) if mode == 'preserved' else ir)
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp.name, '-o', opt.name], out); run(['opt', '-passes=verify', '-disable-output', opt.name], out)
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), opt.name, '-o', obj.name], out)
		for cc in ['gcc', 'clang']:
			exe = out/(mode+'-'+cc); run([cc, obj, *[support/name for name in PROVIDERS], '-lm', '-o', exe], client)
			p = process([exe], client, capture_output=True); assert p.returncode == 0 and p.stdout == b'record kernels: 16 -> 17; snapshot preserved\n' and not p.stderr
			(out/(exe.name+'.stdout')).write_bytes(p.stdout); rows.append(dict(mode=mode, linker=cc, status=0, executable_sha256=sha(exe.read_bytes())))
		(out/(mode+'.machine')).write_bytes(run(['objdump', '-dr', obj], client)); (out/(mode+'.symbols')).write_bytes(run(['readelf', '-h', '-Ws', '-r', obj], client)); (out/(mode+'.size')).write_bytes(run(['size', '-A', obj], client))
	for name in PROVIDERS:
		(out/(name+'.undefined')).write_bytes(run(['nm', '-u', support/name], client)); (out/(name+'.size')).write_bytes(run(['size', '-A', support/name], client))
	(out/'results.json').write_text(json.dumps(rows, indent='\t')+'\n')
	return rows


def qualify(build, out):
	out.mkdir(parents=True, exist_ok=False)
	try:
		options = {item['name']: item['value'] for item in json.loads(run(['meson', 'introspect', build, '--buildoptions'], ROOT))}
		stage = out/'stage'; prefix = out/'relocated/prefix'; run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage], ROOT)
		prefix.parent.mkdir(); shutil.copytree(stage/Path(options['prefix']).relative_to('/'), prefix)
		def relocated(option):
			path = Path(options[option]); return prefix/(path.relative_to(options['prefix']) if path.is_absolute() else path)
		compiler = relocated('bindir')/'astrac'; library = relocated('datadir')/'astra'; support = relocated('libdir')/'astra/x86_64-linux'
		assert compiler.read_bytes() == (build/'astrac').read_bytes()
		for name in PROVIDERS:
			assert (support/name).read_bytes() == (build/'lib/astra'/name).read_bytes()
		for name in [*LIBRARIES, 'hosted/math.vapi']:
			assert (library/name).read_bytes() == library_file(LIB, name).read_bytes()
		before, original = permutations(build/'astrac', LIB, build/'lib/astra', out/'original')
		after, installed = permutations(compiler, library, support, out/'relocated/qualification')
		assert before == after, 'Exact source labels must be reproducible without payload rewriting'
		machine_client(build, out/'relocated/qualification/client', support, out/'machine')
		kernel = out/'kernel'; run([compiler, ROOT/'tests/struct-elem-1/fixtures/kernel.astra', library/'base/diagnostics.astra', '--link-object', support/'diagnostics-hosted.o', '-o', kernel], ROOT); assert run([kernel], ROOT) == b''
		(out/'results.json').write_text(json.dumps(dict(original=len(original), installed=len(installed), canonical={key: sha(data) for key, data in before.items()}, compiler_sha256=sha(compiler.read_bytes()), providers={name: sha((support/name).read_bytes()) for name in PROVIDERS}, installed_prefix=str(prefix)), indent='\t')+'\n')
	finally:
		(out/'commands.json').write_text(json.dumps(COMMANDS, indent='\t')+'\n')
	print('24 original and 24 relocated installed source orders, exact diagnostic and output-failure results')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
