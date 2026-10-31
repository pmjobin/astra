#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C owned-out normalization, nominal nullable owners, duplication and quiescence."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]

HEADER = '''#ifndef OWNERS14_H
#define OWNERS14_H
#include <stdint.h>
#include <stddef.h>
typedef struct Owner14 Owner14;
_Static_assert(sizeof(Owner14 *) == 8 && sizeof(int32_t) == 4, "LP64 C ownership channels");
int32_t owner14_create(int32_t, Owner14 **);
int32_t owner14_duplicate(Owner14 *, int32_t, Owner14 **);
void owner14_release(Owner14 *);
int32_t owner14_value(Owner14 *);
int32_t owner14_count(int32_t);
int32_t owner14_closed_id(int32_t);
void owner14_reset(void);
Owner14 *owner14_import_create(int32_t);
Owner14 *owner14_import_duplicate(Owner14 *, int32_t);
int32_t owner14_last_status(void);
int32_t owner14_run(int32_t);
int32_t owner14_early(void);
int32_t owner14_order(void);
int32_t owner14_callback(void);
#endif
'''

PROVIDER = '''#include "owners14.h"
#include <stdlib.h>
#include <assert.h>
struct Owner14 { int32_t owners, value, identity; };
static int32_t created, closed, live, bad, closed_ids[32];
static Owner14 *make(int32_t value) {
	Owner14 *r = malloc(sizeof(*r)); assert(r);
	r->owners = 1; r->value = value; r->identity = ++created; ++live; return r;
}
int32_t owner14_create(int32_t mode, Owner14 **out) {
	if (!out) return -2147467261;
	*out = NULL;
	if (mode == 1) return -2147467259;
	if (mode == 4) return 0; /* documented nullable success */
	if (mode == 5) return -2147024882;
	*out = make(mode == 3 ? 7 : 42);
	return mode == 2 ? -2147467259 : mode == 3 ? 1 : 0;
}
int32_t owner14_duplicate(Owner14 *value, int32_t mode, Owner14 **out) {
	if (!out) return -2147467261;
	*out = NULL;
	if (!value) return -2147467261;
	assert(value->owners > 0); ++value->owners; *out = value;
	return mode == 2 ? -2147467259 : 0;
}
void owner14_release(Owner14 *value) {
	if (!value || value->owners <= 0) { ++bad; return; }
	if (--value->owners == 0) { closed_ids[closed++] = value->identity; --live; free(value); }
}
int32_t owner14_value(Owner14 *value) { return value ? value->value : -1; }
int32_t owner14_count(int32_t index) { return index == 0 ? created : index == 1 ? closed : index == 2 ? live : bad; }
int32_t owner14_closed_id(int32_t index) { return index >= 0 && index < closed ? closed_ids[index] : -1; }
void owner14_reset(void) { assert(!live); created = closed = bad = 0; }
'''

ADAPTER = '''#include "owners14.h"
/* Existing Source ABI: owned nullable nominal result, explicit status getter.
 * Actual C T** storage belongs exclusively to this independently compiled SDK.
 * Failed stray ownership is retired before exposing the normalized result. */
static _Thread_local int32_t last_status;
static Owner14 *normalize(Owner14 *value, int32_t status) {
	last_status = status;
	if (status < 0 && value) { owner14_release(value); return NULL; }
	return value;
}
Owner14 *owner14_import_create(int32_t mode) {
	Owner14 *out = NULL; int32_t status = owner14_create(mode, &out); return normalize(out, status);
}
Owner14 *owner14_import_duplicate(Owner14 *value, int32_t mode) {
	Owner14 *out = NULL; int32_t status = owner14_duplicate(value, mode, &out); return normalize(out, status);
}
int32_t owner14_last_status(void) { return last_status; }
'''

SOURCE = '''[CImport(name="owner14_import_create",header="owners14.h")]
owned Owner14 create(int mode);
[CImport(name="owner14_import_duplicate",header="owners14.h")]
owned Owner14 duplicate(borrowed Owner14 value, int mode);
[CImport(name="owner14_last_status",header="owners14.h")] int status();
[CImport(name="owner14_value",header="owners14.h")] int value(borrowed Owner14 object);
[CExport(name="owner14_run")]
int run(int mode) {
	owned Owner14 first = create(mode);
	int result = status();
	if (mode == 1 || mode == 2 || mode == 5) {
		if (first != null) { return 1; }
		if (mode == 5) { if (result != -2147024882) { return 2; } }
		else { if (result != -2147467259) { return 3; } }
		return 0;
	}
	if (mode == 4) { if (first != null || result != 0) { return 4; } return 0; }
	if (mode == 3) { if (first == null || result != 1 || value(first) != 7) { return 5; } return 0; }
	if (first == null || result != 0 || value(first) != 42) { return 6; }
	owned Owner14 copy = duplicate(first, 0);
	if (copy == null || status() != 0) { return 7; }
	owned Owner14 moved = move copy;
	release first;
	owned Owner14 failed = duplicate(moved, 2);
	if (failed != null || status() != -2147467259 || value(moved) != 42) { return 8; }
	return 0;
}
[CExport(name="owner14_early")]
int early() { owned Owner14 first = create(0); owned Owner14 copy = duplicate(first, 0); return 73; }
[CExport(name="owner14_order")]
int order() { owned Owner14 first = create(0); owned Owner14 second = create(0); owned Owner14 copy = duplicate(first, 0); return 0; }
class Capture14 {
	owned Owner14 object;
	init(owned Owner14 object) { this.object = move object; }
	deinit() {}
}
int callback(borrowed Capture14 capture, int input) { return value(capture.object) + input; }
[CExport(name="owner14_callback")]
int retained() {
	owned Owner14 object = create(0);
	var capture = new Capture14(move object);
	var handler = closure_bind(move capture, callback);
	if (retained_register(handler, 0) != 0 || retained_dispatch(handler, 5) != 47) { return 1; }
	if (retained_revoke(handler) != 1 || retained_observe(handler) != 1 || retained_dispatch(handler, 9) != -2) { return 2; }
	return 0;
}
'''

