#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Offline book adapter: bounded Markdown, exact fixtures and local link checking."""
import argparse
import hashlib
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import posixpath
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from render import render


def digest(data):
	return hashlib.sha256(data).hexdigest()


def source(path):
	path = ROOT/path
	if not path.resolve().is_relative_to(ROOT) or any(p.is_symlink() for p in (path, *path.parents)):
		raise ValueError('source path escapes repository or traverses symlink')
	data = path.read_bytes()
	if len(data) > 2*1024*1024: raise ValueError('source exceeds bound')
	return data


def slug(text):
	return re.sub('[^a-z0-9]+', '-', text.lower()).strip('-')


def fixtures():
	data = json.loads(source('tests/books/examples.json'))
	assert data['format'] == 'astra-book-examples/1'
	items = {row['id']:row for row in data['files']}
	assert len(items) == len(data['files'])
	for row in items.values(): source(row['path'])
	for case in data['cases']:
		assert all(key in items for key in case['files'])
		assert case['mode'] in ('run', 'compile_fail', 'compile')
	return data,items


def fenced_examples(text, items):
	active = None
	seen = []
	lines = []
	for line in text.splitlines():
		if line.startswith('```'):
			if active is None:
				active = line[3:]
				lines = []
			else:
				assert line == '```', 'malformed fence'
				if active.startswith(('astra', 'c ')):
					match = re.fullmatch(r'(?:astra|c) example=([a-z][a-z0-9-]*)', active)
					assert match, 'source fence needs an exact example ID'
					key = match[1]
					assert key in items and source(items[key]['path']) == ('\n'.join(lines)+'\n').encode(), key
					seen.append(key)
				active = None
		elif active is not None: lines.append(line)
	assert active is None, 'unclosed fence'
	return seen


def linked_examples(text, origin, items):
	"""Count explicit fixture downloads, excluding code and external lookalikes."""
	paths = {row['path']:key for key,row in items.items()}
	seen = []; fenced = False
	for line in text.splitlines():
		if line.startswith('```'):
			fenced = not fenced
			continue
		if fenced: continue
		for part in re.split(r'(`[^`\n]+`|\[[^\]\n]+\]\([^\s)]+\))',line):
			if not re.fullmatch(r'\[[^\]\n]+\]\([^\s)]+\)',part): continue
			url = urlsplit(part[1:-1].split('](',1)[1])
			if url.scheme or url.netloc or url.query or url.fragment: continue
			path = posixpath.normpath(posixpath.join(posixpath.dirname(origin),unquote(url.path)))
			if path in paths:
				source(path)
				seen.append(paths[path])
	return seen


def inspect():
	chapters = json.loads(source('docs/chapters.json'))
	assert len({row['id'] for row in chapters['chapters']}) == len(chapters['chapters'])
	for row in chapters['chapters']:
		path = Path(row['source'])
		assert not path.is_absolute() and '..' not in path.parts and str(path) == row['source']
	data,items = fixtures()
	seen = []
	hashes = {}
	for row in chapters['chapters']:
		if row.get('book') not in ('reference', 'guide'): continue
		path = 'docs/'+row['source']
		content = source(path)
		assert content.startswith(b'# '), path
		assert len(content.split()) >= 160, ('chapter too short for review', path)
		seen.extend(fenced_examples(content.decode(), items))
		seen.extend(linked_examples(content.decode(), path, items))
		hashes[path] = digest(content)
	assert set(items) <= set(seen), ('unpublished fixtures', set(items)-set(seen))
	rules = json.loads(source('docs/books/rules.json'))
	assert len({r['id'] for r in rules['rules']}) == len(rules['rules'])
	for rule in rules['rules']:
		assert rule['positive'] and rule['negative'] and rule['sources']
		assert rule['chapter'] in hashes
		assert rule['id'] in source(rule['chapter']).decode(), rule['id']
		for item in rule['sources']:
			body = source(item['path'])
			assert digest(body) == item['sha256'], item['path']
			start,end = item['span']
			assert body[start:end] and digest(body[start:end]) == item['span_sha256']
			assert item['symbol'].encode() in body[start:end]
		for item in (*rule['positive'], *rule['negative']):
			assert item['id'].encode() in source(item['path']), item
	return chapters,dict(status='BOOK_SOURCE_PREFLIGHT_PASS', chapters=len(hashes), words=sum(len(source(path).decode().split()) for path in hashes), rules=len(rules['rules']), fixture_files=len(items), examples=len(data['cases']), sources=hashes)


class Links(HTMLParser):
	def __init__(self):
		super().__init__()
		self.ids = set()
		self.links = []
	def handle_starttag(self, tag, attrs):
		for key,value in attrs:
			if key == 'id':
				assert value not in self.ids, ('duplicate HTML anchor', value)
				self.ids.add(value)
			if key in ('href', 'src'): self.links.append(value)
		assert tag not in ('script', 'iframe', 'object'), tag


