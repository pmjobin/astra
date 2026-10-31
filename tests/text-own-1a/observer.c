// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Private test observer for the actual compiled Astra factory/descriptor ABI.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <unistd.h>

extern void *__libc_calloc(size_t, size_t);
extern void __libc_free(void *);
static struct {
	void *pointer;
	size_t bytes;
	int live;
} allocations[256];
static struct {
	void *object, *payload;
	int32_t length;
	int dropped, payload_freed, freed;
} messages[128];
static int used, count, drops, object_frees, payload_frees, allocation_calls;
static const unsigned char *input;
static int32_t input_length;
static void require(int yes) {
	if (!yes) {
		_Exit(98);
	}
}

void *calloc(size_t n, size_t size) {
	allocation_calls++;
	const char *fail = getenv("UTF8_FAIL_ALLOC");
	if (fail && allocation_calls == atoi(fail)) {
		return NULL;
	}
	void *pointer = __libc_calloc(n, size);
	if (pointer) {
		require(used < 256 && (!size || n <= SIZE_MAX / size));
		allocations[used].pointer = pointer;
		allocations[used].bytes = n * size;
		allocations[used++].live = 1;
	}
	return pointer;
}
static size_t extent(void *pointer) {
	for (int i = used - 1; i >= 0; i--) {
		if (allocations[i].pointer == pointer && allocations[i].live) {
			return allocations[i].bytes;
		}
	}
	_Exit(98);
}
void utf8_observe_input(const unsigned char *bytes, int32_t length) {
	input = bytes;
	input_length = length;
}
void utf8_observe_owner(void *object) {
	// Native ordinary nonpolymorphic Class { counted-text {PTR,I32} }.
	struct descriptor {
		const unsigned char *data;
		int32_t length;
	};
	_Static_assert(sizeof(void *) == 8 && offsetof(struct descriptor, length) == 8 && sizeof(struct descriptor) == 16, "qualified GNU x86-64 descriptor");
	struct descriptor text;
	require(object != NULL && extent(object) == sizeof(text));
	memcpy(&text, object, sizeof(text));
	require(count < 128 && text.length == input_length && text.length >= 0);
	if (text.length) {
		require(text.data && text.data != input && extent((void *)text.data) == (size_t)text.length);
		require(memcmp(text.data, input, (size_t)text.length) == 0);
	} else {
		require(text.data == NULL);
	}
	for (int i = 0; i < count; i++) {
		if (!messages[i].freed) {
			require(messages[i].object != object);
			if (text.length && messages[i].length) {
				require(messages[i].payload != text.data);
			}
		}
	}
	messages[count].object = object;
	messages[count].payload = (void *)text.data;
	messages[count++].length = text.length;
}
void utf8_observe_drop(void *object) {
	for (int i = count - 1; i >= 0; i--) {
		if (messages[i].object == object && !messages[i].freed) {
			require(!messages[i].dropped && !messages[i].payload_freed);
			messages[i].dropped = 1;
			drops++;
			char event[64];
			int length = snprintf(event, sizeof(event), "owner-drop %d\n", i + 1);
			require(length > 0 && (size_t)length < sizeof(event));
			require(write(1, event, (size_t)length) == length);
			return;
		}
	}
}
void free(void *pointer) {
	if (!pointer) {
		return;
	}
	for (int i = count - 1; i >= 0; i--) {
		if (messages[i].freed) {
			continue;
		}
		if (messages[i].payload == pointer) {
			require(messages[i].dropped && !messages[i].payload_freed);
			messages[i].payload_freed = 1;
			payload_frees++;
			break;
		}
		if (messages[i].object == pointer) {
			require(messages[i].dropped && (!messages[i].length || messages[i].payload_freed));
			messages[i].freed = 1;
			object_frees++;
			break;
		}
	}
	for (int i = used - 1; i >= 0; i--) {
		if (allocations[i].pointer == pointer && allocations[i].live) {
			allocations[i].live = 0;
			break;
		}
	}
	__libc_free(pointer);
}
__attribute__((destructor)) static void finish(void) {
	for (int i = 0; i < used; i++) {
		require(!allocations[i].live);
	}
	require(drops == count && object_frees == count);
	printf("observer: owners=%d drops=%d objects=%d payloads=%d allocations=%d\n",
	       count, drops, object_frees, payload_frees, allocation_calls);
}
