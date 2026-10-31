/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "native-proof.h"
#include <llvm-c/Disassembler.h>
#include <llvm-c/Target.h>
#include <stdbool.h>
#include <string.h>
#include <limits.h>
#include <stdlib.h>

enum { UNKNOWN,
	   SCALAR,
	   FORMAL,
	   STACK,
	   SAVED };
typedef struct {
	unsigned kind, width;
	int64_t offset;
} Value;
typedef struct {
	int64_t offset;
	unsigned size;
	Value value;
} Slot;
typedef struct {
	Value reg[16], xmm[16];
	Slot slots[128];
	unsigned count;
	bool reads, writes, traps;
	size_t tail_trap;
	const unsigned *offsets, *sizes;
	int fields;
} State;
typedef struct {
	bool memory;
	unsigned reg, base;
	int64_t displacement;
} Operand;
typedef struct {
	const uint8_t *bytes;
	size_t length, at;
	unsigned rex;
	bool operand16;
} Decode;
typedef struct {
	size_t at;
	const char *symbol;
} CallSite;
typedef struct {
	size_t offset, size;
	unsigned index, calls;
	CallSite sites[128];
} Code;
typedef struct {
	const uint8_t *object;
	size_t length;
	const unsigned *offsets, *sizes;
	int fields;
	char *const *symbols, *const *contracts;
	int callees;
	unsigned *cached;
	bool *computed;
	const char *active[64];
	LLVMDisasmContextRef decoder;
} Proof;

