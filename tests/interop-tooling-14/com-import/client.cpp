// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "import14.hpp"
#include "allocation-oracle.hpp"
#include <cstdio>
#include <cstring>
extern "C" int32_t astra_import_exercise(void *);
extern "C" int32_t astra_import_early(void *);
extern "C" int32_t astra_import_status(void *);
static constexpr IID VALUE = {0x849ad154,0x8d1e,0x4c63,{0x9e,0xa2,0x14,0x32,0x9b,0x02,0x20,0x01}};
struct Value : IUnknown { virtual HRESULT STDMETHODCALLTYPE Get(LONG *) = 0; virtual HRESULT STDMETHODCALLTYPE Set(LONG) = 0; };
template<class T> static T load(HMODULE module, const char *name) {
	FARPROC address = GetProcAddress(module, name); T result = nullptr;
	static_assert(sizeof(result) == sizeof(address)); std::memcpy(&result, &address, sizeof(result)); return result;
}
#define CHECK(test) do { if (!(test)) { std::printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
struct Worker { iv14_handle *value; is14_handle *scale; IUnknown *unknown; };
static DWORD WINAPI wrong_thread(void *input) {
	auto context = static_cast<Worker *>(input);
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	int32_t value = 99, status = 99;
	CHECK(iv14_get(context->value, &value) == static_cast<int32_t>(RPC_E_WRONG_THREAD) && value == 0);
	CHECK(iv14_set(context->value, 88) == static_cast<int32_t>(RPC_E_WRONG_THREAD));
	CHECK(is14_scale(context->scale, 2, &value) == static_cast<int32_t>(RPC_E_WRONG_THREAD) && value == 0);
	CHECK(iv14_clone(context->value, &status) == nullptr && status == static_cast<int32_t>(RPC_E_WRONG_THREAD));
	CHECK(astra_import_exercise(context->unknown) == static_cast<int32_t>(RPC_E_WRONG_THREAD));
	CoUninitialize(); return 0;
}
int main(int argc, char **argv) {
	CHECK(argc == 2 && CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	HMODULE module = LoadLibraryA(argv[1]); CHECK(module);
	using Factory = HRESULT (*)(IUnknown **); using Stats = LONG (*)(LONG); using Mode = void (*)(LONG);
	auto create = load<Factory>(module, "producer_create");
	auto stats = load<Stats>(module, "producer_stats");
	auto mode = load<Mode>(module, "producer_mode");
	CHECK(create && stats && mode);
	IUnknown *unknown = nullptr; CHECK(create(&unknown) == S_OK && unknown && stats(2) == 1);
	CHECK(astra_import_exercise(nullptr) == static_cast<int32_t>(E_POINTER));
	CoUninitialize();
	CHECK(astra_import_exercise(unknown) == static_cast<int32_t>(CO_E_NOTINITIALIZED) && stats(2) == 1 && allocation_live == 0);
	CHECK(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	CHECK(astra_import_exercise(unknown) == 0 && stats(2) == 1 && allocation_live == 0);
	CHECK(astra_import_early(unknown) == 73 && stats(2) == 1 && allocation_live == 0);
	std::puts("PASS Astra COM import independent-producer two-IIDs data-vtables exact-QI-clone-move-early-cleanup");
	mode(1); // Failed QI with an acquired stray out must be balanced.
	CHECK(astra_import_status(unknown) == static_cast<int32_t>(E_NOINTERFACE) && stats(2) == 1 && allocation_live == 0);
	mode(2);
	CHECK(astra_import_status(unknown) == static_cast<int32_t>(E_UNEXPECTED) && stats(2) == 1 && allocation_live == 0);
	mode(3);
	CHECK(astra_import_status(unknown) == S_FALSE && stats(2) == 1 && allocation_live == 0);
	mode(0);
	allocation_fail_after = 1;
	CHECK(astra_import_status(unknown) == static_cast<int32_t>(E_OUTOFMEMORY) && stats(2) == 1 && allocation_live == 0);
	allocation_fail_after = 2;
	CHECK(astra_import_early(unknown) == static_cast<int32_t>(E_OUTOFMEMORY) && stats(2) == 1 && allocation_live == 0);
	int32_t status = 99, result = 99;
	iv14_handle *value = iv14_acquire(unknown, &status); CHECK(value && status == S_OK);
	is14_handle *scale = is14_acquire(unknown, &status); CHECK(scale && status == S_OK && stats(2) == 3);
	mode(4); CHECK(iv14_get(value, &result) == static_cast<int32_t>(E_FAIL) && result == 0);
	mode(5); CHECK(is14_scale(scale, 2, &result) == static_cast<int32_t>(E_FAIL) && result == 0);
	mode(0); CHECK(iv14_get(value, &result) == S_OK && result == 17);
	std::puts("PASS Astra COM import HRESULT-S_FALSE failed-QI-partial-out success-null-refusal allocation-and-clone-failure out-cleanup");
	Worker context{value, scale, unknown};
	HANDLE thread = CreateThread(nullptr, 0, wrong_thread, &context, 0, nullptr);
	CHECK(thread && WaitForSingleObject(thread, 10000) == WAIT_OBJECT_0);
	DWORD code = 99; CHECK(GetExitCodeThread(thread, &code) && code == 0 && CloseHandle(thread));
	CoUninitialize();
	CHECK(iv14_get(value, &result) == static_cast<int32_t>(CO_E_NOTINITIALIZED) && result == 0);
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	CHECK(iv14_get(value, &result) == static_cast<int32_t>(RPC_E_WRONG_THREAD) && result == 0);
	CoUninitialize(); CHECK(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	CHECK(iv14_get(value, &result) == S_OK && result == 17);
	iv14_release(value); is14_release(scale);
	CHECK(stats(2) == 1 && allocation_live == 0);
	std::puts("PASS Astra COM import actual-STA-MTA wrong-thread-data-clone-QI missing-and-changed-apartment refusal restored");
	for (unsigned i = 0; i < 128; ++i) {
		Value *reset = nullptr; CHECK(unknown->QueryInterface(VALUE, reinterpret_cast<void **>(&reset)) == S_OK && reset);
		CHECK(reset->Set(40) == S_OK && reset->Release() == 1);
		CHECK(astra_import_exercise(unknown) == 0 && stats(2) == 1 && allocation_live == 0);
	}
	CHECK(stats(0) == 1 && stats(1) == 0 && stats(7) == 0 && allocation_total > 390 && allocation_retired == allocation_total);
	CHECK(unknown->Release() == 0 && stats(1) == 1 && stats(2) == 0);
	CHECK(HeapValidate(GetProcessHeap(), 0, nullptr));
	CHECK(FreeLibrary(module)); CoUninitialize();
	std::puts("PASS Astra COM import 128-repeat exact-provider-destruction all-wrapper-allocations-retired DLL-unload");
	std::puts("ASTRA_COM_IMPORT_WINDOWS_NATIVE=PASS"); return 0;
}
