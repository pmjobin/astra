# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise the actual consumer through tree and relocated installed compilers."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['types.astra', 'validate.astra', 'policy.astra', 'main.astra']
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']


def qualify(build, out):
	out.mkdir(parents=True, exist_ok=False)
	commands, rows, canonical = [], [], {}
	env = dict(os.environ, CCACHE_DISABLE='1')
	def run(argv, cwd=ROOT):
		argv = list(map(str, argv)); result = subprocess.run(argv, cwd=cwd, capture_output=True, env=env)
		commands.append(dict(argv=argv, cwd=str(cwd), status=result.returncode))
		(out / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
		assert result.returncode == 0, (argv, result.returncode, result.stderr.decode())
		return result
	options = {row['name']: row['value'] for row in json.loads(run(['meson', 'introspect', build, '--buildoptions']).stdout)}
	stage, prefix = out / 'stage', out / 'relocated/prefix'
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	prefix.parent.mkdir(); shutil.move(stage / Path(options['prefix']).relative_to('/'), prefix)
	def installed(option):
		path = Path(options[option]); return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
	compiler = installed('bindir') / 'astrac'; data = installed('datadir') / 'astra'
	assert compiler.read_bytes() == (build / 'astrac').read_bytes()
	assert (data / 'docs/language/enums.md').read_bytes() == (ROOT / 'docs/language/enums.md').read_bytes()
	for name in SOURCES + ['README.md']:
		assert (data / 'examples/enums' / name).read_bytes() == (ROOT / 'examples/enums' / name).read_bytes()
	canonical_binary = None
	for route, selected, sources in [('tree', build / 'astrac', ROOT / 'examples/enums'), ('installed', compiler, data / 'examples/enums')]:
		client = out / route; client.mkdir()
		for name in SOURCES:
			shutil.copyfile(sources / name, client / name)
		for number, order in enumerate(itertools.permutations(SOURCES)):
			for stage_name in STAGES:
				result = run([selected, '--dump-' + stage_name, *order], client); assert not result.stderr
				if stage_name not in canonical:
					canonical[stage_name] = result.stdout; (out / ('canonical.' + stage_name)).write_bytes(result.stdout)
				assert result.stdout == canonical[stage_name], (route, order, stage_name)
			exe = client / ('consumer-' + str(number)); result = run([selected, *order, '-o', exe], client); assert not result.stdout and not result.stderr
			identity = hashlib.sha256(exe.read_bytes()).hexdigest()
			if canonical_binary is None:
				canonical_binary = identity
			assert identity == canonical_binary, (route, order)
			result = run([exe], client); assert not result.stdout and not result.stderr
			rows.append(dict(route=route, order=order, binary_sha256=identity))
			# A concrete generic record is an enum payload; the generic function still
			# receives only its old non-enum companion domain.
		generic = client / 'generic.astra'
		generic.write_text('struct Box<T>{T value;} enum Outcome{Ready(Box<int> box),Empty} T identity<T>(T value){return value;} Outcome make(){Box<int> box={value=identity<int>(7)};return Outcome.Ready(box);} int main(){match(make()){case Outcome.Ready(box):{return box.value-7;}else:{return 1;}}}\n')
		exe = client / 'generic'; run([selected, generic.name, '-o', exe], client); result = run([exe], client); assert not result.stdout and not result.stderr
	(out / 'results.json').write_text(json.dumps(dict(rows=rows, source_orders=48, stage_comparisons=432, generic_companion_controls=2, prefix=str(prefix), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), canonical={stage: hashlib.sha256(value).hexdigest() for stage, value in canonical.items()}, source_root=str(ROOT), client_root=str(out)), indent='\t') + '\n')
	print('48 consumer source orders, 432 exact stage comparisons, two generic companion controls')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
