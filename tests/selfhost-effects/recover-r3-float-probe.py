#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent bit-preserving callers for unchanged emitted FP carrier bodies.

The LLVM adapter is ABI-only evidence and receives no native-source credit.
"""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

PROGRAMS = {
	'f32': 'f32 make(f32 value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value; }\nint main() { return 0; }\n',
	'f64': 'f64 make(f64 value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return value; }\nint main() { return 0; }\n',
	'record': 'struct Mixed { f32 fraction; int value; f64 wide; }\nMixed make(bool fail) throws Error { Mixed value = {fraction = -0.0f, value = 42, wide = 0.5d}; if (fail) { throw new Error("kept"); } return value; }\nint main() { return 0; }\n',
	'buffer': 'owned f64[] make(bool fail) throws Error { var value = new f64[2]; if (fail) { throw new Error("kept"); } return move value; }\nint main() { return 0; }\n'
}


def adapter(raw, shape, bits, failure):
	text = raw.decode(); entries = re.findall(r'define internal fastcc ptr @([\w.]+)\(ptr[^\n]*, (?:float|double|i1)', text); assert len(entries) == 1, entries
	text, count = re.subn(r'(define i32 )@main\(', r'\1@source.main(', text); assert count in (0, 1)
	carrier = 'float' if shape == 'f32' else 'double' if shape == 'f64' else '{float,i32,double}' if shape == 'record' else '{ptr,i32}'
	poison = 'bitcast (i32 305419896 to float)' if shape == 'f32' else 'bitcast (i64 1311768467463790320 to double)' if shape == 'f64' else '{float 1.0, i32 999, double 2.0}' if shape == 'record' else '{ptr inttoptr (i64 305419896 to ptr), i32 999}'
	argument = ('float bitcast (i32 '+str(bits)+' to float), ' if shape == 'f32' else 'double bitcast (i64 '+str(bits)+' to double), ' if shape == 'f64' else '')+'i1 '+str(failure).lower()
	if shape in ('f32', 'f64'):
		integer = 'i32' if shape == 'f32' else 'i64'; expected = (305419896 if shape == 'f32' else 1311768467463790320) if failure else bits
		check = '  %bits = bitcast '+carrier+' %got to '+integer+'\n  %cell.ok = icmp eq '+integer+' %bits, '+str(expected)+'\n'
	elif shape == 'record':
		check = '  %a = extractvalue '+carrier+' %got, 0\n  %b = extractvalue '+carrier+' %got, 1\n  %c = extractvalue '+carrier+' %got, 2\n  %a.bits = bitcast float %a to i32\n  %c.bits = bitcast double %c to i64\n  %a.ok = icmp eq i32 %a.bits, '+('1065353216' if failure else '2147483648')+'\n  %b.ok = icmp eq i32 %b, '+('999' if failure else '42')+'\n  %c.ok = icmp eq i64 %c.bits, '+('4611686018427387904' if failure else '4602678819172646912')+'\n  %ab.ok = and i1 %a.ok, %b.ok\n  %cell.ok = and i1 %ab.ok, %c.ok\n'
	else:
		check = '  %data = extractvalue {ptr,i32} %got, 0\n  %count = extractvalue {ptr,i32} %got, 1\n  %data.ok = icmp '+('eq' if failure else 'ne')+' ptr %data, inttoptr (i64 305419896 to ptr)\n  %count.ok = icmp eq i32 %count, '+('999' if failure else '2')+'\n  %cell.ok = and i1 %data.ok, %count.ok\n'
	cleanup = '  %descriptor = load ptr, ptr %error\n  %destroy.cell = getelementptr {ptr,ptr,ptr}, ptr %descriptor, i32 0, i32 1\n  %destroy = load ptr, ptr %destroy.cell\n  call fastcc void %destroy(ptr %error)\n  call void @free(ptr %error)\n' if failure else '  call void @free(ptr %data)\n' if shape == 'buffer' else ''
	main = '\ndefine i32 @main() {\nentry:\n  %slot = alloca '+carrier+'\n  store '+carrier+' '+poison+', ptr %slot\n  %error = call fastcc ptr @'+entries[0]+'(ptr %slot, '+argument+')\n  %channel.ok = icmp '+('ne' if failure else 'eq')+' ptr %error, null\n  br i1 %channel.ok, label %inspect, label %bad\ninspect:\n  %got = load '+carrier+', ptr %slot\n'+check+'  br i1 %cell.ok, label %done, label %bad\ndone:\n'+cleanup+'  ret i32 42\nbad:\n  ret i32 4\n}\n'
	return (text+main).encode()


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); p.add_argument('--oracle-only', action='store_true'); a = p.parse_args(); assert a.version.isalnum() and (a.component is not None or a.oracle_only)
	paths = load_module('r3_float_probe_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r3-float-probe-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	if not a.oracle_only:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name, expected=0):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (name, r.returncode, r.stdout[-1200:], r.stderr[-2400:]); return r
	for shape, text in PROGRAMS.items():
		source = leaf/(shape+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']; astra = build/(shape+'-Astra-original.ll')
		if not a.oracle_only: run([a.component, '--native', astra, *inputs], shape+'-Astra-emit')
		oracle = run([C0, '-O0', '--dump-llvm', *inputs], shape+'-C0-emit'); c0 = build/(shape+'-C0-original.ll'); c0.write_bytes(oracle.stdout)
		patterns = [2147483648, 2143363909] if shape == 'f32' else [9223372036854775808, 9221120237041095220] if shape == 'f64' else [0]
		for producer, original in ([('C0', c0)] if a.oracle_only else [('Astra', astra), ('C0', c0)]):
			for bits in patterns:
				for failure in (False, True):
					name = shape+'-'+producer+'-'+str(bits)+('-error' if failure else '-success'); raw = build/(name+'.ll'); raw.write_bytes(adapter(original.read_bytes(), shape, bits, failure)); run(['opt', '-passes=verify', '-disable-output', raw], name+'-verify'); optimized = build/(name+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', raw, '-o', optimized], name+'-optimize'); run(['opt', '-passes=verify', '-disable-output', optimized], name+'-optimized-verify'); obj = build/(name+'.o'); exe = build/name; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object'); run(['cc', '-no-pie', obj, '-o', exe], name+'-link'); run([exe], name+'-execute', 42); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-memory', 42); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
					rows.append(dict(shape=shape, producer=producer, input_bits=bits, error=failure, original_LLVM_sha256=sha(original), adapter_LLVM_sha256=sha(raw), ELF_sha256=sha(exe))); print(a.mode, name, 'bitwise carrier/poison observation; ABI-only', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_FP_CARRIER_BITS_ONLY', profile=a.mode, component_sha256=None if a.oracle_only else sha(a.component), Astra_effect_ELFs=0, results=rows, limitation='Handwritten LLVM callers only. Original emitted bodies preserved. NaN payload, signed-zero and mixed-layout observations are independent ABI evidence, never additional Astra-native source executions.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
