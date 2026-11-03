// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "sdk-oracle.hpp"

struct Worker {
	Value *value;
};

static DWORD WINAPI other_thread(void *input) {
	auto context = static_cast<Worker *>(input);
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	CHECK(context->value->AddRef() == 4);
	LONG out = 99;
	CHECK(context->value->Get(&out) == RPC_E_WRONG_THREAD && out == 0);
	CHECK(context->value->Set(22) == RPC_E_WRONG_THREAD);
	void *view = context->value;
	CHECK(context->value->QueryInterface(SCALE, &view) == RPC_E_WRONG_THREAD && !view);
	CHECK(context->value->Release() == 3);
	CoUninitialize();
	return 0;
}

int main(int argc, char **argv) {
	static_assert(sizeof(void *) == 8 && sizeof(LONG) == 4 && sizeof(GUID) == 16);
	CHECK(argc == 2);
	HMODULE module = LoadLibraryA(argv[1]);
	CHECK(module);
	using Factory = HRESULT (*)(int32_t, IUnknown **);
	using Stats = LONG (*)(LONG);
	auto create = load<Factory>(module, "a124_thermostat_com_create");
	auto stats = load<Stats>(module, "a124_stats");
	CHECK(create && stats);
	IUnknown *unknown = nullptr;
	CHECK(create(55, &unknown) == CO_E_NOTINITIALIZED && !unknown && stats(0) == 0);
	CHECK(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	CHECK(create(55, nullptr) == E_POINTER && stats(0) == 0);
	CHECK(create(55, &unknown) == S_OK && unknown && stats(0) == 1);
	Value *value = nullptr;
	Scaling *scale = nullptr;
	CHECK(unknown->QueryInterface(VALUE, reinterpret_cast<void **>(&value)) == S_OK);
	CHECK(unknown->QueryInterface(SCALE, reinterpret_cast<void **>(&scale)) == S_OK);
	CHECK(static_cast<void *>(value) != static_cast<void *>(scale));
	IUnknown *first = nullptr, *second = nullptr;
	CHECK(value->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&first)) == S_OK);
	CHECK(scale->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&second)) == S_OK);
	CHECK(first == unknown && second == unknown && first->Release() == 4 && second->Release() == 3);
	IID missing = VALUE;
	missing.Data1 ^= 0xffff;
	void *absent = value;
	CHECK(value->QueryInterface(missing, &absent) == E_NOINTERFACE && !absent);
	CHECK(value->QueryInterface(VALUE, nullptr) == E_POINTER);
	LONG out = 99;
	CHECK(value->Get(nullptr) == E_POINTER && value->Get(&out) == S_OK && out == 30);
	CHECK(value->Set(18) == S_OK && value->Get(&out) == S_OK && out == 18);
	CHECK(scale->Scale(2, &out) == S_OK && out == 36);
	CHECK(value->Set(99) == S_OK && value->Get(&out) == S_OK && out == 30);
	CHECK(value->Set(-2) == S_OK && value->Get(&out) == S_OK && out == 10);
	CHECK(value->Set(10) == S_OK && scale->Scale(0, &out) == S_FALSE && out == 0);
	CHECK(scale->Scale(-1, &out) == E_INVALIDARG && out == 0);
	Worker context{value};
	HANDLE thread = CreateThread(nullptr, 0, other_thread, &context, 0, nullptr);
	CHECK(thread && WaitForSingleObject(thread, 10000) == WAIT_OBJECT_0);
	DWORD code = 99;
	CHECK(GetExitCodeThread(thread, &code) && code == 0 && CloseHandle(thread));
	CoUninitialize();
	CHECK(value->Get(&out) == CO_E_NOTINITIALIZED && out == 0);
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	CHECK(value->Get(&out) == RPC_E_WRONG_THREAD && out == 0);
	CoUninitialize();
	CHECK(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	CHECK(value->Get(&out) == S_OK && out == 10);
	CHECK(unknown->Release() == 2 && value->Release() == 1 && stats(1) == 0);
	CHECK(scale->Scale(2, &out) == S_OK && out == 20 && scale->Release() == 0);
	CHECK(stats(0) == 1 && stats(1) == 1 && stats(2) == 0);
	CHECK(HeapValidate(GetProcessHeap(), 0, nullptr) && FreeLibrary(module));
	CoUninitialize();
	std::puts("PASS A124: thermostat clamping 3-adjustments two-IID canonical-IUnknown HRESULT out-errors STA-MTA wrong-thread restored exact-counts native-destroyed=1 DLL-unloaded");
	return 0;
}
