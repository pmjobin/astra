#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Prove the existing 1024-handle boundary before LLVM sees a large signature."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, bounded_run, read, sha


def source(parameters):
	fields = ' '.join('int f'+str(i)+';' for i in range(8))
	arguments = ', '.join('Eight p'+str(i) for i in range(parameters))
	return 'struct Eight { '+fields+' }\nint large('+arguments+') throws Error { return 17; }\nint main() { return 42; }\n'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('abi_limit_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('abi-limit-'+a.version); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; results = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, label, expected):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300); (leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (label, r.stdout[-1000:], r.stderr[-2000:]); return r
	for count, admitted in [(127, True), (128, False)]:
		name = str(count); path = leaf/(name+'.astra'); path.write_text(source(count)); inputs = [path, ROOT/'lib/astra/base/errors.astra']; target = build/(name+'.ll'); target.write_text('private carrier boundary sentinel\n'); before = sha(target)
		r = run([a.component, '--native', target, *inputs], name+'-Astra', 0 if admitted else 5)
		if admitted:
			run(['opt', '-passes=verify', '-disable-output', target], name+'-verify', 0)
		else:
			assert b'LLVM_DEFERRED: carrier handle capacity' in r.stderr and sha(target) == before
			# C0 can describe the source. Its larger internal vector is not reused
			# or used to raise this compiler's existing bounded adapter capacity.
		oracle = run([C0, '-O0', '--dump-llvm', *inputs], name+'-C0', 0); c0 = build/(name+'-C0.ll'); c0.write_bytes(oracle.stdout); run(['opt', '-passes=verify', '-disable-output', c0], name+'-C0-verify', 0)
		results.append(dict(source_sha256=sha(path), source_parameters=count, physical_parameters=count*8+1, admitted=admitted, destination_preserved=not admitted, C0_LLVM_sha256=sha(c0)))
	(leaf/'result.json').write_text(json.dumps(dict(status='PHYSICAL_HANDLE_BOUNDARY_ONLY', component_sha256=sha(a.component), Astra_effect_ELFs=0, capacity=1024, results=results), indent=2)+'\n'); print('1017 physical channels admitted; 1025 safely deferred before LLVM construction', flush=True)


if __name__ == '__main__':
	main()
