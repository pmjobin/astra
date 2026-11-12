#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay exact physical backing identity checks against independent oracles."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from run import ROOT, WORK, C0_SHA256, sha, declarations
from acceleration import execute, output_path, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--capture', type=Path)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	if a.capsule_prefix and not a.inside_capsule:
		assert a.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(a.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	leaf = output_path(a.runtime_root/('llvm-backing-index-'+a.version), WORK/'runtime'); leaf.mkdir()
	build = output_path(a.build_root/leaf.name, WORK/'build'); build.mkdir()
	source = ROOT/'compiler/backend/llvm/recover-array-instructions.astra'; raw = source.read_bytes()
	def kernel(data):
		return data[data.index(b'bool recover_array_backings_distinct('):data.index(b'// Returns the exact block inventory')]
	view = leaf/'production-kernel.astra'; view.write_bytes(kernel(raw))
	baseline = 'd6b9e963d2cddcf43be50706ba6b16922e073d35'
	reference = subprocess.check_output(['git', 'show', baseline+':'+str(source.relative_to(ROOT))], cwd=ROOT)
	reference = kernel(reference).replace(b'recover_array_backings_distinct(', b'reference_backings_distinct(')
	(leaf/'reference.astra').write_bytes(reference)
	(leaf/'production-source.astra').write_bytes(raw)
	driver = Path(__file__).with_suffix('.astra'); saved_driver = leaf/driver.name; saved_driver.write_bytes(driver.read_bytes())
	(leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	inputs = {}; capture_paths = []
	if a.capture:
		capture = output_path(a.capture, WORK/'runtime')
		for name in ('backings', 'successes', 'locals'):
			path = capture/(name+'.bin'); assert path.stat().st_size % 8 == 0
			inputs[str(path)] = sha(path); capture_paths.append(str(path))
	observer = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned char tokens[5000];
void *backing_pointer(int index) { if(index<0||index>=5000)exit(91);return index?tokens+index:NULL; }
static unsigned mask(int code,int *duplicate) {
 int states=1;while(code>=states){code-=states;states*=3;}
 unsigned bits=0;while(code){int digit=code%3;code/=3;if(digit){unsigned bit=1u<<digit;if(bits&bit)*duplicate=1;bits|=bit;}}return bits;
}
int backing_expected(int a,int b,int c) { int duplicate=0,ignored=0;unsigned bits=mask(a,&duplicate);return !duplicate&&!(bits&(mask(b,&ignored)|mask(c,&ignored))); }
void backing_observed(int kind,int count) { printf("%d %d\n",kind,count); }
static uint64_t *captures[3];static int counts[3];
static void release(void) { for(int n=0;n<3;n++)free(captures[n]); }
int backing_capture_count(int which) {
 const char *paths[3]=PATHS;
 if(which<0||which>2)exit(92);
 if(!captures[which]){FILE *f=fopen(paths[which],"rb");if(!f||fseek(f,0,SEEK_END))exit(93);long bytes=ftell(f);if(bytes<0||bytes%8||bytes>64000000||fseek(f,0,SEEK_SET))exit(94);counts[which]=(int)(bytes/8);captures[which]=malloc((size_t)bytes);if(!captures[which]||fread(captures[which],1,(size_t)bytes,f)!=(size_t)bytes||fclose(f))exit(95);if(which==0&&atexit(release))exit(96);}
 return counts[which];
}
void *backing_capture_value(int which,int index) { if(which<0||which>2||index<0||index>=counts[which])exit(97);return (void *)(uintptr_t)captures[which][index]; }
'''.replace('PATHS', '{'+','.join(json.dumps(path) for path in (capture_paths or ['', '', '']))+'}')
	(leaf/'observer.c').write_text(observer)
	commands = []
	def run(name, argv, expected=0, timeout=180):
		result = execute(argv, leaf/name, expected=expected, timeout=timeout, env=dict(os.environ, CCACHE_DISABLE='1'))
		commands.append(dict(name=name, **result)); write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result['exit'], (leaf/name/'stderr').read_text()[:1500])
		print(name, round(result['seconds'], 3), flush=True)
		return (leaf/name/'stdout').read_bytes()
	run('toolchain', [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', a.compiler, '--receipt', leaf/'toolchain.json'])
	full = declarations(run('AST-source', [a.compiler, '--dump-syntax', leaf/'production-source.astra']).decode())
	selected = declarations(run('AST-kernel', [a.compiler, '--dump-syntax', view]).decode())
	assert len(selected) == 1 and full.count(selected[0]) == 1
	obj = build/'observer.o'; run('observer-build', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', leaf/'observer.c', '-o', obj])
	args = build/'args.o'; run('args-build', ['cc', '-std=c11', '-O2', '-c', ROOT/'lib/runtime/platform/args-posix.c', '-o', args])
	products = []
	for mode in ('O0', 'O2'):
		exe = build/('backing-index-'+mode)
		run(mode+'-build', [a.compiler, '-'+mode, view, saved_driver, leaf/'reference.astra', '--link-object', obj, '--link-object', args, '-o', exe])
		cases = dict(small=b'0 64000\n', large=b'1 6\n2 2\n')
		if a.capture: cases['captured'] = b'3 284425\n'
		for case, expected in cases.items():
			out = run(mode+'-'+case, [exe, '--'+case], 42)
			assert out == expected
			memory = run(mode+'-'+case+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe, '--'+case], 42)
			assert memory == out
			assert all(token in (leaf/(mode+'-'+case+'-memory')/'stderr').read_bytes() for token in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products.append(dict(profile=mode, ELF_sha256=sha(exe), exhaustive_vectors=64000, large_negative_twins=6, budget_boundaries=2, captured=bool(a.capture), strict_memory_streams=len(cases)))
	assert source.read_bytes() == raw and driver.read_bytes() == saved_driver.read_bytes()
	assert all(sha(path) == digest for path, digest in inputs.items())
	write(leaf/'result.json', dict(status='EXACT_BACKING_IDENTITY_HELPER_PASSED', production_source_sha256=sha(source), normalized_production_AST=selected, reference_revision=baseline, reference_sha256=sha(leaf/'reference.astra'), inputs=inputs, products=products, full_original_native_credit=0, limitation='Exact production pointer-equality helper under original C0; no LLVM module emission, integrated physical verifier or full compiler qualification. Exhaustive independent C bit-mask oracle and unchanged scalar reference; large positive twins must precede each alias corruption. The original8M guard remains.'))
	print('EXACT_BACKING_IDENTITY_HELPER_PASSED', leaf, flush=True)


if __name__ == '__main__':
	main()
