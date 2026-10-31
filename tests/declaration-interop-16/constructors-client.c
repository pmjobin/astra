/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#ifdef USE_SDK
#include "constructors16.h"
#else
typedef struct ctor16_handle ctor16_handle;
typedef struct ctor_item16_handle ctor_item16_handle;
typedef struct ctor_extra16_handle ctor_extra16_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t ctor16_create(ctor_item16_handle **,ctor_item16_handle **,int32_t,ctor16_handle **,astra_foreign_error *);
int32_t ctor16_total(ctor16_handle *,int32_t *,astra_foreign_error *);
int32_t ctor_item16_create(int32_t,ctor_item16_handle **,astra_foreign_error *);
int32_t ctor_extra16_create(int32_t,ctor_extra16_handle **,astra_foreign_error *);
int32_t ctor_extra16_cached_code(ctor_extra16_handle *,int32_t *,astra_foreign_error *);
#ifdef EXPECT_SHARED
uint32_t ctor16_release(ctor16_handle *);
uint32_t ctor_item16_release(ctor_item16_handle *);
uint32_t ctor_extra16_release(ctor_extra16_handle *);
#else
int32_t ctor16_destroy(ctor16_handle **,astra_foreign_error *);
int32_t ctor_item16_destroy(ctor_item16_handle **,astra_foreign_error *);
int32_t ctor_extra16_destroy(ctor_extra16_handle **,astra_foreign_error *);
#endif
#endif
int32_t native_constructor_probe(int32_t);
int32_t native_constructor_lexical_probe(int32_t);
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#c); exit(1); } } while (0)
#define STATUS(c) ((int32_t)UINT32_C(c))
static int events[32], event_count, allocations, deny_allocation, retirement_refusals;
static ctor16_handle *observed_parent;
void *__real_calloc(size_t,size_t);
void *__wrap_calloc(size_t n,size_t s) { ++allocations; return deny_allocation && allocations == deny_allocation ? NULL : __real_calloc(n,s); }
int32_t ctor16_retired(int32_t kind) {
	CHECK(event_count < 32); events[event_count++] = kind;
	if (kind == 100 && observed_parent) { int32_t value = 99; CHECK(ctor16_total(observed_parent,&value,NULL) == STATUS(0x8000ffff) && value == 0); ++retirement_refusals; }
	return 0;
}
static int count(int kind) { int found = 0; for (int i = 0; i < event_count; ++i) { found += events[i] == kind; } return found; }
static void inputs(ctor_item16_handle **first,ctor_item16_handle **second) { CHECK(ctor_item16_create(1,first,NULL) == 0 && ctor_item16_create(2,second,NULL) == 0); }
static void release_item(ctor_item16_handle **item) {
#ifdef EXPECT_SHARED
	(void)ctor_item16_release(*item); *item = NULL;
#else
	CHECK(ctor_item16_destroy(item,NULL) == 0 && !*item);
#endif
}
int main(void) {
	for (int mode = 1; mode <= 6; ++mode) {
		ctor_item16_handle *first = NULL, *second = NULL; ctor16_handle *session = (void *)(uintptr_t)1; astra_foreign_error error = {99,99}; inputs(&first,&second); event_count = 0;
		CHECK(ctor16_create(&first,&second,mode,&session,&error) == -1600 && !first && !second && !session && error.domain == 16 && error.code == -1600);
		CHECK(count(1) == 1 && count(2) == 1 && count(200) == 1 && count(100) == 0 && event_count == 3);
		if (mode >= 3) { CHECK(events[0] == 1 && events[1] == 2 && events[2] == 200); }
	}
	for (int lexical = 0; lexical <= 1; ++lexical) {
		for (int mode = 1; mode <= 6; ++mode) {
			event_count = 0; CHECK((lexical ? native_constructor_lexical_probe(mode) : native_constructor_probe(mode)) == -1600);
			CHECK(count(1) == 1 && count(2) == 1 && count(200) == 1 && count(100) == 0 && event_count == 3);
			if (mode >= 3) { CHECK(events[0] == 1 && events[1] == 2); }
		}
		event_count = 0; CHECK((lexical ? native_constructor_lexical_probe(0) : native_constructor_probe(0)) == 14);
		CHECK(event_count == 3 && events[0] == 100 && events[1] == 2 && events[2] == 1);
	}
	ctor_item16_handle *first = NULL, *second = NULL; ctor16_handle *session = NULL; astra_foreign_error error = {99,99}; inputs(&first,&second); event_count = 0;
	allocations = 0; deny_allocation = 1;
	CHECK(ctor16_create(&first,&second,0,&session,&error) == STATUS(0x8007000e) && first && second && !session && !event_count); deny_allocation = 0;
	release_item(&first); release_item(&second); CHECK(count(1) == 1 && count(2) == 1);
	inputs(&first,&second); event_count = 0; allocations = 0; deny_allocation = 4;
	CHECK(ctor16_create(&first,&second,0,&session,&error) == STATUS(0x8007000e) && !first && !second && !session); deny_allocation = 0;
	CHECK(event_count == 3 && events[0] == 100 && events[1] == 2 && events[2] == 1);
	inputs(&first,&second); event_count = 0;
	CHECK(ctor16_create(&first,&second,0,&session,&error) == 0 && !first && !second && session);
	int32_t total = 0; CHECK(ctor16_total(session,&total,&error) == 0 && total == 14); observed_parent = session;
#ifdef EXPECT_SHARED
	CHECK(ctor16_release(session) == 0); session = NULL;
#else
	CHECK(ctor16_destroy(&session,NULL) == 0 && !session);
#endif
	observed_parent = NULL; CHECK(retirement_refusals == 1 && event_count == 3 && events[0] == 100 && events[1] == 2 && events[2] == 1);
	for (int mode = 1; mode <= 4; ++mode) {
		ctor_extra16_handle *extra = NULL; event_count = 0;
		CHECK(ctor_extra16_create(mode,&extra,&error) == -1600 && !extra && !count(101) && count(200) == 1);
		CHECK(count(3) == (mode >= 2) && count(4) == (mode >= 3) && !count(5));
		if (mode == 4) { CHECK(event_count == 3 && events[0] == 4 && events[1] == 3 && events[2] == 200); }
	}
	ctor_extra16_handle *extra = NULL; event_count = 0; CHECK(ctor_extra16_create(0,&extra,&error) == 0 && extra);
	int32_t cached_code = 0; CHECK(ctor_extra16_cached_code(extra,&cached_code,&error) == 0 && cached_code == 5);
#ifdef EXPECT_SHARED
	CHECK(ctor_extra16_release(extra) == 0);
#else
	CHECK(ctor_extra16_destroy(&extra,NULL) == 0 && !extra);
#endif
	CHECK(event_count == 4 && events[0] == 101 && count(3) == 1 && count(4) == 1 && count(5) == 1);
	puts("PASS checked constructors, partial ownership, acquisition order and native caller cleanup"); return 0;
}
