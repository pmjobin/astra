#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Typed COM import declarations, inherited protocol identity and static refusals."""
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
	output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='typed-com-policies-',dir=output));source=Path(__file__).with_name('com-imports.astra');base=source.read_text()
	receipt=dict(scope='typed COM import policy/stage/object prerequisites; runtime Windows evidence separate',compiler_sha256=sha(compiler),recipe_sha256=sha(Path(__file__)),source_sha256=sha(source),checks=[])
	def run(command,expected=0,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];assert 'CRITICAL' not in p.stderr;return p.stdout
	target=['--target=x86_64-w64-windows-gnu']
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:run([compiler,*target,'--dump-'+stage,source])
	header=run([compiler,*target,'--emit-com-header',source]);assert 'struct detail16_Interface : query16_Interface' in header and 'sizeof(BOOL) == 4' in header
	assert 'virtual HRESULT STDMETHODCALLTYPE transform(LONGLONG' in header and 'virtual HRESULT STDMETHODCALLTYPE choose(BOOL' in header
	for level in '012':run([compiler,*target,'-O'+level,'-c',source,'-o',work/('native-O'+level+'.o')])
	for name,text in {
		'duplicate-iid':base.replace('f102','f101'),
		'unknown-base':base.replace('IDetail : IQuery','IDetail : Missing'),
		'cyclic-base':base.replace('interface IQuery {','interface IQuery : IDetail {'),
		'field-storage':base.replace('interface IQuery {','interface IQuery { int value;'),
		'unmanaged-unknown':base.replace('init(borrowed void* unknown)','init(void* unknown)'),
		'wrong-unknown-type':base.replace('init(borrowed void* unknown)','init(int unknown)'),
		'extra-query-argument':base.replace('init(borrowed void* unknown)','init(borrowed void* unknown,int extra)'),
		'owning-query-pointer':base.replace('init(borrowed void* unknown)','init(owned void* unknown)'),
		'foreign-lifetime':base.replace('threading="constructing",profile=', 'threading="constructing",lifetime="unique",profile='),
		'foreign-bool-abi':base.replace('threading="constructing",profile=', 'threading="constructing",bool_abi="c99",profile='),
		'invalid-native-mapping':base.replace('[Foreign(error_factory=', '[Foreign(native="bad-name",error_factory='),
		'query-name-collision':base.replace('i64 transform(', 'i64 QueryInterface('),
		'missing-error-factory':base.replace('error_factory="foreign_fault"','error_factory="missing"'),
		'callback-not-borrowed':base.replace('borrowed Callback<bool,bool>','Callback<bool,bool>'),
		'callback-retained':base.replace('bool choose(', '[ForeignChannel(parameter="code",scope="retained")]bool choose('),
		'callback-erased-type':base.replace('borrowed Callback<bool,bool>','borrowed Fn<bool,bool>'),
		'property-setter-type':base.replace('set(f64 input)','set(i32 input)'),
	}.items():
		assert text!=base;unit=work/(name+'.astra');unit.write_text(text);run([compiler,*target,'--dump-semantics',unit],expected=1,contains='error:')
	run([compiler,'-O0','-c',source,'-o',work/'wrong-target.o'],expected=1,contains='COM import requires')
	receipt['status']='TYPED_COM_IMPORT_POLICY_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))


if __name__=='__main__':main(*sys.argv[1:])
