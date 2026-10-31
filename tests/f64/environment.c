// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <fenv.h>
#include <xmmintrin.h>

int main(void) {
	assert(fegetround() == FE_TONEAREST);
	unsigned int mode = _mm_getcsr();
	assert((mode & 0x6000U) == 0 && (mode & 0x8040U) == 0);
	assert((mode & 0x1f80U) == 0x1f80U);
	return 0;
}
