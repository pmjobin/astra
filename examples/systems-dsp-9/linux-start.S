/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Explicit Linux x86-64 entry shim. Astra supplies the complete algorithm. */
	.text
	.globl _start
	.type _start,@function
_start:
	xor %ebp,%ebp
	and $-16,%rsp
	call astra_entry
	mov %eax,%edi
	mov $60,%eax
	syscall
	ud2
	.size _start,.-_start
	.section .note.GNU-stack,"",@progbits
