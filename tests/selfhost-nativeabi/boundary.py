#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Uncounted literal-bit, void/zero-argument C and physical-symbol controls."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-llvm'))
from oracle import memory

SOURCE = 'extern(C) void c_event(int value);export(C) void astra_event(int value){c_event(value);}export(C) int astra_zero(){return 7;}export(C) f32 astra_tiny(){return 1.4012984643248170709237295832899161312802619418765e-45f;}export(C) f64 astra_precise(){return 1.0000000000000002d;}export(C) f64 astra_negative_zero(){return -0.0d;}\n'
WITNESS = '''#include <stdint.h>
#include <string.h>
static int32_t event;
void c_event(int32_t value){event=value;}
extern void astra_event(int32_t);
extern int32_t astra_zero(void);
extern float astra_tiny(void);
extern double astra_precise(void),astra_negative_zero(void);
int main(void){
    uint32_t small;uint64_t precise,zero;
    float x=astra_tiny();double y=astra_precise(),z=astra_negative_zero();
    memcpy(&small,&x,sizeof small);memcpy(&precise,&y,sizeof precise);memcpy(&zero,&z,sizeof zero);
    astra_event(42);
    return event!=42||astra_zero()!=7||small!=1||precise!=UINT64_C(0x3ff0000000000001)||zero!=UINT64_C(0x8000000000000000);
}
'''


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'build', 'runtime', 'inputs'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime, a.inputs))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True); a.inputs.mkdir(parents=True, exist_ok=True)
	commands = []
	def frozen(name, text):
		path = a.inputs/name
		if path.exists():
			assert path.read_bytes() == text.encode()
		else:
			path.write_text(text)
		return path
	def run(argv, name, expected=0):
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), capture_output=True, cwd=a.build, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-2000:])
		return r
	source = frozen('literal-and-void.astra', SOURCE); witness = frozen('literal-and-void.c', WITNESS)
	obj = a.build/'literal-and-void.o'; c0 = a.build/'literal-and-void.C0.o'; companion = a.build/'witness.o'
	run([a.component, '--emit-obj', a.mode, obj, source], 'native-emit')
	run([a.component, '--llvm-raw', a.mode, a.runtime/'literal-and-void.ll', source], 'native-raw')
	run([a.component, '--abi-plan', a.mode, a.runtime/'unused', source], 'native-plan')
	run([a.compiler, '-'+a.mode, '-c', source, '-o', c0], 'C0-emit')
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-include', ROOT/'tests/selfhost-nativeabi/target.h', '-c', witness, '-o', companion], 'C-compile')
	memories = {}
	for label, application in [('native', obj), ('C0', c0)]:
		exe = a.build/(label+'.exe'); run(['gcc', application, companion, '-o', exe], label+'-link')
		r = run([exe], label+'-execute'); assert not r.stdout and not r.stderr
		v = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], label+'-memory')
		memories[label] = memory(v.stderr)
	for name, argv in [('symbols', ['nm', '-a', obj]), ('ELF', ['readelf', '-h', obj]), ('disassembly', ['objdump', '-dr', obj]), ('IR-verify', ['opt', '-passes=verify', '-disable-output', a.runtime/'literal-and-void.ll'])]:
		run(argv, name)
	collision = [frozen('collision-a.astra', 'namespace NativeabiCollisionA;export(C) int physical_collision(int x){return x;}\n'), frozen('collision-b.astra', 'namespace NativeabiCollisionB;export(C) int physical_collision(int x){return x+1;}\n')]
	run([a.compiler, '--parse', *collision], 'collision-parse')
	sentinel = a.runtime/'existing.o'; sentinel.write_bytes(b'pre-existing destination\n')
	r = run([a.component, '--emit-obj', a.mode, sentinel, *collision], 'physical-collision', 2)
	assert b'C physical symbol collision' in r.stderr and sentinel.read_bytes() == b'pre-existing destination\n'
	unresolved = frozen('unresolved.astra', 'extern(C) int nativeabi13_missing_symbol(int x);int main(){return nativeabi13_missing_symbol(1);}\n')
	missing = a.build/'unresolved.o'; exe = a.build/'unresolved.exe'
	run([a.component, '--emit-obj', a.mode, missing, unresolved], 'unresolved-emit')
	r = run(['gcc', missing, '-o', exe], 'unresolved-link', 1)
	assert b'nativeabi13_missing_symbol' in r.stderr and not exe.exists()
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, counted_in_39=False,
		component_sha256=sha(a.component), source_sha256=sha(source), C_source_sha256=sha(witness),
		memory=memories, controls=['literal signed-zero/subnormal/rounding bits', 'void and zero-argument C calls', 'physical C symbol collision', 'unresolved C link refusal']), indent=2)+'\n')
	print(a.mode, 'literal bits, C void/zero channels, collision and unresolved link controls passed')


if __name__ == '__main__':
	main()