def check_links(outputs):
	parsed = {}
	for name,data in outputs.items():
		if name.endswith('.html'):
			p = Links()
			p.feed(data.decode())
			parsed[name] = p
	count = 0
	for name,p in parsed.items():
		for link in p.links:
			url = urlsplit(link)
			assert not url.scheme and not url.netloc and not url.query, ('nonlocal book dependency', name, link)
			target = posixpath.normpath(posixpath.join(posixpath.dirname(name), unquote(url.path))) if url.path else name
			assert target in outputs, ('broken local link', name, link, target)
			if url.fragment: assert target in parsed and unquote(url.fragment) in parsed[target].ids, ('broken fragment', name, link)
			count += 1
	return count


def build(api_library, api_compiler):
	chapters,receipt = inspect()
	rows = [row for row in chapters['chapters'] if row.get('book') in ('reference', 'guide')]
	routes = {'docs/'+row['source']:str(Path(row['source']).with_suffix('.html')) for row in rows}
	assert len(routes) == len(rows)
	outputs = {}
	css = source('tools/docs/books.css').decode().replace('<', '\\3c ')
	assets = {}
	def resolve(origin, target):
		url = urlsplit(target)
		assert not url.scheme and not url.netloc and not url.query, target
		if not url.path: return '#'+url.fragment
		path = posixpath.normpath(posixpath.join(posixpath.dirname(origin), unquote(url.path)))
		assert not path.startswith(('/', '../')), target
		if path in routes: route = routes[path]
		elif path in ('docs/api/library.html', 'docs/api/compiler.html'): route = path.removeprefix('docs/')
		else:
			# Supporting source/recipes are downloadable byte-exact witnesses.
			route = 'sources/'+path+('.txt' if not path.endswith(('.json', '.txt')) else '')
			assets[route] = source(path)
		assert not url.fragment or path in routes or path.endswith('.html'), target
		return posixpath.relpath(route, posixpath.dirname(routes[origin]))+('#'+url.fragment if url.fragment else '')
	def inline(origin, text):
		parts = re.split(r'(`[^`\n]+`|\[[^\]\n]+\]\([^\s)]+\))', text)
		result = []
		for part in parts:
			if part.startswith('`'): result.append('<code>'+html.escape(part[1:-1])+'</code>')
			elif re.fullmatch(r'\[[^\]\n]+\]\([^\s)]+\)', part):
				label,target = part[1:-1].split('](', 1)
				result.append('<a href="'+html.escape(resolve(origin,target),quote=True)+'">'+html.escape(label)+'</a>')
			else: result.append(html.escape(part))
		return ''.join(result)
	def markdown(origin):
		parts = []
		paragraph = []
		code = None
		listing = False
		table = False
		headings = set()
		def flush():
			if paragraph:
				parts.append('<p>'+inline(origin,' '.join(paragraph))+'</p>')
				paragraph.clear()
		for line in source(origin).decode().splitlines()+['']:
			if line.startswith('```'):
				flush()
				if code is None: code = []
				else:
					parts.append('<pre tabindex="0"><code>'+html.escape('\n'.join(code))+'</code></pre>')
					code = None
				continue
			if code is not None:
				code.append(line)
				continue
			if listing and not line.startswith('- '):
				parts.append('</ul>'); listing = False
			if table and not line.startswith('|'):
				parts.append('</tbody></table></div>'); table = False
			if line.startswith('#'):
				flush()
				match = re.fullmatch(r'(#{1,6}) (.+)',line)
				assert match, line
				level = len(match[1]); label = match[2]; anchor = slug(label)
				assert anchor not in headings, (origin,anchor)
				headings.add(anchor)
				parts.append(f'<h{level} id="{anchor}">'+inline(origin,label)+f'</h{level}>')
			elif line.startswith('- '):
				flush()
				if not listing: parts.append('<ul>'); listing = True
				parts.append('<li>'+inline(origin,line[2:])+'</li>')
			elif line.startswith('|'):
				flush()
				cells = [c.strip() for c in line.strip('|').split('|')]
				if all(re.fullmatch('[-: ]+',c) for c in cells): continue
				if not table:
					parts.append('<div class="table-scroll"><table><thead><tr>'+''.join('<th scope="col">'+inline(origin,c)+'</th>' for c in cells)+'</tr></thead><tbody>'); table = True
				else: parts.append('<tr>'+''.join('<td>'+inline(origin,c)+'</td>' for c in cells)+'</tr>')
			elif not line.strip(): flush()
			else: paragraph.append(line)
		assert code is None
		return ''.join(parts)
	def shell(title, nav, body):
		navigation = '<details class="mobile-toc"><summary>Chapters and search</summary>'+nav+'</details><div class="desktop-toc">'+nav+'</div>'
		return ('<!doctype html>\n<!-- astra-books/1 -->\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'"><title>'+html.escape(title)+' · Astra 28-A2</title><style>'+css+'</style></head><body><a class="skip" href="#content">Skip to content</a><div class="layout"><aside><p class="brand">ASTRA / BOOKS</p>'+navigation+'</aside><main id="content" tabindex="-1"><p class="edition">Development edition 28-A2 · GNU/Linux x86-64 · LLVM 23.1.4</p>'+body+'<footer>Canonical Markdown. Local reading and print-friendly HTML; release qualification and print production remain separate.</footer></main></div></body></html>\n').encode()
	for row in rows:
		origin = 'docs/'+row['source']; route = routes[origin]
		def relative(target): return posixpath.relpath(target,posixpath.dirname(route))
		nav = '<nav aria-label="Books"><a href="'+relative('index.html')+'">Library</a><ol>'
		nav += ''.join('<li><a href="'+relative(routes['docs/'+r['source']])+'">'+html.escape(r['title'])+'</a></li>' for r in rows if r['book'] == row['book'])
		nav += '</ol><a href="'+relative(row['book']+'/print.html')+'">Print / complete book</a><p>Search the complete book with your browser’s Find command, or use the subject index.</p></nav>'
		outputs[route] = shell(row['title'], nav, markdown(origin))
	for book in ('reference','guide'):
		selected = [r for r in rows if r['book'] == book]
		# Compose using the same chapter-relative directory, prefixing anchors.
		body = []
		toc = []
		for number,row in enumerate(selected,1):
			fragment = markdown('docs/'+row['source'])
			prefix = row['id']+'-'
			fragment = re.sub(r'id="([^"]+)"',lambda m:'id="'+prefix+m[1]+'"',fragment)
			def joined_link(match):
				href = html.unescape(match[1]); u = urlsplit(href)
				if not u.path: return 'href="#'+prefix+u.fragment+'"'
				for other in selected:
					if u.path == Path(other['source']).with_suffix('.html').name:
						anchor = u.fragment or slug(other['title'])
						return 'href="#'+other['id']+'-'+anchor+'"'
				return match[0]
			fragment = re.sub(r'href="([^"]+)"',joined_link,fragment)
			anchor = prefix+slug(row['title'])
			toc.append('<li><a href="#'+anchor+'">'+html.escape(row['title'])+'</a></li>')
			body.append('<article class="chapter"><p class="chapter-number">Chapter '+str(number)+'</p>'+fragment+'</article>')
		outputs[book+'/print.html'] = shell('The Astra Language Reference' if book == 'reference' else 'The Astra Programming Language', '<nav aria-label="Print contents"><a href="../index.html">Library</a><h2>Contents</h2><ol>'+''.join(toc)+'</ol></nav>', ''.join(body))
	outputs['index.html'] = shell('Library', '<a href="#content">Contents</a>', '<h1>Astra books</h1><p>Two complementary works for the implemented native language. Read the qualification and feature matrix before relying on a contract.</p><ul>'+''.join('<li><a href="'+routes['docs/'+r['source']]+'">'+html.escape(r['title'])+'</a></li>' for r in rows if r['source'].endswith('README.md'))+'</ul><p><a href="reference/print.html">Complete Reference / browser search / print</a></p><p><a href="guide/print.html">Complete Guide / browser search / print</a></p><p><a href="api/library.html">Generated library API</a> · <a href="api/compiler.html">Generated compiler API</a></p>')
	for name,path in [('library',api_library),('compiler',api_compiler)]:
		assert path.is_file() and not path.is_symlink()
		outputs['api/'+name+'.html'] = render(json.loads(path.read_text()))
	outputs.update(assets)
	links = check_links(outputs)
	receipt.update(outputs={name:digest(data) for name,data in sorted(outputs.items())}, local_links=links, api_inputs={name:digest(path.read_bytes()) for name,path in [('library',api_library),('compiler',api_compiler)]})
	outputs['BUILD.json'] = (json.dumps(receipt,sort_keys=True,indent=2)+'\n').encode()
	return outputs,receipt


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--check', action='store_true')
	p.add_argument('--output',type=Path)
	p.add_argument('--api-library',type=Path)
	p.add_argument('--api-compiler',type=Path)
	a = p.parse_args()
	if a.output:
		assert a.api_library and a.api_compiler
		outputs,receipt = build(a.api_library,a.api_compiler)
		assert a.output.is_absolute() and a.output.resolve().is_relative_to(ROOT.parent/'codex/work/astra/build')
		assert not any(path.is_symlink() for path in (a.output,*a.output.parents))
		if a.check:
			assert not any(path.is_symlink() for path in a.output.rglob('*'))
			assert {str(path.relative_to(a.output)) for path in a.output.rglob('*') if path.is_file()} == set(outputs)
			assert all((a.output/name).read_bytes() == data for name,data in outputs.items())
		else:
			a.output.mkdir(parents=True,exist_ok=False)
			for name,data in outputs.items():
				path = a.output/name
				path.parent.mkdir(parents=True,exist_ok=True)
				path.write_bytes(data)
	else: _,receipt = inspect()
	print(json.dumps({k:v for k,v in receipt.items() if k not in ('outputs','sources')},sort_keys=True))


if __name__ == '__main__':
	main()
