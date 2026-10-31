/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
.text
.globl _start
.type _start,@function
_start:
	call numerical_kernel
	test %eax,%eax
	jne .Lfailed
	mov $1,%eax
	mov $1,%edi
	lea .Lmessage(%rip),%rsi
	mov $.Llength,%edx
	syscall
	xor %edi,%edi
	jmp .Lexit
.Lfailed:
	mov %eax,%edi
.Lexit:
	mov $60,%eax
	syscall
.size _start,.-_start
.section .rodata
.Lmessage:
	.ascii "numerics-no-libc\n"
.set .Llength,.-.Lmessage
.section .note.GNU-stack,"",@progbits
