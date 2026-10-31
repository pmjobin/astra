// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

struct property_resource {
	int32_t value;
};
int32_t property_event(int32_t stage, int32_t tag) {
	printf("%d:%d\n", stage, tag);
	return 0;
}
void *property_resource_make(int32_t value) {
	struct property_resource *resource = malloc(sizeof *resource);
	assert(resource != NULL);
	resource->value = value;
	property_event(1, value);
	return resource;
}
int32_t property_resource_value(void *pointer) {
	assert(pointer != NULL);
	return ((struct property_resource *)pointer)->value;
}
void property_resource_drop(void *pointer) {
	if (pointer != NULL) {
		struct property_resource *resource = pointer;
		property_event(2, resource->value);
		free(resource);
	}
}
