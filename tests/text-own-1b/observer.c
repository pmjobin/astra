/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Test-only: reuse the unchanged real-allocation/Q19A payload observer. */
#include "../text-own-1a/observer.c"

struct byte_buffer {
	unsigned char *base;
	int32_t capacity;
};
struct byte_builder {
	struct byte_buffer backing;
	int32_t used;
};
_Static_assert(sizeof(struct byte_builder) == 24 && offsetof(struct byte_builder, used) == 16,
               "qualified native builder field layout");
static struct {
	struct byte_builder *object;
	void *last;
	int dropped;
} builders[16];
static struct frame {
	int kind, index, used, capacity, count;
	unsigned char *base, *input;
	unsigned char bytes[256], fragment[256];
} frames[32];
static unsigned char snapshots[128][256];
static int builder_count, builder_drops, growths, depth, saved_messages;

static int live(void *pointer) {
	if (!pointer) {
		return 0;
	}
	for (int i = used - 1; i >= 0; i--) {
		if (allocations[i].pointer == pointer) {
			return allocations[i].live;
		}
	}
	return 0;
}
static int builder_index(struct byte_builder *object) {
	for (int i = builder_count - 1; i >= 0; i--) {
		if (builders[i].object == object && !builders[i].dropped) {
			return i;
		}
	}
	_Exit(98);
}
static void stable_messages(void) {
	for (int i = 0; i < count; i++) {
		if (i >= saved_messages) {
			require(messages[i].length <= 256);
			if (messages[i].length) {
				memcpy(snapshots[i], messages[i].payload, (size_t)messages[i].length);
			}
			saved_messages++;
		}
		if (!messages[i].freed && messages[i].length) {
			require(live(messages[i].payload));
			require(memcmp(messages[i].payload, snapshots[i], (size_t)messages[i].length) == 0);
		}
	}
}
void builder_obs_init(struct byte_builder *object) {
	if (!builder_count) {
		require(setvbuf(stdout, NULL, _IONBF, 0) == 0);
	}
	require(builder_count < 16 && object && extent(object) == sizeof(*object));
	require(object->used == 0 && object->backing.capacity == 0 && !object->backing.base);
	builders[builder_count++].object = object;
	printf("builder-init %d\n", builder_count);
}
void builder_obs_begin(int kind, struct byte_builder *object, unsigned char *input_bytes, int32_t n) {
	require(depth < 32 && object->used >= 0 && object->used <= object->backing.capacity && object->used <= 256);
	stable_messages();
	int index = builder_index(object);
	require(!builders[index].dropped);
	struct frame *frame = &frames[depth++];
	frame->kind = kind;
	frame->index = index;
	frame->used = object->used;
	frame->capacity = object->backing.capacity;
	frame->base = object->backing.base;
	frame->count = n;
	frame->input = input_bytes;
	if (object->used) {
		memcpy(frame->bytes, object->backing.base, (size_t)object->used);
	}
	if (kind == 2) {
		require(n >= 0 && n <= 256);
		if (n) {
			memcpy(frame->fragment, input_bytes, (size_t)n);
		}
	}
}
void builder_obs_leave(int kind, struct byte_builder *object, int success) {
	require(depth > 0);
	struct frame *frame = &frames[--depth];
	require(frame->kind == kind && builders[frame->index].object == object);
	require(object->used >= 0 && object->used <= object->backing.capacity);
	if (object->backing.capacity) {
		require(extent(object->backing.base) == (size_t)object->backing.capacity);
	} else {
		require(!object->backing.base);
	}
	if (frame->used) {
		require(memcmp(frame->bytes, object->backing.base, (size_t)frame->used) == 0);
	}
	if (kind == 1) {
		require(object->used == frame->used);
		if (!success || frame->count <= frame->capacity) {
			require(object->backing.base == frame->base && object->backing.capacity == frame->capacity);
		} else {
			require(object->backing.capacity == frame->count && object->backing.base != frame->base && !live(frame->base));
			growths++;
			printf("builder-grow %d %d->%d used=%d\n", frame->index + 1, frame->capacity, object->backing.capacity, object->used);
		}
	} else if (kind == 2) {
		require(success && object->used == frame->used + frame->count);
		if (frame->count) {
			require(memcmp(object->backing.base + frame->used, frame->fragment, (size_t)frame->count) == 0);
			require(memcmp(frame->input, frame->fragment, (size_t)frame->count) == 0);
		}
	} else {
		require(kind == 3 && object->used == frame->used && object->backing.capacity == frame->capacity && object->backing.base == frame->base);
		printf("builder-snapshot %d %s used=%d\n", frame->index + 1, success ? "valid" : "invalid", object->used);
	}
	builders[frame->index].last = object->backing.base;
	stable_messages();
}
void builder_obs_message(void) {
	require(count > 0 && depth > 0 && frames[depth - 1].kind == 3);
	struct frame *frame = &frames[depth - 1];
	int i = count - 1;
	require(messages[i].length == frame->used);
	if (frame->used) {
		require(input != frame->base);
	}
	if (frame->used) {
		require(messages[i].payload != frame->base && memcmp(messages[i].payload, frame->bytes, (size_t)frame->used) == 0);
	}
	stable_messages();
	printf("builder-message %d bytes=%d\n", count, messages[i].length);
}
void builder_obs_drop(struct byte_builder *object) {
	stable_messages();
	int index = builder_index(object);
	require(!builders[index].dropped);
	builders[index].last = object->backing.base;
	builders[index].dropped = 1;
	builder_drops++;
	printf("builder-drop %d used=%d\n", index + 1, object->used);
}
__attribute__((destructor(101))) static void builder_finish(void) {
	require(depth == 0 && builder_count == builder_drops);
	for (int i = 0; i < builder_count; i++) {
		require(!live(builders[i].object) && !live(builders[i].last));
	}
	printf("builder-observer: builders=%d drops=%d growths=%d\n", builder_count, builder_drops, growths);
}
