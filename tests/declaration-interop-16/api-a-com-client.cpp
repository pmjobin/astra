/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
inline constexpr IID service_iid = {0xe576d00a, 0x1616, 0x4b93, {0x8c, 0x71, 0x69, 0x0d, 0xf1, 0xa0, 0x16, 0x16}};
#ifdef USE_SDK
#include "sdk.hpp"
#include "api-com-types.h"
#else
struct Statistics {
	double score;
	std::uint64_t revision, processed;
};
struct Oracle : IUnknown {
	virtual HRESULT STDMETHODCALLTYPE get_revision(LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE get_enabled(BOOL *) = 0;
	virtual HRESULT STDMETHODCALLTYPE set_enabled(BOOL) = 0;
	virtual HRESULT STDMETHODCALLTYPE get_weight(DOUBLE *) = 0;
	virtual HRESULT STDMETHODCALLTYPE process(const BYTE *, LONG, BYTE *, LONG, LONG *) = 0;
	virtual HRESULT STDMETHODCALLTYPE statistics(Statistics *) = 0;
	virtual HRESULT STDMETHODCALLTYPE snapshot(BYTE **, LONG *) = 0;
};
struct Native;
struct Configuration {
	std::int32_t mask;
	bool rotate;
	double weight;
};
struct Error {
	std::int32_t domain, code;
};
static_assert(sizeof(Configuration) == 16 && sizeof(Statistics) == 24, "independent Windows POD oracle");
extern "C" std::int32_t byte_service16_create(Configuration, Native **, Error *);
extern "C" std::uint32_t byte_service16_release(Native *);
extern "C" HRESULT byte_service16_as_com(Native *, IUnknown **);
#endif
extern "C" std::int32_t byte_service16_com_import(void *);
extern "C" std::uint32_t byte16_retired_count(std::int32_t);
static DWORD WINAPI wrong_thread(void *data) {
	auto view = static_cast<Oracle *>(data);
	LONG revision = 99;
	return view->get_revision(&revision) == RPC_E_WRONG_THREAD && revision == 0 ? 0 : 1;
}
int main() {
	assert(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
	Configuration configuration{85, true, 2.5};
	Native *root = nullptr;
	Error error{};
	assert(byte_service16_create(configuration, &root, &error) == 0 && root);
	IUnknown *unknown = nullptr;
	assert(byte_service16_as_com(root, &unknown) == S_OK && unknown);
	void *raw = nullptr;
	assert(unknown->QueryInterface(service_iid, &raw) == S_OK && raw);
	auto view = static_cast<Oracle *>(raw);
	raw = nullptr;
	assert(view->QueryInterface(IID_IUnknown, &raw) == S_OK && raw == unknown);
	static_cast<IUnknown *>(raw)->Release();
	LONG revision = 99;
	BOOL enabled = FALSE;
	DOUBLE weight = 0;
	assert(view->get_revision(&revision) == S_OK && revision == 0 && view->get_enabled(&enabled) == S_OK && enabled == TRUE && view->get_weight(&weight) == S_OK && weight == 2.5);
	BYTE input[] = {3, 0, 254}, output[] = {77, 77, 77, 77};
	LONG produced = -1;
	assert(view->process(input, 3, output, 4, &produced) == S_OK && produced == 3 && output[0] == 172 && output[1] == 170 && output[2] == 87 && output[3] == 77);
	Statistics statistics{};
	assert(view->statistics(&statistics) == S_OK && statistics.revision == 1 && statistics.processed == 3 && statistics.score == 1072.5);
	assert(byte_service16_com_import(view) == 0);
	assert(view->get_revision(&revision) == S_OK && revision == 2);
	assert(view->set_enabled(FALSE) == S_OK);
	output[0] = 77;
	assert(view->process(input, 3, output, 4, &produced) == static_cast<HRESULT>(-1610) && produced == 0 && output[0] == 77);
	assert(view->set_enabled(TRUE) == S_OK);
	assert(view->process(input, 3, output, 2, &produced) == static_cast<HRESULT>(-1610) && produced == 0 && output[0] == 77);
	assert(view->process(nullptr, 1, output, 4, &produced) == E_POINTER && produced == 0);
	HANDLE thread = CreateThread(nullptr, 0, wrong_thread, view, 0, nullptr);
	assert(thread && WaitForSingleObject(thread, INFINITE) == WAIT_OBJECT_0);
	DWORD code = 99;
	assert(GetExitCodeThread(thread, &code) && code == 0);
	CloseHandle(thread);
	BYTE *snapshot = nullptr;
	LONG length = 0;
	assert(view->snapshot(&snapshot, &length) == S_OK && snapshot && length == 3 && snapshot[0] == 172 && snapshot[1] == 170 && snapshot[2] == 87);
	byte_service16_release(root);
	unknown->Release();
	assert(byte16_retired_count(1) == 0 && byte16_retired_count(3) == 0);
	view->Release();
	assert(byte16_retired_count(1) == 1 && byte16_retired_count(3) == 1 && byte16_retired_count(4) == 1);
	assert(snapshot[0] == 172 && snapshot[1] == 170 && snapshot[2] == 87);
	CoTaskMemFree(snapshot);
	assert(HeapValidate(GetProcessHeap(), 0, nullptr));
	CoUninitialize();
	std::puts("PASS API A native Windows C/COM processing, imported calls, checked outputs and exact lifetimes");
	return 0;
}
