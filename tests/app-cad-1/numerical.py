#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the exact retained CAD numerical foundation without PNG/Python packages."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
	compiler = Path(sys.argv[1]).resolve()
	out = Path(sys.argv[2]).resolve()
	out.mkdir(parents=True, exist_ok=True)
	# Every invocation gets a fresh binary root; a failed compile cannot run a
	# previous executable. Meson roots are inside this campaign's build tree.
	import tempfile
	work = Path(tempfile.mkdtemp(prefix='run-', dir=out))
	reference = ROOT / 'workloads/cad/reference'
	origins = json.loads((reference / 'origins.json').read_text())
	for row in origins['files']:
		path = ROOT / 'workloads/cad' / row['path']
		assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], path
	cc = shutil.which('gcc')
	assert cc, 'the accepted compiler test toolchain requires gcc'
	commands = [[cc, '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', str(reference / 'math.c'), '-o', str(work / 'math.o')], [str(compiler), str(reference / 'numeric.astra'), str(reference / 'numeric-tests.astra'), '--link-object', str(work / 'math.o'), '--link-library', 'm', '-o', str(work / 'numeric-tests')], [str(work / 'numeric-tests')]]
	rows = []
	for command in commands:
		p = subprocess.run(command, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(work)))
		rows.append({'argv': command, 'status': p.returncode, 'stdout': p.stdout.decode(errors='backslashreplace'), 'stderr': p.stderr.decode(errors='backslashreplace')})
		(work / 'commands.json').write_text(json.dumps(rows, indent='\t') + '\n')
		assert p.returncode == 0 and not p.stderr and not p.stdout, rows[-1]
	print('Exact CAD f415381 numerical source and original native assertions pass; no PNG or oracle packages required.')


if __name__ == '__main__':
	main()