CLIENT = '''#include "owners14.h"
#include <stdio.h>
#define CHECK(c) do { if (!(c)) { printf("FAIL C owners line=%d: %s\\n", __LINE__, #c); return 1; } } while (0)
int main(void) {
	Owner14 *raw = (Owner14 *)(uintptr_t)1;
	CHECK(owner14_create(2, &raw) == -2147467259 && raw);
	owner14_release(raw); owner14_reset();
	for (int mode = 0; mode <= 5; ++mode) CHECK(owner14_run(mode) == 0);
	CHECK(owner14_count(0) == 3 && owner14_count(1) == 3 && owner14_count(2) == 0 && owner14_count(3) == 0);
	CHECK(owner14_early() == 73 && owner14_count(0) == 4 && owner14_count(1) == 4);
	CHECK(owner14_order() == 0 && owner14_count(0) == 6 && owner14_count(1) == 6);
	CHECK(owner14_closed_id(4) == 6 && owner14_closed_id(5) == 5);
	CHECK(owner14_callback() == 0 && owner14_count(0) == 7 && owner14_count(1) == 7 && owner14_count(2) == 0 && owner14_count(3) == 0);
	puts("PASS C owners: real-owned-out SDK-normalization nullable duplicate explicit-move failed-stray HRESULT-status early-return reverse-destruction retained-cancel-quiescence seven-exact-destructions"); return 0;
}
'''


def main(compiler_arg, output_arg):
	compiler, output = Path(compiler_arg).resolve(), Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='c-owners-', dir=output))
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'checks': rows,
		'profile': 'existing nominal owned nullable function result; C T** normalized exclusively inside explicit SDK, not Source storage'}
	def run(command, expected=0, contains=''):
		assert hashlib.sha256(compiler.read_bytes()).hexdigest() == receipt['compiler_sha256'], 'compiler changed during qualification'
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	for name, text in [('owners14.h', HEADER), ('provider.c', PROVIDER), ('adapter.c', ADAPTER), ('client.c', CLIENT), ('owner.astra', SOURCE)]:
		(work / name).write_text(text)
	declarations = work / 'owners.vapi'
	declarations.write_text('[CCode(destroy_function="owner14_release")] handle Owner14;\n[CCode(destroy_function="owner14_other_release")] handle Other14;\n')
	flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic']
	for cc in ('gcc', 'clang'):
		for name in ('provider', 'adapter', 'client'):
			run([cc, *flags, '-c', work / (name + '.c'), '-o', work / (cc + '-' + name + '.o')])
		run([cc, *flags, '-c', ROOT / 'lib/runtime/interop/retained.c', '-o', work / (cc + '-retained.o')])
	for level in ('0', '1', '2'):
		obj = work / ('owner-O' + level + '.o')
		run([compiler, '-O' + level, '--vapi', declarations, '-c', work / 'owner.astra', '-o', obj])
		for cc in ('gcc', 'clang'):
			binary = work / (cc + '-O' + level)
			run([cc, obj, *[work / (cc + '-' + name + '.o') for name in ('client', 'provider', 'adapter', 'retained')], '-o', binary])
			run([binary], contains='PASS C owners:')
			if level in ('0', '2'):
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--errors-for-leak-kinds=all', '--error-exitcode=99', binary], contains='ERROR SUMMARY: 0 errors')
	for stage in ('semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi'):
		# The native ABI inventory names the exact retained environment; Resource
		# cleanup symbols belong to the separate C ABI authority after erasure.
		run([compiler, '--vapi', declarations, '--dump-' + stage, work / 'owner.astra'],
			contains='owned-closure<Capture14' if stage == 'nabi' else 'owner14_release')
	ir = run([compiler, '--vapi', declarations, '--dump-llvm', work / 'owner.astra'])
	assert 'call void @owner14_release(ptr' in ir, 'actual generated Resource cleanup call missing'
	bad = work / 'bad.astra'
	for text in [SOURCE.replace('owned Owner14 moved = move copy;', 'owned Owner14 moved = copy;'),
		SOURCE + '\nowned Owner14 escape(borrowed Owner14 value) { return move value; }\n',
		SOURCE + '\nint wrong(borrowed Other14 object) { return value(object); }\n']:
		bad.write_text(text)
		run([compiler, '--vapi', declarations, '--check', bad], expected=1)
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} independent C owned-out/nullable/duplication/lifetime/quiescence checks; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
