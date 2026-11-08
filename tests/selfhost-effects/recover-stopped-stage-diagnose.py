#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only diagnosis of an explicitly unqualified stopped build artifact."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--attempt', required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.attempt.isalnum() and a.version.isalnum()
	paths = load_module('stopped_stage_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	build_attempt = paths.BUILD/('shared-stage-'+a.attempt+'-O0')
	runtime_attempt = paths.RUNTIME/build_attempt.name
	component = build_attempt/'astra-shared-stage-O0'
	assert component.is_file() and not component.with_suffix('.identity.json').exists()
	identity = read(runtime_attempt/'typecore-O0-input-identity.json')
	commands = read(runtime_attempt/'commands.json')
	assert any(row['name'] == 'typecore-O0' and row['exit'] == 0 for row in commands)
	changed = {name: dict(before=expected, after=sha(name)) for name, expected in identity['sources'].items() if sha(name) != expected}
	assert changed, 'This diagnostic route requires the recorded changed-input failure; it cannot qualify a compiler.'
	leaf = paths.RUNTIME/('stopped-stage-diagnose-'+a.version)
	leaf.mkdir()
	original = read(paths.RUNTIME.parent/'effects25-r5/original-before-O0/result.json')
	minimal = read(paths.RUNTIME.parent/'effects25-r5/r4-original-view-baseline-O0/result.json')
	source = paths.RUNTIME/'frontier-source-source6'
	groups = [('full-original', original['inputs']), ('minimal-original', minimal['inputs'])]
	for name in ('integer-guarded-arithmetic', 'guarded-shared-constructor', 'array-heap-index', 'array-int-field', 'array-fixed-slice', 'original-builder-format', 'original-builder-invalid'):
		inputs = [source/(name+'.astra'), ROOT/'lib/astra/base/errors.astra']
		if name == 'guarded-shared-constructor':
			inputs += [ROOT/'lib/astra/base/diagnostics.astra']
		if name.startswith('original-builder-'):
			inputs += [ROOT/'lib/astra/text/utf8-message.astra', ROOT/'lib/astra/text/utf8-byte-builder.astra']
			if name.endswith('format'):
				inputs += [ROOT/'lib/astra/text/scalar-format.astra']
		groups.append((name, [dict(path=str(path), sha256=sha(path)) for path in inputs]))
	rows = []
	for name, inputs in groups:
		assert all(sha(row['path']) == row['sha256'] for row in inputs)
		argv = [str(component), *[row['path'] for row in inputs]]
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build_attempt, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name, argv=argv, inputs=inputs, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'result.json').write_text(json.dumps(dict(status='UNQUALIFIED_STOPPED_ARTIFACT_DIAGNOSIS', component_sha256=sha(component), input_receipt_sha256=sha(runtime_attempt/'typecore-O0-input-identity.json'), changed_inputs=changed, attempts=rows, qualified_stage_credit=0, Astra_native_execution_credit=0, limitation='The build failed its postcompile source-identity guard. No sidecar is created or repaired, and no result here qualifies the artifact or any acceptance gate. These read-only observations only guide a fresh, frozen-source build. All original failed receipts remain unchanged.'), indent=2)+'\n')
		print(name, 'UNQUALIFIED diagnostic exit', r.returncode, flush=True)


if __name__ == '__main__':
	main()
