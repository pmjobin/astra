// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdio.h>

struct resource {
	int id;
	int live;
};
static struct resource resources[256];
static int live_count;

int life_record(int code, int value) {
	assert(putchar(code) != EOF);
	assert(fflush(stdout) == 0);
	return value;
}

void *life_create(int id) {
	assert(id > 0 && id < 256 && !resources[id].live);
	resources[id].id = id;
	resources[id].live = 1;
	live_count++;
	return &resources[id];
}

void life_destroy(void *value) {
	struct resource *resource = value;
	assert(resource && resource->live);
	resource->live = 0;
	live_count--;
	life_record(resource->id, 0);
}

int life_id(void *value) {
	struct resource *resource = value;
	assert(resource && resource->live);
	return resource->id;
}

int life_live(void) {
	return live_count;
}
