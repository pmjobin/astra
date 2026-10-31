// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include <stdint.h>

static int32_t state;

int32_t astra_test_add(int32_t a, int32_t b) {
	return a + b;
}

int32_t astra_test_identity(int32_t value) {
	return value;
}

void astra_test_reset(void) {
	state = 0;
}

int32_t astra_test_record(int32_t value) {
	// Tests use at most six bounded digits between resets; no signed overflow.
	state = state * 10 + value;
	return value;
}

int32_t astra_test_state(void) {
	return state;
}

// Export qualification uses separate test-only variants of this companion.
// Ordinary import tests therefore retain no unresolved export references.
#if ASTRA_TEST_CEXPORT == 1
extern int32_t astra_export_add(int32_t, int32_t);

int32_t c_call_astra_add(int32_t a, int32_t b) {
	return astra_export_add(a, b);
}
#elif ASTRA_TEST_CEXPORT == 2
extern void astra_export_record(int32_t);

void c_call_astra_record(int32_t value) {
	astra_export_record(value);
}
#elif ASTRA_TEST_CEXPORT == 3
extern int32_t astra_export_recurse(int32_t);

int32_t c_call_astra_recurse(int32_t value) {
	return astra_export_recurse(value);
}
#elif ASTRA_TEST_CEXPORT == 4
extern int32_t astra_export_roundtrip(void);
extern int32_t astra_export_order(void);

int32_t c_call_astra_order(void) {
	return astra_export_order();
}

int32_t c_call_astra_roundtrip(void) {
	astra_test_record(3);
	int32_t result = astra_export_roundtrip();
	astra_test_record(4);
	return result + 39;
}
#elif ASTRA_TEST_CEXPORT == 5
extern int32_t astra_export_shortcircuit(int32_t);

int32_t c_call_astra_shortcircuit(int32_t value) {
	return astra_export_shortcircuit(value);
}
#elif ASTRA_TEST_CEXPORT == 6
extern int32_t astra_export_wrap(int32_t);
extern int32_t astra_export_loop(int32_t);

int32_t c_call_astra_body(void) {
	// Only Astra performs wrapping arithmetic. C supplies exact bounded values.
	if (astra_export_wrap(1) != INT32_MIN || astra_export_wrap(2) != INT32_MIN + 1 || astra_export_wrap(-1) != INT32_MAX - 1) {
		return 1;
	}
	return astra_export_loop(10) == 18 ? 0 : 2;
}
#elif ASTRA_TEST_CEXPORT == 7
extern int32_t astra_export_trap(int32_t);

int32_t c_call_astra_trap(void) {
	return astra_export_trap(0);
}
#endif

/* OWN-1 qualification: bounded static foreign resources, never heap storage. */
#include <stdlib.h>

static struct {
	int32_t id;
	int32_t live;
	int32_t touches;
} resource_slots[8];
static int32_t resource_live;
static int32_t resource_creates;
static int32_t resource_destroys;
static int32_t resource_order;
static int32_t resource_effects;
static int32_t resource_errors;
static int32_t resource_forbidden;
static int32_t resource_touches;
static int32_t resource_nulls;

static void resource_append(int32_t *state, int32_t id) {
	if (id < 0 || id > 9 || *state > (INT32_MAX - id) / 10) {
		resource_errors++;
		return;
	}
	*state = *state * 10 + id;
}

void astra_test_resource_reset(void) {
	for (int i = 0; i < 8; i++) {
		resource_slots[i].id = 0;
		resource_slots[i].live = 0;
		resource_slots[i].touches = 0;
	}
	resource_live = 0;
	resource_creates = 0;
	resource_destroys = 0;
	resource_order = 0;
	resource_effects = 0;
	resource_errors = 0;
	resource_forbidden = 0;
	resource_touches = 0;
	resource_nulls = 0;
}

