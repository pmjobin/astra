/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <cstdio>
inline constexpr IID query_iid = {0xbbc8184e, 0xeca4, 0x4986, {0x97, 0x7b, 0xf2, 0x71, 0x0b, 0xf1, 0x39, 0x5c}};
inline constexpr IID metadata_iid = {0x4605c677, 0xb6cb, 0x4ecf, {0xad, 0xa6, 0x57, 0xd7, 0x95, 0x02, 0x76, 0x0f}};
inline constexpr IID entry_iid = {0xef5eb6da, 0x4c07, 0x4edb, {0xa4, 0xd9, 0x1d, 0x62, 0xed, 0xe3, 0x1d, 0x9e}};
#ifdef USE_SDK
#include "sdk.hpp"
#include "api-com-types.h"
#else

struct Query {
	DOUBLE ceiling;
	LONGLONG minimum;
	ULONGLONG cap;
	ULONG mask;
	BOOL lowest;
};

struct Answer {
	DOUBLE score;
	LONGLONG code;
	ULONG matches;
	BOOL found;
	ULONGLONG visited;
};

struct EntryOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE get_code(LONGLONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE get_score(DOUBLE *) = 0;
};

struct QueryOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE resolve(Query, EntryOracle **) = 0;
	virtual HRESULT STDMETHODCALLTYPE lookup(Query, Answer *) = 0;
};

struct MetadataOracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE get_requests(LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE get_enabled(BOOL *) = 0;
	virtual HRESULT STDMETHODCALLTYPE set_enabled(BOOL) = 0;
	virtual HRESULT STDMETHODCALLTYPE get_bias(DOUBLE *) = 0;
	virtual HRESULT STDMETHODCALLTYPE set_bias(DOUBLE) = 0;
};
struct Native;

struct Error {
	std::int32_t domain, code;
};

extern "C" std::int32_t catalog16_create(Native **, Error *);
extern "C" std::uint32_t catalog16_release(Native *);
extern "C" HRESULT catalog16_as_com(Native *, IUnknown **);
#define Q_CEILING(v) ((v).ceiling)
#define Q_MIN(v) ((v).minimum)
#define Q_CAP(v) ((v).cap)
#define Q_MASK(v) ((v).mask)
#define Q_LOWEST(v) ((v).lowest)
#define A_SCORE(v) ((v).score)
#define A_CODE(v) ((v).code)
#define A_MATCHES(v) ((v).matches)
#define A_FOUND(v) ((v).found)
#define A_VISITED(v) ((v).visited)
static_assert(sizeof(Query) == 32 && offsetof(Query, lowest) == 28 && sizeof(Answer) == 32 && offsetof(Answer, visited) == 24, "independent COM LLP64/bool32 POD layout");
#endif
extern "C" std::int32_t catalog16_import_provider(void *);
extern "C" std::uint32_t lens16_retired_count(std::int32_t);
static unsigned providers_retired, entries_retired;

class ProviderEntry final : public EntryOracle {
	ULONG refs_ = 1;
	LONGLONG code_;
	DOUBLE score_;

  public:
	ProviderEntry(LONGLONG code, DOUBLE score) : code_(code), score_(score) {}

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, entry_iid)) return E_NOINTERFACE;
		*out = static_cast<EntryOracle *>(this);
		AddRef();
		return S_OK;
	}

	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }

	ULONG STDMETHODCALLTYPE Release() override {
		ULONG result = --refs_;
		if (!result) {
			++entries_retired;
			delete this;
		}
		return result;
	}

	HRESULT STDMETHODCALLTYPE get_code(LONGLONG *out) override {
		if (!out) return E_POINTER;
		*out = code_;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE get_score(DOUBLE *out) override {
		if (!out) return E_POINTER;
		*out = score_;
		return S_OK;
	}
};

class Provider final : public QueryOracle, public MetadataOracle {
	ULONG refs_ = 1;
	LONG calls_ = 0;
	BOOL enabled_ = TRUE;
	DOUBLE bias_ = 0;

  public:
	ULONG refs() const { return refs_; }

