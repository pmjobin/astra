#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify or restore the indexed evidence bytes; never execute their contents."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import tarfile
import tempfile


def main():
	p = argparse.ArgumentParser(); p.add_argument('archive', type=Path); p.add_argument('--output', type=Path, required=True); p.add_argument('--verify-only', action='store_true'); a = p.parse_args()
	decoder = Path(__file__).with_name('restore-columns.py')
	if not decoder.exists(): decoder = Path(__file__).resolve().parents[1]/'selfhost-genref/columns.py'
	spec = importlib.util.spec_from_file_location('effects_column_decoder', decoder); columns = importlib.util.module_from_spec(spec); spec.loader.exec_module(columns)
	root = a.output.resolve(); root.mkdir(parents=True, exist_ok=True); count = 0
	with tempfile.TemporaryDirectory(prefix='effects-restore-', dir=root) as temporary:
		spool = Path(temporary)
		with tarfile.open(a.archive, 'r:xz') as z:
			for member in z:
				assert member.isfile() and (member.name == 'INDEX.json' or member.name.startswith('blobs/') and len(Path(member.name).parts) == 2)
				data = z.extractfile(member)
				if member.name == 'INDEX.json': model = json.load(data); continue
				path = spool/Path(member.name).name; assert not path.exists()
				with path.open('xb') as out:
					for block in iter(lambda: data.read(1048576), b''): out.write(block)
		assert model['format'] == 'astra-effects25-evidence/2'
		column_directory = spool/'columns'; column_directory.mkdir()
		for name, row in model['files'].items():
			if name.startswith('columns/'):
				path = spool/Path(row['blob']).name; target = column_directory/Path(name).name
				target.hardlink_to(path)
		for name, row in model['files'].items():
			target = root/name; assert not Path(name).is_absolute() and '..' not in Path(name).parts and target.resolve().is_relative_to(root)
			h = hashlib.sha256(); size = 0; out = None
			if not a.verify_only:
				assert not target.exists(); target.parent.mkdir(parents=True, exist_ok=True); out = target.open('xb')
			if 'columns' in row: blocks = columns.reconstruct(column_directory, row['columns'])
			else:
				path = spool/Path(row['blob']).name
				def chunks():
					with path.open('rb') as stream:
						for block in iter(lambda: stream.read(1048576), b''): yield block
				blocks = chunks()
			try:
				for block in blocks:
					h.update(block); size += len(block)
					if out: out.write(block)
			finally:
				if out: out.close(); target.chmod(int(row['mode'], 8))
			assert size == row['bytes'] and h.hexdigest() == row['sha256'], name; count += 1
	print(json.dumps(dict(status='BYTE_EXACT', logical_files=count, classification='Evidence reconstruction only; no compiler/runtime qualification.')))


if __name__ == '__main__':
	main()
