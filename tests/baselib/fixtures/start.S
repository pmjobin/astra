/* Linux x86-64 test entry: no CRT/libc, allocator or general Astra runtime. */
.text
.globl _start
_start:
	call main
	mov %eax, %edi
	mov $60, %eax
	syscall
.section .note.GNU-stack,"",@progbits
