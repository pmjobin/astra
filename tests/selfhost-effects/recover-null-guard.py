#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A legal empty factory result becomes a fatal invalid-use guard when raised."""
import argparse
import json
import os
from pathlib import Path
import resource
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

SOURCE = '''owned Error make(bool empty) { if (empty) return null; var value = new Error("kept"); return move value; }
int main() { var value = make(true); try { throw move value; } catch (Error caught) { return 42; } }
'''


def no_core():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--version',required=True); p.add_argument('--component',type=Path,required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('recover_null_guard_paths',ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('null-guard-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources','tools') for path,expected in identity['identity'][group].items())
	source = leaf/'case.astra'; source.write_text(SOURCE); inputs = [source,ROOT/'lib/astra/base/errors.astra']
	def run(argv,name,expected):
		argv = list(map(str,argv)); start = time.monotonic(); r = bounded_run(argv,cwd=build,env=dict(os.environ,CCACHE_DISABLE='1'),preexec_fn=no_core,capture_output=True,timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name,argv=argv,exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); assert r.returncode == expected,(name,r.returncode,r.stdout[-1000:],r.stderr[-2000:]); return r
	c0 = build/'C0'; run([C0,'-'+a.mode,*inputs,'-o',c0],'C0-build',0); run([c0],'C0-null-throw-fatal',-4)
	ir = build/'Astra.ll'; run([a.component,'--native',ir,*inputs],'Astra-emit',0); run(['opt','-passes=verify','-disable-output',ir],'Astra-verify',0); optimized = build/'optimized.ll'; run(['opt','-passes=default<'+a.mode+'>','-S',ir,'-o',optimized],'Astra-optimize',0); run(['opt','-passes=verify','-disable-output',optimized],'Astra-optimized-verify',0); obj = build/'Astra.o'; exe = build/'Astra'; run(['llc','-filetype=obj','-'+a.mode,optimized,'-o',obj],'Astra-object',0); run(['cc','-no-pie',obj,'-o',exe],'Astra-link',0); run([exe],'Astra-null-throw-fatal',-4)
	(leaf/'result.json').write_text(json.dumps(dict(status='FATAL_NULL_THROW_GUARD',profile=a.mode,component_sha256=sha(a.component),source_sha256=sha(source),Astra_ELF_sha256=sha(exe),C0_ELF_sha256=sha(c0),Astra_raw_LLVM_sha256=sha(ir),Astra_exit=-4,C0_exit=-4,returning_effect_program_credit=0,limitation='Intentional LLVM trap/SIGILL before any null header load; no recoverable catch, returning-memory or fatal-unwind guarantee is claimed. Core dumps disabled for these owned child processes.'),indent=2)+'\n'); print(a.mode,'Astra and C0 null throw take the fatal guard',flush=True)


if __name__ == '__main__':
	main()
