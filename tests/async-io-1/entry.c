/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Host entry only. All user tasks, catches and results are compiled Astra. */
extern int run_program(void);
int main(void) {
	return run_program();
}
