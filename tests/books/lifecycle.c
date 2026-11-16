#include <stdint.h>

static int retired;
static int total;
static int trace;

void note_drop(int value) {
	++retired;
	total += value;
}

int drop_count(void) {
	return retired;
}

int drop_sum(void) {
	return total;
}

int tick(int value) {
	trace = trace * 10 + value;
	return value;
}

int tick_trace(void) {
	return trace;
}
