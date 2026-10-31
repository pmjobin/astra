# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Four actual sources, 24 orders, exact providers and relocated installation."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import resource
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['types.astra', 'values.astra', 'owners.astra', 'main.astra']
LIBRARIES = ['base/buffers.astra', 'base/slices.astra', 'base/diagnostics.astra']
PROVIDERS = ['args-posix.o', 'diagnostics-hosted.o']
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def qualify(build, out):
	out.mkdir(parents=True, exist_ok=False); (out / 'tmp').mkdir(); commands = []
	env = dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(out / 'tmp'))
	def run(command, cwd=ROOT, status=0):
		command = list(map(str, command)); p = subprocess.run(command, cwd=cwd, capture_output=True, env=env)
		commands.append(dict(argv=command, cwd=str(cwd), status=p.returncode))
		(out / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
		assert p.returncode == status, (command, p.returncode, p.stderr.decode())
		return p
	options = {row['name']: row['value'] for row in json.loads(run(['meson', 'introspect', build, '--buildoptions']).stdout)}
	stage, prefix = out / 'stage', out / 'relocated/prefix'
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	prefix.parent.mkdir(); shutil.move(stage / Path(options['prefix']).relative_to('/'), prefix)
	def installed(option):
		path = Path(options[option]); return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
	compiler, library, support = installed('bindir') / 'astrac', installed('datadir') / 'astra', installed('libdir') / 'astra/x86_64-linux'
	assert compiler.read_bytes() == (build / 'astrac').read_bytes()
	for name in PROVIDERS:
		assert (support / name).read_bytes() == (build / 'lib/astra' / name).read_bytes()
	canonical, canonical_binary, records = {}, None, []
	for route, selected, libraries, providers in [('tree', build / 'astrac', ROOT / 'lib/astra', build / 'lib/astra'), ('installed', compiler, library, support)]:
		client = out / route; client.mkdir()
		for name in SOURCES:
			shutil.copyfile(ROOT / 'examples/owned-buffer-exchange' / name, client / name)
		for name in LIBRARIES:
			(client / name).parent.mkdir(exist_ok=True); shutil.copyfile(libraries / name, client / name)
		line = next(i for i, text in enumerate((client / 'main.astra').read_text().splitlines(), 1) if '== -1' in text)
		expected = f'Astra assertion failed\n  file: "main.astra"\n  line: {line}\n  expression: "actual.next[0].index == -1"\n  message: ""\n'.encode()
		links = [part for name in PROVIDERS for part in ['--link-object', providers / name]]
		for number, order in enumerate(itertools.permutations(SOURCES)):
			for selected_stage in STAGES:
				p = run([selected, '--dump-' + selected_stage, *order, *LIBRARIES], client); assert not p.stderr
				if selected_stage not in canonical:
					canonical[selected_stage] = p.stdout; (out / ('canonical.' + selected_stage)).write_bytes(p.stdout)
				assert canonical[selected_stage] == p.stdout, (route, order, selected_stage)
			exe = client / ('consumer-' + str(number)); p = run([selected, *order, *LIBRARIES, *links, '-o', exe], client); assert not p.stdout and not p.stderr
			identity = hashlib.sha256(exe.read_bytes()).hexdigest()
			if canonical_binary is None:
				canonical_binary = identity
			assert identity == canonical_binary
			p = run([exe], client); assert not p.stdout and not p.stderr
			p = run([exe, 'failure'], client, -6); assert not p.stdout and p.stderr == expected
			(client / (exe.name + '.stderr')).write_bytes(p.stderr)
			records.append(dict(route=route, order=order, binary_sha256=identity, diagnostic_sha256=hashlib.sha256(p.stderr).hexdigest()))
			# The driver must still preserve an existing requested output on link error.
		target = client / 'preserved-output'; target.write_bytes(b'preserve this requested output\n')
		p = run([selected, *SOURCES, *LIBRARIES, *links, '--link-object', client / 'absent.o', '-o', target], client, 1)
		(client / 'link-failure.stderr').write_bytes(p.stderr); assert target.read_bytes() == b'preserve this requested output\n'
	(out / 'results.json').write_text(json.dumps(dict(rows=records, prefix=str(prefix), installed_compiler=str(compiler), canonical={stage: hashlib.sha256(value).hexdigest() for stage, value in canonical.items()}, source_root=str(ROOT), client_root=str(out), scope='Installed clients are outside the isolated final compiler source tree; the developer run from the repository root is preliminary.'), indent='\t') + '\n')
	print('48 source permutations, all nine stages, relocated providers, source-aware DIAG and preserved output')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
