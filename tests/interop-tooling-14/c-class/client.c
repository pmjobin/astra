// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define ASTRA_FOREIGN14_INTERNAL
#include "counter.h"
#include <stdio.h>
#include <stdint.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif

extern int32_t counter14_native_only(void);
static int constructed;
static int destroyed;
static int disposed;
static int bad;
static int worker_status;
static int personality;

#define CHECK(condition) do { if (!(condition)) { printf("FAIL line=%d: %s\n", __LINE__, #condition); return 1; } } while (0)

int32_t counter14_created(int32_t value) {
	if (value != 40 && value != 9) { ++bad; }
	++constructed;
	return 0;
}
int32_t counter14_destroyed(int32_t value) {
	if (value != 17 && value != 9) { ++bad; }
	++destroyed;
	return 0;
}
static void dispose_personality(void *context) {
	if (context != &personality || destroyed != 1) { ++bad; }
	++disposed;
}
static int worker_check(counter14_handle *handle) {
	int32_t value = 99;
	CHECK(counter14_acquire(handle) == 2);
	CHECK((uint32_t)counter14_get(handle, &value) == UINT32_C(0x8001010e) && value == 0);
	CHECK((uint32_t)counter14_set(handle, 88) == UINT32_C(0x8001010e));
	CHECK((uint32_t)astra_foreign14_counter14_check_thread(handle) == UINT32_C(0x8001010e));
	CHECK(counter14_release(handle) == 1);
	return 0;
}
#ifdef _WIN32
static DWORD WINAPI worker(void *context) { worker_status = worker_check(context); return 0; }
#else
static void *worker(void *context) { worker_status = worker_check(context); return NULL; }
#endif

int main(void) {
	CHECK(counter14_acquire(NULL) == 0 && counter14_release(NULL) == 0);
	CHECK(counter14_weak(NULL) == NULL && counter14_weak_clone(NULL) == NULL && counter14_weak_upgrade(NULL) == NULL);
	counter14_weak_release(NULL);
	int32_t value = 99;
	CHECK((uint32_t)counter14_get(NULL, &value) == UINT32_C(0x80004003) && value == 0);
	CHECK((uint32_t)counter14_set(NULL, 1) == UINT32_C(0x80004003));
	counter14_handle *root = counter14_create(40);
	CHECK(root != NULL && constructed == 1 && destroyed == 0);
	void *identity = counter14_root_identity(root);
	CHECK(identity != NULL && identity != root);
	CHECK(counter14_get(root, &value) == 0 && value == 40);
	CHECK((uint32_t)counter14_get(root, NULL) == UINT32_C(0x80004003));
	CHECK(counter14_set(root, 17) == 0 && counter14_get(root, &value) == 0 && value == 17);
#ifdef _WIN32
	HANDLE thread = CreateThread(NULL, 0, worker, root, 0, NULL);
	CHECK(thread != NULL && WaitForSingleObject(thread, INFINITE) == WAIT_OBJECT_0);
	CHECK(CloseHandle(thread));
#else
	pthread_t thread;
	CHECK(pthread_create(&thread, NULL, worker, root) == 0);
	CHECK(pthread_join(thread, NULL) == 0);
#endif
	CHECK(worker_status == 0 && counter14_get(root, &value) == 0 && value == 17);
	CHECK(astra_foreign14_counter14_personality(root) == NULL);
	CHECK(astra_foreign14_counter14_attach(root, &personality, dispose_personality) == 0);
	CHECK(astra_foreign14_counter14_personality(root) == &personality);
	CHECK((uint32_t)astra_foreign14_counter14_attach(root, &personality, dispose_personality) == UINT32_C(0x8000ffff));
	counter14_weak_handle *weak = counter14_weak(root);
	CHECK(weak != NULL);
	counter14_weak_handle *other_weak = counter14_weak_clone(weak);
	CHECK(other_weak != NULL && other_weak != weak);
	CHECK(counter14_acquire(root) == 2);
	counter14_handle *upgraded = counter14_weak_upgrade(weak);
	CHECK(upgraded == root && counter14_root_identity(upgraded) == identity);
	CHECK(counter14_release(upgraded) == 2 && counter14_release(root) == 1);
	CHECK(destroyed == 0 && disposed == 0);
	CHECK(counter14_release(root) == 0);
	CHECK(destroyed == 1 && disposed == 1 && bad == 0);
	CHECK(counter14_weak_upgrade(weak) == NULL && counter14_weak_upgrade(other_weak) == NULL);
	counter14_weak_release(weak);
	CHECK(destroyed == 1 && disposed == 1);
	counter14_weak_release(other_weak);
	CHECK(counter14_native_only() == 0 && constructed == 2 && destroyed == 2 && disposed == 1 && bad == 0);
	puts("PASS opaque C Class: separate identity, native counts, exact teardown, weak expiry, thread refusal and native-only root");
	return 0;
}
