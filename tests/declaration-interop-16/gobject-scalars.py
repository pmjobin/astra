#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute declaration-derived GObject properties/methods and scanner-produced GIR."""
from pathlib import Path
import hashlib
import json
import os
import shlex
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='declared-gobject-scalars-',dir=output));here=Path(__file__).resolve().parent;source=here/'gobject-scalars.astra'
	receipt=dict(scope='declared GObject scalar/reference/synchronous-callback/counted-payload/boxed-record/native-object/property/checked-method prerequisites; retained signals, GIR import and final M16 gates remain pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),source,here/'gobject-scalars-client.c',here/'gobject-scalars-support.c',here/'gobject-scalars-gi.py',ROOT/'lib/runtime/interop/foreign-14.c']},checks=[])
	def run(command,contains='',env=None):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',G_DEBUG='fatal-warnings',**(env or {})));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==0 and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	flags=['-std=gnu11','-Wall','-Wextra','-Werror','-pthread'];includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']));receipt['providers']=run(['pkg-config','--modversion','gobject-2.0','gobject-introspection-1.0'])
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:run([compiler,'--dump-'+stage,source])
	header=work/'session.h';header.write_text(run([compiler,'--emit-gobject-header',source]));adapter=work/'adapter.c';adapter.write_text(run([compiler,'--emit-gobject-source',source]));(work/'native.h').write_text(run([compiler,'--emit-class-header',source]))
	assert 'try_native_only' not in header.read_text() and 'try_glib_only' in header.read_text()
	receipt['generated']={p.name:sha(p) for p in [header,adapter,work/'native.h']}
	for level in '012':
		obj=work/('native-O'+level+'.o');run([compiler,'-O'+level,'-c',source,'-o',obj])
		for bridge_level in ('1' if level=='1' else '02'):
			prefix=work/('native'+level+'-bridge'+bridge_level);(prefix/'lib').mkdir(parents=True);(prefix/'include').mkdir();(prefix/'include/session.h').write_bytes(header.read_bytes());library=prefix/'lib/libastra16decl.so'
			run(['cc',*flags,'-O'+bridge_level,'-fPIC','-shared','-Wl,-z,defs','-Wl,-soname,libastra16decl.so',*includes,adapter,here/'gobject-scalars-support.c',ROOT/'lib/runtime/interop/foreign-14.c',obj,*libs,'-o',library])
			client=prefix/'client';run(['cc',*flags,'-O2',*includes,here/'gobject-scalars-client.c','-L'+str(prefix/'lib'),'-Wl,-rpath,$ORIGIN/lib','-lastra16decl',*libs,'-o',client]);run([client],contains='PASS declared GObject scalar properties and native C identity')
			if (level,bridge_level) in [('0','0'),('2','2')]:run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
			gir=prefix/'Astra16-2.3.gir';typelib=prefix/'Astra16-2.3.typelib';environment=dict(LD_LIBRARY_PATH=str(prefix/'lib'),GI_TYPELIB_PATH=str(prefix))
			run(['g-ir-scanner','--no-libtool','--namespace=Astra16','--nsversion=2.3','--include=GObject-2.0','--identifier-prefix=Astra16','--symbol-prefix=astra16','--library=astra16decl','--library-path='+str(prefix/'lib'),'--c-include=session.h','--warn-all','--warn-error','--output='+str(gir),'--pkg=gobject-2.0','-I'+str(prefix/'include'),prefix/'include/session.h'],env=environment)
			ns={'g':'http://www.gtk.org/introspection/core/1.0'};document=ET.parse(gir).getroot();records=document.findall('.//g:record',ns);boxed=[r for r in records if r.get('{http://www.gtk.org/introspection/glib/1.0}type-name','').startswith('Astra16Record')];assert len(boxed)==2 and all(r.find("g:method[@name='copy']",ns) is not None for r in boxed);node=document.find(".//g:class[@name='Session']",ns);assert node is not None and node.get('name')=='Session';properties={p.get('name'):p for p in node.findall('g:property',ns)};assert set(properties)=={'count','enabled','scale','title','current'};assert properties['enabled'].find('g:type',ns).get('name')=='gboolean';assert properties['scale'].find('g:type',ns).get('name')=='gdouble';assert node.find("g:method[@name='try_evaluate']",ns).get('throws')=='1';callback=node.find("g:method[@name='try_visit']/g:parameters/g:parameter[@name='argument1']",ns);assert callback.get('scope')=='call' and callback.get('closure')=='2';refs=node.find("g:method[@name='try_eval_refs']/g:parameters",ns);assert refs.find("g:parameter[@name='argument0']/g:type",ns).get('{http://www.gtk.org/introspection/c/1.0}type')=='gint64';assert refs.find("g:parameter[@name='argument1']",ns).get('direction')=='inout' and refs.find("g:parameter[@name='argument2']",ns).get('direction')=='out';buffer=node.find("g:method[@name='try_transform']/g:parameters",ns);assert buffer.find("g:parameter[@name='argument1']",ns).get('direction')=='inout' and buffer.find("g:parameter[@name='argument1_capacity']",ns).get('direction')=='inout';owned=node.find("g:method[@name='try_counted_text']/g:parameters/g:parameter[@name='result']",ns);projection=node.find("g:method[@name='try_spawn']/g:parameters/g:parameter[@name='result']",ns);assert projection.get('transfer-ownership')=='full' and projection.find('g:type',ns).get('name')=='Item';assert owned.get('transfer-ownership')=='full' and owned.find('g:type',ns).get('name')=='GLib.Bytes'
			run(['g-ir-compiler',gir,'--output='+str(typelib)]);run(['python3',here/'gobject-scalars-gi.py',library],contains='PASS declared GObject GI properties, checked errors and exact native retirement',env=environment);receipt.setdefault('products',{})[prefix.name]={str(p.relative_to(prefix)):sha(p) for p in [library,client,gir,typelib,prefix/'include/session.h']}
	receipt['status']='DECLARED_GOBJECT_SCALAR_NATIVE_GIR_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))


if __name__=='__main__':main(*sys.argv[1:])
