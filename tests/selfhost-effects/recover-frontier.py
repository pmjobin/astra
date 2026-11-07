#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Concrete C0-qualified source attempts at remaining permitted shape boundaries."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus():
	catch = 'catch (Error caught) { if (caught.message == "kept") return 42; return 4; }'
	return {
		'checked-receiver-scalar': 'class Parcel { init() {} int leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } return 17; } }\nint main() { var value = new Parcel(); try { return value.leaf(true); } '+catch+' }\n',
		'checked-receiver-void': 'class Parcel { init() {} void leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } } }\nint main() { var value = new Parcel(); try { value.leaf(true); return 3; } '+catch+' }\n',
		'closed-generic-checked-call': 'int leaf<T>(int value) throws Error { if (value == 0) { throw new Error("kept"); } return value; }\nint main() { try { return leaf<int>(0); } '+catch+' }\n',
		'Class-field-factory': 'class Parcel { int value; init(int value) { this.value = value; } }\nowned Parcel make(bool fail) throws Error { var value = new Parcel(42); if (fail) { throw new Error("kept"); } return move value; }\nint main() { try { var value = make(false); return value.value; } catch (Error caught) { return 4; } }\n',
		'derived-Error-field': 'class Detail : Error { int code; init(string message, int code) : base(message) { this.code = code; } }\nint main() { try { throw new Detail("kept", 42); } '+catch+' }\n',
		'derived-literal-constructor': 'class SourceBoundsError : Error { init() : base("invalid source span or offset") {} }\nint main() { try { throw new SourceBoundsError(); } catch (Error caught) { if (caught.message == "invalid source span or offset") return 42; return 4; } }\n',
		'floating-scalar-result': 'f64 leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } return 0.5; }\nint main() { try { if (leaf(false) == 0.5) return 42; return 3; } catch (Error caught) { return 4; } }\n',
		'floating-buffer-result': 'owned f32[] make(bool fail) throws Error { var value = new f32[2]; if (fail) { throw new Error("kept"); } return move value; }\nint main() { try { var value = make(false); return len(value) + 40; } catch (Error caught) { return 4; } }\n'
	}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--version',required=True); p.add_argument('--component',type=Path); p.add_argument('--oracle-only',action='store_true'); a = p.parse_args(); assert a.version.isalnum(); assert a.oracle_only or a.component
	paths = load_module('recover_frontier_paths',ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('frontier-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources','tools') for path,expected in identity['identity'][group].items())
	def run(argv,name):
		argv = list(map(str,argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*argv],cwd=build,env=dict(os.environ,CCACHE_DISABLE='1'),capture_output=True,timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name,argv=argv,exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	for name,text in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source,ROOT/'lib/astra/base/errors.astra']; c0 = build/(name+'-C0'); r = run([C0,'-'+a.mode,*inputs,'-o',c0],name+'-C0-build'); assert r.returncode == 0,(name,r.stderr[-2000:]); assert run([c0],name+'-C0-execute').returncode == 42; memory = run(['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',c0],name+'-C0-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		if a.oracle_only:
			rows.append(dict(name=name,source_sha256=sha(source),C0_ELF_sha256=sha(c0),C0_actual_execution=42,Astra_emitted=None,Astra_actual_execution=None)); (leaf/'result.json').write_text(json.dumps(dict(status='C0_FRONTIER_ORACLE_ONLY',profile=a.mode,component_sha256=None,programs=rows),indent=2)+'\n'); print(a.mode,name,'independent C0 only',flush=True); continue
		target = build/(name+'.ll'); target.write_text('Source frontier destination sentinel\n'); before = sha(target); attempt = run([a.component,'--native',target,*inputs],name+'-Astra-native-attempt'); emitted = attempt.returncode == 0
		if emitted:
			assert run(['opt','-passes=verify','-disable-output',target],name+'-Astra-verify').returncode == 0; obj = build/(name+'.o'); exe = build/name; assert run(['llc','-filetype=obj','-'+a.mode,target,'-o',obj],name+'-Astra-object').returncode == 0; assert run(['cc','-no-pie',obj,'-o',exe],name+'-Astra-link').returncode == 0; assert run([exe],name+'-Astra-execute').returncode == 42
		else: assert sha(target) == before
		rows.append(dict(name=name,source_sha256=sha(source),C0_ELF_sha256=sha(c0),C0_actual_execution=42,Astra_emitted=emitted,Astra_actual_execution=42 if emitted else None,Astra_exit=attempt.returncode,destination_preserved=not emitted,stdout=attempt.stdout.decode(errors='replace')[:4000],stderr=attempt.stderr.decode(errors='replace')[:4000])); (leaf/'result.json').write_text(json.dumps(dict(status='SOURCE_FRONTIER_ATTEMPTS',profile=a.mode,component_sha256=sha(a.component),programs=rows,limitation='C0-only executions do not satisfy Astra runtime gates. Refusals identify remaining source/stage implementation boundaries and preserve output destinations.'),indent=2)+'\n'); print(a.mode,name,'Astra executed' if emitted else 'Astra deferred before native output',flush=True)


if __name__ == '__main__':
	main()
