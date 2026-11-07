#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Keep Class acquisition exactly within independently checked C0 rules."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus():
	box = 'class Parcel { init() {} }\n'
	return [
		('null-Class-local',False,box+'int main() { owned Parcel value = null; return 42; }\n'),
		('null-Error-local',False,'int main() { owned Error value = null; return 42; }\n'),
		('Class-alias-local',False,box+'int main() { var first = new Parcel(); owned Parcel second = first; return 42; }\n'),
		('typed-parenthesized-construction',False,box+'int main() { owned Parcel value = (new Parcel()); return 42; }\n'),
		('Class-construction-return',False,box+'owned Parcel make() { return new Parcel(); }\nint main() { var value = make(); return 42; }\n'),
		('Error-construction-return',False,'owned Error make() { return new Error("kept"); }\nint main() { var value = make(); return 42; }\n'),
		('inferred-parenthesized-construction',True,box+'int main() { var value = (new Parcel()); return 42; }\n'),
		('heap-Class-local-move',True,box+'int main() { var first = new Parcel(); owned Parcel second = move first; return 42; }\n'),
		('heap-Error-local-move',True,'int main() { var first = new Error("kept"); owned Error second = move first; return 42; }\n'),
		('nullable-Class-factory-local',True,box+'owned Parcel make(bool empty) throws Error { if (empty) return null; var value = new Parcel(); return move value; }\nint main() { try { var value = make(true); return 42; } catch (Error caught) { return 4; } }\n'),
		('nullable-Error-factory-local',True,'owned Error make(bool empty) { if (empty) return null; var value = new Error("kept"); return move value; }\nint main() { var value = make(true); return 42; }\n')
	]


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--version',required=True); p.add_argument('--component',type=Path); p.add_argument('--oracle-only',action='store_true'); a = p.parse_args(); assert a.version.isalnum(); assert a.oracle_only or a.component
	paths = load_module('recover_class_policy_paths',ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('class-policy-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources','tools') for path,expected in identity['identity'][group].items())
	def run(argv,name):
		argv = list(map(str,argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*argv],cwd=build,env=dict(os.environ,CCACHE_DISABLE='1'),capture_output=True,timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name,argv=argv,exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	for name,admitted,text in corpus():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source,ROOT/'lib/astra/base/errors.astra']; c0 = build/(name+'-C0'); r = run([C0,'-'+a.mode,*inputs,'-o',c0],name+'-C0-compile'); assert (r.returncode == 0) == admitted,(name,r.returncode,r.stderr[-2000:]); row = dict(name=name,admitted=admitted,source_sha256=sha(source),C0_exit=r.returncode)
		if admitted:
			assert run([c0],name+'-C0-execute').returncode == 42; memory = run(['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',c0],name+'-C0-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		if not a.oracle_only:
			target = build/(name+'.ll'); target.write_text('Class policy boundary sentinel\n'); before = sha(target); r = run([a.component,'--native',target,*inputs],name+'-Astra-emit'); assert (r.returncode == 0) == admitted,(name,r.returncode,r.stdout[-2000:],r.stderr[-2000:]); row['Astra_exit'] = r.returncode
			if admitted:
				assert run(['opt','-passes=verify','-disable-output',target],name+'-Astra-verify').returncode == 0; obj = build/(name+'.o'); exe = build/name; assert run(['llc','-filetype=obj','-'+a.mode,target,'-o',obj],name+'-Astra-object').returncode == 0; assert run(['cc','-no-pie',obj,'-o',exe],name+'-Astra-link').returncode == 0; assert run([exe],name+'-Astra-execute').returncode == 42; memory = run(['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',exe],name+'-Astra-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row['Astra_ELF_sha256'] = sha(exe)
			else: assert sha(target) == before; row['destination_preserved'] = True
		rows.append(row); print(a.mode,name,'C0 agrees with expected policy',flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_CLASS_POLICY_ONLY' if a.oracle_only else 'CLASS_POLICY_AND_NATIVE_CONTROLS',profile=a.mode,component_sha256=sha(a.component) if a.component else None,programs=rows,limitation='Boundary and positive controls are separate from the primary distinct-source qualification counts.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
