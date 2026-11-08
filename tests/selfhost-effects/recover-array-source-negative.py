#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0 array/loan policy, then actual Astra destination preservation."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

GROUP = 'array'

CASES = {
	'buffer-slice': 'int first(u8[] value) { return value[0] as int; } int main() { var bytes = new u8[1]; return first(slice(bytes)); }\n',
	'subslice': 'int first(u8[] value) { return value[0] as int; } int main() { u8[1] bytes = {42}; return first(slice(slice(bytes))); }\n',
	'fixed-copy': 'int main() { u8[1] bytes = {42}; u8[1] other = bytes; return other[0] as int; }\n',
	'fixed-zero': 'int main() { u8[0] bytes = {}; return len(bytes) + 42; }\n',
	'fixed-literal-read': 'int main() { u8[1] bytes = {42}; return bytes[1] as int; }\n',
	'fixed-literal-write': 'int main() { u8[1] bytes = {42}; bytes[1] = 7; return 42; }\n',
	'fixed-negative-read': 'int main() { u8[1] bytes = {42}; return bytes[-1] as int; }\n',
	'slice-negative-start': 'int first(u8[] value) { return len(value) + 42; } int main() { u8[1] bytes = {42}; return first(slice(bytes, -1, 0)); }\n',
	'slice-start-past-end': 'int first(u8[] value) { return len(value) + 42; } int main() { u8[1] bytes = {42}; return first(slice(bytes, 2, 0)); }\n',
	'slice-count-past-end': 'int first(u8[] value) { return len(value) + 42; } int main() { u8[1] bytes = {42}; return first(slice(bytes, 1, 1)); }\n',
	'moved-backing-in-index': 'int retire(owned u8[] bytes) { return 0; } int main() { var bytes = new u8[1]; bytes[retire(move bytes)] = 42; return 42; }\n',
	'moved-backing-in-RHS': 'u8 retire(owned u8[] bytes) { return 42; } int main() { var bytes = new u8[1]; bytes[0] = retire(move bytes); return 42; }\n',
	'escaping-fixed-slice': 'u8[] leak() { u8[1] bytes = {42}; return slice(bytes); } int main() { var view = leak(); return view[0] as int; }\n',
	'moved-field-root-in-index': 'class Box { owned u8[] data; init() { this.data = new u8[1]; } } int retire(owned Box box) { return 0; } int main() { var box = new Box(); box.data[retire(move box)] = 42; return 42; }\n',
	'aliasing-class-in-RHS': 'class Box { owned u8[] data; init() { this.data = new u8[1]; } } u8 replace(Box box) { box.data = new u8[1]; return 42; } int main() { var box = new Box(); box.data[0] = replace(box); return 42; }\n',
}


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--component', type=Path)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--oracle-only', action='store_true')
	p.add_argument('--stage-only', action='store_true')
	a = p.parse_args()
	assert a.version.isalnum()
	assert not (a.oracle_only and a.stage_only)
	if not a.oracle_only:
		assert a.component is not None
		identity = read(a.component.with_suffix('.identity.json'))
		assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('array_negative_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/(GROUP+'-source-negative-'+a.version+'-'+a.mode)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, allowed):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr.splitlines()[:3])
		return r
	rows = []
	for name, text in CASES.items():
		source = leaf/(name+'.astra')
		source.write_text(text)
		inputs = [source, ROOT/'lib/astra/base/errors.astra']
		c0 = run([C0, '-'+a.mode, *inputs, '-o', build/(name+'-C0')], name+'-C0-build', (0, 1))
		row = dict(name=name, source_sha256=sha(source), C0_rejected=c0.returncode != 0)
		if not a.oracle_only and c0.returncode != 0:
			destination = build/(name+'.ll')
			destination.write_text('Negative source output sentinel\n')
			before = sha(destination)
			if a.stage_only:
				argv = [a.component]
				if not a.component.name.startswith('astra-shared-stage-'): argv.append('--shared-stages')
				actual = run([*argv, *inputs], name+'-Astra-stages', (*range(9), 42))
				row.update(Astra_stage_admission_refused=actual.returncode in (1, 2) and b'SHARED_FLOW 1 ' not in actual.stdout and b'SHARED_FLOW 2 ' not in actual.stdout, Astra_stage_status=actual.returncode, destination_preserved=sha(destination) == before)
			else:
				actual = run([a.component, '--native', destination, *inputs], name+'-Astra-attempt', range(9))
				row.update(Astra_not_emitted=actual.returncode != 0, Astra_status=actual.returncode, destination_preserved=sha(destination) == before)
		rows.append(row)
		(leaf/'result.json').write_text(json.dumps(dict(status='C0_'+GROUP.upper()+'_NEGATIVE_POLICY_COLLECTED' if a.oracle_only else GROUP.upper()+'_SOURCE_NEGATIVE_CONTROLS', profile=a.mode, stage_only=a.stage_only, component_sha256=None if a.oracle_only else sha(a.component), C0_sha256=sha(C0), Error_source_sha256=sha(ROOT/'lib/astra/base/errors.astra'), programs=rows, Astra_native_execution_credit=0, limitation='Independent C0 policy is established before expecting Astra rejection. Failed/crashed compiler processes cannot count as a verified negative. Every attempted output is hash-checked for preservation. Stage-only probes establish admission refusal, never target LLVM emission/execution or matched integrated qualification.'), indent=2)+'\n')
		print(a.mode, name, 'C0 rejected' if row['C0_rejected'] else 'C0 accepted: review policy', flush=True)
	assert all(row['C0_rejected'] for row in rows), 'Some proposed negatives are C0-valid; review their explicit source policy.'
	if not a.oracle_only:
		assert all(row['Astra_stage_admission_refused' if a.stage_only else 'Astra_not_emitted'] and row['destination_preserved'] for row in rows)


if __name__ == '__main__':
	main()
