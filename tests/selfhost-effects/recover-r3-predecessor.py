#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reconstruct and independently hash R2 transport without executing evidence."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile
from state import ROOT, load_module, read, sha, bounded_run


def main():
	paths = load_module('r3_predecessor_paths', ROOT/'tests/selfhost-effects/recover-build.py'); r3 = load_module('r3_predecessor_identity', ROOT/'tests/selfhost-effects/r3.py'); report = paths.RUNTIME/'predecessor-report.zip'; assert sha(report) == r3.REPORT; leaf = paths.RUNTIME/'predecessor-verification'; leaf.mkdir()
	with zipfile.ZipFile(report) as z:
		manifest = json.loads(z.read('MANIFEST.json')); assert z.testzip() is None and len(manifest['files']) == 117 and len(z.namelist()) == 118
		for row in manifest['files']:
			data = z.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
			if row['path'].startswith('evidence/') and row['path'] != 'evidence/INDEX.json':
				name = Path(row['path']).relative_to('evidence'); assert len(name.parts) == 1; (leaf/name).write_bytes(data)
	decoder = load_module('r3_predecessor_decoder', ROOT/'tools/qualification/encoded-evidence.py'); model, raw = decoder.decode(leaf/'effects25-completion-encoding.json'); expected = 'ee0639032522c53b23fa9c33ab0dd90abcbed97e27b1a2319970152cb37b989f'; assert hashlib.sha256(raw).hexdigest() == expected
	archive = leaf/'effects25-completion-evidence.tar.xz'; archive.write_bytes(raw); del raw
	argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/restore.py', archive, '--output', leaf/'decoded', '--verify-only']; r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'restore.time', *argv], cwd=ROOT, capture_output=True, timeout=1200); (leaf/'restore.stdout').write_bytes(r.stdout); (leaf/'restore.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr[-2500:]; restored = json.loads(r.stdout); assert restored['status'] == 'BYTE_EXACT' and restored['logical_files'] == read(leaf/'packaging.json')['logical_files']
	result = dict(status='R2_REPORT_AND_DECODED_TRANSPORT_VERIFIED', report_sha256=sha(report), indexed_payloads=117, decoded_archive_sha256=expected, logical_files=restored['logical_files'], qualification_credit=0, limitation='Historical transport integrity is freshly checked. R3 native baseline execution and final source-bound qualification are independent.'); (paths.RUNTIME/'predecessor-verification.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
	main()
