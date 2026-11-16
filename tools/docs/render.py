#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit, standard-library-only static adapter for astra-api-docs/1 JSON."""
import argparse
import html
import json
import os
from pathlib import Path
import stat
import sys

PREFIX = b'<!doctype html>\n<!-- astra-api-docs/1 -->\n'


def render(document):
	if not isinstance(document, dict) or document.get('format') != 'astra-api-docs/1' or type(document.get('schema_version')) is not int or document['schema_version'] != 1:
		raise ValueError('unsupported API documentation schema')
	symbols = document.get('symbols')
	if not isinstance(symbols, list) or len(symbols) > 100000:
		raise ValueError('invalid or excessive symbol list')
	by_id = {}
	for row in symbols:
		if not isinstance(row, dict) or not isinstance(row.get('id'), str) or row['id'] in by_id:
			raise ValueError('invalid or duplicate symbol ID')
		if row.get('visibility') not in ('public', 'internal', 'private'):
			raise ValueError('invalid visibility')
		for key in ('canonical_name', 'signature', 'kind'):
			if not isinstance(row.get(key), str): raise ValueError('invalid symbol label')
		if not isinstance(row.get('documentation'), dict) or not isinstance(row.get('source_location'), dict):
			raise ValueError('invalid documentation or location object')
		markdown = row['documentation'].get('markdown')
		if not isinstance(markdown, str) or len(markdown.encode()) > 65536:
			raise ValueError('invalid or excessive Markdown')
		location = row['source_location'].get('path')
		if not isinstance(location, str) or not location or Path(location).is_absolute() or '..' in Path(location).parts or '\\' in location or any(ord(c) < 32 for c in location):
			raise ValueError('invalid source-root-relative location')
		if not isinstance(row.get('links'), list) or len(row['links']) > 256 or not all(isinstance(link, str) for link in row['links']):
			raise ValueError('invalid links')
		by_id[row['id']] = row
	for row in symbols:
		if any(target not in by_id for target in row['links']): raise ValueError('unresolved structured link')
	escape = html.escape
	anchor = lambda identifier: 's'+identifier.encode().hex()
	parts = [PREFIX.decode(), '<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'"><title>Astra API reference</title><style>body{font:1rem/1.6 system-ui;max-width:80rem;margin:auto;padding:1rem}nav{display:flex;flex-wrap:wrap;gap:1rem}section{border-top:1px solid #aaa;padding:1rem 0}pre{white-space:pre-wrap;overflow-wrap:anywhere}:focus{outline:3px solid #a50}</style><header id="api"><h1>Astra API reference</h1><p>astra-api-docs/1 · Checked semantic contracts; native qualification is separate.</p></header><nav aria-label="Symbols">']
	for row in sorted(symbols, key=lambda row:row['id']):
		parts.append('<a href="#'+anchor(row['id'])+'">'+escape(row['canonical_name'])+'</a>')
	parts.append('</nav><main>')
	for row in sorted(symbols, key=lambda row:row['id']):
		parts.append('<section id="'+anchor(row['id'])+'"><p><a href="#api">API index</a> / '+escape(row['kind'])+' / '+escape(row['visibility'])+'</p><h2><code>'+escape(row['signature'])+'</code></h2><pre>'+escape(row['documentation']['markdown'])+'</pre><details><summary>Resolved contract</summary><pre>'+escape(json.dumps({key:row.get(key) for key in ('type_contract', 'throws', 'parameters', 'type_parameters', 'generic_constraints', 'attributes', 'availability')}, sort_keys=True, ensure_ascii=False, indent=2))+'</pre></details>')
		if row['links']:
			parts.append('<nav aria-label="Related APIs">')
			for target in row['links']:
				parts.append('<a href="#'+anchor(target)+'">'+escape(by_id[target]['canonical_name'])+'</a>')
			parts.append('</nav>')
		parts.append('</section>')
	parts.append('</main></html>\n')
	return ''.join(parts).encode()


def publish(path, data):
	if '..' in path.parts: raise ValueError('output traversal refused')
	parts = path.parts
	if path.is_absolute(): parts = parts[1:]
	if not parts: raise ValueError('output file required')
	directory = os.open('/' if path.is_absolute() else '.', os.O_RDONLY | os.O_DIRECTORY)
	temporary = '.astra-api-render-'+str(os.getpid())+'.tmp'
	created = False
	try:
		for part in parts[:-1]:
			next_directory = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
			os.close(directory)
			directory = next_directory
		try: existing = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
		except FileNotFoundError: existing = None
		if existing is not None:
			try:
				if not stat.S_ISREG(os.fstat(existing).st_mode) or os.read(existing, len(PREFIX)) != PREFIX:
					raise ValueError('existing non-generated output is preserved')
			finally: os.close(existing)
		fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=directory)
		created = True
		with os.fdopen(fd, 'wb') as stream:
			stream.write(data)
			stream.flush()
			os.fsync(stream.fileno())
		os.replace(temporary, parts[-1], src_dir_fd=directory, dst_dir_fd=directory)
		created = False
	finally:
		if created: os.unlink(temporary, dir_fd=directory)
		os.close(directory)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('input', type=Path)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	with a.input.open('rb') as stream:
		raw = stream.read(64*1024*1024+1)
	if len(raw) > 64*1024*1024: raise ValueError('API document exceeds 64 MiB')
	data = render(json.loads(raw.decode('utf-8')))
	publish(a.output, data)


if __name__ == '__main__':
	try: main()
	except (OSError, ValueError, KeyError, TypeError) as error:
		print('api renderer: '+str(error), file=sys.stderr)
		raise SystemExit(1)