static bool range(size_t length, uint64_t offset, uint64_t size) {
	return offset <= length && size <= length - offset;
}
static uint64_t number(const uint8_t *p, unsigned bytes) {
	uint64_t value = 0;
	for (unsigned i = 0; i < bytes; i++)
		value |= (uint64_t)p[i] << (8 * i);
	return value;
}
static bool elf_section(const uint8_t *data, size_t length, unsigned index, const uint8_t **section) {
	uint64_t table = number(data + 40, 8);
	unsigned count = (unsigned)number(data + 60, 2);
	if (index >= count || !range(length, table, (uint64_t)count * 64)) return false;
	*section = data + table + (uint64_t)index * 64;
	return true;
}
static const char *relocated_symbol(const uint8_t *data, size_t length, unsigned table_index, uint64_t index) {
	const uint8_t *table, *strings;
	if (!elf_section(data, length, table_index, &table) || number(table + 4, 4) != 2 || number(table + 56, 8) != 24) return NULL;
	uint64_t offset = number(table + 24, 8), size = number(table + 32, 8);
	if (size % 24 || index >= size / 24 || !range(length, offset, size) ||
	    !elf_section(data, length, (unsigned)number(table + 40, 4), &strings) || number(strings + 4, 4) != 3) return NULL;
	uint64_t str_offset = number(strings + 24, 8), str_size = number(strings + 32, 8), name = number(data + offset + index * 24, 4);
	if (!range(length, str_offset, str_size) || name >= str_size || !memchr(data + str_offset + name, 0, (size_t)(str_size - name))) return NULL;
	return (const char *)data + str_offset + name;
}
static bool function_code(const uint8_t *data, size_t length, const char *name, Code *code) {
	if (length < 64 || memcmp(data, "\177ELF\2\1\1", 7) ||
	    number(data + 16, 2) != 1 || number(data + 18, 2) != 62 ||
	    number(data + 20, 4) != 1 || number(data + 52, 2) != 64 ||
	    number(data + 58, 2) != 64) return false;
	unsigned count = (unsigned)number(data + 60, 2), matches = 0;
	uint64_t start = 0, extent = 0;
	for (unsigned s = 0; s < count; s++) {
		const uint8_t *table, *strings;
		if (!elf_section(data, length, s, &table)) return false;
		if (number(table + 4, 4) != 2) continue; /* SHT_SYMTAB */
		uint64_t offset = number(table + 24, 8), size = number(table + 32, 8);
		if (number(table + 56, 8) != 24 || size % 24 || !range(length, offset, size) ||
		    !elf_section(data, length, (unsigned)number(table + 40, 4), &strings) ||
		    number(strings + 4, 4) != 3) return false;
		uint64_t str_offset = number(strings + 24, 8), str_size = number(strings + 32, 8);
		if (!range(length, str_offset, str_size)) return false;
		for (uint64_t p = 0; p < size; p += 24) {
			const uint8_t *symbol = data + offset + p;
			uint64_t n = number(symbol, 4);
			if (n >= str_size || !memchr(data + str_offset + n, 0, (size_t)(str_size - n))) return false;
			if (strcmp((const char *)data + str_offset + n, name)) continue;
			const uint8_t *section;
			unsigned index = (unsigned)number(symbol + 6, 2);
			if (++matches != 1 || symbol[4] != 0x12 || /* strong STB_GLOBAL/STT_FUNC */
			    !elf_section(data, length, index, &section) || number(section + 4, 4) != 1 ||
			    number(section + 8, 8) != 6) return false; /* exact alloc/exec, no COMDAT group */
			start = number(symbol + 8, 8);
			extent = number(symbol + 16, 8);
			uint64_t section_offset = number(section + 24, 8), section_size = number(section + 32, 8);
			if (!extent || !range(length, section_offset, section_size) || !range((size_t)section_size, start, extent)) return false;
			code->offset = (size_t)(section_offset + start);
			code->size = (size_t)extent;
			code->index = index;
		}
	}
	if (matches != 1) return false;
	/* Relocations can change instruction operands after decoding. Never prove a
	 * byte range touched by one, and do not guess widths for unknown kinds. */
	for (unsigned s = 0; s < count; s++) {
		const uint8_t *section;
		if (!elf_section(data, length, s, &section)) return false;
		unsigned kind = (unsigned)number(section + 4, 4);
		if ((kind != 4 && kind != 9) || number(section + 44, 4) != code->index) continue;
		if (kind != 4 || number(section + 56, 8) != 24) return false;
		uint64_t offset = number(section + 24, 8), size = number(section + 32, 8);
		if (size % 24 || !range(length, offset, size)) return false;
		for (uint64_t p = 0; p < size; p += 24) {
			uint64_t at = number(data + offset + p, 8);
			unsigned relocation = (unsigned)number(data + offset + p + 8, 4), width;
			switch (relocation) {
			case 0:
				width = 0;
				break;
			case 1:
			case 24:
			case 25:
			case 27:
			case 28:
			case 29:
				width = 8;
				break;
			case 2:
			case 4:
			case 9:
			case 10:
			case 11:
			case 26:
			case 41:
			case 42:
				width = 4;
				break;
			case 12:
			case 13:
				width = 2;
				break;
			case 14:
			case 15:
				width = 1;
				break;
			default:
				return false;
			}
			if (width && at < start + extent && (at >= start || start - at < width)) {
				if ((relocation != 2 && relocation != 4) || at <= start || !range((size_t)extent, at - start, 4) ||
				    number(data + offset + p + 16, 8) != UINT64_MAX - 3 || code->calls == 128) return false;
				const char *target = relocated_symbol(data, length, (unsigned)number(section + 40, 4), number(data + offset + p + 8, 8) >> 32);
				if (!target) return false;
				for (unsigned c = 0; c < code->calls; c++)
					if (code->sites[c].at == at - start) return false;
				code->sites[code->calls++] = (CallSite){(size_t)(at - start), target};
			}
		}
	}
	return true;
}

