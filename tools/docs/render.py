#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit, standard-library-only static adapter for astra-api-docs/1 JSON."""
import argparse
import html
import json
import os
from pathlib import Path
import re
import stat
import sys

PREFIX = b'<!doctype html>\n<!-- astra-api-docs/1 -->\n'
DEFAULT_STYLESHEET = Path(__file__).with_name('api.css')


def description(markdown, resolve):
	"""Present the documented bounded subset; never interpret Astra or run fences."""
	parameters = {}
	result = ''
	errors = ''
	parts = []
	code = None
	paragraph = []
	def inline(text):
		chunks = re.split(r'(\{@link [^{}\n]+\}|`[^`\n]+`)', text)
		return ''.join(resolve(chunk[7:-1]) if chunk.startswith('{@link ') else '<code>'+html.escape(chunk[1:-1])+'</code>' if chunk.startswith('`') else html.escape(chunk) for chunk in chunks)
	def flush():
		if paragraph:
			parts.append('<p>'+inline(' '.join(paragraph))+'</p>')
			paragraph.clear()
	for line in markdown.splitlines():
		if line.startswith('```'):
			flush()
			if code is None:
				label = line[3:].strip() or 'Code example'
				metadata = dict(re.findall(r'\b(name|mode)=([a-z][a-z0-9_-]*)\b', label))
				if 'name' in metadata:
					mode = {'run':'Run example', 'compile':'Compile example', 'compile_fail':'Expected compile failure'}.get(metadata.get('mode'), 'Code example')
					label = mode+' · '+metadata['name']
				parts.append('<figure class="example"><figcaption>'+html.escape(label)+'</figcaption><pre><code>')
				code = []
			else:
				parts.append(html.escape('\n'.join(code))+'</code></pre></figure>')
				code = None
			continue
		if code is not None:
			code.append(line)
			continue
		if line.startswith('@param '):
			flush()
			fields = line.split(' ', 2)
			if len(fields) == 3: parameters[fields[1]] = fields[2]
		elif line.startswith('@return '):
			flush()
			result = line[8:]
		elif line.startswith('@throws '):
			flush()
			errors = line[8:]
		elif line.startswith('# '):
			flush()
			parts.append('<h3>'+inline(line[2:])+'</h3>')
		elif not line.strip(): flush()
		else: paragraph.append(line)
	flush()
	if code is not None: raise ValueError('unterminated Markdown fence')
	return ''.join(parts), {key:inline(value) for key,value in parameters.items()}, inline(result), inline(errors)


def type_label(contract):
	if not isinstance(contract, dict) or not isinstance(contract.get('name'), str): return 'unproven'
	flags = contract.get('effective_flags', 0)
	prefix = 'owned ' if flags & 4 else 'borrowed ' if flags & 2 else ''
	return prefix+contract['name']


