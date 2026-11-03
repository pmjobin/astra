// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <cassert>
#include <cstdint>
#include <cstdio>
inline constexpr IID opaque_iid = {0x1d665f00, 0x16ab, 0x4a63, {0xb3, 0xfc, 0x80, 0x26, 0x26, 0x01, 0x66, 0x01}};
using Callback = BOOL(STDMETHODCALLTYPE *)(void *, BOOL);

struct Oracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE get_count(LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE set_count(LONG) = 0;
	virtual HRESULT STDMETHODCALLTYPE evaluate(DOUBLE, DOUBLE *) = 0;
	virtual HRESULT STDMETHODCALLTYPE snapshot(const BYTE *, LONG, BYTE **, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE visit(BOOL, Callback, void *, BOOL *) = 0;
};
struct Native;

struct Error {
	std::int32_t domain, code;
};

extern "C" std::int32_t opaquecom16_native_run(void);
extern "C" std::int32_t opaquecom16_import_run(void *);
extern "C" std::int32_t opaquecom16_create(std::int32_t, double, Native **, Error *);
extern "C" std::int32_t opaquecom16_get_count(Native *, std::int32_t *, Error *);
extern "C" std::uint32_t opaquecom16_release(Native *);
extern "C" HRESULT opaquecom16_as_com(Native *, IUnknown **);
static unsigned native_retired, provider_retired, callbacks, task_frees;

extern "C" std::int32_t opaquecom16_retired(void) {
	++native_retired;
	return 0;
}

extern "C" void opaquecom16_task_free(void *pointer) {
	assert(pointer);
	++task_frees;
	CoTaskMemFree(pointer);
}

static BOOL STDMETHODCALLTYPE invert(void *data, BOOL input) {
	assert(data == &callbacks);
	++callbacks;
	return !input;
}

class Provider final : public Oracle {
	LONG references = 1;
	LONG count = 7;

	~Provider() { ++provider_retired; }

  public:
	LONG refs() const { return references; }

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) noexcept override {
		if (!out) return E_POINTER;
		*out = nullptr;
		if (!IsEqualIID(iid, opaque_iid) && !IsEqualIID(iid, IID_IUnknown)) return E_NOINTERFACE;
		*out = static_cast<Oracle *>(this);
		AddRef();
		return S_OK;
	}

	ULONG STDMETHODCALLTYPE AddRef() noexcept override { return static_cast<ULONG>(InterlockedIncrement(&references)); }

	ULONG STDMETHODCALLTYPE Release() noexcept override {
		LONG value = InterlockedDecrement(&references);
		if (!value) delete this;
		return static_cast<ULONG>(value);
	}

	HRESULT STDMETHODCALLTYPE get_count(LONG *out) noexcept override {
		if (!out) return E_POINTER;
		*out = count;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE set_count(LONG value) noexcept override {
		count = value;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE evaluate(DOUBLE value, DOUBLE *out) noexcept override {
		if (!out) return E_POINTER;
		*out = 0;
		if (value < 0) return static_cast<HRESULT>(-1600);
		*out = value * 2.5 + count;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE snapshot(const BYTE *input, LONG length, BYTE **out, LONG *size) noexcept override {
		if (!out || !size) return E_POINTER;
		*out = nullptr;
		*size = 0;
		if (length < 0 || (!input && length)) return E_INVALIDARG;
		auto data = static_cast<BYTE *>(CoTaskMemAlloc(static_cast<SIZE_T>(length)));
		if (!data && length) return E_OUTOFMEMORY;
		for (LONG i = 0; i < length; ++i)
			data[i] = input[i] ^ 42;
		*out = data;
		*size = length;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE visit(BOOL value, Callback code, void *data, BOOL *out) noexcept override {
		if (!out || !code) return E_POINTER;
		*out = !!code(data, !!value);
		return S_OK;
	}
};

int main() {
	assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
	assert(opaquecom16_native_run() == 0 && native_retired == 1);
	Native *root = nullptr;
	Error error{};
	assert(opaquecom16_create(7, 1.5, &root, &error) == 0 && root);
	IUnknown *unknown = nullptr;
	assert(opaquecom16_as_com(root, &unknown) == S_OK && unknown);
	void *raw = nullptr;
	assert(unknown->QueryInterface(opaque_iid, &raw) == S_OK && raw);
	auto view = static_cast<Oracle *>(raw);
	raw = nullptr;
	assert(view->QueryInterface(IID_IUnknown, &raw) == S_OK && raw == unknown);
	static_cast<IUnknown *>(raw)->Release();
	assert(view->set_count(23) == S_OK);
	std::int32_t count = 0;
	assert(opaquecom16_get_count(root, &count, &error) == 0 && count == 23);
	DOUBLE value = 99;
	assert(view->evaluate(4, &value) == S_OK && value == 29);
	assert(view->evaluate(-1, &value) == static_cast<HRESULT>(-1600) && value == 0);
	BYTE bytes[] = {3, 0, 254}, *copy = nullptr;
	LONG length = 0;
	assert(view->snapshot(bytes, 3, &copy, &length) == S_OK && copy && length == 3 && copy[0] == 86 && copy[1] == 85 && copy[2] == 171);
	CoTaskMemFree(copy);
	BOOL selected = FALSE;
	assert(view->visit(FALSE, invert, &callbacks, &selected) == S_OK && selected == TRUE && callbacks == 1);
	opaquecom16_release(root);
	unknown->Release();
	assert(native_retired == 1);
	view->Release();
	assert(native_retired == 2);
	auto provider = new Provider();
	assert(opaquecom16_import_run(provider) == 0 && provider->refs() == 1 && task_frees == 1);
	provider->Release();
	assert(provider_retired == 1);
	assert(HeapValidate(GetProcessHeap(), 0, nullptr));
	CoUninitialize();
	std::puts("PASS opaque native COM SDK imports and exports, captured callbacks and exact lifetimes");
	return 0;
}
