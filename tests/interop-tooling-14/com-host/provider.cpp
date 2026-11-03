// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "interfaces.hpp"
#include <new>

static LONG destroyed;

class Probe final : public Value14, public Scale14 {
	LONG owners = 1;
	LONG value = 40;
	DWORD thread = GetCurrentThreadId();

	~Probe() { InterlockedIncrement(&destroyed); }

  public:
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, IID_Value14))
			*out = static_cast<Value14 *>(this);
		else if (IsEqualIID(iid, IID_Scale14))
			*out = static_cast<Scale14 *>(this);
		else
			return E_NOINTERFACE;
		AddRef();
		return S_OK;
	}

	ULONG STDMETHODCALLTYPE AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&owners)); }

	ULONG STDMETHODCALLTYPE Release() override {
		LONG remaining = InterlockedDecrement(&owners);
		if (!remaining) delete this;
		return static_cast<ULONG>(remaining);
	}

	HRESULT STDMETHODCALLTYPE Get(LONG *out) override {
		if (!out) return E_POINTER;
		*out = 0;
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		*out = value;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE Set(LONG input) override {
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		value = input;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE Scale(LONG factor, LONG *out) override {
		if (!out) return E_POINTER;
		*out = 0;
		if (GetCurrentThreadId() != thread) return RPC_E_WRONG_THREAD;
		if (factor < 0 || factor > 100 || value < 0 || value > 100) return E_INVALIDARG;
		*out = value * factor;
		return factor == 0 ? S_FALSE : S_OK;
	}
};

extern "C" __declspec(dllexport) HRESULT probe_create(IUnknown **out) {
	if (!out) return E_POINTER;
	*out = nullptr;
	auto p = new (std::nothrow) Probe();
	if (!p) return E_OUTOFMEMORY;
	*out = static_cast<Value14 *>(p);
	return S_OK;
}

extern "C" __declspec(dllexport) LONG probe_destroyed() {
	return destroyed;
}