def render(document, stylesheet=None):
	if not isinstance(document, dict) or document.get('format') != 'astra-api-docs/1' or type(document.get('schema_version')) is not int or document['schema_version'] != 1:
		raise ValueError('unsupported API documentation schema')
	symbols = document.get('symbols')
	build = document.get('build')
	if not isinstance(build, dict) or build.get('kind') != 'source-toolchain-sha256' or not isinstance(build.get('fingerprint'), str):
		raise ValueError('invalid build identity')
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
		if 'owner' not in row or row['owner'] is not None and not isinstance(row['owner'], str):
			raise ValueError('invalid owner identity')
		by_id[row['id']] = row
	for row in symbols:
		if any(target not in by_id for target in row['links']): raise ValueError('unresolved structured link')
		current = row
		seen = {row['id']}
		while current['owner'] is not None:
			owner = current['owner']
			if owner not in by_id or owner in seen or len(seen) >= 128: raise ValueError('invalid or excessive owner chain')
			seen.add(owner)
			current = by_id[owner]
	escape = html.escape
	anchor = lambda identifier: 's'+identifier.encode().hex()
	css = DEFAULT_STYLESHEET.read_text() if stylesheet is None else stylesheet
	if not isinstance(css, str) or len(css.encode()) > 131072: raise ValueError('stylesheet exceeds 128 KiB')
	css = css.replace('<', '\\3c ')
	parts = [PREFIX.decode(), '<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'"><title>Astra API reference</title><style>'+css+'</style></head><body><a class="skip" href="#content">Skip to reference</a><div class="layout"><aside class="sidebar"><a class="brand" href="#api">ASTRA</a><p>Source-derived API reference</p><h2>On this page</h2><nav aria-label="Symbols">']
	children = {}
	for row in symbols: children.setdefault(row['owner'], []).append(row)
	def navigation(owner):
		if owner not in children: return
		parts.append('<ul>')
		for row in sorted(children[owner], key=lambda row:row['id']):
			parts.append('<li><a href="#'+anchor(row['id'])+'">'+escape(row['canonical_name'])+'</a>')
			navigation(row['id'])
			parts.append('</li>')
		parts.append('</ul>')
	navigation(None)
	parts.append('</nav></aside><main id="content"><header id="api"><span class="eyebrow">API reference · astra-api-docs/1</span><h1>Build with Astra.</h1><p class="intro">Declarations, types and contracts derived from the compiler. Examples stay close to the APIs they explain.</p><p class="count">'+str(len(symbols))+' declarations</p></header>')
	for row in sorted(symbols, key=lambda row:row['id']):
		parents = []
		current = row
		while current['owner'] is not None:
			current = by_id[current['owner']]
			parents.append(current)
		breadcrumb = ''.join(' / <a href="#'+anchor(parent['id'])+'">'+escape(parent['canonical_name'])+'</a>' for parent in reversed(parents))
		allowed = set(row['links'])
		def resolve(target):
			matches = [by_id[key] for key in allowed if by_id[key]['canonical_name'] == target]
			if len(matches) != 1: return escape('{@link '+target+'}')
			return '<a href="#'+anchor(matches[0]['id'])+'">'+escape(target)+'</a>'
		prose, parameter_docs, return_docs, error_docs = description(row['documentation']['markdown'], resolve)
		contract = row.get('type_contract', {})
		if not isinstance(contract, dict): raise ValueError('invalid type contract')
		parameters = row.get('parameters', [])
		if not isinstance(parameters, list) or not all(isinstance(item, dict) and isinstance(item.get('name'), str) and isinstance(item.get('type_contract'), dict) for item in parameters): raise ValueError('invalid parameter contract')
		arguments = contract.get('arguments', [])
		result = arguments[0] if contract.get('kind') == 25 and arguments else None
		generics = row.get('type_parameters', [])
		if not isinstance(generics, list) or not all(isinstance(value, str) for value in generics): raise ValueError('invalid type parameters')
		signature = row['signature']
		if result is not None:
			generic_text = '<'+', '.join(generics)+'>' if generics else ''
			signature = type_label(result)+' '+row['canonical_name']+generic_text+'('+', '.join(type_label(item['type_contract'])+' '+item['name'] for item in parameters)+')'
			if row.get('throws'): signature += ' throws '+type_label(row['throws'])
		parts.append('<section class="api" id="'+anchor(row['id'])+'"><p class="breadcrumb"><a href="#api">Reference</a>'+breadcrumb+'</p><div class="title-row"><h2>'+escape(row['canonical_name'])+'</h2><span class="badge">'+escape(row['kind'])+' · '+escape(row['visibility'])+'</span></div><pre class="signature"><code>'+escape(signature)+'</code></pre><div class="prose">'+prose+'</div>')
		if parameters:
			parts.append('<h3>Parameters</h3><div class="table-wrap"><table><thead><tr><th>Name</th><th>Type / ownership</th><th>Description</th></tr></thead><tbody>')
			for item in parameters:
				parts.append('<tr><td><code>'+escape(item['name'])+'</code></td><td><code>'+escape(type_label(item['type_contract']))+'</code></td><td>'+parameter_docs.get(item['name'], '')+'</td></tr>')
			parts.append('</tbody></table></div>')
		if result is not None:
			parts.append('<h3>Returns</h3><p class="contract-note"><code>'+escape(type_label(result))+'</code>'+(' — '+return_docs if return_docs else '')+'</p>')
		constraints = row.get('generic_constraints', [])
		if not isinstance(constraints, list): raise ValueError('invalid generic constraints')
		if constraints:
			parts.append('<h3>Generic constraints</h3>')
			for constraint in constraints:
				if not isinstance(constraint, dict) or not isinstance(constraint.get('parameter'), str) or not isinstance(constraint.get('capabilities'), list) or not all(isinstance(capability, str) for capability in constraint['capabilities']): raise ValueError('invalid generic constraint')
				parts.append('<p><code>'+escape(constraint['parameter']+' : '+', '.join(constraint['capabilities']))+'</code></p>')
		if row.get('throws'):
			parts.append('<h3>Throws</h3><p class="contract-note"><code>'+escape(type_label(row['throws']))+'</code>'+(' — '+error_docs if error_docs else '')+'</p>')
		location = row['source_location']
		parts.append('<p class="source">Source: '+escape(location['path'])+' · UTF-8 bytes '+escape(str(location.get('start', '?')))+'–'+escape(str(location.get('end', '?')))+'</p><details><summary>Compiler contract details · raw JSON</summary><pre>'+escape(json.dumps(row, sort_keys=True, ensure_ascii=False, indent=2))+'</pre></details>')
		if row['links']:
			parts.append('<nav class="related" aria-label="Related APIs"><span>Related</span>')
			for target in dict.fromkeys(row['links']):
				parts.append('<a href="#'+anchor(target)+'">'+escape(by_id[target]['canonical_name'])+'</a>')
			parts.append('</nav>')
		parts.append('</section>')
	parts.append('<footer><p>Contracts describe checked semantics. Native lowering and source-owner liveness require separate qualification.</p><details><summary>Generation details</summary><p>Source/toolchain build: <code>'+escape(build['fingerprint'])+'</code></p></details></footer></main></div></body></html>\n')
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
	p.add_argument('--stylesheet', type=Path, help='Local UTF-8 CSS, embedded in the standalone page (at most 128 KiB)')
	a = p.parse_args()
	with a.input.open('rb') as stream:
		raw = stream.read(64*1024*1024+1)
	if len(raw) > 64*1024*1024: raise ValueError('API document exceeds 64 MiB')
	stylesheet = None
	if a.stylesheet:
		with a.stylesheet.open('rb') as stream: css = stream.read(131073)
		if len(css) > 131072: raise ValueError('stylesheet exceeds 128 KiB')
		stylesheet = css.decode('utf-8')
	data = render(json.loads(raw.decode('utf-8')), stylesheet=stylesheet)
	publish(a.output, data)


if __name__ == '__main__':
	try: main()
	except (OSError, ValueError, KeyError, TypeError) as error:
		print('api renderer: '+str(error), file=sys.stderr)
		raise SystemExit(1)
