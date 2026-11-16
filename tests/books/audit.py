#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authenticate actual book outcomes without promoting partial specification coverage."""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
RUNTIME = WORK/'runtime'
sys.path.insert(0,str(ROOT/'tools/docs'))
import books
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write
from audit import preservation


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--site',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime,RUNTIME); runtime.mkdir(parents=True,exist_ok=False)
	entry = json.loads((RUNTIME/'books28a2-entry/entry.json').read_text())
	assert entry['status']=='AUTHENTICATED_28A1_AFTER_PUBLICATION_G7_PASS'
	native_dir = RUNTIME/'books28a2-native-final1'
	native = json.loads((native_dir/'result.json').read_text())
	assert native['status']=='BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS' and len(native['cases'])==25
	for field in ('inputs','emit_products'):
		assert all(sha(path)==digest for path,digest in native[field].items()),field
	reg_dir = RUNTIME/'books28a2-regression-final1'
	reg = json.loads((reg_dir/'result.json').read_text())
	docs_dir = RUNTIME/'books28a2-docs-retry1'
	docs = json.loads((docs_dir/'result.json').read_text())
	assert docs['status']=='CURRENT_BOOK_DOC_SCHEMA_PREVIEW_PASS'
	retried = {row['label'] for row in docs['suites']}
	assert retried=={'O0-docs-focused','O2-docs-focused','O0-api-preview','O2-api-preview'}
	assert all(row['result']['status']=='EXPECTED_OUTCOME' for row in docs['suites'])
	assert all(row['result']['status']=='EXPECTED_OUTCOME' for row in reg['suites'] if row['label'] not in retried)
	assert len(reg['suites'])==29
	physical = 0
	for row in reg['suites']:
		if '-physical-' in row['label']:
			result = json.loads((reg_dir/row['label']/'result.json').read_text())
			assert result['status']=='SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS'
			physical += result['mutations']
	assert physical==46
	for mode in ('O0','O2'):
		for group in ('library','compiler-source'):
			path = WORK/('build/books28a2/docs-retry1/'+mode+'-api-preview/'+group+'.json')
			other = WORK/('build/books28a2/docs-retry1/O0-api-preview/'+group+'.json')
			assert path.read_bytes()==other.read_bytes()
	api = WORK/'build/books28a2/docs-retry1/O0-api-preview'
	outputs,content = books.build(api/'library.json',api/'compiler-source.json')
	assert all((a.site/name).read_bytes()==data for name,data in outputs.items())
	assert all(b'/home/pmjobin' not in data for name,data in outputs.items() if name.endswith(('.html','.json')))
	render = json.loads((RUNTIME/'books28a2-render-tests-final2/result.json').read_text())
	assert render['status']=='BOOK_RENDERER_HOSTILE_INPUT_AND_REPRODUCIBILITY_PASS'
	visual = json.loads((RUNTIME/'books28a2-visual.json').read_text())
	assert visual['status']=='BOOK_DESKTOP_MOBILE_KEYBOARD_AND_PRINT_VISUALLY_REVIEWED'
	assert all(sha(path)==digest for path,digest in visual['screenshots'].items())
	assert all(sha(a.site/path)==digest for path,digest in visual['HTML'].items())
	owner_products = json.loads((RUNTIME/'api-docs28a1-consolidated-O2/O2-source-owner/result.json').read_text())['products']
	assert all(sha(row['path'])==row['sha256'] for row in owner_products.values())
	commands = strict = failures = 0; costs = []
	for base in (native_dir,reg_dir,docs_dir,RUNTIME/'books28a2-browser-final'):
		for path in sorted(base.rglob('commands.json')):
			for row in json.loads(path.read_text()):
				name = row.get('label',row.get('name')); result = row.get('result',row)
				if 'stdout_sha256' not in result: continue
				commands += 1
				if result['exit']!=result.get('expected_exit',result.get('expected')): failures += 1
				for kind in ('stdout','stderr','time'):
					leaf = path.parent/name/('time.txt' if kind=='time' else kind)
					if not leaf.is_file(): leaf = path.parent/(name+('.time' if kind=='time' else '.'+kind))
					assert sha(leaf)==result[kind+'_sha256'],leaf
					if kind=='stderr' and b'Memcheck, a memory error detector' in leaf.read_bytes():
						assert all(marker in leaf.read_bytes() for marker in (b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)')),leaf
						strict += 1
					if kind=='time':
						values = {}
						for line in leaf.read_text().splitlines():
							if ': ' in line:
								key,value = line.strip().split(': ',1); values[key]=value
						costs.append(dict(path=str(leaf.relative_to(RUNTIME)),wall_seconds=result.get('seconds'),user_seconds=values.get('User time (seconds)'),system_seconds=values.get('System time (seconds)'),maximum_RSS_KiB=values.get('Maximum resident set size (kbytes)'),role='controller (may include child CPU)' if name.endswith('-controller') else 'individual timed command; do not add to enclosing controller'))
	assert failures==4,'Only the four preserved missing-schema-environment attempts may fail'
	identity = json.loads((RUNTIME/'api-docs28a1-full3/identity.json').read_text())
	assert len(identity['sources'])==239 and all(sha(path)==digest for path,digest in identity['sources'].items())
	assert not subprocess.check_output(['git','diff','9f5dfce1a7dbaa8fba93e783762563add34a1948','--','compiler','lib'],cwd=ROOT).strip()
	assert not subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT).strip()
	write(runtime/'execution-costs.json',dict(scope='Per-command real GNU time observations. Nested/controller observations overlap; no fictitious total CPU or task-wide RSS is inferred.',commands=costs))
	inventory = json.loads((ROOT/'docs/books/inventory.json').read_text())
	def binding(path): return dict(path=str(path),sha256=sha(path))
	result = dict(status='PARTIAL',completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),final_commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True,cwd=ROOT).strip(),final_tree=subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True,cwd=ROOT).strip(),gates={'G0':'PASS','G1':'PARTIAL','G2':'PARTIAL','G3':'PARTIAL','G4':'PARTIAL_FULL_SCOPE; ALL_25_AUTHORED_CASES_PASS','G5':'PASS','G6':'PASS_SCOPED_CURRENT_NONREGRESSION','G7':'PASS','G8':'PENDING_AFTER_ACTUAL_REPORT_PUBLICATION'},content={k:v for k,v in content.items() if k not in ('sources','outputs')},unreviewed_source_units=inventory['unreviewed_source_units'],source_units=len(inventory['source_files']),syntax_families=len(inventory['syntax_families']),products_manifest=binding(RUNTIME/'api-docs28a1-products.json'),toolchain=binding(RUNTIME/'selfhost27c-dev21/build-identity.json'),link=binding(RUNTIME/'selfhost27c-dev21/link.json'),regression_plans=binding(reg_dir/'plans.json'),receipts={name:binding(path) for name,path in {'entry':RUNTIME/'books28a2-entry/entry.json','native':native_dir/'result.json','regression_attempt':reg_dir/'result.json','schema_retry':docs_dir/'result.json','renderer':RUNTIME/'books28a2-render-tests-final2/result.json','visual':RUNTIME/'books28a2-visual.json','site':a.site/'BUILD.json'}.items()},rehashed_current_command_records=commands,rechecked_current_strict_memory_streams=strict,preserved_environment_failures=failures,physical_mutation_refusals=physical,preservation=preservation(RUNTIME/'selfhost27b-intake/pre-edit-preservation.json'),remaining=['Exhaustive implemented-rule/source/conformance review remains incomplete: 231 inventoried units have no direct chapter rule witness; declaration-line spans are representative, not whole rule proofs.','The parser-aligned grammar summary is not a complete independently qualified grammar across all 100 syntax families/policies.','Reference and Guide need deeper rule-specific conformance/teaching coverage for the remaining admitted generic, ownership, effect, ABI and profile combinations; representative controls do not establish both books COMPLETE.','Original C0 and 1044 historical proof records remain absent; 27-B PARTIAL and rebuilt C0 all-kinds process-memory NOT_PASS remain; provenance substitution is ACCEPTED WITH DISCLOSURE only.'],limitations=['First quick1 authoring attempt did not independently archive fixture bytes before failure; subsequent quick2 retained identical then-current sources, without retroactively creating an earlier witness.','Source-consumer executables are retained authenticated unchanged builds with their historical revision; their current strict execution is new evidence, not a new build.','Browser profiles/caches are observational state and excluded from transport; actual commands, DOM, controls and screenshots are retained.','G8 recipe is prepared but cannot have a prepublication PASS. No PDF, hardback, web deployment or release.'])
	result['source_consumers'] = owner_products
	result['receipts']['format'] = binding(RUNTIME/'books28a2-format-final2.json')
	write(runtime/'result.json',result)
	print('PARTIAL: native and rendering evidence qualified; exhaustive two-book coverage remains incomplete')


if __name__ == '__main__':
	main()