void *astra_test_resource_create(int32_t id) {
	resource_creates++;
	if (id == 0) {
		return NULL;
	}
	for (int i = 0; i < 8; i++) {
		if (!resource_slots[i].live) {
			resource_slots[i].id = id;
			resource_slots[i].live = 1;
			resource_live++;
			return &resource_slots[i];
		}
	}
	resource_errors++;
	return NULL;
}

void astra_test_resource_destroy(void *p) {
	/* A normal exit here exposes erroneous cleanup before an Astra trap. */
	if (resource_forbidden) {
		_Exit(91);
	}
	for (int i = 0; i < 8; i++) {
		if (p == &resource_slots[i] && resource_slots[i].live) {
			resource_slots[i].live = 0;
			resource_live--;
			resource_destroys++;
			resource_append(&resource_order, resource_slots[i].id);
			resource_append(&resource_effects, resource_slots[i].id);
			return;
		}
	}
	/* Includes null, unknown pointers, and double destruction. */
	resource_errors++;
}

int32_t astra_test_resource_live_count(void) {
	return resource_live;
}
int32_t astra_test_resource_create_count(void) {
	return resource_creates;
}
int32_t astra_test_resource_destroy_count(void) {
	return resource_destroys;
}
int32_t astra_test_resource_destroy_order(void) {
	return resource_order;
}
int32_t astra_test_resource_error_count(void) {
	return resource_errors;
}
int32_t astra_test_resource_effect_order(void) {
	return resource_effects;
}
void astra_test_resource_forbid_cleanup(void) {
	resource_forbidden = 1;
}
int32_t astra_test_resource_record_effect(int32_t id) {
	resource_append(&resource_effects, id);
	return id;
}

void *astra_test_resource_create_other(int32_t id) {
	return astra_test_resource_create(id);
}
/* RESOURCE-1: distinct imported symbols can share the same static pool. */
void *astra_test_resource_create_same(int32_t id) {
	return astra_test_resource_create(id);
}
void *astra_test_resource_create_a(int32_t id) {
	return astra_test_resource_create(id);
}
void *astra_test_resource_create_b(int32_t id) {
	return astra_test_resource_create(id);
}
void astra_test_resource_destroy_other(void *p) {
	resource_append(&resource_effects, 8);
	astra_test_resource_destroy(p);
}

/* OBORROW-1: direct synchronous pointer use, with no retained alias. */
static int resource_index(void *p) {
	if (p == NULL) {
		resource_nulls++;
		return -1;
	}
	for (int i = 0; i < 8; i++) {
		if (p == &resource_slots[i] && resource_slots[i].live) {
			return i;
		}
	}
	resource_errors++;
	return -1;
}

int32_t astra_test_resource_is_live(void *p) {
	return resource_index(p) >= 0;
}
int32_t astra_test_resource_id(void *p) {
	int i = resource_index(p);
	return i < 0 ? 0 : resource_slots[i].id;
}
int32_t astra_test_resource_touch(void *p) {
	int i = resource_index(p);
	if (i < 0) {
		return 0;
	}
	resource_slots[i].touches++;
	resource_touches++;
	resource_append(&resource_effects, 7);
	return resource_slots[i].id;
}
int32_t astra_test_resource_touch_count(void) {
	return resource_touches;
}
int32_t astra_test_resource_null_count(void) {
	return resource_nulls;
}
void *astra_test_resource_raw(void) {
	return astra_test_resource_create(4);
}
int32_t astra_test_resource_observe3(int32_t first, void *p, int32_t last) {
	if (first != 1 || last != 2 || resource_effects != 12 || resource_destroys != 0) {
		resource_errors++;
	}
	resource_append(&resource_effects, 3);
	return astra_test_resource_id(p);
}
void astra_test_resource_raw_destroy(void *p) {
	astra_test_resource_destroy(p);
}
int32_t astra_test_resource_inspect_extern(void *p) {
	return astra_test_resource_is_live(p);
}
