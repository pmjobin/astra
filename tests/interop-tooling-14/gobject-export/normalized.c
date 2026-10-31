// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "gobject14.h"
#include <stdio.h>
static int calls;
static int observed;
static int bad;
static void changed(Astra14Counter *self, gint value, gpointer context) {
	(void)context; gint actual = -1;
	if (!astra14_counter_try_get_value(self, &actual, NULL) || actual != value) ++bad;
	observed = value; ++calls;
}
#define CHECK(test) do { if (!(test)) { printf("FAIL normalized line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
int main(void) {
	GError *error = NULL;
	Astra14Counter *object = astra14_counter_new(40, &error); CHECK(object && !error);
	g_signal_connect(object, "changed", G_CALLBACK(changed), NULL);
	CHECK(astra14_counter_try_set_value(object, 40, &error) && !error && calls == 1 && observed == 41);
	CHECK(astra14_counter_try_set_value(object, 150, &error) && !error && calls == 2 && observed == 100);
	CHECK(astra14_counter_try_set_value(object, 200, &error) && !error && calls == 2);
	CHECK(astra14_counter_try_set_value(object, -5, &error) && !error && calls == 3 && observed == 0 && !bad);
	g_object_unref(object);
	puts("PASS normalized native property: signals reflect committed values and suppress unchanged state");
	return 0;
}
