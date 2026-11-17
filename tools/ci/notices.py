#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Collect verbatim upstream notices for the LLVM/Polly archives bundled by Astra."""
import argparse
import hashlib
import re
from pathlib import Path, PurePosixPath
import tarfile

from common import require, verify, write

PIN = dict(bytes=179272572, sha256='819ecf7351f1a66f76b2d701d8942faaf5faeb324cb90c9d5b090de142434bb2')
URL = 'https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.4/llvm-project-23.1.4.src.tar.xz'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--archive', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	verify(a.archive, PIN)
	require(not a.output.exists(), 'notice output already exists')
	notices, sources = {}, {}
	with tarfile.open(a.archive, 'r|xz') as archive:
		for member in archive:
			parts = PurePosixPath(member.name).parts
			require(parts and not member.name.startswith('/') and '..' not in parts, 'unsafe source archive path')
			name = '/'.join(parts[1:])
			if not member.isfile() or not name.startswith(('llvm/', 'polly/')):
				continue
			leaf = PurePosixPath(name).name.upper()
			license_file = leaf.startswith(('LICENSE', 'COPYING', 'COPYRIGHT', 'NOTICE'))
			source = name.startswith(('llvm/lib/', 'llvm/include/', 'polly/lib/')) and PurePosixPath(name).suffix in ('.c', '.cc', '.cpp', '.h', '.hpp', '.inc', '.def')
			if not license_file and not source:
				continue
			data = archive.extractfile(member).read()
			if license_file:
				text = data
			else:
				match = re.match(rb'\s*(?:(?://[^\n]*(?:\n|$)|/\*.*?\*/|\s+))*', data, re.S)
				text = match.group(0)
				if not re.search(rb'copyright|redistribut|license|public domain', text, re.I):
					continue
				if b'SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception' in text and not re.search(rb'copyright|redistribut|public domain|BSD|MIT License', text, re.I):
					continue
			digest = hashlib.sha256(text).hexdigest()
			notices.setdefault(digest, dict(text=text, paths=[]))['paths'].append(name)
			sources[name] = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), retained_notice_sha256=digest, complete_file=license_file)
	require(any('xxhash' in name.lower() for name in sources) and any('ConvertUTF' in name for name in sources) and any('BLAKE3' in name for name in sources), 'expected dependency notices absent')
	a.output.mkdir(parents=True)
	with (a.output/'THIRD-PARTY-NOTICES.txt').open('wb') as stream:
		stream.write(b'Verbatim notices collected from the pinned LLVM 23.1.4 source archive.\nLLVM and Polly main licenses are also installed separately.\n\n')
		for digest, row in sorted(notices.items()):
			stream.write(('='*72+'\n'+'\n'.join(sorted(row['paths']))+'\nNotice SHA-256: '+digest+'\n\n').encode())
			stream.write(row['text'])
			stream.write(b'\n\n')
	write(a.output/'SOURCE.json', dict(source_url=URL, source_archive=PIN, source_commit='7a941dfb2877a0b8cf30323fefa85ad019e0b0f5', sources=sources, unique_notices=len(notices), scope='All LICENSE/COPYING/COPYRIGHT/NOTICE files under LLVM and Polly plus leading third-party/copyright comments in library and installed-header sources. Standard LLVM SPDX-only headers are covered by the separately installed main licenses. Notices are preserved verbatim; this inventory does not grant a new license or change the dependency.'))
	print(len(sources), 'source notices;', len(notices), 'unique texts')


if __name__ == '__main__':
	main()
