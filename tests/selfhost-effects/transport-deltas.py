#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact BSDIFF40 evidence storage; standalone standard-library reconstruction."""
import argparse
import bz2
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import lzma
from pathlib import Path
import re
import subprocess
import tarfile
import time
import urllib.request

SOURCES = {
	'bsdiff': '17a82b761d5ef23b8f35d92b13d1732e6e9d2df4d9b29fd89efdab107092fa7b',
	'bspatch': '7c8607c45ee2111479313a561b6bb706f75e3a4ab670dedce4aca05f019a184d',
}


def digest(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def number(data):
	assert len(data) == 8
	value = int.from_bytes(data, 'little'); return -(value & ((1 << 63)-1)) if value >> 63 else value


def apply(old, patch):
	assert patch[:8] == b'BSDIFF40' and len(patch) >= 32
	control_size, difference_size, size = [number(patch[i:i+8]) for i in (8, 16, 24)]
	assert min(control_size, difference_size, size) >= 0 and 32+control_size+difference_size <= len(patch)
	control = bz2.decompress(patch[32:32+control_size]); difference = bz2.decompress(patch[32+control_size:32+control_size+difference_size]); extra = bz2.decompress(patch[32+control_size+difference_size:])
	assert len(control) % 24 == 0
	result = bytearray(); old_position = difference_position = extra_position = 0
	for offset in range(0, len(control), 24):
		count, literal, seek = [number(control[i:i+8]) for i in range(offset, offset+24, 8)]
		assert count >= 0 and literal >= 0 and len(result)+count+literal <= size and difference_position+count <= len(difference) and extra_position+literal <= len(extra)
		block = bytearray(count); first, last = max(old_position, 0), min(old_position+count, len(old))
		if last > first: block[first-old_position:last-old_position] = old[first:last]
		delta = difference[difference_position:difference_position+count]
		for match in re.finditer(rb'[^\x00]+', delta):
			for position in range(match.start(), match.end()): block[position] = (block[position]+delta[position]) & 255
		result.extend(block); result.extend(extra[extra_position:extra_position+literal])
		old_position += count+seek; difference_position += count; extra_position += literal
	assert len(result) == size and difference_position == len(difference) and extra_position == len(extra)
	return result


def prepare(leaf, build, witness):
	build.mkdir(); receipts = []
	for name, expected in SOURCES.items():
		source = build/(name+'.c'); prior = witness/(name+'.c')
		url = 'https://raw.githubusercontent.com/freebsd/freebsd-src/release/9.0.0/usr.bin/bsdiff/'+name+'/'+name+'.c'
		if prior.is_file(): data = prior.read_bytes()
		else:
			with urllib.request.urlopen(url, timeout=30) as response: data = response.read()
		assert hashlib.sha256(data).hexdigest() == expected; source.write_bytes(data)
		argv = ['cc', '-O2', '-D__FBSDID(x)=', '-DSIZE_T_MAX=SIZE_MAX', '-DOFF_MAX=INT64_MAX', source, '-lbz2', '-o', build/name]
		r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'-build.time'), *map(str, argv)], capture_output=True)
		(leaf/(name+'-build.stdout')).write_bytes(r.stdout); (leaf/(name+'-build.stderr')).write_bytes(r.stderr); assert r.returncode == 0, r.stderr
		receipts.append(dict(url=url, source=str(source), source_sha256=expected, product=str(build/name), product_sha256=digest(build/name), argv=list(map(str, argv))))
	return receipts


