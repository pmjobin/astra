#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A later bounds trap must preserve the earlier nested method's visible effect."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, sha

SOURCE = '''extern(C) int callplace_effect(int c);
class Device {
	int stamp;
	init() { this.stamp = 0; }
	int mark(int value) { int a = callplace_effect(65); this.stamp = this.stamp + 1; return value; }
	int combine(int a, int b) { int c = callplace_effect(66); return a + b; }
}
class Frame { owned Device child; init(owned Device child) { this.child = move child; } }
int main() { var child = new Device(); var frame = new Frame(move child); var values = new int[1]; return frame.child.combine(frame.child.mark(7), values[2]); }
'''


def main():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--version',default='v2'); a = p.parse_args()
	leaf = RUNTIME/('failure-'+a.version+'-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False); source = leaf/'order.astra'; source.write_text(SOURCE); commands = []; env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('LD_PRELOAD',None)
	def run(argv,name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=env,timeout=180)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	assert run([C0,'--check',source],'C0-check').returncode == 0
	observer = build/'observer.o'; observer_source = ROOT/'tests/selfhost-callplace/effect-observer.c'
	assert run(['gcc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',observer_source,'-o',observer],'observer').returncode == 0
	obj = build/'native.o'; native = build/'native'; oracle = build/'C0'
	assert run([a.component,'--classstorage-emit-obj',a.mode,obj,source],'native-object').returncode == 0
	assert run(['gcc',obj,observer,'-o',native],'native-link').returncode == 0
	assert run([C0,'-'+a.mode,source,'--link-object',observer,'-o',oracle],'C0-build').returncode == 0
	results = {}
	for label,exe in [('native',native),('C0',oracle)]:
		r = run([exe],label+'-execute'); assert r.returncode in (-4,132) and r.stdout == b'A',(label,r.returncode,r.stdout,r.stderr)
		results[label] = dict(exit=r.returncode,stdout_hex=r.stdout.hex(),ELF_sha256=sha(exe))
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',component_sha256=sha(a.component),observer_sha256=sha(observer_source),source_sha256=sha(source),results=results,commands=commands,limitation='Fatal bounds-trap ordering only: the qualified C0 and native LLVM trap both use SIGILL. This is not recoverable throws Error, and no normal-return leak claim is made for an aborted process.'),indent=2)+'\n'); print(a.mode,'INNER_EFFECT_RETAINED OUTER_NOT_EXECUTED')


if __name__ == '__main__':
	main()
