// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#ifdef WITH_GOBJECT
#include <glib-object.h>
#endif

/* Independent declarations deliberately do not include the generated SDK. */
typedef struct Native Native;
typedef struct {
	int32_t domain, code;
} Error;
static unsigned destroyed, callbacks;
int32_t personality16_retired(void) {
	++destroyed;
	return 0;
}
extern int32_t personality16_native_run(void);
#ifndef NATIVE_ONLY
extern int32_t personality16_native_create(int32_t, bool, double, Native **, Error *);
extern int32_t personality16_native_get_count(Native *, int32_t *, Error *);
extern int32_t personality16_native_set_count(Native *, int32_t, Error *);
extern int32_t personality16_native_evaluate(Native *, double, double *, Error *);
extern int32_t personality16_native_visit(Native *, bool, bool (*)(void *, bool), void *, bool *, Error *);
extern uint32_t personality16_native_release(Native *);
static bool invert(void *data, bool input) {
	assert(data == &callbacks);
	++callbacks;
	return !input;
}
#ifdef WITH_GOBJECT
typedef struct _Personality16Facet Facet;
extern Facet *personality16_facet_as_gobject(Native *, GError **);
extern gboolean personality16_facet_try_evaluate(Facet *, gdouble, gdouble *, GError **);
extern gboolean personality16_facet_try_visit(Facet *, gboolean, gboolean (*)(gpointer, gboolean), gpointer, gboolean *, GError **);
static gboolean go_invert(gpointer data, gboolean input) {
	assert(data == &callbacks);
	++callbacks;
	return !input;
}
#endif
#endif
int main(void) {
	assert(personality16_native_run() == 0 && destroyed == 1);
#ifndef NATIVE_ONLY
	Native *root = NULL;
	Error error = {0, 0};
	int32_t count = 0;
	double value = 99;
	bool chosen = false;
	assert(personality16_native_create(7, true, 1.5, &root, &error) == 0 && root);
	assert(personality16_native_evaluate(root, 2, &value, &error) == 0 && value == 10);
	assert(personality16_native_evaluate(root, -1, &value, &error) == -1600 && value == 0 && error.domain == 16 && error.code == -1600);
	assert(personality16_native_visit(root, false, invert, &callbacks, &chosen, &error) == 0 && chosen && callbacks == 1);
	assert(personality16_native_set_count(root, 19, &error) == 0);
#ifdef WITH_GOBJECT
	GError *failure = NULL;
	Facet *facet = personality16_facet_as_gobject(root, &failure), *again = personality16_facet_as_gobject(root, &failure);
	assert(facet && again == facet && !failure);
	g_object_set(facet, "count", 23, NULL);
	assert(personality16_facet_try_evaluate(facet, 4, &value, &failure) && value == 29 && !failure);
	assert(!personality16_facet_try_evaluate(facet, -1, &value, &failure) && value == 0 && failure && failure->code == -1600);
	g_clear_error(&failure);
	gboolean go_chosen = FALSE;
	assert(personality16_facet_try_visit(facet, FALSE, go_invert, &callbacks, &go_chosen, &failure) && go_chosen && callbacks == 2);
#endif
#ifdef WITH_GOBJECT
	const int32_t expected_count = 23;
#else
	const int32_t expected_count = 19;
#endif
	assert(personality16_native_get_count(root, &count, &error) == 0 && count == expected_count);
	personality16_native_release(root);
#ifdef WITH_GOBJECT
	assert(destroyed == 1);
	g_object_unref(again);
	assert(destroyed == 1);
	g_object_unref(facet);
#endif
	assert(destroyed == 2);
#else
	assert(callbacks == 0);
#endif
	puts("PASS common declaration selected personalities and exact native lifetime");
	return 0;
}
