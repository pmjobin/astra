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


def ledger(raw, metadata):
	model = json.loads(metadata.read_text()); assert model['nodes'] is None and model['raw_flow'] is None
	identities = {row['path']: row['sha256'] for row in model['files']}; nodes = []; flow = []
	with raw.open() as stream:
		for line in stream:
			line = line.rstrip('\n'); values = line.split()
			if not values: continue
			if values[0] == 'NODE':
				path = bytes.fromhex(values[7]).decode()
				nodes.append(dict(node=int(values[1]), syntax_kind=int(values[2]), function_symbol=int(values[3]), type=int(values[4]), flags=int(values[5]), deferred=int(values[6]), path=path, start=int(values[8]), end=int(values[9]), source_sha256=identities[path]))
			elif values[0] not in ('SOURCE', 'DECL'): flow.append(line)
	failed = any(line.startswith('CHECKED_ERROR ') for line in flow); reasons = model['reason_authority']['reasons']
	for row in nodes:
		row['function'] = model['declarations'].get(str(row['function_symbol']))
		row['deferred_reason'] = reasons.get(str(row['deferred']), 'specific syntax family '+str(row['syntax_kind']) if row['deferred'] >= 100 else None)
		row['disposition'] = 'TYPE_DEFERRED_'+str(row['deferred']) if row['deferred'] else 'TYPE_RECORDED_WITHOUT_WHOLE_PROGRAM_ADMISSION' if row['type'] else 'NO_CHECKED_USE_RECORDED'
		row['program_checked_error'] = failed
	model['nodes'] = nodes; model['raw_flow'] = flow
	return (json.dumps(model, indent=2)+'\n').encode()


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
		assert model['format'] in ('astra-effects25-evidence/2', 'astra-effects25-evidence/3')
		column_directory = spool/'columns'; column_directory.mkdir()
		for name, row in model['files'].items():
			if name.startswith('columns/'):
				path = spool/Path(row['blob']).name; target = column_directory/Path(name).name
				target.hardlink_to(path)
		cache = {}; decoded = spool/'decoded'; decoded.mkdir()
		def materialize(name):
			row = model['files'][name]
			if row['sha256'] in cache: return cache[row['sha256']]
			if 'ledger' in row:
				data = ledger(materialize(row['ledger']['raw']), materialize(row['ledger']['metadata'])); target = decoded/row['sha256']; target.write_bytes(data)
			elif 'columns' in row:
				target = decoded/row['sha256']
				with target.open('xb') as out:
					for block in columns.reconstruct(column_directory, row['columns']): out.write(block)
			else: target = spool/Path(row['blob']).name
			with target.open('rb') as stream: digest = hashlib.file_digest(stream, 'sha256').hexdigest()
			assert target.stat().st_size == row['bytes'] and digest == row['sha256'], name
			cache[row['sha256']] = target; return target
		for name, row in model['files'].items():
			target = root/name; assert not Path(name).is_absolute() and '..' not in Path(name).parts and target.resolve().is_relative_to(root)
			actual = materialize(name)
			if not a.verify_only:
				assert not target.exists(); target.parent.mkdir(parents=True, exist_ok=True)
				with actual.open('rb') as source, target.open('xb') as out:
					for block in iter(lambda: source.read(1048576), b''): out.write(block)
				target.chmod(int(row['mode'], 8))
			count += 1
	print(json.dumps(dict(status='BYTE_EXACT', logical_files=count, classification='Evidence reconstruction only; no compiler/runtime qualification.')))


if __name__ == '__main__':
	main()
