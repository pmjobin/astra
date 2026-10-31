/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_ASYNC_LINUX_H
#define ASTRA_ASYNC_LINUX_H
#include "virtual.h"

/* L1 successor boundary; the existing native-tasks-v15 ownership ABI is shared. */
enum AstraAsyncLinuxOperation { ASTRA_LINUX_NONE,
	                            ASTRA_LINUX_CAPACITY,
	                            ASTRA_LINUX_KERNEL,
	                            ASTRA_LINUX_SETUP,
	                            ASTRA_LINUX_PROFILE,
	                            ASTRA_LINUX_PROBE,
	                            ASTRA_LINUX_DURATION,
	                            ASTRA_LINUX_CREDITS,
	                            ASTRA_LINUX_IDS,
	                            ASTRA_LINUX_SUBMIT,
	                            ASTRA_LINUX_DECODE,
	                            ASTRA_LINUX_TARGET,
	                            ASTRA_LINUX_CANCEL };
typedef struct AstraAsyncLinuxFailure {
	int operation;
	int error;
	uint64_t operation_id;
} AstraAsyncLinuxFailure;
AstraAsyncExecutor *astra_async_linux_open(uint32_t capacity);
int astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds);
int astra_async_linux_delay_result(AstraAsyncTask *task, uint32_t pc);
int astra_async_linux_wait(AstraAsyncExecutor *executor);
AstraAsyncLinuxFailure astra_async_linux_last_failure(void);
/* Opaque unique fd+buffer owner. No buffer or descriptor escapes this API. */
typedef struct AstraLinuxPayload AstraLinuxPayload;
AstraLinuxPayload *astra_linux_payload_open(const unsigned char *path, int length, int capacity, int writing);
void astra_linux_payload_close(AstraLinuxPayload *payload);
int astra_linux_payload_configure(AstraLinuxPayload *payload, int offset, int count, int64_t file_offset);
int astra_linux_payload_byte(AstraLinuxPayload *payload, int index);
int astra_linux_payload_set(AstraLinuxPayload *payload, int index, int byte);
int astra_linux_payload_count(AstraLinuxPayload *payload);
int astra_linux_payload_error(AstraLinuxPayload *payload);
int astra_linux_payload_finish(AstraLinuxPayload *payload);
int astra_async_linux_payload(AstraAsyncTask *task, AstraLinuxPayload *payload);
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
void astra_linux_payload_test_bad_fd(AstraLinuxPayload *payload);
typedef struct AstraAsyncLinuxSnapshot {
	AstraAsyncToken token;
	uint64_t target;
	uint64_t cancel;
	uint64_t generation;
	uint32_t pc;
	unsigned prepared;
	unsigned cancel_prepared;
	unsigned target_seen;
	unsigned cancel_seen;
	int target_result;
	int cancel_result;
	unsigned active;
	uint64_t ns;
	unsigned exposed;
	unsigned consumed;
	unsigned cancel_exposed;
	unsigned cancel_consumed;
} AstraAsyncLinuxSnapshot;
int astra_async_linux_test_snapshot(AstraAsyncExecutor *executor, uint32_t slot, AstraAsyncLinuxSnapshot *out);
int astra_async_linux_test_record(AstraAsyncExecutor *executor, uint32_t slot, AstraAsyncLinuxSnapshot *out);
int astra_async_linux_test_decode(AstraAsyncExecutor *executor, uint64_t id, int result, unsigned flags);
void astra_async_linux_test_fake(AstraAsyncExecutor *executor);
void astra_async_linux_test_submit(AstraAsyncExecutor *executor, int result);
void astra_async_linux_test_hold_submit(AstraAsyncExecutor *executor, int hold);
unsigned astra_async_linux_test_pending(AstraAsyncExecutor *executor);
int astra_async_linux_test_queued(AstraAsyncExecutor *executor, uint64_t id);
void astra_async_linux_test_ids(AstraAsyncExecutor *executor, uint64_t next);
void astra_async_linux_test_transport(AstraAsyncExecutor *executor, int injected_submit, int hold_completions);
#endif
#endif
