#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently preserve exact baseline inputs and verify the R3 transport."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile
from state import ROOT, load_module, read, sha, bounded_run


def main():
	paths = load_module('r4_snapshots_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/'baseline-snapshots'; leaf.mkdir(); products = {}
	for mode in ('O0', 'O2'):
		component = paths.BUILD.parent/('effects25-r3/full-final6-'+mode)/('astra-llvm-'+mode); identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
		for group in ('sources', 'tools'):
			for path, expected in identity['identity'][group].items():
				assert sha(path) == expected
				if group == 'sources' and Path(path).is_relative_to(ROOT):
					target = leaf/mode/Path(path).relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(Path(path).read_bytes())
		products[mode] = dict(component=str(component), sha256=sha(component), identity=identity)
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	with zipfile.ZipFile(paths.RUNTIME/'predecessor-report.zip') as z:
		for name in z.namelist():
			if name.startswith('evidence/') and name != 'evidence/INDEX.json':
				target = leaf/Path(name).name; target.write_bytes(z.read(name))
	decoder = load_module('r4_predecessor_decoder', ROOT/'tools/qualification/encoded-evidence.py'); model, raw = decoder.decode(leaf/'effects25-completion-encoding.json'); expected = 'b38d6fccc89064ab67ded2d0275148d5b71654ae351097458db40b7b5ccd8a10'; assert hashlib.sha256(raw).hexdigest() == expected
	archive = leaf/'predecessor-evidence.tar.xz'; archive.write_bytes(raw); del raw
	argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/restore.py', archive, '--output', leaf/'decoded', '--verify-only']; r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'restore.time', *argv], cwd=ROOT, capture_output=True, timeout=1200); (leaf/'restore.stdout').write_bytes(r.stdout); (leaf/'restore.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr[-2500:]; restored = json.loads(r.stdout); assert restored['status'] == 'BYTE_EXACT' and restored['logical_files'] == 65032
	(leaf/'result.json').write_text(json.dumps(dict(status='BASELINE_INPUTS_AND_R3_TRANSPORT_VERIFIED', products={mode: row['sha256'] for mode, row in products.items()}, transport_sha256=expected, logical_files=65032, native_execution_credit=0), indent=2)+'\n'); print('Baseline snapshots and 65,032 historical evidence files independently verified', flush=True)


if __name__ == '__main__':
	main()
