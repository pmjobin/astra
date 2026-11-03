/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Resource {
	int value;
} Resource;

static Resource *live[2];
static unsigned opened, closed, observations;

Resource *open_resource(int value) {
	assert(opened < 2);
	Resource *resource = malloc(sizeof(*resource));
	assert(resource != NULL);
	resource->value = value;
	live[opened++] = resource;
	return resource;
}

int read_resource(Resource *resource) {
	assert(resource == live[0] && closed == 0);
	return resource->value;
}

void close_resource(Resource *resource) {
	assert(closed < opened && resource == live[closed]);
	live[closed++] = NULL;
	free(resource);
}

void resource_observed(int stage, int value) {
	assert(value == 42 && stage == (int)++observations);
	if (stage == 3) {
		assert(opened == 2 && closed == 2);
	}
}

__attribute__((destructor)) static void verify(void) {
	assert(opened == 2 && closed == 2 && observations == 3);
	puts("REAL generated Resource capture: repeated wait reads exact live owner; success and submitted cancellation each clean once");
}
