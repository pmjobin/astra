#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind final current native receipts, raw streams, products and Git sources."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
RUNTIME = WORK/'runtime'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write
from audit import preservation


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime, RUNTIME)
	runtime.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	receipts = {}
	commands = 0
	strict = 0
	def products(node):
		if isinstance(node, dict):
			if isinstance(node.get('path'), str) and 'sha256' in node:
				assert sha(node['path']) == node['sha256']
			for path,value in node.items():
				if isinstance(value, str) and Path(path).is_absolute() and len(value) == 64:
					assert sha(path) == value
				products(value)
		elif isinstance(node, list):
			for value in node: products(value)
	def raw(directory, name, result):
		nonlocal commands,strict
		commands += 1
		for kind in ('stdout', 'stderr', 'time'):
			leaf = directory/name/('time.txt' if kind == 'time' else kind)
			flat = directory/(name+('.time' if kind == 'time' else '.'+kind))
			path = leaf if leaf.is_file() else flat
			assert sha(path) == result[kind+'_sha256'], path
			if kind == 'stderr' and b'Memcheck, a memory error detector' in path.read_bytes():
				log = path.read_bytes()
				assert all(marker in log for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')), path
				strict += 1
	def receipt(label, directory, status):
		path = directory/'result.json'
		data = json.loads(path.read_text())
		assert data['status'] == status, (label, data['status'])
		for field,name in (('identity_sha256', 'identity.json'), ('observations_sha256', 'observations.json'), ('semantic_oracle_sha256', 'semantic-oracle.json')):
			if field in data: assert sha(directory/name) == data[field]
		for key in ('products', 'emit_products'): products(data.get(key))
		if 'commands_sha256' in data:
			assert sha(directory/'commands.json') == data['commands_sha256']
			for row in json.loads((directory/'commands.json').read_text()):
				name = row.get('name', row.get('label'))
				result = row.get('result', row)
				if 'expected_exit' in result:
					assert result['status'] == 'EXPECTED_OUTCOME' and result['exit'] == result['expected_exit'] and not result['timed_out']
				else: assert result['exit'] == result['expected']
				raw(directory, name, result)
		receipts[label] = dict(path=str(path), sha256=sha(path), status=status)
		return data
	entry = json.loads((RUNTIME/'api-docs28a1-entry/entry-audit.json').read_text())
	assert entry['status'] == 'AUTHENTICICATED_EXISTING_AFTER_PUBLICATION_27D_G8_PASS'
	assert entry['immutable_report_G8'] == 'PENDING' and entry['source_F'] == 230
	assert entry['receipt_sha256'] == 'fb2df80a2872d97a4821277490c294a489b0ab8f524fe55da317ed7e2b2b91fc'
	assert sha(RUNTIME/'selfhost27d-delivery-G8/result.json') == entry['receipt_sha256']
	assert datetime.datetime.fromisoformat(entry['receipt_UTC']) > datetime.datetime.fromisoformat(entry['publication_UTC'])
	identity = json.loads((RUNTIME/'api-docs28a1-full3/identity.json').read_text())
	assert len(identity['sources']) == 239
	for path,value in identity['sources'].items():
		assert sha(path) == value
		name = str(Path(path).relative_to(ROOT))
		assert subprocess.check_output(['git', 'show', 'HEAD:'+name], cwd=ROOT) == Path(path).read_bytes()
	products_path = RUNTIME/'api-docs28a1-products.json'
	images = json.loads(products_path.read_text())['products']
	assert set(images) == {'O0', 'O2'}
	physical_mutations = 0
	for mode,product in images.items():
		assert sha(product['path']) == product['sha256'] and sha(product['object']) == product['object_sha256']
		assert all(sha(product[kind]['path']) == product[kind]['sha256'] for kind in ('native', 'doc'))
		focused = receipt(mode+'-focused', RUNTIME/('api-docs28a1-focused-edges-'+mode), 'FOCUSED_NATIVE_DOCS_ACCEPTANCE_PASS')
		assert focused['negatives'] == 20 and focused['source_sha256'] == sha(Path(__file__).with_name('run.py'))
		receipt(mode+'-native', RUNTIME/('api-docs28a1-native-'+mode), 'CURRENT_COMPLETE_COMPILER_DOCS_ISOLATION_AND_COMMENT_EQUIVALENCE_PASS')
		receipt(mode+'-previews', RUNTIME/('api-docs28a1-current-preview-'+mode), 'CURRENT_COMPILER_REAL_API_PREVIEWS_PASS')
		for group,count in (('library', 2), ('catalog', 6)):
			suffix = '2' if mode == 'O0' and group == 'catalog' else ''
			example = receipt(mode+'-'+group+'-examples', RUNTIME/('api-docs28a1-current-examples-'+mode+'-'+group+suffix), 'CHECKED_DOCUMENTATION_EXAMPLES_PASS')
			assert example['examples'] == count and example['strict_memory'] and example['profiles'] == ['O0', 'O2']
		consolidated = receipt(mode+'-consolidated', RUNTIME/('api-docs28a1-consolidated-'+mode), 'CURRENT_CONSOLIDATED_NATIVE_ABI_OWNER_PHYSICAL_PASS')
		assert len(consolidated['suites']) == (11 if mode == 'O0' else 12)
		for suite in consolidated['suites']:
			label = suite['label']
			feature = label[len(mode)+1:]
			directory = RUNTIME/('api-docs28a1-consolidated-'+mode)/label
			expected = {'ownership':'SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS', 'intrinsic':'SELECTED_INTRINSIC_ABI_NATIVE_GATES_PASS', 'C-client':'EXISTING_C_TO_ASTRA_STRING_DESCRIPTOR_CLIENT_PASS', 'source-owner':'FOCUSED_EXPRESSIVE_SEMANTIC_COMPONENT_PASS'}.get(feature)
			if feature.startswith('physical-'): expected = 'SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS'
			if feature in ('named', 'match', 'range', 'format', 'collection'): expected = 'SELECTED_EXPRESSIVE_NATIVE_AND_MEMORY_PASS'
			assert expected and sha(directory/'result.json') == suite['receipt_sha256']
			data = receipt('source-owner' if feature == 'source-owner' else label, directory, expected)
			if feature.startswith('physical-'): physical_mutations += data['mutations']
			if feature == 'source-owner': assert set(data['products']) == {'O0', 'O2'}
			for key in ('sources', 'source_inputs', 'providers', 'tools', 'actual_sources'):
				for path,value in data.get(key, {}).items():
					if isinstance(value, str) and Path(path).is_absolute(): assert sha(path) == value
	assert physical_mutations == 46
	host = receipt('private-transport', RUNTIME/'api-docs28a1-host3', 'PRIVATE_DOC_TRANSPORT_PASS')
	assert host['sha256_vectors'] == 13 and host['source_sha256'] == sha(ROOT/'compiler/docs/host.c')
	renderer = receipt('static-renderer', Path('/tmp/astra-docs28a1-render-unit8'), 'STRUCTURED_STATIC_RENDERER_PASS')
	assert renderer['renderer_sha256'] == sha(ROOT/'tools/docs/render.py')
	assert renderer['output_sha256'] == sha(Path('/tmp/astra-docs28a1-render-unit8/no-native-tools.html'))
	preserved = preservation(RUNTIME/'selfhost27b-intake/pre-edit-preservation.json')
	earlier = json.loads((RUNTIME/'api-docs28a1-preservation-current.json').read_text())['result']
	assert earlier['workflow_current_hashes'] == preserved['workflow_current_hashes']
	for group in ('library', 'compiler-source', 'catalog'):
		for suffix in ('.json', '.html', '-native.html'):
			assert (WORK/('build/api-docs28a1/current-preview-O0/'+group+suffix)).read_bytes() == (WORK/('build/api-docs28a1/current-preview-O2/'+group+suffix)).read_bytes()
	visual = json.loads((RUNTIME/'api-docs28a1-visual-final.json').read_text())
	assert visual['status'] == 'CURRENT_LIBRARY_LOCAL_DESKTOP_MOBILE_AND_FRAGMENT_VISUAL_PASS'
	assert all(sha(path) == value for path,value in visual['screenshots'].items())
	write(runtime/'result.json', dict(status='CURRENT_G0_G6_QUALIFIED_AND_G7_PUBLICATION_STEP_READY', completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), final_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), source_identity_sha256=sha(RUNTIME/'api-docs28a1-full3/identity.json'), products_manifest=dict(path=str(products_path), sha256=sha(products_path)), receipts=receipts, rehashed_command_records=commands, rechecked_strict_memory_streams=strict, physical_mutations=physical_mutations, preservation=preserved, publication_check=dict(status='PENDING_AFTER_ACTUAL_REPORT_PUBLICATION', recipe='tests/api-docs/delivery.py', sha256=sha(Path(__file__).with_name('delivery.py'))), scope='Current source/native evidence only. Historical 27-B PARTIAL, 1044 missing proofs and C0 memory NOT_PASS remain; owner provenance substitution is separate. Publication-dependent receipt cannot exist before the actual ZIP.'))
	print('Current native evidence authenticated; publication-dependent check remains separate')


if __name__ == '__main__':
	main()
