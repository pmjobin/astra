# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Install to a private DESTDIR, relocate, then use the real installed CLI."""
from pathlib import Path
import itertools
import json
import shutil
import sys
sys.dont_write_bytecode = True
from qualify import ROOT, LIB, STAGES, COMMANDS, cc, run, launch, sha


def qualify(build, out):
	build = build.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=True)
	options = {item['name']: item['value'] for item in json.loads(run(['meson', 'introspect', build, '--buildoptions']))}
	index = 1
	while (out / ('run-' + str(index))).exists():
		index += 1
	work = out / ('run-' + str(index)); work.mkdir()
	stage = work / 'install'; prefix = work / 'relocated/prefix'; client = work / 'relocated/client'
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	prefix.parent.mkdir(parents=True); shutil.copytree(stage / Path(options['prefix']).relative_to('/'), prefix)
	shutil.copytree(ROOT / 'examples/args', client)
	def relocate(option):
		path = Path(options[option]); return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
	compiler = relocate('bindir') / 'astrac'; library = relocate('datadir') / 'astra'; support = relocate('libdir') / 'astra/x86_64-linux'
	for name in ['args-posix.c', 'args-posix.h']:
		assert (library / 'platform' / name).read_bytes() == (LIB / 'platform' / name).read_bytes()
	assert (support / 'args-posix.o').exists() and b'args-posix' in (support / 'target.txt').read_bytes()
	launcher = work / 'launcher'; cc('/usr/bin/gcc', ROOT / 'tests/args/launcher.c', launcher)
	sources = [client / name for name in ['main.astra', 'views.astra', 'labels.astra']] + [library / 'hosted/text.astra']
	original = [ROOT / 'examples/args' / name for name in ['main.astra', 'views.astra', 'labels.astra']] + [LIB / 'hosted/text.astra']
	canonical = {}
	for step in STAGES:
		before = run([build / 'astrac', '--dump-' + step, *original]); after = run([compiler, '--dump-' + step, *sources], cwd=client)
		if step == 'syntax':
			for i, (old, new) in enumerate(zip(original, sources)):
				before = before.replace(str(old).encode(), ('input-' + str(i)).encode()); after = after.replace(str(new).encode(), ('input-' + str(i)).encode())
		assert before == after, step
		canonical[step] = run([compiler, '--dump-' + step, *sources], cwd=client)
	arguments = [b'custom installed invocation', b'', b'a b', 'é e\u0301😀'.encode(), b'--']
	expected = b''.join(b'arg: ' + a + b'\n' for a in arguments)
	consumer = client / 'arguments'
	for order in itertools.permutations(sources):
		for step in STAGES:
			assert run([compiler, '--dump-' + step, *order], cwd=client) == canonical[step]
		run([compiler, *order, '--link-object', support / 'args-posix.o', '--link-object', support / 'text-posix.o', '-o', consumer], cwd=client)
		p = launch(launcher, consumer, arguments, work); assert p.returncode == 0 and p.stdout == expected and not p.stderr
	count = client / 'count.astra'; count.write_text('int main(borrowed string[] a){return len(a);}')
	run([compiler, count, '--link-object', support / 'args-posix.o', '-o', client / 'count'], cwd=client)
	p = launch(launcher, client / 'count', [b'invocation', b'one', b'two'], work); assert p.returncode == 3 and not p.stdout and not p.stderr
	result = dict(configured={key: options[key] for key in ['prefix', 'bindir', 'datadir', 'libdir']}, compiler=str(compiler), cwd=str(client), consumer=str(consumer), count_consumer=str(client/'count'), provider=str(support/'args-posix.o'), target_identity=(support/'target.txt').read_text(), permutations=24, canonical={step: sha(data) for step,data in canonical.items()}, stdout_sha256=sha(expected), installed=[dict(path=str(p.relative_to(prefix)), sha256=sha(p.read_bytes())) for p in sorted(prefix.rglob('*')) if p.is_file()], commands=COMMANDS)
	(out / 'installation.json').write_text(json.dumps(result, indent='\t') + '\n'); print('ARGS-1 installed/relocated consumer PASS')


if __name__ == '__main__':
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
