#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build all production compiler modules with a focused native test entry."""
import argparse
import json
import os
from pathlib import Path
import runpy
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, git, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--check', action='store_true')
	p.add_argument('--snapshot', action='store_true', help='compile immutable Git-authenticated inputs while live engineering continues')
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('native-'+a.version+'-'+a.mode); build = a.build_root/leaf.name
	leaf.mkdir(); build.mkdir()
	source_root = ROOT
	if a.snapshot:
		source_root = leaf/'source-inputs'; source_root.mkdir()
		revision = git('rev-parse', 'HEAD').decode().strip(); rows = []
		tracked = git('ls-files', '-z', 'compiler', 'lib/astra', 'lib/runtime/platform').decode().split('\0')
		names = sorted({name for name in tracked if name and Path(name).suffix in ('.astra', '.c', '.h')} | {'tests/selfhost-typecore/build.py', 'tests/selfhost-parser/controls.astra', 'tests/selfhost-parser/cursors.astra', 'tests/selfhost-compiler-complete/native-query.astra'})
		for name in names:
			path = ROOT/name; raw = path.read_bytes(); assert git('show', revision+':'+name) == raw, name
			target = source_root/name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(raw); target.chmod(0o444)
			rows.append(dict(original_path=str(path), input_path=str(target), sha256=sha(target), bytes=len(raw), mode='0444'))
		write(leaf/'snapshot.json', dict(revision=revision, sources=rows, limitation='Immutable build-input archive, not another Git checkout. Extra archived libraries receive no translation credit; the actual command/input identity determines consumed modules.'))
	commands = []
	def capture(argv, name, details=None):
		if argv is None:
			write(leaf/(name+'.json'), details)
			if details and 'sources' in details:
				for source, expected in details['sources'].items():
					path = Path(source)
					if path.is_relative_to(source_root):
						assert sha(path) == expected
						target = leaf/'source-witnesses'/path.relative_to(source_root); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(path.read_bytes())
			return b''
		argv = list(map(str, argv))
		if a.check and name == 'ownflow-'+a.mode:
			assert argv[:4] == ['/usr/bin/time', '-v', str(a.compiler), '-'+a.mode]
			argv = [*argv[:3], '--dump-semantics', *argv[4:argv.index('--link-object')]]
		start = time.monotonic()
		process = subprocess.Popen(argv, cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
		timed_out = False
		try:
			out, err = process.communicate(timeout=3600)
		except subprocess.TimeoutExpired:
			timed_out = True; os.killpg(process.pid, signal.SIGKILL); out, err = process.communicate()
		(leaf/(name+'.stdout')).write_bytes(out); (leaf/(name+'.stderr')).write_bytes(err)
		commands.append(dict(name=name, argv=argv, exit=process.returncode, timed_out=timed_out, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands); print(name, process.returncode, flush=True)
		assert process.returncode == 0 and not timed_out, err.split(b'Command exited')[0][-5000:]
		if a.check and name == 'ownflow-'+a.mode:
			write(leaf/'result.json', dict(status='C0_FRONTEND_ONLY', target_native_credit=0, limitation='Actual --dump-semantics command only. No native product, cache identity or full source translation is published.'))
			raise SystemExit(0)
		return out
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split(); shim_source = source_root/'compiler/backend/llvm/capi.c'; shim = build/'llvm-capi.o'
	deps = subprocess.check_output(['gcc', '-std=c11', *flags, '-M', shim_source], text=True).replace('\\\n', ' ').split(':', 1)[1].split()
	capture(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', shim_source, '-o', shim], 'llvm-capi')
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'native'], text=True).strip(); assert library.startswith('-l') and ' ' not in library
	library_path = Path(subprocess.check_output(['llvm-config', '--libdir'], text=True).strip())/('lib'+library[2:]+'.so')
	compiler_sources = sorted((source_root/'compiler').rglob('*.astra'))
	tracked = git('ls-files', '-z', 'compiler').decode().split('\0')
	assert {str(p.relative_to(source_root)) for p in compiler_sources} == {p for p in tracked if p.endswith('.astra')}
	base_path = source_root/'tests/selfhost-typecore/build.py'; base = runpy.run_path(str(base_path))
	automatic = {*(source_root/'compiler/source').glob('*.astra'), *(source_root/'compiler/syntax').glob('*.astra'), *(source_root/'compiler/semantic').glob('*.astra')}
	extra = [p for p in compiler_sources if p not in automatic]
	write(leaf/'scope.json', dict(compiler_modules=len(compiler_sources), compiler_sources={str(p):sha(p) for p in compiler_sources}, retained_test_entry='native-query.astra', limitation='All current production compiler modules form the C0-built test host. Historical regression dispatch is absent from this host only. Frozen original target inputs are selected separately and are never pruned by this recipe. No cold speedup, inherited qualification or Stage1 credit.'))
	products = base['build'](a.compiler, build, capture, (a.mode,), consumer=source_root/'tests/selfhost-compiler-complete/native-query.astra', with_flow=True, extra_sources=extra, product_prefix='astra-native-probe-', link_objects=[shim], link_libraries=[library[2:]], link_inputs=[library_path, *map(Path, deps), Path(__file__), Path(__file__).with_name('run.py'), base_path])
	write(leaf/'products.json', products)
	write(leaf/'result.json', dict(status='BUILT_COMPLETE_PRODUCTION_TEST_HOST', target_native_credit=0, limitation='C0-built development host with all current production modules. Actual target source-to-native execution must be proved separately. No complete original compiler translation, inherited regression or Stage1 claim follows from this build.'))


if __name__ == '__main__':
	main()
