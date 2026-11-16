#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Generate and verify real library/compiler examples with a current compiler."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('products', 'identity', 'toolchain', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	product = json.loads(a.products.read_text())['products'][a.mode]
	assert sha(product['path']) == product['sha256']
	assert all(sha(product[kind]['path']) == product[kind]['sha256'] for kind in ('native', 'doc'))
	identity = json.loads(a.identity.read_text())
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=False)
	runtime.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	toolchain = json.loads(a.toolchain.read_text())
	assert all(sha(path) == value for path,value in toolchain['tools'].items())
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	assert subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4'
	libraries = sorted(identity['material']['sources'])
	libraries = [path for path in libraries if path.startswith('lib/')]
	assert len(libraries) == 10
	groups = {'library':['lib/astra/base/order.astra'], 'compiler-source':['compiler/source/source.astra', *libraries], 'catalog':['tests/api-docs/examples.astra']}
	commands = []
	products = {}
	inputs = {path:sha(ROOT/path) for paths in groups.values() for path in paths}
	def run(label, argv):
		result = execute(argv, runtime/label, timeout=300, env=env)
		commands.append(dict(label=label, argv=list(map(str, argv)), result=result))
		write(runtime/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', label
	counts = {}
	for name,paths in groups.items():
		document = build/(name+'.json')
		run(name+'-extract', [product['path'], 'doc', '--output', document, *paths])
		data = json.loads(document.read_text())
		assert data['build']['fingerprint'] == identity['fingerprint']
		assert all(inputs[row['path']] == row['sha256'] for row in data['inputs'])
		import jsonschema
		jsonschema.Draft202012Validator(json.loads((ROOT/'docs/api/schema.json').read_text())).validate(data)
		counts[name] = len(data['symbols'])
		repeat = build/(name+'-repeat.json')
		run(name+'-repeat', [product['path'], 'doc', '--output', repeat, *reversed(paths)])
		assert repeat.read_bytes() == document.read_bytes()
		memory = build/(name+'-memory.json')
		run(name+'-memory', ['valgrind', '--trace-children=yes', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product['path'], 'doc', '--output', memory, *paths])
		assert all(marker in (runtime/(name+'-memory')/'stderr').read_bytes() for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		assert memory.read_bytes() == document.read_bytes()
		native_html = build/(name+'-native.html')
		run(name+'-native-html', [product['path'], 'doc', '--format', 'html', '--output', native_html, *paths])
		styled = build/(name+'.html')
		run(name+'-styled-html', ['python3', '-B', ROOT/'tools/docs/render.py', document, '--output', styled])
		if name == 'library':
			assert {row['canonical_name'] for row in data['symbols']} == {'min', 'max'}
			assert all(row['generic_constraints'] for row in data['symbols'])
		if name == 'compiler-source':
			rows = {row['canonical_name']:row for row in data['symbols']}
			assert rows['source_buffer']['documentation']['markdown'] and rows['SourceBuffer']['documentation']['markdown']
			assert rows['source_buffer']['type_contract']['arguments'][0]['ownership'] == 'owned'
			assert 'SourceBuffer.interface_input' not in rows and 'SourceBuffer.native_interface' in rows
		for path in (document, native_html, styled): products[str(path)] = sha(path)
	assert all(sha(ROOT/path) == value for path,value in inputs.items())
	write(runtime/'result.json', dict(status='CURRENT_COMPILER_REAL_API_PREVIEWS_PASS', host_profile=a.mode, producer=product, inputs=inputs, symbol_counts=counts, emit_products=products, renderer_sha256=sha(ROOT/'tools/docs/render.py'), stylesheet_sha256=sha(ROOT/'tools/docs/api.css'), commands_sha256=sha(runtime/'commands.json'), scope='Actual source-derived JSON, native/static HTML, schema, shuffled inputs and strict all-kinds extraction memory. Example execution and browser inspection remain separate.'))
	print(json.dumps(dict(status='CURRENT_COMPILER_REAL_API_PREVIEWS_PASS', symbol_counts=counts)))


if __name__ == '__main__':
	main()
