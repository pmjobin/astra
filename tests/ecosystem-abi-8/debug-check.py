# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently decode public debug products and exercise a source debugger."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_path, output_path):
	compiler = Path(compiler_path).resolve()
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='debug-', dir=output))
	rows = []
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), source_sha256=sha(HERE/'debug-probe.astra'), checks=rows)

	def run(command, expected=0, contains=()):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == expected and all(text in p.stdout + p.stderr for text in contains)
		rows.append(dict(command=command, expected_exit=expected, exit=p.returncode,
			stdout=p.stdout, stderr=p.stderr, passed=valid))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
		return p.stdout

	for level in (0, 1, 2):
		for debug in (False, True):
			product = out/f'probe-O{level}-g{int(debug)}'
			flags = ['-g'] if debug else []
			run([compiler, f'-O{level}', *flags, HERE/'debug-probe.astra', '-o', product])
			run([product])
			sections = run(['readelf', '-S', product])
			assert ('.debug_info' in sections and '.debug_line' in sections) == debug
			dependencies = run(['readelf', '-d', product])
			assert 'libgobject' not in dependencies and 'libglib' not in dependencies
			if debug:
				run(['llvm-dwarfdump', '--verify', product], contains=('No errors.',))
				run(['readelf', '--debug-dump=decodedline', product], contains=('debug-probe.astra',))

	info = run(['llvm-dwarfdump', '--debug-info', out/'probe-O0-g1'],
		contains=('DW_TAG_formal_parameter', 'DW_TAG_variable', '"input"', '"local"', '"analyze"', 'Astra Stage 0'))
	assert 'DW_AT_location' in info
	if shutil.which('gdb'):
		run(['gdb', '--nx', '--batch', '-ex', 'set debuginfod enabled off',
			'-ex', f'break {HERE / "debug-probe.astra"}:6', '-ex', 'run',
			'-ex', 'print input', '-ex', 'print local', '-ex', 'continue', out/'probe-O0-g1'],
			contains=('Breakpoint 1,', '$1 = 35', '$2 = 42', 'exited normally'))
		run(['gdb', '--nx', '--batch', '-ex', 'set debuginfod enabled off',
			'-ex', f'break {HERE / "debug-probe.astra"}:11', '-ex', 'run',
			'-ex', 'print reading', '-ex', 'print local_float', '-ex', 'continue', out/'probe-O0-g1'],
			contains=('Breakpoint 1,', '$1 = 1.25', '$2 = 3.75', 'exited normally'))
	else:
		receipt['debugger'] = 'GDB unavailable; bounded independent DWARF validation only'

		# Lexical normalization must preserve actual filesystem traversal via symlinks.
	(out/'real/inside').mkdir(parents=True)
	(out/'real/probe.astra').write_bytes((HERE/'debug-probe.astra').read_bytes())
	(out/'link').symlink_to(out/'real/inside', target_is_directory=True)
	traversal = out/'link/../probe.astra'
	run([compiler, '-g', traversal, '-o', out/'traversal'])
	run([out/'traversal'])
	run(['llvm-dwarfdump', '--verify', out/'traversal'], contains=('No errors.',))
	if shutil.which('gdb'):
		run(['gdb', '--nx', '--batch', '-ex', 'set debuginfod enabled off',
			'-ex', f'break {traversal}:6', '-ex', 'run', '-ex', 'list 6',
			'-ex', 'print input', '-ex', 'print local', '-ex', 'continue', out/'traversal'],
			contains=('return local;', '$1 = 35', '$2 = 42', 'exited normally'))

	for arguments in (['-g', '--help'], ['-g', '--parse', HERE/'debug-probe.astra'], ['-g', '--dump-ssa', HERE/'debug-probe.astra']):
		run([compiler, *arguments], expected=2)
	run([compiler, '-g', '--check', HERE/'debug-probe.astra'])
	run([compiler, '-g', '-g', '--dump-llvm', HERE/'debug-probe.astra'], contains=('!DICompileUnit', '!DILocation', '#dbg_declare'))
	receipt['products'] = {p.name: sha(p) for p in out.glob('probe-*')}
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS: public debug O0/O1/O2 parity, DWARF and debugger; evidence {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
