#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Self-contained actual I numerical values and Context ownership regression."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
	compiler = Path(sys.argv[1]).resolve()
	out = Path(sys.argv[2]).resolve()
	out.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='run-', dir=out))
	source = ROOT / 'workloads/cad/idiomatic'
	algorithm = (source / 'src/algorithm.astra').read_text()
	# Exact production record/owner declarations, with no replacement allocator,
	# stub algorithm, raw native entry, private image or optional Python package.
	context = algorithm[algorithm.index('struct Kernel {'):algorithm.index('Kernel load_kernel(')]
	(work / 'context.astra').write_text(context)
	commands = [['/usr/bin/gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / 'workloads/cad/reference/math.c', '-o', work / 'math.o']]
	for name, files in [('numeric', [source / 'tests/numeric.astra']), ('ownership', [work / 'context.astra', ROOT / 'tests/app-cad-2/ownership.astra'])]:
		commands += [[compiler, source / 'src/numeric.astra', *files, '--link-object', work / 'math.o', '--link-library', 'm', '-o', work / name], [work / name]]
	rows = []
	for command in commands:
		process = subprocess.run(list(map(str, command)), capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(work)))
		rows.append({'argv': list(map(str, command)), 'status': process.returncode, 'stdout': process.stdout.decode(errors='backslashreplace'), 'stderr': process.stderr.decode(errors='backslashreplace')})
		(work / 'commands.json').write_text(json.dumps(rows, indent='\t') + '\n')
		assert process.returncode == 0 and not process.stdout and not process.stderr, rows[-1]
	(work / 'inputs.json').write_text(json.dumps({str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [source / 'src/algorithm.astra', source / 'src/numeric.astra', source / 'tests/numeric.astra', ROOT / 'tests/app-cad-2/ownership.astra', ROOT / 'workloads/cad/reference/math.c']}, indent='\t') + '\n')
	print('I original numerical assertions and native Context snapshot/borrow/replacement/disposal controls pass.')


if __name__ == '__main__':
	main()
