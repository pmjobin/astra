/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Isolate installed GLib's process-lifetime quark-table growth from Astra. */
#include <assert.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
	assert(argc == 2);
	char *end;
	unsigned long count = strtoul(argv[1], &end, 10);
	assert(*end == '\0' && count > 0 && count <= 4096);
	GQuark first = g_quark_from_static_string("m17-quark-growth-anchor");
	GQuark last = first;
	for (unsigned long i = 0; i < count; ++i) {
		char *text = g_strdup_printf("m17-quark-growth-%lu", i);
		last = g_quark_from_string(text);
		assert(last == first + i + 1 && strcmp(g_quark_to_string(last), text) == 0);
		g_free(text);
	}
	printf("quark growth: first=%u inserted=%lu last=%u\n", first, count, last);
	return 0;
}
