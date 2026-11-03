#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Capture immutable intake identities and preserve the exact predecessor ZIP."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORK = Path.home()/'Workspace/codex/work/astra'
RUNTIME = WORK/'runtime/llvm12'
PREVIOUS = 'c5a004c40c72b48c90451d296e15141c86277dd2f7fe1506eac113238edfc001'


def sha(p):
	return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
	RUNTIME.mkdir(parents=True, exist_ok=True)
	report = Path.home()/'Workspace/codex/reports/astra-report-current.zip'
	assert sha(report) == PREVIOUS
	history = WORK/'runtime/report-history'
	history.mkdir(exist_ok=True)
	out = history/(PREVIOUS+'.zip')
	if not out.exists():
		shutil.copyfile(report, out)
	assert sha(out) == PREVIOUS
	old = json.loads((WORK/'runtime/ssa11/initial.json').read_text())
	record = dict(predecessor_sha256=sha(out), predecessor_path=str(out))
	for key, value in old.items():
		if isinstance(value, dict):
			record[key] = value
			# Preserve initial configuration, refs and complete tracked content, including donor.
	for name, root in [('repository', ROOT), ('donor', Path.home()/'Workspace/astra-bootstrap')]:
		paths = subprocess.check_output(['git','-C',str(root),'ls-files','-z']).decode().split('\0')[:-1]
		record[name] = dict(root=str(root), files={p:sha(root/p) for p in paths}, head=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD']).decode().strip())
	for name, argv in [('refs',['git','show-ref']),('worktrees',['git','worktree','list','--porcelain']),('status',['git','status','--porcelain=v1']),('config',['git','config','--local','--list'])]:
		record[name] = subprocess.check_output(argv, cwd=ROOT).decode()
	record['skill'] = {str(p):sha(p) for p in (Path.home()/'.agents/skills/pm-next').rglob('*') if p.is_file() and '__pycache__' not in str(p)}
	(RUNTIME/'initial.json').write_text(json.dumps(record, indent=2)+'\n')
	print('preserved predecessor and',len(record['donor']['files']),'donor files')


if __name__ == '__main__':
	main()
