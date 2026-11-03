#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify completed gates and prepare evidence for the unchanged pm-next publisher."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def sha(data):
	return hashlib.sha256(data).hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def passed(path):
	value = read(path); assert value['status'] == 'PASS', path; return value


def product(path):
	path = Path(path); identity = read(path.with_suffix('.identity.json'))
	assert sha(path.read_bytes()) == identity['sha256']
	assert all(sha(Path(name).read_bytes()) == digest for group in ('sources', 'tools') for name, digest in identity['identity'][group].items())
	return dict(path=str(path), sha256=identity['sha256'], identity_sha256=sha(path.with_suffix('.identity.json').read_bytes()))


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--qualification', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	a = p.parse_args(); config = read(a.qualification)
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.runtime, a.build))
	assert subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain=v1', '--untracked-files=all']) == b''
	initial = read(a.runtime/'initial.json'); base = initial['repository']['head']
	preservation = passed(config['preservation']); proof = passed(config['proof'])
	assert preservation['protected_files'] == 451 and preservation['donor_files'] == 6622 and proof['observations'] == 1044
	style = read(config['format']); assert style['changed'] == 0 and not style['applied']
	passed(config['standalone'])
	for name in ('ledger_before', 'ledger_after_initial', 'ledger_after_current'):
		ledger = read(config[name]); assert ledger['nodes'] and ledger['files']
		assert all(row['source_sha256'] for row in ledger['nodes'])
	profiles, identities = {}, []
	for mode in ('O0', 'O2'):
		c = config['profiles'][mode]
		native = product(c['component']); identities.append(native)
		new = passed(Path(c['new'])/'result.json')
		old = passed(Path(c['old'])/'result.json')
		mutation = passed(Path(c['mutations'])/'result.json')
		passed(Path(c['negative'])/'result.json'); passed(Path(c['policies'])/'result.json'); passed(Path(c['integration'])/'result.json')
		assert old['selected_distinct_executions'] == 39 and len(new['cases']) >= 12
		assert mutation['substantive_model_count'] >= 18 and mutation['physical_count'] >= 5 and mutation['nonseal_rejections']
		before = a.runtime/('before-'+mode)
		old_cases = []
		for family in ('legacy', 'additions'):
			prior, current = passed(before/family/'result.json'), passed(Path(c['old'])/family/'result.json')
			assert len(prior['cases']) == len(current['cases'])
			for left, right in zip(prior['cases'], current['cases']):
				assert left['name'] == right['name'] and left['source_sha256'] == right['source_sha256'] == sha(Path(right['source_path']).read_bytes())
			old_cases.extend(current['cases'])
		assert len(old_cases) == 39
		old_ids = {(row['source_sha256'],) for row in old_cases}
		new_ids = {tuple(sorted(source['sha256'] for source in row['sources'])) for row in new['cases']}
		assert len(new_ids) == len(new['cases']) and not old_ids.intersection(new_ids)
		for row in new['cases']:
			assert row['component_sha256'] == native['sha256'] and row['mode'] == mode
			assert all(sha(Path(source['path']).read_bytes()) == source['sha256'] for source in row['sources'])
			assert all(sha(Path(value['path']).read_bytes()) == value['sha256'] for value in row['products'].values())
		for row in old_cases:
			assert row['component_sha256'] == native['sha256']
			assert all(sha(Path(value['path']).read_bytes()) == value['sha256'] for value in row['products'].values())
		continuity = passed(Path(c['old'])/'continuity/result.json')
		assert sum(continuity['outcomes'].values()) == 80
		profiles[mode] = dict(retained=39, new=len(new_ids), distinct=39+len(new_ids), model_mutations=mutation['substantive_model_count'], physical_mutations=mutation['physical_count'], original_statuses=continuity['outcomes'], component=native, new_programs=new['cases'], retained_programs=old_cases)
	assert {tuple(sorted(s['sha256'] for s in row['sources'])) for row in profiles['O0']['new_programs']} == {tuple(sorted(s['sha256'] for s in row['sources'])) for row in profiles['O2']['new_programs']}
	head = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
	tree = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD^{tree}'], text=True).strip()
	assert preservation['head'] == head and preservation['tree'] == tree
	qualified_tools = {Path(value['component']).resolve() for value in config['profiles'].values()}
	qualified_tools.update(Path(row['path']).resolve() for row in read(Path(config['proof']).parent/'products.json').values())
	qualified_tools.update(Path(path).resolve() for path in [config['standalone_component'], *config['ledger_components']])
	tool_references = [dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path.read_bytes()), embedded=path.resolve() in qualified_tools) for path in sorted(a.build.rglob('astra-*')) if path.is_file() and path.suffix != '.json']
	costs = read(config['costs']); cost_summary = {key: value for key, value in costs.items() if key not in ('commands', 'unplaced_measurements', 'GNU_time_logs')}
	summary = dict(format='astra-generics14-evidence/1', readiness='READY_FOR_UNCHANGED_NATIVE_PUBLISHER', initial_head=base, initial_tree=initial['repository']['tree'], final_head=head, final_tree=tree, profiles=profiles, proof_observations=1044, protected=451, donor_files=6622, qualification=config, costs=cost_summary, tool_references=tool_references, tool_transport_limit='Qualified native/query/ledger products are embedded. Obsolete development tool binaries remain private with exact hashes and build receipts, to respect the installed publisher ZIP cap. All task runtime observations are retained.', remaining_deferrals=config['deferrals'], publication='G9 requires the unchanged installed publisher and verification of its canonical outer ZIP; this preparer does not publish.')
	out = a.runtime/'handoff'; out.mkdir(exist_ok=False)
	(out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
	payload = {}
	def include(path, name):
		path = Path(path); assert path.is_file() and not path.is_symlink()
		assert name not in payload; payload[name] = path
	for path in sorted(a.runtime.rglob('*')):
		if not path.is_file() or path.is_symlink(): continue
		rel = path.relative_to(a.runtime)
		if rel.parts[0] in ('handoff', 'report-evidence') or path.suffix in ('.zip', '.xz'): continue
		include(path, 'runtime/'+rel.as_posix())
	for path in sorted(a.build.rglob('*')):
		if path.is_file() and not path.is_symlink():
			if path.name.startswith('astra-') and path.suffix != '.json' and path.resolve() not in qualified_tools: continue
			include(path, 'build/'+path.relative_to(a.build).as_posix())
	changed = subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--name-only', '-z', base, head]).decode().split('\0')
	for name in changed:
		if name and (ROOT/name).is_file(): include(ROOT/name, 'source/'+name)
	patch = out/'full-task.patch'
	patch.write_bytes(subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--binary', '--full-index', base, head])); include(patch, 'patches/full-task.patch')
	series = out/'task-commits.patch'
	series.write_bytes(subprocess.check_output(['git', '-C', str(ROOT), 'format-patch', '--stdout', '--binary', '--full-index', base+'..'+head])); include(series, 'patches/task-commits.patch')
	include(out/'summary.json', 'summary.json')
	index = [dict(path=name, bytes=path.stat().st_size, sha256=sha(path.read_bytes())) for name, path in sorted(payload.items())]
	archive = out/'raw-evidence.tar.xz'
	with tarfile.open(archive, 'w:xz', preset=6) as tar:
		for name, path in sorted(payload.items()):
			info = tarfile.TarInfo(name); info.size = path.stat().st_size; info.mode = 0o644; info.mtime = 0
			with path.open('rb') as stream: tar.addfile(info, stream)
		raw = (json.dumps(index, separators=(',', ':'))+'\n').encode(); info = tarfile.TarInfo('index.json'); info.size = len(raw); info.mode = 0o644; tar.addfile(info, io.BytesIO(raw))
	with tarfile.open(archive, 'r:xz') as tar:
		assert len(tar.getmembers()) == len(index)+1
		for row in index:
			data = tar.extractfile(row['path']).read(); assert len(data) == row['bytes'] and sha(data) == row['sha256']
	encoded = a.runtime/'report-evidence'
	subprocess.run([sys.executable, '-B', ROOT/'tools/qualification/encoded-evidence.py', 'pack', '--input', archive, '--output', encoded, '--stem', 'generics14-raw'], check=True)
	attachments = [*sorted(encoded.glob('*')), out/'summary.json']
	manifest = dict(format='pm-next-evidence/1', files=[dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path.read_bytes())) for path in attachments])
	assert len(attachments) <= 128 and sum(path.stat().st_size for path in attachments) <= 64*1024*1024 and all(path.stat().st_size <= 2*1024*1024 for path in attachments)
	(out/'evidence-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
	print('Ready:', len(index), 'verified raw members;', len(attachments), 'bounded attachments; unchanged pm-next publisher still required')


if __name__ == '__main__':
	main()
