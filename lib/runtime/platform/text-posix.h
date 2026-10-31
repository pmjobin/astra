/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_TEXT_POSIX_H
#define ASTRA_TEXT_POSIX_H

#include <stdint.h>

/* Borrow [data, data + byte_length) only during this call. Empty permits NULL.
 * stream: 1 stdout, 2 stderr. newline: 0 payload only, 1 append LF.
 * Return 0 on complete success, 1 on failure (possibly after partial output).
 * Never retain, modify, free or invalidate the storage. See text-output.md. */
int32_t astra_host_text_write(int32_t stream, const unsigned char *data, int32_t byte_length, int32_t newline);

#endif
