# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Generic registry closure and deterministic installed-file archive checks."""
from pathlib import Path
import gzip
import hashlib
import tarfile


def check_current_registry(registry, qualified):
	assert registry['source_freeze']['commit'] == qualified
	assert registry['full_registry_pass'] and registry['selected_pass']
	assert registry['exit'] == 0 and registry['stage'] == 'REGISTRY_PASS'
	assert all(registry[key] for key in ('source_unchanged', 'compiler_unchanged', 'registry_unchanged'))
	assert not any(registry[key] for key in ('held', 'missing_selected', 'unexpected', 'duplicates', 'nonpassing', 'tap_skips'))
	names = [row['name'] for row in registry['registry']]
	observed = [row['name'].removeprefix('astra:') for row in registry['results']]
	assert len(names) == len(set(names)) == len(observed) == len(set(observed))
	assert set(names) == set(observed) == set(registry['selected_registrations'])
	assert all(row['result'] == 'OK' for row in registry['results'])


def split_archive(prefix, output, epoch, selected, extras=()):
	"""Archive installed files and identified review docs; preserve binary bytes."""
	entries = [('astra-dev/' + str(path.relative_to(prefix)), path) for path in sorted(prefix.rglob('*'))
		if path.is_file() and selected(path.relative_to(prefix).as_posix())]
	entries += list(extras)
	assert len(entries) == len({name for name, _ in entries})
	with output.open('xb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=epoch) as zipped:
		with tarfile.open(fileobj=zipped, mode='w') as tar:
			for name, path in sorted(entries):
				assert not path.is_symlink(), path
				assert not Path(name).is_absolute() and '..' not in Path(name).parts
				info = tar.gettarinfo(str(path), name)
				info.uid = info.gid = 0; info.uname = info.gname = ''; info.mtime = epoch
				with path.open('rb') as data: tar.addfile(info, data)


def archive_members(path):
	rows = []
	with tarfile.open(path) as archive:
		for member in archive:
			assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
			row = dict(path=member.name, bytes=member.size, mode=member.mode, type=member.type.decode('ascii'),
				mtime=member.mtime, uid=member.uid, gid=member.gid, uname=member.uname, gname=member.gname)
			if member.isfile(): row['sha256'] = hashlib.file_digest(archive.extractfile(member), 'sha256').hexdigest()
			if member.issym() or member.islnk(): row['linkname'] = member.linkname
			rows.append(row)
	return rows
