#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact GType, SDK, checked error and target admission for typed imports."""
from pathlib import Path
import hashlib,json,os,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='typed-gobject-policies-',dir=output));source=Path(__file__).with_name('gobject-imports.astra');base=source.read_text();receipt=dict(compiler_sha256=sha(compiler),recipe_sha256=sha(Path(__file__)),source_sha256=sha(source),checks=[])
	def run(command,expected=0,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];assert 'CRITICAL' not in p.stderr;return p.stdout
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:run([compiler,'--dump-'+stage,source])
	for option in ['--emit-class-header','--emit-gobject-header','--emit-gobject-source']:assert run([compiler,option,source])==run([compiler,option,source])
	for name,text in {
		'missing-record-binding':base.replace('Sample=Provider16Sample:provider16_sample|',''),
		'bad-record-type':base.replace('Provider16Sample:provider16_sample','invalid-type:provider16_sample'),
		'duplicate-record-binding':base.replace('Sample=Provider16Sample:provider16_sample','Sample=Provider16Sample:provider16_sample|Sample=Other:other'),
		'bad-gtype':base.replace('type="Provider16Ledger"','type="provider16Ledger"'),
		'invalid-namespace':base.replace('namespace="ProviderApi"','namespace="provider-api"'),
		'bad-version':base.replace('version="3.2"','version="3..2"'),
		'missing-sdk':base.replace(',header="gobject-provider.h"',''),
		'unsafe-sdk':base.replace('header="gobject-provider.h"','header="../gobject-provider.h"'),
		'missing-symbol-prefix':base.replace(',symbol_prefix="provider16_ledger"',''),
		'bad-symbol-prefix':base.replace('symbol_prefix="provider16_ledger"','symbol_prefix="provider16-ledger"'),
		'foreign-intrusive-lifetime':base.replace('threading="constructing"','lifetime="shared",threading="constructing"'),
		'wrong-threading':base.replace('threading="constructing"','threading="free"'),
		'c-bool-convention':base.replace('threading="constructing"','bool_abi="c99",threading="constructing"'),
		'missing-error-factory':base.replace('error_factory="foreign_fault"','error_factory="missing"'),
	}.items():
		assert text!=base;unit=work/(name+'.astra');unit.write_text(text);run([compiler,'--dump-semantics',unit],1,'error:')
	imports_only=work/'imports-only.astra';imports_only.write_text(base.split('\nbool invert(')[0]);assert 'GObjectImport' in imports_only.read_text() and 'GObjectExport' not in imports_only.read_text()
	run([compiler,'--target=x86_64-w64-windows-gnu','-c',imports_only,'-o',work/'wrong-target.o'],1,'GObject import requires')
	receipt['status']='TYPED_GOBJECT_IMPORT_POLICY_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
