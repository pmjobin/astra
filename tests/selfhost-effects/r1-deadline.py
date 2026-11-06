#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Prove timeout termination includes an owned command's sleeping descendant."""
import json
import argparse
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	runtime = ROOT.parent/'codex/work/astra/runtime/effects25-r1'
	pidfile = runtime/('deadline-child-'+a.version+'.pid'); assert not pidfile.exists()
	program = 'import subprocess,sys,time; from pathlib import Path; child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); Path(sys.argv[1]).write_text(str(child.pid)); time.sleep(60)'
	start = time.monotonic()
	try:
		bounded_run([sys.executable, '-c', program, str(pidfile)], timeout=0.3, capture_output=True)
		raise AssertionError('deadline did not fire')
	except subprocess.TimeoutExpired:
		elapsed = time.monotonic()-start
	assert pidfile.is_file()
	pid = int(pidfile.read_text()); proc = Path('/proc')/str(pid)
	state = 'absent'
	try: state = (proc/'stat').read_text().split(') ', 1)[1].split()[0]
	except (FileNotFoundError, ProcessLookupError): pass
	assert state in ('absent', 'Z', 'X'), state
	result = dict(status='PASS', deadline_seconds=0.3, elapsed_seconds=elapsed, child_pid=pid, child_state=state, classification='Harness process-group termination only; compiler resource ceilings unchanged')
	(runtime/'process-deadline.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result), flush=True)


if __name__ == '__main__':
	main()
