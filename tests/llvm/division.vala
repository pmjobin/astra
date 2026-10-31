// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Backend.LLVM;

namespace Astra.Tests.Llvm {
private bool constant(CApi.ValueRef value, int64 number) {
	return (void*) CApi.is_constant_int (value) != null && CApi.constant_signed (value) == number;
}

// Test-only abstract evaluation of guard operands. Unknown values stay
// unknown; both successors are explored. This never executes generated IR.
private bool known(CApi.ValueRef value, CApi.ValueRef left, CApi.ValueRef right, bool overflow, out int64 number) {
	if ((void*) value == (void*) right) {
		number = overflow ? -1 : 0;
		return true;
	}
	if (overflow && (void*) value == (void*) left) {
		number = -2147483648L;
		return true;
	}
	if ((void*) CApi.is_constant_int (value) != null) {
		number = CApi.constant_signed (value);
		return true;
	}
	number = 0;
	return false;
}

private int guard_truth(CApi.ValueRef value, CApi.ValueRef left, CApi.ValueRef right, bool overflow, CApi.ValueRef[] all) {
	if ((void*) CApi.is_constant_int (value) != null) {
		return CApi.constant_signed (value) == 0 ? 0 : 1;
	}
	bool instruction = false;
	foreach (var i in all) {
		instruction = instruction || (void*) i == (void*) value;
	}
	if (!instruction) {
		return -1;
	}
	if (CApi.opcode (value) == CApi.Opcode.ICMP && CApi.predicate (value) == CApi.IntPredicate.EQ) {
		int64 a;
		int64 b = 0;
		if (known (CApi.operand (value, 0), left, right, overflow, out a) && known (CApi.operand (value, 1), left, right, overflow, out b)) {
			return a == b ? 1 : 0;
		}
	}
	if (CApi.opcode (value) == CApi.Opcode.AND) {
		int a = guard_truth (CApi.operand (value, 0), left, right, overflow, all);
		int b = guard_truth (CApi.operand (value, 1), left, right, overflow, all);
		return a == 0 || b == 0 ? 0 : a == 1 && b == 1 ? 1 : -1;
	}
	return -1;
}

private bool exceptional_path_reaches(CApi.ValueRef function, CApi.ValueRef raw, bool overflow) {
	var left = CApi.operand (raw, 0);
	var right = CApi.operand (raw, 1);
	var all = instructions (function);
	CApi.BasicBlockRef[] pending = {
		CApi.entry_block (function)
	};
	var seen = new HashTable<void*, void*> (direct_hash, direct_equal);
	for (int n = 0; n < pending.length; n++) {
		var b = pending[n];
		if (seen.contains ((void*) b)) {
			continue;
		}
		seen.insert ((void*) b, (void*) b);
		if ((void*) b == (void*) CApi.instruction_parent (raw)) {
			return true;
		}
		var end = CApi.block_terminator (b);
		uint count = CApi.successor_count (end);
		int truth = count == 2 ? guard_truth (CApi.condition (end), left, right, overflow, all) : -1;
		for (uint s = 0; s < count; s++) {
			if (truth < 0 || s == (truth == 1 ? 0 : 1)) {
				pending += CApi.successor (end, s);
			}
		}
	}
	return false;
}

private bool reachable_without(CApi.ValueRef function, CApi.BasicBlockRef target, CApi.BasicBlockRef excluded) {
	CApi.BasicBlockRef[] pending = {
		CApi.entry_block (function)
	};
	var seen = new HashTable<void*, void*> (direct_hash, direct_equal);
	for (int n = 0; n < pending.length; n++) {
		var b = pending[n];
		if ((void*) b == (void*) excluded || seen.contains ((void*) b)) {
			continue;
		}
		seen.insert ((void*) b, (void*) b);
		if ((void*) b == (void*) target) {
			return true;
		}
		var end = CApi.block_terminator (b);
		for (uint s = 0; s < CApi.successor_count (end); s++) {
			pending += CApi.successor (end, s);
		}
	}
	return false;
}

private void trap_block(CApi.BasicBlockRef block) {
	var call = CApi.first_instruction (block);
	assert (CApi.opcode (call) == CApi.Opcode.CALL);
	assert (CApi.intrinsic_id (CApi.called_value (call)) == CApi.lookup_intrinsic_id ("llvm.trap", 9));
	assert (CApi.opcode (CApi.next_instruction (call)) == CApi.Opcode.UNREACHABLE);
	assert ((void*) CApi.next_instruction (CApi.next_instruction (call)) == null);
}

private int audit_division(LlvmModuleArtifact artifact) {
	int count = 0;
	foreach (var function in functions (artifact)) {
		foreach (var raw in instructions (function)) {
			var opcode = CApi.opcode (raw);
			if (opcode != CApi.Opcode.SDIV && opcode != CApi.Opcode.SREM) {
				continue;
			}
			count++;
			var normal = CApi.instruction_parent (raw);
			var right = CApi.operand (raw, 1);
			bool dominated = false;
			foreach (var b in blocks (function)) {
				var end = CApi.block_terminator (b);
				if (CApi.successor_count (end) != 2) {
					continue;
				}
				var condition = CApi.condition (end);
				if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ) {
					continue;
				}
				if ((void*) CApi.operand (condition, 0) == (void*) right && constant (CApi.operand (condition, 1), 0) && !reachable_without (function, normal, CApi.successor (end, 1))) {
					trap_block (CApi.successor (end, 0));
					dominated = true;
				}
			}
			assert (dominated);
			assert (!exceptional_path_reaches (function, raw, false));
			assert (!exceptional_path_reaches (function, raw, true));
			var continuation = CApi.successor (CApi.block_terminator (normal), 0);
			var phi = CApi.first_instruction (continuation);
			assert (CApi.opcode (phi) == CApi.Opcode.PHI && CApi.incoming_count (phi) == 2);
			assert (constant (CApi.incoming_value (phi, 0), opcode == CApi.Opcode.SDIV ? -2147483648L : 0));
			assert ((void*) CApi.incoming_value (phi, 1) == (void*) raw && (void*) CApi.incoming_block (phi, 1) == (void*) normal);
		}
	}
	return count;
}

