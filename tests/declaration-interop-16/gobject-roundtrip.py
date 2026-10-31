#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh scanned SDK -> strict declarations -> executing native Astra consumer."""
from pathlib import Path
import copy,hashlib,json,os,shlex,subprocess,sys,tempfile
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
GI='{http://www.gtk.org/introspection/core/1.0}'
C='{http://www.gtk.org/introspection/c/1.0}'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='declared-gir-roundtrip-',dir=output));here=Path(__file__).resolve().parent;importer=ROOT/'tools/gir/import.py';profile=here/'gobject-roundtrip-profile.json';template=here/'gobject-roundtrip.astra.in'
	receipt=dict(scope='fresh typed GObject GIR roundtrip, native imported properties/callbacks/buffers/records/objects/errors and fail-closed metadata mutations; signals/composition and final M16 pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),profile,template,here/'gobject-roundtrip-client.c',here/'gobject-scalars.py',here/'gobject-scalars.astra',importer,importer.with_name('declarations.py')]},checks=[])
	def run(command,expected=0,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];command=list(map(str,command));p=subprocess.run(command,capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',G_DEBUG='fatal-warnings',PYTHONDONTWRITEBYTECODE='1'));receipt['checks'].append(dict(command=command,exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	producer=json.loads(run(['python3',here/'gobject-scalars.py',compiler,output/'producer']));producer_receipt=Path(producer['receipt']);products=json.loads(producer_receipt.read_text());assert products['compiler_sha256']==receipt['compiler_sha256'] and len(products['products'])==5;receipt['producer_receipt']=dict(path=str(producer_receipt),sha256=sha(producer_receipt))
	flags=['-std=gnu11','-Wall','-Wextra','-Werror','-pthread'];includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']))
	for variant in products['products']:
		sdk=producer_receipt.parent/variant;gir=sdk/'Astra16-2.3.gir';directory=work/variant;directory.mkdir();generated=directory/'generated';cmd=['python3',importer,'--profile',profile,'--gir',gir];run([*cmd,'--output',generated]);run([*cmd,'--verify',generated]);second=directory/'second';run([*cmd,'--output',second]);assert all((generated/name).read_bytes()==(second/name).read_bytes() for name in ['bindings.astra','contract.json']);contract=json.loads((generated/'contract.json').read_text());assert len(contract['records'])==2 and len(contract['callbacks'])==2
		records=list(contract['records'].values());sample=next(r['source'] for r in records if r['fields'][0][0]=='count');pair=next(r['source'] for r in records if r['fields'][0][0]=='first');consumer=template.read_text().replace('@SAMPLE@',sample).replace('@PAIR@',pair);prelude,body=consumer.split('bool invert',1);source=directory/'consumer.astra';source.write_text(prelude+(generated/'bindings.astra').read_text()+'bool invert'+body)
		for stage in ['semantics','core','cfg','ssa','nabi','cabi']:run([compiler,'--dump-'+stage,source])
		level=variant[6];bridge_level=variant[-1];obj=directory/'consumer.o';run([compiler,'-O'+level,'-c',source,'-o',obj]);adapter=directory/'imports.c';adapter.write_text(run([compiler,'--emit-gobject-source',source]));client=directory/'client';run(['cc',*flags,'-O'+bridge_level,*includes,'-I'+str(sdk/'include'),adapter,here/'gobject-roundtrip-client.c',obj,'-L'+str(sdk/'lib'),'-Wl,-rpath,'+str(sdk/'lib'),'-lastra16decl',*libs,'-o',client]);run([client],contains='PASS native GIR roundtrip ownership and algorithms')
		if variant in ['native0-bridge0','native2-bridge2']:run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
		receipt.setdefault('products',{})[variant]={str(p.relative_to(directory)):sha(p) for p in [generated/'bindings.astra',generated/'contract.json',source,adapter,obj,client]}
		# Mutate one real, well-formed SDK fact at a time. No shared producer and
		# consumer agreement is accepted when scope/ownership/physical facts change.
	base=ET.parse(gir);ns={'g':GI[1:-1]};find=lambda doc,path:doc.find(path,ns)
	mutations={
		'missing-encoding':lambda d:find(d,".//g:method[@name='try_counted_text']/g:parameters/g:parameter[@name='result']/g:attribute[@name='astra.encoding']").set('name','astra.missing'),
		'lost-owned-object':lambda d:find(d,".//g:method[@name='try_spawn']/g:parameters/g:parameter[@name='result']").set('transfer-ownership','none'),
		'callback-retained':lambda d:find(d,".//g:method[@name='try_visit']/g:parameters/g:parameter[@name='argument1']").set('scope','notified'),
		'wrong-closure':lambda d:find(d,".//g:method[@name='try_visit']/g:parameters/g:parameter[@name='argument1']").set('closure','0'),
		'wrong-length':lambda d:find(d,".//g:method[@name='try_transform']/g:parameters/g:parameter[@name='argument1']/g:array").set('length','0'),
		'lost-produced':lambda d:find(d,".//g:method[@name='try_transform']/g:parameters/g:parameter[@name='argument1']/g:attribute[@name='astra.produced']").set('value','unknown'),
		'wrong-domain':lambda d:find(d,".//g:method[@name='try_evaluate']/g:attribute[@name='astra.error-domain']").set('value','17'),
		'wrong-status':lambda d:find(d,".//g:method[@name='try_evaluate']/g:attribute[@name='astra.error-codes']").set('value','-1601'),
		'missing-throws':lambda d:find(d,".//g:method[@name='try_evaluate']").set('throws','0'),
		'wrong-gtype':lambda d:find(d,".//g:class[@name='Session']").set('{http://www.gtk.org/introspection/glib/1.0}get-type','other_get_type'),
		'wrong-boxed-field':lambda d:find(d,".//g:field[@name='astra_field_2_enabled']/g:type").set(C+'type','_Bool'),
		'unknown-channel-fact':lambda d:find(d,".//g:method[@name='try_evaluate']/g:parameters/g:parameter[@name='argument0']").set('guess-retained','1'),
	}
	for name,mutate in mutations.items():
		doc=copy.deepcopy(base);mutate(doc);path=work/(name+'.gir');doc.write(path,encoding='utf-8',xml_declaration=True);run(['python3',importer,'--profile',profile,'--gir',path,'--output',work/(name+'-rejected')],1,'astra-gir:')
		# Supported verifier rejects altered generated declarations and DTD input.
	bindings=generated/'bindings.astra';original=bindings.read_bytes();bindings.write_bytes(original+b'// drift\n');run([*cmd,'--verify',generated],1,'drift');bindings.write_bytes(original);run([*cmd,'--verify',generated]);dtd=work/'dtd.gir';dtd.write_text('<!DOCTYPE repository [<!ENTITY x "bad">]><repository/>');run(['python3',importer,'--profile',profile,'--gir',dtd,'--output',work/'dtd-rejected'],1,'DTD/entities')
	receipt['mutants']=list(mutations);receipt['status']='TYPED_GIR_NATIVE_ROUNDTRIP_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
