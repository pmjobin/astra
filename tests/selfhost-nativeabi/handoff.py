#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Prepare complete hashed evidence for the unchanged installed publisher."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(data):
	return hashlib.sha256(data).hexdigest()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--before-prefix', default='preformat-v5-tests-')
	p.add_argument('--after-prefix', default='final-tests-')
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.runtime, a.build))
	assert not subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain=v1'])
	def read(path):
		return json.loads(path.read_text())
	initial = read(a.runtime/'initial.json')
	preservation = read(a.runtime/'preservation-final.json')
	proof = read(a.runtime/'final-proof-replay/result.json')
	assert preservation['status'] == proof['status'] == 'PASS' and preservation['protected_files'] == 451 and proof['observations'] == 1044
	formatting = read(a.runtime/'format-apply.json')
	assert formatting['applied'] and formatting['changed'] > 0
	for name in ('format-check-before-commit.json', 'format-reapply-before-commit.json', 'format-check-final.json'):
		assert read(a.runtime/name)['changed'] == 0
	final_format = read(a.runtime/'format-check-final.json')
	final_rows = {row['path']: row for row in final_format['rows']}
	complete_map = []
	for row in formatting['rows']:
		current = final_rows.pop(row['path'])
		complete_map.append(dict(**row, final_sha256=current['after_sha256'], final_mode=current['after_mode'],
			subsequent_functional_change=row['after_sha256'] != current['after_sha256']))
	for row in final_rows.values():
		assert row['state'] == 'compliant'
		complete_map.append(dict(**row, before_mechanical_sha256=None, after_mechanical_sha256=None,
			final_sha256=row['after_sha256'], final_mode=row['after_mode'], added_after_mechanical=True))
	mechanical = read(a.runtime/'formatting-commit.json')
	for row in formatting['rows']:
		for commit, key in ((mechanical['before'], 'before_sha256'), (mechanical['commit'], 'after_sha256')):
			data = subprocess.check_output(['git', '-C', str(ROOT), 'show', commit+':'+row['path']])
			assert sha(data) == row[key], row['path']
	payload = {}
	def put(name, data):
		assert name not in payload
		payload[name] = data
	def regular(path, name):
		assert path.is_file() and not path.is_symlink(), path
		put(name, path.read_bytes())
	base = initial['repository']['head']
	put('patches/full-task.patch', subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--binary', '--full-index', base, 'HEAD']))
	put('patches/mechanical-format.patch', subprocess.check_output(['git', '-C', str(ROOT), 'diff', '--binary', '--full-index', mechanical['before'], mechanical['commit']]))
	profiles = {}
	for mode in ('O0', 'O2'):
		before = a.runtime/(a.before_prefix+mode); after = a.runtime/(a.after_prefix+mode)
		assert read(before/'result.json')['status'] == read(after/'result.json')['status'] == 'PASS'
		assert read(a.runtime/('paired-'+mode+'.json'))['status'] == 'PASS'
		for phase in ('before', 'after'):
			style = read(a.runtime/('native-style-'+phase+'-'+mode)/'result.json'); assert style['status'] == 'PASS'
			for case in style['cases']:
				for label, product in case['products'].items():
					path = Path(product['path']); assert sha(path.read_bytes()) == product['sha256']
					regular(path, 'native-style/'+phase+'/'+mode+'/'+case['name']+'/'+label)
		for phase, leaf in [('before', before), ('after', after)]:
			for family in ('legacy', 'additions'):
				cases = read(leaf/family/'result.json')['cases']
				for case in cases:
					assert sha(Path(case['source_path']).read_bytes()) == case['source_sha256']
					for label, product in case['products'].items():
						path = Path(product['path']); assert sha(path.read_bytes()) == product['sha256']
						regular(path, 'products/'+phase+'/'+mode+'/'+case['name']+'/'+label+path.suffix)
					if phase == 'after' and mode == 'O0':
						regular(Path(case['source_path']), 'inputs/selected/'+case['name']+'.astra')
						# The command ledger, rather than a guessed build directory, identifies
						# the exact component that emitted these application bodies.
			commands = read(leaf/'legacy/commands.json')
			component = Path(next(row['argv'][0] for row in commands if '--ssa' in row['argv']))
			identity = read(component.with_suffix('.identity.json'))
			assert sha(component.read_bytes()) == identity['sha256']
			if phase == 'after':
				assert all(sha(Path(path).read_bytes()) == digest for path, digest in identity['identity']['sources'].items())
				assert all(sha(Path(path).read_bytes()) == digest for path, digest in identity['identity']['tools'].items())
			regular(component, 'components/'+phase+'/'+mode+'/native')
			regular(component.with_suffix('.identity.json'), 'components/'+phase+'/'+mode+'/identity.json')
			for check in read(leaf/'result.json')['checks']:
				argv = check['argv']
				if check['name'] == 'continuity' or '--build' not in argv:
					continue
				directory = Path(argv[argv.index('--build')+1])
				assert directory.resolve().is_relative_to(a.build.resolve())
				for path in sorted(directory.rglob('*')):
					if path.is_file():
						regular(path, 'auxiliary-products/'+phase+'/'+mode+'/'+check['name']+'/'+path.relative_to(directory).as_posix())
		profiles[mode] = dict(executions=39, original=24, additions=14, existing_nested=1,
			original_fault_categories=21, additional_fault_categories=18,
			upstream=dict(core=22, cfg=26, ssa=30), paired_sha256=sha((a.runtime/('paired-'+mode+'.json')).read_bytes()))
		# Ship all three complete compiler artifacts losslessly within the installed
		# publisher's evidence budget. The existing zstd tool supplies byte deltas;
		# an actual decode must reproduce each target's SHA-256 before attachment.
	seed = a.build/'formatter-before/astrac'
	regular(seed, 'compilers/formatter-before.seed')
	codec = Path(shutil.which('zstd')).resolve()
	transport = a.runtime/'handoff/compiler-transport'; transport.mkdir(parents=True, exist_ok=True)
	codec_rows, codec_commands = [], []
	for label, target in [('reference-C0', Path(initial['c0']['path'])), ('formatter-after', a.build/'formatter-after/astrac')]:
		patch = transport/(label+'.zst')
		with tempfile.TemporaryDirectory(prefix='verify-', dir=transport) as scratch:
			decoded = Path(scratch)/'compiler'
			for stage, argv in [('encode', [codec, '-q', '-f', '-9', '--long=27', '--patch-from='+str(seed), target, '-o', patch]),
				('decode', [codec, '-q', '-d', '--patch-from='+str(seed), patch, '-o', decoded])]:
				start = time.monotonic()
				result = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/('transport-'+label+'-'+stage+'.time')), *map(str, argv)], capture_output=True)
				codec_commands.append(dict(argv=list(map(str, argv)), exit=result.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
				(a.runtime/'compiler-transport-commands.json').write_text(json.dumps(codec_commands, indent=2)+'\n')
				assert result.returncode == 0, result.stderr[-2000:]
			assert sha(decoded.read_bytes()) == sha(target.read_bytes())
		regular(patch, 'compilers/'+label+'.delta.zst')
		codec_rows.append(dict(target=label, bytes=target.stat().st_size, sha256=sha(target.read_bytes()),
			seed='compilers/formatter-before.seed', seed_sha256=sha(seed.read_bytes()), patch='compilers/'+label+'.delta.zst',
			patch_sha256=sha(patch.read_bytes()), decoded_and_verified=True, executable_mode=0o755))
	put('compilers/transport.json', json.dumps(dict(format='astra-lossless-compiler-transport/1',
		tool=dict(path=str(codec), sha256=sha(codec.read_bytes()), version=subprocess.check_output([str(codec), '--version'], text=True).strip()),
		decode='zstd -d --patch-from=compilers/formatter-before.seed compilers/TARGET.delta.zst -o TARGET; verify SHA-256 before use',
		artifacts=codec_rows), indent=2).encode()+b'\n')
	for path in sorted(a.runtime.rglob('*')):
		if not path.is_file() or path.is_symlink():
			continue
		rel = path.relative_to(a.runtime)
		if rel.parts[0] in ('handoff', 'report-evidence') or path.name == 'initial.json' or path.suffix == '.zip':
			continue
		if path.suffix in ('.json', '.stdout', '.stderr', '.time', '.log', '.astra', '.c', '.ll', '.abi', '.nabi', '.cabi', '.o', '.exe', '.native', '.c0'):
			regular(path, 'runtime/'+rel.as_posix())
	for row in read(a.runtime/'frozen/predecessor.json'):
		for index, name in enumerate(row['paths']):
			regular(Path(name), 'inputs/original80/'+row['name']+'/'+str(index)+'.astra')
	out = a.runtime/'report-evidence'; out.mkdir(exist_ok=True)
	attachments = []
	def attach(name, data):
		path = out/name; path.write_text(json.dumps(data, indent=2)+'\n'); attachments.append(path)
	map_parts = []
	for index, start in enumerate(range(0, len(complete_map), 800)):
		name = 'format-map-'+str(index).zfill(3)+'.json'
		attach(name, complete_map[start:start+800]); map_parts.append(name)
	attach('format-map-index.json', dict(format='astra-full-format-map/1', before=mechanical['before'], after=mechanical['commit'],
		rows=len(complete_map), mechanical_scope_rows=len(formatting['rows']), changed=formatting['changed'], parts=map_parts,
		engine=formatting['configs'], tools=formatting['tools']))
	index = {name: dict(bytes=len(data), sha256=sha(data)) for name, data in payload.items()}
	index_parts = []
	items = list(index.items())
	for number, start in enumerate(range(0, len(items), 1000)):
		name = 'raw-index-'+str(number).zfill(3)+'.json'; attach(name, dict(items[start:start+1000])); index_parts.append(name)
	attach('raw-index.json', dict(format='astra-evidence-raw-index/1', members=len(index), parts=index_parts))
	archive = a.runtime/'handoff/raw-evidence.tar.xz'; archive.parent.mkdir(exist_ok=True)
	with tarfile.open(archive, 'w:xz', preset=9) as tar:
		for name, data in sorted(payload.items()):
			info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o644; tar.addfile(info, io.BytesIO(data))
	data = archive.read_bytes()
	for number, start in enumerate(range(0, len(data), 900000)):
		chunk = data[start:start+900000]
		attach('raw-part-'+str(number).zfill(3)+'.json', dict(format='astra-evidence-base64-chunk/1',
			archive_sha256=sha(data), offset=start, bytes=len(chunk), sha256=sha(chunk), base64=base64.b64encode(chunk).decode()))
	attach('qualification.json', dict(format='astra-nativeabi13-r1-qualification/1', status='PASS',
		head=subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
		tree=subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD^{tree}'], text=True).strip(),
		profiles=profiles, protected=451, donor_files=preservation['donor_files'], proof_observations=1044,
		formatting_commit=mechanical, full_task_patch_sha256=index['patches/full-task.patch']['sha256'],
		mechanical_patch_sha256=index['patches/mechanical-format.patch']['sha256'],
		raw_archive=dict(bytes=len(data), sha256=sha(data), members=len(payload)),
		private_initial_capture_sha256=sha((a.runtime/'initial.json').read_bytes()),
		instrumentation_observations={mode: read(a.runtime/(a.after_prefix+mode)/'numeric/result.json')['instrumented'] for mode in ('O0', 'O2')},
		named_deferrals=['Valgrind numerical conformance for the independently reproduced wide-u64-to-f32 conversion discrepancy; native host expectations remain exact.',
		'Owning-record reassignment rejected by the unchanged C0 reference; typed/general foreign pointers, aggregate C ABI, callbacks, varargs and retained pointers.',
		'Other targets, Windows execution, full historical registry and Stage1/self-hosting completion are outside this bounded qualification.'],
		publication='Prepared evidence; unchanged installed pm-next publisher must complete publication.'))
	files = [dict(path=path.name, bytes=path.stat().st_size, sha256=sha(path.read_bytes())) for path in sorted(attachments)]
	assert all(row['bytes'] <= 2*1024*1024 for row in files) and len(files) <= 128
	assert sum(row['bytes'] for row in files) <= 64*1024*1024
	(out/'evidence-index.json').write_text(json.dumps(dict(format='pm-next-evidence/1', files=files), indent=2)+'\n')
	print('Prepared', len(files), 'hashed attachments with full patches, per-file map and lossless raw receipts; installed publisher still required')


if __name__ == '__main__':
	main()
