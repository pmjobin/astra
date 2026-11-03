#!/usr/bin/env python3
"""Checked source formatting. See CODING_STYLE.md for pins and scope."""
import sys
sys.dont_write_bytecode = True
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import tempfile
import time

from lanes import stable_format
from lexical import scan, call_interiors

ROOT = Path(__file__).resolve().parents[2]
SUFFIXES = {'.vala', '.vapi', '.c', '.h', '.cpp', '.hpp', '.py', '.astra', '.sh', '.js', '.S', '.ld', '.in', '.cmd', '.build', '.options'}


def sha(data):
	return hashlib.sha256(data).hexdigest()


def transformation(before, after, lane):
	old, new = before.splitlines(), after.splitlines()
	added_blank = removed_blank = 0
	for tag, left, right, start, end in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
		if tag != 'equal':
			removed_blank += sum(not line.strip() for line in old[left:right])
			added_blank += sum(not line.strip() for line in new[start:end])
	braces = 0
	if lane == 'astra':
		braces = sum(t[0] in ('{', '}') for t in scan(before)) - sum(t[0] in ('{', '}') for t in scan(after))
		if braces < 0 or braces % 2:
			raise ValueError('unbalanced formatting brace receipt')
	classes = []
	if before == after:
		classes.append('compliant')
	else:
		classes.append('ordinary-lane-formatter')
		if added_blank or removed_blank:
			classes.append('blank-spacing')
		if braces:
			classes.append('safe-braced-one-liner')
	return dict(classification=classes, before_lines=len(old), after_lines=len(new),
		before_bytes=len(before), after_bytes=len(after), added_blank_lines=added_blank,
		removed_blank_lines=removed_blank, removed_brace_pairs=braces // 2,
		preserved_call_interiors=len(call_interiors(before)) if lane in ('c', 'cpp') else 0)


def source_identity(metadata):
	# Reads may update atime. Only content/mode/inode changes indicate a race.
	return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_size,
		metadata.st_mtime_ns, metadata.st_ctime_ns, metadata.st_nlink)


def receipt_path(path, root=ROOT):
	path = Path(os.path.abspath(path))
	if path.resolve().is_relative_to(root.resolve()) or any(p.is_symlink() for p in (path, *path.parents)):
		raise ValueError('receipt must be an external nonsymlink path; check never writes repository content')
	return path


def tracked(root=ROOT):
	return {os.fsdecode(n) for n in subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).split(b'\0') if n}


def safe_parent(root, name):
	parts = PurePosixPath(name).parts
	if not parts or PurePosixPath(name).is_absolute() or any(p in ('..', '.') for p in parts) or str(PurePosixPath(name)) != name:
		raise ValueError('unsafe source path: ' + name)
	fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
	try:
		for part in parts[:-1]:
			next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
			os.close(fd)
			fd = next_fd
		return fd, parts[-1]
	except BaseException:
		os.close(fd)
		raise


def read_source(root, name):
	dirfd, leaf = safe_parent(root, name)
	try:
		fd = os.open(leaf, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dirfd)
		with os.fdopen(fd, 'rb') as stream:
			before = os.fstat(stream.fileno())
			if not stat.S_ISREG(before.st_mode):
				raise ValueError('nonregular source: ' + name)
			data = stream.read()
			if source_identity(before) != source_identity(os.fstat(stream.fileno())):
				raise ValueError('concurrent source change: ' + name)
		return data, before
	finally:
		os.close(dirfd)


def publish(root, name, before, metadata, after):
	dirfd, leaf = safe_parent(root, name)
	temporary = None
	try:
		# Open the temporary through the checked directory, never a symlink.
		for unused in range(10):
			temporary = '.astra-format-' + os.urandom(12).hex()
			try:
				fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dirfd)
				break
			except FileExistsError:
				continue
		else:
			raise ValueError('cannot allocate atomic source temporary')
		with os.fdopen(fd, 'wb') as stream:
			stream.write(after)
			stream.flush()
			os.fchmod(stream.fileno(), stat.S_IMODE(metadata.st_mode))
			os.fsync(stream.fileno())
		current, current_stat = read_source(root, name)
		if current != before or source_identity(current_stat) != source_identity(metadata) or source_identity(os.stat(leaf, dir_fd=dirfd, follow_symlinks=False)) != source_identity(metadata):
			raise ValueError('concurrent source change: ' + name)
		os.replace(temporary, leaf, src_dir_fd=dirfd, dst_dir_fd=dirfd)
		temporary = None
	finally:
		if temporary is not None:
			os.unlink(temporary, dir_fd=dirfd)
		os.close(dirfd)


