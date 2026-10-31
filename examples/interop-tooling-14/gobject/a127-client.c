/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "a127-report.h"
#include <stdint.h>
#include <stdio.h>
extern int32_t a127_stats(int32_t);
extern int32_t a127_report_byte(int32_t, int32_t);
#define CHECK(test) do { if (!(test)) { printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
int main(void) {
	GError *error = NULL; Astra127Diagnostic *object = astra127_diagnostic_new(0, &error); CHECK(object && !error);
	gchar *first = astra127_diagnostic_report(object, 0, &error); CHECK(first && !error && g_strcmp0(first, "info[0]: ready 🖤") == 0);
	g_object_set(object, "value", 1, NULL);
	gchar *second = astra127_diagnostic_report(object, 0, &error); CHECK(second && !error && g_strcmp0(second, "warning[1]: retry café") == 0);
	CHECK(g_strcmp0(first, "info[0]: ready 🖤") == 0 && first != second);
	CHECK(astra127_diagnostic_report(object, 99, &error) == NULL && error && error->code == 6); g_clear_error(&error);
	CHECK(a127_report_byte(0, 999) == -7 && a127_stats(4) == 0);
	g_object_set(object, "value", 2, NULL);
	for (int i = 0; i < 64; ++i) {
		gchar *text = astra127_diagnostic_report(object, 0, &error);
		CHECK(text && !error && g_strcmp0(text, "error[2]: invalid packet") == 0 && a127_stats(4) == 0); g_free(text);
	}
	g_free(first); g_free(second); CHECK(a127_stats(5) > 1000);
	g_object_run_dispose(G_OBJECT(object)); CHECK(astra127_diagnostic_report(object, 0, &error) == NULL && error && error->code == 3); g_clear_error(&error);
	g_object_unref(object); CHECK(a127_stats(0) == 1 && a127_stats(1) == 1 && a127_stats(2) == 2 && a127_stats(3) == 2 && a127_stats(4) == 0);
	puts("PASS A127 C: Astra-owned UTF8 native-error mapping copied-transfer-full independent-storage all-text-retired native-destroyed=1");
	return 0;
}
