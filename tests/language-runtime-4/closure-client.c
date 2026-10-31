// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
extern int closure_client_apply(int bias, int input);
static int state;
int closure_client_event(int tag) {
	if (tag == 1 && state == 0)
		state = 1;
	else if (tag == 2 && state == 1)
		state = 2;
	else
		state = -100;
	return state;
}
int main(void) {
	int sum = 0;
	for (int i = 0; i < 200; ++i) {
		state = 0;
		int value = closure_client_apply(i, 7);
		if (state != 2 || value != i + 7) return 81;
		sum += value;
	}
	return printf("closure-sum=%d destroyed=200\n", sum) < 0;
}
