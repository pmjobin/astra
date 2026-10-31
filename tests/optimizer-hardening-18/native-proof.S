/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
.text
.macro begin name
.globl \name
.type \name,@function
\name:
.endm
.macro end name
.size \name,.-\name
.endm
begin read32
	movl (%rdi),%eax
	ret
end read32
begin write32
	movl %esi,(%rdi)
	ret
end write32
begin spill32
	movq %rdi,-8(%rsp)
	movq -8(%rsp),%rax
	movl (%rax),%eax
	ret
end spill32
begin frame32
	pushq %rbp
	movq %rsp,%rbp
	subq $16,%rsp
	movq %rdi,-8(%rbp)
	movq -8(%rbp),%rax
	movl (%rax),%eax
	addq $16,%rsp
	popq %rbp
	ret
end frame32
begin pure64
	addsd %xmm1,%xmm0
	ret
end pure64
begin escape
	movq %rdi,%rax
	ret
end escape
begin capture
	movq %rdi,foreign_storage(%rip)
	ret
end capture
begin self_capture
	movq %rdi,(%rdi)
	ret
end self_capture
begin compare_pointer
	testq %rdi,%rdi
	ret
end compare_pointer
begin wide_read
	movq (%rdi),%rax
	ret
end wide_read
begin clobber_saved
	movq %rdi,%rbx
	ret
end clobber_saved
begin partial_address
	movb %dil,%al
	ret
end partial_address
begin incoming_stack
	movq (%rsp),%rax
	ret
end incoming_stack
begin atomic
	lock addl $1,(%rdi)
	ret
end atomic
begin syscall_leaf
	syscall
	ret
end syscall_leaf
begin call_leaf
	call foreign_function
	ret
end call_leaf
begin guarded_read32
	cmpq $0,%rdi
	jne 1f
	ud2
1:
	movl (%rdi),%eax
	ret
end guarded_read32
begin guarded_tail32
	testq %rdi,%rdi
	je 1f
	movl (%rdi),%eax
	ret
1:
	ud2
end guarded_tail32
begin guarded_unused
	testq %rdi,%rdi
	je 1f
	xorl %eax,%eax
	ret
1:
	ud2
end guarded_unused
begin false_guard
	testq %rdi,%rdi
	je 1f
	xorl %eax,%eax
	ret
1:
	movq %rdi,(%rdi)
	ret
end false_guard
begin wrapper32
	pushq %rax
	call read32
	popq %rcx
	ret
end wrapper32
begin tail32
	jmp read32@PLT
end tail32
begin wrapper_write32
	pushq %rax
	call write32
	popq %rcx
	ret
end wrapper_write32
begin recursive32
	jmp recursive32@PLT
end recursive32
begin conflicting_prefixes
	.byte 0xf2,0x66,0x0f,0x10,0x07
	ret
end conflicting_prefixes
// Emit a real linker relocation even for a symbol defined in this object.
.macro conditional_jump opcode, target
	.byte 0x0f, \opcode
	.long 0
	.reloc .-4, R_X86_64_PLT32, \target-4
.endm
begin conditional32
	testb $1,%sil
	conditional_jump 0x85,read32
	movl (%rdi),%eax
	ret
end conditional32
begin conditional_null32
	testq %rdi,%rdi
	conditional_jump 0x85,read32
	ud2
end conditional_null32
begin conditional_write32
	testb $1,%dl
	conditional_jump 0x85,write32
	ret
end conditional_write32
begin conditional_pointer_bits
	testq $1,%rdi
	conditional_jump 0x85,read32
	movl (%rdi),%eax
	ret
end conditional_pointer_bits
begin conditional_false_null
	testq %rdi,%rdi
	conditional_jump 0x84,read32
	ud2
end conditional_false_null
begin conditional_missing_trap
	testq %rdi,%rdi
	conditional_jump 0x85,read32
	xorl %eax,%eax
	ret
end conditional_missing_trap
begin conditional_stack32
	pushq %rbx
	testb $1,%sil
	conditional_jump 0x85,read32
	popq %rbx
	movl (%rdi),%eax
	ret
end conditional_stack32
.section .text.comdat,"axG",@progbits,comdat_read32,comdat
begin comdat_read32
	movl (%rdi),%eax
	ret
end comdat_read32
.section .note.GNU-stack,"",@progbits
