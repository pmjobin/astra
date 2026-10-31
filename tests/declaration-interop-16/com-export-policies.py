#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Member-derived COM export admission and deterministic SDK projection."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='typed-com-export-policies-',dir=output));source=Path(__file__).with_name('com-exports.astra');base=source.read_text()
	receipt=dict(scope='typed COM export source/schema/SDK prerequisites; actual native Windows evidence separate',compiler_sha256=sha(compiler),recipe_sha256=sha(Path(__file__)),source_sha256=sha(source),checks=[])
	def run(command,expected=0,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];assert 'CRITICAL' not in p.stderr;return p.stdout
	target=['--target=x86_64-w64-windows-gnu']
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:run([compiler,*target,'--dump-'+stage,source])
	for option in ['--emit-com-header','--emit-com-source','--emit-class-header','--emit-class-source']:
		first=run([compiler,*target,option,source]);assert first==run([compiler,*target,option,source])
		if option=='--emit-com-source':assert 'nativequery16_evaluate(root' in first and 'reinterpret_cast' not in first and 'Scale(LONG' not in first and 'static_cast<HRESULT>(-1600)' not in first
	for level in '012':run([compiler,*target,'-O'+level,'-c',source,'-o',work/('native-O'+level+'.o')])
	for name,text in {
		'unknown-interface':base.replace('interfaces="IQuery,IDetail,ITyped,IProxy,IRoots"','interfaces="Missing"'),
		'duplicate-interface':base.replace('interfaces="IQuery,IDetail,ITyped,IProxy,IRoots"','interfaces="IQuery,IQuery"'),
		'unique-root':base.replace('[Shared]',''),
		'wrong-context':base.replace('COMExport(interfaces="IQuery,IDetail,ITyped,IProxy,IRoots",threading="constructing"','COMExport(interfaces="IQuery,IDetail,ITyped,IProxy,IRoots",threading="agile"'),
		'missing-profile':base.replace('COMExport(interfaces="IQuery,IDetail,ITyped,IProxy,IRoots",threading="constructing",profile="declarations-v1")','COMExport(interfaces="IQuery,IDetail,ITyped,IProxy,IRoots",threading="constructing")'),
		'wrong-native-root-projection':base.replace('owned NativeQuery native_duplicate(borrowed NativeQuery input){operation();var result=input.clone();return move result;}', 'owned Other native_duplicate(borrowed NativeQuery input){operation();var result=new Other();return move result;}')+'\n[Shared][CExport(name="othernative16",profile="declarations-v1")]class Other{[Foreign]init(){}}',
		'conflicting-interface-override':base.replace('interfaces="IQuery,IDetail,ITyped,IProxy,IRoots"','interfaces="IQuery,IDetail,ITyped,IProxy,IRoots,IConflict"').replace('[Foreign]f64 native_read','[Foreign]i64 alternate(i64 input,f64 bias,bool enabled){return input;}[Foreign]f64 native_read')+'[COMImport(name="conflict16",iid="473dc7e9-41d6-4768-bda4-cc48396af306",threading="constructing",profile="declarations-v1")]interface IConflict{[Foreign(error_factory="foreign_fault",error_domain="16",errors="Fault=-1600")]init(borrowed void* unknown)throws Fault;[Foreign(native="alternate",error_factory="foreign_fault",error_domain="16",errors="Fault=-1600")]i64 transform(i64 input,f64 bias,bool enabled)throws Fault;}',
		'missing-native-binding':base.replace('native="evaluate"','native="missing"'),
		'wrong-result-sign':base.replace('i64 transform(i64','u64 transform(i64'),
		'wrong-native-arity':base.replace('i64 evaluate(i64 input,f64 bias,bool enabled)','i64 evaluate(i64 input,f64 bias,bool enabled,int extra)'),
		'wrong-property-binding':base.replace('native="gain"','native="evaluate"'),
		'missing-bool-convention':base.replace(',bool_abi="c99"',''),
		'wrong-pod-field':base.replace('ComSample adjust(ComSample input,f64 delta','ComSample adjust(ComSample input,f32 delta'),
		'missing-selected-member':base.replace('[Foreign]string constant','string constant'),
	}.items():
		assert text!=base;unit=work/(name+'.astra');unit.write_text(text);run([compiler,*target,'--dump-semantics',unit],expected=1,contains='error:')
	receipt['status']='TYPED_COM_EXPORT_POLICY_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))


if __name__=='__main__':main(*sys.argv[1:])
