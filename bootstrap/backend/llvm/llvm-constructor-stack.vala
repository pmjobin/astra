// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Backend.LLVM {
// Exact path facts for the private bounded integer stack used by checked
// construction. LLVM addresses, loads, stores and arithmetic are reconstructed
// here; no lowering event or upstream ownership graph supplies their effects.
internal class LlvmScopedConstructorStack : Object {
	private CApi.ValueRef count;
	private CApi.ValueRef stack;
	private CApi.TypeRef word;
	private CApi.TypeRef array;
	private int capacity;
	private HashTable<void*, int> registers = new HashTable<void*, int> (direct_hash, direct_equal);
	internal int slots { get { return capacity + 1 + (int) registers.size (); } }
	private static bool one(CApi.ValueRef value) {
		return (void*) CApi.is_constant_int (value) != null && CApi.const_int_zext (value) == 1;
	}

	private bool count_address(CApi.ValueRef value) {
		return (void*) value == (void*) count;
	}

	private bool stack_address(CApi.ValueRef value) {
		return (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.GEP && CApi.operand_count (value) == 3 && (void*) CApi.gep_source_type (value) == (void*) array && (void*) CApi.operand (value, 0) == (void*) stack && (void*) CApi.is_constant_int (CApi.operand (value, 1)) != null && CApi.const_int_zext (CApi.operand (value, 1)) == 0;
	}

	private void memory_uses(CApi.ValueRef address) throws LlvmError {
		for (var use = CApi.first_use (address); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) == null) {
				throw new LlvmError.VERIFICATION ("checked constructor stack escaped its private storage");
			}
			bool load = CApi.opcode (user) == CApi.Opcode.LOAD;
			if (!(load || CApi.opcode (user) == CApi.Opcode.STORE) || (void*) CApi.operand (user, load ? 0 : 1) != (void*) address || (void*) (load ? CApi.type_of (user) : CApi.type_of (CApi.operand (user, 0))) != (void*) word || CApi.get_volatile (user) != 0 || CApi.get_ordering (user) != 0) {
				throw new LlvmError.VERIFICATION ("checked constructor stack requires exact private integer memory effects");
			}
		}
	}

	internal LlvmScopedConstructorStack (CApi.ValueRef function, int capacity) throws LlvmError {
		if (capacity <= 0) {
			throw new LlvmError.VERIFICATION ("checked constructor stack lost its exact native capacity");
		}
		this.capacity = capacity;
		word = CApi.int32_type_in_context (CApi.type_context (CApi.type_of (function)));
		array = CApi.array_type (word, capacity);
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.ALLOCA || CApi.operand_count (instruction) != 1 || !one (CApi.operand (instruction, 0))) {
					continue;
				}
				var type = CApi.allocated_type (instruction);
				if ((void*) type == (void*) word) {
					if ((void*) count != null) {
						throw new LlvmError.VERIFICATION ("checked constructor stack count is ambiguous");
					}
					count = instruction;
				}
				if ((void*) type == (void*) array) {
					if ((void*) stack != null) {
						throw new LlvmError.VERIFICATION ("checked constructor acquisition stack is ambiguous");
					}
					stack = instruction;
				}
			}
		}
		if ((void*) count == null || (void*) stack == null) {
			throw new LlvmError.VERIFICATION ("checked constructor lost its bounded acquisition stack");
		}
		memory_uses (count);
		for (var use = CApi.first_use (stack); (void*) use != null; use = CApi.next_use (use)) {
			var address = CApi.user (use);
			if (!stack_address (address)) {
				throw new LlvmError.VERIFICATION ("checked constructor stack lost its original bounded address");
			}
			memory_uses (address);
		}
		bool changed = false;
		do {
			changed = false;
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (registers.contains ((void*) instruction) || (void*) CApi.type_of (instruction) != (void*) word) {
						continue;
					}
					var opcode = CApi.opcode (instruction);
					bool tracked = opcode == CApi.Opcode.LOAD && (count_address (CApi.operand (instruction, 0)) || stack_address (CApi.operand (instruction, 0)));
					if (opcode == CApi.Opcode.ADD || opcode == CApi.Opcode.SUB) {
						tracked = registers.contains ((void*) CApi.operand (instruction, 0)) || registers.contains ((void*) CApi.operand (instruction, 1));
					}
					if (tracked) {
						registers.insert ((void*) instruction, (int) registers.size ());
						changed = true;
					}
				}
			}
		} while (changed);
	}

	// Zero is unknown; a bounded nonnegative integer is encoded as n + 1.
	private uint value(CApi.ValueRef input, uint[] state, int offset) {
		if ((void*) CApi.type_of (input) != (void*) word) {
			return 0;
		}
		if ((void*) CApi.is_constant_int (input) != null) {
			uint64 number = CApi.const_int_zext (input);
			return number < uint.MAX ? (uint) number + 1 : 0;
		}
		return registers.contains ((void*) input) ? state[offset + capacity + 1 + registers.lookup ((void*) input)] : 0;
	}

	private int address(CApi.ValueRef input, uint[] state, int offset, bool strict) throws LlvmError {
		if (count_address (input)) {
			return 0;
		}
		if (!stack_address (input)) {
			return -1;
		}
		uint index = value (CApi.operand (input, 2), state, offset);
		if (index == 0 || index - 1 >= capacity) {
			if (strict) {
				throw new LlvmError.VERIFICATION ("checked constructor stack address lacks its proven current bound");
			}
			return -2;
		}
		return (int) index;
	}

	internal void effect(CApi.ValueRef instruction, uint[] state, int offset, bool strict) throws LlvmError {
		var opcode = CApi.opcode (instruction);
		if (opcode == CApi.Opcode.STORE) {
			int slot = address (CApi.operand (instruction, 1), state, offset, strict);
			if (slot == -1) {
				return;
			}
			uint incoming = value (CApi.operand (instruction, 0), state, offset);
			if (slot == 0 && (incoming == 0 || incoming - 1 > capacity)) {
				if (strict) {
					throw new LlvmError.VERIFICATION ("checked constructor stack count lacks its proven native bound");
				}
				incoming = 0;
			}
			if (slot == -2) {
				for (int i = 1; i <= capacity; i++) {
					state[offset + i] = 0;
				}
			} else {
				state[offset + slot] = incoming;
			}
		}
		if (!registers.contains ((void*) instruction)) {
			return;
		}
		uint result = 0;
		if (opcode == CApi.Opcode.LOAD) {
			int slot = address (CApi.operand (instruction, 0), state, offset, strict);
			if (slot >= 0) {
				result = state[offset + slot];
			}
		} else {
			uint left = value (CApi.operand (instruction, 0), state, offset), right = value (CApi.operand (instruction, 1), state, offset);
			if (left != 0 && right != 0) {
				uint calculated = opcode == CApi.Opcode.ADD ? (left - 1) + (right - 1) : (left - 1) - (right - 1);
				result = calculated < uint.MAX ? calculated + 1 : 0;
			}
		}
		state[offset + capacity + 1 + registers.lookup ((void*) instruction)] = result;
	}

	internal int condition(CApi.ValueRef instruction, uint[] state, int offset) {
		if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != CApi.Opcode.ICMP) {
			return -1;
		}
		uint left = value (CApi.operand (instruction, 0), state, offset), right = value (CApi.operand (instruction, 1), state, offset);
		if (left == 0 || right == 0) {
			return -1;
		}
		switch (CApi.predicate (instruction)) {
		case CApi.IntPredicate.EQ:
			return left == right ? 1 : 0;
		case CApi.IntPredicate.NE:
			return left != right ? 1 : 0;
		case CApi.IntPredicate.UGE:
			return left >= right ? 1 : 0;
		default:
			return -1;
		}
	}

	internal bool edge(CApi.ValueRef end, uint successor, uint[] state, int offset) {
		if (CApi.opcode (end) != CApi.Opcode.SWITCH) {
			return true;
		}
		uint selected = value (CApi.operand (end, 0), state, offset);
		if (selected == 0) {
			return true;
		}
		uint choice = 0;
		for (uint i = 1; i < CApi.successor_count (end); i++) {
			uint candidate = value (CApi.switch_case_value (end, i), state, offset);
			if (candidate != 0 && candidate == selected) {
				choice = i;
				break;
			}
		}
		return choice == successor;
	}

}
}
