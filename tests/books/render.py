#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Hostile-input and reproducibility controls for the offline book adapter."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tools/docs'))
import books
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime',type=Path,required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime,WORK/'runtime'); runtime.mkdir(parents=True,exist_ok=False)
	api = ROOT/'docs/api/examples/minmax.json'
	first,receipt = books.build(api,api)
	assert first == books.build(api,api)[0]
	checks = ['byte-identical-double-generation','all-local-links-and-fragments']
	def refuse(label,fn):
		try: fn()
		except (ValueError,AssertionError,KeyError): checks.append(label)
		else: raise AssertionError('unsafe input accepted: '+label)
	refuse('source-traversal',lambda:books.source('../codex/reports/astra-report-current.zip'))
	refuse('fixture-mismatch',lambda:books.fenced_examples('```astra example=hello\nwrong\n```',books.fixtures()[1]))
	refuse('unknown-fixture',lambda:books.fenced_examples('```astra example=missing\nwrong\n```',books.fixtures()[1]))
	refuse('unmarked-source',lambda:books.fenced_examples('```astra\nint main() {}\n```',books.fixtures()[1]))
	refuse('unclosed-fence',lambda:books.fenced_examples('```text\nopen',{}))
	refuse('missing-fragment',lambda:books.check_links({'x.html':b'<a href="#absent">bad</a>'}))
	refuse('active-script',lambda:books.check_links({'x.html':b'<script>bad()</script>'}))
	refuse('external-resource',lambda:books.check_links({'x.html':b'<img src="https://example.invalid/a.png">'}))
	items = books.fixtures()[1]
	link = '[Original source](../../tests/books/hello.astra)'
	origin = 'docs/guide/glossary.md'
	assert books.linked_examples(link,origin,items)==['hello']
	for text in ('```text\n'+link+'\n```', '`'+link+'`', '[False](https://example.invalid/tests/books/hello.astra)', link.replace('hello.astra','missing.astra'), link.replace('hello.astra','hello.astra#fragment')):
		assert books.linked_examples(text,origin,items)==[]
	checks.append('only-real-fixture-download-links-count-as-publication')
	read = books.source
	def modified(addition):
		books.source = lambda path: read(path)+(addition.encode() if path=='docs/guide/glossary.md' else b'')
	try:
		modified('\n**<script>unsafe</script>**\n')
		outputs,_ = books.build(api,api)
		assert b'<strong>&lt;script&gt;unsafe&lt;/script&gt;</strong>' in outputs['guide/glossary.html']
		checks.append('strong-text-escaped-without-active-markup')
		modified('\n'+link+'\n')
		outputs,_ = books.build(api,api)
		assert outputs['sources/tests/books/hello.astra.txt']==books.source('tests/books/hello.astra')
		checks.append('linked-fixture-download-is-byte-exact')
		modified('\n<script>alert(1)</script>\n')
		outputs,_ = books.build(api,api)
		assert b'&lt;script&gt;' in outputs['guide/glossary.html'] and b'<script>' not in outputs['guide/glossary.html']
		checks.append('raw-html-escaped')
		modified('\n[x](javascript:alert)\n')
		refuse('javascript-link',lambda:books.build(api,api))
		modified('\n# Glossary, index and edition history\n')
		refuse('duplicate-heading',lambda:books.build(api,api))
	finally: books.source = read
	order = [row for row in json.loads(books.source('docs/chapters.json'))['chapters'] if row.get('book') == 'guide']
	assert [row['number'] for row in order] == list(range(13))
	for at,row in enumerate(order):
		page = first[str(Path(row['source']).with_suffix('.html'))].decode()
		for offset,relation in ((-1,'prev'),(1,'next')):
			if 0 <= at+offset < len(order):
				target = Path(order[at+offset]['source']).with_suffix('.html').name
				assert 'rel="'+relation+'" href="'+target+'"' in page
			else: assert 'rel="'+relation+'"' not in page
	checks.append('all-guide-previous-next-links-follow-chapter-registry')
	for row in books.fixtures()[0]['files']:
		assert first['sources/'+row['path']+'.txt'] == books.source(row['path'])
	checks.append('every-manifest-fixture-download-is-byte-exact')
	assert first == books.build(api,api)[0]
	write(runtime/'result.json',dict(status='BOOK_RENDERER_HOSTILE_INPUT_AND_REPRODUCIBILITY_PASS',checks=checks,renderer_sha256=sha(ROOT/'tools/docs/books.py'),stylesheet_sha256=sha(ROOT/'tools/docs/books.css'),local_links=receipt['local_links'],scope='Standard-library source/render controls; no native compiler or browser acceptance inferred.'))
	print(len(checks),'renderer controls passed')


if __name__ == '__main__':
	main()
