#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe real allocation retirement order and C0 snapshot failure behavior."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

INTERPOSER = r'''#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
extern void *__libc_calloc(size_t, size_t);
extern void __libc_free(void *);
static void *addresses[1024];
static unsigned int acquired;
static char *decimal(char *out, size_t value) {
	char digits[32]; unsigned int count = 0;
	do { digits[count++] = '0' + value % 10; value /= 10; } while (value);
	while (count) *out++ = digits[--count];
	return out;
}
static void observe(char event, unsigned int identity, size_t bytes) {
	char line[100]; char *at = line;
	*at++ = 'R'; *at++ = '4'; *at++ = ' '; *at++ = event; *at++ = ' ';
	at = decimal(at, identity); *at++ = ' '; at = decimal(at, bytes); *at++ = '\n';
	size_t count = (size_t)(at - line);
	if (write(2, line, count) != (ssize_t)count) _exit(88);
}
void *calloc(size_t count, size_t width) {
	size_t bytes = count * width;
	const char *failure = getenv("ASTRA_R4_FAIL_SIZE");
	if (failure && bytes == (size_t)strtoull(failure, 0, 10)) { observe('X', 0, bytes); return 0; }
	void *result = __libc_calloc(count, width);
	if (result) {
		if (acquired == 1024) _exit(89);
		addresses[acquired++] = result; observe('A', acquired, bytes);
	}
	return result;
}
void free(void *value) {
	if (value) {
		unsigned int i = acquired;
		while (i && addresses[i - 1] != value) --i;
		if (i) { observe('F', i, 0); addresses[i - 1] = 0; }
	}
	__libc_free(value);
}
'''


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_lifetime_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-lifetime-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; results = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name, environment=None):
		argv = list(map(str, argv)); start = time.monotonic(); env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None); env.pop('ASTRA_R4_FAIL_SIZE', None)
		invocation = ['/usr/bin/env', *[key+'='+value for key, value in environment.items()], *argv] if environment else argv
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *invocation], cwd=build, env=env, capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=invocation, test_environment=environment or {}, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	interposer = leaf/'observe.c'; interposer.write_text(INTERPOSER); library = build/'observe.so'; assert run(['cc', '-std=c11', '-O2', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror', interposer, '-o', library], 'observer-build').returncode == 0
	corpus = load_module('r4_lifetime_corpus', ROOT/'tests/selfhost-effects/recover-r4-qualify.py')
	programs = {'reverse-declared-cleanup':corpus.corpus()['field-owned-child-success'], 'empty-snapshot':'class Label { private readonly string text; init(string value) { this.text = value; } } int main() { var value = new Label(""); return 42; }\n', 'nonempty-snapshot':'class Label { private readonly string text; init(string value) { this.text = value; } } int main() { var value = new Label("x"); return 42; }\n'}
	buffer = 'class Bytes { owned u8[] data; init(int count) { this.data = new u8[count]; } int count() { return len(this.data); } } '
	programs.update({'empty-buffer':buffer+'int main() { var value = new Bytes(0); return value.count() + 42; }\n', 'nonempty-buffer':buffer+'int main() { var value = new Bytes(1); return value.count() + 41; }\n'})
	for name, text in programs.items():
		source = leaf/(name+'.astra'); source.write_text(text); ir = build/(name+'.ll'); optimized = build/(name+'-optimized.ll'); native = build/(name+'-Astra'); c0 = build/(name+'-C0'); obj = build/(name+'.o'); assert run([C0, '-'+a.mode, source, '-o', c0], name+'-C0-build').returncode == 0; products = [('C0', c0)]
		if a.component:
			assert run([a.component, '--native', ir, source], name+'-emit').returncode == 0; assert run(['opt', '-passes=verify', '-disable-output', ir], name+'-verify').returncode == 0; assert run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], name+'-optimize').returncode == 0; assert run(['opt', '-passes=verify', '-disable-output', optimized], name+'-optimized-verify').returncode == 0; assert run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object').returncode == 0; assert run(['cc', '-no-pie', obj, '-o', native], name+'-link').returncode == 0; products.append(('Astra', native))
		row = dict(name=name, source_sha256=sha(source), native_ELF_sha256=sha(native) if a.component else None, C0_ELF_sha256=sha(c0), traces={})
		for label, program in products:
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], name+'-'+label+'-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			env = {'LD_PRELOAD':str(library)}; observed = run([program], name+'-'+label+'-observe', env); assert observed.returncode == 42; trace = re.findall(rb'^R4 ([AFX]) ([0-9]+) ([0-9]+)$', observed.stderr, re.M); row['traces'][label] = [(event.decode(), int(index), int(size)) for event, index, size in trace]; assert trace
			if name != 'reverse-declared-cleanup':
				env['ASTRA_R4_FAIL_SIZE'] = '1'; failure = run([program], name+'-'+label+'-allocation-failure', env); signal = re.search(r'Command terminated by signal ([0-9]+)', (leaf/(name+'-'+label+'-allocation-failure.time')).read_text()); row[label+'_failure_signal'] = int(signal[1]) if signal else None; row[label+'_failure_exit'] = failure.returncode
				if name in ('empty-snapshot', 'empty-buffer'): assert failure.returncode == 42 and not signal and b'R4 X ' not in failure.stderr
				else: assert signal and int(signal[1]) == 4 and failure.returncode == 132 and b'R4 X 0 1\n' in failure.stderr
		row['trace_equal'] = row['traces']['Astra'] == row['traces']['C0'] if a.component else None
		if a.component: assert row['trace_equal'], row
		results.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_LIFETIME_CONTROLS' if a.component else 'C0_LIFETIME_CONTROLS', profile=a.mode, component_sha256=sha(a.component) if a.component else None, observer_source_sha256=sha(interposer), observer_ELF_sha256=sha(library), programs=results, primary_native_credit=0, limitation='Observer interposition is applied only to the named generated executables, never a compiler or Valgrind. Fatal allocation controls have no returning-memory/unwind credit. Exact free identities observe reverse declared cleanup separately from ordinary unsuppressed memory runs.'), indent=2)+'\n'); print(a.mode, name, 'C0/native lifetime controls agree' if a.component else 'C0 lifetime/failure oracle only', flush=True)


if __name__ == '__main__':
	main()
