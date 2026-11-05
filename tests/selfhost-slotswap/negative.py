#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Parse-valid source controls for record eligibility, loans and live storage."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha

RECORD = 'struct Datum { int value; }\n'
BOX = RECORD+'class Holder { owned Datum[] rows; owned Datum[] spare; init() { this.rows = new Datum[2]; this.spare = new Datum[3]; } int turn() { swap(this.rows, this.spare); return 0; } }\n'
CASES = {
	'nominal-record-canonical-conflict': RECORD+'struct Other { int value; } int main() { var a = new Datum[2]; var b = new Other[2]; swap(a, b); return 0; }',
	'nested-owner-element': 'class Payload { init() {} } struct Indirect { owned Payload payload; } int main() { var a = new Indirect[2]; var b = new Indirect[3]; swap(a, b); return 0; }',
	'symbolic-record-identity-conflict': RECORD+'void change<T,U>(owned T[] a, owned U[] b) { swap(a,b); } int main() { var a = new Datum[2]; var b = new Datum[3]; change<Datum,Datum>(move a,move b); return 0; }',
	'non-owning-record-parameter': RECORD+'void change(Datum[] a, owned Datum[] b) { swap(a,b); } int main() { var a = new Datum[2]; var b = new Datum[3]; change(a,move b); return 0; }',
	'moved-record-owner': RECORD+'int main() { var a = new Datum[2]; var b = new Datum[3]; var c = move a; swap(a,b); return len(c); }',
	'released-record-owner': RECORD+'int main() { var a = new Datum[2]; var b = new Datum[3]; release a; swap(a,b); return 0; }',
	'surviving-record-view': RECORD+'int main() { var a = new Datum[2]; var b = new Datum[3]; Datum[] view = a; swap(a,b); return view[0].value; }',
	'pending-containing-record-loan': BOX+'int take(Datum[] rows, int n) { return n; } int change(borrowed Holder a, borrowed Holder b) { return take(a.rows,b.turn()); } int main() { var box = new Holder(); return change(box,box); }',
	'uninitialized-record-field': RECORD+'class Partial { owned Datum[] a; owned Datum[] b; init() { this.a = new Datum[2]; swap(this.a,this.b); this.b = new Datum[3]; } } int main() { var box = new Partial(); return 0; }',
	'record-element-is-not-owner-slot': RECORD+'int main() { var a = new Datum[2]; var b = new Datum[3]; swap(a[0],b[0]); return 0; }',
}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('negative-v2-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	commands = []; results = []; env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None)
	def run(argv,name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=env,timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	valid = leaf/'valid.astra'; valid.write_text(RECORD+'int main() { var a = new Datum[2]; var b = new Datum[3]; swap(a,b); return len(a); }\n')
	output = build/'preserved.o'; assert run([a.component,'--classstorage-emit-obj',a.mode,output,valid],'valid-twin').returncode == 0; original = sha(output)
	for name,source in CASES.items():
		path = leaf/(name+'.astra'); path.write_text(source+'\n')
		assert run([C0,'--dump-syntax',path],name+'-parse').returncode == 0,name
		c = run([C0,'--check',path],name+'-C0'); n = run([a.component,'--classstorage-emit-obj',a.mode,output,path],name+'-native')
		assert c.returncode == 1 and n.returncode in (1,2,3) and sha(output) == original,(name,c.returncode,n.returncode)
		assert run([a.component,'--classstorage-emit-obj',a.mode,output,valid],name+'-restored-twin').returncode == 0 and sha(output) == original
		results.append(dict(category=name,source_sha256=sha(path),C0_exit=c.returncode,C0_diagnostic=c.stderr.decode(),native_exit=n.returncode,native_diagnostic=n.stderr.decode(),parser_accepted=True,output_preserved=True,valid_twin_restored=True)); print(a.mode,name,'PARSE_VALID C0/NATIVE_REJECTED',flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),mutations=results,commands=commands,recipe_sha256=sha(__file__),limitation='Actual diagnostics retain stage attribution; an earlier bounded element-domain refusal is not credited as a later loan or swap proof.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