def encode(pending, files, leaf, build, witness, cache=None):
	tools = prepare(leaf, build, witness); jobs = leaf/'delta-jobs'; jobs.mkdir()
	captured = {}
	if cache:
		for row in json.loads((cache/'delta-commands.json').read_text()): captured[(row['base'], row['target'])] = row
		cache_sha256 = digest(cache/'delta-commands.json')
	column_keys = {}
	for row in files.values():
		if 'columns' not in row: continue
		for kind, part in row['columns']['parts'].items(): column_keys[files['columns/'+part['path']]['blob']] = ('column', kind, '', 0)
		for group in row['columns']['groups']:
			for ordinal, part in enumerate(group['columns']): column_keys[files['columns/'+part['path']]['blob']] = ('column', 'values', group['header'], ordinal)
	nominal = {}
	for name, row in files.items():
		if 'blob' in row: nominal.setdefault(row['blob'], name)
	groups, planned, depths = {}, [], {}
	for name, path in pending.items():
		size = path.stat().st_size
		if size < 8192: continue
		with path.open('rb') as stream: first = stream.read(128)
		if name in column_keys: key = column_keys[name]
		elif first.startswith(b'(') and b'\0' not in first: key = ('Core', Path(nominal[name]).name)
		elif first.startswith(b'\x7fELF'): key = ('ELF', first[16:18].hex(), 'large' if size >= 500000 else 'small')
		elif b'; ModuleID' in first or first.startswith(b'source_filename'): key = ('LLVM',)
		elif size >= 1048576 and first.lstrip().startswith((b'{', b'[')): key = ('JSON', Path(nominal[name]).name)
		else: continue
		groups.setdefault(key, []).append(name)
	for members in groups.values():
		previous = None
		for name in sorted(members, key=lambda name: (pending[name].stat().st_size, name)):
			size = pending[name].stat().st_size
			if previous is None or size > pending[previous].stat().st_size*1.4 or depths[previous] >= 64: depths[name] = 0
			else: planned.append((previous, name)); depths[name] = depths[previous]+1
			previous = name
	def run(pair):
		base, name = pair; label = name[6:]; patch = jobs/(label+'.bsdiff'); argv = [build/'bsdiff', pending[base], pending[name], patch]
		if pair in captured and captured[pair]['exit'] == 0:
			row = dict(captured[pair]); prior_patch = cache/'delta-jobs'/(label+'.bsdiff'); assert prior_patch.is_file()
			if row['accepted']:
				assert 'blobs/'+digest(prior_patch) == row['patch']
				data = apply(pending[base].read_bytes(), prior_patch.read_bytes()); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == name[6:]
			row.update(exact_cached_input_pair=True, cache_receipt=str(cache/'delta-commands.json'), cache_receipt_sha256=cache_sha256, cache_revalidation_monotonic=time.monotonic(), limitation='Original command/time fields remain historical. Exact captured bytes and each accepted patch are revalidated; no compiler execution or speedup credit.')
			return row, prior_patch
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', jobs/(label+'.time'), *map(str, argv)], capture_output=True, timeout=300)
		(jobs/(label+'.stdout')).write_bytes(r.stdout); (jobs/(label+'.stderr')).write_bytes(r.stderr)
		row = dict(base=base, target=name, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest(), accepted=False)
		if r.returncode == 0:
			data = pending[name].read_bytes(); row['raw_fast_XZ_bytes'] = len(lzma.compress(data, preset=0)); row['patch_bytes'] = patch.stat().st_size
			if patch.stat().st_size < min(len(data)/8, row['raw_fast_XZ_bytes']/3):
				reconstructed = apply(pending[base].read_bytes(), patch.read_bytes()); assert hashlib.sha256(reconstructed).hexdigest() == name[6:] and len(reconstructed) == len(data)
				row.update(accepted=True, patch='blobs/'+digest(patch), bytes=len(data))
		return row, patch
	with ThreadPoolExecutor(max_workers=8) as executor: results = list(executor.map(run, planned))
	physical, deltas = dict(pending), {}
	for row, path in results:
		if row['accepted']:
			physical.pop(row['target']); deltas[row['target']] = dict(base=row['base'], patch=row['patch'], bytes=row['bytes'])
	for row, path in results:
		if row['accepted']: physical[row['patch']] = path
	commands = [row for row, _ in results]; (leaf/'delta-commands.json').write_text(json.dumps(commands, indent=2)+'\n')
	storage = dict(format='astra-byte-deltas/1', deltas=deltas)
	receipt = dict(recipe_sha256=digest(__file__), tools=tools, attempted=len(results), accepted=len(deltas), original_blob_bytes=sum(path.stat().st_size for path in pending.values()), stored_blob_bytes=sum(path.stat().st_size for path in physical.values()), commands_sha256=digest(leaf/'delta-commands.json'), failed=[row for row in commands if row['exit'] != 0], Astra_execution_credit=0, limitation='Every accepted BSDIFF40 delta is independently applied by the standalone Python decoder and required to match the actual original byte hash. Raw bases and every original logical row remain. Eight bounded encoder processes operate only on captured artifact bytes; no source, command, proof result or target execution is synthesized.')
	(leaf/'delta-codec-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
	return physical, storage, receipt


def decode(archive, output, expected=None):
	assert not output.exists(); root = output.with_suffix('.blobs'); root.mkdir(); observed = {}
	with tarfile.open(archive, 'r|xz') as packed:
		for member in packed:
			assert member.isfile() and member.name not in observed; stream = packed.extractfile(member)
			if member.name == 'INDEX.json': index = json.load(stream); observed[member.name] = None; continue
			assert re.fullmatch('blobs/[0-9a-f]{64}', member.name)
			path = root/member.name[6:]; actual = hashlib.sha256()
			with path.open('xb') as out:
				for block in iter(lambda: stream.read(1048576), b''): out.write(block); actual.update(block)
			assert member.name == 'blobs/'+actual.hexdigest(); observed[member.name] = path
	assert index['format'] == 'astra-effects25-evidence/5' and index['milestone'] == 'ASTRA-SELFHOST-EFFECTS-25-R5'
	if expected is not None: assert index == expected
	storage = index['storage']; assert storage['format'] == 'astra-byte-deltas/1'; deltas = storage['deltas']
	originals = {row['blob'] for row in index['files'].values() if 'blob' in row}; assert set(deltas) <= originals
	assert set(observed)-{'INDEX.json'} == (originals-set(deltas)) | {row['patch'] for row in deltas.values()}
	cache, visiting = {}, set()
	def materialize(name):
		assert name in originals
		if name in cache: return cache[name]
		assert name not in visiting and len(visiting) <= 64; visiting.add(name)
		if name in deltas:
			row = deltas[name]; old = materialize(row['base']).read_bytes(); data = apply(old, observed[row['patch']].read_bytes())
			assert len(data) == row['bytes'] and name == 'blobs/'+hashlib.sha256(data).hexdigest()
			path = root/('decoded-'+name[6:]); path.write_bytes(data)
		else: path = observed[name]
		visiting.remove(name); cache[name] = path; return path
	standard = dict(index); standard['format'] = 'astra-effects25-evidence/3'; standard.pop('storage')
	with lzma.LZMAFile(output, 'wb', preset=0) as compressed, tarfile.open(fileobj=compressed, mode='w|') as packed:
		for name in sorted(originals):
			path = materialize(name); entry = tarfile.TarInfo(name); entry.mode = 0o644; entry.size = path.stat().st_size
			with path.open('rb') as stream: packed.addfile(entry, stream)
		data = (json.dumps(standard, indent=2)+'\n').encode(); entry = tarfile.TarInfo('INDEX.json'); entry.mode = 0o644; entry.size = len(data); packed.addfile(entry, io.BytesIO(data))
	return index


def main():
	p = argparse.ArgumentParser(); p.add_argument('archive', type=Path); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); index = decode(a.archive, a.output)
	print(json.dumps(dict(status='EXACT_BLOBS_RECONSTRUCTED', logical_files=len(index['files']), delta_blobs=len(index['storage']['deltas']), standard_archive_sha256=digest(a.output), Astra_execution_credit=0)))


if __name__ == '__main__':
	main()
