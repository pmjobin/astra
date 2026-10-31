// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Independent oracle: deliberately does not include compiler-generated headers.
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <stdint.h>
#include <cstdio>
#include <cstring>

static constexpr IID VALUE = {0x849ad154,0x8d1e,0x4c63,{0x9e,0xa2,0x14,0x32,0x9b,0x02,0x20,0x01}};
static constexpr IID SCALE = {0x849ad154,0x8d1e,0x4c63,{0x9e,0xa2,0x14,0x32,0x9b,0x02,0x20,0x02}};
struct Value : IUnknown { virtual HRESULT STDMETHODCALLTYPE Get(LONG *) = 0; virtual HRESULT STDMETHODCALLTYPE Set(LONG) = 0; };
struct Scaling : IUnknown { virtual HRESULT STDMETHODCALLTYPE Scale(LONG, LONG *) = 0; };
struct CHandle;
struct CWeak;
using AsCom = HRESULT (*)(CHandle *, IUnknown **);
struct Worker { Value *value; CHandle *root; AsCom as_com; };
template<class T> static T load(HMODULE module, const char *name) {
	FARPROC address = GetProcAddress(module, name);
	T result = nullptr;
	static_assert(sizeof(result) == sizeof(address));
	std::memcpy(&result, &address, sizeof(result));
	return result;
}
#define CHECK(test) do { if (!(test)) { std::printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
static DWORD WINAPI wrong_thread(void *argument) {
	auto context = static_cast<Worker *>(argument);
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	LONG out = -1;
	CHECK(context->value->AddRef() == 7);
	CHECK(context->value->Get(&out) == RPC_E_WRONG_THREAD && out == 0);
	CHECK(context->value->Set(88) == RPC_E_WRONG_THREAD);
	void *result = context->value;
	CHECK(context->value->QueryInterface(VALUE, &result) == RPC_E_WRONG_THREAD && !result);
	IUnknown *other = context->value;
	CHECK(context->as_com(context->root, &other) == RPC_E_WRONG_THREAD && !other);
	CHECK(context->value->Release() == 6);
	CoUninitialize();
	return 0;
}
int main(int argc, char **argv) {
	static_assert(sizeof(void *) == 8 && sizeof(LONG) == 4 && sizeof(GUID) == 16);
	CHECK(argc == 2);
	HMODULE module = LoadLibraryA(argv[1]);
	CHECK(module);
#define LOAD(name, type) auto name = load<type>(module, "com14_" #name); CHECK(name)
	using Create = CHandle *(*)(int32_t);
	using Count = uint32_t (*)(CHandle *);
	using Get = int32_t (*)(CHandle *, int32_t *);
	using Set = int32_t (*)(CHandle *, int32_t);
	using Identity = void *(*)(CHandle *);
	using Weak = CWeak *(*)(CHandle *);
	using Upgrade = CHandle *(*)(CWeak *);
	using WeakRelease = void (*)(CWeak *);
	using Factory = HRESULT (*)(int32_t, IUnknown **);
	using Stats = LONG (*)(LONG);
	using Native = int32_t (*)();
	using Fail = void (*)(uint32_t);
	LOAD(create, Create); LOAD(acquire, Count); LOAD(release, Count);
	LOAD(get, Get); LOAD(set, Set); LOAD(root_identity, Identity);
	LOAD(weak, Weak); LOAD(weak_upgrade, Upgrade); LOAD(weak_release, WeakRelease);
	LOAD(as_com, AsCom); LOAD(com_create, Factory); LOAD(stats, Stats); LOAD(native_only, Native);
	LOAD(fail_after, Fail);
	CHECK(stats(0) == 0 && stats(1) == 0 && stats(2) == 0);
	IUnknown *unknown = reinterpret_cast<IUnknown *>(uintptr_t(1));
	CHECK(com_create(40, &unknown) == CO_E_NOTINITIALIZED && !unknown && stats(0) == 0);
	CHECK(com_create(40, nullptr) == E_POINTER);
	CHECK(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	CHandle *root = create(40);
	CHECK(root && stats(0) == 1 && stats(1) == 0);
	void *native = root_identity(root);
	CHECK(native && native != root);
	CHECK(as_com(nullptr, &unknown) == E_POINTER && !unknown);
	CHECK(as_com(root, &unknown) == S_OK && unknown);
	CHECK(static_cast<void *>(unknown) != root && static_cast<void *>(unknown) != native);
	Value *value = nullptr;
	Scaling *scale = nullptr;
	CHECK(unknown->QueryInterface(VALUE, reinterpret_cast<void **>(&value)) == S_OK && value);
	CHECK(unknown->QueryInterface(SCALE, reinterpret_cast<void **>(&scale)) == S_OK && scale);
	CHECK(static_cast<void *>(value) != static_cast<void *>(scale));
	IUnknown *first = nullptr, *second = nullptr;
	CHECK(value->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&first)) == S_OK);
	CHECK(scale->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&second)) == S_OK);
	CHECK(first == unknown && second == unknown);
	IID missing = VALUE; missing.Data1 ^= 0xffff;
	void *absent = value;
	CHECK(value->QueryInterface(missing, &absent) == E_NOINTERFACE && !absent);
	CHECK(value->QueryInterface(VALUE, nullptr) == E_POINTER);
	std::puts("PASS Astra COM two-IIDs canonical-IUnknown distinct-C-COM-native identities QI-acquires");
	LONG result = -1;
	int32_t c_value = -1;
	CHECK(value->Get(nullptr) == E_POINTER && scale->Scale(2, nullptr) == E_POINTER);
	CHECK(value->Get(&result) == S_OK && result == 40);
	CHECK(set(root, 17) == S_OK && value->Get(&result) == S_OK && result == 17);
	CHECK(value->Set(17) == S_OK && get(root, &c_value) == S_OK && c_value == 17);
	CHECK(scale->Scale(2, &result) == S_OK && result == 34);
	CHECK(scale->Scale(0, &result) == S_FALSE && result == 0);
	CHECK(scale->Scale(-1, &result) == E_INVALIDARG && result == 0);
	std::puts("PASS Astra COM HRESULT-S_OK-S_FALSE-failure out-cleanup shared-native-data");
	Worker context{value, root, as_com};
	HANDLE thread = CreateThread(nullptr, 0, wrong_thread, &context, 0, nullptr);
	CHECK(thread && WaitForSingleObject(thread, 10000) == WAIT_OBJECT_0);
	DWORD code = 99;
	CHECK(GetExitCodeThread(thread, &code) && code == 0 && CloseHandle(thread));
	CHECK(value->Get(&result) == S_OK && result == 17);
	CoUninitialize();
	CHECK(value->Get(&result) == CO_E_NOTINITIALIZED && result == 0);
	CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK);
	CHECK(value->Get(&result) == RPC_E_WRONG_THREAD && result == 0);
	CoUninitialize();
	CHECK(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED) == S_OK);
	CHECK(value->Get(&result) == S_OK && result == 17);
	std::puts("PASS Astra COM actual-STA-MTA wrong-thread-QI-data-adaptation missing-and-changed-apartment refusal restored");
	CWeak *weak_owner = weak(root);
	CHECK(weak_owner);
	CHandle *upgraded = weak_upgrade(weak_owner);
	CHECK(upgraded == root && root_identity(upgraded) == native && release(upgraded) == 6);
	CHECK(first->Release() == 5 && second->Release() == 4 && value->Release() == 3 && scale->Release() == 2);
	CHECK(unknown->Release() == 1 && stats(1) == 0);
	IUnknown *again = nullptr;
	CHECK(as_com(root, &again) == S_OK && again == unknown);
	CHECK(release(root) == 1 && stats(1) == 0);
	CHECK(again->Release() == 0 && stats(1) == 1);
	CHECK(!weak_upgrade(weak_owner));
	weak_release(weak_owner);
	CHECK(com_create(9, &unknown) == S_OK && unknown);
	CHECK(unknown->Release() == 0 && stats(0) == 2 && stats(1) == 2);
	CHECK(native_only() == 0 && stats(0) == 3 && stats(1) == 3);
	for (unsigned i = 0; i < 128; ++i) {
		CHECK(com_create(40, &unknown) == S_OK && unknown && unknown->Release() == 0);
	}
	CHECK(stats(0) == 131 && stats(1) == 131 && stats(2) == 0 && stats(3) == 0 && stats(4) == stats(5));
	fail_after(1);
	unknown = reinterpret_cast<IUnknown *>(uintptr_t(1));
	CHECK(com_create(40, &unknown) == E_OUTOFMEMORY && !unknown);
	CHECK(stats(0) == 132 && stats(1) == 132 && stats(3) == 0);
	root = create(40); CHECK(root && stats(0) == 133 && stats(1) == 132);
	fail_after(1);
	unknown = reinterpret_cast<IUnknown *>(uintptr_t(1));
	CHECK(as_com(root, &unknown) == E_OUTOFMEMORY && !unknown);
	CHECK(acquire(root) == 2 && release(root) == 1 && get(root, &c_value) == S_OK && c_value == 40);
	CHECK(as_com(root, &unknown) == S_OK && unknown && release(root) == 1 && unknown->Release() == 0);
	CHECK(stats(0) == 133 && stats(1) == 133 && stats(2) == 0 && stats(3) == 0 && stats(4) == 131 && stats(5) == 131);
	std::puts("PASS Astra COM export factory-cache-OOM null-out exact-partial-cleanup restored-adaptation all-wrapper-allocations-retired");
	std::puts("PASS Astra COM exact-native-counts cached-view native-move-clone-weak-expiry 133-payload-destructions");
	CoUninitialize();
	CHECK(FreeLibrary(module));
	std::puts("ASTRA_COM_EXPORT_WINDOWS_NATIVE=PASS; imported-COM=NOT_TESTED");
	return 0;
}