static bool take(Decode *d, unsigned width, uint64_t *value) {
	if (!range(d->length, d->at, width)) return false;
	*value = number(d->bytes + d->at, width);
	d->at += width;
	return true;
}
static bool modrm(Decode *d, Operand *rm, unsigned *reg) {
	uint64_t raw;
	if (!take(d, 1, &raw)) return false;
	unsigned mode = (unsigned)raw >> 6, base = (unsigned)raw & 7;
	*reg = (((unsigned)raw >> 3) & 7) + ((d->rex & 4) ? 8 : 0);
	rm->memory = mode != 3;
	rm->displacement = 0;
	if (mode == 3) {
		rm->reg = base + ((d->rex & 1) ? 8 : 0);
		return true;
	}
	if (base == 4) {
		if (!take(d, 1, &raw) || (raw & 0x38) != 0x20 || (d->rex & 2)) return false; /* no index */
		base = (unsigned)raw & 7;
	}
	if (mode == 0 && base == 5) return false; /* RIP or absolute address */
	rm->base = base + ((d->rex & 1) ? 8 : 0);
	if (mode == 1) {
		if (!take(d, 1, &raw)) return false;
		rm->displacement = (int8_t)raw;
	}
	if (mode == 2) {
		if (!take(d, 4, &raw)) return false;
		rm->displacement = (int32_t)raw;
	}
	return true;
}
static bool scalar(Value value, unsigned width) {
	return value.kind == SCALAR && value.width >= width;
}
static Value scalar_value(unsigned width) {
	return (Value){SCALAR, width, 0};
}
static bool field(State *s, int64_t offset, unsigned width) {
	if (offset < 0) return false;
	for (int f = 0; f < s->fields; f++)
		if ((uint64_t)offset == s->offsets[f] && width == s->sizes[f]) return true;
	return false;
}
static bool private_address(State *s, int64_t at, unsigned size) {
	/* SysV's 128-byte red zone is private between calls. The call checker
	 * invalidates it; return addresses/incoming arguments are never private. */
	return s->reg[4].kind == STACK && at >= s->reg[4].offset - 128 && at < 0 && size <= (uint64_t)(-at);
}
static bool stack_store(State *s, int64_t at, unsigned width, Value value) {
	if (!private_address(s, at, width)) return false;
	for (unsigned i = 0; i < s->count;) {
		Slot slot = s->slots[i];
		if (at < slot.offset + slot.size && slot.offset < at + width)
			s->slots[i] = s->slots[--s->count];
		else
			i++;
	}
	if (s->count == 128) return false; /* optional proof budget; producer exports unknown */
	s->slots[s->count++] = (Slot){at, width, value};
	return true;
}
static bool load(State *s, Operand op, unsigned width, bool vector, Value *result) {
	if (!op.memory) {
		Value value = vector ? s->xmm[op.reg] : s->reg[op.reg];
		if (value.kind == SCALAR && !scalar(value, width)) return false;
		if (value.kind != SCALAR && (vector || width != 8)) return false;
		*result = value;
		return true;
	}
	Value base = s->reg[op.base];
	int64_t at = base.offset + op.displacement;
	if (base.kind == FORMAL && field(s, at, width)) {
		s->reads = true;
		*result = scalar_value(width);
		return true;
	}
	if (base.kind != STACK || !private_address(s, at, width)) return false;
	for (unsigned i = 0; i < s->count; i++) {
		Slot slot = s->slots[i];
		if (slot.offset != at || slot.size != width) continue;
		if ((slot.value.kind == SCALAR && !scalar(slot.value, width)) || (vector && !scalar(slot.value, width)) || (slot.value.kind != SCALAR && width != 8)) return false;
		*result = slot.value;
		return true;
	}
	return false;
}
static bool store(State *s, Operand op, unsigned width, bool vector, Value value) {
	if (!op.memory) {
		if (vector) {
			if (!scalar(value, width)) return false;
			s->xmm[op.reg] = scalar_value(width);
			return true;
		}
		if (op.reg == 4) return false; /* rsp changes have explicit rules */
		if (value.kind != SCALAR && width != 8) return false;
		if (width == 4 && value.kind == SCALAR)
			value.width = 8; /* zero extension */
		else if (value.kind == SCALAR)
			value.width = width;
		s->reg[op.reg] = value;
		return true;
	}
	Value base = s->reg[op.base];
	int64_t at = base.offset + op.displacement;
	if (base.kind == FORMAL && scalar(value, width) && field(s, at, width)) {
		s->writes = true;
		return true;
	}
	if (base.kind != STACK) return false;
	return stack_store(s, at, width, value);
}
static Operand reg_operand(unsigned reg) {
	return (Operand){false, reg, 0, 0};
}

static size_t instruction_length(LLVMDisasmContextRef decoder, const uint8_t *bytes, size_t size) {
	char assembly[256];
	return LLVMDisasmInstruction(decoder, (uint8_t *)bytes, size, 0, assembly, sizeof assembly);
}

/* A null refusal is an explicit terminal trap, not a pointer identity result.
 * Admit only zero checks immediately controlling a decoded UD2 terminal. The
 * nonnull path remains checked instruction by instruction; no nonnull fact or
 * memory(none) permission follows from this model. */
