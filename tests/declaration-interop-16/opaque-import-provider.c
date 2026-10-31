/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "opaque-import-provider.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef struct {
	int32_t domain, code;
} Error;
typedef struct {
	int32_t seed;
} CProvider;
static unsigned c_retired, g_retired;
int32_t unitc16_create(int32_t seed, CProvider **result, Error *error) {
	assert(result && error);
	error->domain = error->code = 0;
	*result = calloc(1, sizeof **result);
	assert(*result);
	(*result)->seed = seed;
	return 0;
}
int32_t unitc16_sum(CProvider *self, int32_t input, int32_t *result, Error *error) {
	assert(self && result && error);
	error->domain = error->code = 0;
	*result = 0;
	if (input < 0) {
		error->domain = 16;
		error->code = -1600;
		return -1600;
	}
	*result = self->seed + input;
	return 0;
}
int32_t unitc16_destroy(CProvider **owner, Error *error) {
	assert(owner && error);
	error->domain = error->code = 0;
	if (*owner) {
		free(*owner);
		*owner = NULL;
		++c_retired;
	}
	return 0;
}
struct _UnitProvider16 {
	GObject parent;
	gint seed;
};
G_DEFINE_TYPE(UnitProvider16, unit_provider16, G_TYPE_OBJECT)
static void finalize(GObject *object) {
	++g_retired;
	G_OBJECT_CLASS(unit_provider16_parent_class)->finalize(object);
}
static void unit_provider16_class_init(UnitProvider16Class *klass) {
	G_OBJECT_CLASS(klass)->finalize = finalize;
}
static void unit_provider16_init(UnitProvider16 *self) {
	self->seed = 0;
}
UnitProvider16 *unit_provider16_new(gint seed, GError **error) {
	assert(error && !*error);
	UnitProvider16 *result = g_object_new(unit_provider16_get_type(), NULL);
	result->seed = seed;
	return result;
}
gboolean unit_provider16_try_sum(UnitProvider16 *self, gint input, gint *result, GError **error) {
	assert(UNIT_IS_PROVIDER16(self) && result && error && !*error);
	*result = 0;
	if (input < 0) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "negative input");
		return FALSE;
	}
	*result = self->seed + input;
	return TRUE;
}
extern int32_t opaque_import16_run(void);
int main(void) {
	assert(opaque_import16_run() == 0 && c_retired == 1 && g_retired == 1);
	puts("PASS opaque C/GObject imported declarations and native consumer ownership");
	return 0;
}