private void division() throws GLib.Error {
	var artifact = lower (fixture ("tests/scalar/fixtures/division.astra"));
	assert (audit_division (artifact) == 2);
	var fs = functions (artifact);
	for (int f = 1; f <= 4; f++) {
		var entry = CApi.block_terminator (CApi.entry_block (fs[f]));
		assert (constant (CApi.condition (entry), f < 3 ? 0 : -1));
		trap_block (CApi.successor (entry, 0));
		var nonzero = CApi.block_terminator (CApi.successor (entry, 1));
		assert (constant (CApi.condition (nonzero), f < 3 ? -1 : 0));
		var normal = CApi.successor (nonzero, 1);
		assert (CApi.opcode (CApi.first_instruction (normal)) == CApi.Opcode.UNREACHABLE);
		var phi = returned (fs[f]);
		assert (CApi.incoming_count (phi) == 1);
		assert (constant (CApi.incoming_value (phi, 0), f == 1 || f == 3 ? -2147483648L : 0));
	}
	assert (!artifact.dump ().contains ("poison"));
}

private void division_order() throws GLib.Error {
	var artifact = lower (fixture ("tests/llvm/fixtures/division-order.astra"));
	assert (audit_division (artifact) == 1);
	var fs = functions (artifact);
	var cs = operations (fs[3], CApi.Opcode.CALL);
	// The intrinsic is in its own trap block; Astra calls retain identity.
	var first = CApi.first_instruction (CApi.entry_block (fs[3]));
	var middle = CApi.next_instruction (first);
	assert ((void*) CApi.called_value (first) == (void*) fs[0] && (void*) CApi.called_value (middle) == (void*) fs[1]);
	assert (CApi.opcode (CApi.next_instruction (middle)) == CApi.Opcode.ICMP);
	assert (cs.length == 4);
	var last = cs[3];
	assert ((void*) CApi.called_value (last) == (void*) fs[2]);
	var raw = operations (fs[3], CApi.Opcode.SDIV)[0];
	assert ((void*) CApi.operand (raw, 0) == (void*) middle);
	var continuation = CApi.successor (CApi.block_terminator (CApi.instruction_parent (raw)), 0);
	assert ((void*) CApi.instruction_parent (last) == (void*) continuation);
	var phi = CApi.first_instruction (continuation);
	var sum = CApi.next_instruction (phi);
	assert (CApi.opcode (sum) == CApi.Opcode.ADD && (void*) CApi.next_instruction (sum) == (void*) last);
	assert ((void*) CApi.operand (sum, 0) == (void*) first && (void*) CApi.operand (sum, 1) == (void*) phi);
	assert (audit_division (lower (fixture ("tests/scalar/fixtures/trap-order.astra"))) == 5);
}

private void division_phi() throws GLib.Error {
	var artifact = lower (fixture ("tests/llvm/fixtures/division-phi.astra"));
	assert (audit_division (artifact) == 2);
	var f = functions (artifact)[0];
	var join = returned (f);
	assert (CApi.opcode (join) == CApi.Opcode.PHI && CApi.incoming_count (join) == 2);
	for (uint p = 0; p < 2; p++) {
		var argument = CApi.incoming_value (join, p);
		assert (CApi.opcode (argument) == CApi.Opcode.PHI);
		assert ((void*) CApi.incoming_block (join, p) == (void*) CApi.instruction_parent (argument));
		assert (CApi.block_name (CApi.incoming_block (join, p)).has_suffix (".continue"));
	}
}

private void unsafe_control() throws GLib.Error {
	var artifact = new LlvmModuleArtifact ();
	var i32 = CApi.int32_type_in_context (artifact.context);
	CApi.TypeRef[] parameters = {
		i32, i32
	};
	var type = CApi.function_type (i32, parameters, 2, 0);
	var function = CApi.add_function (artifact.module, "unsafe", type);
	var entry = CApi.append_basic_block_in_context (artifact.context, function, "entry");
	var builder = CApi.create_builder_in_context (artifact.context);
	CApi.position_builder_at_end (builder, entry);
	var raw = CApi.build_sdiv (builder, CApi.get_param (function, 0), CApi.get_param (function, 1), "raw");
	CApi.build_ret (builder, raw);
	CApi.dispose_builder (builder);
	// LLVM verification alone accepts this Astra-incorrect implementation.
	artifact.verify ();
	assert (exceptional_path_reaches (function, raw, false));
	assert (exceptional_path_reaches (function, raw, true));
}

private void register_division_tests() {
	add ("/llvm/division/guards-and-special-values", division);
	add ("/llvm/division/effect-order", division_order);
	add ("/llvm/division/actual-phi-predecessor", division_phi);
	add ("/llvm/division/unsafe-negative-control", unsafe_control);
}
}
