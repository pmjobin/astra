#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Select authenticated historical evidence into R5, never its old locations."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import time
from state import ROOT, load_module, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--prefix', action='append', required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_history_paths', ROOT/'tests/selfhost-effects/recover-build.py'); archive = paths.RUNTIME/'r4-evidence.tar.xz'
	assert sha(archive) == '821be606065c62df8109d2042c1a1dd1547d1e8bceb2d4f95889d1967ba15478'
	start = time.monotonic()
	with tarfile.open(archive, 'r:xz') as packed: index = json.load(packed.extractfile('INDEX.json'))
	selected = {name: row for name, row in index['files'].items() if any(name.startswith(prefix) for prefix in a.prefix)}
	assert selected and all('blob' in row for row in selected.values()), 'Only literal evidence blobs are selected; encoded observations need the full decoder'
	by_blob = {}
	for name, row in selected.items():
		assert not Path(name).is_absolute() and '..' not in Path(name).parts
		by_blob.setdefault(row['blob'], []).append(name)
	output = paths.RUNTIME/'r4-history'; output.mkdir(exist_ok=True)
	with tarfile.open(archive, 'r|xz') as packed:
		for member in packed:
			if member.name not in by_blob: continue
			data = packed.extractfile(member).read(); digest = hashlib.sha256(data).hexdigest()
			for name in by_blob.pop(member.name):
				row = selected[name]; assert len(data) == row['bytes'] and digest == row['sha256']
				target = output/name; target.parent.mkdir(parents=True, exist_ok=True)
				if target.exists(): assert target.read_bytes() == data
				else: target.write_bytes(data)
			if not by_blob: break
	assert not by_blob
	receipt = dict(status='BYTE_EXACT_SELECTED_HISTORY', archive_sha256=sha(archive), selected=selected, seconds=time.monotonic()-start, limitation='Read-only historical witnesses in R5 only. No old path is restored, no live source is overwritten, and no execution is credited.')
	(paths.RUNTIME/('history-selection-'+a.version+'.json')).write_text(json.dumps(receipt, indent=2)+'\n'); print(len(selected), 'historical witnesses authenticated', flush=True)


if __name__ == '__main__':
	main()
