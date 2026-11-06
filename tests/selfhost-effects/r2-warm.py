#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact full-product reuse and independently bounded process-group control."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, sha, bounded_run, load_module


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2')); p.add_argument('--deadline', action='store_true'); a = p.parse_args()
	state = load_module('r2_warm_state', ROOT/'tests/selfhost-effects/r2-state.py')
	if a.deadline:
		pidfile = state.RUNTIME/'deadline-child.pid'; assert not pidfile.exists()
		program = 'import subprocess,sys,time; from pathlib import Path; child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); Path(sys.argv[1]).write_text(str(child.pid)); time.sleep(60)'
		start = time.monotonic()
		try:
			bounded_run([sys.executable, '-c', program, str(pidfile)], timeout=0.3, capture_output=True)
			raise AssertionError('deadline did not fire')
		except subprocess.TimeoutExpired: elapsed = time.monotonic()-start
		pid = int(pidfile.read_text()); child = Path('/proc')/str(pid); status = 'absent'
		try: status = (child/'stat').read_text().split(') ', 1)[1].split()[0]
		except (FileNotFoundError, ProcessLookupError): pass
		assert status in ('absent', 'Z', 'X'), status
		result = dict(status='PASS', deadline_seconds=0.3, elapsed_seconds=elapsed, child_pid=pid, child_state=status)
		(state.RUNTIME/'process-deadline.json').write_text(json.dumps(result, indent=2)+'\n'); print(result); return
	assert a.mode
	component = state.BUILD/('compiler-v1-'+a.mode)/('astra-llvm-'+a.mode); expected = sha(component)
	attempts = state.RUNTIME/('compiler-build-v1-'+a.mode); before = set(attempts.glob('build-*'))
	start = time.monotonic(); argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/r2-build.py', '--mode', a.mode]
	r = bounded_run(['/usr/bin/time', '-v', '-o', state.RUNTIME/('warm-'+a.mode+'.time'), *argv], cwd=ROOT, capture_output=True, timeout=120)
	(state.RUNTIME/('warm-'+a.mode+'.stdout')).write_bytes(r.stdout); (state.RUNTIME/('warm-'+a.mode+'.stderr')).write_bytes(r.stderr)
	assert r.returncode == 0 and sha(component) == expected, r.stderr[-2500:]
	created = set(attempts.glob('build-*')) - before; assert len(created) == 1
	marker = next(iter(created))/('ownflow-'+a.mode+'-exact-reuse.json'); assert marker.is_file()
	result = dict(status='EXACT_REUSE_VERIFIED', mode=a.mode, argv=list(map(str, argv)), seconds=time.monotonic()-start, product_sha256=expected, reuse_marker=str(marker), reuse_marker_sha256=sha(marker), classification='Identity reuse, not compilation or a matched-workload speedup')
	(state.RUNTIME/('warm-'+a.mode+'.json')).write_text(json.dumps(result, indent=2)+'\n'); print(result)


if __name__ == '__main__':
	main()
