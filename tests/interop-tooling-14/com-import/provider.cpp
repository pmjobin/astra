// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Independent Windows SDK producer; no generated Astra declarations.
#include <windows.h>
#include <unknwn.h>
#include <new>
static constexpr IID VALUE = {0x849ad154, 0x8d1e, 0x4c63, {0x9e, 0xa2, 0x14, 0x32, 0x9b, 0x02, 0x20, 0x01}};
static constexpr IID SCALE = {0x849ad154, 0x8d1e, 0x4c63, {0x9e, 0xa2, 0x14, 0x32, 0x9b, 0x02, 0x20, 0x02}};

struct Value : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE Get(LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE Set(LONG) = 0;
};

struct Scaling : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE Scale(LONG, LONG *) = 0;
};

static LONG counters[8];
static LONG mode;

class Producer final : public Value, public Scaling {
	LONG owners = 1;
	LONG value = 40;
	DWORD thread = GetCurrentThreadId();

	~Producer() { InterlockedIncrement(&counters[1]); }

  public:
	Producer() {
		InterlockedIncrement(&counters[0]);
		InterlockedIncrement(&counters[2]);
	}

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override {
		InterlockedIncrement(&counters[3]);
		if (!out) return E_POINTER;
		*out = nullptr;
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		if (mode == 2) return S_OK; // Deliberate broken-provider success/null control.
		if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, VALUE))
			*out = static_cast<Value *>(this);
		else if (IsEqualIID(iid, SCALE))
			*out = static_cast<Scaling *>(this);
		else
			return E_NOINTERFACE;
		AddRef();
		return mode == 1 ? E_NOINTERFACE : mode == 3 ? S_FALSE
		                                             : S_OK;
	}

	ULONG STDMETHODCALLTYPE AddRef() override {
		InterlockedIncrement(&counters[2]);
		return static_cast<ULONG>(InterlockedIncrement(&owners));
	}

	ULONG STDMETHODCALLTYPE Release() override {
		LONG remaining = InterlockedDecrement(&owners);
		InterlockedDecrement(&counters[2]);
		if (remaining < 0) InterlockedIncrement(&counters[7]);
		if (!remaining) delete this;
		return static_cast<ULONG>(remaining);
	}

	HRESULT STDMETHODCALLTYPE Get(LONG *out) override {
		InterlockedIncrement(&counters[4]);
		if (!out) return E_POINTER;
		*out = 0;
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		if (mode == 4) {
			*out = 777;
			return E_FAIL;
		}
		*out = value;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE Set(LONG input) override {
		InterlockedIncrement(&counters[5]);
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		value = input;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE Scale(LONG factor, LONG *out) override {
		InterlockedIncrement(&counters[6]);
		if (!out) return E_POINTER;
		*out = 0;
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		if (mode == 5) {
			*out = 888;
			return E_FAIL;
		}
		if (factor < 0 || factor > 100 || value < 0 || value > 100) return E_INVALIDARG;
		*out = value * factor;
		return factor == 0 ? S_FALSE : S_OK;
	}
};

extern "C" __declspec(dllexport) HRESULT producer_create(IUnknown **out) {
	if (!out) return E_POINTER;
	auto result = new (std::nothrow) Producer();
	*out = result ? static_cast<Value *>(result) : nullptr;
	return *out ? S_OK : E_OUTOFMEMORY;
}

extern "C" __declspec(dllexport) LONG producer_stats(LONG index) {
	return index >= 0 && index < 8 ? InterlockedCompareExchange(&counters[index], 0, 0) : -1;
}

extern "C" __declspec(dllexport) void producer_mode(LONG value) {
	mode = value;
}
