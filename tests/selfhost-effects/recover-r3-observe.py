#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe actual Error ancestry, origin, snapshot and destruction externally."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--native-version'); p.add_argument('--oracle-only', action='store_true'); a = p.parse_args(); assert a.version.isalnum(); assert a.oracle_only or a.native_version
	paths = load_module('r3_observer_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r3-observer-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; results = []
	def run(argv, name, environment=None, allowed=(0,)):
		argv = list(map(str, argv)); parent = dict(os.environ, CCACHE_DISABLE='1'); parent.pop('LD_PRELOAD', None)
		if environment and environment.get('LD_PRELOAD'): argv = ['/usr/bin/env', 'LD_PRELOAD='+environment['LD_PRELOAD'], *argv]
		start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=parent, capture_output=True, timeout=120); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')), LD_PRELOAD=(environment or {}).get('LD_PRELOAD'))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-3000:]); return r
	if a.oracle_only:
		programs = [('C0', paths.BUILD/('frontier-'+('literalbefore2' if a.mode == 'O0' else 'literalbefore')+'-'+a.mode)/'literal-exact-catch-C0')]
	else:
		qualification = read(paths.RUNTIME/('early-'+a.native_version+'-'+a.mode)/'result.json'); assert all(row['Astra_effect_ELF'] for row in qualification['programs']); directory = paths.BUILD/('early-'+a.native_version+'-'+a.mode); programs = [(label, directory/('literal-exact-catch-'+label)) for label in ('Astra', 'C0')]
	for compiler in ('gcc', 'clang'):
		library = build/(compiler+'.so'); run([compiler, '-std=c11', '-'+a.mode, '-fPIC', '-shared', '-Wall', '-Wextra', '-Werror', ROOT/'tests/selfhost-effects/r3-error-observer.c', '-o', library], compiler+'-build')
		for label, program in programs:
			environment = dict(os.environ, LD_PRELOAD=str(library)); environment.pop('VALGRIND_OPTS', None); r = run([program], compiler+'-'+label+'-observe', environment, (42,)); assert b'R3_ERROR_OBSERVER valid=1 snapshots=1 errors=1 live=0' in r.stderr
			results.append(dict(observer_compiler=compiler, observer_sha256=sha(library), program=label, ELF_sha256=sha(program), actual_exit=r.returncode, observation=r.stderr.decode()))
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_ONLY_DYNAMIC_ERROR_OBSERVATION' if a.oracle_only else 'INDEPENDENT_C0_ASTRA_DYNAMIC_ERROR_OBSERVATION', profile=a.mode, source_sha256=sha(ROOT/'tests/selfhost-effects/r3-error-observer.c'), observations=results, primary_corpus_credit=0, limitation='GNU/Linux allocation interposition observes the actual private payload; plain unsuppressed Valgrind runs are retained separately, without interposition.'), indent=2)+'\n'); print(a.mode, 'independent dynamic Error ancestry/origin/snapshot/lifetime observed', flush=True)


if __name__ == '__main__':
	main()
