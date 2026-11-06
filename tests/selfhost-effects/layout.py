#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent GCC/Clang and LLVM measurements of the approved C0 error layout."""
import json
from pathlib import Path
import subprocess
import time
from state import bounded_run, RUNTIME, BUILD, sha

SOURCE = r'''
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Target.h>
struct Text { const char* data; std::int32_t count; };
struct Error { void* descriptor; void* origin; Text text; };
struct Descriptor { void* parent; void* destroy; void* slots; };
#pragma pack(push, 1)
struct Packed { void* descriptor; void* origin; Text text; };
#pragma pack(pop)
struct Swapped { void* origin; void* descriptor; Text text; };
struct WideText { const char* data; std::int64_t count; };
struct Wide { void* descriptor; void* origin; WideText text; };
struct NoOrigin { void* descriptor; Text text; };
struct GapText { const char* data; std::int64_t gap; std::int32_t count; };
struct Gap { void* descriptor; void* origin; GapText text; };
struct Shifted { void* descriptor; Text text; void* origin; };
int main(int argc, char** argv) {
	if (argc != 2) return 1;
	LLVMContextRef context = LLVMContextCreate(); LLVMMemoryBufferRef input = nullptr; char* message = nullptr; LLVMModuleRef module = nullptr;
	if (LLVMCreateMemoryBufferWithContentsOfFile(argv[1], &input, &message) || LLVMParseIRInContext(context, input, &module, &message)) return 2;
	LLVMTargetDataRef layout = LLVMCreateTargetData(LLVMGetDataLayoutStr(module));
	LLVMTypeRef root = LLVMGetTypeByName2(context, "astra.class.0");
	LLVMValueRef global = LLVMGetNamedGlobal(module, "astra.class.descriptor.0");
	if (!root || !global || LLVMCountStructElementTypes(root) != 3) return 3;
	LLVMTypeRef descriptor = LLVMGlobalGetValueType(global); LLVMTypeRef text = LLVMStructGetTypeAtIndex(root, 2);
	if (LLVMCountStructElementTypes(text) != 2 || LLVMGetIntTypeWidth(LLVMStructGetTypeAtIndex(text, 1)) != 32) return 4;
	bool equal = LLVMPointerSize(layout) == sizeof(void*) && LLVMABISizeOfType(layout, root) == sizeof(Error) && LLVMABIAlignmentOfType(layout, root) == alignof(Error)
		&& LLVMOffsetOfElement(layout, root, 0) == offsetof(Error, descriptor) && LLVMOffsetOfElement(layout, root, 1) == offsetof(Error, origin)
		&& LLVMOffsetOfElement(layout, root, 2) == offsetof(Error, text) && LLVMOffsetOfElement(layout, text, 1) == offsetof(Text, count)
		&& LLVMABISizeOfType(layout, descriptor) == sizeof(Descriptor) && LLVMABIAlignmentOfType(layout, descriptor) == alignof(Descriptor)
		&& LLVMOffsetOfElement(layout, descriptor, 0) == offsetof(Descriptor, parent) && LLVMOffsetOfElement(layout, descriptor, 1) == offsetof(Descriptor, destroy)
		&& LLVMOffsetOfElement(layout, descriptor, 2) == offsetof(Descriptor, slots);
	std::printf("LAYOUT %zu %zu %zu %zu %zu %zu %zu %zu %zu\n", sizeof(Error), alignof(Error), offsetof(Error, descriptor), offsetof(Error, origin), offsetof(Error, text), offsetof(Error, text) + offsetof(Text, count), sizeof(Descriptor), alignof(Descriptor), sizeof(void*));
	bool bad[6] = { sizeof(Packed) != sizeof(Error) || alignof(Packed) != alignof(Error), offsetof(Swapped, descriptor) != offsetof(Error, descriptor), sizeof(WideText::count) != sizeof(Text::count), sizeof(NoOrigin) != sizeof(Error), offsetof(Gap, text) + offsetof(GapText, count) != offsetof(Error, text) + offsetof(Text, count), offsetof(Shifted, text) != offsetof(Error, text) };
	for (int i = 0; i != 6; ++i) { if (!bad[i]) return 5; std::printf("ALTERNATIVE %d rejected\n", i); }
	LLVMDisposeTargetData(layout); LLVMDisposeModule(module); LLVMContextDispose(context); return equal ? 0 : 6;
}
'''


def main():
	leaf = RUNTIME/'layout-v1'; build = BUILD/'layout-v1'; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	source = leaf/'layout.cpp'; source.write_text(SOURCE)
	ir = BUILD/'c0-design-v2/heap-factories-O0.ll'; assert ir.is_file()
	flags = subprocess.check_output(['llvm-config', '--cflags', '--ldflags', '--libs', 'core', 'irreader', '--system-libs'], text=True).split(); rows = []
	for tool in ('g++', 'clang++'):
		for mode in ('O0', 'O2'):
			exe = build/(tool+'-'+mode); commands = [[tool, '-std=c++17', '-'+mode, '-Wall', '-Wextra', '-Werror', source, *flags, '-o', exe], [exe, ir]]
			for i, argv in enumerate(commands):
				start = time.monotonic(); r = bounded_run(list(map(str, argv)), capture_output=True, timeout=120); name = tool+'-'+mode+'-'+str(i)
				(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
				rows.append(dict(argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(rows, indent=2)+'\n'); assert r.returncode == 0, r.stderr[-2000:]
				if i == 1: assert r.stdout.splitlines()[0] == b'LAYOUT 32 8 0 8 16 24 24 8 8' and len(r.stdout.splitlines()) == 7
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_LAYOUT_DESIGN_EVIDENCE', C0_IR_sha256=sha(ir), source_sha256=sha(source), independent_tool_profiles=4, rejected_layout_alternatives_per_profile=6, new_Astra_effect_physical_mutations=0, limitation='C0 layout agreement only. No candidate error-call ABI, cleanup or SSA implementation is established by these measurements.'), indent=2)+'\n')
	print('GCC/Clang O0/O2 agree with C0 LLVM layout; six independent layout alternatives/profile rejected', flush=True)


if __name__ == '__main__':
	main()
