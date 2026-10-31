/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Explicit Multiboot-1 address header and PC startup, not application logic. */
.section .multiboot,"a"
.balign 4
.long 0x1badb002
.long 0x00010003
.long -(0x1badb002 + 0x00010003)
.long __image_start
.long __image_start
.long __load_end
.long __bss_end
.long _start32

.section .text.boot,"ax"
.code32
.global _start32
_start32:
	cli
	cld
	cmpl $0x2badb002, %eax
	jne boot_invalid
	/* Poison first: the qualification can detect omitted explicit init. */
	movl $__bss_start, %edi
	movl $__bss_end, %ecx
	subl %edi, %ecx
	movb $0xa5, %al
	rep stosb
#ifndef ASTRA_TEST_SKIP_BSS_INIT
	movl $__bss_start, %edi
	movl $__bss_end, %ecx
	subl %edi, %ecx
	xorl %eax, %eax
	rep stosb
#endif
	movl $__data_start, %edi
	movl $__data_end, %ecx
	subl %edi, %ecx
	movb $0xa5, %al
	rep stosb
#ifndef ASTRA_TEST_SKIP_DATA_INIT
	movl $__data_start, %edi
	movl $__data_load, %esi
	movl $__data_end, %ecx
	subl %edi, %ecx
	rep movsb
#endif
	movl $boot_stack_top, %esp
	movl $0x51a7cafe, stack_guard
	/* Four 512-entry page directories identity-map the first four GiB. */
	movl $page_directories, %edi
	movl $0x83, %eax
	movl $2048, %ecx
1:
	movl %eax, (%edi)
	movl $0, 4(%edi)
	addl $0x200000, %eax
	addl $8, %edi
	loop 1b
	movl $page_directories, %eax
	orl $3, %eax
	movl $page_directory_pointer, %edi
	movl $4, %ecx
2:
	movl %eax, (%edi)
	addl $4096, %eax
	addl $8, %edi
	loop 2b
	movl $page_directory_pointer, %eax
	orl $3, %eax
	movl %eax, page_map
	movl $page_map, %eax
	movl %eax, %cr3
	movl %cr4, %eax
	orl $0x620, %eax
	movl %eax, %cr4
	movl $0xc0000080, %ecx
	rdmsr
	orl $0x100, %eax
	wrmsr
	lgdt gdt_pointer
	movl %cr0, %eax
	andl $0xfffffff3, %eax
	orl $0x80000003, %eax
	movl %eax, %cr0
	ljmpl $8, $entry64
boot_invalid:
	movw $0x501, %dx
	movb $0x7e, %al
	outb %al, %dx
3:
	hlt
	jmp 3b

.code64
entry64:
	movw $16, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	xorl %eax, %eax
	movw %ax, %fs
	movw %ax, %gs
	movq $boot_stack_top, %rsp
	xorq %rbp, %rbp
	fninit
	ldmxcsr initial_mxcsr(%rip)
	/* 16550A, 115200 baud, 8N1; no external host device or network. */
	movw $0x3f9, %dx
	xorl %eax, %eax
	outb %al, %dx
	movw $0x3fb, %dx
	movb $0x80, %al
	outb %al, %dx
	movw $0x3f8, %dx
	movb $1, %al
	outb %al, %dx
	movw $0x3f9, %dx
	xorl %eax, %eax
	outb %al, %dx
	movw $0x3fb, %dx
	movb $3, %al
	outb %al, %dx
	movw $0x3fa, %dx
	movb $0xc7, %al
	outb %al, %dx
	movw $0x3fc, %dx
	movb $0x0b, %al
	outb %al, %dx
#ifdef ASTRA_PC_EDU
	/* Explicit EDU at bus 0, slot 4: one MiB MMIO BAR and memory decoding. */
	movw $0xcf8, %dx
	movl $0x80002000, %eax
	outl %eax, %dx
	movw $0xcfc, %dx
	inl %dx, %eax
	cmpl $0x11e81234, %eax
	jne guest_invalid
	movw $0xcf8, %dx
	movl $0x80002010, %eax
	outl %eax, %dx
	movw $0xcfc, %dx
	movl $0xf0000000, %eax
	outl %eax, %dx
	movw $0xcf8, %dx
	movl $0x80002004, %eax
	outl %eax, %dx
	movw $0xcfc, %dx
	movl $2, %eax
	outl %eax, %dx
