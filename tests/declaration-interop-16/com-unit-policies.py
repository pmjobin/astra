#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check Windows opaque COM target and independent serialized declaration authority."""
from pathlib import Path
import hashlib,json,os,runpy,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='opaque-com-policies-',dir=output));here=Path(__file__).resolve().parent;helpers=runpy.run_path(str(ROOT/'tests/structural-generics-15/units.py'));receipt=dict(scope='opaque Windows COM target/metadata authority prerequisites; native execution and final M16 separate',compiler_sha256=sha(compiler),checks=[])
	def run(command,expected=0,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	selected=['--target=x86_64-w64-windows-gnu','--foreign-personalities=c,com'];interface=work/'session.asti';obj=work/'session.o';anchor=work/'anchor.astra';anchor.write_text('int anchor(){return 0;}\n');producer=[compiler,*selected,'-O0','-c','--module','WinUnit16','--native-export','WinUnit16.Session','--native-export','WinUnit16.Fault','--native-export','WinUnit16.foreign_fault','--emit-interface',interface,here/'com-unit.astra',here/'com-unit-protocol.astra','-o',obj];run(producer)
	for stage in ['semantics','core','cfg','ssa','nabi','cabi']:run([compiler,*selected,'--import-module',interface,'--dump-'+stage,here/'com-unit-consumer.astra'])
	run([compiler,'--target=x86_64-w64-windows-gnu','-c','--module','Legacy','--native-export','Legacy.value','--emit-interface',work/'refused.asti',anchor,'-o',work/'refused.o'],2,'Windows interop requires')
	run([compiler,'--import-module',interface,'--dump-cabi',anchor],1,'interface version/schema/compiler fingerprint mismatch')
	run([compiler,'--target=x86_64-w64-windows-gnu','--foreign-personalities=none','--import-module',interface,'--dump-cabi',anchor],1,'foreign import declaration/selection/factory identity mismatch')
	def fingerprint(groups,include_object):
		text=''
		for group in sorted(groups):
			if group=='receipt' or not include_object and group=='object':continue
			text+=str(len(group))+':'+group
			for key in sorted(groups[group]):
				if not include_object and (key in ['identity','symbol','declarations','declarations_sha256'] or group.startswith('foreign-import ') and key=='declaration'):continue
				value=groups[group][key];text+=str(len(key))+':'+key+str(len(value))+':'+value
		return hashlib.sha256(text.encode()).hexdigest()
	for label,old,new,diagnostic in [('iid','1d665f00-16ab-4a63-b3fc-802626016601','1d665f00-16ab-4a63-b3fc-802626016602','foreign import declaration/selection/factory identity mismatch'),('error-code','=-1600','=-1601','foreign import declaration/selection/factory identity mismatch'),('body','f64 evaluate(f64 input) throws WinUnit16.Fault;','f64 evaluate(f64 input) throws WinUnit16.Fault{return input;}','one bodyless typed COM declaration'),('callback','Callback<bool,bool>','Callback<bool,i32>','exact selected native member/signature')]:
		bad=work/label;bad.mkdir();shutil.copyfile(obj,bad/'session.o');groups=helpers['metadata'](interface.read_text());declaration=groups['foreign-import IOpaque16']['declaration'];assert old in declaration;groups['foreign-import IOpaque16']['declaration']=declaration.replace(old,new,1);assert fingerprint(groups,False)==groups['abi']['identity'];groups['receipt']['fingerprint']=fingerprint(groups,True);(bad/'session.asti').write_text(helpers['encoded'](groups));run([compiler,*selected,'--import-module',bad/'session.asti','--dump-cabi',anchor],1,diagnostic)
	receipt['status']='OPAQUE_COM_METADATA_POLICIES_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
