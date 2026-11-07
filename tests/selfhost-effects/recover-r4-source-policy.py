#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Attribute the live original Class/member frontier without creating authority."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--original-version'); p.add_argument('--view-version'); p.add_argument('--minimal-view-version'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_source_policy_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-source-policy-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; results = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	for name, version in [('original', a.original_version), ('original-view', a.view_version), ('r4-original-view', a.minimal_view_version)]:
		version = version or a.version; assert version.isalnum()
		attempt = read(paths.RUNTIME/(name+'-'+version+'-'+a.mode)/'result.json'); inputs = attempt['inputs']; assert all(sha(row['path']) == row['sha256'] for row in inputs); argv = [str(a.component), '--r4-source-policy', *[row['path'] for row in inputs]]; start = time.monotonic(); env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=env, capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == 0, (name, r.stderr[-2000:]); classes = [line for line in r.stdout.decode().splitlines() if line.startswith('R4_CLASS ')]; results.append(dict(name=name, version=version, inputs=inputs, observation_sha256=sha(leaf/(name+'.stdout')), checked=[line for line in r.stdout.decode().splitlines() if line.startswith('R4_CHECKED ')], classes=classes)); print(a.mode, name, len(classes), 'actual Class policies observed', flush=True)
	for row in results:
		raw = (leaf/(row['name']+'.stdout')).read_bytes(); assert re.findall(rb'^R4_PROFILE (.+)$', raw, re.M) == [b'PRIVATE_FIELDED_EFFECTS']
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_ORIGINAL_SOURCE_POLICY_OBSERVATION', profile=a.mode, semantic_profile='Explicit private checked_build_effects_profile', component_sha256=sha(a.component), populations=results, Astra_native_program_credit=0, limitation='These read-only source/member/layout eligibility queries are not native execution, an owner-root proof, whole-module admission or a replacement for any verifier. Exact original attempts, emitted products and first source stops remain separately attributed.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
