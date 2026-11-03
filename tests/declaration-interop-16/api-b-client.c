/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#ifdef USE_SDK
#include "native.h"
#include "api-types.h"
#else
typedef struct Index Index;
typedef struct Match Match;

typedef struct {
	int64_t minimum;
	double ceiling;
	uint32_t mask;
	bool lowest;
} Query;

typedef struct {
	int64_t code;
	double score;
	uint32_t matches;
	bool found;
} Answer;

typedef struct {
	int32_t domain, code;
} Error;

_Static_assert(sizeof(Query) == 24 && offsetof(Query, lowest) == 20 && sizeof(Answer) == 24 && offsetof(Answer, found) == 20, "independent query/answer POD layout");
extern int32_t record_query16_create(Index **, Error *);
extern int32_t record_query16_search(Index *, Query, Answer *, Error *);
extern int32_t record_query16_find(Index *, Query, Match **, Error *);
extern int32_t record_query16_compare(Index *, Match *, Match *, int32_t *, Error *);
extern int32_t record_query16_get_requests(Index *, int32_t *, Error *);
extern int32_t record_query16_set_enabled(Index *, bool, Error *);
extern int32_t record_query16_set_bias(Index *, double, Error *);
extern int32_t record_query16_get_last(Index *, Match **, Error *);
extern int32_t record_query16_get_description(Index *, char **, int32_t *, Error *);
extern int32_t record_query16_text_release(char **, int32_t *, Error *);
extern uint32_t record_query16_release(Index *);
extern int32_t record_match16_get_code(Match *, int64_t *, Error *);
extern int32_t record_match16_get_score(Match *, double *, Error *);
extern uint32_t record_match16_release(Match *);
#define Q_MIN(value) ((value).minimum)
#define Q_CEILING(value) ((value).ceiling)
#define Q_MASK(value) ((value).mask)
#define Q_LOWEST(value) ((value).lowest)
#define A_CODE(value) ((value).code)
#define A_SCORE(value) ((value).score)
#define A_MATCHES(value) ((value).matches)
#define A_FOUND(value) ((value).found)
#endif
extern uint32_t query16_retired_count(int32_t);

static void requests(Index *root, int expected) {
	int32_t actual = -1;
	Error error = {0};
	assert(record_query16_get_requests(root, &actual, &error) == 0 && actual == expected);
}

int main(void) {
	Index *root = NULL;
	Error error = {0};
	assert(record_query16_create(&root, &error) == 0 && root);
	Match *missing = NULL;
	assert(record_query16_get_last(root, &missing, &error) == 0 && !missing);
	Query query = {0, 10, 7, true};
	Answer answer = {0};
	assert(record_query16_search(root, query, &answer, &error) == 0 && A_CODE(answer) == 59 && A_SCORE(answer) == 1.75 && A_MATCHES(answer) == 3 && A_FOUND(answer));
	requests(root, 1);
	Match *held = NULL;
	assert(record_query16_get_last(root, &held, &error) == 0 && held);
	char *description = NULL;
	int32_t length = 0;
	assert(record_query16_get_description(root, &description, &length, &error) == 0 && length == 15 && !memcmp(description, "Record index λ", 15) && description[15] == 0);
	assert(record_query16_set_bias(root, 1.0, &error) == 0);
	Q_CEILING(query) = 3;
	Q_MASK(query) = 3;
	Q_LOWEST(query) = false;
	assert(record_query16_search(root, query, &answer, &error) == 0 && !A_FOUND(answer) && A_CODE(answer) == 0 && A_SCORE(answer) == 0 && A_MATCHES(answer) == 0);
	requests(root, 2);
	assert(record_query16_get_last(root, &missing, &error) == 0 && !missing);
	assert(record_query16_find(root, query, &missing, &error) == 1 && !missing);
	requests(root, 3);
	assert(record_query16_set_bias(root, 0, &error) == 0);
	Q_MIN(query) = 20;
	Q_CEILING(query) = 10;
	Q_MASK(query) = 7;
	assert(record_query16_search(root, query, &answer, &error) == 0 && A_CODE(answer) == 31 && A_SCORE(answer) == 5.5 && A_MATCHES(answer) == 2 && A_FOUND(answer));
	Match *found = NULL;
	assert(record_query16_find(root, query, &found, &error) == 0 && found);
	requests(root, 5);
	int32_t comparison = 0;
	assert(record_query16_compare(root, held, found, &comparison, &error) == 0 && comparison == 1);
	Q_MIN(query) = -1;
	answer = (Answer){99, 99, 99, true};
	assert(record_query16_search(root, query, &answer, &error) == -1620 && error.domain == 16 && A_CODE(answer) == 0 && A_SCORE(answer) == 0 && !A_MATCHES(answer) && !A_FOUND(answer));
	Q_MIN(query) = 0;
	Q_CEILING(query) = NAN;
	assert(record_query16_search(root, query, &answer, &error) == -1620);
	Q_CEILING(query) = 10;
	assert(record_query16_set_enabled(root, false, &error) == 0 && record_query16_search(root, query, &answer, &error) == -1620);
	requests(root, 5);
	record_query16_release(root);
	assert(query16_retired_count(1) == 1 && query16_retired_count(2) == 1 && query16_retired_count(3) == 3 && query16_retired_count(4) == 3);
	int64_t code = 0;
	double score = 0;
	assert(record_match16_get_code(held, &code, &error) == 0 && code == 59 && record_match16_get_score(held, &score, &error) == 0 && score == 1.75);
	assert(record_match16_get_code(found, &code, &error) == 0 && code == 31);
	record_match16_release(held);
	record_match16_release(found);
	assert(query16_retired_count(3) == 5);
	assert(!memcmp(description, "Record index λ", 15));
	assert(record_query16_text_release(&description, &length, &error) == 0 && !description && !length);
	puts("PASS frozen API B independent record query, nullable objects, errors and surviving owners");
	return 0;
}
