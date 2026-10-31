// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "interfaces.hpp"
#include <cstdio>

#define CHECK(test) do { if (!(test)) { std::printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
static DWORD WINAPI wrong_thread(void *argument) {
	HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
	if (FAILED(init)) return 1;
	LONG out = -1;
	HRESULT status = static_cast<Value14 *>(argument)->Get(&out);
	CoUninitialize();
	return status == RPC_E_WRONG_THREAD && out == 0 ? 0 : 2;
}
int main(int argc, char **argv) {
	CHECK(argc == 2);
	HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	CHECK(SUCCEEDED(init));
	HMODULE module = LoadLibraryA(argv[1]);
	CHECK(module != nullptr);
	using Factory = HRESULT (*)(IUnknown **);
	using Destroyed = LONG (*)();
	auto create = reinterpret_cast<Factory>(GetProcAddress(module, "probe_create"));
	auto destroyed = reinterpret_cast<Destroyed>(GetProcAddress(module, "probe_destroyed"));
	CHECK(create && destroyed && destroyed() == 0);
	IUnknown *root = nullptr;
	CHECK(create(&root) == S_OK && root);
	Value14 *value = nullptr;
	Scale14 *scale = nullptr;
	CHECK(root->QueryInterface(IID_Value14, reinterpret_cast<void **>(&value)) == S_OK && value);
	CHECK(root->QueryInterface(IID_Scale14, reinterpret_cast<void **>(&scale)) == S_OK && scale);
	CHECK(static_cast<void *>(value) != static_cast<void *>(scale));
	IUnknown *first = nullptr, *second = nullptr;
	CHECK(value->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&first)) == S_OK);
	CHECK(scale->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&second)) == S_OK);
	CHECK(first == root && second == root);
	std::puts("PASS canonical-IUnknown two-IIDs distinct-interface-views QI-retains");
	IID absent = IID_Value14;
	absent.Data1 ^= 0xffff;
	void *missing = value;
	CHECK(root->QueryInterface(absent, &missing) == E_NOINTERFACE && missing == nullptr);
	LONG result = -1;
	CHECK(value->Get(nullptr) == E_POINTER);
	CHECK(value->Get(&result) == S_OK && result == 40);
	CHECK(value->Set(41) == S_OK);
	CHECK(scale->Scale(2, &result) == S_OK && result == 82);
	CHECK(scale->Scale(0, &result) == S_FALSE && result == 0);
	CHECK(scale->Scale(-1, &result) == E_INVALIDARG && result == 0);
	std::puts("PASS HRESULT-S_OK-S_FALSE-failure null-and-out-cleanup exact-data");
	HANDLE worker = CreateThread(nullptr, 0, wrong_thread, value, 0, nullptr);
	CHECK(worker != nullptr && WaitForSingleObject(worker, 10000) == WAIT_OBJECT_0);
	DWORD code = 99;
	CHECK(GetExitCodeThread(worker, &code) && code == 0);
	CHECK(CloseHandle(worker));
	std::puts("PASS real-STA-and-MTA initialization wrong-thread-refusal borrowed-worker-joined");
	CHECK(first->Release() == 4);
	CHECK(second->Release() == 3);
	CHECK(value->Release() == 2);
	CHECK(scale->Release() == 1);
	CHECK(destroyed() == 0);
	CHECK(root->Release() == 0);
	CHECK(destroyed() == 1);
	std::puts("PASS AddRef-Release counts exactly-one-provider-destruction");
	CHECK(FreeLibrary(module));
	CoUninitialize();
	std::puts("HOST_COM_AVAILABLE=YES; compiler-COM-import-export=NOT_TESTED");
	return 0;
}
