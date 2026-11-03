#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe retained full sources and an exact pre-task syntax subsystem slice."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from run import decode


def main():
	p=argparse.ArgumentParser()
	for name in ('compiler','build','runtime','frozen'):
		p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--second-profile-build',type=Path)
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	rows=[]
	def run(argv,name,expected=None):
		start=time.monotonic()
		r=subprocess.run(['/usr/bin/time','-v','-o',str(a.runtime/(name+'.time')),*map(str,argv)],capture_output=True,cwd=a.build)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start))
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
		if expected is not None: assert r.returncode==expected,(name,r.stderr.decode()[:2000])
		return r.stdout
	root=a.frozen/'compiler-frozen'
	parts=[]
	for name,start,end in [('compiler/syntax/model.astra',b'struct SyntaxNodeId',b'enum SyntaxKind'),('compiler/syntax/arena-support.astra',b'SyntaxSpan syntax_empty_span()',b'SyntaxSpan syntax_cover(')]:
		data=(root/name).read_bytes()
		first,last=data.index(start),data.index(end)
		parts.append(dict(path=name,start=first,end=last,source_sha256=hashlib.sha256(data).hexdigest(),slice_sha256=hashlib.sha256(data[first:last]).hexdigest()))
		path=a.runtime/(Path(name).stem+'-slice.astra')
		path.write_bytes(data[first:last])
		parts[-1]['input']=str(path)
	harness=a.runtime/'slice-main.astra'
	harness.write_text('int main(){var a=syntax_empty_span();SyntaxSourceId source={index=7};var b=syntax_span(source,3,9);if(a.source.index!=0||b.source.index!=7||b.start!=3||b.end!=9){return 1;}return 0;}\n')
	paths=[*[x['input'] for x in parts],str(harness)]
	(a.runtime/'slice-origins.json').write_text(json.dumps(parts,indent=2)+'\n')
	old=json.loads((a.frozen/'compiler-inputs.json').read_text())
	compiler_paths=[p for p in old['paths'] if '/tests/' not in p]
	run([old['tool'],'--flow',*compiler_paths],'frozen-before',3)
	before=run([old['tool'],'--flow',*paths],'slice-before',3)
	run([a.compiler,'--check',*paths],'slice-c0',0)
	observations=[]
	for mode in ('O0','O2'):
		product_dir=a.second_profile_build if mode=='O2' and a.second_profile_build else a.build
		exe=product_dir/('astra-flow-'+mode)
		d=run([exe,'--admit',*paths],'slice-'+mode,0)
		assert all(decode(d)['proofs'].values())
		observations.append(d)
		product=a.build/('syntax-slice-'+mode)
		run([a.compiler,'-'+mode,*paths,'-o',product],'slice-compile-'+mode,0)
		run([product],'slice-execute-'+mode,0)
		run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',product],'slice-memory-'+mode,0)
	assert observations[0]==observations[1]
	prior=decode(before)['proofs']
	after=decode(observations[0])['proofs']
	(a.runtime/'slice-ledger.json').write_text(json.dumps(dict(closed_original=[list(k) for k,v in prior.items() if not v and after.get(k)==1],new=[list(k) for k,v in after.items() if v and k not in prior],absent=[list(k) for k in prior if k not in after]),indent=2)+'\n')
	current=json.loads((a.build/'astra-flow-O0.identity.json').read_text())['identity']['sources']
	for label,paths in [('frozen',compiler_paths),('current',[x for x in current if x.endswith('.astra') and '/tests/' not in x])]:
		observations=[]
		for mode in ('O0','O2'):
			product_dir=a.second_profile_build if mode=='O2' and a.second_profile_build else a.build
			data=run([product_dir/('astra-flow-'+mode),'--admit',*paths],label+'-'+mode,3)
			o=decode(data)
			assert not any(o['proofs'].values()) and not o['errors'],(label,mode,o['errors'])
			observations.append(data)
		assert observations[0]==observations[1],label
	print('PASS syntax slice and full-source deferral observations')


if __name__=='__main__':
	main()
