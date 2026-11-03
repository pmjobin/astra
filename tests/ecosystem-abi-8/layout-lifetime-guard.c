// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only C-API interposer. Check lifetime, independent of allocator reuse.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <llvm-c/Core.h>
#include <llvm-c/Target.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define REAL(name) \
	__typeof__(&name) call; \
	void *symbol = dlsym(RTLD_NEXT, #name); \
	_Static_assert(sizeof(call) == sizeof(symbol), "ELF function pointer size"); \
	memcpy(&call, &symbol, sizeof(call)); \
	if (call == NULL) _exit(98)

static struct {
	LLVMTargetDataRef data;
	LLVMContextRef context;
} caches[512];

static unsigned queries, released, contexts;

static void track(LLVMTargetDataRef data, LLVMTypeRef type) {
	LLVMContextRef context = LLVMGetTypeContext(type);
	++queries;
	for (unsigned i = 0; i < 512; ++i) {
		if (caches[i].data == data && caches[i].context == context) return;
	}
	for (unsigned i = 0; i < 512; ++i) {
		if (caches[i].data == NULL) {
			caches[i].data = data;
			caches[i].context = context;
			return;
		}
	}
	fputs("layout-guard capacity exceeded\n", stderr);
	_exit(98);
}

unsigned long long LLVMABISizeOfType(LLVMTargetDataRef data, LLVMTypeRef type) {
	REAL(LLVMABISizeOfType);
	track(data, type);
	return call(data, type);
}

unsigned LLVMABIAlignmentOfType(LLVMTargetDataRef data, LLVMTypeRef type) {
	REAL(LLVMABIAlignmentOfType);
	track(data, type);
	return call(data, type);
}

unsigned long long LLVMOffsetOfElement(LLVMTargetDataRef data, LLVMTypeRef type, unsigned field) {
	REAL(LLVMOffsetOfElement);
	track(data, type);
	return call(data, type, field);
}

void LLVMDisposeTargetData(LLVMTargetDataRef data) {
	REAL(LLVMDisposeTargetData);
	for (unsigned i = 0; i < 512; ++i) {
		if (caches[i].data == data) {
			// A narrowly reintroduced lifetime error, confined to a child that
			// must exit at context disposal before emitting/executing code.
			if (getenv("ASTRA_TEST_RETAIN_LAYOUT") != NULL) return;
			caches[i].data = NULL;
			++released;
		}
	}
	call(data);
}

void LLVMContextDispose(LLVMContextRef context) {
	REAL(LLVMContextDispose);
	for (unsigned i = 0; i < 512; ++i) {
		if (caches[i].data != NULL && caches[i].context == context) {
			fprintf(stderr, "layout-guard: queried cache survives context data=%p context=%p\n", (void *)caches[i].data, (void *)context);
			_exit(97);
		}
	}
	++contexts;
	call(context);
}

__attribute__((destructor)) static void receipt(void) {
	fprintf(stderr, "layout-guard: queries=%u released=%u contexts=%u\n", queries, released, contexts);
}
