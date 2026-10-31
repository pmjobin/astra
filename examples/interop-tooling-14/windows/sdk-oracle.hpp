// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Independent SDK authority. No generated Astra header is included.
#ifndef ASTRA14_APP_SDK_ORACLE_HPP
#define ASTRA14_APP_SDK_ORACLE_HPP
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <stdint.h>
#include <cstdio>
#include <cstring>
static constexpr IID VALUE = {0x849ad154,0x8d1e,0x4c63,{0x9e,0xa2,0x14,0x32,0x9b,0x02,0x20,0x01}};
static constexpr IID SCALE = {0x849ad154,0x8d1e,0x4c63,{0x9e,0xa2,0x14,0x32,0x9b,0x02,0x20,0x02}};
struct Value : IUnknown { virtual HRESULT STDMETHODCALLTYPE Get(LONG *) = 0; virtual HRESULT STDMETHODCALLTYPE Set(LONG) = 0; };
struct Scaling : IUnknown { virtual HRESULT STDMETHODCALLTYPE Scale(LONG, LONG *) = 0; };
template<class T> static T load(HMODULE module, const char *name) {
	FARPROC address = GetProcAddress(module, name);
	T result = nullptr;
	static_assert(sizeof(result) == sizeof(address));
	std::memcpy(&result, &address, sizeof(result));
	return result;
}
#define CHECK(test) do { if (!(test)) { std::printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
#endif
