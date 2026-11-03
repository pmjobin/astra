// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
static int trace;
static int count;
int record_mark(int value) {
	trace = trace * 10 + value;
	count++;
	return value;
}
int record_trace(void) {
	return trace;
}
int record_count(void) {
	return count;
}