static size_t null_guard(State *s, LLVMDisasmContextRef decoder, const uint8_t *bytes,
                         size_t size, size_t absolute, size_t function_size) {
	size_t length = instruction_length(decoder, bytes, size);
	if (!length) return 0;
	Decode d = {bytes, length, 0, 0, false};
	uint64_t rex, opcode;
	if (!take(&d, 1, &rex) || rex < 0x48 || rex > 0x4f || !take(&d, 1, &opcode)) return 0;
	d.rex = (unsigned)rex;
	Operand rm;
	unsigned reg;
	if (!modrm(&d, &rm, &reg) || rm.memory || s->reg[rm.reg].kind != FORMAL) return 0;
	if (opcode == 0x85) {
		if (rm.reg != reg) return 0;
	} else if (opcode == 0x83 && reg == 7) {
		uint64_t immediate;
		if (!take(&d, 1, &immediate) || immediate != 0) return 0;
	} else
		return 0;
	if (d.at != length || !range(size, length, 2)) return 0;
	const uint8_t *branch = bytes + length;
	if (instruction_length(decoder, branch, size - length) != 2) return 0;
	if (branch[0] == 0x75 && branch[1] == 2 && range(size, length + 2, 2) &&
	    bytes[length + 2] == 0x0f && bytes[length + 3] == 0x0b &&
	    instruction_length(decoder, bytes + length + 2, size - length - 2) == 2) {
		s->traps = true;
		return length + 4;
	}
	if (branch[0] == 0x74 && branch[1] <= 127) {
		size_t at = length + 2 + branch[1];
		if (range(size, at, 2) && absolute + at + 2 == function_size && bytes[at] == 0x0f && bytes[at + 1] == 0x0b &&
		    instruction_length(decoder, bytes + at, size - at) == 2) {
			s->traps = true;
			s->tail_trap = absolute + at;
			return length + 2;
		}
	}
	return 0;
}

static unsigned prove_function(Proof *proof, const char *symbol, const unsigned *types, int types_length, unsigned result_type, unsigned depth);

static bool preserved(State *state) {
	static const unsigned registers[] = {3, 5, 12, 13, 14, 15};
	if (state->reg[4].kind != STACK || state->reg[4].offset != 0) return false;
	for (unsigned i = 0; i < sizeof registers / sizeof registers[0]; i++) {
		Value value = state->reg[registers[i]];
		if (value.kind != SAVED || value.offset != registers[i]) return false;
	}
	return true;
}
static bool type_valid(unsigned type) {
	return type == 1 || type == 2 || type == 4 || type == 8 || type == 16 || type == 17 || type == 32;
}

static bool call(State *state, Proof *proof, const Code *code, size_t relocation, bool tail,
                 unsigned result_type, unsigned depth) {
	const char *symbol = NULL;
	for (unsigned c = 0; c < code->calls; c++)
		if (code->sites[c].at == relocation) symbol = code->sites[c].symbol;
	if (!symbol) return false;
	int selected = -1;
	for (int c = 0; c < proof->callees; c++)
		if (!strcmp(symbol, proof->symbols[c])) {
			if (selected != -1) return false;
			selected = c;
		}
	if (selected == -1) return false;
	unsigned values[16], count = 0;
	const char *text = proof->contracts[selected];
	do {
		char *end;
		if (count == 16 || *text < '0' || *text > '9') return false;
		unsigned long value = strtoul(text, &end, 10);
		if (value > UINT_MAX || (*end && *end != ',')) return false;
		values[count++] = (unsigned)value;
		if (!*end) break;
		text = end + 1;
	} while (true);
	if (count < 2 || (values[0] & ~55U) || ((values[0] & 48) != 16 && (values[0] & 48) != 32) ||
	    !(values[1] == 0 || (type_valid(values[1]) && values[1] != 32))) return false;
	unsigned flags = values[0] & 7, returned = values[1], *parameters = values + 2;
	int parameter_count = (int)count - 2;
	for (int p = 0; p < parameter_count; p++)
		if (!type_valid(parameters[p])) return false;
	if (values[0] & 16) {
		if (!proof->computed[selected]) {
			proof->cached[selected] = prove_function(proof, symbol, parameters, parameter_count, returned, depth + 1);
			proof->computed[selected] = true;
		}
		unsigned checked = proof->cached[selected];
		if (!(checked & 8) || (flags & ~checked)) return false;
	}
	static const unsigned registers[] = {7, 6, 2, 1, 8, 9};
	unsigned integer = 0, vector = 0, pointers = 0;
	for (int p = 0; p < parameter_count; p++) {
		unsigned type = parameters[p];
		if (type == 16 || type == 17) {
			if (vector == 8 || !scalar(state->xmm[vector++], type == 16 ? 4 : 8)) return false;
		} else {
			if (integer == 6) return false;
			Value value = state->reg[registers[integer++]];
			if (type == 32) {
				if (++pointers != 1 || !(flags & 1) || value.kind != FORMAL || value.offset != 0) return false;
			} else if (!scalar(value, type))
				return false;
		}
	}
	if (!pointers && !(flags & 4)) return false;
	if (tail) {
		if (!preserved(state) || (result_type != 0 && result_type != returned)) return false;
	} else if (state->reg[4].kind != STACK || ((8 + state->reg[4].offset) & 15))
		return false;
	if (!(flags & 4)) state->reads = true;
	if (pointers && !(flags & 2)) state->writes = true;
	/* A callee owns its red zone. Only explicitly allocated caller frame slots
	 * survive. Every caller-saved register loses its old pointer provenance. */
	for (unsigned i = 0; i < state->count;) {
		if (state->slots[i].offset < state->reg[4].offset)
			state->slots[i] = state->slots[--state->count];
		else
			i++;
	}
	static const unsigned clobbered[] = {0, 1, 2, 6, 7, 8, 9, 10, 11};
	for (unsigned i = 0; i < sizeof clobbered / sizeof clobbered[0]; i++)
		state->reg[clobbered[i]] = (Value){UNKNOWN, 0, 0};
	for (unsigned i = 0; i < 16; i++)
		state->xmm[i] = (Value){UNKNOWN, 0, 0};
	if (returned == 16 || returned == 17)
		state->xmm[0] = scalar_value(returned == 16 ? 4 : 8);
	else if (returned)
		state->reg[0] = scalar_value(returned);
	return true;
}

