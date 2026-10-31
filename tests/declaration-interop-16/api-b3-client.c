/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#ifndef PROVIDER_SCORE
#define PROVIDER_SCORE 3.75
#endif
#ifdef USE_SDK
#include "native.h"
#include "api-types.h"
#else
typedef struct Directory Directory;
typedef struct Row Row;
typedef struct {
	float boost;
	double ceiling;
	int64_t minimum;
	uint64_t cap;
	uint32_t mask;
	bool lowest;
} Probe;
typedef struct {
	float score;
	int64_t code;
	uint32_t matches;
	bool found;
	uint64_t visited;
} Selection;
typedef struct {
	int32_t domain, code;
} Error;
_Static_assert(sizeof(Probe) == 40 && offsetof(Probe, lowest) == 36 && offsetof(Probe, cap) == 24 && sizeof(Selection) == 32 && offsetof(Selection, found) == 20 && offsetof(Selection, visited) == 24, "independent query/answer POD layout");
extern int32_t orbit16_create(Directory **, Error *);
extern int32_t orbit16_scan(Directory *, Probe, Selection *, Error *);
extern int32_t orbit16_entry_for(Directory *, Probe, Row **, Error *);
extern int32_t orbit16_population(Directory *, uint32_t, uint64_t *, Error *);
extern int32_t orbit16_order(Directory *, Row *, Row *, int32_t *, Error *);
extern int32_t orbit16_get_requests(Directory *, int32_t *, Error *);
extern int32_t orbit16_set_enabled(Directory *, bool, Error *);
extern int32_t orbit16_set_bias(Directory *, double, Error *);
extern int32_t orbit16_get_last(Directory *, Row **, Error *);
extern int32_t orbit16_get_description(Directory *, char **, int32_t *, Error *);
extern int32_t orbit16_text_release(char **, int32_t *, Error *);
extern uint32_t orbit16_release(Directory *);
extern int32_t orbit_row16_get_code(Row *, int64_t *, Error *);
extern int32_t orbit_row16_get_score(Row *, double *, Error *);
extern uint32_t orbit_row16_release(Row *);
#define Q_BOOST(value) ((value).boost)
#define Q_CAP(value) ((value).cap)
#define A_VISITED(value) ((value).visited)
#define Q_MIN(value) ((value).minimum)
#define Q_CEILING(value) ((value).ceiling)
#define Q_MASK(value) ((value).mask)
#define Q_LOWEST(value) ((value).lowest)
#define A_CODE(value) ((value).code)
#define A_SCORE(value) ((value).score)
#define A_MATCHES(value) ((value).matches)
#define A_FOUND(value) ((value).found)
#endif
extern uint32_t orbit16_retired_count(int32_t);
static void requests(Directory *root, int expected) {
	int32_t actual = -1;
	Error error = {0};
	assert(orbit16_get_requests(root, &actual, &error) == 0 && actual == expected);
}
int main(void) {
	Directory *root = NULL;
	Error error = {0};
	assert(orbit16_create(&root, &error) == 0 && root);
	Row *missing = NULL;
	assert(orbit16_get_last(root, &missing, &error) == 0 && !missing);
	Probe query = {0, 10, 0, 0, 7, true};
	Selection answer = {0};
	assert(orbit16_scan(root, query, &answer, &error) == 0 && A_CODE(answer) == 83 && A_SCORE(answer) == 0.5 && A_MATCHES(answer) == 3 && A_FOUND(answer) && A_VISITED(answer) == 3);
	requests(root, 1);
	Row *held = NULL;
	assert(orbit16_get_last(root, &held, &error) == 0 && held);
	char *description = NULL;
	int32_t length = 0;
	assert(orbit16_get_description(root, &description, &length, &error) == 0 && length == 15 && !memcmp(description, "Stream query λ", 15) && description[15] == 0);
	assert(orbit16_set_bias(root, 1.0, &error) == 0);
	Q_CEILING(query) = 3;
	Q_MASK(query) = 3;
	Q_LOWEST(query) = false;
	assert(orbit16_scan(root, query, &answer, &error) == 0 && !A_FOUND(answer) && A_CODE(answer) == 0 && A_SCORE(answer) == 0 && A_MATCHES(answer) == 0);
	requests(root, 2);
	assert(orbit16_get_last(root, &missing, &error) == 0 && !missing);
	assert(orbit16_entry_for(root, query, &missing, &error) == 1 && !missing);
	requests(root, 3);
	assert(orbit16_set_bias(root, 0, &error) == 0);
	Q_MIN(query) = 30;
	Q_CEILING(query) = 10;
	Q_MASK(query) = 7;
	assert(orbit16_scan(root, query, &answer, &error) == 0 && A_CODE(answer) == 47 && A_SCORE(answer) == 6.25 && A_MATCHES(answer) == 2 && A_FOUND(answer));
	Row *found = NULL;
	assert(orbit16_entry_for(root, query, &found, &error) == 0 && found);
	requests(root, 5);
	int32_t comparison = 0;
	assert(orbit16_order(root, held, found, &comparison, &error) == 0 && comparison == 1);
	Q_MIN(query) = -1;
	answer = (Selection){99, 99, 99, true, 99};
	assert(orbit16_scan(root, query, &answer, &error) == -1620 && error.domain == 16 && A_CODE(answer) == 0 && A_SCORE(answer) == 0 && !A_MATCHES(answer) && !A_FOUND(answer));
	Q_MIN(query) = 0;
	Q_CEILING(query) = NAN;
	assert(orbit16_scan(root, query, &answer, &error) == -1620);
	Q_CEILING(query) = 10;
	assert(orbit16_set_enabled(root, false, &error) == 0 && orbit16_scan(root, query, &answer, &error) == -1620);
	requests(root, 5);
	uint64_t count = 99;
	assert(orbit16_population(root, UINT32_MAX, &count, &error) == 0 && count == 3);
	assert(orbit16_set_enabled(root, true, &error) == 0);
	Q_MIN(query) = 0;
	Q_CEILING(query) = 10;
	Q_CAP(query) = 1;
	Q_BOOST(query) = 0.5;
	Q_MASK(query) = 7;
	Q_LOWEST(query) = true;
	assert(orbit16_scan(root, query, &answer, &error) == 0 && A_CODE(answer) == 23 && A_SCORE(answer) == PROVIDER_SCORE + 0.5 && A_MATCHES(answer) == 1 && A_VISITED(answer) == 3);
	requests(root, 6);
	orbit16_release(root);
	assert(orbit16_retired_count(1) == 1 && orbit16_retired_count(2) == 1 && orbit16_retired_count(3) == 4 && orbit16_retired_count(4) == 3);
	int64_t code = 0;
	double score = 0;
	assert(orbit_row16_get_code(held, &code, &error) == 0 && code == 83 && orbit_row16_get_score(held, &score, &error) == 0 && score == 0.5);
	assert(orbit_row16_get_code(found, &code, &error) == 0 && code == 47);
	orbit_row16_release(held);
	orbit_row16_release(found);
	assert(orbit16_retired_count(3) == 6);
	assert(!memcmp(description, "Stream query λ", 15));
	assert(orbit16_text_release(&description, &length, &error) == 0 && !description && !length);
	puts("PASS frozen API B3 independent record query, nullable objects, errors and surviving owners");
	return 0;
}
