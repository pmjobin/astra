/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#ifndef PROVIDER_SCORE
#define PROVIDER_SCORE 2.25
#endif
#ifdef USE_SDK
#include "native.h"
#include "api-types.h"
#else
typedef struct Catalog Catalog;
typedef struct Entry Entry;
typedef struct {
	double ceiling;
	int64_t minimum;
	uint64_t cap;
	uint32_t mask;
	bool lowest;
} Query;
typedef struct {
	double score;
	int64_t code;
	uint32_t matches;
	bool found;
	uint64_t visited;
} Answer;
typedef struct {
	int32_t domain, code;
} Error;
_Static_assert(sizeof(Query) == 32 && offsetof(Query, lowest) == 28 && offsetof(Query, cap) == 16 && sizeof(Answer) == 32 && offsetof(Answer, found) == 20 && offsetof(Answer, visited) == 24, "independent query/answer POD layout");
extern int32_t catalog16_create(Catalog **, Error *);
extern int32_t catalog16_lookup(Catalog *, Query, Answer *, Error *);
extern int32_t catalog16_resolve(Catalog *, Query, Entry **, Error *);
extern int32_t catalog16_cardinality(Catalog *, uint32_t, uint64_t *, Error *);
extern int32_t catalog16_rank(Catalog *, Entry *, Entry *, int32_t *, Error *);
extern int32_t catalog16_get_requests(Catalog *, int32_t *, Error *);
extern int32_t catalog16_set_enabled(Catalog *, bool, Error *);
extern int32_t catalog16_set_bias(Catalog *, double, Error *);
extern int32_t catalog16_get_last(Catalog *, Entry **, Error *);
extern int32_t catalog16_get_description(Catalog *, char **, int32_t *, Error *);
extern int32_t catalog16_text_release(char **, int32_t *, Error *);
extern uint32_t catalog16_release(Catalog *);
extern int32_t catalog_entry16_get_code(Entry *, int64_t *, Error *);
extern int32_t catalog_entry16_get_score(Entry *, double *, Error *);
extern uint32_t catalog_entry16_release(Entry *);
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
extern uint32_t lens16_retired_count(int32_t);
static void requests(Catalog *root, int expected) {
	int32_t actual = -1;
	Error error = {0};
	assert(catalog16_get_requests(root, &actual, &error) == 0 && actual == expected);
}
int main(void) {
	Catalog *root = NULL;
	Error error = {0};
	assert(catalog16_create(&root, &error) == 0 && root);
	Entry *missing = NULL;
	assert(catalog16_get_last(root, &missing, &error) == 0 && !missing);
	Query query = {10, 0, 0, 7, true};
	Answer answer = {0};
	assert(catalog16_lookup(root, query, &answer, &error) == 0 && A_CODE(answer) == 59 && A_SCORE(answer) == 1.75 && A_MATCHES(answer) == 3 && A_FOUND(answer) && A_VISITED(answer) == 3);
	requests(root, 1);
	Entry *held = NULL;
	assert(catalog16_get_last(root, &held, &error) == 0 && held);
	char *description = NULL;
	int32_t length = 0;
	assert(catalog16_get_description(root, &description, &length, &error) == 0 && length == 15 && !memcmp(description, "Record index λ", 15) && description[15] == 0);
	assert(catalog16_set_bias(root, 1.0, &error) == 0);
	Q_CEILING(query) = 3;
	Q_MASK(query) = 3;
	Q_LOWEST(query) = false;
	assert(catalog16_lookup(root, query, &answer, &error) == 0 && !A_FOUND(answer) && A_CODE(answer) == 0 && A_SCORE(answer) == 0 && A_MATCHES(answer) == 0);
	requests(root, 2);
	assert(catalog16_get_last(root, &missing, &error) == 0 && !missing);
	assert(catalog16_resolve(root, query, &missing, &error) == 1 && !missing);
	requests(root, 3);
	assert(catalog16_set_bias(root, 0, &error) == 0);
	Q_MIN(query) = 20;
	Q_CEILING(query) = 10;
	Q_MASK(query) = 7;
	assert(catalog16_lookup(root, query, &answer, &error) == 0 && A_CODE(answer) == 31 && A_SCORE(answer) == 5.5 && A_MATCHES(answer) == 2 && A_FOUND(answer));
	Entry *found = NULL;
	assert(catalog16_resolve(root, query, &found, &error) == 0 && found);
	requests(root, 5);
	int32_t comparison = 0;
	assert(catalog16_rank(root, held, found, &comparison, &error) == 0 && comparison == 1);
	Q_MIN(query) = -1;
	answer = (Answer){99, 99, 99, true, 99};
	assert(catalog16_lookup(root, query, &answer, &error) == -1620 && error.domain == 16 && A_CODE(answer) == 0 && A_SCORE(answer) == 0 && !A_MATCHES(answer) && !A_FOUND(answer));
	Q_MIN(query) = 0;
	Q_CEILING(query) = NAN;
	assert(catalog16_lookup(root, query, &answer, &error) == -1620);
	Q_CEILING(query) = 10;
	assert(catalog16_set_enabled(root, false, &error) == 0 && catalog16_lookup(root, query, &answer, &error) == -1620);
	requests(root, 5);
	uint64_t count = 99;
	assert(catalog16_cardinality(root, UINT32_MAX, &count, &error) == 0 && count == 3);
	assert(catalog16_set_enabled(root, true, &error) == 0);
	Q_MIN(query) = 0;
	Q_CEILING(query) = 10;
	Q_CAP(query) = 1;
	Q_MASK(query) = 7;
	Q_LOWEST(query) = true;
	assert(catalog16_lookup(root, query, &answer, &error) == 0 && A_CODE(answer) == 17 && A_SCORE(answer) == PROVIDER_SCORE && A_MATCHES(answer) == 1 && A_VISITED(answer) == 3);
	requests(root, 6);
	catalog16_release(root);
	assert(lens16_retired_count(1) == 1 && lens16_retired_count(2) == 1 && lens16_retired_count(3) == 4 && lens16_retired_count(4) == 3);
	int64_t code = 0;
	double score = 0;
	assert(catalog_entry16_get_code(held, &code, &error) == 0 && code == 59 && catalog_entry16_get_score(held, &score, &error) == 0 && score == 1.75);
	assert(catalog_entry16_get_code(found, &code, &error) == 0 && code == 31);
	catalog_entry16_release(held);
	catalog_entry16_release(found);
	assert(lens16_retired_count(3) == 6);
	assert(!memcmp(description, "Record index λ", 15));
	assert(catalog16_text_release(&description, &length, &error) == 0 && !description && !length);
	puts("PASS frozen API B2 independent record query, nullable objects, errors and surviving owners");
	return 0;
}
