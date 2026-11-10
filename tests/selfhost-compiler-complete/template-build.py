#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build a focused current Typecore/Flow observer; no target native qualification."""
import argparse
import json
import os
from pathlib import Path
import runpy
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--check', action='store_true')
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('template-'+a.version)
	build = a.build_root/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def capture(argv, name, details=None):
		if argv is None:
			write(leaf/(name+'.json'), details)
			if details and 'sources' in details:
				for source, expected in details['sources'].items():
					path = Path(source)
					if path.is_relative_to(ROOT):
						assert sha(path) == expected
						target = leaf/'source-witnesses'/path.relative_to(ROOT)
						target.parent.mkdir(parents=True, exist_ok=True)
						target.write_bytes(path.read_bytes())
			return b''
		argv = list(map(str, argv))
		if a.check and name == 'ownflow-O0':
			assert argv[:4] == ['/usr/bin/time', '-v', str(a.compiler), '-O0']
			argv = [*argv[:3], '--dump-semantics', *argv[4:argv.index('--link-object')]]
		start = time.monotonic()
		process = subprocess.Popen(argv, cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
		timed_out = False
		try:
			out, err = process.communicate(timeout=3600)
		except subprocess.TimeoutExpired:
			timed_out = True
			os.killpg(process.pid, signal.SIGKILL)
			out, err = process.communicate()
		result = subprocess.CompletedProcess(argv, process.returncode, out, err)
		(leaf/(name+'.stdout')).write_bytes(result.stdout)
		(leaf/(name+'.stderr')).write_bytes(result.stderr)
		commands.append(dict(name=name, argv=argv, exit=result.returncode, timed_out=timed_out, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands)
		print(name, result.returncode, flush=True)
		assert result.returncode == 0 and not timed_out, result.stderr.split(b'Command exited')[0][-5000:]
		if a.check and name == 'ownflow-O0':
			write(leaf/'result.json', dict(status='C0_FRONTEND_ONLY', target_native_credit=0, limitation='Actual command is --dump-semantics; the recorded native input identity is only the request. No native product or cache identity is published.'))
			raise SystemExit(0)
		return result.stdout
	base_path = ROOT/'tests/selfhost-typecore/build.py'
	base = runpy.run_path(str(base_path))
	products = base['build'](a.compiler, build, capture, ('O0',), consumer=Path(__file__).with_name('template-query.astra'), with_flow=True, product_prefix='astra-template-proof-', link_inputs=[Path(__file__), base_path])
	write(leaf/'products.json', products)
	write(leaf/'result.json', dict(status='BUILT_SEMANTIC_OBSERVER', target_native_credit=0, limitation='Current source/syntax/semantic modules and authored dependencies under C0. This diagnoses template source and Flow only; Core/CFG/SSA/LLVM/native target generation and complete compiler support are not qualified.'))


if __name__ == '__main__':
	main()
