/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdlib.h>
static int live, metrics, metric_drops;

int report_event(int stage, int value) {
	(void)value;
	if (stage == 1) {
		++live;
		++metrics;
	} else if (stage == 2) {
		--live;
		--metrics;
		++metric_drops;
	} else if (stage == 3)
		++live;
	else if (stage == 4)
		--live;
	else
		abort();
	if (live < 0 || metrics < 0 || metric_drops > 1) abort();
	return 0;
}

int report_live(void) {
	return live;
}

int report_metric_drops(void) {
	return metric_drops;
}
