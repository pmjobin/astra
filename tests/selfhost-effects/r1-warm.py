#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measure one exact compiler-product reuse, separately from cold compilation."""
import argparse
import json
import sys
import time
from state import ROOT, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	base = ROOT.parent/'codex/work/astra'; runtime = base/'runtime/effects25-r1'
	component = base/'build/effects25-r1'/('compiler-v1-'+a.mode)/('astra-llvm-'+a.mode)
	expected = sha(component); attempts = runtime/('compiler-build-v1-'+a.mode); before = set(attempts.glob('build-*'))
	start = time.monotonic(); argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/r1-full-build.py', '--mode', a.mode]
	r = bounded_run(['/usr/bin/time', '-v', '-o', runtime/('warm-'+a.mode+'.time'), *argv], cwd=ROOT, capture_output=True, timeout=120)
	(runtime/('warm-'+a.mode+'.stdout')).write_bytes(r.stdout); (runtime/('warm-'+a.mode+'.stderr')).write_bytes(r.stderr)
	assert r.returncode == 0 and sha(component) == expected, r.stderr[-2500:]
	created = set(attempts.glob('build-*')) - before; assert len(created) == 1
	marker = next(iter(created))/('ownflow-'+a.mode+'-exact-reuse.json'); assert marker.is_file()
	result = dict(status='EXACT_REUSE_VERIFIED', mode=a.mode, argv=list(map(str, argv)), seconds=time.monotonic()-start, product_sha256=expected, reuse_marker=str(marker), reuse_marker_sha256=sha(marker), classification='Identity/cache reuse, not a new compilation or matched-workload speedup')
	(runtime/('warm-'+a.mode+'.json')).write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result), flush=True)


if __name__ == '__main__':
	main()
