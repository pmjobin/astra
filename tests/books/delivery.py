#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate, genuinely subsequent 28-A2 canonical-ZIP-bound delivery replay."""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--report-sha256',required=True)
	p.add_argument('--qualification',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	a = p.parse_args()
	report_path = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert sha(report_path) == a.report_sha256
	with zipfile.ZipFile(report_path) as z:
		report = json.loads(z.read('RESULT.json'))
		assert report['project_id']=='astra' and report['milestone_id']=='ASTRA-RELEASE-28A2-LANGUAGE-REFERENCE-AND-GUIDE'
		assert report['submission_sha256']=='641e588a2e2e17a0772fe15d66bb1907ad2f1da111a7083e937f072d664e0ed2'
		assert z.read('evidence/QUALIFICATION.json') == a.qualification.read_bytes()
		for name in report['changed_committed_paths']:
			assert (ROOT/name).read_bytes() == subprocess.check_output(['git','show',report['final_commit']+':'+name],cwd=ROOT)
	assert report['final_commit']==subprocess.check_output(['git','rev-parse','HEAD'],text=True,cwd=ROOT).strip()
	assert report['final_tree']==subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True,cwd=ROOT).strip()
	assert not subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT).strip()
	start = datetime.datetime.now(datetime.timezone.utc)
	assert start > datetime.datetime.fromisoformat(report['timestamp'])
	qualification = json.loads(a.qualification.read_text())
	for key in ('products_manifest','toolchain','link'):
		assert sha(qualification[key]['path'])==qualification[key]['sha256']
	build = output_path(a.build,WORK/'build'); runtime = output_path(a.runtime,WORK/'runtime')
	build.mkdir(parents=True,exist_ok=False); runtime.mkdir(parents=True,exist_ok=False)
	write(runtime/'start.json',dict(start_UTC=start.isoformat(),publication_UTC=report['timestamp'],report_sha256=a.report_sha256,qualification_sha256=sha(a.qualification),engineering_status=report['status']))
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	toolchain = json.loads(Path(qualification['toolchain']['path']).read_text())
	assert all(sha(path)==digest for path,digest in toolchain['tools'].items())
	env = dict(os.environ,PYTHONDONTWRITEBYTECODE='1')
	env.update({k:v for k,v in toolchain['environment'].items() if v is not None})
	debugger = runtime/'tool-bin/gdb'; debugger.parent.mkdir()
	debugger.write_bytes((ROOT/'tests/api-docs/gdb-host.py').read_bytes()); debugger.chmod(0o755)
	env['PATH'] = str(debugger.parent)+os.pathsep+env['PATH']
	commands = []
	def run(label,argv,expected=0):
		result = execute(argv,runtime/(label+'-controller'),expected=expected,timeout=2400,env=env)
		commands.append(dict(label=label,argv=list(map(str,argv)),result=result)); write(runtime/'commands.json',commands)
		assert result['status']=='EXPECTED_OUTCOME',label
	products = qualification['products_manifest']['path']; tools = qualification['toolchain']['path']
	run('books',['python3','-B',ROOT/'tests/books/run.py','--products',products,'--toolchain',tools,'--link',qualification['link']['path'],'--build',build/'books','--runtime',runtime/'books'])
	assert json.loads((runtime/'books/result.json').read_text())['status']=='BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS'
	run('docs-native',['python3','-B',ROOT/'tests/api-docs/native.py','--products',products,'--toolchain',tools,'--build',build/'docs-native','--runtime',runtime/'docs-native'])
	plans = json.loads(Path(qualification['regression_plans']['path']).read_text())
	assert sha(qualification['regression_plans']['path'])==qualification['regression_plans']['sha256']
	for plan in plans:
		if '-physical-' not in plan['label'] and not plan.get('memory'): continue
		argv = list(plan['argv']); label = plan['label']
		if plan.get('memory'):
			identities = {row['path']:row['sha256'] for row in qualification['source_consumers'].values()}
			assert argv[-1] in identities and sha(argv[-1])==identities[argv[-1]]
		for flag,parent in (('--build',build),('--runtime',runtime)):
			if flag in argv: argv[argv.index(flag)+1] = str(parent/label)
		run(label,argv,plan.get('expected',0))
	assert sha(report_path)==a.report_sha256
	write(runtime/'result.json',dict(status='AFTER_PUBLICATION_28A2_REPLAY_PASS',start_UTC=start.isoformat(),completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),report_sha256=a.report_sha256,engineering_status=report['status'],commands_sha256=sha(runtime/'commands.json'),scope='Separate subsequent host execution bound to the real published report. Engineering PARTIAL, specification gaps and historical exceptions remain unchanged. This does not amend the immutable report, deploy a site or qualify a release.'))


if __name__ == '__main__':
	main()
