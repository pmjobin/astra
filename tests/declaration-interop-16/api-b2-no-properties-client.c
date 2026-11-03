/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <glib-object.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
typedef struct Worker Worker;

typedef struct {
	int32_t domain, code;
} Error;

extern int32_t propertyless16_create(Worker **, Error *);
extern int32_t propertyless16_apply(Worker *, int64_t, double, bool, int64_t *, Error *);
extern uint32_t propertyless16_release(Worker *);
extern GObject *propertyless16_worker_as_gobject(Worker *, GError **);

int main(void) {
	Worker *root = NULL;
	Error error = {0};
	assert(propertyless16_create(&root, &error) == 0 && root);
	int64_t output = 0;
	assert(propertyless16_apply(root, INT64_C(5000000000), 2.0, true, &output, &error) == 0 && output == INT64_C(-5000000002));
	GError *gerror = NULL;
	GObject *object = propertyless16_worker_as_gobject(root, &gerror);
	assert(object && !gerror);
	guint count = 99;
	GParamSpec **properties = g_object_class_list_properties(G_OBJECT_GET_CLASS(object), &count);
	assert(count == 0);
	g_free(properties);
	propertyless16_release(root);
	g_object_unref(object);
	puts("PASS API B2 no-property class with substituted i64/f64/bool signature");
	return 0;
}
