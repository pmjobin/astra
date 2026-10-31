#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Captured native environment projected into an exact synchronous callback."""
from pathlib import Path
import hashlib,json,os,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='captured-callbacks-',dir=output));here=Path(__file__).resolve().parent;source=here/'captured-callbacks.astra';receipt=dict(compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),source,here/'captured-callbacks-client.c']},checks=[])
	def run(command,expected=0,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];assert 'CRITICAL' not in p.stderr;return p.stdout
	for stage in ['semantics','core','cfg','ssa','nabi','cabi']:run([compiler,'--dump-'+stage,source])
	for level in '012':
		obj=work/('native-O'+level+'.o');client=work/('native-O'+level);run([compiler,'-O'+level,'-c',source,'-o',obj]);run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O2',here/'captured-callbacks-client.c',obj,'-o',client]);run([client],contains='PASS captured scalar/BOOL/void callbacks');run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors');receipt.setdefault('products',{})[client.name]=sha(client)
	base=source.read_text()
	for name,text in {
		'wrong-scalar-result':base.replace('Callback<i64,','Callback<f64,'),
		'wrong-scalar-argument':base.replace('Callback<bool,bool>','Callback<bool,u32>'),
		'escaping-field':base+'class Escape{Callback<int,int> saved;}\n',
		'escaping-result':base+'Callback<int,int> escape(borrowed Closure<Environment,int,int> source){return source;}\n',
		'copied-callback':base.replace('return apply(closure);','var saved=closure;return apply(saved);'),
		'reverse-overlapping-owner':base+'void overlap(owned Closure<Environment,bool,bool> owner,borrowed Callback<bool,bool> view){}int bad(){var environment=new Environment(1);var closure=closure_bind(move environment,flip);overlap(move closure,closure);return 0;}\n',
		'overlapping-owner':base+'void overlap(borrowed Callback<bool,bool> view,owned Closure<Environment,bool,bool> owner){}int bad(){var environment=new Environment(1);var closure=closure_bind(move environment,flip);overlap(closure,move closure);return 0;}\n',
	}.items():
		assert text!=base;unit=work/(name+'.astra');unit.write_text(text);run([compiler,'--dump-core',unit],1,'error:')
	receipt['status']='CAPTURED_NATIVE_CALLBACK_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
