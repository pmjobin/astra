#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze and reconcile an actual Meson registry; never change test semantics."""
from pathlib import Path
import argparse,hashlib,json,pickle,subprocess
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n')
def inputs():
	names=subprocess.check_output(['git','ls-files','-z','--','bootstrap','lib','tests','tools/gir','meson.build','meson.options'],cwd=ROOT).decode().split('\0')
	return {name:sha(ROOT/name) for name in names if name}
def main():
	parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('mode',choices=['inventory','reconcile']);parser.add_argument('--build',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--log',type=Path);args=parser.parse_args();build=args.build.resolve();output=args.output.resolve();assert not output.is_relative_to(ROOT) and not build.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True)
	if args.mode=='inventory':
		assert not (output/'inventory.json').exists(),'Preserve previous inventories; choose a fresh output directory'
		rows=json.loads(subprocess.check_output(['meson','introspect',build,'--tests']));setup=pickle.loads((build/'meson-private/meson_test_setup.dat').read_bytes());assert len(rows)==len(setup)
		for ordinal,(row,test) in enumerate(zip(rows,setup),1):
			assert row['name']==test.name and row['suite']==test.suite
			row.update(ordinal=ordinal,expected_exitcode=test.expected_exitcode,expected_fail=test.expected_fail,project=test.project_name)
			suites=[s.split(':',1)[1] for s in test.suite if ':' in s];row['log_name']=('+'.join(suites)+' - ' if suites else '')+test.project_name+':'+test.name
		assert len({row['log_name'] for row in rows})==len(rows)
		save(output/'inventory.json',rows);save(output/'options.json',json.loads(subprocess.check_output(['meson','introspect',build,'--buildoptions'])));save(output/'source.json',dict(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),tree=subprocess.check_output(['git','rev-parse','HEAD^{tree}'],cwd=ROOT,text=True).strip(),inputs=inputs(),compiler_sha256=sha(build/'astrac')));print(json.dumps(dict(registrations=len(rows),inventory_sha256=sha(output/'inventory.json'))));return
	original=json.loads((output/'source.json').read_text());assert original['inputs']==inputs() and original['compiler_sha256']==sha(build/'astrac'),'Source/compiler changed since registry freeze'
	rows=json.loads((output/'inventory.json').read_text());definitions={r['log_name']:r for r in rows};log=(args.log or build/'meson-logs/m16-final-full.json');results=[json.loads(line) for line in log.read_text().splitlines()];seen=set();outcomes=[]
	for result in results:
		name=result['name'];assert name in definitions and name not in seen,name;seen.add(name);definition=definitions[name];assert result['command']==definition['cmd'],name
		if result['result']=='OK':assert not result['is_fail'] and result['returncode']==(definition['expected_exitcode'] or 0),name
		outcomes.append(dict(name=name,result=result['result'],returncode=result['returncode'],expected_exitcode=definition['expected_exitcode'],expected_fail=definition['expected_fail'],duration=result['duration']))
	missing=sorted(set(definitions)-seen);bad=[row for row in outcomes if row['result']!='OK'];save(output/'outcomes.json',outcomes);summary=dict(status='PASS' if not missing and not bad else 'FAIL',registered=len(rows),observed=len(results),missing=missing,nonpassing=bad,source_sha256=sha(output/'source.json'),inventory_sha256=sha(output/'inventory.json'),options_sha256=sha(output/'options.json'),raw_log=dict(path=str(log),sha256=sha(log)),outcomes_sha256=sha(output/'outcomes.json'));save(output/'summary.json',summary);print(json.dumps(summary));assert summary['status']=='PASS'
if __name__=='__main__':main()
