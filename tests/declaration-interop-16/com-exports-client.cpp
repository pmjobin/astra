// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <cstdint>
#include <cassert>
#include <cstdio>
#include <cstddef>
#include <cstring>
// Independent ABI: application prototypes do not include the generated SDK.
inline constexpr IID query_iid = {0x473dc7e9, 0x41d6, 0x4768, {0xbd, 0xa4, 0xcc, 0x48, 0x39, 0x6a, 0xf3, 0x01}};
inline constexpr IID detail_iid = {0x473dc7e9, 0x41d6, 0x4768, {0xbd, 0xa4, 0xcc, 0x48, 0x39, 0x6a, 0xf3, 0x02}};
using callback = BOOL(STDMETHODCALLTYPE *)(void *, BOOL);
struct QueryOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE transform(LONGLONG, DOUBLE, BOOL, LONGLONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE get_gain(DOUBLE *) = 0;
	virtual HRESULT STDMETHODCALLTYPE set_gain(DOUBLE) = 0;
	virtual HRESULT STDMETHODCALLTYPE choose(BOOL, callback, void *, BOOL *) = 0;
};
struct DetailOracle : QueryOracle {
	virtual HRESULT STDMETHODCALLTYPE stamp(ULONGLONG, ULONGLONG *) = 0;
};

inline constexpr IID typed_iid = {0x473dc7e9, 0x41d6, 0x4768, {0xbd, 0xa4, 0xcc, 0x48, 0x39, 0x6a, 0xf3, 0x03}};
struct SampleOracle {
	BOOL enabled, marked;
	LONG count;
	DOUBLE scale;
	ULONGLONG stamp;
	FLOAT weight;
	ULONG flags;
	LONGLONG offset;
};
static_assert(sizeof(SampleOracle) == 48 && alignof(SampleOracle) == 8 && offsetof(SampleOracle, marked) == 4 && offsetof(SampleOracle, count) == 8 && offsetof(SampleOracle, scale) == 16 && offsetof(SampleOracle, offset) == 40, "independent exported COM POD layout");
struct TypedOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE amend(SampleOracle, DOUBLE, LONG, SampleOracle *) = 0;
	virtual HRESULT STDMETHODCALLTYPE snapshot(const BYTE *, LONG, BYTE *, LONG, LONG *, LONG, BYTE **, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE text(LONG, char **, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE inspect(const char *, const char *, LONG, LONG *) = 0;
};

inline constexpr IID proxy_iid = {0x473dc7e9, 0x41d6, 0x4768, {0xbd, 0xa4, 0xcc, 0x48, 0x39, 0x6a, 0xf3, 0x04}};
struct ProxyOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE observe(QueryOracle *, LONGLONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE relay(QueryOracle **, QueryOracle **) = 0;
};
static unsigned provider_made, provider_retired, provider_pins, provider_unpins, provider_calls;
class IndependentQuery final : public QueryOracle {
	LONG references = 1;
	~IndependentQuery() { ++provider_retired; }

  public:
	IndependentQuery() { ++provider_made; }
	LONG count() const { return references; }
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) noexcept override {
		if (!out) return E_POINTER;
		*out = nullptr;
		if (!IsEqualIID(iid, query_iid) && !IsEqualIID(iid, IID_IUnknown)) return E_NOINTERFACE;
		*out = static_cast<QueryOracle *>(this);
		AddRef();
		return S_OK;
	}
	ULONG STDMETHODCALLTYPE AddRef() noexcept override {
		++provider_pins;
		return static_cast<ULONG>(InterlockedIncrement(&references));
	}
	ULONG STDMETHODCALLTYPE Release() noexcept override {
		++provider_unpins;
		LONG value = InterlockedDecrement(&references);
		if (!value) delete this;
		return static_cast<ULONG>(value);
	}
	HRESULT STDMETHODCALLTYPE transform(LONGLONG, DOUBLE, BOOL, LONGLONG *) noexcept override { return E_NOTIMPL; }
	HRESULT STDMETHODCALLTYPE get_gain(DOUBLE *out) noexcept override {
		assert(out);
		++provider_calls;
		*out = 3.5;
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE set_gain(DOUBLE) noexcept override { return E_NOTIMPL; }
	HRESULT STDMETHODCALLTYPE choose(BOOL, callback, void *, BOOL *) noexcept override { return E_NOTIMPL; }
};

inline constexpr IID roots_iid = {0x473dc7e9, 0x41d6, 0x4768, {0xbd, 0xa4, 0xcc, 0x48, 0x39, 0x6a, 0xf3, 0x05}};
struct RootsOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE read(QueryOracle *, DOUBLE *) = 0;
	virtual HRESULT STDMETHODCALLTYPE duplicate(QueryOracle *, QueryOracle **) = 0;
	virtual HRESULT STDMETHODCALLTYPE transfer(QueryOracle **, QueryOracle **) = 0;
	virtual HRESULT STDMETHODCALLTYPE lookup(BOOL, QueryOracle *, QueryOracle **) = 0;
};
struct native_handle;
struct native_error {
	std::int32_t domain, code;
};
extern "C" std::int32_t nativequery16_create(double, native_handle **, native_error *);
extern "C" std::int32_t nativequery16_get_gain(native_handle *, double *, native_error *);
extern "C" std::uint32_t nativequery16_release(native_handle *);
extern "C" HRESULT nativequery16_as_com(native_handle *, IUnknown **);
static unsigned destroyed, operations, callbacks;
extern "C" std::int32_t comexport16_retired(void) {
	++destroyed;
	return 0;
}
extern "C" std::int32_t comexport16_operation(void) {
	++operations;
	return 0;
}
static BOOL STDMETHODCALLTYPE invert(void *data, BOOL input) {
	assert(data && input == TRUE);
	++callbacks;
	return 0;
}
struct ThreadProbe {
	QueryOracle *query;
	HRESULT status;
	LONGLONG output;
};
static DWORD WINAPI wrong_thread(void *opaque) {
	auto probe = static_cast<ThreadProbe *>(opaque);
	HRESULT status = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	assert(SUCCEEDED(status));
	probe->output = 99;
	probe->status = probe->query->transform(3, 2.0, TRUE, &probe->output);
	CoUninitialize();
	return 0;
}

