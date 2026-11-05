#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Distinguish unavailable arguments from genuine nominal and arity conflicts."""
import json
import argparse
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha

PREFIX = '''struct SymbolId { int index; }
struct OtherId { int index; }
class Store {
	int stamp;
	init() { this.stamp = 0; }
	SymbolId id(SymbolId value) { return value; }
	int slot(SymbolId value) { return value.index; }
}
class Holder {
	owned Store child;
	init(owned Store child) { this.child = move child; }
}
SymbolId identity(SymbolId value) { return value; }
'''
CASES = {
	'valid-known-nested': ('return graph.slot(identity(id));',0,0),
	'wrong-nominal': ('OtherId wrong = {index = 7}; return graph.slot(wrong);',1,1),
	'wrong-arity': ('return graph.slot(id, id);',1,1),
	'unavailable-nested-receiver': ('return graph.slot(root.child.id(id));',0,1),
	'unavailable-local-initializer': ('var bad = identity(root.child.id(id)); return graph.slot(bad);',0,1),
}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v2'); a = p.parse_args(); assert a.version.replace('-','').isalnum()
	leaf = RUNTIME/('diagnostic-controls-'+a.version); leaf.mkdir(exist_ok=False); commands = []; rows = []
	component = read(RUNTIME/'initial.json')['products']['O0']['path']; observer = BUILD/'diagnosis-v3/diagnose-O0'
	for name,(body,c0_exit,native_exit) in CASES.items():
		path = leaf/(name+'.astra'); path.write_text(PREFIX+'int main() { var graph = new Store(); var child = new Store(); var root = new Holder(move child); SymbolId id = {index = 7}; '+body+' }\n')
		for label,argv,expected in [('parse',[C0,'--dump-syntax',path],0),('C0',[C0,'--check',path],c0_exit),('native',[component,'--classstorage-admit','O0',BUILD/'unused',path],native_exit),*([('observer',[observer,path],0)] if native_exit == 1 else [])]:
			start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'-'+label+'.time'),*map(str,argv)],cwd=BUILD,capture_output=True,timeout=60)
			(leaf/(name+'-'+label+'.stdout')).write_bytes(r.stdout); (leaf/(name+'-'+label+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(name=name+'-'+label,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
			assert r.returncode == expected,(name,label,r.returncode,r.stderr.decode()[:1500],r.stdout.decode()[:500])
		rows.append(dict(name=name,source_sha256=sha(path),C0_exit=c0_exit,native_exit=native_exit,classification='Parse/type observations only; not counted as new executable programs or mutation categories.'))
		print(name,c0_exit,native_exit,flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='DISTINGUISHING_CONTROLS_PASS',rows=rows,commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