/* A conditional direct tail call has two independently checked continuations.
 * The taken edge ends in the exact typed callee; the fallthrough retains the
 * original registers/stack. Only scalar tests, or a null refusal whose other
 * edge is an immediate terminal UD2, supply the predicate. Arbitrary branches,
 * pointer-bit tests, indirect targets and guessed flag provenance remain closed. */
static size_t conditional_tail(State *state, Proof *proof, const Code *code,
                               size_t at, unsigned result_type, unsigned depth, bool *returned) {
	const uint8_t *bytes = proof->object + code->offset + at;
	size_t available = code->size - at;
	size_t length = instruction_length(proof->decoder, bytes, available);
	if (!length) return 0;
	Decode d = {bytes, length, 0, 0, false};
	uint64_t opcode;
	if (!take(&d, 1, &opcode)) return 0;
	if (opcode >= 0x40 && opcode <= 0x4f) {
		d.rex = (unsigned)opcode;
		if (!take(&d, 1, &opcode)) return 0;
	}
	Operand rm;
	unsigned reg;
	if (!modrm(&d, &rm, &reg)) return 0;
	bool null_refusal = false;
	State fallthrough = *state;
	if (opcode == 0x85 && !rm.memory && rm.reg == reg) {
		Value value = fallthrough.reg[reg];
		if (value.kind == FORMAL && (d.rex & 8))
			null_refusal = true;
		else if (!scalar(value, d.rex & 8 ? 8 : 4))
			return 0;
	} else if ((opcode == 0xf6 || opcode == 0xf7) && reg == 0) {
		unsigned width = opcode == 0xf6 ? 1 : d.rex & 8 ? 8
		                                                : 4;
		if (width == 1 && !d.rex && !rm.memory && rm.reg >= 4) return 0;
		Value value;
		uint64_t immediate;
		if (!load(&fallthrough, rm, width, false, &value) || !scalar(value, width) || !take(&d, width == 1 ? 1 : 4, &immediate)) return 0;
	} else
		return 0;
	if (d.at != length || !range(available, length, 6)) return 0;
	const uint8_t *branch = bytes + length;
	if (instruction_length(proof->decoder, branch, available - length) != 6 || branch[0] != 0x0f ||
	    (branch[1] != 0x84 && branch[1] != 0x85)) return 0;
	size_t consumed = length + 6;
	if (null_refusal) {
		if (branch[1] != 0x85 || consumed + 2 != available || bytes[consumed] != 0x0f || bytes[consumed + 1] != 0x0b ||
		    instruction_length(proof->decoder, bytes + consumed, 2) != 2) return 0;
		fallthrough.traps = true;
		consumed += 2;
	}
	State taken = fallthrough;
	if (!call(&taken, proof, code, at + length + 2, true, result_type, depth)) return 0;
	fallthrough.reads |= taken.reads;
	fallthrough.writes |= taken.writes;
	fallthrough.traps |= taken.traps;
	*state = fallthrough;
	*returned = null_refusal;
	return consumed;
}

