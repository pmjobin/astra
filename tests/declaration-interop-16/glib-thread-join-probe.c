/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <glib.h>
static gpointer worker(gpointer data) {
	return data;
}
int main(void) {
	GThread *thread = g_thread_new("probe", worker, NULL);
	g_thread_join(thread);
	return 0;
}
