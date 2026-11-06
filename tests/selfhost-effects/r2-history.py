#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently reopen R1, bind its sources to Git and decode its exact archive."""
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import zipfile
from state import ROOT, load_module, read, sha


def main():
	state = load_module('r2_history_state', ROOT/'tests/selfhost-effects/r2-state.py')
	path = state.RUNTIME/'predecessor-report.zip'; assert sha(path) == state.REPORT
	leaf = state.RUNTIME/'predecessor-verification'; leaf.mkdir()
	with zipfile.ZipFile(path) as z:
		assert z.testzip() is None
		manifest = json.loads(z.read('MANIFEST.json')); assert len(manifest['files']) == 51 and len(z.namelist()) == 52
		result = json.loads(z.read('RESULT.json')); assert result['status'] == 'PARTIAL'
		assert (result['final_commit'], result['final_tree']) == (state.BASE, state.TREE)
		sources = 0
		for row in manifest['files']:
			data = z.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
			if row['path'].startswith('source/'):
				name = row['path'].removeprefix('source/')
				assert data == subprocess.check_output(['git', 'show', state.BASE+':'+name], cwd=ROOT); sources += 1
			if row['path'].startswith('evidence/') and row['path'] != 'evidence/INDEX.json':
				name = Path(row['path']).name; (leaf/name).write_bytes(data)
	assert sources == 27
	decoder = load_module('r2_predecessor_decoder', ROOT/'tools/qualification/encoded-evidence.py')
	model, raw = decoder.decode(leaf/'effects25-r1-encoding.json')
	expected = 'b35a8cdb8b03e7d8917489b9808497f02b359c78cec7f1945ee72810f722a9c4'
	assert hashlib.sha256(raw).hexdigest() == expected
	archive = leaf/'effects25-r1-evidence.tar.xz'; archive.write_bytes(raw)
	with tarfile.open(archive, 'r:xz') as packed:
		members = packed.getmembers(); assert len(members) == 10317
		assert all(m.isfile() and not Path(m.name).is_absolute() and '..' not in Path(m.name).parts for m in members)
	receipt = dict(status='PREDECESSOR_PARTIAL_AUTHENTICATED', report_sha256=sha(path), report_bytes=path.stat().st_size, manifest_payloads=51, source_blobs_bound_to_Git=sources, final_commit=state.BASE, final_tree=state.TREE, restored_tar_xz_sha256=expected, physical_tar_members=10317, classification='Historical R1 byte/Git/transport verification only; no new Astra runtime qualification')
	(state.RUNTIME/'predecessor-verified.json').write_text(json.dumps(receipt, indent=2)+'\n'); print(receipt, flush=True)


if __name__ == '__main__':
	main()
