#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh inherited status/layout/model controls with historical attribution."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import bounded_run, ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('continuity-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False); commands = []
	for label in ('source-status', 'layout-lifetime'):
		old = next(row for row in read(PRIOR/('controls-v3-'+a.mode)/'commands.json') if row['name'] == label); argv = old['argv'].copy(); argv[argv.index('--component')+1] = str(a.component)
		for flag, value in [('--build', BUILD/(leaf.name+'-'+label)), ('--runtime', leaf/label)]: argv[argv.index(flag)+1] = str(value)
		start = time.monotonic(); r = bounded_run(argv, cwd=ROOT, capture_output=True, timeout=300)
		(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=label, argv=argv, exit=r.returncode, seconds=time.monotonic()-start))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == 0, r.stderr[-2000:]
		assert read(leaf/label/'result.json')['status'] == 'PASS'
		if label == 'source-status': assert read(leaf/label/'observations/result.json')['outcomes'] == {'0':56, '4':12, '3':12}
		print(a.mode, label, 'inherited control passed', flush=True)
	old = next(row for row in read(PRIOR/('controls-v3-'+a.mode)/'commands.json') if row['name'] == 'downstream-models'); argv = old['argv'].copy(); argv[0] = str(a.component)
	destination = BUILD/(leaf.name+'-preserved.o'); destination.write_bytes(b'EFFECTS-25 inherited negative-control destination\n'); expected = sha(destination); argv[3] = str(destination)
	start = time.monotonic(); r = bounded_run(argv, cwd=ROOT, capture_output=True, timeout=180)
	(leaf/'models.stdout').write_bytes(r.stdout); (leaf/'models.stderr').write_bytes(r.stderr)
	mutations = [line.split() for line in r.stdout.decode().splitlines() if line.startswith('CALLPLACE_MODEL_MUTATION ')]
	assert r.returncode == 0 and sha(destination) == expected and len(mutations) == 28 and all(row[-1] == 'VALID_RESTORED' for row in mutations)
	commands.append(dict(name='inherited-models', argv=argv, exit=r.returncode, seconds=time.monotonic()-start)); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
	(leaf/'result.json').write_text(json.dumps(dict(status='INHERITED_CONTROLS_PASSED', original_statuses=dict(admitted=56, rejected=12, deferred=12), model_categories=28, new_effect_model_categories=0, component_sha256=sha(a.component), attribution='Existing Generic/Core/CFG/SSA and layout-cache controls; no new recoverable-effect qualification'), indent=2)+'\n')
	print(a.mode, '28 inherited model controls restored; destination preserved', flush=True)


if __name__ == '__main__':
	main()
