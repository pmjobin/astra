// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "sdk-oracle.hpp"
struct CHandle;
struct CWeak;
using AsCom = HRESULT (*)(CHandle *, IUnknown **);
struct Worker {
	CHandle *root;
	AsCom adapt;
	Value *value;
};
static DWORD WINAPI other_thread(void *input) {
	auto context = static_cast<Worker *>(input);
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	IUnknown *out = context->value;
	CHECK(context->adapt(context->root, &out) == RPC_E_WRONG_THREAD && !out);
	CHECK(context->value->Set(1) == RPC_E_WRONG_THREAD);
	CoUninitialize();
	return 0;
}
int main(int argc, char **argv) {
	CHECK(argc == 2 && CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	HMODULE module = LoadLibraryA(argv[1]);
	CHECK(module);
	using Create = CHandle *(*)(int32_t);
	using Count = uint32_t (*)(CHandle *);
	using Get = int32_t (*)(CHandle *, int32_t *);
	using Set = int32_t (*)(CHandle *, int32_t);
	using Identity = void *(*)(CHandle *);
	using Weak = CWeak *(*)(CHandle *);
	using Upgrade = CHandle *(*)(CWeak *);
	using WeakRelease = void (*)(CWeak *);
	using Stats = LONG (*)(LONG);
#define LOAD(name, type) auto name = load<type>(module, "a125_budget_" #name); CHECK(name)
	LOAD(create, Create);
	LOAD(acquire, Count);
	LOAD(release, Count);
	LOAD(get, Get);
	LOAD(set, Set);
	LOAD(root_identity, Identity);
	LOAD(weak, Weak);
	LOAD(weak_upgrade, Upgrade);
	LOAD(weak_release, WeakRelease);
	LOAD(as_com, AsCom);
#undef LOAD
	auto stats = load<Stats>(module, "a125_stats");
	CHECK(stats);
	CHandle *root = create(60);
	CHECK(root && stats(0) == 1 && stats(1) == 0);
	void *native = root_identity(root);
	CHECK(native && native != root);
	CWeak *observer = weak(root);
	CHECK(observer);
	IUnknown *unknown = nullptr;
	CHECK(as_com(root, &unknown) == S_OK && unknown);
	CHECK(static_cast<void *>(unknown) != root && static_cast<void *>(unknown) != native);
	Value *value = nullptr;
	Scaling *scale = nullptr;
	CHECK(unknown->QueryInterface(VALUE, reinterpret_cast<void **>(&value)) == S_OK);
	CHECK(unknown->QueryInterface(SCALE, reinterpret_cast<void **>(&scale)) == S_OK);
	IUnknown *canonical = nullptr;
	CHECK(scale->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&canonical)) == S_OK && canonical == unknown);
	CHECK(canonical->Release() == 4 && acquire(root) == 5 && release(root) == 4);
	IUnknown *same = nullptr;
	CHECK(as_com(root, &same) == S_OK && same == unknown && same->Release() == 4);
	int32_t out = 99;
	LONG com_out = 99;
	CHECK(set(root, 10) == S_OK && value->Get(&com_out) == S_OK && com_out == 50);
	CHECK(value->Set(15) == S_OK && get(root, &out) == S_OK && out == 35);
	CHECK(value->Set(100) == S_OK && set(root, -1) == S_OK && get(root, &out) == S_OK && out == 35);
	CHECK(scale->Scale(2, &com_out) == S_OK && com_out == 70);
	Worker context{root, as_com, value};
	HANDLE thread = CreateThread(nullptr, 0, other_thread, &context, 0, nullptr);
	CHECK(thread && WaitForSingleObject(thread, 10000) == WAIT_OBJECT_0);
	DWORD code = 99;
	CHECK(GetExitCodeThread(thread, &code) && code == 0 && CloseHandle(thread));
	CHECK(set(root, 35) == S_OK && value->Get(&com_out) == S_OK && com_out == 0);
	CHECK(get(root, nullptr) == E_POINTER && value->Get(nullptr) == E_POINTER);
	CHECK(release(root) == 3 && stats(1) == 0);
	CHandle *upgraded = weak_upgrade(observer);
	CHECK(upgraded == root && root_identity(upgraded) == native);
	CHECK(release(upgraded) == 3 && unknown->Release() == 2 && value->Release() == 1 && stats(1) == 0);
	CHECK(scale->Scale(0, &com_out) == S_FALSE && com_out == 0 && scale->Release() == 0);
	CHECK(stats(0) == 1 && stats(1) == 1 && stats(2) == 0 && weak_upgrade(observer) == nullptr);
	weak_release(observer);
	CHECK(HeapValidate(GetProcessHeap(), 0, nullptr) && FreeLibrary(module));
	CoUninitialize();
	std::puts("PASS A125: lease-budget C-COM shared-expenses separate-views stable-identity QI-counts weak-retains expiry wrong-thread native-destroyed=1 DLL-unloaded");
	return 0;
}
