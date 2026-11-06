#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent parse-valid type/ownership negatives with preserved output destinations."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha

PREFIX = '''struct SymbolId { int index; }
struct OtherId { int index; }
class Store {
	int value;
	init() { this.value = 1; }
	int slot(SymbolId value) { return value.index; }
	int read(int value) { return this.value + value; }
}
class Holder { owned Store child; init(owned Store child) { this.child = move child; } }
int consume(owned Holder value) { return 0; }
'''
GENERIC_PREFIX = '''struct SymbolId { int index; }
struct OtherId { int index; }
class Echo<T> { init() {} U echo<U>(U value) { return value; } }
class Holder { owned Echo<SymbolId> child; init(owned Echo<SymbolId> child) { this.child = move child; } }
'''
GENERIC_SETUP = 'var child = new Echo<SymbolId>(); var root = new Holder(move child); SymbolId id = {index = 7}; '
SETUP = 'var child = new Store(); var root = new Holder(move child); SymbolId id = {index = 7}; '
CASES = {
	'wrong-place-nominal': 'OtherId wrong = {index = 7}; return root.child.slot(wrong);',
	'wrong-place-arity': 'return root.child.slot(id, id);',
	'fake-nongeneric-promotion': 'return root.child.slot<int>(id);',
	'moved-receiver-root': 'var other = move root; return root.child.slot(id);',
	'released-receiver-root': 'release root; return root.child.slot(id);',
	'containing-owner-consumed-in-argument': 'return root.child.read(consume(move root));',
	'generic-wrong-nominal': 'OtherId wrong = {index = 7}; var result = root.child.echo<SymbolId>(wrong); return result.index;',
	'generic-wrong-arity': 'var result = root.child.echo<int, bool>(7); return result;',
	'nested-wrong-result': 'var result = root.child.echo<OtherId>(id); return result.index;',
	'duplicate-owner-after-call': 'int n = root.child.slot(id); owned Holder other = root; return n;',
}


def main():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('negative-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False); commands = []; rows = []
	def run(argv,name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'),timeout=180)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	for name,body in CASES.items():
		path = leaf/(name+'.astra'); generic = name.startswith('generic-') or name == 'nested-wrong-result'
		path.write_text((GENERIC_PREFIX if generic else PREFIX)+'int main() { '+(GENERIC_SETUP if generic else SETUP)+body+' }\n')
		assert run([C0,'--parse',path],name+'-parse').returncode == 0
		oracle = run([C0,'--check',path],name+'-C0'); assert oracle.returncode == 1,(name,oracle.stderr.decode())
		admit = run([a.component,'--classstorage-admit',a.mode,build/'unused',path],name+'-native'); assert admit.returncode in (1,3),(name,admit.stdout[:500])
		dest = build/(name+'.o'); dest.write_bytes(b'preserved negative destination\n'); original = sha(dest)
		assert run([a.component,'--classstorage-emit-obj',a.mode,dest,path],name+'-writer').returncode == 2 and sha(dest) == original
		rows.append(dict(name=name,source_sha256=sha(path),C0_diagnostic=oracle.stderr.decode(),native_diagnostic=admit.stdout.decode(),native_exit=admit.returncode,destination_sha256=original)); print(a.mode,name,'REFUSED',flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,cases=rows,commands=commands,limitation='Source negatives are separate from substantive model/physical mutations.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