static void typed_payloads(IUnknown *unknown) {
	void *raw = nullptr;
	assert(unknown->QueryInterface(typed_iid, &raw) == S_OK && raw && raw != unknown);
	auto typed = static_cast<TypedOracle *>(raw);
	raw = nullptr;
	assert(typed->QueryInterface(IID_IUnknown, &raw) == S_OK && raw == unknown);
	static_cast<IUnknown *>(raw)->Release();
	SampleOracle input{TRUE, FALSE, 4, 2.5, UINT64_C(9223372036854775809), 1.25f, UINT32_C(4000000000), INT64_C(-5000000000)}, output{};
	assert(typed->amend(input, 0.5, 0, &output) == S_OK && !output.enabled && output.marked == TRUE && output.count == 11 && output.scale == 3.0 && output.stamp == input.stamp && output.weight == 3.25f && output.flags == input.flags && output.offset == input.offset);
	output.count = 99;
	assert(typed->amend(input, 0.5, 1, &output) == static_cast<HRESULT>(-1600) && output.count == 0 && output.scale == 0 && output.marked == 0);
	BYTE bytes[] = {3, 4, 5}, destination[] = {77, 77, 77, 77};
	LONG count = -1, length = -1;
	BYTE *data = nullptr;
	assert(typed->snapshot(bytes, 3, destination, 4, &count, 0, &data, &length) == S_OK && count == 3 && destination[0] == 23 && destination[2] == 25 && destination[3] == 77 && bytes[0] == 3 && length == 3 && data && data[0] == 13 && data[2] == 15);
	CoTaskMemFree(data);
	data = nullptr;
	count = -1;
	length = -1;
	std::memset(destination, 77, 4);
	assert(typed->snapshot(bytes, 3, destination, 4, &count, 1, &data, &length) == static_cast<HRESULT>(-1600) && !data && length == 0 && count == 0 && destination[0] == 77 && destination[2] == 77);
	char *text = nullptr;
	assert(typed->text(0, &text, &length) == S_OK && length == 4 && text && text[0] == 'a' && text[1] == 0 && static_cast<unsigned char>(text[2]) == 195 && static_cast<unsigned char>(text[3]) == 169);
	CoTaskMemFree(text);
	text = nullptr;
	assert(typed->text(1, &text, &length) == S_OK && length == 0);
	CoTaskMemFree(text);
	const char nul[] = {99, 97, 102, static_cast<char>(195), static_cast<char>(169), 0}, counted[] = {97, 0, static_cast<char>(195), static_cast<char>(169)};
	LONG result = 0;
	assert(typed->inspect(nul, counted, 4, &result) == S_OK && result == 9);
	typed->Release();
}

static void interface_payloads(IUnknown *unknown) {
	void *raw = nullptr;
	assert(unknown->QueryInterface(proxy_iid, &raw) == S_OK && raw);
	auto proxy = static_cast<ProxyOracle *>(raw);
	auto provider = new IndependentQuery();
	LONGLONG value = 99;
	assert(proxy->observe(provider, &value) == S_OK && value == 3 && provider->count() == 1 && provider_calls == 1);
	QueryOracle *input = provider, *out = nullptr;
	assert(proxy->relay(&input, &out) == S_OK && !input && out == provider && provider->count() == 1);
	out->Release();
	assert(provider_made == 1 && provider_retired == 1 && provider_pins + 1 == provider_unpins);
	proxy->Release();
}

