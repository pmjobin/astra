/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start32)
SECTIONS
{
	. = 0x100000;
	__image_start = .;
	.multiboot : { KEEP(*(.multiboot)) }
	.text : ALIGN(16) { *(.text.boot) *(.text .text.*) }
	.rodata : ALIGN(16) { *(.rodata .rodata.*) }
	__data_load = ALIGN(., 16);
	.data 0x200000 : AT(__data_load)
	{
		__data_start = .;
		*(.data .data.*)
		__data_end = .;
	}
	__load_end = __data_load + SIZEOF(.data);
	.bss (NOLOAD) : ALIGN(4096)
	{
		__bss_start = .;
		*(.bss .bss.* COMMON)
		__bss_end = .;
	}
	/DISCARD/ : { *(.eh_frame .eh_frame.* .comment .note*) }
	ASSERT(__load_end < 0x200000, "ROM image overlaps runtime DATA")
	ASSERT(__bss_end < 0x300000, "boot RAM budget exceeded")
	ASSERT(SIZEOF(.multiboot) == 32, "missing exact Multiboot address header")
}
