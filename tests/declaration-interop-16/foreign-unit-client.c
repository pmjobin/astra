// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
typedef struct Native Native;

typedef struct {
	int32_t domain, code;
} Error;

typedef struct {
	bool enabled;
	int32_t count;
	double weight;
} Sample;

typedef struct {
	double left, right;
} Pair;

_Static_assert(sizeof(Sample) == 16 && offsetof(Sample, count) == 4 && offsetof(Sample, weight) == 8, "independent mixed POD layout");
extern int32_t opaque16_create(int32_t, Native **, Error *);
extern int32_t opaque16_amend(Native *, Sample, Sample *, Error *);
extern int32_t opaque16_exchange(Native *, Pair, Pair *, Error *);
extern int32_t opaque16_visit(Native *, bool, bool (*)(void *, bool), void *, bool *, Error *);
extern int32_t opaque16_set_count(Native *, int32_t, Error *);
extern int32_t opaque16_checked(Native *, double, double *, Error *);
extern int32_t opaque16_snapshot(Native *, const uint8_t *, int32_t, uint8_t **, int32_t *, Error *);
extern int32_t opaque16_bytes_release(uint8_t **, int32_t *, Error *);
extern int32_t opaque16_destroy(Native **, Error *);
extern int32_t opaque16_consumer(void);
extern int32_t opaque16_facade_create(int32_t, Native **, Error *);
extern int32_t opaque16_facade_amend(Native *, Sample, int32_t, Sample *, Error *);
extern int32_t opaque16_facade_destroy(Native **, Error *);
static unsigned destroyed, callbacks, facades;

int32_t opaque16_retired(void) {
	++destroyed;
	return 0;
}

int32_t opaque16_facade_retired(void) {
	++facades;
	return 0;
}

static bool invert(void *data, bool input) {
	assert(data == &callbacks);
	++callbacks;
	return !input;
}

int main(void) {
	assert(opaque16_consumer() == 0 && destroyed == 2 && facades == 1);
	Native *root = NULL;
	Error error = {0, 0};
	assert(opaque16_create(7, &root, &error) == 0 && root);
	Sample input = {true, 4, 2.5}, result = {0};
	assert(opaque16_amend(root, input, &result, &error) == 0 && !result.enabled && result.count == 11 && result.weight == 3.75 && input.enabled);
	Pair pair = {1.25, 2.5}, out = {0};
	assert(opaque16_exchange(root, pair, &out, &error) == 0 && out.left == 9.5 && out.right == 1.25);
	bool choice = false;
	assert(opaque16_visit(root, false, invert, &callbacks, &choice, &error) == 0 && choice && callbacks == 1);
	const uint8_t bytes[] = {3, 0, 254};
	uint8_t *copy = NULL;
	int32_t length = 0;
	assert(opaque16_snapshot(root, bytes, 3, &copy, &length, &error) == 0 && copy && length == 3 && copy[0] == 4 && copy[1] == 1 && copy[2] == 255);
	assert(opaque16_bytes_release(&copy, &length, &error) == 0 && !copy && !length);
	double checked = 99;
	assert(opaque16_checked(root, -1, &checked, &error) == -1600 && checked == 0 && error.domain == 16 && error.code == -1600);
	assert(opaque16_checked(root, 2, &checked, &error) == 0 && checked == 10);
	assert(opaque16_set_count(root, 19, &error) == 0);
	assert(opaque16_amend(root, input, &result, &error) == 0 && result.count == 23);
	assert(opaque16_destroy(&root, &error) == 0 && !root && destroyed == 3);
	assert(opaque16_facade_create(13, &root, &error) == 0 && root);
	assert(opaque16_facade_amend(root, input, 5, &result, &error) == 0 && !result.enabled && result.count == 22 && result.weight == 3.75);
	assert(opaque16_facade_destroy(&root, &error) == 0 && !root && destroyed == 4 && facades == 2);
	puts("PASS opaque foreign native units preserve unique ownership, typed records and callbacks");
	return 0;
}
