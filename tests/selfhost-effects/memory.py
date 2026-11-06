#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh unsuppressed normal-return memory checks on the 15 GENREF programs."""
import argparse
import json
from pathlib import Path
import re
import time
from state import RUNTIME, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	leaf = RUNTIME/('memory-v1-'+a.mode); leaf.mkdir(exist_ok=False); results = []
	programs = read(RUNTIME/('inherited-v1-'+a.mode)/'result.json')['programs'][187:]; assert len(programs) == 15
	for row in programs:
		exe = row['fresh_products']['native']; assert sha(exe['path']) == exe['sha256']
		argv = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe['path']]
		start = time.monotonic(); r = bounded_run(argv, capture_output=True, timeout=120)
		(leaf/(row['name']+'.stdout')).write_bytes(r.stdout); (leaf/(row['name']+'.stderr')).write_bytes(r.stderr)
		assert r.returncode == row['exit'] and b'in use at exit: 0 bytes in 0 blocks' in r.stderr and b'ERROR SUMMARY: 0 errors' in r.stderr and b'(suppressed: 0 from 0)' in r.stderr, (row['name'], r.stderr[-2500:])
		results.append(dict(name=row['name'], argv=argv, exit=r.returncode, seconds=time.monotonic()-start, native_sha256=exe['sha256'], stdout_sha256=sha(leaf/(row['name']+'.stdout')), stderr_sha256=sha(leaf/(row['name']+'.stderr')))); (leaf/'result.json').write_text(json.dumps(dict(status='NORMAL_RETURN_MEMORY_PASSED', mode=a.mode, programs=results, new_Astra_recoverable_error_paths=0, attribution='Fresh memory replay of the 15 inherited GENREF source programs; historical numerical Valgrind deferrals are not rerun or relabeled.'), indent=2)+'\n')
	print(a.mode, '15 fresh normal-return programs: zero errors/live allocations/suppressions', flush=True)


if __name__ == '__main__':
	main()
