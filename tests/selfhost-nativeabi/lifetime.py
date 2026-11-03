#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Uncounted owner edge controls and a separate allocation-failure observation."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-llvm'))
from oracle import memory

FAULT = '''#include <stddef.h>
#include <unistd.h>
extern void *__real_calloc(size_t,size_t);
extern void __real_free(void *);
static unsigned calls;
void *__wrap_calloc(size_t count,size_t width){
    if(++calls==2){(void)write(2,"FAIL\\n",5);return 0;}
    (void)write(2,"ALLOC\\n",6);return __real_calloc(count,width);
}
void __wrap_free(void *p){if(p)(void)write(2,"FREE\\n",5);__real_free(p);}
'''


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'runtime', 'build'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--inputs', type=Path, required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.runtime, a.build))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert not a.inputs.resolve().is_relative_to(ROOT)
	a.inputs.mkdir(parents=True, exist_ok=True)
	def frozen(name, text):
		path = a.inputs/name
		if path.exists():
			assert path.read_bytes() == text.encode()
		else:
			path.write_text(text)
		return path
	commands = []
	def run(argv, name, expected=0):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, cwd=a.build, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode,
			monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-2000:])
		return r
		# An empty buffer has no allocation, but retires the preceding owner.
	source = frozen('zero-replace.astra', 'int main(){owned int[] value=new int[2];value=new int[0];value=new int[3];return 0;}\n')
	obj = a.build/'zero-replace.o'; native = a.build/'zero-replace'; c0 = native.with_suffix('.c0')
	run([a.component, '--emit-obj', a.mode, obj, source], 'zero-native-emit')
	run(['gcc', obj, '-o', native], 'zero-native-link')
	run([a.compiler, '-'+a.mode, source, '-o', c0], 'zero-C0-build')
	memories = {}
	for label, exe in [('native', native), ('C0', c0)]:
		run([exe], 'zero-'+label)
		r = run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], 'zero-memory-'+label)
		memories[label] = memory(r.stderr, [('A', 2), ('F', 2), ('A', 3), ('F', 3)])
		# C0 rejects self-move replacement; preserve rejection, without emitting.
	self_move = frozen('self-move.astra', 'int main(){owned int[] value=new int[2];value=move value;return 0;}\n')
	r = run([a.compiler, '--check', self_move], 'self-move-C0', 1)
	assert b'self-move replacement is unsupported' in r.stderr
	forbidden = a.runtime/'self-move.forbidden.o'
	run([a.component, '--emit-obj', a.mode, forbidden, self_move], 'self-move-native', 2)
	assert not forbidden.exists()
	# Linker wrapping changes only the allocator oracle, not Astra bodies.
	failure = frozen('failed-replacement.astra', 'int main(){owned int[] value=new int[2];value=new int[3];return 0;}\n')
	companion = frozen('allocator-fault.c', FAULT)
	wrapper = a.build/'allocator-fault.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', companion, '-o', wrapper], 'allocator-fault-build')
	traps = {}
	for label in ('native', 'C0'):
		obj = a.build/('failed-'+label+'.o'); exe = obj.with_suffix('.exe')
		argv = [a.component, '--emit-obj', a.mode, obj, failure] if label == 'native' else [a.compiler, '-'+a.mode, '--entry-object', failure, '-o', obj]
		run(argv, 'failure-emit-'+label)
		run(['gcc', obj, wrapper, '-Wl,--wrap=calloc', '-Wl,--wrap=free', '-o', exe], 'failure-link-'+label)
		# Run directly to retain the actual signal rather than time's 128+signal.
		start = time.monotonic(); r = subprocess.run([str(exe)], capture_output=True, cwd=a.build, timeout=10)
		(a.runtime/('failure-'+label+'.stdout')).write_bytes(r.stdout)
		(a.runtime/('failure-'+label+'.stderr')).write_bytes(r.stderr)
		assert r.returncode == -4 and not r.stdout and r.stderr == b'ALLOC\nFAIL\n', (label, r.returncode, r.stderr)
		traps[label] = dict(signal=4, trace=r.stderr.decode(), executable_sha256=sha(exe),
			normal_leak_claim=False, monotonic_start=start, monotonic_end=time.monotonic())
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode,
		component_sha256=sha(a.component), compiler_sha256=sha(a.compiler), zero_size_memory=memories,
		self_move='rejected by C0 and native before object publication', allocation_failure=traps,
		counted_in_39=False), indent=2)+'\n')
	print(a.mode, 'zero-size, self-move refusal and failed RHS retirement order passed')


if __name__ == '__main__':
	main()
