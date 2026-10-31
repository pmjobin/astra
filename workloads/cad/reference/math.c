// Exact scalar adapter functions from CAD f415381 native/adapter.c.
// Image and Buffer bookkeeping are omitted from this numerical-foundation target.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <math.h>
#include <string.h>
#include <float.h>

_Static_assert(sizeof(double) == 8 && DBL_MANT_DIG == 53 && DBL_MAX_EXP == 1024, "C binary64 required");

void cad_fail(int32_t code, double value) {
	fprintf(stderr, "astra-cad: failure %d (value %.17g)\n", code, value);
	exit(2);
}
double cad_exp(double x) { return exp(x); }
double cad_log(double x) { return log(x); }
double cad_sqrt(double x) { return sqrt(x); }
double cad_pow(double x, double y) { return pow(x, y); }
double cad_nextafter(double x, double toward) { return nextafter(x, toward); }
int32_t cad_same_bits(double a, double b) { return memcmp(&a, &b, sizeof(a)) == 0; }
double cad_number(int32_t x) { return x; }
int32_t cad_integer(double x) {
	if (!isfinite(x) || x < INT32_MIN || x > INT32_MAX) { cad_fail(1, x); }
	return (int32_t)x;
}
