/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* A real fd Resource admitted to the typed arena; no per-resource heap block. */
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

struct resource {
	int fd;
	int id;
	int live;
};
static struct resource resources[64];
static int active, opened, closed;

void *packet_open(int32_t id) {
	assert(id > 0 && id < 64 && !resources[id].live);
	int fd = open("/dev/null", O_RDWR | O_CLOEXEC);
	assert(fd >= 0);
	resources[id] = (struct resource){fd, id, 1};
	active++;
	opened++;
	return &resources[id];
}

void astra_packet_resource_close(void *pointer) {
	struct resource *resource = pointer;
	assert(resource >= resources && resource < resources + 64 && resource->live);
	assert(close(resource->fd) == 0);
	resource->live = 0;
	active--;
	closed++;
}

int32_t packet_live(void) {
	return active;
}

int32_t packet_audit(int32_t expected) {
	assert(active == expected && opened - closed == active);
	return 0;
}

int32_t packet_finish(int32_t expected_opened) {
	assert(!active && opened == expected_opened && closed == expected_opened);
	printf("packets:%d closed:%d\n", opened, closed);
	return 0;
}
