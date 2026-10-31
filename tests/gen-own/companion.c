// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdio.h>

struct resource {
	int id;
	int live;
};
static struct resource resources[256];

int life_record(int code, int value) {
	assert(putchar(code) != EOF);
	assert(fflush(stdout) == 0);
	return value;
}

void *life_create(int id) {
	assert(id > 0 && id < 256 && !resources[id].live);
	resources[id].id = id;
	resources[id].live = 1;
	return &resources[id];
}

void *own_token_create(int id) {
	return life_create(id);
}

int life_id(void *value) {
	struct resource *resource = value;
	assert(resource && resource->live && resource == &resources[resource->id]);
	return resource->id;
}

void life_destroy(void *value) {
	struct resource *resource = value;
	int id = life_id(value);
	resource->live = 0;
	life_record(id, 0);
}
