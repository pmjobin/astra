/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "a127-report.h"
#include <stdint.h>
extern int32_t a127_report_byte(int32_t, int32_t);
extern int32_t a127_stats(int32_t);
gchar *astra127_diagnostic_report(Astra127Diagnostic *self, gint offset, GError **error) {
	gint severity = 0;
	if (!astra127_diagnostic_try_get_value(self, &severity, error)) return NULL;
	if (offset < -100 || offset > 100) {
		g_set_error_literal(error, astra127_diagnostic_error_quark(), 6, "severity offset outside explicit range");
		return NULL;
	}
	gint code = severity + offset;
	int32_t size = a127_report_byte(code, -1);
	if (size < 0) {
		g_set_error_literal(error, astra127_diagnostic_error_quark(), -size, "Astra rejected diagnostic severity");
		return NULL;
	}
	if (size > 1024 || a127_stats(4) != 0) g_error("unretired native text or unexpected extent");
	gchar *result = g_malloc((gsize)size + 1);
	for (int32_t i = 0; i < size; ++i) {
		int32_t byte = a127_report_byte(code, i);
		if (byte < 0 || byte > 255 || a127_stats(4) != 0) g_error("native text byte contract failed");
		result[i] = (gchar)(guchar)byte;
	}
	result[size] = '\0';
	if (!g_utf8_validate(result, size, NULL)) g_error("native report was not UTF-8");
	return result;
}
