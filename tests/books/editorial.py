#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent final audit of the full Guide campaign; historical gates stay historical."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
BASE = '5f3e8bd4e7b4ceaa38c0bddc18fc32bf17d94cdf'
TREE = '9bfebde601c5c20f4c72520ed1f89fbae454b6fe'
SUBMISSION = '37e25c2d36def85d5b2aefe38f953b539d191071e031caa19dd7f408afa9a9f7'
PREDECESSOR = '432b1caab2fcf585bd1953d32ef6a6729b0ef3216ad4fb742e4175dceaac3a28'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write
from audit import preservation
sys.path.insert(0,str(ROOT/'tools/docs'))
import books
from completion import streams


def load(path):
	return json.loads(Path(path).read_text())


def binding(path):
	return dict(path=str(path),sha256=sha(path))


def git(*args):
	return subprocess.check_output(['git',*args],cwd=ROOT)


def command(directory, label, expected):
	leaf = directory/label
	r = load(leaf/'result.json')
	assert r['status'] == 'EXPECTED_OUTCOME' and r['exit'] == r['expected_exit'] == expected and not r['timed_out'],leaf
	for kind in ('stdout','stderr','time'):
		assert sha(leaf/('time.txt' if kind == 'time' else kind)) == r[kind+'_sha256'],leaf
	return (leaf/'stdout').read_bytes(),(leaf/'stderr').read_bytes()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('entry','regression','tutorial','render','browser','visual','site','format-receipt','usage','runtime'):
		p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--native',type=Path,action='append',required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime,WORK/'runtime')
	assert not runtime.exists()
	entry = load(a.entry/'entry.json')
	assert entry['head'] == BASE and entry['tree'] == TREE
	assert entry['status'] == '? tests/selfhost-compiler-complete/run.py\n'
	intake = load(WORK/'runtime/native-current/pm-next-intake.json')
	assert intake['base_commit'] == BASE and intake['submission_sha256'] == SUBMISSION and not intake['published']
	archive = Path(intake['submission_path'])
	assert archive.stat().st_size == 84617238 and sha(archive) == SUBMISSION
	with zipfile.ZipFile(archive) as z:
		manifest = load(a.entry/'MANIFEST.json')
		assert manifest == json.loads(z.read('MANIFEST.json'))
		assert set(z.namelist()) == {'MANIFEST.json'} | {row['path'] for row in manifest['files']}
		for row in manifest['files']:
			data = z.read(row['path'])
			assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		for row in json.loads(z.read('SOURCE-WITNESSES.json'))['source_witnesses']:
			data = git('show',BASE+':'+row['path'])
			assert data == z.read(row['readonly_path'])
			assert git('rev-parse',BASE+':'+row['path']).decode().strip() == row['git_blob']
		owner_note = 'reference/owner/ASTRA-RELEASE-OWNER-C0-DISPOSITION-2026-11-15.md'
		owner_decision = 'docs/decisions/0170-rebuilt-c0-release-provenance.md'
		assert hashlib.sha256(z.read(owner_note)).hexdigest() == '90e82d0007a5494b46779fecbe0738b01bac3543688e5bb97cd1720ce7f1410b'
		assert (ROOT/owner_decision).read_bytes() == git('show',BASE+':'+owner_decision)
		assert sha(ROOT/owner_decision) == '52837e56c3cb2a8593248f5708768aed0602e5d96bb9ab987bf81346f0703ee1'
		# The supplied authorization and the repository's implementation record are
		# distinct artifacts. Both preserve provenance acceptance and memory NOT_PASS.
	prior_intake = load(a.entry/'R2-pm-next-intake.json')
	assert prior_intake['published'] and prior_intake['report_sha256'] == PREDECESSOR
	assert prior_intake['final_commit'] == BASE and prior_intake['final_tree'] == TREE
	canonical = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert sha(canonical) == PREDECESSOR,'this prepublication audit expects the genuine R2 canonical report'
	with zipfile.ZipFile(canonical) as z:
		q = json.loads(z.read('evidence/QUALIFICATION.json'))
		assert all(q['gates'][key].startswith('PASS') for key in ('P0','P1','P2','P3','P4','P5','P6'))
		assert q['gates']['P7'] == 'PENDING_INSTALLED_PUBLISHER_NOT_PRECLAIMED'
		assert json.loads(z.read('RESULT.json'))['final_commit'] == BASE

	manifest = load(ROOT/'tests/books/examples.json')
	old = json.loads(git('show',BASE+':tests/books/examples.json'))
	assert len(old['cases']) == 46 and len(old['files']) == 49
	assert manifest['cases'][:46] == old['cases'] and manifest['files'][:49] == old['files']
	assert len(manifest['cases']) == 63 and len(manifest['files']) == 66
	for row in old['files']:
		assert (ROOT/row['path']).read_bytes() == git('show',BASE+':'+row['path'])
	for name in ('values.md','records.md','EDITORIAL-PLAN.md','EDITORIAL-REVIEW.md'):
		assert (ROOT/'docs/guide'/name).read_bytes() == git('show',BASE+':docs/guide/'+name)
	chapter_rows = [r for r in load(ROOT/'docs/chapters.json')['chapters'] if r.get('book') == 'guide']
	assert [r['source'] for r in chapter_rows] == ['guide/'+n+'.md' for n in ('README','getting-started','values','records','objects','text-errors','sequences','generics-match','ffi','application','tooling','profiles','glossary')]
	assert [r['number'] for r in chapter_rows] == list(range(13))
	manuscript = {'docs/'+r['source']:sha(ROOT/'docs'/r['source']) for r in chapter_rows}
	for plan in a.entry.glob('native-plan-*.json'):
		assert load(plan)['manuscript'] == manuscript,'manuscript changed during final qualification'

	case_roots = {}
	for base in a.native:
		native = load(base/'result.json')
		assert native['status'] == 'BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS'
		assert native['manifest_case_count'] == len(manifest['cases'])
		assert (base/'executed-recipe.py.txt').read_bytes() == (ROOT/'tests/books/run.py').read_bytes()
		assert sha(base/'commands.json') == native['commands_sha256']
		for group in ('inputs','emit_products'):
			assert all(sha(path) == digest for path,digest in native[group].items()),group
		assert set(native['input_witnesses']) == set(native['inputs'])
		for path,witness in native['input_witnesses'].items():
			assert sha(base/witness) == native['inputs'][path]
		for row in native['cases']:
			assert row['status'] == 'EXPECTED_OUTCOMES_PASS' and row['id'] not in case_roots
			case_roots[row['id']] = (base,native)
	assert set(case_roots) == {row['id'] for row in manifest['cases']}
	for case in manifest['cases']:
		base,native = case_roots[case['id']]
		build = Path(native['build'])
		for host in ('O0','O2'):
			for target in ('O0','O2'):
				label = case['id']+'-'+host+'-'+target
				if case['mode'] == 'compile_fail':
					out,err = command(base,label+'-reject',1)
					assert out == b'' and case['diagnostic'].lower().encode() in err.lower()
					assert (build/(label+'.o')).read_bytes() == b'BOOK_NEGATIVE_OUTPUT_SENTINEL\n'
					out,err = command(base,label+'-reject-absent',1)
					assert out == b'' and err.decode() == native['diagnostics'][case['id']]
					assert not (build/(label+'-absent.o')).exists()
					continue
				command(base,label+'-compile',0)
				command(base,label+'-IR',0)
				command(base,label+'-verify',0)
				if case['mode'] != 'run': continue
				out,err = command(base,label+'-plain-execute',case['exit'])
				assert out == case.get('stdout','').encode() and err == case.get('stderr','').encode()
				out,_ = command(base,label+'-execute',case['exit'])
				assert out == case.get('stdout','').encode()
				if case.get('data'):
					for number in range(2):
						assert command(base,label+'-plain-input-refusal-'+str(number),64) == (b'',b'')
						assert command(base,label+'-input-refusal-'+str(number),64)[0] == b''
				for number,row in enumerate(case.get('extra_runs',[])):
					assert command(base,label+'-plain-extra-'+str(number),row['exit']) == (row['stdout'].encode(),row['stderr'].encode())
					assert command(base,label+'-extra-'+str(number),row['exit'])[0] == row['stdout'].encode()
				if case.get('freestanding'):
					assert command(base,label+'-static-execute',case['exit'])[0] == b''
					assert command(base,label+'-undefined',0)[0] == b''
					assert b'INTERP' not in command(base,label+'-segments',0)[0]

	reg = load(a.regression/'result.json')
	assert reg['status'] == 'CURRENT_BOOK_NONREGRESSION_PASS' and len(reg['suites']) == 29
	assert reg['qualification_sha256'] == sha(a.entry/'R1-bound-regression-qualification.json') == 'b4ea36e0a8a497468d5062626c38fb2f6df2133508593ec46c85b175c45bbcf4'
	prior = load(a.entry/'R1-bound-regression-qualification.json')
	for name in ('products_manifest','toolchain','link','regression_plans'):
		assert sha(prior[name]['path']) == prior[name]['sha256']
	assert all(sha(path) == digest for path,digest in load(prior['toolchain']['path'])['tools'].items())
	assert all(sha(path) == digest for path,digest in load(prior['link']['path'])['objects'].items())
	qualified_products = load(prior['products_manifest']['path'])['products']
	for product in qualified_products.values():
		for image in (product,product['native'],product['doc']):
			assert sha(image['path']) == image['sha256']
	assert all(load(base/'result.json')['products'] == qualified_products and load(base/'result.json')['LLVM'] == '23.1.4' for base in a.native)
	assert all(sha(row['path']) == row['sha256'] for row in prior['source_consumers'].values())
	plans = load(a.regression/'plans.json')
	assert sha(a.regression/'plans.json') == reg['plans_sha256'] and sha(a.regression/'commands.json') == reg['commands_sha256']
	assert {r['label'] for r in plans} == {r['label'] for r in load(prior['regression_plans']['path'])}
	assert all(r['result']['status'] == 'EXPECTED_OUTCOME' for r in reg['suites'])
	assert (a.regression/'executed-recipe.py.txt').read_bytes() == (ROOT/'tests/books/regression.py').read_bytes()
	statuses = {
		**{name:'SELECTED_EXPRESSIVE_NATIVE_AND_MEMORY_PASS' for name in ('named','match','range','format','collection')},
		'ownership':'SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS',
		'intrinsic':'SELECTED_INTRINSIC_ABI_NATIVE_GATES_PASS',
		'C-client':'EXISTING_C_TO_ASTRA_STRING_DESCRIPTOR_CLIENT_PASS',
		**{name:'SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS' for name in ('physical-owner','physical-range','physical-enum')},
		'docs-native':'CURRENT_COMPLETE_COMPILER_DOCS_ISOLATION_AND_COMMENT_EQUIVALENCE_PASS',
		'docs-focused':'FOCUSED_NATIVE_DOCS_ACCEPTANCE_PASS',
		'api-preview':'CURRENT_COMPILER_REAL_API_PREVIEWS_PASS',
	}
	for suite in reg['suites']:
		label = suite['label']
		if label.endswith('-source-owner-memory'):
			command(a.regression,label+'-controller',42)
			continue
		base = a.regression/label; result = load(base/'result.json')
		kind = label if label == 'docs-native' else label[3:]
		assert result['status'] == statuses[kind] and not result.get('oracle_only',False),label
		for name in ('identity','commands','inputs'):
			if name+'_sha256' in result:
				assert sha(base/(name+'.json')) == result[name+'_sha256'],label
		if 'identity_sha256' in result:
			identity = load(base/'identity.json')
			for group in ('inputs','providers','tools'):
				assert all(sha(path) == digest for path,digest in identity.get(group,{}).items()),(label,group)
		if kind == 'C-client':
			assert {row['profile'] for row in result['profiles']} == {'O0','O2'}
			assert all(row['positive'] == 42 and row['empty'] == 1 and row['strict_returning_target_memory_streams'] == 2 for row in result['profiles'])
		if kind == 'ownership':
			assert load(base/'inputs.json') == result['source_inputs']
			assert all(sha(path) == digest for path,digest in result['source_inputs'].items())
	physical = 0
	for suite in reg['suites']:
		if '-physical-' not in suite['label']: continue
		base = a.regression/suite['label']; result = load(base/'result.json')
		assert result['status'] == 'SELECTED_INDEPENDENT_PHYSICAL_MUTATIONS_PASS'
		assert sha(base/'identity.json') == result['identity_sha256'] and sha(base/'observations.json') == result['observations_sha256']
		for group in ('inputs','tools'):
			assert all(sha(path) == digest for path,digest in load(base/'identity.json')[group].items())
		for row in load(base/'observations.json'):
			observation = row['observations']; control = row['action'].endswith('control')
			assert sha(base/row['name']/'mutate.gdb') == row['script_sha256']
			for kind in ('mutation','structural-return','inferior-exit'):
				assert load(base/row['name']/(kind+'.json')) == observation[kind]
			assert observation['structural-return']['returned'] == 0
			assert observation['inferior-exit']['exit'] == int(not control)
			for kind in ('stdout','stderr','time'):
				assert sha(base/row['name']/'execution'/('time.txt' if kind == 'time' else kind)) == row['execution'][kind+'_sha256']
		physical += result['mutations']
	assert physical == 46

	api = a.site.parent/'regression-final1/O0-api-preview'
	for group in ('library','compiler-source'):
		assert (api/(group+'.json')).read_bytes() == (api.parent/'O2-api-preview'/(group+'.json')).read_bytes()
	outputs,content = books.build(api/'library.json',api/'compiler-source.json')
	assert outputs == books.build(api/'library.json',api/'compiler-source.json')[0]
	assert {str(p.relative_to(a.site)) for p in a.site.rglob('*') if p.is_file()} == set(outputs)
	assert all((a.site/name).read_bytes() == data for name,data in outputs.items())
	assert all(b'/home/pmjobin' not in data for name,data in outputs.items() if name.endswith(('.html','.json')))
	for row in manifest['files']:
		assert outputs['sources/'+row['path']+'.txt'] == (ROOT/row['path']).read_bytes()
	render = load(a.render/'result.json')
	assert render['status'] == 'BOOK_RENDERER_HOSTILE_INPUT_AND_REPRODUCIBILITY_PASS' and len(render['checks']) == 18
	assert render['renderer_sha256'] == sha(ROOT/'tools/docs/books.py') and render['stylesheet_sha256'] == sha(ROOT/'tools/docs/books.css')
	browser = load(a.browser/'result.json'); visual = load(a.visual)
	assert browser['status'] == 'BOOK_BROWSER_EXECUTED_PENDING_VISUAL_INSPECTION'
	assert len(browser['keyboard_and_print']['chapterChecks']) == 13
	assert visual['status'] == 'VISUALLY_INSPECTED' and visual['screenshots'] == browser['screenshots']
	assert len(visual['screenshots']) == 17 and all(sha(path) == digest for path,digest in visual['screenshots'].items())
	assert all(sha(a.site/path) == digest for path,digest in visual['HTML'].items())
	tutorial = load(a.tutorial/'result.json')
	assert tutorial['status'] == 'ACTUAL_PUBLISHED_TUTORIAL_COMMANDS_AND_SETUP_REFUSALS_PASS' and len(tutorial['blocks']) == 46
	assert all(sha(path) == digest for path,digest in tutorial['sources'].items())
	assert all(sha(path) == digest for path,digest in tutorial['products'].items())
	for key,path in {'expectations':ROOT/'tests/books/tutorial.json','helper':ROOT/'tests/books/environment.py','recipe':ROOT/'tests/books/tutorial.py','script':a.tutorial/'tutorial.sh','commands':a.tutorial/'commands.json','observed':a.tutorial/'observed.json'}.items():
		assert tutorial[key+'_sha256'] == sha(path)
	for name,row in load(a.tutorial/'observed.json').items():
		base = a.tutorial/'blocks'/name
		for kind in ('source','stdout','stderr'):
			assert sha(base/('source.sh' if kind == 'source' else kind)) == row[kind+'_sha256']

	commands,memory,costs = streams([*a.native,a.regression,a.tutorial,a.browser])
	assert memory
	for row in memory:
		data = Path(row['path']).read_bytes()
		pids = set(re.findall(rb'^==([0-9]+)== Memcheck,',data,re.M)); assert pids
		for pid in pids:
			lines = b'\n'.join(line for line in data.splitlines() if line.startswith(b'=='+pid+b'=='))
			assert b'ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)' in lines
			assert b'in use at exit: 0 bytes in 0 blocks' in lines
	for base in (*a.native,a.regression,a.tutorial):
		for index in base.rglob('commands.json'):
			for row in load(index):
				argv = row.get('argv',[])
				if argv and Path(str(argv[0])).name == 'valgrind':
					assert {'--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all'} <= set(argv)
	formatted = load(a.format_receipt)
	assert formatted['changed'] == 0
	assert all(row['state'] == 'compliant' and row['before_sha256'] == row['after_sha256'] == sha(ROOT/row['path']) for row in formatted['rows'])
	preserved = preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json')
	assert preserved == entry['preservation']
	for path in ('compiler','bootstrap','lib','docs/reference','docs/books','tools/format','format/toolchain.json','AGENTS.md','CODING_STYLE.md','codex-project.json'):
		assert not git('diff',BASE,'--',path),path
	assert not git('status','--porcelain','--untracked-files=no').strip()
	assert git('ls-files','--others','--exclude-standard').decode().splitlines() == ['tests/selfhost-compiler-complete/run.py']
	head = git('rev-parse','HEAD').decode().strip(); tree = git('rev-parse','HEAD^{tree}').decode().strip()
	assert subprocess.run(['git','merge-base','--is-ancestor',BASE,head],cwd=ROOT).returncode == 0
	paths = git('diff','--name-only',BASE,head).decode().splitlines()
	assert all(path.startswith(('docs/guide/','tests/books/')) or path in ('docs/chapters.json','format/scope.json','tools/docs/books.py') for path in paths)
	scope = load(ROOT/'format/scope.json')
	assert {row['path'] for row in formatted['rows']} == {path for path in paths if path in scope and 'lane' in scope[path]}
	assert sha(ROOT/'tests/books/editorial.py') == sha(Path(__file__))
	usage = load(a.usage)
	assert usage['model'] == {'model':'gpt-6-astra','effort':'max'}
	review = ROOT/'docs/guide/EDITORIAL-R3-REVIEW.md'
	assert review.is_file() and (ROOT/'docs/guide/EDITORIAL-R3-PLAN.md').is_file()
	runtime.mkdir(parents=True)
	write(runtime/'execution-costs.json',dict(scope='Actual individual command GNU time wall/CPU/RSS. Controllers and children overlap; no summed task CPU/RSS or billing estimate.',commands=costs))
	result = dict(format='astra-full-guide-editorial/1',status='PASS',scope='Entire reader-first Guide only; formal 28-A2-R1 remains PARTIAL.',audited_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),initial_head=BASE,initial_tree=TREE,final_head=head,final_tree=tree,submission_sha256=SUBMISSION,gates={'B0':'PASS_EXACT_INTAKE_AND_GENUINE_R2_P7','B1':'PASS_ALL_13_ENTRIES_EDITORIALLY_REVIEWED','B2':'PASS_CONTINUOUS_READINGS_AND_COMPLETE_APPLICATION','B3':'PASS_SOURCE_FIXTURE_CROSSCHECK_AND_TESTED_ANSWERS','B4':'PASS_FULL_NATIVE_MATRIX_AND_ALL_PUBLISHED_COMMANDS','B5':'PASS_CURRENT_ABI_OWNERS_PHYSICAL_MUTATIONS_STRICT_MEMORY','B6':'PASS_DETERMINISTIC_LOCAL_BOOKS_AND_ACTUAL_BROWSER_INSPECTION','B7':'PASS_CRITICAL_SELF_REVIEW_NOT_A_NOVICE_STUDY','B8':'PASS_PRESERVATION_AND_OBSERVED_MODEL_COUNTERS','B9':'PENDING_INSTALLED_PUBLISHER_NOT_PRECLAIMED'},source_files={path:dict(sha256=sha(ROOT/path),git_blob=git('rev-parse',head+':'+path).decode().strip()) for path in paths},manuscript=manuscript,book_cases=len(manifest['cases']),case_profiles=4*len(manifest['cases']),regression_suites=29,physical_mutations=physical,command_records=len(commands),strict_memory_streams=memory,local_links=content['local_links'],native=[binding(base/'result.json') for base in a.native],regression=binding(a.regression/'result.json'),tutorial=binding(a.tutorial/'result.json'),renderer=binding(a.render/'result.json'),browser=binding(a.browser/'result.json'),visual=binding(a.visual),site=binding(a.site/'BUILD.json'),format_receipt=binding(a.format_receipt),model_usage=binding(a.usage),review=binding(review),audit_recipe=binding(Path(__file__)),preservation=preserved,publication_model='Installed canonical publisher supplies B9. No additional installed G8 is required. Historical R1 G8 was already executed during R2 intake; its immutable prepublication record is not rewritten.',history='Unlaunched two-chapter R3 superseded without execution. Formal R1 G1-G4/222 source witnesses remain open. Original C0/1044 raw files lost; rebuilt C0 ACCEPTED_WITH_DISCLOSURE; historical strict all-kinds C0 memory NOT_PASS. No compiler/ABI/LLVM change, release, push/tag, deployment or PDF.')
	write(runtime/'QUALIFICATION.json',result)
	print(json.dumps(dict(status=result['status'],case_profiles=result['case_profiles'],command_records=len(commands),strict_memory_streams=len(memory),physical_mutations=physical,local_links=content['local_links'],publication=result['gates']['B9'])))


if __name__ == '__main__':
	main()