	LONG calls() const { return calls_; }

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, query_iid))
			*out = static_cast<QueryOracle *>(this);
		else if (IsEqualIID(iid, metadata_iid))
			*out = static_cast<MetadataOracle *>(this);
		else
			return E_NOINTERFACE;
		AddRef();
		return S_OK;
	}

	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }

	ULONG STDMETHODCALLTYPE Release() override {
		ULONG result = --refs_;
		if (!result) {
			++providers_retired;
			delete this;
		}
		return result;
	}

	HRESULT STDMETHODCALLTYPE lookup(Query input, Answer *out) override {
		if (!out) return E_POINTER;
		*out = {};
		if (!enabled_) return static_cast<HRESULT>(-1620);
		++calls_;
		if (!Q_MASK(input)) return S_OK;
		A_CODE(*out) = 1000 + Q_MIN(input);
		A_SCORE(*out) = Q_CEILING(input) * 0.5 + bias_;
		A_MATCHES(*out) = 2;
		A_FOUND(*out) = TRUE;
		A_VISITED(*out) = 9;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE resolve(Query input, EntryOracle **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		Answer result{};
		HRESULT status = lookup(input, &result);
		if (FAILED(status)) return status;
		if (!A_FOUND(result)) return S_FALSE;
		*out = new ProviderEntry(A_CODE(result), A_SCORE(result));
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE get_requests(LONG *out) override {
		if (!out) return E_POINTER;
		*out = calls_;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE get_enabled(BOOL *out) override {
		if (!out) return E_POINTER;
		*out = enabled_;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE set_enabled(BOOL value) override {
		enabled_ = value != FALSE;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE get_bias(DOUBLE *out) override {
		if (!out) return E_POINTER;
		*out = bias_;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE set_bias(DOUBLE value) override {
		bias_ = value;
		return S_OK;
	}
};

static DWORD WINAPI wrong_thread(void *data) {
	auto query = static_cast<QueryOracle *>(data);
	Query input{};
	Answer out{};
	A_CODE(out) = 99;
	return query->lookup(input, &out) == RPC_E_WRONG_THREAD && A_CODE(out) == 0 && A_VISITED(out) == 0 ? 0 : 1;
}

int main() {
	assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
	Native *root = nullptr;
	Error error{};
	assert(catalog16_create(&root, &error) == 0 && root);
	IUnknown *unknown = nullptr;
	assert(catalog16_as_com(root, &unknown) == S_OK && unknown);
	void *raw = nullptr;
	assert(unknown->QueryInterface(query_iid, &raw) == S_OK && raw);
	auto query = static_cast<QueryOracle *>(raw);
	raw = nullptr;
	assert(query->QueryInterface(metadata_iid, &raw) == S_OK && raw);
	auto metadata = static_cast<MetadataOracle *>(raw);
	raw = nullptr;
	assert(metadata->QueryInterface(IID_IUnknown, &raw) == S_OK && raw == unknown);
	static_cast<IUnknown *>(raw)->Release();
	Query input{10, 0, 0, 7, TRUE};
	Answer answer{};
	assert(query->lookup(input, &answer) == S_OK && A_CODE(answer) == 59 && A_SCORE(answer) == 1.75 && A_MATCHES(answer) == 3 && A_FOUND(answer) == TRUE && A_VISITED(answer) == 3);
	Q_CAP(input) = 1;
	assert(query->lookup(input, &answer) == S_OK && A_CODE(answer) == 17 && A_SCORE(answer) == 2.25 && A_MATCHES(answer) == 1);
	Q_CAP(input) = 0;
	Q_MIN(input) = 20;
	Q_LOWEST(input) = FALSE;
	EntryOracle *held = nullptr;
	assert(query->resolve(input, &held) == S_OK && held);
	LONGLONG code = 0;
	DOUBLE score = 0;
	assert(held->get_code(&code) == S_OK && code == 31 && held->get_score(&score) == S_OK && score == 5.5);
	LONG calls = 0;
	assert(metadata->get_requests(&calls) == S_OK && calls == 3);
	Q_MASK(input) = 0;
	EntryOracle *missing = nullptr;
	assert(query->resolve(input, &missing) == S_FALSE && !missing);
	assert(metadata->set_enabled(FALSE) == S_OK);
	A_CODE(answer) = 99;
	assert(query->lookup(input, &answer) == static_cast<HRESULT>(-1620) && !A_CODE(answer) && !A_VISITED(answer));
	assert(metadata->set_enabled(TRUE) == S_OK);
	Q_MIN(input) = -1;
	assert(query->lookup(input, &answer) == static_cast<HRESULT>(-1620) && !A_CODE(answer));
	Q_MIN(input) = 0;
	HANDLE thread = CreateThread(nullptr, 0, wrong_thread, query, 0, nullptr);
	assert(thread && WaitForSingleObject(thread, INFINITE) == WAIT_OBJECT_0);
	DWORD status = 99;
	assert(GetExitCodeThread(thread, &status) && status == 0);
	CloseHandle(thread);
	catalog16_release(root);
	unknown->Release();
	query->Release();
	assert(lens16_retired_count(1) == 0 && lens16_retired_count(2) == 0);
	metadata->Release();
	assert(lens16_retired_count(1) == 1 && lens16_retired_count(2) == 1 && lens16_retired_count(3) == 4 && lens16_retired_count(4) == 2);
	assert(held->get_code(&code) == S_OK && code == 31);
	held->Release();
	assert(lens16_retired_count(3) == 5);
	auto provider = new Provider();
	void *meta_raw = nullptr;
	assert(provider->QueryInterface(metadata_iid, &meta_raw) == S_OK);
	auto provider_meta = static_cast<MetadataOracle *>(meta_raw);
	void *identity = nullptr;
	assert(provider_meta->QueryInterface(IID_IUnknown, &identity) == S_OK && identity == static_cast<QueryOracle *>(provider));
	static_cast<IUnknown *>(identity)->Release();
	provider_meta->Release();
	assert(catalog16_import_provider(static_cast<QueryOracle *>(provider)) == 0 && provider->refs() == 1 && provider->calls() == 3 && entries_retired == 1);
	provider->Release();
	assert(providers_retired == 1);
	assert(HeapValidate(GetProcessHeap(), 0, nullptr));
	CoUninitialize();
	std::puts("PASS API B2 Windows independent C/COM records, two interfaces, nullable owners and provider imports");
	return 0;
}
