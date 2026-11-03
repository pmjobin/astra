#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only preservation/tool/source audit, with task-private receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import stat
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
WORK = Path.home()/'Workspace/codex/work/astra'
RUNTIME = WORK/'runtime/llvm12'
BASE = '36006923b2cfb5187769e86b38b3ccd5cd58d681'
TREE = '71d756587479d7caf9bc7920349f8a6e0052f0f3'
ZIP = Path.home()/'Workspace/codex/submissions/ASTRA-SELFHOST-LLVM-12-SUBMISSION.zip'
SUBMISSION = '0c122cc588ee1c357d2da4200ff0f42c5900f029a5259add8c157cbaff45064f'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def call(*argv):
	return subprocess.check_output(argv,cwd=ROOT,text=True).strip()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--name',default='audit')
	a = p.parse_args()
	initial = json.loads((RUNTIME/'initial.json').read_text())
	assert ZIP.stat().st_size == 24010 and sha(ZIP) == SUBMISSION
	sys.path.insert(0,str(Path.home()/'.agents/skills/pm-next/scripts'))
	from common import verify_zip
	manifest,digest = verify_zip(ZIP)
	assert set(manifest) == {'format','kind','project_id','milestone_id','base_commit','supersedes','entrypoint','files'}
	assert manifest['format'] == 'pm-codex-submission/1' and manifest['kind'] == 'milestone' and manifest['project_id'] == 'astra' and manifest['milestone_id'] == 'ASTRA-SELFHOST-LLVM-12'
	assert manifest['base_commit'] == BASE and manifest['supersedes'] == [] and manifest['entrypoint'] == 'TASK.md'
	with zipfile.ZipFile(ZIP) as z:
		assert all(stat.S_ISREG(i.external_attr>>16) for i in z.infolist())
		assert json.loads(z.read('PROVENANCE.json'))['required_base_tree'] == TREE
	assert call('git','rev-parse',BASE+'^{tree}') == TREE
	assert call('git','merge-base','--is-ancestor',BASE,'HEAD') == ''
	assert json.loads((ROOT/'codex-project.json').read_text()) == dict(project_id='astra',workflow_format=1)
	assert sha(initial['predecessor_path']) == initial['predecessor_sha256'] == 'c5a004c40c72b48c90451d296e15141c86277dd2f7fe1506eac113238edfc001'
	for path,item in initial['protected'].items():
		file = ROOT/path
		assert sha(file) == item['sha256'] and stat.S_IMODE(file.stat().st_mode) == item['mode'],path
	reconciled = []
	reconciliation = RUNTIME/'local-reconciliation.json'
	observed = json.loads(reconciliation.read_text()) if reconciliation.exists() else {}
	for path,item in initial['local'].items():
		file = Path(path)
		assert stat.S_IMODE(file.stat().st_mode) == item['mode'],path
		if sha(file) != item['sha256']:
			# initial.local was explicitly inherited from SSA-11; a global setting
			# changed before this task. Preserve both identities, never edit history.
			assert file == Path.home()/'.codex/config.toml',path
			assert file.stat().st_ctime < (RUNTIME/'initial.json').stat().st_mtime
			row = dict(path=path,historical_sha256=item['sha256'],current_sha256=sha(file),ctime=file.stat().st_ctime,mtime=file.stat().st_mtime,intake_mtime=(RUNTIME/'initial.json').stat().st_mtime,explanation='Pre-existing global configuration difference; inode change time predates this task intake. Project Git/config/AGENTS pins match; no configuration write performed by the task.')
			if observed:
				assert observed[path] == row
			reconciled.append(row)
	if not observed and reconciled:
		reconciliation.write_text(json.dumps({row['path']:row for row in reconciled},indent=2)+'\n')
	for path,digest in initial['skill'].items():
		assert sha(path) == digest,path
	donor = Path(initial['donor']['root'])
	assert call('git','-C',str(donor),'rev-parse','HEAD') == initial['donor']['head'] == '61d1529956369770fc817563a43b0038b852ab90'
	assert all(sha(donor/path) == digest for path,digest in initial['donor']['files'].items())
	source_authority = json.loads((WORK/'runtime/ssa11/c0-source-authority.json').read_text())
	for path,item in source_authority['source'].items():
		assert sha(ROOT/path) == item['sha256'],path
	assert sha(initial['c0']['path']) == initial['c0']['sha256']
	changed = set(call('git','diff','--name-only',BASE).splitlines())
	assert all(sha(ROOT/path) == digest for path,digest in initial['repository']['files'].items() if path not in changed)
	tools = {}
	for name,argv in [('C0',[initial['c0']['path'],'--version']),('LLVM',['llvm-config','--version']),('LLVM target',['llvm-config','--host-target']),('LLVM library',['llvm-config','--libfiles']),('linker',['ld','--version']),('GCC',['gcc','--version']),('sysroot',['gcc','-print-sysroot']),('Valgrind',['valgrind','--version']),('opt',['opt','--version']),('llvm-as',['llvm-as','--version']),('C0 target',[initial['c0']['path'],'--target-info'])]:
		r = subprocess.run(argv,capture_output=True,text=True)
		tools[name] = dict(argv=argv,exit=r.returncode,stdout=r.stdout,stderr=r.stderr)
		assert r.returncode == 0,(name,r.stderr)
	result = dict(status='PASS',base_commit=BASE,base_tree=TREE,submission_sha256=sha(ZIP),submission_bytes=ZIP.stat().st_size,indexed_payloads=len(manifest['files']),zip_members=len(manifest['files'])+1,head=call('git','rev-parse','HEAD'),tree=call('git','rev-parse','HEAD^{tree}'),status_porcelain=call('git','status','--porcelain=v1'),source_authority_sha256=sha(WORK/'runtime/ssa11/c0-source-authority.json'),C0=initial['c0'],predecessor_report=dict(path=initial['predecessor_path'],sha256=initial['predecessor_sha256']),protected_files=len(initial['protected']),donor_files=len(initial['donor']['files']),donor_head=initial['donor']['head'],local_configuration_and_hooks='historical identities unchanged except explicitly reconciled pre-intake global setting; current config and project hooks preserved',configuration_reconciliation=reconciled,installed_skill='byte-exact unchanged',host=dict(system=platform.system(),machine=platform.machine()),tools=tools,changed_paths=sorted(changed),configuration_sha256=hashlib.sha256(initial['config'].encode()).hexdigest())
	(RUNTIME/(a.name+'.json')).write_text(json.dumps(result,indent=2)+'\n')
	print('PASS:',len(initial['protected']),'protected,',len(initial['donor']['files']),'donor, source/tool/workflow identities')


if __name__ == '__main__':
	main()
