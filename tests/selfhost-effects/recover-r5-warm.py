#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measure exact R5 product reuse separately from the completed cold build."""
import argparse
import json
from pathlib import Path
import sys
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_warm_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('warm-'+a.version+'-'+a.mode); leaf.mkdir(); identity = read(a.component.with_suffix('.identity.json')); expected = sha(a.component); assert expected == identity['sha256'] and all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	directory = paths.RUNTIME/('full-build-'+a.version+'-'+a.mode); before = set(directory.glob('build-*')); argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/r5.py', 'recover-full-build', '--mode', a.mode, '--version', a.version]; start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'time', *argv], cwd=ROOT, capture_output=True, timeout=120); (leaf/'stdout').write_bytes(r.stdout); (leaf/'stderr').write_bytes(r.stderr); assert r.returncode == 0 and sha(a.component) == expected, r.stderr[-2500:]
	created = set(directory.glob('build-*')) - before; assert len(created) == 1; marker = next(iter(created))/('ownflow-'+a.mode+'-exact-reuse.json'); assert marker.is_file()
	result = dict(status='EXACT_IDENTITY_REUSE', profile=a.mode, argv=list(map(str, argv)), elapsed=time.monotonic()-start, component_sha256=expected, reuse_marker=str(marker), reuse_marker_sha256=sha(marker), limitation='Exact Astra compiler product reuse through explicit R5 routing; no Astra compiler recompilation or speedup claim. Any small C shim/provider work remains separately recorded.'); (leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(a.mode, 'EXACT_IDENTITY_REUSE', flush=True)


if __name__ == '__main__':
	main()
