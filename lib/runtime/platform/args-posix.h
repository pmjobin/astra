/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_ARGS_POSIX_H
#define ASTRA_ARGS_POSIX_H

#include <stdint.h>

/* Private x86-64 Linux startup protocol; not an Astra source CABI. */
struct AstraArgsTextV0 {
	const unsigned char *data;
	int32_t byte_length;
};

int32_t astra_host_args_prepare_v0(int32_t argc, char *const *argv, const struct AstraArgsTextV0 **out_items);
void astra_host_args_dispose_v0(const struct AstraArgsTextV0 *items);

#endif
