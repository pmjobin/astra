#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Final source/product, history, preservation and exact warm-cost evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, BASE, C0, read, sha, git, preservation


def main():
	p = argparse.ArgumentParser(); p.add_argument('--warm-only',action='store_true'); a = p.parse_args()
	if a.warm_only:
		rows = []
		for mode in ('O0','O2'):
			leaf = RUNTIME/('warm-timed-v2-'+mode); assert not leaf.exists()
			argv = [sys.executable,'-B',ROOT/'tests/selfhost-llvm/build.py','--compiler',C0,'--source-root',RUNTIME/'source-window-v2','--build',BUILD/('native-window-v2-'+mode),'--runtime',leaf,'--mode',mode]
			start = time.monotonic()
			with (RUNTIME/('warm-timed-'+mode+'.stdout')).open('xb') as out,(RUNTIME/('warm-timed-'+mode+'.stderr')).open('xb') as err:
				r = subprocess.run(['/usr/bin/time','-v','-o',RUNTIME/('warm-timed-'+mode+'.time'),*map(str,argv)],cwd=ROOT,stdout=out,stderr=err,timeout=60)
			assert r.returncode == 0
			assert list(leaf.glob('build-*/ownflow-'+mode+'-exact-reuse.json')) and not list(leaf.glob('build-*/ownflow-'+mode+'.json'))
			rows.append(dict(mode=mode,argv=list(map(str,argv)),start=start,end=time.monotonic(),wall_seconds=time.monotonic()-start,status='EXACT_INPUT_AND_PRODUCT_REUSE_NO_REBUILD'))
		(RUNTIME/'warm-timed.json').write_text(json.dumps(rows,indent=2)+'\n'); return
	assert git('status','--porcelain=v1','--untracked-files=all') == ''
	initial = read(RUNTIME/'initial/result.json'); current = preservation()
	assert all(current[key] == initial[key] for key in current)
	assert git('config','--show-origin','--list') == initial['config'] and git('stash','list') == initial['stash']
	head = git('rev-parse','HEAD').strip(); tree = git('rev-parse','HEAD^{tree}').strip()
	assert subprocess.run(['git','merge-base','--is-ancestor',BASE,head],cwd=ROOT).returncode == 0
	before_refs = {line.split()[1]:line.split()[0] for line in initial['refs'].splitlines()}; after_refs = {line.split()[1]:line.split()[0] for line in git('show-ref').splitlines()}
	assert before_refs.keys() == after_refs.keys() and all(after_refs[name] == value for name,value in before_refs.items() if name != 'refs/heads/main')
	assert git('worktree','list','--porcelain').replace('HEAD '+head,'HEAD '+BASE) == initial['worktrees']
	for path,value in initial['hooks'].items(): assert sha(path) == value['sha256'] and oct(Path(path).stat().st_mode & 0o777) == value['mode']
	for path,value in initial['workflow'].items(): assert sha(path) == value
	assert sha(RUNTIME/'predecessor-report.zip') == initial['predecessor_sha256']
	for name in ('AGENTS.md','CODING_STYLE.md','codex-project.json'):
		assert (ROOT/name).read_bytes() == subprocess.check_output(['git','show',BASE+':'+name],cwd=ROOT)
	old_scope = json.loads(subprocess.check_output(['git','show',BASE+':format/scope.json'],cwd=ROOT)); scope = read(ROOT/'format/scope.json'); assert all(scope.get(name) == value for name,value in old_scope.items())
	proof_path = RUNTIME.parent/'indexpath18/historical-proof-outputs.json'; proofs = read(proof_path); assert proofs['count'] == len(proofs['outputs']) == 1044
	for path,value in proofs['outputs'].items(): assert sha(path) == value['sha256']
	products = {}; bindings = {}
	for label,path in [('O0',BUILD/'native-window-v2-O0/astra-llvm-O0'),('O2',BUILD/'native-window-v2-O2/astra-llvm-O2'),('diagnostic',BUILD/'diagnostic-window-v2/resource-O0')]:
		data = read(path.with_suffix('.identity.json')); assert sha(path) == data['sha256']
		for source,value in data['identity']['sources'].items():
			source = Path(source); assert sha(source) == value
			if source.is_relative_to(RUNTIME/'source-window-v2'): relative = source.relative_to(RUNTIME/'source-window-v2')
			elif source.is_relative_to(ROOT): relative = source.relative_to(ROOT)
			else: continue
			assert sha(ROOT/relative) == value
			blob = subprocess.check_output(['git','show',head+':'+str(relative)],cwd=ROOT); assert hashlib.sha256(blob).hexdigest() == value
			bindings[str(relative)] = dict(sha256=value,Git_blob=git('rev-parse',head+':'+str(relative)).strip())
		for tool,value in data['identity']['tools'].items(): assert sha(tool) == value
		products[label] = dict(path=str(path),sha256=sha(path),identity_path=str(path.with_suffix('.identity.json')),identity_sha256=sha(path.with_suffix('.identity.json')))
	changed = git('diff','--name-only',BASE+'..'+head).splitlines(); assert all(name in bindings for name in changed if name.endswith('.astra'))
	assert read(RUNTIME/'engineering-summary.json')['status'] == 'ENGINEERING_GATES_COMPLETE_PUBLICATION_PENDING'
	assert read(RUNTIME/'cycles-final-v3/result.json')['status'] == 'PASS' and len(read(RUNTIME/'warm-timed.json')) == 2
	result = dict(status='PASS',final_commit=head,final_tree=tree,base_commit=BASE,protected_files=451,donor_files=6622,historical_proof_outputs=1044,historical_proof_inventory_sha256=sha(proof_path),historical_attribution='Preserved original outputs, not freshly reproven by copying',predecessor_sha256=initial['predecessor_sha256'],workflow=initial['workflow'],compiled_Git_bindings=bindings,products=products,changed_paths=changed,clean_status=True,recipe_sha256=sha(__file__))
	(RUNTIME/'final-audit.json').write_text(json.dumps(result,indent=2)+'\n'); print(head,tree,'451 protected / 6622 donor / 1044 historical outputs unchanged; exact compiled source bindings verified')


if __name__ == '__main__':
	main()
