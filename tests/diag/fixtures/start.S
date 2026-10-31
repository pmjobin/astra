/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
.text
.global _start
_start:
	xor %ebp, %ebp
	and $-16, %rsp
	call main
	mov %eax, %edi
	mov $60, %eax
	syscall
.section .note.GNU-stack,"",@progbits
