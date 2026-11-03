// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cstdio>
#include <cassert>
// Independent ABI declarations: no generated SDK is used to define this producer.
inline constexpr IID query_iid = {0x2c2d4a08, 0xa483, 0x4ace, {0x9e, 0x01, 0xf6, 0x79, 0x3e, 0x47, 0xf1, 0x01}};
inline constexpr IID detail_iid = {0x2c2d4a08, 0xa483, 0x4ace, {0x9e, 0x01, 0xf6, 0x79, 0x3e, 0x47, 0xf1, 0x02}};
inline constexpr IID records_iid = {0x2c2d4a08, 0xa483, 0x4ace, {0x9e, 0x01, 0xf6, 0x79, 0x3e, 0x47, 0xf1, 0x03}};
using boolean_callback = BOOL(STDMETHODCALLTYPE *)(void *, BOOL);

struct QueryOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE transform(LONGLONG, DOUBLE, BOOL, LONGLONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE get_gain(DOUBLE *) = 0;
	virtual HRESULT STDMETHODCALLTYPE set_gain(DOUBLE) = 0;
	virtual HRESULT STDMETHODCALLTYPE choose(BOOL, boolean_callback, void *, BOOL *) = 0;
};

struct DetailOracle : QueryOracle {
	virtual HRESULT STDMETHODCALLTYPE stamp(ULONGLONG, ULONGLONG *) = 0;
};

struct SampleOracle {
	BOOL enabled;
	BOOL marked;
	LONG count;
	DOUBLE scale;
	ULONGLONG stamp;
	FLOAT weight;
	ULONG flags;
	LONGLONG offset;
};

static_assert(sizeof(SampleOracle) == 48 && alignof(SampleOracle) == 8 && offsetof(SampleOracle, marked) == 4 && offsetof(SampleOracle, count) == 8 && offsetof(SampleOracle, scale) == 16 && offsetof(SampleOracle, offset) == 40, "independent Windows COM record oracle");

