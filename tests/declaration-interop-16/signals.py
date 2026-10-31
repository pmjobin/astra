#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute native signal bodies through an independently compiled GObject client."""
from pathlib import Path
import hashlib,json,os,shlex,subprocess,sys,tempfile
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='native-signals-',dir=output));here=Path(__file__).resolve().parent
	receipt=dict(scope='three native GObject signals, owned object projections, C/GI retention and selected scalar signal GIR-to-native-Closure round-trip; remaining domain/frozen API/final M16 qualification pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),*[here/('signals'+s) for s in ['.astra','-support.c','-client.c','-gi.py','-profile.json','-roundtrip.astra.in','-roundtrip-client.c']],ROOT/'lib/runtime/interop/foreign-14.c',ROOT/'lib/runtime/interop/gobject-signals-16.c',ROOT/'lib/runtime/interop/gobject-signals-16.h',ROOT/'tools/gir/import.py',ROOT/'tools/gir/declarations.py']},checks=[])
	def run(command,contains='',env=None):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',G_DEBUG='fatal-warnings',PYTHONDONTWRITEBYTECODE='1',**(env or {})));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==0 and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	flags=['-std=gnu11','-Wall','-Wextra','-Werror','-pthread'];includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']))
	for level in '012':
		unit=work/('O'+level);unit.mkdir();source=unit/'implementation.astra';source.write_bytes((here/'signals.astra').read_bytes());obj=unit/'signals.o';interface=unit/'signals.asti';run([compiler,'-O'+level,'-c','--module','SignalUnit','--native-export','SignalUnit.Session','--native-export','SignalUnit.Sample','--native-export','SignalUnit.Item','--emit-interface',interface,source,'-o',obj]);source.unlink();anchor=unit/'adapter.astra';anchor.write_text('int anchor(){return 0;}\n');adapter=unit/'signals.c';adapter.write_text(run([compiler,'--import-module',interface,'--emit-gobject-source',anchor]));header=unit/'signals.h';header.write_text(run([compiler,'--import-module',interface,'--emit-gobject-header',anchor]));assert not source.exists() and 'this.raw' not in adapter.read_text();library=unit/'libevents16.so';run(['cc',*flags,'-O'+level,'-fPIC','-shared','-Wl,-z,defs',*includes,adapter,here/'signals-support.c',ROOT/'lib/runtime/interop/foreign-14.c',obj,*libs,'-o',library]);client=unit/'client';run(['cc',*flags,*includes,here/'signals-client.c','-L'+str(unit),'-Wl,-rpath,$ORIGIN','-levents16',*libs,'-o',client]);run([client],contains='PASS native typed signal delivery')
		if level in '02':run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
		gir=unit/'Events16-1.0.gir';environment=dict(LD_LIBRARY_PATH=str(unit),GI_TYPELIB_PATH=str(unit));run(['g-ir-scanner','--no-libtool','--namespace=Events16','--nsversion=1.0','--include=GObject-2.0','--identifier-prefix=Events16','--symbol-prefix=events16','--library=events16','--library-path='+str(unit),'--c-include=signals.h','--warn-all','--warn-error','--output='+str(gir),'--pkg=gobject-2.0','-I'+str(unit),header],env=environment);run(['g-ir-compiler',gir,'--output='+str(unit/'Events16-1.0.typelib')]);run(['python3',here/'signals-gi.py',library],contains='PASS scanned GI typed signals',env=environment)

		generated=unit/'generated';importer=ROOT/'tools/gir/import.py';run(['python3',importer,'--profile',here/'signals-profile.json','--gir',gir,'--output',generated]);run(['python3',importer,'--profile',here/'signals-profile.json','--gir',gir,'--verify',generated]);consumer=unit/'consumer.astra';consumer.write_text((here/'signals-roundtrip.astra.in').read_text().replace('@BINDINGS@',(generated/'bindings.astra').read_text()));consumer_obj=unit/'consumer.o';run([compiler,'-O'+level,'--vapi',generated/'bindings.vapi','-c',consumer,'-o',consumer_obj]);imports=unit/'imports.c';imports.write_text(run([compiler,'--vapi',generated/'bindings.vapi','--emit-gobject-source',consumer]));roundtrip=unit/'roundtrip';runtime=ROOT/'lib/runtime/interop';run(['cc',*flags,'-O'+level,*includes,'-I'+str(unit),'-I'+str(generated),'-I'+str(runtime),imports,generated/'bindings.c',here/'signals-roundtrip-client.c',runtime/'gobject-signals-16.c',consumer_obj,'-L'+str(unit),'-Wl,-rpath,$ORIGIN','-levents16',*libs,'-o',roundtrip]);run([roundtrip],contains='PASS scanned SDK signal round-trip')
		if level in '02':run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',roundtrip],contains='ERROR SUMMARY: 0 errors')

		if level=='0':
			core='{http://www.gtk.org/introspection/core/1.0}';glib='{http://www.gtk.org/introspection/glib/1.0}';c='{http://www.gtk.org/introspection/c/1.0}';mutants=['missing-destroy','async-scope','borrowed-destroy','first','typed-return','scalar-width','scalar-transfer','scalar-null','scalar-out','scalar-scope','scalar-destroy','duplicate-name']
			for index,mutation in enumerate(mutants):
				tree=ET.parse(gir);signal=tree.find('.//'+glib+'signal[@name="updated"]');assert signal is not None;arguments=signal.find(core+'parameters');argument=arguments[0]
				if mutation in ['missing-destroy','async-scope','borrowed-destroy']:
					key='astra.signal-scope' if mutation=='async-scope' else 'astra.signal-destroy';fact=next(n for n in signal.findall(core+'attribute') if n.attrib['name']==key)
					if mutation=='missing-destroy':signal.remove(fact)
					else:fact.set('value','async' if mutation=='async-scope' else 'borrowed')
				elif mutation=='first':signal.set('when','first')
				elif mutation=='typed-return':signal.find(core+'return-value').find(core+'type').set('name','gint')
				elif mutation=='scalar-width':argument.find(core+'type').set('name','gint64')
				elif mutation=='scalar-transfer':argument.set('transfer-ownership','full')
				elif mutation=='scalar-null':argument.set('nullable','1')
				elif mutation=='scalar-out':argument.set('direction','out')
				elif mutation=='scalar-scope':argument.set('scope','async')
				elif mutation=='scalar-destroy':argument.set('destroy','2')
				elif mutation=='duplicate-name':arguments[1].set('name',argument.attrib['name'])
				path=unit/('mutant-'+mutation+'.gir');tree.write(path,encoding='utf-8',xml_declaration=True);rejected=unit/('rejected-'+mutation);command=['python3',importer,'--profile',here/'signals-profile.json','--gir',path,'--output',rejected];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120,env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));assert p.returncode==1 and not rejected.exists(),receipt['checks'][-1]

	fixture=(here/'signals.astra').read_text()
	for index,(old,new) in enumerate([
		('emit updated(this.raw,true,2.5);','this.updated(this.raw,true,2.5);'),
		('emit updated(this.raw,true,2.5);','emit updated(this.raw,7,2.5);'),
		('[Shared][CExport','[CExport'),
		('signal void updated','signal int updated'),
		('signal void updated(int count','signal void updated(owned Session count'),
		('signal void updated','signal void notify'),
		('[Foreign]signal void updated','[Foreign(personalities="c")]signal void updated'),
	]):
		assert old in fixture;source=work/('negative'+str(index)+'.astra');source.write_text(fixture.replace(old,new,1));command=[compiler,'--dump-llvm',source];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120);receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));assert p.returncode==1 and 'error' in p.stderr and 'define ' not in p.stdout,receipt['checks'][-1]
	none=work/'none.o';run([compiler,'--foreign-personalities=none','-c',here/'signals.astra','-o',none]);undefined=run(['nm','-u',none]);assert 'astra_foreign16_signal_' not in undefined and 'g_signal_' not in undefined
	receipt['status']='NATIVE_TYPED_SIGNALS_GIR_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