/* Ordinary accepted encodings deliberately form a small scalar language.
 * Calls and terminal conditional calls have separate typed checks. There are no
 * indirect branches, atomics, system operations, pointer comparisons,
 * integer division, FP policy changes, implicit memory operands or guessed
 * instruction effects. Unrecognized valid source simply gets no optional fact. */
static bool step(State *s, Decode *d, unsigned result_type, bool *returned) {
	uint64_t op;
	bool f2 = false, f3 = false;
	if (!take(d, 1, &op)) return false;
	if (op == 0xf2 || op == 0xf3) {
		f2 = op == 0xf2;
		f3 = op == 0xf3;
		if (!take(d, 1, &op)) return false;
	}
	if (op == 0x66) {
		d->operand16 = true;
		if (!take(d, 1, &op)) return false;
	}
	if (op >= 0x40 && op <= 0x4f) {
		d->rex = (unsigned)op;
		if (!take(d, 1, &op)) return false;
	}
	unsigned width = d->rex & 8 ? 8 : d->operand16 ? 2
	                                               : 4;
	if (op == 0x0f) {
		if (d->operand16 && (f2 || f3)) return false; /* conflicting mandatory SSE prefixes */
		if (!take(d, 1, &op)) return false;
		Operand rm;
		unsigned reg;
		if (!modrm(d, &rm, &reg)) return false;
		if (op == 0x1f && reg == 0 && !f2 && !f3) return true; /* nop, no memory access */
		if (d->rex & 8) return false;
		unsigned size = f2 ? 8 : f3 ? 4
		                            : 16;
		if ((op == 0x10 || op == 0x11 || op == 0x28 || op == 0x29) &&
		    (!(op == 0x28 || op == 0x29) || (!f2 && !f3))) {
			Operand src = (op & 1) ? reg_operand(reg) : rm, dst = (op & 1) ? rm : reg_operand(reg);
			Value value;
			return load(s, src, size, true, &value) && scalar(value, size) && store(s, dst, size, true, value);
		}
		if (((op == 0x57 && !f2 && !f3) || (op == 0xef && d->operand16 && !f2 && !f3)) && !rm.memory && rm.reg == reg) {
			s->xmm[reg] = scalar_value(16);
			return true;
		}
		if ((op == 0x58 || op == 0x59 || op == 0x5c || op == 0x5e) && (f2 || f3) && !d->operand16) {
			Value value;
			if (!scalar(s->xmm[reg], size) || !load(s, rm, size, true, &value) || !scalar(value, size)) return false;
			s->xmm[reg] = scalar_value(size);
			return true;
		}
		return false;
	}
	if (f2 || f3) return false;
	if (op == 0x90 && !d->rex && !d->operand16) return true;
	if (op == 0xc3 && !d->rex && !d->operand16) {
		static const unsigned preserved[] = {3, 5, 12, 13, 14, 15};
		if (s->reg[4].kind != STACK || s->reg[4].offset != 0) return false;
		for (unsigned i = 0; i < sizeof preserved / sizeof preserved[0]; i++) {
			Value value = s->reg[preserved[i]];
			if (value.kind != SAVED || value.offset != preserved[i]) return false;
		}
		if (result_type && !(result_type == 16 || result_type == 17 ? scalar(s->xmm[0], result_type == 16 ? 4 : 8) : scalar(s->reg[0], result_type))) return false;
		*returned = true;
		return true;
	}
	if (op >= 0x50 && op <= 0x5f && !d->operand16 && !(d->rex & 6)) {
		unsigned reg = ((unsigned)op & 7) + ((d->rex & 1) ? 8 : 0);
		if (reg == 4 || s->reg[4].kind != STACK) return false;
		if (op < 0x58) {
			s->reg[4].offset -= 8;
			return stack_store(s, s->reg[4].offset, 8, s->reg[reg]);
		}
		Value value;
		Operand mem = {true, 0, 4, 0};
		if (!load(s, mem, 8, false, &value)) return false;
		s->reg[reg] = value;
		s->reg[4].offset += 8;
		return s->reg[4].offset <= 0;
	}
	if (op >= 0xb8 && op <= 0xbf && !(d->rex & 6)) {
		unsigned reg = ((unsigned)op & 7) + ((d->rex & 1) ? 8 : 0);
		uint64_t immediate;
		return take(d, width, &immediate) && store(s, reg_operand(reg), width, false, scalar_value(width));
	}
	Operand rm;
	unsigned reg;
	if (!modrm(d, &rm, &reg)) return false;
	if (op == 0x89 || op == 0x8b || op == 0x88 || op == 0x8a) {
		if (op == 0x88 || op == 0x8a) {
			width = 1;
			if (!d->rex && (reg >= 4 || (!rm.memory && rm.reg >= 4))) return false;
		}
		Operand src = op == 0x89 || op == 0x88 ? reg_operand(reg) : rm;
		Operand dst = op == 0x89 || op == 0x88 ? rm : reg_operand(reg);
		Value value;
		if (!load(s, src, width, false, &value)) return false;
		/* mov rsp/rbp is only an exact private stack alias, never a pivot. */
		if (!dst.memory && dst.reg == 4) {
			if (width != 8 || value.kind != STACK || value.offset > 0 || value.offset < s->reg[4].offset) return false;
			s->reg[4] = value;
			return true;
		}
		return store(s, dst, width, false, value);
	}
	if (op == 0xc7 && reg == 0) {
		uint64_t immediate;
		return take(d, width == 2 ? 2 : 4, &immediate) && store(s, rm, width, false, scalar_value(width));
	}
	if (op == 0x8d && width == 8 && rm.memory && s->reg[rm.base].kind == STACK) {
		Value value = s->reg[rm.base];
		value.offset += rm.displacement;
		if (value.offset >= 0 || value.offset < s->reg[4].offset - 128) return false;
		return store(s, reg_operand(reg), width, false, value);
	}
	if (op == 0x81 || op == 0x83) {
		uint64_t raw;
		if (reg > 7 || !take(d, op == 0x83 ? 1 : width == 2 ? 2
		                                                    : 4,
		                     &raw)) return false;
		int64_t immediate = op == 0x83 ? (int8_t)raw : width == 2 ? (int16_t)raw
		                                                          : (int32_t)raw;
		if (!rm.memory && rm.reg == 4 && width == 8 && (reg == 0 || reg == 5)) {
			if (s->reg[4].kind != STACK || immediate < 0 || immediate > INT_MAX) return false;
			int64_t next = s->reg[4].offset + (reg == 0 ? immediate : -immediate);
			if (next > 0 || next < -INT_MAX) return false;
			s->reg[4].offset = next;
			return true;
		}
		Value value;
		if (!(reg == 0 || reg == 1 || reg == 4 || reg == 5 || reg == 6 || reg == 7) || !load(s, rm, width, false, &value) || !scalar(value, width)) return false;
		return reg == 7 || store(s, rm, width, false, scalar_value(width));
	}
	if (op == 0x31 || op == 0x33 || op == 0x01 || op == 0x03 || op == 0x29 || op == 0x2b ||
	    op == 0x21 || op == 0x23 || op == 0x09 || op == 0x0b || op == 0x39 || op == 0x3b || op == 0x85) {
		Operand src = op & 2 ? rm : reg_operand(reg), dst = op & 2 ? reg_operand(reg) : rm;
		if ((op == 0x31 || op == 0x33) && !rm.memory && rm.reg == reg) return store(s, dst, width, false, scalar_value(width));
		Value a, b;
		if (!load(s, src, width, false, &a) || !load(s, dst, width, false, &b) || !scalar(a, width) || !scalar(b, width)) return false;
		return op == 0x39 || op == 0x3b || op == 0x85 || store(s, dst, width, false, scalar_value(width));
	}
	return false;
}