#endif
	/* Core fatal-memory/arithmetic error channel; hardware IRQs stay masked. */
	leaq trap_idt(%rip), %rdi
	.macro install_vector number, handler
	movq $\handler, %rax
	movw %ax, (16*\number)(%rdi)
	movw $8, (16*\number+2)(%rdi)
	movw $0x8e00, (16*\number+4)(%rdi)
	shrq $16, %rax
	movw %ax, (16*\number+6)(%rdi)
	shrq $16, %rax
	movl %eax, (16*\number+8)(%rdi)
	movl $0, (16*\number+12)(%rdi)
	.endm
	install_vector 6, fault6_entry
	install_vector 13, fault13_entry
	install_vector 14, fault14_entry
#ifdef ASTRA_PC_TRAP
	/* Optional source-defined breakpoint handler and real exception return. */
	install_vector 3, trap3_entry
#endif
	lidt trap_idt_pointer(%rip)
	xorl %r12d, %r12d
console_next:
	movl %r12d, %edi
	movl initialized_probe(%rip), %esi
	movl zero_probe(%rip), %edx
	call astra_entry
	testl %eax, %eax
	jz console_complete
	call uart_putc
	incl %r12d
	cmpl $256, %r12d
	jb console_next
	jmp guest_invalid
console_complete:
	cmpl $0x51a7cafe, stack_guard(%rip)
	jne guest_invalid
	movb $16, %al
	jmp guest_exit
guest_invalid:
	movb $0x7e, %al
guest_exit:
	movw $0x501, %dx
	outb %al, %dx
4:
	hlt
	jmp 4b

/* Byte serialization only; every byte is returned by compiled Astra. */
uart_putc:
	movb %al, %r8b
	movw $0x3fd, %dx
5:
	inb %dx, %al
	testb $0x20, %al
	jz 5b
	movw $0x3f8, %dx
	movb %r8b, %al
	outb %al, %dx
	ret

/* Fatal exceptions never resume an invalid instruction or unwind an owner.
 * The explicit panic channel is a core startup service, with no libc call. */
fault6_entry:
	movl $6, %r13d
	jmp fault_panic
fault13_entry:
	movl $13, %r13d
	jmp fault_panic
fault14_entry:
	movl $14, %r13d
fault_panic:
	cli
	cld
	movq $boot_stack_top, %rsp
	leaq panic_prefix(%rip), %rsi
6:
	lodsb
	testb %al, %al
	jz 7f
	call uart_putc
	jmp 6b
7:
	movl %r13d, %eax
	shrl $4, %eax
	call panic_hex
	movl %r13d, %eax
	call panic_hex
	movb $10, %al
	call uart_putc
	jmp guest_invalid
panic_hex:
	andl $15, %eax
	addl $48, %eax
	cmpl $57, %eax
	jbe 8f
	addl $39, %eax
8:
	jmp uart_putc

#ifdef ASTRA_PC_TRAP
/* This is an actual vector entry, distinct from the ordinary C callable.
 * Preserve general and x87/SSE state, replace only EAX with the source result,
 * and return with IRETQ. There is no hardware IRQ/nesting support claim. */
trap3_entry:
	pushq %rax
	pushq %rcx
	pushq %rdx
	pushq %rbx
	pushq %rbp
	pushq %rsi
	pushq %rdi
	pushq %r8
	pushq %r9
	pushq %r10
	pushq %r11
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rsp, %r12
	subq $528, %rsp
	andq $-16, %rsp
	fxsave64 (%rsp)
	cld
	movl $3, %edi
	movl 112(%r12), %esi
	call astra_trap_handler
	movl %eax, 112(%r12)
	fxrstor64 (%rsp)
	movq %r12, %rsp
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %r11
	popq %r10
	popq %r9
	popq %r8
	popq %rdi
	popq %rsi
	popq %rbp
	popq %rbx
	popq %rdx
	popq %rcx
	popq %rax
	iretq
#endif

.section .rodata.boot,"a"
.balign 8
gdt:
	.quad 0
	.quad 0x00af9a000000ffff
	.quad 0x00cf92000000ffff
gdt_pointer:
	.word . - gdt - 1
	.long gdt
initial_mxcsr:
	.long 0x1f80
trap_idt_pointer:
	.word 4095
	.quad trap_idt
panic_prefix:
	.asciz "PANIC:"

.section .data.boot,"aw"
initialized_probe:
	.long 0x13579bdf

.section .bss.boot,"aw",@nobits
.balign 4096
page_map:
	.skip 4096
page_directory_pointer:
	.skip 4096
page_directories:
	.skip 16384
zero_probe:
	.skip 4
.balign 16
trap_idt:
	.skip 4096
stack_guard:
	.skip 4
.balign 16
boot_stack:
	.skip 65536
boot_stack_top:

.section .note.GNU-stack,"",@progbits
