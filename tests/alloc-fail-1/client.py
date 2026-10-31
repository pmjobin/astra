# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Installed/relocated four-source composition and explicit linking failures."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import re
import resource
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['types.astra', 'actions.astra', 'factory.astra', 'main.astra']
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']


def limited():
	resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024, 64 * 1024 * 1024))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def qualify(build, out):
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	env = dict(os.environ, TMPDIR=str(out / 'tmp'), CCACHE_DISABLE='1')
	commands = []
	def run(argv, cwd=out, limited_memory=False):
		p = subprocess.run(list(map(str, argv)), cwd=cwd, env=env, capture_output=True, preexec_fn=limited if limited_memory else None)
		commands.append(dict(argv=list(map(str, argv)), cwd=str(cwd), status=p.returncode, stderr=p.stderr.decode(), stdout_sha256=hashlib.sha256(p.stdout).hexdigest(), limit_mib=64 if limited_memory else None))
		return p
	def checked(argv, cwd=out):
		p = run(argv, cwd)
		assert p.returncode == 0 and not p.stderr, commands[-1]
		return p.stdout
	def permutations(compiler, example, support, directory):
		directory.mkdir()
		for name in SOURCES + ['application.vapi', 'application.c']:
			shutil.copyfile(example / name, directory / name)
		for cc in ['gcc', 'clang']:
			checked([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', 'application.c', '-o', cc + '.o'], directory)
		foreign = ['--vapi', 'application.vapi']
		canonical = {stage: checked([compiler, '--dump-' + stage, *SOURCES, *([] if stage == 'syntax' else foreign)], directory) for stage in STAGES}
		for stage, data in canonical.items():
			(directory / ('canonical.' + stage)).write_bytes(data)
		assert len(re.findall(rb'\(function #\d+ "astra\.gen\.', canonical['ssa'])) == 2
		line = next(i for i, text in enumerate((directory / 'factory.astra').read_text().splitlines(), 1) if 'else returning_report' in text)
		reported = f'allocation example: factory.astra:{line}: count = 67108864\n'.encode()
		rows = []
		for index, order in enumerate(itertools.permutations(SOURCES)):
			for stage in STAGES:
				assert checked([compiler, '--dump-' + stage, *order, *([] if stage == 'syntax' else foreign)], directory) == canonical[stage], (order, stage)
			for cc in ['gcc', 'clang']:
				exe = directory / (f'consumer-{index}-' + cc)
				checked([compiler, *order, *foreign, '--link-object', cc + '.o', '--link-object', support / 'args-posix.o', '-o', exe], directory)
				for mode, status, error in [('', 0, b''), ('fatal', 2, b'allocation example: failure 41 (records 67108864)\n'), ('returning', -signal.SIGILL, reported), ('default', -signal.SIGILL, b'')]:
					p = run([exe, *([mode] if mode else [])], directory, True)
					assert p.returncode == status and p.stdout == b'' and p.stderr == error, commands[-1]
					rows.append(dict(order=order, provider=cc, mode=mode, status=p.returncode, stderr_hex=p.stderr.hex()))
		(directory / 'runs.json').write_text(json.dumps(rows, indent='\t') + '\n')
		return canonical
	try:
		options = {item['name']: item['value'] for item in json.loads(checked(['meson', 'introspect', build, '--buildoptions']))}
		stage = out / 'stage'
		checked(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
		original_prefix = stage / Path(options['prefix']).relative_to('/')
		prefix = out / 'relocated-prefix'
		shutil.move(original_prefix, prefix)
		def installed(option):
			path = Path(options[option])
			return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
		compiler = installed('bindir') / 'astrac'
		example = installed('datadir') / 'astra/examples/allocation-failure'
		support = installed('libdir') / 'astra/x86_64-linux'
		assert compiler.read_bytes() == (build / 'astrac').read_bytes()
		assert (support / 'args-posix.o').read_bytes() == (build / 'lib/astra/args-posix.o').read_bytes()
		for name in SOURCES + ['application.c', 'application.vapi', 'README.md']:
			assert (example / name).read_bytes() == (ROOT / 'examples/allocation-failure' / name).read_bytes()
		before = permutations(build / 'astrac', ROOT / 'examples/allocation-failure', build / 'lib/astra', out / 'original')
		after = permutations(compiler, example, support, out / 'installed')
		assert before == after
		client = out / 'installed'
		output = client / 'preserved-output'
		output.write_bytes(b'previous output\x00must survive\n')
		digest = hashlib.sha256(output.read_bytes()).hexdigest()
		(client / 'wrong.c').write_text('void wrong_application_action(void){}\n')
		checked(['gcc', '-c', 'wrong.c', '-o', 'wrong.o'], client)
		shutil.copyfile(client / 'gcc.o', client / 'duplicate.o')
		for name, objects in [('missing', []), ('wrong', ['wrong.o']), ('duplicate', ['gcc.o', 'duplicate.o'])]:
			p = run([compiler, *SOURCES, '--vapi', 'application.vapi', '--link-object', support / 'args-posix.o', *[part for obj in objects for part in ['--link-object', obj]], '-o', output], client)
			assert p.returncode == 1 and b'allocation_example_' in p.stderr and hashlib.sha256(output.read_bytes()).hexdigest() == digest, commands[-1]
			(out / (name + '.stderr')).write_bytes(p.stderr)
		(client / 'native.astra').write_text('void returning_report(int n){}int main(){var a=new int[2] else returning_report(2);return len(a)-2;}\n')
		checked([compiler, 'native.astra', '-o', 'native'], client)
		assert checked([client / 'native'], client) == b''
		(out / 'provider-dependencies.txt').write_bytes(checked(['nm', '-u', client / 'gcc.o']))
		(out / 'result.json').write_text(json.dumps(dict(orders_before=24, orders_relocated=24, runtime_executions=384, stages={stage: hashlib.sha256(data).hexdigest() for stage, data in before.items()}, prefix=str(prefix), configured=options, link_failure_preserved_sha256=digest), indent='\t') + '\n')
	finally:
		(out / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
	print('24 original and 24 relocated orders; GCC/Clang actions; 384 exact runtime results; 3 atomic link failures')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
