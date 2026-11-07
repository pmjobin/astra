#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measure exact product reuse and verify bounded descendant termination."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, load_module, bounded_run, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0','O2')); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); p.add_argument('--deadline', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('recover_warm_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('warm-'+a.version+('-'+a.mode if a.mode else '')); leaf.mkdir()
	if a.deadline:
		pidfile = leaf/'owned-child.pid'; program = 'import subprocess,sys,time; from pathlib import Path; child=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); Path(sys.argv[1]).write_text(str(child.pid)); time.sleep(60)'; start = time.monotonic()
		try: bounded_run([sys.executable,'-c',program,str(pidfile)],timeout=0.3,capture_output=True); raise AssertionError('Deadline failed')
		except subprocess.TimeoutExpired: elapsed = time.monotonic()-start
		pid = int(pidfile.read_text()); state = 'absent'
		try: state = (Path('/proc')/str(pid)/'stat').read_text().split(') ',1)[1].split()[0]
		except (FileNotFoundError,ProcessLookupError): pass
		assert state in ('absent','Z','X'); result = dict(status='OWNED_PROCESS_GROUP_DEADLINE_VERIFIED', deadline=0.3, elapsed=elapsed, child_pid=pid, child_state=state)
	else:
		assert a.mode and a.component; expected = sha(a.component); before = set((paths.RUNTIME/('full-build-'+a.version+'-'+a.mode)).glob('build-*')); argv = [sys.executable,'-B',ROOT/'tests/selfhost-effects/recover-full-build.py','--mode',a.mode,'--version',a.version]; start = time.monotonic(); r = bounded_run(['/usr/bin/time','-v','-o',leaf/'time',*argv],cwd=ROOT,capture_output=True,timeout=120); (leaf/'stdout').write_bytes(r.stdout); (leaf/'stderr').write_bytes(r.stderr); assert r.returncode == 0 and sha(a.component) == expected, r.stderr[-2500:]
		created = set((paths.RUNTIME/('full-build-'+a.version+'-'+a.mode)).glob('build-*'))-before; assert len(created) == 1; marker = next(iter(created))/('ownflow-'+a.mode+'-exact-reuse.json'); assert marker.is_file(); result = dict(status='EXACT_IDENTITY_REUSE', profile=a.mode, argv=list(map(str,argv)), elapsed=time.monotonic()-start, component_sha256=expected, reuse_marker=str(marker), reuse_marker_sha256=sha(marker), limitation='Exact cached product reuse; no compilation or matched-workload speedup is claimed')
	(leaf/'result.json').write_text(json.dumps(result,indent=2)+'\n'); print(result['status'],flush=True)


if __name__ == '__main__':
	main()
