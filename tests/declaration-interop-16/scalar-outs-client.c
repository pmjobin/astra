/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef USE_SDK
#include "scalar-outs16.h"
#else
typedef struct outs16_handle outs16_handle;
typedef struct out_ctor16_handle out_ctor16_handle;
typedef struct out_child16_handle out_child16_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t outs16_create(int32_t,int64_t *,outs16_handle **,astra_foreign_error *);
int32_t outs16_calculate(outs16_handle *,int32_t,int32_t *,uint32_t *,int64_t *,uint64_t *,float *,double *,astra_foreign_error *);
int32_t outs16_snapshot(outs16_handle *,const int32_t *,int32_t *,astra_foreign_error *);
int32_t outs16_fill(outs16_handle *,uint8_t *,int32_t,int32_t *,int32_t,bool *,astra_foreign_error *);
int32_t outs16_compose(outs16_handle *,uint8_t *,int32_t,int32_t *,int32_t,out_child16_handle **,astra_foreign_error *);
int32_t out_ctor16_create(uint8_t *,int32_t,int32_t *,int32_t,out_ctor16_handle **,astra_foreign_error *);
int32_t out_child16_code(out_child16_handle *,int32_t *,astra_foreign_error *);
#ifdef EXPECT_SHARED
uint32_t outs16_release(outs16_handle *);
uint32_t out_ctor16_release(out_ctor16_handle *);
uint32_t out_child16_release(out_child16_handle *);
#else
int32_t outs16_destroy(outs16_handle **,astra_foreign_error *);
int32_t out_ctor16_destroy(out_ctor16_handle **,astra_foreign_error *);
int32_t out_child16_destroy(out_child16_handle **,astra_foreign_error *);
#endif
#endif
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#c); exit(1); } } while (0)
#define STATUS(c) ((int32_t)UINT32_C(c))
static int faults, children, constructors, allocations, deny_allocation;
void *__real_calloc(size_t,size_t);
void *__wrap_calloc(size_t n,size_t s) { ++allocations; return deny_allocation && allocations == deny_allocation ? NULL : __real_calloc(n,s); }
int32_t outs16_retired(int32_t kind) { if (kind == 1) { ++faults; } else if (kind == 2) { ++children; } else { CHECK(kind == 3); ++constructors; } return 0; }
static void release_child(out_child16_handle **child) {
#ifdef EXPECT_SHARED
	(void)out_child16_release(*child); *child = NULL;
#else
	CHECK(out_child16_destroy(child,NULL) == 0 && !*child);
#endif
}
int main(void) {
	outs16_handle *service = NULL; astra_foreign_error error = {99,99}; int64_t born = 99;
	CHECK(outs16_create(7,&born,&service,&error) == 0 && service && born == INT64_C(4000000007));
	int32_t sum = 99; uint32_t unsigned32 = 99; int64_t signed64 = 99; uint64_t unsigned64 = 99; float single = 99; double double_value = 10;
	CHECK(outs16_calculate(service,0,&sum,&unsigned32,&signed64,&unsigned64,&single,&double_value,&error) == 0);
	CHECK(sum == 16 && unsigned32 == UINT32_C(4000000000) && signed64 == -INT64_C(4000000000) && unsigned64 == UINT64_C(9223372036854775809) && single == 1.25f && double_value == 12.5);
	double_value = 10;
	CHECK(outs16_calculate(service,1,&sum,&unsigned32,&signed64,&unsigned64,&single,&double_value,&error) == -1600 && error.domain == 16 && faults == 1);
	CHECK(!sum && !unsigned32 && !signed64 && !unsigned64 && single == 0 && double_value == 10);
	CHECK(outs16_calculate(service,0,NULL,&unsigned32,&signed64,&unsigned64,&single,&double_value,&error) == STATUS(0x80004003));
	int32_t input = 11, value = 99; CHECK(outs16_snapshot(service,&input,&value,&error) == 0 && value == 18 && input == 11);
	CHECK(outs16_snapshot(service,&input,&input,&error) == STATUS(0x80070057) && input == 11);
	uint8_t output[4]; int32_t produced = 99; bool ready = true;
	for (int mode = 1; mode <= 3; ++mode) {
		memset(output,81,sizeof output); produced = 99; ready = true;
		CHECK(outs16_fill(service,output,4,&produced,mode,&ready,&error) == (mode == 1 ? -1600 : STATUS(0x8000ffff)));
		CHECK(!produced && !ready && output[0] == 81 && output[3] == 81);
	}
	CHECK(faults == 2);
	CHECK(outs16_fill(service,output,4,&produced,0,&ready,&error) == 0 && produced == 4 && ready && output[0] == 61 && output[1] == 0 && output[3] == 0);
	out_child16_handle *child = NULL; memset(output,81,sizeof output); produced = 99;
	CHECK(outs16_compose(service,output,4,&produced,1,&child,&error) == STATUS(0x8000ffff) && !child && !produced && output[0] == 81 && children == 1);
	allocations = 0; deny_allocation = 3;
	CHECK(outs16_compose(service,output,4,&produced,0,&child,&error) == STATUS(0x8007000e) && !child && !produced && output[0] == 81 && children == 2); deny_allocation = 0;
	CHECK(outs16_compose(service,output,4,&produced,0,&child,&error) == 0 && child && produced == 4 && output[0] == 65);
	CHECK(out_child16_code(child,&value,&error) == 0 && value == 17); release_child(&child); CHECK(children == 3);
	out_ctor16_handle *ctor = NULL; memset(output,81,sizeof output); produced = 99;
	CHECK(out_ctor16_create(output,4,&produced,1,&ctor,&error) == STATUS(0x8000ffff) && !ctor && !produced && output[0] == 81 && constructors == 1);
	allocations = 0; deny_allocation = 3;
	CHECK(out_ctor16_create(output,4,&produced,0,&ctor,&error) == STATUS(0x8007000e) && !ctor && !produced && output[0] == 81 && constructors == 2); deny_allocation = 0;
	CHECK(out_ctor16_create(output,4,&produced,0,&ctor,&error) == 0 && ctor && produced == 4 && output[0] == 63);
#ifdef EXPECT_SHARED
	CHECK(out_ctor16_release(ctor) == 0 && outs16_release(service) == 0);
#else
	CHECK(out_ctor16_destroy(&ctor,NULL) == 0 && !ctor && outs16_destroy(&service,NULL) == 0 && !service);
#endif
	CHECK(constructors == 3);
	puts("PASS typed scalar outputs, explicit produced counts and provisional object cleanup"); return 0;
}
