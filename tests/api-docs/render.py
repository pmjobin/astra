#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Adversarial structured-renderer tests; fixtures carry no extraction credit."""
import argparse
import copy
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


class Inspect(HTMLParser):
	def __init__(self):
		super().__init__()
		self.ids = []
		self.links = []

	def handle_starttag(self, tag, attributes):
		assert tag not in ('script', 'iframe', 'img', 'object')
		assert not any(key.startswith('on') for key,value in attributes)
		values = dict(attributes)
		if 'id' in values: self.ids.append(values['id'])
		if tag == 'a': self.links.append(values['href'])


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	spec = importlib.util.spec_from_file_location('astra_docs_json_renderer', ROOT/'tools/docs/render.py')
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	row = dict(id='v1:0:function:answer:Fn<int>', canonical_name='answer', kind='function', signature='answer : Fn<int>', visibility='public', documentation=dict(markdown='<script>bad()</script> $(touch EXECUTED) <img src=x onerror=bad()>'), source_location=dict(path='api.astra', start=0, end=1), links=[], type_contract={}, throws=None, parameters=[], type_parameters=[], attributes={}, availability={})
	other = copy.deepcopy(row)
	other.update(id='v1:0:function:other:Fn<int>', canonical_name='other', links=[row['id']])
	row['owner'] = None
	other['owner'] = row['id']
	document = dict(format='astra-api-docs/1', schema_version=1, compiler='fixture', provenance='authored adversarial fixture; no extraction credit', inputs=[], symbols=[row, other])
	document['build'] = dict(kind='source-toolchain-sha256', fingerprint='unavailable')
	raw = module.render(document)
	assert raw == module.render(document)
	inspect = Inspect()
	inspect.feed(raw.decode())
	assert len(inspect.ids) == len(set(inspect.ids))
	assert all(value.startswith('#') and value[1:] in inspect.ids for value in inspect.links)
	assert b'&lt;script&gt;' in raw and b'<script>' not in raw
	rich = copy.deepcopy(document)
	rich['symbols'][0]['type_contract'] = dict(kind=25, name='Fn<int,int>', arguments=[dict(name='int', effective_flags=0)])
	rich['symbols'][0]['parameters'] = [dict(name='value', type_contract=dict(name='int', effective_flags=0))]
	rich['symbols'][0]['links'] = [other['id']]
	rich['symbols'][0]['documentation']['markdown'] = '@param value <script>bad()</script>\n@return See {@link other}.'
	rich_output = module.render(rich, stylesheet='body { color: #123; } </style><script>bad()</script>')
	assert b'<script>' not in rich_output and b'&lt;script&gt;' in rich_output
	assert b'<p class="contract-note"><code>int</code> \xe2\x80\x94 See <a href="#' in rich_output and b'Compiler contract details' in rich_output
	Inspect().feed(rich_output.decode())
	output = a.runtime/'api.html'
	module.publish(output, raw)
	new = copy.deepcopy(document)
	new['symbols'] = [row]
	module.publish(output, module.render(new))
	assert other['id'].encode().hex().encode() not in output.read_bytes()
	output.write_bytes(b'USER_FILE\n')
	try: module.publish(output, raw)
	except ValueError: pass
	else: raise AssertionError('existing non-generated file overwritten')
	assert output.read_bytes() == b'USER_FILE\n'
	link = a.runtime/'linked.html'
	link.symlink_to(output)
	try: module.publish(link, raw)
	except OSError: pass
	else: raise AssertionError('symlink output accepted')
	for mutate in (
		lambda doc:doc.update(schema_version=2),
		lambda doc:doc.update(schema_version=True),
		lambda doc:doc['symbols'][0].update(documentation=None),
		lambda doc:doc['symbols'][0].update(owner=row['id']),
		lambda doc:doc['symbols'][0].update(owner='missing'),
		lambda doc:doc['symbols'].append(copy.deepcopy(row)),
		lambda doc:doc['symbols'][0]['links'].append('missing'),
		lambda doc:doc['symbols'][0]['source_location'].update(path='/host/private'),
		lambda doc:doc['symbols'][0]['source_location'].update(path='../escape'),
	):
		bad = copy.deepcopy(document)
		mutate(bad)
		try: module.render(bad)
		except ValueError: pass
		else: raise AssertionError('invalid structured input accepted')
	input_path = a.runtime/'api.json'
	input_path.write_text(json.dumps(document))
	env = dict(os.environ, PATH='/nonexistent')
	r = subprocess.run([sys.executable, '-B', ROOT/'tools/docs/render.py', input_path, '--output', a.runtime/'no-native-tools.html'], env=env, capture_output=True)
	assert r.returncode == 0 and not r.stderr and not (a.runtime/'EXECUTED').exists()
	result = dict(status='STRUCTURED_STATIC_RENDERER_PASS', scope='Authored JSON adversaries only; compiler extraction separate', renderer_sha256=hashlib.sha256((ROOT/'tools/docs/render.py').read_bytes()).hexdigest(), output_sha256=hashlib.sha256((a.runtime/'no-native-tools.html').read_bytes()).hexdigest(), native_tools_available=False, examples_executed=False)
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result))


if __name__ == '__main__':
	main()
