#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C/C++ layouts and actual original SourceBuffer C0 execution."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

SOURCE = '''#include <stdint.h>
#include <stddef.h>
typedef struct ByteBuffer { uint8_t *base; int32_t count; } ByteBuffer;
typedef struct IntBuffer { int32_t *base; int32_t count; } IntBuffer;
typedef struct OriginalSourceBuffer { void *filename; ByteBuffer content; IntBuffer starts; int32_t lines; uint8_t interface_input; } OriginalSourceBuffer;
typedef struct OriginalBuilder { ByteBuffer backing; int32_t used; } OriginalBuilder;
typedef struct IndependentMixed { void *label; uint8_t flag; IntBuffer data; int32_t count; } IndependentMixed;
#ifdef __cplusplus
#define ASSERT static_assert
#define ALIGN alignof
#else
#define ASSERT _Static_assert
#define ALIGN _Alignof
#endif
ASSERT(sizeof(OriginalSourceBuffer) == 48 && ALIGN(OriginalSourceBuffer) == 8, "SourceBuffer extent");
ASSERT(offsetof(OriginalSourceBuffer, filename) == 0 && offsetof(OriginalSourceBuffer, content) == 8 && offsetof(OriginalSourceBuffer, starts) == 24 && offsetof(OriginalSourceBuffer, lines) == 40 && offsetof(OriginalSourceBuffer, interface_input) == 44, "SourceBuffer fields");
ASSERT(sizeof(OriginalBuilder) == 24 && ALIGN(OriginalBuilder) == 8 && offsetof(OriginalBuilder, backing) == 0 && offsetof(OriginalBuilder, used) == 16, "Builder");
ASSERT(sizeof(IndependentMixed) == 40 && ALIGN(IndependentMixed) == 8 && offsetof(IndependentMixed, label) == 0 && offsetof(IndependentMixed, flag) == 8 && offsetof(IndependentMixed, data) == 16 && offsetof(IndependentMixed, count) == 32, "independent mixed fields");
int main(void) { return 42; }
'''


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--provider-build', type=Path); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_layout_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-layout-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-1500:], r.stderr[-2500:]); return r
	layouts = []
	for compiler in ('gcc', 'clang', 'g++', 'clang++'):
		source = leaf/(compiler.replace('+', 'p')+('.cpp' if '+' in compiler else '.c')); source.write_text(SOURCE); exe = build/source.stem; run([compiler, '-std=c++17' if '+' in compiler else '-std=c11', '-Wall', '-Wextra', '-Werror', source, '-o', exe], compiler+'-build'); run([exe], compiler+'-execute', (42,)); layouts.append(dict(compiler=compiler, source_sha256=sha(source), ELF_sha256=sha(exe)))
	before = read(paths.RUNTIME/'original-before-O0/result.json'); dependencies = [Path(row['path']) for row in before['inputs'][2:]]
	assert all(sha(row['path']) == row['sha256'] for row in before['inputs'][2:])
	caller = leaf/'source-buffer-caller.astra'; caller.write_text('int main() { try { var filename = new Utf8Message("path"); var content = new u8[1]; content[0] = 42; var starts = new int[1]; starts[0] = 0; var source = new SourceBuffer(move filename, move content, move starts, 1, false); if (source.length != 1) return 3; if (source.native_interface) return 4; return source.byte_at(0); } catch (Error caught) { return 5; } }\n')
	providers = load_module('r4_layout_providers', ROOT/'tests/selfhost-typecore/build.py'); provider_build = a.provider_build or paths.BUILD.parent/('effects25-r3/full-final6-'+a.mode); objects = [provider_build/(name+'.o') for name in providers.PROVIDERS]
	for path in objects:
		identity = read(path.with_suffix('.identity.json')); assert sha(path) == identity['sha256'] and all(sha(source) == expected for group in ('sources', 'tools') for source, expected in identity['identity'][group].items())
	links = [arg for path in objects for arg in ('--link-object', path)]; inputs = [caller, *dependencies]; exe = build/'C0-SourceBuffer'
	run([C0, '-'+a.mode, *inputs, *links, '-o', exe], 'C0-build'); run([exe], 'C0-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'C0-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	ir = build/'C0.ll'; ir.write_bytes(run([C0, '-O0', '--dump-llvm', *inputs], 'C0-ABI').stdout); run(['opt', '-passes=verify', '-disable-output', ir], 'C0-LLVM-verify')
	(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_LAYOUT_AND_ORIGINAL_C0_ONLY', profile=a.mode, layouts=layouts, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], C0_ELF_sha256=sha(exe), C0_LLVM_sha256=sha(ir), C0_exit=42, Astra_native_credit=0, limitation='C/C++ offsets are independent predictions; raw C0 source LLVM and actual original SourceBuffer execution are retained separately. These are not Astra-native field or original-function qualification.'), indent=2)+'\n'); print(a.mode, 'C/C++ layout and original C0 SourceBuffer execution/Valgrind pass', flush=True)


if __name__ == '__main__':
	main()
