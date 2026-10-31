# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Install, relocate and exercise all source orders with stable relative labels."""
from pathlib import Path
import itertools
import json
import shutil
import sys

sys.dont_write_bytecode = True
from qualify import HERE, LIB, ROOT, STAGES, COMMANDS, process, report, run, sha, write_json


def permutations(compiler, library, support, client, out):
	client.mkdir(parents=True)
	for name in ['wrapper.astra', 'helper.astra', 'client.astra']:
		shutil.copyfile(HERE / 'fixtures' / name, client / name)
	shutil.copyfile(library / 'base/diagnostics.astra', client / 'library.astra')
	sources = ['client.astra', 'wrapper.astra', 'helper.astra', 'library.astra']
	canonical = {stage: run([compiler, '--dump-' + stage, *sources], cwd=client) for stage in STAGES}
	for stage, data in canonical.items():
		(out / ('canonical.' + stage)).write_bytes(data)
	expected = report(b'client.astra', 3, b'is_ready(args)', 'bad é e\u0301😀 %s%n'.encode())
	rows = []
	for i, order in enumerate(itertools.permutations(sources)):
		for stage in STAGES:
			assert run([compiler, '--dump-' + stage, *order], cwd=client) == canonical[stage], (order, stage)
		exe = client / ('consumer-' + str(i)); run([compiler, *order, '--link-object', support / 'args-posix.o', '--link-object', support / 'diagnostics-hosted.o', '-o', exe], cwd=client)
		p = process([exe, 'ok'], cwd=client); assert p.returncode == 0 and not p.stdout and not p.stderr
		p = process([exe, 'bad é e\u0301😀 %s%n'], cwd=client); assert p.returncode < 0 and not p.stdout and p.stderr == expected
		exe.with_suffix('.stderr').write_bytes(p.stderr); rows.append(dict(order=list(order), status=p.returncode, stderr_sha256=sha(p.stderr), executable=str(exe)))
		# CLI spelling normalization is lexical and leaves '..' and case intact.
	(client / 'sub').mkdir()
	for label, expected_label in [('./client.astra', b'client.astra'), ('./sub//../client.astra', b'sub/../client.astra'), (str(client / 'client.astra'), str(client / 'client.astra').encode())]:
		exe = client / 'label'; run([compiler, label, *sources[1:], '--link-object', support / 'args-posix.o', '--link-object', support / 'diagnostics-hosted.o', '-o', exe], cwd=client)
		p = process([exe, 'bad']); assert p.returncode < 0 and p.stderr == report(expected_label, 3, b'is_ready(args)', b'bad')
	write_json(out / 'permutations.json', rows)
	return canonical, rows


def link_controls(compiler, library, support, out):
	out.mkdir()
	path = out / 'client.astra'; path.write_text('int main(){assert_that(false);return 0;}')
	exe = out / 'consumer'; rows = []
	for objects in [[], ['diagnostics-trap.o', 'diagnostics-hosted.o'], ['diagnostics-hosted.o', 'diagnostics-hosted.o']]:
		exe.write_bytes(b'preserve requested output\n'); args = [compiler, path, library / 'base/diagnostics.astra']
		for name in objects:
			args += ['--link-object', support / name]
		p = process([*args, '-o', exe]); assert p.returncode != 0 and b'astra_diag_assert_fail_v0' in p.stderr and exe.read_bytes() == b'preserve requested output\n'
		rows.append(dict(objects=objects, status=p.returncode, diagnostic=p.stderr.decode()))
		# Coexistence explicitly selects independent old failure and ordinary output.
	path.write_text('int main(){assert(true);assert_code(true,7);assert_equal_i32(1,1,0);assert_that(true);if(!println("ok")){return 1;}return 0;}')
	run([compiler, path, library / 'base/diagnostics.astra', library / 'base/contracts.astra', library / 'hosted/equality.astra', library / 'hosted/text.astra', '--link-object', support / 'diagnostics-hosted.o', '--link-object', support / 'failure-hosted.o', '--link-object', support / 'text-posix.o', '-o', exe])
	p = process([exe]); assert p.returncode == 0 and p.stdout == b'ok\n' and not p.stderr
	write_json(out / 'results.json', rows)
	return rows


def qualify(build, out):
	build = build.resolve(); out = out.resolve(); out.mkdir(parents=True, exist_ok=False)
	options = {item['name']: item['value'] for item in json.loads(run(['meson', 'introspect', build, '--buildoptions']))}
	stage = out / 'stage'; prefix = out / 'relocated/prefix'; client = out / 'relocated/client'
	try:
		run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
		prefix.parent.mkdir(); shutil.copytree(stage / Path(options['prefix']).relative_to('/'), prefix)
		def relocate(option):
			path = Path(options[option]); return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
		compiler = relocate('bindir') / 'astrac'; library = relocate('datadir') / 'astra'; support = relocate('libdir') / 'astra/x86_64-linux'
		for name in ['diagnostics.h', 'diagnostics-hosted.c', 'diagnostics-trap.c']:
			assert (library / 'platform' / name).read_bytes() == (LIB / 'platform' / name).read_bytes()
		assert (library / 'base/diagnostics.astra').read_bytes() == (LIB / 'base/diagnostics.astra').read_bytes()
		for name in ['diagnostics-trap.o', 'diagnostics-hosted.o']:
			assert (support / name).read_bytes() == (build / 'lib/astra' / name).read_bytes()
		assert b'astra_diag_assert_fail_v0' in (support / 'target.txt').read_bytes()
		first = out / 'original'; first.mkdir(); before, rows = permutations(build / 'astrac', LIB, build / 'lib/astra', first / 'client', first)
		after, installed = permutations(compiler, library, support, client, out)
		assert before == after, 'stable relative labels must be identical without path scrubbing'
		links = link_controls(compiler, library, support, out / 'links')
		result = dict(configured={key: options[key] for key in ['prefix', 'bindir', 'datadir', 'libdir']}, compiler=str(compiler), cwd=str(client), source_permutations=len(rows), installed_permutations=len(installed), canonical={key: sha(value) for key, value in after.items()}, links=links, installed=[dict(path=str(p.relative_to(prefix)), sha256=sha(p.read_bytes())) for p in sorted(prefix.rglob('*')) if p.is_file()])
		write_json(out / 'results.json', result)
	finally:
		write_json(out / 'commands.json', COMMANDS)
	print('DIAG-1 installed relocated CLI, source orders and link controls PASS')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]), Path(sys.argv[2]))
