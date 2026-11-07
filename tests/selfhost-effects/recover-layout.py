#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C and C++ target-layout witnesses; never count as Astra ELFs."""
import argparse
import json
import os
from pathlib import Path
import shutil
import time
from state import ROOT, load_module, bounded_run, sha

SOURCE = r'''#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct Descriptor Descriptor;
typedef struct Origin { const char *file; int32_t count, line, column; } Origin;
typedef struct Root { const Descriptor *descriptor; const Origin *origin; uint8_t *data; int32_t count; } Root;
struct Descriptor { const Descriptor *parent; void (*destroy)(Root *); const void *slots; };
typedef struct Derived { Root base; } Derived;
typedef struct Extended { Derived base; int8_t tag; } Extended;
_Static_assert(sizeof(void *) == 8 && sizeof(long) == 8, "LP64");
_Static_assert(sizeof(Root) == 32 && _Alignof(Root) == 8, "complete root");
_Static_assert(offsetof(Root, descriptor) == 0 && offsetof(Root, origin) == 8, "header");
_Static_assert(offsetof(Root, data) == 16 && offsetof(Root, count) == 24, "snapshot");
_Static_assert(sizeof(Derived) == 32 && offsetof(Extended, tag) == 32 && sizeof(Extended) == 40, "complete base tail padding");
_Static_assert(sizeof(Descriptor) == 24 && offsetof(Descriptor, parent) == 0 && offsetof(Descriptor, destroy) == 8 && offsetof(Descriptor, slots) == 16, "descriptor");
_Static_assert(sizeof(Origin) == 24 && offsetof(Origin, count) == 8 && offsetof(Origin, line) == 12 && offsetof(Origin, column) == 16, "origin");
static void destroy(Root *root) { free(root->data); }
int main(void) {
 const uint8_t bytes[] = {0x41, 0, 0xc3, 0xa9};
 const void *slots[1] = {NULL};
 const Descriptor descriptor = {NULL, destroy, slots};
 const Origin origin = {"layout-probe", 12, 1, 1};
 Root *root = (Root *)calloc(1, sizeof(Root)); if (!root) return 9;
 root->data = (uint8_t *)calloc(sizeof(bytes) + 1, 1); if (!root->data) { free(root); return 9; }
 memcpy(root->data, bytes, sizeof(bytes)); root->count = (int32_t)sizeof(bytes); root->descriptor = &descriptor; root->origin = &origin;
 if (root->count != 4 || root->data[1] != 0 || root->data[2] != 0xc3 || root->data[3] != 0xa9 || root->data[4] != 0) return 8;
 printf("ROOT %zu %zu %zu %zu %zu %zu\n", sizeof(Root), (size_t)_Alignof(Root), offsetof(Root, descriptor), offsetof(Root, origin), offsetof(Root, data), offsetof(Root, count));
 printf("DERIVED %zu %zu %zu\n", sizeof(Derived), offsetof(Extended, tag), sizeof(Extended));
 printf("DESCRIPTOR %zu %zu %zu %zu\n", sizeof(Descriptor), offsetof(Descriptor, parent), offsetof(Descriptor, destroy), offsetof(Descriptor, slots));
 printf("ORIGIN %zu %zu %zu %zu\n", sizeof(Origin), offsetof(Origin, count), offsetof(Origin, line), offsetof(Origin, column));
 root->descriptor->destroy(root); free(root); return 0;
}
'''


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	state = load_module('recover_layout_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = state.RUNTIME/('layout-'+a.version); build = state.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	commands = []; results = []
	def run(argv, label):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=120)
		(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(argv=argv, exit=r.returncode, seconds=time.monotonic()-start, label=label)); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == 0, r.stderr; return r
	expected = b'ROOT 32 8 0 8 16 24\nDERIVED 32 32 40\nDESCRIPTOR 24 0 8 16\nORIGIN 24 8 12 16\n'
	for language, compiler, standard, suffix in (('C', 'gcc', 'c11', 'c'), ('C++', 'clang++', 'c++17', 'cpp')):
		source = SOURCE if language == 'C' else SOURCE.replace('_Static_assert', 'static_assert').replace('_Alignof', 'alignof')
		path = leaf/('layout.'+suffix); path.write_text(source)
		for mode in ('O0', 'O2'):
			name = language.replace('+', 'p')+'-'+mode; exe = build/name; run([compiler, '-std='+standard, '-'+mode, '-Wall', '-Wextra', '-Werror', path, '-o', exe], name+'-compile'); native = run([exe], name+'-execute'); assert native.stdout == expected
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-memory'); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			results.append(dict(language=language, profile=mode, compiler=shutil.which(compiler), compiler_sha256=sha(shutil.which(compiler)), source_sha256=sha(path), ELF_sha256=sha(exe), output=native.stdout.decode(), memory='zero unsuppressed errors and live allocations'))
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_C_CPP_LAYOUT_ONLY', Astra_effect_ELFs=0, results=results), indent=2)+'\n'); print('Independent GCC C and Clang C++ layout/snapshot probes pass O0/O2; zero Astra effect ELF credit', flush=True)


if __name__ == '__main__':
	main()
