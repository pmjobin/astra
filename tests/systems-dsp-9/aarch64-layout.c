/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Independent Clang target-layout witness; this object is never executed. */
_Static_assert(__SIZEOF_INT__ == 4, "AArch64 int width");
_Static_assert(__SIZEOF_POINTER__ == 8, "AArch64 LP64 pointer width");
_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "selected target endianness");
struct pair {
	unsigned first;
	unsigned second;
};
_Static_assert(sizeof(struct pair) == 8, "flat record stride");
_Static_assert(__builtin_offsetof(struct pair, second) == 4, "flat record offset");
_Static_assert(_Alignof(struct pair) == 4, "flat record alignment");
int c_identity(int value) {
	return value;
}
