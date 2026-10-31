# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed normal memory qualification; recursive traps remain separate."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

def main(execution, qualifier, installed, output):
	rows = []
	programs = [(execution/name, 42, False) for name in ('basic', 'retry', 'staging', 'lifetime', 'bits', 'task', 'matrix', 'reuse-O0')]
	programs += [(qualifier, 0, True), (installed/'current/client/application', 42, False)]
	for program, expected, retained_glib in programs:
		argv = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', str(program)] + (['--tap'] if retained_glib else [])
		p = subprocess.run(argv, capture_output=True, timeout=180)
		errors = re.search(rb'ERROR SUMMARY: ([0-9,]+) errors', p.stderr)
		suppressed = re.search(rb'\(suppressed: ([0-9,]+) from ([0-9,]+)\)', p.stderr)
		assert errors and suppressed, p.stderr[-4000:]
		lost = {}
		for kind in ('definitely', 'indirectly', 'possibly'):
			match = re.search((kind+r' lost: ([0-9,]+) bytes').encode(), p.stderr)
			lost[kind] = int(match[1].replace(b',', b'')) if match else 0
		live = re.search(rb'in use at exit: ([0-9,]+) bytes in ([0-9,]+) blocks', p.stderr)
		assert live
		row = {'command': argv, 'executable_sha256': hashlib.sha256(program.read_bytes()).hexdigest(), 'expected_exit': expected, 'observed_exit': p.returncode, 'default_suppressions': False, 'errors': int(errors[1].replace(b',', b'')), 'suppressed_errors': int(suppressed[1].replace(b',', b'')), 'lost_bytes': lost, 'live_bytes': int(live[1].replace(b',', b'')), 'retained_GLib_LLVM_runtime': retained_glib, 'stdout_sha256': hashlib.sha256(p.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(p.stderr).hexdigest()}
		row['status'] = 'PASS' if p.returncode == expected and row['errors'] == 0 and row['suppressed_errors'] == 0 and not any(lost.values()) and (retained_glib or row['live_bytes'] == 0) else 'FAIL'
		rows.append(row)
		output.write_text(json.dumps({'status': 'PASS' if all(r['status'] == 'PASS' for r in rows) else 'FAIL', 'receipts': rows}, separators=(',', ':'))+'\n')
		assert row['status'] == 'PASS', (row, p.stderr[-6000:])
	print(f'LAZY normal memory PASS: {len(rows)} unsuppressed runs; no lost blocks or errors')

if __name__ == '__main__':
	main(*[Path(arg).resolve() for arg in sys.argv[1:]])
