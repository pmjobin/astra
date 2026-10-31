#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Declared GObject metadata, selected members and static SDK refusal controls."""
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
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='declared-gobject-policies-',dir=output));source=Path(__file__).with_name('gobject-scalars.astra');base=source.read_text();receipt=dict(scope='declared GObject profile/member/target prerequisites; native/GI execution separately qualified',compiler_sha256=sha(compiler),recipe_sha256=sha(Path(__file__)),source_sha256=sha(source),checks=[])
	def run(command,expected=0,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,expected_exit=expected,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==expected and contains in p.stdout+p.stderr,receipt['checks'][-1];assert 'CRITICAL' not in p.stderr;return p.stdout
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:run([compiler,'--dump-'+stage,source])
	for option in ['--emit-gobject-header','--emit-gobject-source']:
		first=run([compiler,option,source]);assert first==run([compiler,option,source]);assert 'try_native_only' not in first and 'try_glib_only' in first
	native=work/'native.h';native.write_text(run([compiler,'--emit-class-header',source]));probe=work/'public.c';probe.write_text('#include "native.h"\nvoid *probe = (void *)&go16_native_glib_only;\n');run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fsyntax-only',probe],expected=1,contains='go16_native_glib_only');probe.write_text('#define ASTRA_FOREIGN16_INTERNAL\n#include "native.h"\nvoid *probe = (void *)&go16_native_glib_only;\n');run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fsyntax-only',probe])
	for name,text in {
		'unique-root':base.replace('[Shared]',''),
		'c-only-child-root':base.replace('[GObjectExport(type="Astra16Item",namespace="Astra16",version="2.3",profile="declarations-v1")]',''),
		'unselected-owned-property':base.replace('[Foreign]property owned Item current','property owned Item current'),
		'owned-property-with-setter':base.replace('var result=clone_item(this.child);return move result;}}','var result=clone_item(this.child);return move result;}set(owned Item input){this.child=move input;}}'),
		'bad-type-name':base.replace('type="Astra16Session"','type="astra16Session"'),
		'wrong-type-namespace':base.replace('namespace="Astra16"','namespace="Other"'),
		'empty-version':base.replace('version="2.3"','version=""'),
		'malformed-version':base.replace('version="2.3"','version="2..3"'),
		'missing-version':base.replace(',version="2.3"',''),
		'missing-gobject-profile':base.replace('version="2.3",profile="declarations-v1"','version="2.3"'),
		'floating-policy':base.replace('version="2.3",profile=', 'version="2.3",floating="true",profile='),
		'missing-c-bool-convention':base.replace(',bool_abi="c99"',''),
		'unknown-member-personality':base.replace('personalities="gobject"','personalities="unknown"'),
		'duplicate-member-personality':base.replace('personalities="gobject"','personalities="gobject,gobject"'),
		'invalid-property-name':base.replace('[Foreign]property int count','[Foreign(name="_count")]property int count'),
		'duplicate-gtype':base+'[Shared][CExport(name="duplicate16",profile="declarations-v1")][GObjectExport(type="Astra16Session",namespace="Astra16",version="4.0",profile="declarations-v1")]class Duplicate{[Foreign]init(){}}',
	}.items():
		assert text!=base;unit=work/(name+'.astra');unit.write_text(text);run([compiler,'--dump-semantics',unit],expected=1,contains='error:')
	unit=work/'symbol-collision.astra';unit.write_text(base.replace('name="go16_native"','name="astra16_session"').replace('[Foreign(personalities="c")]int native_only','[Foreign(name="get_type",personalities="c")]int native_only'));run([compiler,'--emit-gobject-header',unit],expected=1,contains='symbol collision')
	run([compiler,'--target=x86_64-w64-windows-gnu','-c',source,'-o',work/'wrong-target.o'],expected=1,contains='GObjectExport requires')
	receipt['status']='DECLARED_GOBJECT_POLICY_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))


if __name__=='__main__':main(*sys.argv[1:])
