# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Install, relocate and consume explicit output artifacts with the real CLI."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
from qualify import ROOT, LIB, STAGES, COMMANDS, run, process, sha


def qualify(build, out):
	build = build.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=True)
	options = {item['name']: item['value'] for item in json.loads(run(['meson', 'introspect', build, '--buildoptions']))}
	record_root = out
	index = 1
	while (record_root / ('run-' + str(index))).exists():
		index += 1
	out = record_root / ('run-' + str(index)); out.mkdir()
	stage = out / 'install'; destination = out / 'relocated'; prefix = destination / 'prefix'; client = destination / 'client'
	assert not stage.exists() and not destination.exists(), 'use fresh campaign installation paths'
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	installed = stage / Path(options['prefix']).relative_to('/')
	prefix.parent.mkdir(parents=True); shutil.copytree(installed, prefix); shutil.copytree(ROOT / 'examples/text-output', client)
	def relocate(option):
		path = Path(options[option]); return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
	compiler = relocate('bindir') / 'astrac'; library = relocate('datadir') / 'astra'; support = relocate('libdir') / 'astra/x86_64-linux'
	assert (support / 'text-posix.o').exists() and (support / 'target.txt').exists()
	for name in ['text-posix.c', 'text-posix.h']:
		assert (library / 'platform' / name).read_bytes() == (LIB / 'platform' / name).read_bytes()
	assert (library / 'hosted/text.astra').read_bytes() == (LIB / 'hosted/text.astra').read_bytes()
	hello = destination / 'hello'; run([compiler, client / 'hello.astra', library / 'hosted/text.astra', '--link-object', support / 'text-posix.o', '-o', hello], cwd=client); assert run([hello], cwd=client) == b'Hello from Astra.\n'
	sources = [client / name for name in ['labels.astra', 'model.astra', 'main.astra']] + [library / 'hosted/text.astra', library / 'base/contracts.astra']
	exe = destination / 'composition'; run([compiler, *sources, '--link-object', support / 'text-posix.o', '--link-object', support / 'failure-trap.o', '-o', exe], cwd=client)
	p = process([exe], cwd=client); assert p.returncode == 0 and p.stdout == b'Astra \xc3\xa9\0\xf0\x9f\x98\x80\n%s%n\0after' and p.stderr == b'status\0okreleased\n'
	original = [ROOT / 'examples/text-output' / name for name in ['labels.astra', 'model.astra', 'main.astra']] + [LIB / 'hosted/text.astra', LIB / 'base/contracts.astra']
	comparisons = {}
	for step in STAGES:
		a = run([build / 'astrac', '--dump-' + step, *original]); b = run([compiler, '--dump-' + step, *sources], cwd=client); assert a == b, step; comparisons[step] = sha(b)
	a = run([build / 'astrac', '--dump-syntax', *original]); b = run([compiler, '--dump-syntax', *sources], cwd=client)
	for index, (before, after) in enumerate(zip(original, sources)):
		a = a.replace(('(source "' + str(before) + '"').encode(), ('(source "input-' + str(index) + '"').encode())
		b = b.replace(('(source "' + str(after) + '"').encode(), ('(source "input-' + str(index) + '"').encode())
	assert a == b; comparisons['syntax-with-relocated-source-provenance'] = sha(b)
	# Normal false returns preserve destructor and owned field cleanup.
	with open('/dev/full', 'wb') as full:
		p = subprocess.run([exe], cwd=client, stdout=full, stderr=subprocess.PIPE, timeout=30)
	assert p.returncode == 1 and p.stderr == b'released\n'
	manifest = [dict(path=str(p.relative_to(prefix)), sha256=sha(p.read_bytes())) for p in sorted(prefix.rglob('*')) if p.is_file()]
	result = dict(configured={k: options[k] for k in ['prefix', 'bindir', 'datadir', 'libdir']}, prefix=str(prefix), compiler=str(compiler), source=str(library/'hosted/text.astra'), provider=str(support/'text-posix.o'), target_identity=(support/'target.txt').read_text(), consumer=str(exe), cwd=str(client), comparisons=comparisons, install_manifest=manifest, commands=COMMANDS)
	(record_root / 'installation.json').write_text(json.dumps(result, indent='\t')+'\n'); print('TEXT-IO installed/relocated consumer PASS')


if __name__ == '__main__':
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