static unsigned prove_function(Proof *proof, const char *symbol, const unsigned *types, int types_length, unsigned result_type, unsigned depth) {
	if (depth >= 64) return 0;
	for (unsigned d = 0; d < depth; d++)
		if (!strcmp(proof->active[d], symbol)) return 0;
	proof->active[depth] = symbol;
	Code code = {0};
	if (!function_code(proof->object, proof->length, symbol, &code)) return 0;
	State state = {0};
	state.tail_trap = SIZE_MAX;
	state.offsets = proof->offsets;
	state.sizes = proof->sizes;
	state.fields = proof->fields;
	state.reg[4] = (Value){STACK, 8, 0};
	static const unsigned saved[] = {3, 5, 12, 13, 14, 15};
	for (unsigned i = 0; i < sizeof saved / sizeof saved[0]; i++)
		state.reg[saved[i]] = (Value){SAVED, 8, saved[i]};
	static const unsigned arguments[] = {7, 6, 2, 1, 8, 9};
	unsigned integer = 0, vector = 0, pointers = 0;
	for (int i = 0; i < types_length; i++) {
		unsigned type = types[i];
		if (!type_valid(type)) return 0;
		if (type == 16 || type == 17) {
			if (vector == 8) return 0;
			state.xmm[vector++] = scalar_value(type == 16 ? 4 : 8);
		} else {
			if (integer == 6) return 0;
			unsigned reg = arguments[integer++];
			if (type == 32) {
				if (++pointers != 1) return 0;
				state.reg[reg] = (Value){FORMAL, 8, 0};
			} else
				state.reg[reg] = scalar_value(type);
		}
	}
	size_t at = 0;
	bool returned = false, valid = true;
	unsigned calls = 0;
	while (at < code.size && !returned) {
		const uint8_t *bytes = proof->object + code.offset + at;
		size_t conditional = conditional_tail(&state, proof, &code, at, result_type, depth, &returned);
		if (conditional) {
			calls++;
			at += conditional;
			continue;
		}
		size_t guarded = null_guard(&state, proof->decoder, bytes, code.size - at, at, code.size);
		if (guarded) {
			at += guarded;
			continue;
		}
		size_t length = instruction_length(proof->decoder, bytes, code.size - at);
		if (!length) {
			valid = false;
			break;
		}
		if (length == 5 && (bytes[0] == 0xe8 || bytes[0] == 0xe9)) {
			bool tail = bytes[0] == 0xe9;
			if (!call(&state, proof, &code, at + 1, tail, result_type, depth)) {
				valid = false;
				break;
			}
			calls++;
			returned = tail;
		} else {
			Decode instruction = {bytes, length, 0, 0, false};
			if (!step(&state, &instruction, result_type, &returned) || instruction.at != length) {
				valid = false;
				break;
			}
		}
		at += length;
	}
	if (!valid || !returned || calls != code.calls || (at != code.size && !(at == state.tail_trap && code.size - at == 2))) return 0;
	return 8 | (pointers ? 1 : 0) | (pointers && !state.writes ? 2 : 0) | (!state.reads && !state.writes && !state.traps ? 4 : 0);
}

