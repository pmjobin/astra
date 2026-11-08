#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual source receiver identities and ABI plans, without LLVM emission."""
import argparse
import json
import os
from pathlib import Path
import runpy
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--diagnose', action='store_true'); p.add_argument('--core-check', action='store_true')
	a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('abi_source_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('abi-source-'+a.version); build = paths.BUILD/leaf.name
	leaf.mkdir(); build.mkdir()
	source = ROOT/'compiler/backend/llvm/recover-storage-abi.astra'
	data = source.read_bytes(); end = data.index(b'// Compare physical types against the original nominal table')
	view = leaf/'actual-abi-source.astra'; view.write_bytes(data[:end])
	commands = []
	def capture(argv, name, details=None):
		if argv is None:
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n')
			if details and 'sources' in details:
				for name, expected in details['sources'].items():
					path = Path(name)
					if path.is_relative_to(ROOT):
						assert sha(path) == expected
						target = leaf/'source-witnesses'/path.relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True)
						if target.exists(): assert sha(target) == expected
						else: target.write_bytes(path.read_bytes())
			return b''
		argv = list(map(str, argv))
		if a.core_check and name.startswith('typecore-'): argv = [*argv[:3], '--dump-core', *argv[4:argv.index('--link-object')]]
		start = time.monotonic()
		r = bounded_run(argv, cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=3600)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name,r.returncode,flush=True)
		assert r.returncode == 0,r.stderr.split(b'Command being timed')[0][-3000:]
		if a.core_check and name.startswith('typecore-'): raise SystemExit(0)
		return r.stdout
	base_path = ROOT/'tests/selfhost-typecore/build.py'
	base = runpy.run_path(str(base_path))
	products = base['build'](C0, build, capture, ('O0',), consumer=ROOT/'tests/selfhost-effects/recover-abi-source-query.astra', extra_sources=[view], product_prefix='astra-abi-source-', link_inputs=[Path(__file__), source, base_path, ROOT/'tests/selfhost-effects/r5-resume.py'])
	exe = build/'astra-abi-source-O0'
	fixture = paths.RUNTIME/'native-frontiers-errororacle2-O0/result.json'
	witness = next(row for row in read(fixture)['programs'] if row['name'] == 'derived-error-computed-base')
	assert all(sha(row['path']) == row['sha256'] for row in witness['inputs'])
	argv = [exe, '--diagnose' if a.diagnose else '--verify', *[row['path'] for row in witness['inputs']]]
	start = time.monotonic()
	r = bounded_run(['/usr/bin/time','-v','-o',leaf/'observe.time',*map(str,argv)],cwd=build,env=dict(os.environ,CCACHE_DISABLE='1'),capture_output=True,timeout=300)
	(leaf/'observe.stdout').write_bytes(r.stdout); (leaf/'observe.stderr').write_bytes(r.stderr)
	commands.append(dict(name='observe',argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/'observe.stdout'),stderr_sha256=sha(leaf/'observe.stderr')))
	(leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
	assert r.returncode == 42,(r.returncode,r.stdout[-3000:],r.stderr[-1000:])
	assert r.stdout.count(b'ABI_ERROR_RECEIVER ') >= 2
	if not a.diagnose: assert r.stdout.count(b'ABI_RECEIVER_MUTATIONS_VALID 5') >= 2
	(leaf/'result.json').write_text(json.dumps(dict(status='SOURCE_ABI_RECEIVER_DIAGNOSED' if a.diagnose else 'SOURCE_ABI_RECEIVER_PLANS_VERIFIED',source_path=str(source),source_sha256=sha(source),view_first=0,view_last=end,view_sha256=sha(view),products=products,inputs=witness['inputs'],fixture_sha256=sha(fixture),observation_sha256=sha(leaf/'observe.stdout'),Astra_native_execution_credit=0,limitation='Complete byte-exact production ABI-plan definitions and actual source normalization/checking under unchanged C0. Diagnosis preserves the actual rejection. Verification requires five independent ABI-plan mutations with positive restoration per source receiver. No target LLVM, ELF execution or milestone qualification is inferred.'),indent=2)+'\n')
	print('Source ABI receiver observation passed; zero target native execution credit',flush=True)


if __name__ == '__main__':
	main()
