// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>

#ifndef OWN_MEMORY
extern void *__libc_calloc(size_t, size_t);
extern void __libc_free(void *);

static struct {
	void *pointer;
	int id, live;
} allocations[32];

#endif

static struct {
	void *pointer;
	int initialized, heap, drops, observed, frees;
} owners[128];

static int pointer_checks, owner_count, free_count;
#ifndef OWN_MEMORY
static int used;
#endif

static void prepare(void) {
	static int ready;
	if (!ready) {
		setvbuf(stdout, NULL, _IONBF, 0);
		ready = 1;
	}
}

static void require(int condition) {
	if (!condition) {
		_Exit(98);
	}
}

static void event(int code, int id) {
	prepare();
	printf("%c%d\n", code, id);
}

#ifndef OWN_MEMORY

void *calloc(size_t count, size_t size) {
	void *pointer = __libc_calloc(count, size);
	require(pointer != NULL && used < 32);
	allocations[used].pointer = pointer;
	allocations[used].live = 1;
	used++;
	prepare();
	puts("A");
	return pointer;
}

void free(void *pointer) {
	if (pointer == NULL) {
		return;
	}
	int found = -1;
	for (int i = 0; i < used; i++) {
		if (allocations[i].live && allocations[i].pointer == pointer) {
			found = i;
			break;
		}
	}
	require(found >= 0);
	int id = allocations[found].id;
	require(id > 0 && owners[id].initialized && owners[id].heap && owners[id].frees == 0 && owners[id].observed == owners[id].drops);
	owners[id].frees++;
	allocations[found].live = 0;
	free_count++;
	event('F', id);
	__libc_free(pointer);
}

#endif

int32_t own_init(int32_t id, int32_t heap, int32_t drops) {
	require(id > 0 && id < 128 && !owners[id].initialized && (heap == 0 || heap == 1) && drops >= 0);
	owners[id].initialized = 1;
	owners[id].heap = heap;
	owners[id].drops = drops;
	owner_count++;
	if (heap) {
#ifndef OWN_MEMORY
		int found = -1;
		for (int i = 0; i < used; i++) {
			if (allocations[i].live && allocations[i].id == 0) {
				require(found == -1);
				found = i;
			}
		}
		require(found >= 0);
		allocations[found].id = id;
		if (owners[id].pointer) {
			require(owners[id].pointer == allocations[found].pointer);
		}
		owners[id].pointer = allocations[found].pointer;
#endif
	}
	event('I', id);
	return id;
}

int32_t own_drop(int32_t code, int32_t id) {
	require(id > 0 && id < 128 && owners[id].initialized && !owners[id].frees);
	// Derived complete destruction includes its own event and then base deinit.
	if (code == 'd') {
		require(owners[id].drops == 2 && owners[id].observed == 0);
	}
	owners[id].observed++;
	require(owners[id].observed <= owners[id].drops);
	event(code, id);
	return id;
}

int32_t own_derived(int32_t id) {
	require(id > 0 && id < 128 && owners[id].initialized && owners[id].drops == 1 && owners[id].observed == 0);
	owners[id].drops = 2;
	return id;
}

int32_t own_mark(int32_t code, int32_t id) {
	require(id > 0 && id < 128 && owners[id].initialized && owners[id].observed == 0 && owners[id].frees == 0);
	event(code, id);
	return id;
}

// Test-only entry instrumentation checks actual pointers in an independent C client.
void own_pointer(void *pointer, int32_t id, int32_t heap, int32_t constructor) {
	require(pointer != NULL && id > 0 && id < 128 && (heap == 0 || heap == 1));
	if (constructor) {
		if (owners[id].pointer) {
			require(owners[id].pointer == pointer);
		}
		owners[id].pointer = pointer;
	} else {
		require(owners[id].initialized && owners[id].pointer == pointer && owners[id].heap == heap && owners[id].frees == 0 && owners[id].observed == 0);
	}
#ifndef OWN_MEMORY
	int matches = 0;
	for (int i = 0; i < used; i++) {
		if (allocations[i].live && allocations[i].pointer == pointer) {
			matches++;
		}
	}
	require(matches == heap);
#endif
	pointer_checks++;
}

void own_loan(void *pointer, int32_t id) {
	require(id > 0 && id < 128 && owners[id].initialized);
	own_pointer(pointer, id, owners[id].heap, 0);
}

int32_t own_finish(void) {
#ifndef OWN_MEMORY
	for (int i = 0; i < used; i++) {
		require(!allocations[i].live);
	}
#endif
	for (int id = 1; id < 128; id++) {
		if (owners[id].initialized) {
			require(owners[id].observed == owners[id].drops);
#ifndef OWN_MEMORY
			require(owners[id].frees == owners[id].heap);
#endif
		}
	}
	printf("Z%d:%d\n", owner_count, free_count);
	return 42;
}

#ifdef OWN_CLIENT
extern int32_t own_native_entry(void);

int main(void) {
	int result = own_native_entry();
	printf("P%d\n", pointer_checks);
	return result;
}

#endif
