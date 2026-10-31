// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "sdk-oracle.hpp"
#include "allocation-oracle.hpp"
extern "C" int32_t a123_reconcile(void *);
static DWORD WINAPI other_thread(void *unknown) {
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(RPC_E_WRONG_THREAD));
	CoUninitialize();
	return 0;
}
int main(int argc, char **argv) {
	CHECK(argc == 2 && CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	HMODULE module = LoadLibraryA(argv[1]);
	CHECK(module);
	using Create = HRESULT (*)(IUnknown **);
	using Stats = LONG (*)(LONG);
	using Mode = void (*)(LONG);
	auto create = load<Create>(module, "producer_create");
	auto stats = load<Stats>(module, "producer_stats");
	auto mode = load<Mode>(module, "producer_mode");
	CHECK(create && stats && mode);
	IUnknown *unknown = nullptr;
	CHECK(create(&unknown) == S_OK && unknown);
	Value *reset = nullptr;
	CHECK(unknown->QueryInterface(VALUE, reinterpret_cast<void **>(&reset)) == S_OK);
	CHECK(stats(2) == 2);
	CHECK(a123_reconcile(nullptr) == static_cast<int32_t>(E_POINTER));
	for (unsigned repeat = 0; repeat < 32; ++repeat) {
		CHECK(reset->Set(40) == S_OK);
		CHECK(a123_reconcile(unknown) == 810765);
		LONG final = 99;
		CHECK(reset->Get(&final) == S_OK && final == 6);
		CHECK(stats(2) == 2 && allocation_live == 0);
	}
	mode(1);
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(E_NOINTERFACE) && stats(2) == 2);
	mode(2);
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(E_UNEXPECTED) && stats(2) == 2);
	mode(4);
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(E_FAIL) && stats(2) == 2);
	mode(5);
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(E_FAIL) && stats(2) == 2);
	mode(0);
	allocation_fail_after = 1;
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(E_OUTOFMEMORY) && stats(2) == 2);
	allocation_fail_after = 3;
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(E_OUTOFMEMORY) && stats(2) == 2);
	CHECK(allocation_live == 0);
	HANDLE thread = CreateThread(nullptr, 0, other_thread, unknown, 0, nullptr);
	CHECK(thread && WaitForSingleObject(thread, 10000) == WAIT_OBJECT_0);
	DWORD status = 99;
	CHECK(GetExitCodeThread(thread, &status) && status == 0 && CloseHandle(thread));
	CoUninitialize();
	CHECK(a123_reconcile(unknown) == static_cast<int32_t>(CO_E_NOTINITIALIZED));
	CHECK(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	CHECK(reset->Set(40) == S_OK && a123_reconcile(unknown) == 810765);
	CHECK(stats(0) == 1 && stats(1) == 0 && stats(2) == 2 && stats(7) == 0);
	CHECK(reset->Release() == 1);
	CHECK(unknown->Release() == 0 && stats(1) == 1 && stats(2) == 0);
	CHECK(allocation_live == 0 && allocation_total == allocation_retired);
	CHECK(HeapValidate(GetProcessHeap(), 0, nullptr) && FreeLibrary(module));
	CoUninitialize();
	std::puts("PASS A123: reconciliation checksum=810765 two-IID clone-move HRESULT-error OOM wrong-thread apartment restored provider-destroyed=1 wrappers-retired");
	return 0;
}