struct RecordsOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE amend(SampleOracle, DOUBLE, LONG, SampleOracle *) = 0;
	virtual HRESULT STDMETHODCALLTYPE snapshot(const BYTE *, LONG, BYTE *, LONG, LONG *, LONG, BYTE **, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE text(LONG, char **, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE inspect(const char *, const char *, LONG, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE compare(QueryOracle *, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE make(LONG, QueryOracle **) = 0;
	virtual HRESULT STDMETHODCALLTYPE lookup(LONG, QueryOracle **) = 0;
	virtual HRESULT STDMETHODCALLTYPE take(QueryOracle **, LONG, LONG *) = 0;
};

static unsigned made, retired, exceptions, queries, transforms, reads, writes, choices, stamps, pins, unpins;
static void *task_allocations[32];
static unsigned task_allocated, task_freed;

static void *task_allocate(std::size_t size) {
	assert(task_allocated < 32);
	void *value = CoTaskMemAlloc(size);
	assert(value);
	task_allocations[task_allocated++] = value;
	return value;
}

extern "C" void com16_task_free(void *value) {
	if (!value) return;
	bool found = false;
	for (unsigned i = 0; i < task_allocated; ++i) {
		if (task_allocations[i] == value) {
			assert(!found);
			task_allocations[i] = nullptr;
			found = true;
		}
	}
	assert(found);
	++task_freed;
	CoTaskMemFree(value);
}

extern "C" std::int32_t com16_exception_retired(void) {
	++exceptions;
	return 0;
}

extern "C" std::int32_t com16_run(void *);
extern "C" std::int32_t com16_space(void *);
extern "C" std::int32_t com16_records(void *);
extern "C" std::int32_t com16_payloads(void *);
extern "C" std::int32_t com16_objects(void *);

class Oracle final : public DetailOracle, public RecordsOracle {
	LONG references = 1;
	DWORD thread = GetCurrentThreadId();
	double gain = 1.5;
	bool fail;

	~Oracle() { ++retired; }

  public:
	explicit Oracle(bool fail = false) : fail(fail) { ++made; }

	LONG count() const { return references; }

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) noexcept override {
		assert(out);
		*out = nullptr;
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		++queries;
		if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, query_iid))
			*out = static_cast<QueryOracle *>(this);
		else if (IsEqualIID(iid, detail_iid))
			*out = static_cast<DetailOracle *>(this);
		else if (IsEqualIID(iid, records_iid))
			*out = static_cast<RecordsOracle *>(this);
		else
			return E_NOINTERFACE;
		AddRef();
		return S_OK;
	}

	ULONG STDMETHODCALLTYPE AddRef() noexcept override {
		++pins;
		return static_cast<ULONG>(InterlockedIncrement(&references));
	}

	ULONG STDMETHODCALLTYPE Release() noexcept override {
		++unpins;
		LONG remaining = InterlockedDecrement(&references);
		if (!remaining) delete this;
		return static_cast<ULONG>(remaining);
	}

	HRESULT STDMETHODCALLTYPE transform(LONGLONG input, DOUBLE bias, BOOL enabled, LONGLONG *out) noexcept override {
		assert(GetCurrentThreadId() == thread && out && bias == 2.5 && enabled == TRUE);
		++transforms;
		*out = 99;
		if (fail) return static_cast<HRESULT>(-1600);
		*out = input + 7;
		return S_FALSE;
	}

	HRESULT STDMETHODCALLTYPE get_gain(DOUBLE *out) noexcept override {
		assert(out);
		++reads;
		*out = gain;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE set_gain(DOUBLE value) noexcept override {
		++writes;
		gain = value;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE choose(BOOL input, boolean_callback code, void *data, BOOL *out) noexcept override {
		assert(code && data && out && (input == TRUE || input == FALSE));
		++choices;
		BOOL value = code(data, input);
		assert(value == TRUE || value == FALSE);
		*out = value ? 7 : 0;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE stamp(ULONGLONG input, ULONGLONG *out) noexcept override {
		assert(out && input == UINT64_C(9223372036854775809));
		++stamps;
		*out = input + 7;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE amend(SampleOracle input, DOUBLE delta, LONG mode, SampleOracle *out) noexcept override {
		assert(out && input.enabled == TRUE && input.marked == FALSE && input.count == 4 && input.scale == 2.5 && input.stamp == UINT64_C(9223372036854775809) && input.weight == 1.25f && input.flags == UINT32_C(4000000000) && input.offset == INT64_C(-5000000000) && delta == 0.5);
		*out = input;
		out->enabled = 0;
		out->marked = 7;
		out->count += 7;
		out->scale += delta;
		out->weight += 2;
		if (mode) return static_cast<HRESULT>(-1600);
		return S_FALSE;
	}

	HRESULT STDMETHODCALLTYPE snapshot(const BYTE *input, LONG length, BYTE *output, LONG capacity, LONG *count, LONG mode, BYTE **result, LONG *result_length) noexcept override {
		assert(input && length == 3 && input[0] == 3 && input[2] == 5 && capacity == 4 && output && count && result && result_length);
		output[0] = 23;
		output[1] = 24;
		*count = 2;
		auto data = static_cast<BYTE *>(task_allocate(3));
		data[0] = 13;
		data[1] = 14;
		data[2] = 15;
		*result = data;
		*result_length = 3;
		if (mode == 1) return static_cast<HRESULT>(-1600);
		if (mode == 2) *count = 5;
		if (mode == 3) *result_length = -1;
		return S_FALSE;
	}

	HRESULT STDMETHODCALLTYPE text(LONG mode, char **result, LONG *length) noexcept override {
		assert(result && length);
		auto data = static_cast<char *>(task_allocate(5));
		const unsigned char valid[] = {97, 0, 195, 169, 0};
		std::memcpy(data, valid, 5);
		if (mode) data[2] = static_cast<char>(0xff);
		*result = data;
		*length = 4;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE inspect(const char *nul, const char *counted, LONG length, LONG *result) noexcept override {
		assert(nul && counted && result && std::strlen(nul) == 5 && length == 4 && counted[1] == 0 && static_cast<unsigned char>(counted[2]) == 195);
		*result = 9;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE compare(QueryOracle *input, LONG *out) noexcept override {
		assert(input == static_cast<QueryOracle *>(this) && out);
		*out = 77;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE make(LONG mode, QueryOracle **out) noexcept override {
		assert(out);
		*out = nullptr;
		if (mode == 2) return S_OK;
		*out = static_cast<QueryOracle *>(this);
		AddRef();
		return mode == 1 ? static_cast<HRESULT>(-1600) : S_OK;
	}

	HRESULT STDMETHODCALLTYPE lookup(LONG mode, QueryOracle **out) noexcept override {
		assert(out);
		*out = nullptr;
		if (!mode) return S_FALSE;
		*out = static_cast<QueryOracle *>(this);
		AddRef();
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE take(QueryOracle **input, LONG mode, LONG *out) noexcept override {
		assert(input && *input == static_cast<QueryOracle *>(this) && out);
		*out = 88;
		if (!mode) {
			(*input)->Release();
			*input = nullptr;
		}
		return mode == 1 ? static_cast<HRESULT>(-1600) : S_OK;
	}
};

class Absent final : public IUnknown {
	LONG references = 1;

  public:
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, void **out) noexcept override {
		*out = nullptr;
		return E_NOINTERFACE;
	}

	ULONG STDMETHODCALLTYPE AddRef() noexcept override { return static_cast<ULONG>(InterlockedIncrement(&references)); }

	ULONG STDMETHODCALLTYPE Release() noexcept override {
		LONG value = InterlockedDecrement(&references);
		if (!value) delete this;
		return static_cast<ULONG>(value);
	}
};

struct query16_handle;

struct bridge_error {
	std::int32_t domain, code;
};

extern "C" std::int32_t query16_acquire(void *, query16_handle **, bridge_error *);
extern "C" std::uint32_t query16_release(query16_handle *);
extern "C" std::int32_t query16_get_gain(query16_handle *, double *, bridge_error *);
extern "C" std::int32_t query16_choose(query16_handle *, bool, bool (*)(void *, bool), void *, bool *, bridge_error *);

struct CarrierRelease {
	query16_handle *owner;
	bool called;
};

static bool release_carrier(void *opaque, bool input) {
	auto context = static_cast<CarrierRelease *>(opaque);
	assert(!input && !context->called);
	context->called = true;
	query16_release(context->owner);
	double gain = 0;
	bridge_error error{};
	assert(query16_get_gain(context->owner, &gain, &error) == 0 && gain == 1.5);
	return true;
}

static void carrier_reentry() {
	auto provider = new Oracle();
	query16_handle *owner = nullptr;
	bridge_error error{};
	assert(query16_acquire(static_cast<DetailOracle *>(provider), &owner, &error) == 0 && owner);
	CarrierRelease context{owner, false};
	bool result = false;
	assert(query16_choose(owner, false, release_carrier, &context, &result, &error) == 0 && result && context.called && provider->count() == 1);
	provider->Release();
}

int main() {
	HRESULT status = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	assert(SUCCEEDED(status));
	auto provider = new Oracle();
	assert(com16_run(static_cast<DetailOracle *>(provider)) == 0 && provider->count() == 1);
	assert(queries == 2 && transforms == 1 && reads == 2 && writes == 1 && choices == 2 && stamps == 1 && made == 1 && retired == 0 && exceptions == 0);
	assert(com16_records(static_cast<DetailOracle *>(provider)) == 0 && provider->count() == 1 && exceptions == 1);
	assert(com16_payloads(static_cast<DetailOracle *>(provider)) == 0 && provider->count() == 1 && exceptions == 6);
	assert(com16_objects(static_cast<DetailOracle *>(provider)) == 0 && provider->count() == 1 && exceptions == 9);
	provider->Release();
	assert(retired == 1 && pins + 1 == unpins);
	assert(com16_run(nullptr) == static_cast<std::int32_t>(E_POINTER) && exceptions == 10);
	auto absent = new Absent();
	assert(com16_run(absent) == static_cast<std::int32_t>(E_NOINTERFACE) && exceptions == 11);
	absent->Release();
	provider = new Oracle(true);
	assert(com16_space(static_cast<DetailOracle *>(provider)) == 16 && exceptions == 12 && provider->count() == 1);
	provider->Release();
	assert(made == 2 && retired == 2 && pins + 2 == unpins);
	carrier_reentry();
	assert(made == 3 && retired == 3 && pins + 3 == unpins);
	assert(task_allocated == 6 && task_freed == task_allocated);
	for (void *value : task_allocations)
		assert(!value);
	CoUninitialize();
	std::puts("PASS typed COM imports, inherited slots, BOOL32 callbacks and exact foreign references");
	return 0;
}
