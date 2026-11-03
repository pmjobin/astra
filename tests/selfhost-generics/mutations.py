#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Require substantive generic forgeries, real controls and restored authorities."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
MODELS = [
	'wrong-origin', 'wrong-concrete-declaration', 'swapped-type-arguments',
	'missing-enclosing-instance', 'different-same-shape-Class-instance',
	'erased-owner-parameter', 'invented-owning-field', 'wrong-field-type',
	'wrong-nominal-symbol-map', 'wrong-body-result-type', 'forged-body-source-span',
	'wrong-call-instance', 'wrong-cloned-binder-reference', 'wrong-receiver-type',
	'erased-receiver-borrow', 'invented-method-dispatch', 'invented-call-owner',
	'incomplete-instance', 'missing-instantiated-body',
]
PHYSICAL = {
	39: 'missing-private-receiver-channel', 40: 'wrong-Class-layout-size',
	41: 'wrong-physical-allocation-size', 42: 'null-instead-of-selected-receiver',
	43: 'omitted-once-only-Class-retirement',
	44: 'wrong-buffer-element-stride',
}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('component', 'runtime', 'build'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	control = ROOT/'tests/selfhost-generics/fixtures/control.astra'
	identities = {str(path): sha(path) for path in (control, ROOT/'tests/selfhost-generics/mutations.astra', a.component)}
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=300)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode, r.stderr[-2000:]); return r.stdout
	before = run([a.component, '--generic-plan', a.mode, a.build/'unused', control], 'known-good-before')
	model = run([a.component, '--generic-mutations', a.mode, a.build/'unused', control], 'model-forgeries')
	for line in model.decode().splitlines():
		values = line.split()
		if values[0] != 'GENERIC_MUTATION': continue
		category, stage = map(int, values[1:]); assert 0 <= category < len(MODELS) and stage in (1, 2, 3)
		rows.append(dict(family='typed-binder-Flow', category=category, name=MODELS[category], independent_rejection_stage=stage, valid_control_and_exact_restore='asserted in separately compiled Astra consumer'))
	assert {r['category'] for r in rows} == set(range(19)) and len(rows) == 19
	physical = run([a.component, '--generic-native-mutations', a.mode, a.build/'refused.o', control], 'physical-forgeries')
	for line in physical.decode().splitlines():
		values = line.split()
		if values[0] != 'GENERIC_NATIVE_MUTATION': continue
		category, stage = map(int, values[1:3]); assert category in PHYSICAL and 0 < stage < 5
		old_abi, old_ir, new_abi, new_ir = map(bytes.fromhex, values[3:7])
		assert old_abi != new_abi or old_ir != new_ir
		rows.append(dict(family='physical-ABI', category=category, name=PHYSICAL[category], independent_rejection_stage=stage, before_abi_sha256=hashlib.sha256(old_abi).hexdigest(), before_ir_sha256=hashlib.sha256(old_ir).hexdigest(), changed_abi_sha256=hashlib.sha256(new_abi).hexdigest(), changed_ir_sha256=hashlib.sha256(new_ir).hexdigest(), write_refused=True, restored_control='freshly reconstructed and audited; upstream exact snapshot equality asserted'))
	assert {r['category'] for r in rows if r['family'] == 'physical-ABI'} == set(PHYSICAL) and len(rows) == 25
	after = run([a.component, '--generic-plan', a.mode, a.build/'unused', control], 'known-good-after')
	assert before == after and not (a.build/'refused.o').exists()
	assert all(sha(path) == digest for path, digest in identities.items())
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, identities=identities, mutations=rows, control_sha256=hashlib.sha256(before).hexdigest(), substantive_model_count=19, physical_count=6, nonseal_rejections=True), indent=2)+'\n')
	print(a.mode, '19 typed/binder/Flow and 6 physical forgeries rejected; controls restored')


if __name__ == '__main__':
	main()
