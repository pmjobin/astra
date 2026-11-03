// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifndef ASTRA_SURGE14_HOST_INTERFACES_HPP
#define ASTRA_SURGE14_HOST_INTERFACES_HPP
#include <windows.h>
#include <unknwn.h>

// Host capability probe only. This independently compiled C++ provider is not
// an Astra export and cannot qualify the compiler's COM implementation.
static const IID IID_Value14 = {0xce114a01, 0x5331, 0x4e00, {0x91, 0x14, 0x14, 0x00, 0x00, 0x00, 0x00, 0x01}};
static const IID IID_Scale14 = {0xce114a02, 0x5331, 0x4e00, {0x91, 0x14, 0x14, 0x00, 0x00, 0x00, 0x00, 0x02}};

struct Value14 : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE Get(LONG *result) = 0;
	virtual HRESULT STDMETHODCALLTYPE Set(LONG value) = 0;
};

struct Scale14 : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE Scale(LONG factor, LONG *result) = 0;
};

static_assert(sizeof(void *) == 8, "selected COM host is x86-64");
static_assert(sizeof(GUID) == 16 && sizeof(HRESULT) == 4 && sizeof(LONG) == 4, "Windows COM widths");
#endif
