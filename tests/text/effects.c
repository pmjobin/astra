// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
static int position;
static int mismatch;

int trace(int step) {
	static const int expected[] = {1, 2, 6, 4, 3, 5, 3};
	if (position >= 7 || expected[position] != step) {
		mismatch = 1;
	}
	position++;
	return step;
}

int input(void) {
	return 2;
}

int verdict(void) {
	return position == 7 && !mismatch ? 0 : 90;
}
