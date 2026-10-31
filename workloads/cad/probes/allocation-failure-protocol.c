// Application excerpt from aster-scale f415381 native/adapter.c:27-30.
// This provider implements only the original diagnostic/termination protocol.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void cad_fail(int32_t code, double value) {
	fprintf(stderr, "astra-cad: failure %d (value %.17g)\n", code, value);
	exit(2);
}
