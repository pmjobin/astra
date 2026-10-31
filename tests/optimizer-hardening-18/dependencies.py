#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute installed host dependencies; not a generated-Astra qualification."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shlex
import subprocess
import tempfile
import time


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--build', type=Path, required=True)
	parser.add_argument('--runtime', type=Path, required=True)
	parser.add_argument('--liburing-prefix', type=Path, required=True)
	args = parser.parse_args()
	source = Path(__file__).with_suffix('.c').resolve()
	for p in [args.build, args.runtime]:
		assert not p.resolve().is_relative_to(source.parents[2])
		p.mkdir(parents=True, exist_ok=True)
	build = Path(tempfile.mkdtemp(prefix='dependencies-', dir=args.build.resolve()))
	runtime = Path(tempfile.mkdtemp(prefix='dependencies-', dir=args.runtime.resolve()))
	env = dict(os.environ, CCACHE_DISABLE='1',
		PKG_CONFIG_PATH=str(args.liburing_prefix.resolve() / 'lib/pkgconfig'), DEBUGINFOD_URLS='')
	flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'gobject-2.0', 'liburing'], text=True, env=env))
	evidence = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
		'scope': 'host dependency execution only; system GLib/liburing are not instrumented', 'checks': []}
	for name, sanitize in [('plain', []), ('asan-ubsan', ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']), ('tsan', ['-fsanitize=thread'])]:
		exe = build / name
		commands = [['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', *sanitize,
			str(source), *flags, '-o', str(exe)], [str(exe), *(['--uring'] if name == 'plain' else [])]]
		for cmd in commands:
			start = time.monotonic()
			p = subprocess.run(cmd, capture_output=True, text=True, timeout=60, env=env)
			evidence['checks'].append(dict(command=cmd, exit=p.returncode, seconds=time.monotonic()-start, stdout=p.stdout, stderr=p.stderr))
			(runtime / 'checks.json').write_text(json.dumps(evidence, indent=2)+'\n')
			print(name, 'compile' if cmd[0]=='clang' else 'execution', p.returncode, flush=True)
			if p.returncode: break
	print(runtime / 'checks.json')
	return 0 if len(evidence['checks']) == 6 and all(c['exit'] == 0 for c in evidence['checks']) else 1


if __name__ == '__main__': raise SystemExit(main())
