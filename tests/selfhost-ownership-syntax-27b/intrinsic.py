#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe actual native-v14 intrusive objects through allocation and C layout."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
SOURCE = '''extern(C) u64 strong_count();
extern(C) u64 weak_count();
extern(C) int payload_value();
extern(C) int allocation_count();
extern(C) int free_count();
extern(C) int drop_count();
extern(C) int bad_drop_count();
extern(C) void note_drop(int value);
[Shared]
class Session {
	int value;
	init(int value) { this.value = value; }
	deinit() { note_drop(this.value); }
}
Weak<Session> observe() {
	Session first = new Session(40);
	Session second = shared_clone(first);
	weak Session observer = shared_downgrade(first);
	var duplicate = weak_clone(observer);
	var alive = weak_upgrade(duplicate);
	if (alive != null) {
		if (alive.value != 40 || strong_count() != 3 || weak_count() != 3 || payload_value() != 40) return null;
	} else { return null; }
	return move observer;
}
int work() {
	var observer = observe();
	if (strong_count() != 0 || weak_count() != 1 || drop_count() != 1 || free_count() != 0 || bad_drop_count() != 0) return 1;
	var expired = weak_upgrade(observer);
	if (expired != null) return 2;
	return 42;
}
int main() {
	int result = work();
	if (free_count() != 1 || allocation_count() != 1 || drop_count() != 1 || bad_drop_count() != 0) return 3;
	return result;
}
'''
BRIDGE = '''#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
struct native_session {
	void *descriptor, *origin;
	uint64_t strong, weak;
	void *monitor;
	uint64_t thread;
	int32_t value;
};
_Static_assert(sizeof(struct native_session) == 56, "native-v14 complete payload");
_Static_assert(_Alignof(struct native_session) == 8, "native-v14 alignment");
_Static_assert(offsetof(struct native_session, strong) == 16, "strong offset");
_Static_assert(offsetof(struct native_session, weak) == 24, "weak offset");
_Static_assert(offsetof(struct native_session, value) == 48, "payload offset");
void *__real_calloc(size_t, size_t);
void __real_free(void *);
static unsigned char *observed;
static int allocations, frees, drops, bad_drops;
void *__wrap_calloc(size_t n, size_t size) {
	void *value = __real_calloc(n, size);
	if (value && n == 1 && size == sizeof(struct native_session)) {
		observed = value;
		++allocations;
	}
	return value;
}
void __wrap_free(void *value) {
	if (value && value == observed) { observed = NULL; ++frees; }
	__real_free(value);
}
static uint64_t count(size_t offset) {
	uint64_t result = UINT64_MAX;
	if (observed) memcpy(&result, observed + offset, sizeof(result));
	return result;
}
uint64_t strong_count(void) { return count(offsetof(struct native_session, strong)); }
uint64_t weak_count(void) { return count(offsetof(struct native_session, weak)); }
int payload_value(void) {
	int32_t result = -1;
	if (observed) memcpy(&result, observed + offsetof(struct native_session, value), sizeof(result));
	return result;
}
int allocation_count(void) { return allocations; }
int free_count(void) { return frees; }
int drop_count(void) { return drops; }
int bad_drop_count(void) { return bad_drops; }
void note_drop(int value) {
	++drops;
	if (value != 40 || strong_count() != 0 || weak_count() != 2 || frees != 0) ++bad_drops;
}
'''


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('compiler', 'c0', 'link', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--c0-sha256', required=True)
	p.add_argument('--oracle-only', action='store_true')
	a = p.parse_args()
	assert all(re.fullmatch('[0-9a-f]{64}', h) for h in (a.compiler_sha256, a.c0_sha256))
	assert sha(a.compiler) == a.compiler_sha256 and sha(a.c0) == a.c0_sha256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=False)
	runtime.mkdir(parents=True, exist_ok=False)
	link = json.loads(a.link.read_text())
	providers = {path:digest for path, digest in link['objects'].items() if Path(path).name not in ('llvm-capi.o', 'arguments.o')}
	assert len(providers) == 5 and all(sha(path) == h for path, h in providers.items())
	source = runtime/'intrinsic.astra'
	oracle = runtime/'intrinsic-legacy.astra'
	bridge = runtime/'observer.c'
	source.write_text('language astra27b;\n'+SOURCE)
	oracle.write_text(SOURCE.replace('Weak<Session> observe()', 'owned Weak<Session> observe()').replace('Session first =', 'var first =').replace('Session second =', 'var second =').replace('weak Session observer =', 'var observer ='))
	bridge.write_text(BRIDGE)
	inputs = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('support.py'), a.link, source, oracle, bridge)}
	tools = tool_identity([a.compiler, a.c0, '/usr/bin/time', *[shutil.which(n) for n in ('gcc', 'cc', 'as', 'ld', 'valgrind', 'opt', 'llc')]])
	write(runtime/'identity.json', dict(inputs=inputs, providers=providers, tools=tools, scope='C allocation observers implement no source function, ownership transfer, count update or destructor.'))
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	commands = []
	products = {}
	def run(name, argv, expected=0):
		argv = list(map(str, argv))
		r = execute(argv, runtime/name, expected=expected, timeout=900, env=env)
		commands.append(dict(name=name, argv=argv, result=r))
		write(runtime/'commands.json', commands)
		print(name, r['status'], round(r['seconds'], 3), flush=True)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected)
		log = (runtime/name/'stderr').read_bytes()
		assert all(m in log for m in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	observer = build/'observer.o'
	run('observer', ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', bridge, '-o', observer])
	for kind, compiler, text in [('C0', a.c0, oracle), *([] if a.oracle_only else [('Astra', a.compiler, source)])]:
		for mode in ('O0', 'O2'):
			name = kind+'-'+mode
			obj = build/(name+'.o')
			target = build/name
			args = [compiler, '-c', '-'+mode]
			if kind == 'C0':
				args += ['--entry-object']
			run(name+'-compile', [*args, '-o', obj, text])
			run(name+'-link', ['cc', '-no-pie', '-Wl,--wrap=calloc,--wrap=free', obj, observer, *providers, '-o', target])
			run(name+'-native', [target], 42)
			memory(name+'-memory', [target], 42)
			products.update({str(path):sha(path) for path in (obj, target)})
			write(runtime/'products.json', products)
		if kind == 'Astra':
			memory('Astra-compiler-memory', [compiler, '--emit-llvm', '-o', build/'intrinsic.ll', text], 0)
	assert all(sha(path) == h for path, h in {**inputs, **tools, **providers, **products}.items())
	write(runtime/'result.json', dict(status='C0_INTRINSIC_ABI_ORACLE_ONLY' if a.oracle_only else 'SELECTED_INTRINSIC_ABI_NATIVE_GATES_PASS', compiler_sha256=a.compiler_sha256, c0_sha256=a.c0_sha256, oracle_only=a.oracle_only, identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), products=products, scope='Actual native header/count/death observations only; complete ownership, mutation, preservation and delivery gates remain separate.'))


if __name__ == '__main__':
	main()
