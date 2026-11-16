#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Audit R1 execution bytes separately from still-open book acceptance duties."""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write
from audit import preservation
sys.path.insert(0,str(ROOT/'tools/docs'))
import books
import inventory


def load(path):
	return json.loads(Path(path).read_text())


def identity(path):
	return dict(path=str(path),sha256=sha(path))


def streams(bases):
	"""Rehash actual streams, then inspect every process memory summary."""
	commands = []; memory = []; costs = []
	for base in bases:
		for index in sorted(base.rglob('commands.json')):
			for row in load(index):
				label = row.get('label',row.get('name')); result = row.get('result',row)
				if 'stdout_sha256' not in result: continue
				assert not result.get('timed_out',False) and result['exit']==result.get('expected_exit',result.get('expected')),(index,label)
				for kind in ('stdout','stderr','time'):
					leaf = index.parent/label/('time.txt' if kind=='time' else kind)
					if not leaf.is_file(): leaf = index.parent/(label+('.time' if kind=='time' else '.'+kind))
					if not leaf.is_file(): leaf = index.parent/(label+'-controller')/('time.txt' if kind=='time' else kind)
					assert sha(leaf)==result[kind+'_sha256'],leaf
					data = leaf.read_bytes()
					if kind=='stderr' and b'Memcheck, a memory error detector' in data:
						errors = re.findall(rb'ERROR SUMMARY: ([0-9,]+) errors',data)
						live = re.findall(rb'in use at exit: ([0-9,]+) bytes in ([0-9,]+) blocks',data)
						assert errors and live and all(v==b'0' for v in errors) and all(a==b==b'0' for a,b in live),leaf
						assert b'(suppressed: 0 from 0)' in data,leaf
						memory.append(dict(path=str(leaf),sha256=sha(leaf),process_summaries=len(errors)))
					if kind=='time':
						fields = {}
						for line in data.decode().splitlines():
							if ': ' in line:
								key,value = line.strip().split(': ',1); fields[key] = value
						costs.append(dict(path=str(leaf),wall_seconds=result.get('seconds'),user_seconds=fields.get('User time (seconds)'),system_seconds=fields.get('System time (seconds)'),maximum_RSS_KiB=fields.get('Maximum resident set size (kbytes)'),role='May enclose child measurements; do not sum parent and child CPU'))
				commands.append(dict(index=str(index),label=label))
	return commands,memory,costs


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('native','grammar','limits','regression','render','browser','site','visual','format-receipt','runtime'): p.add_argument('--'+key,type=Path,required=True)
	p.add_argument('--allow-dirty',action='store_true',help='Engineering preflight only; does not qualify final preservation/delivery')
	a = p.parse_args()
	r = output_path(a.runtime,WORK/'runtime'); r.mkdir(parents=True,exist_ok=False)
	(r/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	stage = WORK/'runtime/native-current'
	entry = load(stage/'r1-authentication.json'); g8 = load(stage/'r1-predecessor-G8.json')
	assert entry['submission_sha256']=='9e78499c69071e6972bbe98d7f7dd7a886567f45b9fbfd50f89548f713e0cc0b'
	assert g8['status']=='INDEPENDENTLY_REAUTHENTICATED_AFTER_PUBLICATION_28A2_G8_PASS'
	assert g8['report_sha256']==entry['canonical_report_sha256']=='0d58b978a92d01f0ecdf6bfbcd0ff82423b0e5c0454920be05eed44655c2a01f'
	assert datetime.datetime.fromisoformat(g8['start_UTC'])>datetime.datetime.fromisoformat(g8['publication_UTC'])
	for key in ('main_receipt','supplement_receipt'): assert sha(g8[key]['path'])==g8[key]['sha256']
	prior = load(stage/'input/reference/report28a2/evidence/QUALIFICATION.json')
	for key in ('products_manifest','toolchain','link','regression_plans'): assert sha(prior[key]['path'])==prior[key]['sha256']
	tools = load(prior['toolchain']['path']); assert all(sha(path)==digest for path,digest in tools['tools'].items())
	for product in load(prior['products_manifest']['path'])['products'].values():
		for image in (product,product['native'],product['doc']): assert sha(image['path'])==image['sha256']
	native = load(a.native/'result.json')
	assert native['status']=='BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS' and native['full_manifest'] and len(native['cases'])==39
	for key in ('inputs','emit_products'): assert all(sha(path)==digest for path,digest in native[key].items())
	grammar = load(a.grammar/'result.json')
	assert grammar['status']=='CURRENT_PARSER_GOLDENS_AND_TYPED_SOURCE_O0_O2_PASS' and grammar['cases']==476 and grammar['protected_goldens']==125
	assert len(grammar['observed_families'])==96 and not grammar['unobserved_concrete_families']
	for name,row in load(a.grammar/'inputs.json').items(): assert sha(ROOT/name)==row['sha256']==sha(a.grammar/'inputs'/name)
	for product in load(a.grammar/'consumer-products.json').values():
		for key in ('object','executable'): assert sha(product[key]['path'])==product[key]['sha256']
	limits = load(a.limits/'result.json')
	assert limits['status']=='CURRENT_GENERIC_LAZY_CAPTURE_COMPREHENSION_AND_PARSER_BOUNDARIES_PASS' and len(load(a.limits/'cases.json'))==12
	for key in ('inputs','emit_products'): assert all(sha(path)==digest for path,digest in limits[key].items())
	reg = load(a.regression/'result.json'); plans = load(a.regression/'plans.json')
	assert reg['status']=='CURRENT_BOOK_NONREGRESSION_PASS' and len(reg['suites'])==29
	assert {v['label'] for v in reg['suites']}=={v['label'] for v in plans}
	assert all(v['result']['status']=='EXPECTED_OUTCOME' for v in reg['suites'])
	physical = 0
	for row in reg['suites']:
		if '-physical-' in row['label']:
			value = load(a.regression/row['label']/'result.json'); assert value['status']=='SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS'; physical += value['mutations']
	assert physical==46
	api = WORK/'build/books28a2-r1/regression-final1/O0-api-preview'
	for mode in ('O0','O2'):
		for group in ('library','compiler-source'): assert (api/(group+'.json')).read_bytes()==(api.parent/(mode+'-api-preview')/(group+'.json')).read_bytes()
	outputs,content = books.build(api/'library.json',api/'compiler-source.json')
	assert {str(path.relative_to(a.site)) for path in a.site.rglob('*') if path.is_file()}==set(outputs)
	assert all((a.site/name).read_bytes()==data for name,data in outputs.items())
	assert load(a.render/'result.json')['status']=='BOOK_RENDERER_HOSTILE_INPUT_AND_REPRODUCIBILITY_PASS'
	visual = load(a.visual); assert visual['status']=='BOOK_DESKTOP_MOBILE_KEYBOARD_AND_PRINT_VISUALLY_REVIEWED'
	assert all(sha(path)==digest for path,digest in visual['screenshots'].items())
	assert all(sha(a.site/name)==digest for name,digest in visual['HTML'].items())
	formatted = load(a.format_receipt); assert not formatted['applied'] and formatted['changed']==0,formatted
	assert all(row['state'] in ('compliant','protected') and row['before_sha256']==row['after_sha256'] for row in formatted['rows'])
	for base,name in ((a.native,'run.py'),(a.grammar,'grammar.py'),(a.limits,'limits.py'),(a.regression,'regression.py')):
		assert (base/'executed-recipe.py.txt').read_bytes()==(ROOT/'tests/books'/name).read_bytes(),name
	for name,value in inventory.products().items(): assert load(ROOT/'docs/books'/name)==value
	inv = load(ROOT/'docs/books/inventory.json'); assert len(inv['source_files'])==269 and inv['role_classified_units']==269 and len(inv['syntax_families'])==100
	assert all(row['git_blob']==subprocess.check_output(['git','rev-parse',entry['head']+':'+row['path']],cwd=ROOT,text=True).strip() for row in inv['source_files'])
	protected = preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json'); assert protected==entry['preservation']
	assert not subprocess.check_output(['git','diff',entry['head'],'--','compiler','lib'],cwd=ROOT).strip()
	dirty = subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT).decode()
	assert a.allow_dirty or not dirty,dirty
	commands,memory,costs = streams([a.native,a.grammar,a.limits,a.regression,a.browser])
	write(r/'execution-costs.json',dict(commands=costs,scope='Actual GNU time per command. Parent and child CPU overlap; RSS is per measured process tree. No invented summed CPU or peak task RSS. Outer task controller time files are retained separately.'))
	head = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
	tree = subprocess.check_output(['git','rev-parse','HEAD^{tree}'],cwd=ROOT,text=True).strip()
	write(r/'QUALIFICATION.json',dict(format='astra-book-completion-qualification/1',status='PARTIAL',audited_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),final_commit=head,final_tree=tree,tracked_status=dirty,final_preservation_qualified=not dirty,submission_sha256=entry['submission_sha256'],predecessor_G8=identity(stage/'r1-predecessor-G8.json'),entry_authentication=identity(stage/'r1-authentication.json'),products_manifest=prior['products_manifest'],toolchain=prior['toolchain'],link=prior['link'],regression_plans=identity(a.regression/'plans.json'),native=identity(a.native/'result.json'),grammar=identity(a.grammar/'result.json'),limits=identity(a.limits/'result.json'),regression=identity(a.regression/'result.json'),source_consumers=prior['source_consumers'],site=identity(a.site/'BUILD.json'),visual=identity(a.visual),format_receipt=identity(a.format_receipt),content=content,source_coverage=dict(units=269,classified=269,syntax_families=100,typed_families_observed=96,abstract_families=4,rules=66,units_without_direct_rule_witness=inv['unreviewed_source_units'],exhaustive_semantic_conformance='OPEN'),actual_command_records=len(commands),strict_memory_streams=memory,physical_mutation_refusals=physical,preservation=protected,gates=dict(G0='PASS',G1='PARTIAL',G2='PARTIAL',G3='PARTIAL',G4='PARTIAL_FULL_SCOPE; EXECUTED_AUTHORED_CASES_PASS',G5='PASS_SCOPED_OFFLINE_PRODUCT',G6='PASS_SCOPED_CURRENT_REGRESSION',G7='PASS' if not dirty else 'PREFLIGHT_ONLY',G8='PENDING_ACTUAL_LATER_PUBLICATION'),history='Original 28-A2 and 27B PARTIAL unchanged; original C0 and 1044 proofs absent; rebuilt C0 provenance ACCEPTED_WITH_DISCLOSURE; strict C0 process memory NOT_PASS, no safety waiver.',remaining_obligations='Rule-specific semantic review and positive/negative witnesses for all applicable authoritative units; full foreign-policy/profile and ambiguity grammar qualification; deeper teaching and conformance across the original implemented language. Classified files and observed syntax families do not close these duties.'))
	print('R1 audit:',len(commands),'command records,',len(memory),'strict streams; original full books acceptance remains PARTIAL')


if __name__ == '__main__':
	main()
