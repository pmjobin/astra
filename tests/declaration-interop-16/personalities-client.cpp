// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <cstdint>
#include <cassert>
#include <cstdio>
// Independent IID, slot sequence and BOOL32 declarations.
inline constexpr IID facet_iid = {0xe4211800, 0x12cb, 0x4d3a, {0xbc, 0xda, 0x80, 0x16, 0x26, 0x01, 0x66, 0x11}};
using Callback = BOOL(STDMETHODCALLTYPE *)(void *, BOOL);
struct Facet : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE get_count(LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE set_count(LONG) = 0;
	virtual HRESULT STDMETHODCALLTYPE evaluate(DOUBLE, DOUBLE *) = 0;
	virtual HRESULT STDMETHODCALLTYPE visit(BOOL, Callback, void *, BOOL *) = 0;
};
struct Native;
struct Error {
	std::int32_t domain, code;
};
extern "C" std::int32_t personality16_native_run(void);
extern "C" std::int32_t personality16_native_create(std::int32_t, bool, double, Native **, Error *);
extern "C" std::int32_t personality16_native_get_count(Native *, std::int32_t *, Error *);
extern "C" std::uint32_t personality16_native_release(Native *);
extern "C" HRESULT personality16_native_as_com(Native *, IUnknown **);
static unsigned destroyed, callbacks;
extern "C" std::int32_t personality16_retired(void) {
	++destroyed;
	return 0;
}
static BOOL STDMETHODCALLTYPE invert(void *data, BOOL input) {
	assert(data == &callbacks);
	++callbacks;
	return !input;
}
int main() {
	assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
	assert(personality16_native_run() == 0 && destroyed == 1);
	Native *root = nullptr;
	Error error{};
	assert(personality16_native_create(7, true, 1.5, &root, &error) == 0 && root);
	IUnknown *unknown = nullptr;
	assert(personality16_native_as_com(root, &unknown) == S_OK && unknown);
	void *raw = nullptr;
	assert(unknown->QueryInterface(facet_iid, &raw) == S_OK && raw);
	auto facet = static_cast<Facet *>(raw);
	raw = nullptr;
	assert(facet->QueryInterface(IID_IUnknown, &raw) == S_OK && raw == unknown);
	static_cast<IUnknown *>(raw)->Release();
	DOUBLE value = 99;
	assert(facet->evaluate(2, &value) == S_OK && value == 10);
	assert(facet->evaluate(-1, &value) == static_cast<HRESULT>(-1600) && value == 0);
	assert(facet->set_count(23) == S_OK);
	std::int32_t count = 0;
	assert(personality16_native_get_count(root, &count, &error) == 0 && count == 23);
	BOOL chosen = FALSE;
	assert(facet->visit(FALSE, invert, &callbacks, &chosen) == S_OK && chosen == TRUE && callbacks == 1);
	personality16_native_release(root);
	unknown->Release();
	assert(destroyed == 1);
	facet->Release();
	assert(destroyed == 2);
	CoUninitialize();
	std::puts("PASS common declaration C and COM personalities, captured callback and exact native lifetime");
	return 0;
}
