#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only original C0 Error layout/constructor IR observations."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('error_layout_oracle_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('error-layout-oracles-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	prior = paths.RUNTIME/'owner-form-oracles-source2'
	observed = read(prior/'result.json')
	commands = []
	rows = []
	def run(argv, name):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode, r.stderr.splitlines()[:4])
		return r
	for name in ('derived-error-field', 'derived-error-computed-base', 'derived-error-snapshot'):
		program = next(row for row in observed['programs'] if row['name'] == name)
		source = prior/(name+'.astra')
		assert sha(source) == program['source_sha256']
		assert all(not row['C0_source_rejected'] and row['exit'] == 42 for row in program['profiles'])
		inputs = [source, ROOT/'lib/astra/base/errors.astra']
		for mode in ('O0', 'O2'):
			label = name+'-'+mode
			r = run([C0, '-'+mode, '--dump-llvm', *inputs], label+'-IR')
			physical = build/(label+'.ll')
			physical.write_bytes(r.stdout)
			run(['opt', '-passes=verify', '-disable-output', physical], label+'-verify')
			rows.append(dict(name=name, mode=mode, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], LLVM_path=str(physical), LLVM_sha256=sha(physical)))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_C0_ERROR_IR_OBSERVATIONS', C0_sha256=sha(C0), prior_execution_receipt_sha256=sha(prior/'result.json'), observations=rows, Astra_native_execution_credit=0, limitation='Unchanged C0 IR from complete already executed source inputs, independently LLVM verified. Layout and order must be read from the actual IR. No Astra implementation or execution is qualified.'), indent=2)+'\n')
	print('C0 Error constructor/layout observations recorded; zero Astra execution credit', flush=True)


if __name__ == '__main__':
	main()