def qualified_tools(lanes, astrac=None, uncrustify=None):
	pins = json.loads((ROOT/'format/toolchain.json').read_text())
	needed = {'vala': ['uncrustify'], 'c': ['clang-format'], 'cpp': ['clang-format'],
		'javascript': ['clang-format', 'node'], 'python': ['python3'], 'meson': ['meson', 'python3'],
		'shell': ['shfmt'], 'astra': ['astrac']}
	tools, identities = {}, {}
	for key in sorted({key for lane in lanes for key in needed[lane]}):
		pin = pins[key]
		override = {'astrac': astrac or os.environ.get('ASTRA_FORMAT_ASTRAC'),
			'uncrustify': uncrustify or os.environ.get('ASTRA_FORMAT_UNCRUSTIFY')}.get(key)
		path = override or shutil.which(pin['command'])
		if not path or not Path(path).is_file():
			raise ValueError('FORMATTER_REQUIRED: ' + pin['command'] + '; see CODING_STYLE.md')
		path = Path(path).resolve()
		if sha(path.read_bytes()) != pin['sha256']:
			raise ValueError('unqualified tool identity: ' + key + '; repilot before updating format/toolchain.json')
		version = subprocess.run([str(path), '--version'], capture_output=True, text=True, timeout=10)
		if version.returncode or version.stdout.strip() != pin['version']:
			raise ValueError('unqualified tool version: ' + key + '; repilot before updating format/toolchain.json')
		tools[key] = str(path)
		identities[key] = {**pin, 'actual_path': str(path)}
	return tools, identities


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	mode = parser.add_mutually_exclusive_group(required=True)
	mode.add_argument('--check', action='store_true')
	mode.add_argument('--apply', action='store_true')
	parser.add_argument('--receipt', type=Path)
	parser.add_argument('--astrac', help='explicit qualified baseline compiler path')
	parser.add_argument('--uncrustify', help='explicit qualified release formatter path')
	parser.add_argument('paths', nargs='*', help='tracked files or directory prefixes')
	args = parser.parse_args()
	if args.receipt:
		args.receipt = receipt_path(args.receipt)
	start = time.monotonic()
	scope = json.loads((ROOT/'format/scope.json').read_text())
	names = tracked()
	candidates = {n for n in names if Path(n).suffix in SUFFIXES}
	if candidates != scope.keys():
		raise ValueError('source scope changed; classify additions/removals in format/scope.json: ' + repr(sorted(candidates ^ scope.keys())[:20]))
	selected = set(scope)
	if args.paths:
		selected = set()
		for prefix in args.paths:
			if prefix.startswith('/') or '..' in PurePosixPath(prefix).parts:
				raise ValueError('unsafe selection: ' + prefix)
			matches = {n for n in scope if n == prefix or n.startswith(prefix.rstrip('/') + '/')}
			if not matches:
				raise ValueError('untracked or unknown source selection: ' + prefix)
			if prefix in scope and 'exclude' in scope[prefix]:
				raise ValueError('protected source: ' + prefix + ': ' + scope[prefix]['exclude'])
			selected.update(matches)
	tools, identities = qualified_tools({scope[n]['lane'] for n in selected if 'lane' in scope[n]}, args.astrac, args.uncrustify)
	rows, pending = [], []
	for name in sorted(selected):
		entry = scope[name]
		before, metadata = read_source(ROOT, name)
		row = dict(path=name, before_sha256=sha(before), mode=stat.S_IMODE(metadata.st_mode), after_mode=stat.S_IMODE(metadata.st_mode))
		if 'exclude' in entry:
			if sha(before) != entry['sha256']:
				raise ValueError('protected source identity changed: ' + name)
			row.update(state='protected', reason=entry['exclude'], after_sha256=sha(before))
			row.update(transformation(before, before, None), classification=['protected'])
		else:
			try:
				after = stable_format(entry['lane'], before, name, ROOT, tools)
			except Exception as error:
				raise ValueError(name + ': ' + str(error)) from error
			changed = before != after
			row.update(state='changed' if changed else 'compliant', lane=entry['lane'], after_sha256=sha(after), guard='PASS', stable=True)
			row.update(transformation(before, after, entry['lane']))
			if changed:
				pending.append((name, before, metadata, after))
		rows.append(row)
		# Every candidate is computed and verified before any source is published.
	if args.apply:
		for name, before, metadata, after in pending:
			publish(ROOT, name, before, metadata, after)
	receipt = dict(format='astra-source-format/2', applied=args.apply, tools=identities,
		head=subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
		tree=subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD^{tree}'], text=True).strip(),
		configs={n: sha((ROOT/n).read_bytes()) for n in ('CODING_STYLE.md', 'format/scope.json', 'format/toolchain.json', 'format/vala.cfg', 'format/clang-format.yaml', 'tools/format/source.py', 'tools/format/lanes.py', 'tools/format/lexical.py')},
		changed=len(pending), rows=rows, seconds=time.monotonic() - start)
	if args.receipt:
		args.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
	print(('APPLY' if args.apply else 'CHECK') + ': ' + str(len(rows)) + ' sources; ' + str(len(pending)) + ' changes; %.2fs' % receipt['seconds'])
	return int(bool(pending) and not args.apply)


if __name__ == '__main__':
	try:
		raise SystemExit(main())
	except (ValueError, OSError, subprocess.SubprocessError) as error:
		print('FORMAT FAILED: ' + str(error), file=sys.stderr)
		raise SystemExit(2)