unsigned astra_native_object_proof(const uint8_t *object, int object_length,
                                   const char *symbol, const unsigned *types, int types_length,
                                   unsigned result_type, const unsigned *offsets, int offsets_length,
                                   const unsigned *sizes, int sizes_length,
                                   char *const *callee_symbols, int callee_symbols_length,
                                   char *const *callee_contracts, int callee_contracts_length) {
	if (object_length < 0 || types_length < 0 || offsets_length < 0 || offsets_length != sizes_length ||
	    callee_symbols_length < 0 || callee_symbols_length != callee_contracts_length ||
	    !(result_type == 0 || (type_valid(result_type) && result_type != 32))) return 0;
	if (LLVMInitializeNativeTarget() || LLVMInitializeNativeDisassembler()) return 0;
	LLVMDisasmContextRef decoder = LLVMCreateDisasm("x86_64-pc-linux-gnu", NULL, 0, NULL, NULL);
	if (!decoder) return 0;
	Proof proof = {0};
	proof.object = object;
	proof.length = (size_t)object_length;
	proof.offsets = offsets;
	proof.sizes = sizes;
	proof.fields = offsets_length;
	proof.decoder = decoder;
	proof.symbols = callee_symbols;
	proof.contracts = callee_contracts;
	proof.callees = callee_symbols_length;
	proof.cached = calloc((size_t)callee_symbols_length, sizeof *proof.cached);
	proof.computed = calloc((size_t)callee_symbols_length, sizeof *proof.computed);
	unsigned result = 0;
	if (!callee_symbols_length || (proof.cached && proof.computed)) result = prove_function(&proof, symbol, types, types_length, result_type, 0);
	free(proof.cached);
	free(proof.computed);
	LLVMDisasmDispose(decoder);
	return result;
}

unsigned astra_native_leaf_proof(const uint8_t *object, int object_length,
                                 const char *symbol, const unsigned *types, int types_length,
                                 unsigned result_type, const unsigned *offsets, int offsets_length,
                                 const unsigned *sizes, int sizes_length) {
	return astra_native_object_proof(object, object_length, symbol, types, types_length,
	                                 result_type, offsets, offsets_length, sizes, sizes_length, NULL, 0, NULL, 0);
}
