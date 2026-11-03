// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only GNU host initializer: establish and verify the requested ambient
// numeric locale before an otherwise unchanged public Astra entry executes.
#include <assert.h>
#include <locale.h>
#include <stdlib.h>
#include <string.h>

__attribute__((constructor)) static void establish_numeric_locale(void) {
	const char *requested = getenv("ASTRA_TEST_NUMERIC_LOCALE");
	if (!requested) return;
	assert(!strcmp(requested, "C") || !strcmp(requested, "fr_CA.utf8"));
	assert(setlocale(LC_NUMERIC, requested));
	assert(!strcmp(localeconv()->decimal_point, !strcmp(requested, "C") ? "." : ","));
}