static void native_class_payloads(IUnknown *unknown, QueryOracle *query) {
	void *raw = nullptr;
	assert(unknown->QueryInterface(roots_iid, &raw) == S_OK && raw);
	auto roots = static_cast<RootsOracle *>(raw);
	DOUBLE gain = 0;
	assert(roots->read(query, &gain) == S_OK && gain == 3.5);
	QueryOracle *out = nullptr;
	assert(roots->duplicate(query, &out) == S_OK && out == query);
	out->Release();
	raw = nullptr;
	assert(unknown->QueryInterface(query_iid, &raw) == S_OK);
	auto input = static_cast<QueryOracle *>(raw);
	assert(roots->transfer(&input, &input) == E_INVALIDARG && input);
	out = nullptr;
	assert(roots->transfer(&input, &out) == S_OK && !input && out == query);
	out->Release();
	out = query;
	assert(roots->lookup(FALSE, query, &out) == S_FALSE && !out);
	assert(roots->lookup(TRUE, query, &out) == S_OK && out == query);
	out->Release();
	auto foreign = new IndependentQuery();
	gain = 99;
	assert(roots->read(foreign, &gain) == E_NOINTERFACE && gain == 0 && foreign->count() == 1);
	foreign->Release();
	assert(provider_made == 2 && provider_retired == 2 && provider_pins + 2 == provider_unpins);
	roots->Release();
}
static BOOL STDMETHODCALLTYPE release_last(void *opaque, BOOL input) {
	assert(input == TRUE);
	static_cast<QueryOracle *>(opaque)->Release();
	return TRUE;
}
int main() {
	assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
	native_handle *root = nullptr;
	native_error error{};
	assert(nativequery16_create(1.5, &root, &error) == 0 && root);
	IUnknown *unknown = nullptr;
	assert(nativequery16_as_com(root, &unknown) == S_OK && unknown);
	void *raw = nullptr;
	assert(unknown->QueryInterface(query_iid, &raw) == S_OK && raw);
	auto query = static_cast<QueryOracle *>(raw);
	raw = nullptr;
	assert(query->QueryInterface(detail_iid, &raw) == S_OK && raw);
	auto detail = static_cast<DetailOracle *>(raw);
	raw = nullptr;
	assert(detail->QueryInterface(IID_IUnknown, &raw) == S_OK && raw == unknown);
	static_cast<IUnknown *>(raw)->Release();
	LONGLONG value = 99;
	assert(query->transform(5000000000, 2.0, TRUE, &value) == S_OK && value == 5000000007);
	assert(query->transform(-1, 2.0, TRUE, &value) == static_cast<HRESULT>(-1600) && value == 0);
	assert(query->set_gain(3.5) == S_OK);
	DOUBLE gain = 0;
	assert(detail->get_gain(&gain) == S_OK && gain == 3.5);
	double c_gain = 0;
	assert(nativequery16_get_gain(root, &c_gain, &error) == 0 && c_gain == gain);
	BOOL choice = 99;
	assert(query->choose(7, invert, &choice, &choice) == S_OK && choice == FALSE && callbacks == 1);
	ULONGLONG stamp = 0;
	assert(detail->stamp(UINT64_C(9223372036854775809), &stamp) == S_OK && stamp == UINT64_C(9223372036854775818));
	ThreadProbe probe{query, E_FAIL, 99};
	HANDLE thread = CreateThread(nullptr, 0, wrong_thread, &probe, 0, nullptr);
	assert(thread && WaitForSingleObject(thread, 10000) == WAIT_OBJECT_0);
	CloseHandle(thread);
	assert(probe.status == RPC_E_WRONG_THREAD && probe.output == 0);
	raw = reinterpret_cast<void *>(1);
	assert(query->QueryInterface(IID_IClassFactory, &raw) == E_NOINTERFACE && !raw);
	assert(operations == 7 && !destroyed);
	typed_payloads(unknown);
	assert(operations == 14 && !destroyed);
	interface_payloads(unknown);
	assert(operations == 16 && !destroyed);
	native_class_payloads(unknown, query);
	assert(operations == 22 && !destroyed);
	nativequery16_release(root);
	query->Release();
	detail->Release();
	assert(!destroyed);
	unknown->Release();
	assert(destroyed == 1);
	root = nullptr;
	assert(nativequery16_create(1.0, &root, &error) == 0);
	unknown = nullptr;
	assert(nativequery16_as_com(root, &unknown) == S_OK);
	raw = nullptr;
	assert(unknown->QueryInterface(query_iid, &raw) == S_OK);
	query = static_cast<QueryOracle *>(raw);
	nativequery16_release(root);
	unknown->Release();
	choice = 0;
	assert(query->choose(TRUE, release_last, query, &choice) == S_OK && choice == TRUE && destroyed == 2 && operations == 23);
	CoUninitialize();
	std::puts("PASS typed COM exports execute native Astra algorithms and share canonical root");
	return 0;
}
