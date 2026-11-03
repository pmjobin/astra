/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
static int family, mode, count, phases, active;
static int events[4];

int context_ctor_begin(int selected_family, int selected_mode) {
	assert(!active && selected_family >= 0 && selected_family <= 2);
	family = selected_family;
	mode = selected_mode;
	count = 0;
	active = 1;
	return 0;
}

int context_ctor_event(int value) {
	assert(active && count < 4);
	events[count++] = value;
	return 0;
}

int context_ctor_end(void) {
	assert(active);
	active = 0;
	++phases;
	if (family == 0) {
		assert(count == 3);
		if (mode == 0) {
			assert(events[0] == 100 && events[1] == 2 && events[2] == 1);
		} else if (mode == 1) {
			assert(events[0] == 2 && events[1] == 1 && events[2] == 200);
		} else {
			assert(events[0] == 1 && events[1] == 2 && events[2] == 200);
		}
	} else if (family == 1) {
		if (mode == 0) {
			assert(count == 3 && events[0] == 101 && events[1] == 4 && events[2] == 3);
		} else if (mode == 1) {
			assert(count == 1 && events[0] == 200);
		} else if (mode == 2) {
			assert(count == 2 && events[0] == 3 && events[1] == 200);
		} else {
			assert(count == 3 && events[0] == 4 && events[1] == 3 && events[2] == 200);
		}
	} else {
		assert(count == 3 && events[0] == 102 && events[1] == 200 && events[2] == 102);
	}
	return 0;
}

int context_ctor_finish(void) {
	assert(!active && phases == 12);
	puts("context constructors: twelve success/failure paths, exact input and initialized-prefix retirement");
	return 0;
}
