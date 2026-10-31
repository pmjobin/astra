# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only qualification identities; JSON output belongs in external runtime."""
from pathlib import Path
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main(build_path, output_path):
	build, output = Path(build_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	receipt = dict(commands=[], identities={})
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

	def identify(path):
		p = Path(path)
		if p.is_file(): receipt['identities'][str(p.resolve())] = dict(sha256=sha(p), bytes=p.stat().st_size)

	def run(command):
		p = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, text=True, timeout=60)
		receipt['commands'].append(dict(command=list(map(str, command)), exit=p.returncode, stdout=p.stdout, stderr=p.stderr))
		assert p.returncode == 0, receipt['commands'][-1]
		return p.stdout

	for command in [['git', 'rev-parse', 'HEAD', 'HEAD^{tree}'], ['git', 'status', '--porcelain=v1'],
		['git', 'worktree', 'list', '--porcelain'], ['git', 'stash', 'list'], ['git', 'show-ref'],
		['uname', '-a'], ['pkg-config', '--modversion', 'gobject-2.0', 'glib-2.0', 'girepository-2.0'],
		['pkg-config', '--cflags', '--libs', 'gobject-2.0'], ['llvm-config', '--version']]:
		run(command)
	for name, arguments in [('cc', ['--version']), ('clang', ['--version']), ('valac', ['--version']),
		('python3', ['--version']), ('meson', ['--version']), ('ninja', ['--version']), ('gdb', ['--version']),
		('valgrind', ['--version']), ('readelf', ['--version']), ('llvm-dwarfdump', ['--version']),
		('nm', ['--version']), ('ld', ['--version']), ('pkg-config', ['--version'])]:
		selected = shutil.which(name); assert selected
		identify(selected); run([selected, *arguments])
	identify(build/'astrac')
	for name in ['intro-buildoptions.json', 'intro-compilers.json', 'intro-buildsystem_files.json']:
		p = build/'meson-info'/name
		identify(p)
		receipt[name] = json.loads(p.read_text())
	assert str(ROOT/'meson.build') in receipt['intro-buildsystem_files.json']
	for executable in [build/'astrac', *sorted((build/'ecosystem-abi-8').rglob('program'))]:
		if executable.is_file():
			identify(executable)
			text = run(['ldd', executable])
			for path in re.findall(r'(?:=>\s*)?(/[^\s()]+)', text): identify(path)
			if executable == build/'astrac': run(['readelf', '-d', executable])
			# Actual transitive header set for both adapter and generated bridge contracts.
	flags = shlex.split(run(['pkg-config', '--cflags', 'gobject-2.0']))
	for source in [ROOT/'lib/runtime/interop/gobject.c', ROOT/'lib/runtime/interop/gobject-signals.c', ROOT/'tests/ecosystem-abi-8/counter.c']:
		text = run(['/usr/bin/clang', '-M', '-I'+str(ROOT/'lib/runtime/interop'), *flags, source])
		for name in shlex.split(text.replace('\\\n', ' '))[1:]: identify(ROOT/name if not Path(name).is_absolute() else name)
	for name in ['/usr/share/gir-1.0/GObject-2.0.gir', '/usr/share/gir-1.0/GLib-2.0.gir', '/usr/lib64/girepository-1.0/GObject-2.0.typelib']:
		identify(name)
	prefix = Path(os.environ.get('ASTRA_LIBURING_PREFIX', str(Path.home()/'.local/opt/liburing-2.15')))
	for path in [prefix/'include/liburing.h', prefix/'include/liburing/io_uring_version.h', prefix/'lib/liburing.a']:
		identify(path)
		# Include every tracked source/recipe and task-owned untracked path only.
	paths = run(['git', 'ls-files', '-z']).split('\0')
	initial = output.parent/'initial-state.json'
	protected = {r['path'] for r in json.loads(initial.read_text())['untracked']} if initial.exists() else set()
	for name in run(['git', 'ls-files', '--others', '--exclude-standard', '-z']).split('\0'):
		if name and name not in protected: paths.append(name)
		# The derived evidence document cannot include a hash of its own next bytes.
	receipt['source_sha256'] = {name: sha(ROOT/name) for name in paths if name and name != 'docs/ecosystem-abi-8-evidence.json' and (ROOT/name).is_file()}
	receipt['scope'] = 'Exact local host identities. Compiler host GLib dependencies are distinct from selected target dependencies; no cross-target qualification.'
	output.write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: source/tool/header/library/build identities written to {output}')


if __name__ == '__main__':
	main(*sys.argv[1:])
