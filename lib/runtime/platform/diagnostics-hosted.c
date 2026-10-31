/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "diagnostics.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#if !defined(__x86_64__) || !defined(__linux__)
#error "Astra hosted diagnostics require qualified TEXT-IO x86-64 Linux"
#endif

static int astra_diag_shape(const unsigned char *bytes, int32_t length) {
	return length >= 0 && (length == 0 || bytes != NULL);
}

static int astra_diag_text(FILE *stream, const unsigned char *bytes, int32_t length) {
	static const unsigned char hex[] = "0123456789ABCDEF";
	if (fputc('"', stream) == EOF) {
		return 0;
	}
	for (int32_t i = 0; i < length; i++) {
		unsigned char value = bytes[i];
		const char *escape = NULL;
		switch (value) {
		case '"':
			escape = "\\\"";
			break;
		case '\\':
			escape = "\\\\";
			break;
		case '\n':
			escape = "\\n";
			break;
		case '\r':
			escape = "\\r";
			break;
		case '\t':
			escape = "\\t";
			break;
		case 0:
			escape = "\\0";
			break;
		default:
			break;
		}
		if (escape != NULL) {
			if (fwrite(escape, 1, 2, stream) != 2) {
				return 0;
			}
		} else if (value < 32 || value == 127) {
			unsigned char encoded[] = {'\\', 'u', '0', '0', hex[value >> 4], hex[value & 15]};
			if (fwrite(encoded, 1, sizeof(encoded), stream) != sizeof(encoded)) {
				return 0;
			}
		} else if (fputc(value, stream) == EOF) {
			return 0;
		}
	}
	return fwrite("\"\n", 1, 2, stream) == 2;
}

/* Private renderer: tests can include this translation unit to qualify its
 * bounded reads without replacing the production nonreturning contract. */
static int astra_diag_render(FILE *stream, const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length, const unsigned char *message, int32_t message_length) {
	if (!astra_diag_shape(file, file_length) || !astra_diag_shape(expression, expression_length) || !astra_diag_shape(message, message_length)) {
		static const char invalid[] = "Astra assertion failed: invalid diagnostic text view\n";
		return fwrite(invalid, 1, sizeof(invalid) - 1, stream) == sizeof(invalid) - 1;
	}
	static const char first[] = "Astra assertion failed\n  file: ";
	if (fwrite(first, 1, sizeof(first) - 1, stream) != sizeof(first) - 1 || !astra_diag_text(stream, file, file_length)) {
		return 0;
	}
	if (fprintf(stream, "  line: %" PRId32 "\n  expression: ", line) < 0 || !astra_diag_text(stream, expression, expression_length)) {
		return 0;
	}
	static const char last[] = "  message: ";
	return fwrite(last, 1, sizeof(last) - 1, stream) == sizeof(last) - 1 && astra_diag_text(stream, message, message_length);
}

_Noreturn void astra_diag_assert_fail_v0(const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length, const unsigned char *message, int32_t message_length) {
	(void)astra_diag_render(stderr, file, file_length, line, expression, expression_length, message, message_length);
	(void)fflush(stderr);
	abort();
}
