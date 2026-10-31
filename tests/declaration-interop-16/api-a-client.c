/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifdef USE_SDK
#include "native.h"
#include "api-types.h"
#else
typedef struct Session Session;
typedef struct {
	int32_t mask;
	bool rotate;
	double weight;
} Configuration;
typedef struct {
	double score;
	uint64_t revision, processed;
} Statistics;
typedef struct {
	int32_t domain, code;
} Error;
_Static_assert(sizeof(Configuration) == 16 && sizeof(Statistics) == 24, "independent application POD layouts");
extern int32_t byte_session16_create(Configuration, Session **, Error *);
extern int32_t byte_session16_configure(Session *, Configuration, Error *);
extern int32_t byte_session16_process(Session *, const uint8_t *, int32_t, uint8_t *, int32_t, int32_t *, Error *);
extern int32_t byte_session16_statistics(Session *, Statistics *, Error *);
extern int32_t byte_session16_snapshot(Session *, uint8_t **, int32_t *, Error *);
extern int32_t byte_session16_bytes_release(uint8_t **, int32_t *, Error *);
extern int32_t byte_session16_destroy(Session **, Error *);
#endif
extern uint32_t byte16_retired_count(int32_t);
#define sessions byte16_retired_count(1)
#define errors byte16_retired_count(2)
static void stats(Session *session, uint64_t revision, uint64_t processed, double score) {
	Statistics actual = {0};
	Error error = {0};
	assert(byte_session16_statistics(session, &actual, &error) == 0 && actual.revision == revision && actual.processed == processed && actual.score == score);
}
int main(void) {
	Configuration configuration = {85, true, 2.5};
	Session *session = NULL;
	Error error = {0};
	Configuration invalid = {256, true, 1.0};
	assert(byte_session16_create(invalid, &session, &error) == -1610 && !session && error.domain == 16 && errors == 1);
	assert(byte_session16_create(configuration, &session, &error) == 0 && session);
	stats(session, 0, 0, 0);
	const uint8_t input[] = {0, 1, 254, 255, 0, 128}, expected[] = {170, 168, 87, 85, 170, 171};
	uint8_t output[8];
	memset(output, 77, sizeof output);
	int32_t produced = -1;
	assert(byte_session16_process(session, input, 6, output, 8, &produced, &error) == 0 && produced == 6 && !memcmp(output, expected, 6) && output[6] == 77 && output[7] == 77);
	stats(session, 1, 6, 2127.5);
	uint8_t *snapshot = NULL;
	int32_t length = 0;
	assert(byte_session16_snapshot(session, &snapshot, &length, &error) == 0 && length == 6 && !memcmp(snapshot, expected, 6));
	memset(output, 77, sizeof output);
	assert(byte_session16_process(session, input, 6, output, 2, &produced, &error) == -1610 && produced == 0 && output[0] == 77 && error.domain == 16);
	stats(session, 1, 6, 2127.5);
	Configuration nan = {85, true, NAN};
	assert(byte_session16_configure(session, nan, &error) == -1610);
	assert(byte_session16_configure(session, invalid, &error) == -1610);
	stats(session, 1, 6, 2127.5);
	const uint8_t again[] = {3, 0, 254}, second[] = {172, 170, 87};
	assert(byte_session16_process(session, again, 3, output, 8, &produced, &error) == 0 && produced == 3 && !memcmp(output, second, 3));
	stats(session, 2, 9, 3200.0);
	assert(length == 6 && !memcmp(snapshot, expected, 6));
	assert(byte_session16_process(session, NULL, 0, NULL, 0, &produced, &error) == 0 && produced == 0);
	stats(session, 3, 9, 3200.0);
	assert(byte_session16_process(session, NULL, 1, output, 8, &produced, &error) < 0 && produced == 0);
	stats(session, 3, 9, 3200.0);
	assert(byte_session16_destroy(&session, &error) == 0 && !session && sessions == 1 && errors == 4);
	assert(length == 6 && !memcmp(snapshot, expected, 6));
	assert(byte_session16_bytes_release(&snapshot, &length, &error) == 0 && !snapshot && !length);
	puts("PASS API A unique processing session: checked configuration, bounded output, statistics and independent snapshots");
	return 0;
}
