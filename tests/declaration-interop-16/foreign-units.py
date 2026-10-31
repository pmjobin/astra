#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque foreign leaf/component/adapter composition with hidden producer bodies."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import runpy
import shutil
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='opaque-foreign-units-',dir=output));here=Path(__file__).resolve().parent
	helper=ROOT/'tests/structural-generics-15/units.py';helpers=runpy.run_path(str(helper));sources=[Path(__file__).resolve(),*[here/('foreign-unit-'+name) for name in ['leaf.astra','middle.astra','consumer.astra','client.c','native-client.c']],ROOT/'lib/runtime/interop/foreign-14.c',helper];receipt=dict(scope='opaque declarations-v1 unique C Class and closed record prerequisites; shared COM/GObject unit and remaining M16 gates pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in sources},checks=[],products={})
	def run(command,contains='',expected=0):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	flags=['-std=c11','-Wall','-Wextra','-Werror','-pedantic','-pthread'];runtime=work/'foreign.o';run(['cc',*flags,'-O2','-c',ROOT/'lib/runtime/interop/foreign-14.c','-o',runtime])
	for levels in [*itertools.product('02',repeat=3),('1','1','1')]:
		case=work/('units-'+''.join(levels));case.mkdir();leaf=case/'leaf.astra';middle=case/'middle.astra';consumer=case/'consumer.astra';leaf.write_bytes((here/'foreign-unit-leaf.astra').read_bytes());middle.write_bytes((here/'foreign-unit-middle.astra').read_bytes());consumer.write_bytes((here/'foreign-unit-consumer.astra').read_bytes())
		run([compiler,'-O'+levels[0],'-c','--module','Hidden16','--native-export','Hidden16.Session','--native-export','Hidden16.Fault','--native-export','Hidden16.Sample','--native-export','Hidden16.Pair<f64>','--emit-interface',case/'leaf.asti',leaf,'-o',case/'leaf.o']);leaf.unlink()
		run([compiler,'-O'+levels[1],'-c','--module','Adapter16','--native-export','Adapter16.Facade','--import-module',case/'leaf.asti','--emit-interface',case/'middle.asti',middle,'-o',case/'middle.o']);middle.unlink();assert not leaf.exists() and not middle.exists()
		for name in ['leaf.asti','middle.asti']:
			text=(case/name).read_text();assert 'schema=gnu-x86_64-lp64-runtime-units/6' in text and '[foreign ' in text and 'this.seed' not in text and 'this.nested' not in text
		if levels==('0','0','0'):
			for stage in ['semantics','core','cfg','ssa','nabi','cabi']:run([compiler,'--import-module',case/'middle.asti','--dump-'+stage,consumer])
			trace=case/'adapter-opens.log';run(['strace','-f','-e','trace=openat,openat2','-o',trace,compiler,'--import-module',case/'middle.asti','--emit-class-source',consumer]);opens=trace.read_text();assert str(case/'leaf.asti') in opens and str(case/'middle.asti') in opens and str(case/'leaf.o') in opens and str(case/'middle.o') in opens;assert all(str(p) not in opens for p in sources if p.suffix=='.astra');assert str(leaf) not in opens and str(middle) not in opens;receipt['artifact_only_trace']=dict(path=str(trace),sha256=sha(trace))
			anchor=case/'anchor.astra';anchor.write_text('int anchor(){return 0;}\n')
			for label,old,new,diagnostic in [
				('prefix','name="opaque16"','name="different16"','foreign declaration/selection/member/bridge identity mismatch'),
				('member-name',r'[Foreign]\nSample amend',r'[Foreign(name="different")]\nSample amend','foreign declaration/selection/member/bridge identity mismatch'),
				('member-omitted',r'[Foreign]\nPair<f64> exchange',r'Pair<f64> exchange','foreign declaration/selection/member/bridge identity mismatch'),
				('error-code','errors="Hidden16.Fault=-1600"','errors="Hidden16.Fault=-1601"','foreign declaration/selection/member/bridge identity mismatch'),
				('bool-abi','bool_abi="c99"','bool_abi="other"','copied C bool channels require explicit bool_abi=c99'),
				('callback-owner','borrowed Callback<bool,bool>','Callback<bool,bool>','Callback'),
				('body','Sample amend(Sample input) {}','Sample amend(Sample input) {return input;}','native interface cannot contain executable implementation bodies')]:
				bad=case/('mutant-'+label);bad.mkdir();shutil.copyfile(case/'leaf.o',bad/'leaf.o');groups=helpers['metadata']((case/'leaf.asti').read_text());declarations=groups['abi']['declarations'];assert old in declarations;groups['abi']['declarations']=declarations.replace(old,new,1);groups['abi']['declarations_sha256']=hashlib.sha256(groups['abi']['declarations'].replace(r'\n','\n').encode()).hexdigest();(bad/'leaf.asti').write_text(helpers['reseal'](groups));run([compiler,'--import-module',bad/'leaf.asti','--dump-cabi',anchor],expected=1,contains=diagnostic)
			run([compiler,'--foreign-personalities=none','--import-module',case/'leaf.asti','--dump-cabi',anchor],expected=1,contains='foreign declaration/selection/member/bridge identity mismatch')
			bad=case/'mutant-schema-downgrade';bad.mkdir();shutil.copyfile(case/'leaf.o',bad/'leaf.o');groups=helpers['metadata']((case/'leaf.asti').read_text());groups['abi']['schema']='gnu-x86_64-lp64-typed-units/3';(bad/'leaf.asti').write_text(helpers['reseal'](groups));run([compiler,'--import-module',bad/'leaf.asti','--dump-cabi',anchor],expected=1,contains='unknown interface group')
		header=case/'native.h';header.write_text(run([compiler,'--import-module',case/'middle.asti','--emit-class-header',consumer]));adapter=case/'adapter.c';adapter.write_text(run([compiler,'--import-module',case/'middle.asti','--emit-class-source',consumer]));assert 'this.seed' not in adapter.read_text() and 'this.nested' not in adapter.read_text()
		probe=case/'header.c';probe.write_text('#include "native.h"\n#include "native.h"\n');run(['cc',*flags,'-fsyntax-only',probe]);run([compiler,'-O'+levels[2],'-c','--import-module',case/'middle.asti',consumer,'-o',case/'consumer.o']);run(['cc',*flags,'-O'+levels[2],'-c',adapter,'-o',case/'adapter.o'])
		binary=case/'client';run(['cc',*flags,'-O2',here/'foreign-unit-client.c',case/'leaf.o',case/'middle.o',case/'consumer.o',case/'adapter.o',runtime,'-o',binary]);run([binary],contains='PASS opaque foreign native units')
		if levels in [('0','0','0'),('2','2','2')]:run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',binary],contains='ERROR SUMMARY: 0 errors')
		receipt['products'][case.name]={p.name:sha(p) for p in [case/'leaf.o',case/'leaf.asti',case/'middle.o',case/'middle.asti',case/'adapter.o',case/'consumer.o',header,adapter,binary]}
	case=work/'native-only';case.mkdir();selected=[compiler,'--foreign-personalities=none'];leaf=case/'leaf.astra';middle=case/'middle.astra';consumer=case/'consumer.astra';leaf.write_bytes((here/'foreign-unit-leaf.astra').read_bytes());middle.write_bytes((here/'foreign-unit-middle.astra').read_bytes());consumer.write_bytes((here/'foreign-unit-consumer.astra').read_bytes())
	run([*selected,'-O2','-c','--module','Hidden16','--native-export','Hidden16.Session','--native-export','Hidden16.Fault','--native-export','Hidden16.Sample','--native-export','Hidden16.Pair<f64>','--emit-interface',case/'leaf.asti',leaf,'-o',case/'leaf.o']);leaf.unlink();run([*selected,'-O0','-c','--module','Adapter16','--native-export','Adapter16.Facade','--import-module',case/'leaf.asti','--emit-interface',case/'middle.asti',middle,'-o',case/'middle.o']);middle.unlink();run([*selected,'-O2','-c','--import-module',case/'middle.asti',consumer,'-o',case/'consumer.o']);symbols=run(['nm','-g','--defined-only',case/'leaf.o',case/'middle.o']);assert 'opaque16_create' not in symbols and 'opaque16_facade_create' not in symbols
	binary=case/'client';run(['cc',*flags,'-O2',here/'foreign-unit-native-client.c',case/'leaf.o',case/'middle.o',case/'consumer.o',runtime,'-o',binary]);run([binary],contains='PASS native-only opaque foreign declarations');dependencies=run(['ldd',binary]);assert 'gobject' not in dependencies and 'glib' not in dependencies;run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',binary],contains='ERROR SUMMARY: 0 errors');receipt['native_only']={p.name:sha(p) for p in [case/'leaf.o',case/'leaf.asti',case/'middle.o',case/'middle.asti',case/'consumer.o',binary]}
	receipt['status']='OPAQUE_FOREIGN_UNIQUE_C_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))


if __name__=='__main__':main(*sys.argv[1:])
