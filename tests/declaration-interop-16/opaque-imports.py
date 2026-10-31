#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C/GObject nominal import declarations retained by opaque native libraries."""
from pathlib import Path
import hashlib,json,os,runpy,shlex,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='opaque-imports-',dir=output));here=Path(__file__).resolve().parent;helper=ROOT/'tests/structural-generics-15/units.py';helpers=runpy.run_path(str(helper))
	sources=[Path(__file__).resolve(),*[here/('opaque-import-'+suffix) for suffix in ['declarations.astra','leaf.astra','consumer.astra','provider.c','provider.h']],helper,ROOT/'lib/runtime/interop/foreign-14.c'];receipt=dict(scope='opaque C/GObject nominal import declaration and native parameter/factory composition; final M16 remains pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in sources},checks=[],products={})
	def run(command,contains='',expected=0):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',G_DEBUG='fatal-warnings',PYTHONDONTWRITEBYTECODE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	flags=['-std=gnu11','-Wall','-Wextra','-Werror','-pthread'];includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']))
	def fingerprint(groups,include_object):
		text=''
		for group in sorted(groups):
			if group=='receipt' or not include_object and group=='object':continue
			text+=str(len(group))+':'+group
			for key in sorted(groups[group]):
				if not include_object and (key in ['identity','symbol','declarations','declarations_sha256'] or group.startswith('foreign-import ') and key=='declaration'):continue
				value=groups[group][key];text+=str(len(key))+':'+key+str(len(value))+':'+value
		return hashlib.sha256(text.encode()).hexdigest()
	for level in '012':
		case=work/('O'+level);case.mkdir();declarations=case/'declarations.astra';declarations.write_bytes((here/'opaque-import-declarations.astra').read_bytes());leaf=case/'leaf.astra';leaf.write_bytes((here/'opaque-import-leaf.astra').read_bytes());obj=case/'leaf.o';interface=case/'leaf.asti';run([compiler,'-O'+level,'-c','--module','ImportChannel16',*[a for n in ['ImportChannel16.Fault','ImportChannel16.foreign_fault','ImportChannel16.inspect'] for a in ['--native-export',n]],'--emit-interface',interface,declarations,leaf,'-o',obj]);declarations.unlink();leaf.unlink();consumer=case/'consumer.astra';consumer.write_bytes((here/'opaque-import-consumer.astra').read_bytes());run([compiler,'-O'+level,'-c','--import-module',interface,consumer,'-o',case/'consumer.o']);adapter=case/'imports.c';adapter.write_text(run([compiler,'--import-module',interface,'--emit-gobject-source',consumer]));(case/'opaque-import-provider.h').write_bytes((here/'opaque-import-provider.h').read_bytes());client=case/'client';run(['cc',*flags,'-O'+level,*includes,'-I'+str(case),adapter,here/'opaque-import-provider.c',ROOT/'lib/runtime/interop/foreign-14.c',obj,case/'consumer.o',*libs,'-o',client]);run([client],contains='PASS opaque C/GObject imported declarations')
		if level in '02':run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
		if level=='0':
			trace=case/'opens.log';run(['strace','-f','-e','trace=openat,openat2','-o',trace,compiler,'--import-module',interface,'--emit-gobject-source',consumer]);assert str(interface) in trace.read_text() and str(obj) in trace.read_text() and str(leaf) not in trace.read_text() and str(declarations) not in trace.read_text()
			for root,old,new in [('UnitCProvider','name="unitc16"','name="changed16"'),('UnitGProvider','type="UnitProvider16"','type="OtherProvider16"')]:
				bad=case/('mutant-'+root);bad.mkdir();shutil.copyfile(obj,bad/'leaf.o');groups=helpers['metadata'](interface.read_text());group='foreign-import '+root;assert old in groups[group]['declaration'];groups[group]['declaration']=groups[group]['declaration'].replace(old,new,1);assert fingerprint(groups,False)==groups['abi']['identity'];groups['receipt']['fingerprint']=fingerprint(groups,True);(bad/'leaf.asti').write_text(helpers['encoded'](groups));run([compiler,'--import-module',bad/'leaf.asti','--dump-cabi',consumer],expected=1,contains='foreign import declaration/selection/factory identity mismatch')
		receipt['products'][case.name]={p.name:sha(p) for p in [interface,obj,case/'consumer.o',adapter,client]}
	receipt['status']='OPAQUE_C_GOBJECT_IMPORTS_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
