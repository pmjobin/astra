/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct Row16 { double ratio; uint64_t marker; bool ready; } Row16;
#ifdef USE_SDK
#include "errors16.h"
#define ROW_TYPE SDK_ROW_TYPE
#define ROW_RATIO astra_field_0_ratio
#define ROW_MARKER astra_field_1_marker
#define ROW_READY astra_field_2_ready
#else
typedef struct errors16_handle errors16_handle;
typedef struct error_item16_handle error_item16_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t errors16_create(int32_t,errors16_handle **,astra_foreign_error *);
int32_t errors16_last(errors16_handle *,error_item16_handle **,astra_foreign_error *);
int32_t errors16_read(errors16_handle *,int32_t,int32_t *,astra_foreign_error *);
int32_t errors16_score(errors16_handle *,int32_t,double *,astra_foreign_error *);
int32_t errors16_row(errors16_handle *,int32_t,Row16 *,astra_foreign_error *);
int32_t errors16_update(errors16_handle *,int32_t,int32_t,astra_foreign_error *);
int32_t errors16_take(errors16_handle *,error_item16_handle **,int32_t,int32_t *,astra_foreign_error *);
int32_t errors16_build(errors16_handle *,int32_t,error_item16_handle **,astra_foreign_error *);
int32_t errors16_find(errors16_handle *,bool,int32_t,error_item16_handle **,astra_foreign_error *);
int32_t errors16_fill(errors16_handle *,uint8_t *,int32_t,int32_t,int32_t *,astra_foreign_error *);
int32_t errors16_bytes(errors16_handle *,int32_t,uint8_t **,int32_t *,astra_foreign_error *);
int32_t errors16_text(errors16_handle *,int32_t,char **,int32_t *,astra_foreign_error *);
int32_t errors16_bytes_release(uint8_t **,int32_t *,astra_foreign_error *);
int32_t errors16_text_release(char **,int32_t *,astra_foreign_error *);
int32_t error_item16_create(int32_t,error_item16_handle **,astra_foreign_error *);
int32_t error_item16_code(error_item16_handle *,int32_t *,astra_foreign_error *);
#ifdef EXPECT_SHARED
uint32_t error_item16_release(error_item16_handle *);
uint32_t errors16_release(errors16_handle *);
#else
int32_t error_item16_destroy(error_item16_handle **,astra_foreign_error *);
int32_t errors16_destroy(errors16_handle **,astra_foreign_error *);
#endif
#define ROW_TYPE Row16
#define ROW_RATIO ratio
#define ROW_MARKER marker
#define ROW_READY ready
#endif
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#c); exit(1); } } while (0)
static int faults, items, service_deaths, watching_publication, publication_observed;
#ifdef EXPECT_SHARED
static errors16_handle *dying_service;
#endif
static error_item16_handle *published_item;
int32_t errors16_retired(int32_t kind) {
	if (kind == 1) { ++faults; } else if (kind == 2) { ++items; } else { CHECK(kind == 3); ++service_deaths; if (watching_publication) { CHECK(published_item == NULL); ++publication_observed; } } return 0;
}
int32_t errors16_drop_receiver(void) {
#ifdef EXPECT_SHARED
	CHECK(dying_service && errors16_release(dying_service) >= 1); dying_service = NULL;
#endif
	return 0;
}
static void release_item(error_item16_handle **item) {
#ifdef EXPECT_SHARED
	(void)error_item16_release(*item); *item = NULL;
#else
	CHECK(error_item16_destroy(item,NULL) == 0 && !*item);
#endif
}
int main(void) {
	errors16_handle *service = NULL; astra_foreign_error error = {99,99}; int32_t value = 99, length = 99;
	CHECK(errors16_create(37,&service,&error) == 0 && service && error.domain == 0 && error.code == 0);
#ifdef USE_SDK
	CHECK(errors16_read_ERROR_DOMAIN == 16 && errors16_read_ERROR_BadInput == -1601 && errors16_read_ERROR_Fault == -1600 && errors16_find_NULL_STATUS == 1);
#endif
	for (int mode = 1; mode <= 4; ++mode) {
		int32_t expected = mode == 2 || mode == 3 ? -1601 : -1600; int before = faults; double score = 99;
		value = 99; CHECK(errors16_read(service,mode,&value,&error) == expected && value == 0 && error.domain == 16 && error.code == expected && faults == before + 1);
		CHECK(errors16_score(service,mode,&score,&error) == expected && score == 0.0 && faults == before + 2);
		ROW_TYPE row; memset(&row,0xa5,sizeof row); CHECK(errors16_row(service,mode,&row,&error) == expected && faults == before + 3);
		const uint8_t *storage = (const uint8_t *)&row; for (size_t i = 0; i < sizeof row; ++i) { CHECK(storage[i] == 0); }
		CHECK(errors16_update(service,99,mode,&error) == expected && faults == before + 4);
		uint8_t output[3] = {81,82,83}; value = 99;
		CHECK(errors16_fill(service,output,3,mode,&value,&error) == expected && value == 0 && output[0] == 81 && output[1] == 82 && output[2] == 83 && faults == before + 5);
		uint8_t *bytes = (void *)(uintptr_t)1; length = 99;
		CHECK(errors16_bytes(service,mode,&bytes,&length,&error) == expected && !bytes && length == 0 && faults == before + 6);
		char *text = (void *)(uintptr_t)1; length = 99;
		CHECK(errors16_text(service,mode,&text,&length,&error) == expected && !text && length == 0 && faults == before + 7);
		error_item16_handle *item = (void *)(uintptr_t)1; int before_items = items;
		CHECK(errors16_build(service,mode,&item,&error) == expected && !item && items == before_items + 1 && faults == before + 8);
		CHECK(error_item16_create(29,&item,NULL) == 0 && item); value = 99;
		CHECK(errors16_take(service,&item,mode,&value,&error) == expected && !item && value == 0 && items == before_items + 2 && faults == before + 9);
		CHECK(errors16_find(service,false,mode,&item,&error) == expected && !item && faults == before + 10);
		CHECK(errors16_read(service,mode,&value,NULL) == expected && value == 0 && faults == before + 11);
	}
	CHECK(errors16_read(service,0,&value,&error) == 0 && value == 37 && error.domain == 0 && error.code == 0);
	double score = 0; CHECK(errors16_score(service,0,&score,&error) == 0 && score == 42.5);
	ROW_TYPE row; CHECK(errors16_row(service,0,&row,&error) == 0 && row.ROW_RATIO == 42.5 && row.ROW_MARKER == UINT64_C(9223372036854775809) && row.ROW_READY);
	error_item16_handle *item = NULL; CHECK(errors16_find(service,false,0,&item,&error) == 1 && !item && error.domain == 0 && error.code == 0);
	CHECK(errors16_find(service,true,0,&item,&error) == 0 && item); CHECK(error_item16_code(item,&value,NULL) == 0 && value == 73); release_item(&item);
	uint8_t output[3] = {81,82,83}; CHECK(errors16_fill(service,output,3,0,&value,&error) == 0 && value == 1 && output[0] == 66 && output[1] == 82 && output[2] == 83);
	uint8_t *bytes = NULL; CHECK(errors16_bytes(service,0,&bytes,&length,&error) == 0 && bytes && length == 3 && bytes[0] == 21 && bytes[2] == 23);
	CHECK(errors16_bytes_release(&bytes,&length,&error) == 0 && !bytes && !length);
	char *text = NULL; CHECK(errors16_text(service,0,&text,&length,&error) == 0 && text && length == 5 && memcmp(text,"hi\0\xc3\xa9",5) == 0);
	CHECK(errors16_text_release(&text,&length,&error) == 0 && !text && !length);
#ifdef USE_SDK
	error.domain = 16; error.code = -1601; astra_foreign_error_clear(&error); CHECK(error.domain == 0 && error.code == 0); astra_foreign_error_clear(NULL);
#endif
#ifdef EXPECT_SHARED
	CHECK(errors16_release(service) == 0);
#else
	CHECK(errors16_destroy(&service,NULL) == 0 && !service);
#endif
	CHECK(faults == 44 && items == 9);
#ifdef EXPECT_SHARED
	CHECK(errors16_create(19,&dying_service,NULL) == 0); watching_publication = 1;
	CHECK(errors16_last(dying_service,&published_item,NULL) == 0 && published_item && !dying_service && publication_observed == 1 && service_deaths == 2); watching_publication = 0;
	CHECK(error_item16_code(published_item,&value,NULL) == 0 && value == 75); release_item(&published_item); CHECK(items == 10);
#endif
	puts("PASS named checked errors, outputs, native cleanup and nonfailure status"); return 0;
}
