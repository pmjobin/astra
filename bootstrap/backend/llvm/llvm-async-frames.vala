// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.NativeAbi;
namespace Astra.Backend.LLVM {
internal class LlvmAsyncRuntime : Object {
	private weak LlvmModuleArtifact artifact;
	internal CApi.TypeRef pointer;
	internal CApi.TypeRef i32;
	internal CApi.TypeRef i64;
	internal CApi.TypeRef nothing;
	internal LlvmAsyncRuntime (LlvmModuleArtifact artifact) {
		this.artifact = artifact;
		pointer = CApi.pointer_type_in_context (artifact.context, 0);
		i32 = CApi.int32_type_in_context (artifact.context);
		i64 = CApi.int_type_in_context (artifact.context, 64);
		nothing = CApi.void_type_in_context (artifact.context);
	}
	internal void trap(CApi.BuilderRef builder) {
		uint identity = CApi.lookup_intrinsic_id ("llvm.trap", 9);
		var target = CApi.get_intrinsic_declaration (artifact.module, identity, null, 0);
		var signature = CApi.intrinsic_get_type (artifact.context, identity, null, 0);
		CApi.build_call (builder, signature, target, null, 0, "");
		CApi.build_unreachable (builder);
	}
	internal CApi.ValueRef call(CApi.BuilderRef builder, string symbol, CApi.TypeRef result, CApi.TypeRef[] parameters, CApi.ValueRef[] arguments, string name = "") throws LlvmError {
		var signature = CApi.function_type (result, parameters, parameters.length, 0);
		var target = CApi.named_function (artifact.module, symbol);
		var registered = (void*) artifact.async_runtime_symbols.lookup (symbol);
		if (registered == null) {
			if ((void*) target != null) {
				throw new LlvmError.LOWERING ("virtual runtime protocol name conflicts with a source-declared physical identity");
			}
			target = CApi.add_function (artifact.module, symbol, signature);
			CApi.set_function_call_conv (target, CApi.CallConv.C);
			artifact.async_runtime_symbols.insert (symbol, (void*) target);
		} else if ((void*) target != registered || CApi.count_basic_blocks (target) != 0) {
			throw new LlvmError.LOWERING ("virtual runtime operation lost its registered external provider identity");
		}
		if ((void*) CApi.global_value_type (target) != (void*) signature || CApi.function_call_conv (target) != CApi.CallConv.C) {
			throw new LlvmError.LOWERING ("async runtime operation conflicts with an exact existing physical identity");
		}
		var instruction = CApi.build_call (builder, signature, target, arguments, arguments.length, name);
		CApi.set_instruction_call_conv (instruction, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (instruction, target, signature, arguments, CApi.CallConv.C, "exact nominated native task protocol operation"));
		return instruction;
	}
}
internal class LlvmAsyncFieldAccess : Object {
	private CApi.ValueRef address;
	private CApi.ValueRef backing;
	private CApi.TypeRef frame;
	private uint index;
	internal LlvmAsyncFieldAccess (CApi.ValueRef address, CApi.ValueRef backing, CApi.TypeRef frame, uint index) {
		this.address = address;
		this.backing = backing;
		this.frame = frame;
		this.index = index;
	}
	internal void verify() throws LlvmError {
		if (CApi.opcode (address) != CApi.Opcode.GEP || CApi.operand_count (address) != 3 || (void*) CApi.operand (address, 0) != (void*) backing || CApi.const_int_zext (CApi.operand (address, 1)) != 0 || CApi.const_int_zext (CApi.operand (address, 2)) != index || (void*) CApi.gep_source_type (address) != (void*) frame) {
			throw new LlvmError.VERIFICATION ("async frame address lost exact allocation/type/field association");
		}
	}
}
internal class LlvmAsyncEffectOrder : Object {
	private CApi.BasicBlockRef block;
	private void*[] instructions;
	private void*[] edges;
	internal LlvmAsyncEffectOrder (CApi.BasicBlockRef block) {
		this.block = block;
		int count = 0;
		for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
			count++;
		}
		instructions = new void*[count];
		int n = 0;
		for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
			instructions[n++] = (void*) i;
		}
		var terminator = CApi.block_terminator (block);
		edges = new void*[CApi.successor_count (terminator)];
		for (uint e = 0; e < edges.length; e++) {
			edges[e] = (void*) CApi.successor (terminator, e);
		}
	}
	internal void verify() throws LlvmError {
		int n = 0;
		for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
			if (n >= instructions.length || instructions[n++] != (void*) i) {
				throw new LlvmError.VERIFICATION ("async operation/cleanup/publication lost exact prerequisite order or gained an unplanned effect");
			}
		}
		if (n != instructions.length) {
			throw new LlvmError.VERIFICATION ("async operation/cleanup/publication lost a mandatory effect");
		}
		var terminator = CApi.block_terminator (block);
		if (CApi.successor_count (terminator) != edges.length) {
			throw new LlvmError.VERIFICATION ("async prerequisite lost its exact control edge");
		}
		for (uint e = 0; e < edges.length; e++) {
			if ((void*) CApi.successor (terminator, e) != edges[e]) {
				throw new LlvmError.VERIFICATION ("async cleanup/publication lost original prerequisite control edge");
			}
		}
	}
}
// Copied physical suspension authority for a complete coroutine lifetime
// graph. No source/SSA node survives the exact native state association.
internal class LlvmAsyncContinuation : Object {
	private CApi.ValueRef setter;
	private CApi.ValueRef operation;
	private CApi.ValueRef returned;
	private CApi.BasicBlockRef continuation;
	private CApi.BasicBlockRef refused;
	private CApi.ValueRef task;
	private uint pc;
	private bool waiting;
	private LlvmClassCallBinding set_call;
	private LlvmClassCallBinding operation_call;
	private static LlvmClassCallBinding copied_call(CApi.ValueRef call, string label) {
		var arguments = new CApi.ValueRef[CApi.argument_count (call)];
		for (uint i = 0; i < arguments.length; i++) {
			arguments[i] = CApi.operand (call, i);
		}
		return new LlvmClassCallBinding (call, CApi.called_value (call), CApi.called_function_type (call), arguments, CApi.CallConv.C, label);
	}
	internal LlvmAsyncContinuation (CApi.ValueRef setter, CApi.ValueRef operation, CApi.ValueRef returned, CApi.BasicBlockRef continuation, CApi.BasicBlockRef refused, CApi.ValueRef task, uint pc, bool waiting) {
		this.setter = setter;
		this.operation = operation;
		this.returned = returned;
		this.continuation = continuation;
		this.refused = refused;
		this.task = task;
		this.pc = pc;
		this.waiting = waiting;
		set_call = copied_call (setter, "coroutine saved PC");
		operation_call = copied_call (operation, "coroutine accepted suspension");
	}
	internal CApi.ValueRef saved_pc() {
		return setter;
	}
	internal CApi.ValueRef admission() {
		return operation;
	}
	internal CApi.ValueRef suspension_return() {
		return returned;
	}
	internal CApi.BasicBlockRef next_state() {
		return continuation;
	}
	internal uint state() {
		return pc;
	}
	internal void verify(CApi.ValueRef resume, CApi.BasicBlockRef expected) throws LlvmError {
		set_call.verify ();
		operation_call.verify ();
		var block = CApi.instruction_parent (operation);
		var suspended = CApi.instruction_parent (returned);
		var branch = CApi.block_terminator (block);
		size_t length;
		if (pc == 0 || (void*) next_state () != (void*) expected || (void*) CApi.block_parent (continuation) != (void*) resume || (void*) CApi.block_parent (block) != (void*) resume || (void*) CApi.instruction_parent (setter) != (void*) block || CApi.value_name (CApi.called_value (setter), out length) != "astra_async_set_pc" || CApi.argument_count (saved_pc ()) != 2 || (void*) CApi.operand (setter, 0) != (void*) task || (void*) CApi.is_constant_int (CApi.operand (setter, 1)) == null || CApi.const_int_zext (CApi.operand (setter, 1)) != pc || CApi.argument_count (admission ()) < 2 || (void*) CApi.operand (operation, 0) != (void*) task || CApi.opcode (returned) != CApi.Opcode.RET || CApi.operand_count (returned) != 0 || (void*) CApi.first_instruction (suspended) != (void*) returned || (void*) CApi.block_terminator (suspended) != (void*) returned || CApi.opcode (branch) != CApi.Opcode.BR || CApi.successor_count (branch) != 2 || (void*) CApi.successor (branch, 0) != (void*) suspended || (void*) CApi.successor (branch, 1) != (void*) refused) {
			throw new LlvmError.VERIFICATION ("coroutine suspension lost its exact saved state, task or accepted return edge");
		}
		var condition = CApi.operand (branch, 0);
		if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != (waiting ? CApi.IntPredicate.EQ : CApi.IntPredicate.NE) || (void*) CApi.operand (condition, 0) != (void*) operation || (void*) CApi.is_constant_int (CApi.operand (condition, 1)) == null || CApi.const_int_zext (CApi.operand (condition, 1)) != 0) {
			throw new LlvmError.VERIFICATION ("coroutine suspension requires its actual accepted admission result");
		}
		string name = CApi.value_name (CApi.called_value (operation), out length);
		if (waiting ? name != "astra_async_wait" && name != "astra_async_bridge_wait" : name != "astra_async_delay" && name != "astra_async_linux_delay_ms" && name != "astra_async_linux_payload") {
			throw new LlvmError.VERIFICATION ("coroutine suspension lost its nominated runtime operation");
		}
		bool stored = false, admitted = false;
		for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.value_name (CApi.called_value (instruction), out length) == "astra_async_set_pc" && (void*) instruction != (void*) setter) {
				throw new LlvmError.VERIFICATION ("coroutine saved continuation was overwritten before suspension");
			}
			if ((void*) instruction == (void*) setter) {
				stored = true;
			}
			if ((void*) instruction == (void*) operation) {
				if (!stored) {
					throw new LlvmError.VERIFICATION ("coroutine admission precedes its saved continuation");
				}
				admitted = true;
			}
			if ((void*) instruction == (void*) branch && !admitted) {
				throw new LlvmError.VERIFICATION ("coroutine suspension precedes actual admission");
			}
		}
		int incoming = 0;
		for (var candidate = CApi.first_block (resume); (void*) candidate != null; candidate = CApi.next_block (candidate)) {
			var end = CApi.block_terminator (candidate);
			for (uint e = 0; e < CApi.successor_count (end); e++) {
				if ((void*) CApi.successor (end, e) == (void*) suspended) {
					incoming++;
				}
			}
		}
		if (incoming != 1) {
			throw new LlvmError.VERIFICATION ("coroutine suspended return gained an unadmitted predecessor");
		}
	}
}
internal class LlvmAsyncOwnerWrite : Object {
	internal CApi.ValueRef instruction;
	internal LlvmAsyncOwnerWrite (CApi.ValueRef instruction) {
		this.instruction = instruction;
	}
}
// Copied typed future success mapping. This is shape authority only: the
// capture admission also requires publication/observation debt verification
// through actual resume, destroy and caller instructions.
internal class LlvmAsyncRecordResult : Object {
	private CApi.TypeRef carrier;
	private int[] captures;
	internal uint field_count { get { return captures.length; } }
	internal uint owner_count { get; private set; }
	internal uint empty_count { get; private set; }
	internal bool empty_field(uint field) {
		return captures[field] == -2;
	}
	internal int capture(uint field) {
		return captures[field];
	}
	internal CApi.TypeRef result_type() {
		return carrier;
	}
	internal CApi.ValueRef publication_value(CApi.ValueRef store, uint field) throws LlvmError {
		if (field >= field_count || CApi.opcode (store) != CApi.Opcode.STORE || CApi.operand_count (store) != 2 || CApi.get_volatile (store) != 0 || CApi.get_ordering (store) != 0 || (void*) CApi.type_of (CApi.operand (store, 0)) != (void*) carrier) {
			throw new LlvmError.VERIFICATION ("scoped result publication lost its complete typed payload");
		}
		var value = CApi.operand (store, 0);
		if (field_count == 1) {
			return value;
		}
		var seen = new HashTable<uint, bool> (direct_hash, direct_equal);
		CApi.ValueRef selected = (CApi.ValueRef) null;
		while ((void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.INSERT_VALUE) {
			if (CApi.index_count (value) != 1 || (void*) CApi.type_of (value) != (void*) carrier) {
				throw new LlvmError.VERIFICATION ("scoped result publication changed its physical field path");
			}
			uint member = CApi.indices (value)[0];
			if (member >= field_count || seen.contains (member)) {
				throw new LlvmError.VERIFICATION ("scoped result publication repeats or escapes a physical field");
			}
			seen.insert (member, true);
			if (member == field) {
				selected = CApi.operand (value, 1);
			}
			value = CApi.operand (value, 0);
		}
		if ((void*) value == (void*) CApi.const_null (carrier)) {
			if ((void*) selected == null) {
				selected = CApi.const_null (CApi.struct_type_at_index (carrier, field));
			}
		} else if (CApi.is_constant (value) != 0 && CApi.operand_count (value) == field_count && (void*) CApi.type_of (value) == (void*) carrier) {
			if ((void*) selected == null) {
				selected = CApi.operand (value, field);
			}
		} else {
			throw new LlvmError.VERIFICATION ("scoped result publication lacks its exact complete aggregate origin");
		} return selected;
	}
	internal bool publication_chain(CApi.ValueRef insertion, CApi.ValueRef store) throws LlvmError {
		if (field_count == 1 || CApi.opcode (insertion) != CApi.Opcode.INSERT_VALUE || (void*) CApi.type_of (insertion) != (void*) carrier) {
			return false;
		}
		var value = CApi.operand (store, 0);
		bool found = false;
		while ((void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.INSERT_VALUE) {
			if ((void*) value == (void*) insertion) {
				found = true;
			}
			var use = CApi.first_use (value);
			if ((void*) use == null || (void*) CApi.next_use (use) != null) {
				throw new LlvmError.VERIFICATION ("scoped result aggregate escaped its single exact publication chain");
			}
			var user = CApi.user (use);
			if ((void*) user != (void*) store && (CApi.opcode (user) != CApi.Opcode.INSERT_VALUE || (void*) CApi.operand (user, 0) != (void*) value)) {
				throw new LlvmError.VERIFICATION ("scoped result aggregate gained an unproved transport");
			}
			value = CApi.operand (value, 0);
		}
		return found;
	}
	internal void verify(LlvmScopedOwnedInputs inputs) throws LlvmError {
		inputs.verify_signature ();
		if (field_count == 0 || owner_count + empty_count == 0 || (field_count == 1 ? CApi.type_kind (result_type ()) != CApi.TypeKind.POINTER : CApi.type_kind (result_type ()) != CApi.TypeKind.STRUCT || CApi.count_struct_element_types (result_type ()) != field_count)) {
			throw new LlvmError.VERIFICATION ("scoped task result lost its copied physical carrier");
		}
		var used = new HashTable<int, bool> (direct_hash, direct_equal);
		uint empty = 0;
		for (uint f = 0; f < field_count; f++) {
			int slot = capture (f);
			if (slot == -2) {
				if (CApi.type_kind (field_count == 1 ? result_type () : CApi.struct_type_at_index (result_type (), f)) != CApi.TypeKind.POINTER) {
					throw new LlvmError.VERIFICATION ("empty scoped task result lost its pointer carrier");
				}
				empty++;
				continue;
			}
			if (slot < 0) {
				continue;
			}
			if (slot >= inputs.count || inputs.input_graph (slot) != null || used.contains (slot) || CApi.type_kind (field_count == 1 ? result_type () : CApi.struct_type_at_index (result_type (), f)) != CApi.TypeKind.POINTER) {
				throw new LlvmError.VERIFICATION ("scoped task result lost its distinct original owner mapping");
			}
			used.insert (slot, true);
		}
		if (used.size () != owner_count || empty != empty_count) {
			throw new LlvmError.VERIFICATION ("scoped task result lost its complete retained owner inventory");
		}
	}
	private LlvmAsyncRecordResult (CApi.TypeRef carrier, int fields) {
		this.carrier = carrier;
		captures = new int[fields];
		for (int f = 0; f < fields; f++) {
			captures[f] = -1;
		}
	}
	internal static LlvmAsyncRecordResult? from_native(LlvmModuleArtifact artifact, NativeFunction source, NativeAbiProgram program, LlvmScopedOwnedInputs inputs) throws LlvmError {
		var signature = source.signature;
		var record = signature.struct_result;
		if (record == null || record.mode != NativeStructValueMode.MOVE_VALUE || record.leaves.length == 0 || record.result_carrier != NativeStructResultCarrier.SINGLE_LEAF && record.result_carrier != NativeStructResultCarrier.LEAF_AGGREGATE) {
			return null;
		}
		try {
			var summary = Astra.Source.RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			if (!summary.complete || summary.logical_coordinates || summary.has_exception || summary.store_count != 0 || summary.updated_inputs ().length != 0 || summary.equations.requirements (summary.result, "f1").length != 0) {
				return null;
			}
			for (int p = 0; p < inputs.count; p++) {
				uint position = inputs.physical_position (p);
				var retained = summary.equations.requirements (summary.result, "f2.f%u".printf (position));
				if (retained.length != 1 || retained[0].kind != Astra.Source.RuntimeScopeOriginKind.OWNER_PARAMETER || retained[0].ordinal != position || retained[0].path != "" || !retained[0].descendants || retained[0].exclusion_count != 0) {
					return null;
				}
			}
			var input_records = new HashTable<int, NativeObjectOriginPlan> (direct_hash, direct_equal);
			if (!LlvmScopedRecordInputs.bind (signature, program.classes, input_records)) {
				return null;
			}
			var types = new CApi.TypeRef[record.leaves.length];
			var mapper = new LlvmTypeMapper (artifact.context);
			for (int f = 0; f < record.leaves.length; f++) {
				var leaf = record.leaves[f];
				if (leaf.buffer_component != -1 || leaf.abi_type.get_type () != typeof (NativeScalarAbiType)) {
					return null;
				}
				types[f] = mapper.abi_type (leaf.abi_type);
			}
			var carrier = types.length == 1 ? types[0] : CApi.struct_type_in_context (artifact.context, types, types.length, 0);
			var result = new LlvmAsyncRecordResult (carrier, types.length);
			var used = new HashTable<int, bool> (direct_hash, direct_equal);
			var seen = new HashTable<NativeRecordResource, bool> (direct_hash, direct_equal);
			for (uint f = 0; f < record.leaves.length; f++) {
				var leaf = record.leaves[f];
				NativeRecordResource? owner = null;
				foreach (var candidate in record.ownership) {
					if (candidate.field_path == leaf.storage_path) {
						if (owner != null) {
							return null;
						}
						owner = candidate;
					}
				}
				var path = new StringBuilder ("f0");
				foreach (var component in leaf.storage_path.split (".")) {
					int ordinal;
					if (!int.try_parse (component, out ordinal) || ordinal < 0) {
						return null;
					}
					path.append_printf (".f%d", ordinal);
				}
				var roots = summary.equations.requirements (summary.result, path.str);
				if (owner == null) {
					if (roots.length != 0) {
						return null;
					}
					continue;
				}
				if (seen.contains (owner) || owner.buffer_cleanup != null || owner.cleanup_symbol != "" || owner.cleanup_class_ordinal < 0 || owner.cleanup_class_ordinal >= program.classes.length || CApi.type_kind (types[f]) != CApi.TypeKind.POINTER) {
					return null;
				}
				seen.insert (owner, true);
				var object_class = program.classes[owner.cleanup_class_ordinal];
				if (object_class.name != owner.type_name || !object_class.allocation_policy_valid ()) {
					throw new LlvmError.INVALID_INPUT ("scoped task result lost its exact native Class origin");
				}
				if (!LlvmScopedClassGraph.contains_scope (object_class, program)) {
					continue;
				}
				if (roots.length == 0) {
					var policy = object_class.allocation_policy;
					if (policy == null || policy.kind != Astra.Source.AllocationKind.CONTEXT || policy.context_mode != "scoped-affine" || !LlvmScopedClassGraph.value_scope_free (object_class, program.classes)) {
						return null;
					}
					result.captures[f] = -2;
					result.empty_count++;
					continue;
				}
				if (roots.length != 1) {
					return null;
				}
				var root = roots[0];
				if (root.kind != Astra.Source.RuntimeScopeOriginKind.OWNER_PARAMETER || root.path != "" || !root.descendants || root.exclusion_count != 0 || root.ordinal < 0 || root.ordinal >= signature.parameters.length) {
					return null;
				}
				var origin = input_records.lookup (root.ordinal) ?? signature.parameters[root.ordinal].object_origin;
				if (origin == null || !origin.heap || origin.class_ordinal != object_class.ordinal || origin.class_name != object_class.name) {
					return null;
				}
				int slot = -1;
				for (int p = 0; p < inputs.count; p++) {
					if (inputs.physical_position (p) == root.ordinal) {
						slot = p;
					}
				}
				if (slot < 0 || inputs.input_graph (slot) != null || used.contains (slot)) {
					return null;
				}
				used.insert (slot, true);
				result.captures[f] = slot;
				result.owner_count++;
			}
			if (seen.size () != record.ownership.length || result.owner_count + result.empty_count == 0) {
				return null;
			}
			return result;
		} catch (Astra.Source.RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("scoped task result lifetime shape: %s", failure.message);
		}
	}
}
// This record retains a detached plan and LLVM identities, never SSA nodes.
internal class LlvmAsyncFrameBinding : Object {
	internal LlvmScopedOwnedInputs? scoped_captures { get; private set; }
	internal LlvmAsyncRecordResult? scoped_result { get; private set; }
	private LlvmSumSequence? checked_capture_body;
	internal void verify_captured_factory(bool checked_admission) throws LlvmError {
		if (scoped_captures == null) {
			throw new LlvmError.VERIFICATION ("scoped capture lacks its original input shapes");
		}
		scoped_captures.verify ();
		if (checked_admission) {
			if (checked_capture_body == null) {
				throw new LlvmError.VERIFICATION ("checked scoped capture factory was not sealed");
			}
			checked_capture_body.verify ();
		}
	}

	internal void bind_scoped_captures(NativeFunction source, NativeAbiProgram program, LlvmStructRegistry structs) throws LlvmError {
		if (effects.length != 0 || scoped_captures != null) {
			throw new LlvmError.LOWERING ("coroutine scoped capture shapes bind once before emission");
		}
		var ordinary = LlvmScopedOwnedInputs.from_native (artifact, factory, factory_type, source, program, structs, true);
		var inputs = LlvmScopedOwnedInputs.from_native (artifact, factory, factory_type, source, program, structs, true, true);
		var result = inputs == null ? null : LlvmAsyncRecordResult.from_native (artifact, source, program, inputs);
		if (result != null) {
			result.verify (inputs);
			if ((void*) result.result_type () != (void*) CApi.struct_type_at_index (frame_type, 0)) {
				throw new LlvmError.INVALID_INPUT ("scoped task result differs from its original physical frame payload");
			}
			scoped_captures = inputs;
			scoped_result = result;
		} else {
			scoped_captures = inputs != null && inputs.deferred_error ? inputs : ordinary;
			if (scoped_captures == null && LlvmScopedOwnedInputs.required (source.signature, program)) {
				throw new LlvmError.LOWERING ("scoped coroutine requires its complete captured-owner/context lifetime authority");
			}
		}

	}
	// Resolve only a concrete frame field on this coroutine's exact runtime
	// data pointer. Resume and destroy refer to the same retained allocation.
	internal int lifetime_field(CApi.ValueRef address) {
		if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.GEP || CApi.operand_count (address) != 3 || (void*) CApi.gep_source_type (address) != (void*) frame_type || (void*) CApi.is_constant_int (CApi.operand (address, 1)) == null || CApi.const_int_zext (CApi.operand (address, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (address, 2)) == null) {
			return -1;
		}
		var data = CApi.operand (address, 0);
		var code = CApi.block_parent (CApi.instruction_parent (address));
		if ((void*) code != (void*) resume && (void*) code != (void*) destroy || (void*) CApi.is_instruction (data) == null || CApi.opcode (data) != CApi.Opcode.CALL || CApi.argument_count (data) != 1 || (void*) CApi.operand (data, 0) != (void*) CApi.get_param (code, 0)) {
			return -1;
		}
		size_t length;
		if (CApi.value_name (CApi.called_value (data), out length) != "astra_async_data") {
			return -1;
		}
		uint64 field = CApi.const_int_zext (CApi.operand (address, 2));
		return field < CApi.count_struct_element_types (frame_type) ? (int) field : -1;
	}
	internal int captured_owner(int position) {
		for (uint o = 0; o < plan.owner_count; o++) {
			if (plan.owner (o).capture_first_leaf == position) {
				return (int) owner_field (o);
			}
		}
		return -1;
	}
	internal NativeAsyncFramePlan plan;
	internal CApi.TypeRef frame_type;
	internal CApi.TypeRef resume_type;
	internal CApi.TypeRef factory_type;
	internal CApi.ValueRef resume;
	internal CApi.ValueRef factory;
	internal CApi.ValueRef checked_factory;
	internal CApi.ValueRef destroy;
	private CApi.TypeRef destroy_type;
	private GenericArray<LlvmAsyncContinuation> continuations = new GenericArray<LlvmAsyncContinuation> ();
	internal uint continuation_count { get { return continuations.length; } }
	internal LlvmAsyncContinuation continuation(uint ordinal) {
		return continuations[ordinal];
	}
	private CApi.BasicBlockRef cancel_pending;
	private CApi.ValueRef original_resume;
	private CApi.ValueRef original_destroy;
	private CApi.ValueRef original_task;
	private CApi.BasicBlockRef original_resume_entry;
	private CApi.BasicBlockRef original_destroy_entry;
	private CApi.BasicBlockRef original_cancel;
	private CApi.ValueRef cancel_admission;
	internal CApi.ValueRef drained_children() {
		return cancel_admission;
	}
	private GenericArray<LlvmAsyncEffectOrder> effects = new GenericArray<LlvmAsyncEffectOrder> ();
	internal void seal_effects() throws LlvmError {
		if (effects.length != 0) {
			throw new LlvmError.LOWERING ("coroutine physical identity binds once before verification");
		}
		if (scoped_captures != null) {
			scoped_captures.seal (artifact.scoped_descriptors);
			checked_capture_body = new LlvmSumSequence (checked_factory, true);
		}
		original_resume = resume;
		original_destroy = destroy;
		original_task = task;
		original_resume_entry = CApi.first_block (resume);
		original_destroy_entry = CApi.first_block (destroy);
		original_cancel = cancel_entry;
		foreach (var code in new CApi.ValueRef[] { factory, checked_factory, resume, destroy }) {
			for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
				effects.add (new LlvmAsyncEffectOrder (block));
			}
		}
	}
	internal CApi.ValueRef task;
	internal CApi.BasicBlockRef cancel_entry;
	private CApi.ValueRef backing;
	private CApi.ValueRef dispatch;
	internal CApi.ValueRef dispatcher() {
		return dispatch;
	}
	private CApi.ValueRef pc_read;
	private CApi.BasicBlockRef fallback;
	private CApi.BasicBlockRef[] resume_blocks;
	private GenericArray<LlvmAsyncFieldAccess> accesses = new GenericArray<LlvmAsyncFieldAccess> ();
	private GenericArray<LlvmAsyncOwnerWrite> owner_writes = new GenericArray<LlvmAsyncOwnerWrite> ();
	internal uint owner_write_count { get { return owner_writes.length; } }
	internal CApi.ValueRef owner_write(uint ordinal) {
		return owner_writes[ordinal].instruction;
	}
	private LlvmAsyncRuntime runtime;
	private weak LlvmModuleArtifact artifact;
	internal static CApi.TypeRef factory_signature(LlvmTypeMapper types, NativeSignature signature) throws LlvmError {
		var parameters = new CApi.TypeRef[signature.parameters.length + 3];
		for (int p = 0; p < signature.parameters.length; p++) {
			parameters[p] = (signature.parameters[p].abi_type is NativeSliceType) ? types.buffer_carrier () : types.abi_type (signature.parameters[p].abi_type);
		}
		for (int p = signature.parameters.length; p < parameters.length; p++) {
			parameters[p] = types.scalar (NativeScalarType.PTR);
		}
		return CApi.function_type (types.scalar (NativeScalarType.PTR), parameters, parameters.length, 0);
	}
	internal LlvmAsyncFrameBinding (LlvmModuleArtifact artifact, LlvmTypeMapper types, NativeAsyncFramePlan plan, NativeSignature signature, CApi.TypeRef[] storage_types, LlvmSumRegistry? sums, string? module_symbol = null) throws LlvmError {
		this.artifact = artifact;
		this.plan = plan;
		runtime = new LlvmAsyncRuntime (artifact);
		if (storage_types.length != plan.storage_count) {
			throw new LlvmError.LOWERING ("async declared storage has no complete physical binding");
		}
		var fields = new CApi.TypeRef[plan.field_count + 1 + plan.object_count + plan.owner_count * 2 + plan.buffer_count + plan.storage_count + plan.enum_count * 2 + 1];
		fields[0] = signature.sum_result != null ? sums.lookup(signature.sum_result.identity).carrier : plan.record_result != null ? types.success_result_type(signature) : plan.result == null ? CApi.int_type_in_context(artifact.context, 8) : (plan.result is NativeSliceType) ? types.buffer_carrier () : types.abi_type (plan.result);
		for (uint f = 0; f < plan.field_count; f++) {
			fields[f + 1] = (plan.field (f).abi_type is NativeSliceType) ? types.buffer_carrier () : types.abi_type (plan.field (f).abi_type);
		}
		for (uint o = 0; o < plan.object_count; o++) {
			fields[plan.field_count + 1 + o] = runtime.pointer;
		}
		for (uint o = 0; o < plan.owner_count; o++) {
			fields[plan.field_count + 1 + plan.object_count + o * 2] = runtime.pointer;
			fields[plan.field_count + 2 + plan.object_count + o * 2] = CApi.int1_type_in_context (artifact.context);
		}
		for (uint b = 0; b < plan.buffer_count; b++) {
			fields[buffer_field (b)] = types.buffer_carrier ();
		}
		for (uint s = 0; s < plan.storage_count; s++) {
			fields[storage_field (s)] = storage_types[s];
		}
		for (uint e = 0; e < plan.enum_count; e++) {
			fields[enum_field (e)] = sums.lookup (plan.enum_slot (e).identity).carrier;
			fields[enum_field (e) + 1] = CApi.int1_type_in_context (artifact.context);
		}
		fields[result_live_field ()] = CApi.int1_type_in_context (artifact.context);
		frame_type = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		CApi.TypeRef[] resume_parameters = {
			runtime.pointer
		};
		resume_type = CApi.function_type (runtime.nothing, resume_parameters, 1, 0);
		resume = CApi.add_function (artifact.module, module_symbol == null ? "astra.task.resume.%d".printf (plan.function_ordinal) : module_symbol + "_resume", resume_type);
		CApi.set_linkage (resume, module_symbol == null ? CApi.Linkage.INTERNAL : CApi.Linkage.EXTERNAL);
		CApi.set_function_call_conv (resume, CApi.CallConv.C);
		CApi.TypeRef[] destroy_parameters = {
			runtime.pointer, runtime.i32
		};
		destroy_type = CApi.function_type (runtime.nothing, destroy_parameters, 2, 0);
		destroy = CApi.add_function (artifact.module, module_symbol == null ? "astra.task.destroy.%d".printf (plan.function_ordinal) : module_symbol + "_destroy", destroy_type);
		CApi.set_linkage (destroy, module_symbol == null ? CApi.Linkage.INTERNAL : CApi.Linkage.EXTERNAL);
		CApi.set_function_call_conv (destroy, CApi.CallConv.C);
		factory_type = factory_signature (types, signature);
		factory = CApi.add_function (artifact.module, module_symbol ?? "astra.task.create.%d".printf (plan.function_ordinal), factory_type);
		CApi.set_linkage (factory, module_symbol == null ? CApi.Linkage.INTERNAL : CApi.Linkage.EXTERNAL);
		CApi.set_function_call_conv (factory, LlvmLowering.CALL_CONVENTION);
		checked_factory = CApi.add_function (artifact.module, module_symbol == null ? "astra.task.create.checked.%d".printf (plan.function_ordinal) : module_symbol + "_checked", factory_type);
		CApi.set_linkage (checked_factory, module_symbol == null ? CApi.Linkage.INTERNAL : CApi.Linkage.EXTERNAL);
		CApi.set_function_call_conv (checked_factory, LlvmLowering.CALL_CONVENTION);
		if (module_symbol != null) {
			artifact.native_modules.add (new LlvmNativeModuleBinding (resume, resume_type, module_symbol + "_resume", false, CApi.CallConv.C));
			artifact.native_modules.add (new LlvmNativeModuleBinding (destroy, destroy_type, module_symbol + "_destroy", false, CApi.CallConv.C));
			artifact.native_modules.add (new LlvmNativeModuleBinding (checked_factory, factory_type, module_symbol + "_checked", false));
		}
		build_factory (types, signature, sums, factory, false);
		build_factory (types, signature, sums, checked_factory, true);
		resume_blocks = new CApi.BasicBlockRef[plan.state_count];
	}
	private void build_factory(LlvmTypeMapper types, NativeSignature signature, LlvmSumRegistry? sums, CApi.ValueRef target_factory, bool checked_admission) throws LlvmError {
		int capture_count = (int) signature.parameters.length;
		var builder = CApi.create_builder_in_context (artifact.context);
		// Destroy is emitted from exact owner plans once class callbacks exist.
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, target_factory, "capture"));
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact ();
		}
		uint alignment = CApi.abi_alignment_of_type (artifact.class_target.enum_target_data (artifact), frame_type);
		CApi.TypeRef[] create_parameters = {
			runtime.i64, runtime.i64, runtime.pointer, runtime.pointer, runtime.pointer
		};
		CApi.ValueRef[] create_arguments = {
			CApi.size_of (frame_type), CApi.const_int (runtime.i64, alignment, 0), resume, destroy, CApi.get_param (target_factory, capture_count)
		};
		var default_backing = CApi.append_basic_block_in_context (artifact.context, target_factory, "frame.default");
		var selected_backing = CApi.append_basic_block_in_context (artifact.context, target_factory, "frame.context");
		var captured = CApi.append_basic_block_in_context (artifact.context, target_factory, "frame.admitted");
		var descriptor = CApi.get_param (target_factory, capture_count + 1);
		var ordinary = CApi.build_icmp (builder, CApi.IntPredicate.EQ, descriptor, CApi.const_null (runtime.pointer), "default.backing");
		var branch = CApi.build_cond_br (builder, ordinary, default_backing, selected_backing);
		artifact.class_branches.add (new LlvmClassBranchBinding (branch, ordinary, default_backing, selected_backing));
		CApi.position_builder_at_end (builder, default_backing);
		CApi.ValueRef default_task;
		if (checked_admission) {
			default_task = runtime.call (builder, "astra_async_try_new_allocated", runtime.pointer, new CApi.TypeRef[] { runtime.i64, runtime.i64, runtime.pointer, runtime.pointer, runtime.pointer, runtime.pointer, runtime.pointer }, new CApi.ValueRef[] { create_arguments[0], create_arguments[1], resume, destroy, create_arguments[4], CApi.const_null (runtime.pointer), CApi.get_param (target_factory, capture_count + 2) }, "cold.default.task");
		} else {
			default_task = runtime.call (builder, "astra_async_new", runtime.pointer, create_parameters, create_arguments, "cold.default.task");
		}
		CApi.build_br (builder, captured);
		CApi.position_builder_at_end (builder, selected_backing);
		var selected_task = runtime.call (builder, checked_admission ? "astra_async_try_new_allocated" : "astra_async_new_allocated", runtime.pointer,
			new CApi.TypeRef[] { runtime.i64, runtime.i64, runtime.pointer, runtime.pointer, runtime.pointer, runtime.pointer, runtime.pointer },
			new CApi.ValueRef[] { create_arguments[0], create_arguments[1], resume, destroy, create_arguments[4], descriptor, CApi.get_param (target_factory, capture_count + 2) }, "cold.context.task");
		CApi.build_br (builder, captured);
		CApi.position_builder_at_end (builder, captured);
		var created = CApi.build_phi (builder, runtime.pointer, "cold.task");
		CApi.ValueRef[] choices = {
			default_task, selected_task
		};
		CApi.BasicBlockRef[] predecessors = {
			default_backing, selected_backing
		};
		CApi.add_incoming (created, choices, predecessors, 2);
		artifact.class_phis.add (new LlvmClassPhiBinding (created, choices, predecessors));
		if (checked_admission) {
			var refused = CApi.append_basic_block_in_context (artifact.context, target_factory, "frame.refused");
			var published = CApi.append_basic_block_in_context (artifact.context, target_factory, "frame.captures");
			var empty = CApi.const_null (runtime.pointer);
			var failed = CApi.build_icmp (builder, CApi.IntPredicate.EQ, created, empty, "frame.admission.refused");
			artifact.class_values.add (new LlvmClassValueBinding (failed, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { created, empty }, "checked frame exact refusal predicate", -1, (int) CApi.IntPredicate.EQ));
			var guarded = CApi.build_cond_br (builder, failed, refused, published);
			artifact.class_branches.add (new LlvmClassBranchBinding (guarded, failed, refused, published));
			CApi.position_builder_at_end (builder, refused);
			CApi.build_ret (builder, empty);
			CApi.position_builder_at_end (builder, published);
		}
		runtime.call (builder, "astra_async_require_provider", runtime.nothing, new CApi.TypeRef[] { runtime.pointer, runtime.i32 }, new CApi.ValueRef[] { created, CApi.const_int (runtime.i32, (uint) plan.provider, 0) });
		CApi.TypeRef[] one_pointer = {
			runtime.pointer
		};
		CApi.ValueRef[] created_argument = {
			created
		};
		var environment = runtime.call (builder, "astra_async_data", runtime.pointer, one_pointer, created_argument, "cold.frame");
		CApi.build_store (builder, CApi.const_null (frame_type), environment);
		for (int p = 0; p < signature.parameters.length; p++) {
			var address = field_address (builder, environment, (uint) p + 1);
			var input = CApi.get_param (target_factory, p);
			var stored = CApi.build_store (builder, input, address);
			artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { input, address }, "cold captured parameter publication"));
		}
		for (uint o = 0; o < plan.owner_count; o++) {
			var capture = plan.owner (o);
			if (capture.capture_first_leaf < 0) {
				continue;
			}
			var pointer = CApi.get_param (target_factory, capture.capture_first_leaf);
			var address = field_address (builder, environment, owner_field (o));
			var stored = CApi.build_store (builder, pointer, address);
			artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { pointer, address }, "cold committed Resource capture"));
			var flag = field_address (builder, environment, owner_field (o) + 1);
			var live = CApi.build_icmp (builder, CApi.IntPredicate.NE, pointer, CApi.const_null (runtime.pointer), "capture.owner.live");
			var marked = CApi.build_store (builder, live, flag);
			artifact.class_values.add (new LlvmClassValueBinding (marked, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { live, flag }, "cold committed Resource liveness"));
		}
		for (uint b = 0; b < plan.buffer_count; b++) {
			var capture = plan.buffer (b);
			if (capture.capture_first_leaf < 0) {
				continue;
			}
			var empty = CApi.const_null (types.buffer_carrier ());
			var base_value = CApi.get_param (target_factory, capture.capture_first_leaf);
			var pair = CApi.build_insert_value (builder, empty, base_value, 0, "capture.buffer.base");
			artifact.class_values.add (new LlvmClassValueBinding (pair, CApi.Opcode.INSERT_VALUE, types.buffer_carrier (), new CApi.ValueRef[] { empty, base_value }, "exact cold buffer base", 0));
			var count_value = CApi.get_param (target_factory, capture.capture_first_leaf + 1);
			var complete = CApi.build_insert_value (builder, pair, count_value, 1, "capture.buffer.count");
			artifact.class_values.add (new LlvmClassValueBinding (complete, CApi.Opcode.INSERT_VALUE, types.buffer_carrier (), new CApi.ValueRef[] { pair, count_value }, "exact cold buffer count", 1));
			pair = complete;
			var address = field_address (builder, environment, buffer_field (b));
			var stored = CApi.build_store (builder, pair, address);
			artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { pair, address }, "cold committed complete buffer capture"));
		}
		for (uint e = 0; e < plan.enum_count; e++) {
			var capture = plan.enum_slot (e);
			if (capture.capture_first_leaf < 0) {
				continue;
			}
			var address = field_address (builder, environment, enum_field (e));
			sums.copy (builder, sums.lookup (capture.identity), address, CApi.get_param (target_factory, capture.capture_first_leaf));
			var parameter = field_address (builder, environment, (uint) capture.capture_first_leaf + 1);
			var stored = CApi.build_store (builder, address, parameter);
			artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { address, parameter }, "cold captured complete enum carrier address"));
			if (capture.owning) {
				var flag = field_address (builder, environment, enum_field (e) + 1);
				var live = CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0);
				var marked = CApi.build_store (builder, live, flag);
				artifact.class_values.add (new LlvmClassValueBinding (marked, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { live, flag }, "cold committed owning enum liveness"));
			}
		}
		CApi.build_ret (builder, created);
		CApi.dispose_builder (builder);
	}

	internal CApi.ValueRef field_address(CApi.BuilderRef builder, CApi.ValueRef base_pointer, uint index) {
		var address = CApi.build_struct_gep (builder, frame_type, base_pointer, index, "task.field.%u".printf (index));
		accesses.add (new LlvmAsyncFieldAccess (address, base_pointer, frame_type, index));
		return address;
	}
	private uint definition_field(int ordinal) throws LlvmError {
		for (uint f = 0; f < plan.field_count; f++) {
			if (plan.field (f).definition == ordinal) {
				return f + 1;
			}
		}
		throw new LlvmError.LOWERING ("async value has no exact persistent frame field");
	}
	internal CApi.ValueRef debug_environment() {
		return backing;
	}
	internal uint debug_value_index(int ordinal) {
		for (uint f = 0; f < plan.field_count; f++) {
			if (plan.field (f).definition == ordinal) {
				return f + 1;
			}
		}
		return uint.MAX;
	}
	internal CApi.ValueRef read(CApi.BuilderRef builder, int ordinal, CApi.TypeRef type) throws LlvmError {
		var address = field_address (builder, backing, definition_field (ordinal));
		var loaded = CApi.build_load (builder, type, address, "task.value.%d".printf (ordinal));
		artifact.class_values.add (new LlvmClassValueBinding (loaded, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { address }, "persistent source definition read"));
		return loaded;
	}
	internal void write(CApi.BuilderRef builder, int ordinal, CApi.ValueRef value) throws LlvmError {
		var address = field_address (builder, backing, definition_field (ordinal));
		var stored = CApi.build_store (builder, value, address);
		artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { value, address }, "persistent source definition publication"));
	}
	internal CApi.ValueRef environment(CApi.BuilderRef builder, CApi.ValueRef task) throws LlvmError {
		return runtime.call (builder, "astra_async_data", runtime.pointer, new CApi.TypeRef[] { runtime.pointer }, new CApi.ValueRef[] { task }, "task.frame");
	}
	internal CApi.ValueRef object_read(CApi.BuilderRef builder, uint ordinal) {
		var address = field_address (builder, backing, 1 + plan.field_count + ordinal);
		var loaded = CApi.build_load (builder, runtime.pointer, address, "frame.object");
		artifact.class_values.add (new LlvmClassValueBinding (loaded, CApi.Opcode.LOAD, runtime.pointer, new CApi.ValueRef[] { address }, "persistent exact heap object"));
		return loaded;
	}
	internal void object_write(CApi.BuilderRef builder, uint ordinal, CApi.ValueRef pointer) {
		var address = field_address (builder, backing, 1 + plan.field_count + ordinal);
		var stored = CApi.build_store (builder, pointer, address);
		artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { pointer, address }, "persistent exact heap allocation association"));
	}
	internal uint owner_field(uint ordinal) {
		return 1 + plan.field_count + plan.object_count + ordinal * 2;
	}
	internal uint buffer_field(uint ordinal) {
		return 1 + plan.field_count + plan.object_count + plan.owner_count * 2 + ordinal;
	}
	internal uint result_live_field() {
		return enum_field (plan.enum_count);
	}
	internal CApi.ValueRef result_address(CApi.BuilderRef builder) {
		return field_address (builder, backing, 0);
	}
	internal void result_initialized(CApi.BuilderRef builder) {
		var live = CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0);
		var address = field_address (builder, backing, result_live_field ());
		var stored = CApi.build_store (builder, live, address);
		artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { live, address }, "exact initialized task success payload before publication"));
	}
	internal uint enum_field(uint ordinal) {
		return storage_field (plan.storage_count) + ordinal * 2;
	}
	internal CApi.ValueRef enum_address(CApi.BuilderRef builder, uint ordinal) {
		return field_address (builder, backing, enum_field (ordinal));
	}
	internal CApi.ValueRef enum_flag(CApi.BuilderRef builder, uint ordinal) {
		return field_address (builder, backing, enum_field (ordinal) + 1);
	}
	internal uint storage_field(uint ordinal) {
		return buffer_field (plan.buffer_count) + ordinal;
	}
	internal CApi.ValueRef storage_address(CApi.BuilderRef builder, uint ordinal) {
		return field_address (builder, backing, storage_field (ordinal));
	}
	internal CApi.ValueRef buffer_address(CApi.BuilderRef builder, uint ordinal) {
		return field_address (builder, backing, buffer_field (ordinal));
	}
	internal void owner_update(CApi.BuilderRef builder, uint ordinal, CApi.ValueRef pointer, bool acquire) {
		var address = field_address (builder, backing, owner_field (ordinal));
		var selected = acquire ? pointer : CApi.const_null (runtime.pointer);
		var stored = CApi.build_store (builder, selected, address);
		owner_writes.add (new LlvmAsyncOwnerWrite (stored));
		artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { selected, address }, "exact frame owner acquisition or disarm"));
		var live = acquire ? CApi.build_icmp (builder, CApi.IntPredicate.NE, pointer, CApi.const_null (runtime.pointer), "frame.owner.live") : CApi.const_null (CApi.int1_type_in_context (artifact.context));
		var flag = field_address (builder, backing, owner_field (ordinal) + 1);
		var published = CApi.build_store (builder, live, flag);
		artifact.class_values.add (new LlvmClassValueBinding (published, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { live, flag }, "exact initialized frame owner liveness"));
	}
	internal CApi.BasicBlockRef enter_wait(CApi.BuilderRef builder, CApi.ValueRef child, bool discard, int block, int position, out CApi.BasicBlockRef failure, bool payload = false, CApi.ValueRef bridge = (CApi.ValueRef) null) throws LlvmError {
		uint selected = 0;
		for (uint s = 1; s < plan.state_count; s++) {
			if (plan.state (s).block == block && plan.state (s).position == position) {
				selected = s;
				break;
			}
		}
		if (selected == 0) {
			throw new LlvmError.LOWERING ("await lost its exact resume-state association");
		}
		var setter = runtime.call (builder, "astra_async_set_pc", runtime.nothing, new CApi.TypeRef[] { runtime.pointer, runtime.i32 }, new CApi.ValueRef[] { task, CApi.const_int (runtime.i32, selected, 0) });
		NativeAsyncWait? wait = null;
		for (uint w = 0; w < plan.wait_count; w++) {
			if (plan.wait (w).block == block && plan.wait (w).position == position) {
				wait = plan.wait (w);
			}
		}
		if (wait == null || (wait.bridge_definition >= 0) != ((void*) bridge != null)) {
			throw new LlvmError.LOWERING ("wait lost exact native bridge/ordinary observation authority");
		}
		var admitted = (void*) bridge == null ? runtime.call(builder, "astra_async_wait", runtime.i32, new CApi.TypeRef[] { runtime.pointer, runtime.pointer, runtime.i32 }, new CApi.ValueRef[] { task, child, CApi.const_int (runtime.i32, discard ? 1 : 0, 0) }, "await.admission") : runtime.call (builder, "astra_async_bridge_wait", runtime.i32, new CApi.TypeRef[] { runtime.pointer, runtime.pointer, runtime.pointer, runtime.i32 }, new CApi.ValueRef[] { task, child, bridge, CApi.const_int (runtime.i32, discard ? 1 : 0, 0) }, "bridge.admission");
		var suspended = CApi.append_basic_block_in_context (artifact.context, resume, "await.suspended");
		failure = CApi.append_basic_block_in_context (artifact.context, resume, "await.admission.failure");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, admitted, CApi.const_null (runtime.i32), "await.admitted"), suspended, failure);
		CApi.position_builder_at_end (builder, suspended);
		var returned = CApi.build_ret_void (builder);
		continuations.add (new LlvmAsyncContinuation (setter, admitted, returned, resume_blocks[selected], failure, task, selected, true));
		return resume_blocks[selected];
	}
	internal void raise(CApi.BuilderRef builder, CApi.ValueRef exception) throws LlvmError {
		complete (builder, 6, exception);
		CApi.build_ret_void (builder);
	}
	internal void begin(CApi.BuilderRef builder, CApi.BasicBlockRef entry, CApi.BasicBlockRef initial) throws LlvmError {
		task = CApi.get_param (resume, 0);
		CApi.position_builder_at_end (builder, entry);
		CApi.TypeRef[] pointer_parameter = {
			runtime.pointer
		};
		CApi.ValueRef[] argument = {
			task
		};
		backing = runtime.call (builder, "astra_async_data", runtime.pointer, pointer_parameter, argument, "stable.frame");
		var cancellation = runtime.call (builder, "astra_async_cancel_requested", runtime.i32, pointer_parameter, argument, "cancel.requested");
		var cancelled = CApi.append_basic_block_in_context (artifact.context, resume, "cancel.drain");
		cancel_entry = cancelled;
		var select = CApi.append_basic_block_in_context (artifact.context, resume, "state.select");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.NE, cancellation, CApi.const_null (runtime.i32), "cancel.check"), cancelled, select);
		CApi.position_builder_at_end (builder, cancelled);
		var drained = runtime.call (builder, "astra_async_cancel_scope", runtime.i32, pointer_parameter, argument, "children.drained");
		cancel_admission = drained;
		var publish = CApi.append_basic_block_in_context (artifact.context, resume, "cancel.publish");
		var pending = CApi.append_basic_block_in_context (artifact.context, resume, "cancel.pending");
		cancel_pending = pending;
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.NE, drained, CApi.const_null (runtime.i32), "drain.check"), publish, pending);
		CApi.position_builder_at_end (builder, publish);
		complete (builder, 7, CApi.const_null (runtime.pointer));
		CApi.build_ret_void (builder);
		CApi.position_builder_at_end (builder, pending);
		CApi.build_ret_void (builder);
		CApi.position_builder_at_end (builder, select);
		pc_read = runtime.call (builder, "astra_async_pc", runtime.i32, pointer_parameter, argument, "task.pc");
		fallback = CApi.append_basic_block_in_context (artifact.context, resume, "invalid.state");
		resume_blocks[0] = initial;
		for (uint s = 1; s < plan.state_count; s++) {
			resume_blocks[s] = CApi.append_basic_block_in_context (artifact.context, resume, "resume.%u".printf (s));
		}
		dispatch = CApi.build_switch (builder, pc_read, fallback, plan.state_count);
		for (uint s = 0; s < plan.state_count; s++) {
			CApi.add_case (dispatch, CApi.const_int (runtime.i32, s, 0), resume_blocks[s]);
		}
		CApi.position_builder_at_end (builder, fallback);
		runtime.trap (builder);
	}
	internal CApi.BasicBlockRef suspend(CApi.BuilderRef builder, CApi.ValueRef ticks, bool signed_ticks, int block, int position, out CApi.BasicBlockRef failure, bool payload = false) throws LlvmError {
		uint selected = 0;
		for (uint s = 1; s < plan.state_count; s++) {
			if (plan.state (s).block == block && plan.state (s).position == position) {
				selected = s;
				break;
			}
		}
		if (selected == 0) {
			throw new LlvmError.LOWERING ("suspension has no exact native resume state");
		}
		if (payload != (plan.state (selected).payload_definition >= 0)) {
			throw new LlvmError.LOWERING ("payload suspension differs from exact native owner hold plan");
		}
		if (payload) {
			uint owner = (uint) plan.state (selected).payload_owner;
			var address = field_address (builder, backing, owner_field (owner));
			var stored = CApi.build_load (builder, runtime.pointer, address, "payload.retained.owner");
			artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.LOAD, runtime.pointer, new CApi.ValueRef[] { address }, "payload suspension retains exact frame owner"));
			var exact = CApi.build_icmp (builder, CApi.IntPredicate.EQ, stored, ticks, "payload.owner.identity");
			artifact.class_values.add (new LlvmClassValueBinding (exact, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { stored, ticks }, "payload pointer matches retained frame owner", -1, (int) CApi.IntPredicate.EQ));
			var valid = CApi.append_basic_block_in_context (artifact.context, resume, "payload.owner.valid");
			var invalid = CApi.append_basic_block_in_context (artifact.context, resume, "payload.owner.invalid");
			var guard = CApi.build_cond_br (builder, exact, valid, invalid);
			artifact.class_branches.add (new LlvmClassBranchBinding (guard, exact, valid, invalid));
			CApi.position_builder_at_end (builder, invalid);
			runtime.trap (builder);
			CApi.position_builder_at_end (builder, valid);
			var flag_address = field_address (builder, backing, owner_field (owner) + 1);
			var bool_type = CApi.int1_type_in_context (artifact.context);
			var flag = CApi.build_load (builder, bool_type, flag_address, "payload.retained.live");
			artifact.class_values.add (new LlvmClassValueBinding (flag, CApi.Opcode.LOAD, bool_type, new CApi.ValueRef[] { flag_address }, "payload frame owner liveness"));
			var empty = CApi.const_null (runtime.pointer);
			var nonnull = CApi.build_icmp (builder, CApi.IntPredicate.NE, ticks, empty, "payload.nonnull");
			artifact.class_values.add (new LlvmClassValueBinding (nonnull, CApi.Opcode.ICMP, bool_type, new CApi.ValueRef[] { ticks, empty }, "payload nullable owner disposition", -1, (int) CApi.IntPredicate.NE));
			var live = CApi.build_icmp (builder, CApi.IntPredicate.EQ, flag, nonnull, "payload.owner.liveness");
			artifact.class_values.add (new LlvmClassValueBinding (live, CApi.Opcode.ICMP, bool_type, new CApi.ValueRef[] { flag, nonnull }, "payload owner retains initialized destruction responsibility", -1, (int) CApi.IntPredicate.EQ));
			var ready = CApi.append_basic_block_in_context (artifact.context, resume, "payload.owner.ready");
			guard = CApi.build_cond_br (builder, live, ready, invalid);
			artifact.class_branches.add (new LlvmClassBranchBinding (guard, live, ready, invalid));
			CApi.position_builder_at_end (builder, ready);
		}
		CApi.TypeRef[] pc_parameters = {
			runtime.pointer, runtime.i32
		};
		CApi.ValueRef[] pc_arguments = {
			task, CApi.const_int (runtime.i32, selected, 0)
		};
		var setter = runtime.call (builder, "astra_async_set_pc", runtime.nothing, pc_parameters, pc_arguments);
		var duration = payload ? ticks : signed_ticks ? CApi.build_sext(builder, ticks, runtime.i64, "logical.ticks") : CApi.build_zext (builder, ticks, runtime.i64, "logical.ticks");
		if (!payload && plan.provider == Astra.Source.AsyncProviderKind.LINUX_IO_URING && (void*) CApi.is_instruction (duration) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (duration, signed_ticks ? CApi.Opcode.SEXT : CApi.Opcode.ZEXT, runtime.i64, new CApi.ValueRef[] { ticks }, "Linux duration evaluates its exact signed or unsigned source operand once"));
		}
		CApi.TypeRef[] delay_parameters = {
			runtime.pointer, payload ? runtime.pointer : runtime.i64
		};
		CApi.ValueRef[] delay_arguments = {
			task, duration
		};
		var admitted = runtime.call (builder, payload ? "astra_async_linux_payload" : plan.provider == Astra.Source.AsyncProviderKind.LINUX_IO_URING ? "astra_async_linux_delay_ms" : "astra_async_delay", runtime.i32, delay_parameters, delay_arguments, "delay.registered");
		failure = CApi.append_basic_block_in_context (artifact.context, resume, "delay.refused");
		var waiting = CApi.append_basic_block_in_context (artifact.context, resume, "delay.suspended");
		if (plan.provider == Astra.Source.AsyncProviderKind.LINUX_IO_URING) {
			var zero = CApi.const_null (runtime.i32);
			var accepted = CApi.build_icmp (builder, CApi.IntPredicate.NE, admitted, zero, "delay.check");
			artifact.class_values.add (new LlvmClassValueBinding (accepted, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { admitted, zero }, "Linux admission checks exact provider status", -1, (int) CApi.IntPredicate.NE));
			var admission = CApi.build_cond_br (builder, accepted, waiting, failure);
			artifact.class_branches.add (new LlvmClassBranchBinding (admission, accepted, waiting, failure));
		} else {
			// Preserve the qualified virtual instruction and name emission order.
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.NE, admitted, CApi.const_null (runtime.i32), "delay.check"), waiting, failure);
		}
		CApi.position_builder_at_end (builder, waiting);
		var returned = CApi.build_ret_void (builder);
		continuations.add (new LlvmAsyncContinuation (setter, admitted, returned, resume_blocks[selected], failure, task, selected, false));
		return resume_blocks[selected];
	}
	internal CApi.ValueRef delay_result(CApi.BuilderRef builder, int block, int position) throws LlvmError {
		uint selected = 0;
		for (uint s = 1; s < plan.state_count; s++) {
			if (plan.state (s).block == block && plan.state (s).position == position) {
				selected = s;
				break;
			}
		}
		if (selected == 0 || plan.provider != Astra.Source.AsyncProviderKind.LINUX_IO_URING) {
			throw new LlvmError.LOWERING ("Linux completion result lost its original suspension");
		}
		return runtime.call (builder, "astra_async_linux_delay_result", runtime.i32, new CApi.TypeRef[] { runtime.pointer, runtime.i32 }, new CApi.ValueRef[] { task, CApi.const_int (runtime.i32, selected, 0) }, "delay.completion.status");
	}
	private void complete(CApi.BuilderRef builder, int phase, CApi.ValueRef exception) throws LlvmError {
		CApi.TypeRef[] parameters = {
			runtime.pointer, runtime.i32, runtime.pointer
		};
		CApi.ValueRef[] arguments = {
			task, CApi.const_int (runtime.i32, phase, 0), exception
		};
		runtime.call (builder, "astra_async_complete", runtime.nothing, parameters, arguments);
	}
	internal void succeed(CApi.BuilderRef builder, CApi.ValueRef result) throws LlvmError {
		if ((void*) result != null) {
			var address = result_address (builder);
			var stored = CApi.build_store (builder, result, address);
			artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, runtime.nothing, new CApi.ValueRef[] { result, address }, "exact complete task success payload publication"));
			result_initialized (builder);
		}
		complete (builder, 5, CApi.const_null (runtime.pointer));
		CApi.build_ret_void (builder);
	}
	internal CApi.BasicBlockRef[] lifetime_entries() throws LlvmError {
		verify_continuations ();
		return new CApi.BasicBlockRef[] {
				   original_resume_entry, original_destroy_entry
		};
	}
	internal CApi.BasicBlockRef[] lifetime_successors(CApi.BasicBlockRef block) throws LlvmError {
		verify_continuations ();
		var function = CApi.block_parent (block);
		if ((void*) function != (void*) resume && (void*) function != (void*) destroy) {
			throw new LlvmError.VERIFICATION ("coroutine lifetime graph cannot import an unrelated block");
		}
		var end = CApi.block_terminator (block);
		if ((void*) end == (void*) dispatch) {
			return new CApi.BasicBlockRef[] {
					   resume_blocks[0]
			};
		}
		if (CApi.opcode (end) == CApi.Opcode.RET && (void*) function != (void*) destroy) {
			foreach (var edge in continuations) {
				if ((void*) edge.suspension_return () == (void*) end) {
					return new CApi.BasicBlockRef[] {
							   edge.next_state (), original_cancel
					};
				}
			}
			return new CApi.BasicBlockRef[] {
					   (void*) block == (void*) cancel_pending ? original_cancel : original_destroy_entry
			};
		}
		var result = new CApi.BasicBlockRef[CApi.successor_count (end)];
		for (uint e = 0; e < result.length; e++) {
			result[e] = CApi.successor (end, e);
		}
		return result;
	}
	internal void verify_continuations() throws LlvmError {
		if (effects.length == 0 || (void*) resume != (void*) original_resume || (void*) destroy != (void*) original_destroy || (void*) task != (void*) original_task || (void*) CApi.first_block (resume) != (void*) original_resume_entry || (void*) CApi.first_block (destroy) != (void*) original_destroy_entry || (void*) cancel_entry != (void*) original_cancel) {
			throw new LlvmError.VERIFICATION ("immutable coroutine identity, entry or cancellation route changed");
		}
		if (continuation_count + 1 != plan.state_count) {
			throw new LlvmError.VERIFICATION ("coroutine lifetime graph lost a planned suspension");
		}
		var returns = new HashTable<void*, bool> (direct_hash, direct_equal);
		var states = new HashTable<uint, bool> (direct_hash, direct_equal);
		for (uint ordinal = 0; ordinal < continuation_count; ordinal++) {
			var edge = continuation (ordinal);
			uint selected = edge.state ();
			if (selected == 0 || selected >= resume_blocks.length || states.contains (selected) || returns.contains ((void*) edge.suspension_return ())) {
				throw new LlvmError.VERIFICATION ("coroutine lifetime graph repeats or substitutes a planned continuation");
			}
			edge.verify (resume, resume_blocks[selected]);
			states.insert (selected, true);
			returns.insert ((void*) edge.suspension_return (), true);
		}
		for (var block = CApi.first_block (resume); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) != CApi.Opcode.RET || returns.contains ((void*) end)) {
				continue;
			}
			if ((void*) block == (void*) cancel_pending) {
				var drained = drained_children ();
				var drain_branch = CApi.block_terminator (original_cancel);
				var condition = CApi.operand (drain_branch, 0);
				size_t length;
				if ((void*) CApi.first_instruction (block) != (void*) end || CApi.opcode (drain_branch) != CApi.Opcode.BR || CApi.successor_count (drain_branch) != 2 || (void*) CApi.successor (drain_branch, 1) != (void*) block || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.NE || (void*) CApi.operand (condition, 0) != (void*) drained || (void*) CApi.is_constant_int (CApi.operand (condition, 1)) == null || CApi.const_int_zext (CApi.operand (condition, 1)) != 0 || CApi.opcode (drained) != CApi.Opcode.CALL || CApi.value_name (CApi.called_value (drained), out length) != "astra_async_cancel_scope" || CApi.argument_count (drained) != 1 || (void*) CApi.operand (drained, 0) != (void*) task) {
					throw new LlvmError.VERIFICATION ("coroutine pending cancellation lost its actual child-drain guard");
				}
				continue;
			}
			CApi.ValueRef previous = (CApi.ValueRef) null;
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null && (void*) instruction != (void*) end; instruction = CApi.next_instruction (instruction)) {
				previous = instruction;
			}
			size_t length;
			if ((void*) previous == null || CApi.opcode (previous) != CApi.Opcode.CALL || CApi.value_name (CApi.called_value (previous), out length) != "astra_async_complete" || CApi.argument_count (previous) != 3 || (void*) CApi.operand (previous, 0) != (void*) task || (void*) CApi.is_constant_int (CApi.operand (previous, 1)) == null || CApi.const_int_zext (CApi.operand (previous, 1)) < 5 || CApi.const_int_zext (CApi.operand (previous, 1)) > 7) {
				throw new LlvmError.VERIFICATION ("coroutine return lacks actual completion or an exact retained continuation");
			}
			CApi.TypeRef[] parameters = {
				runtime.pointer, runtime.i32, runtime.pointer
			};
			var signature = CApi.function_type (runtime.nothing, parameters, 3, 0);
			var complete = CApi.called_value (previous);
			if ((void*) CApi.is_function (complete) == null || CApi.count_basic_blocks (complete) != 0 || (void*) CApi.global_value_type (complete) != (void*) signature || (void*) CApi.called_function_type (previous) != (void*) signature || CApi.instruction_call_conv (previous) != CApi.CallConv.C || CApi.function_call_conv (complete) != CApi.CallConv.C) {
				throw new LlvmError.VERIFICATION ("coroutine completion lost its exact external runtime ABI");
			}
		}
	}
	internal void verify() throws LlvmError {
		var entries = lifetime_entries ();
		if (lifetime_successors (entries[0]).length != 2) {
			throw new LlvmError.VERIFICATION ("coroutine lifetime entry lost its cancellation/state dispatch");
		}
		int blocks = 0;
		foreach (var code in new CApi.ValueRef[] { factory, checked_factory, resume, destroy }) {
			blocks += (int) CApi.count_basic_blocks (code);
		}
		if (blocks != effects.length) {
			throw new LlvmError.VERIFICATION ("coroutine physical graph gained or lost an unplanned block");
		}
		if (effects.length == 0 || (void*) CApi.global_value_type (destroy) != (void*) destroy_type || CApi.function_call_conv (destroy) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("async destruction lost complete exact signature/convention and effect authority");
		}
		if ((void*) CApi.global_value_type (checked_factory) != (void*) factory_type || CApi.function_call_conv (checked_factory) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("checked frame factory lost exact capture/allocator channels");
		}
		try {
			plan.verify ();
		} catch (NativeAbiError error) {
			throw new LlvmError.VERIFICATION (error.message);
		}
		if ((void*) dispatcher () == null) {
			throw new LlvmError.VERIFICATION ("async frame lost its concrete dispatcher");
		}
		for (uint o = 0; o < owner_write_count; o++) {
			if (CApi.opcode (owner_write (o)) != CApi.Opcode.STORE || CApi.operand_count (owner_write (o)) != 2) {
				throw new LlvmError.VERIFICATION ("async frame owner lost its concrete publication or disarm");
			}
		}
		if ((void*) CApi.global_value_type (resume) != (void*) resume_type || CApi.function_call_conv (resume) != CApi.CallConv.C || (void*) CApi.global_value_type (factory) != (void*) factory_type || CApi.function_call_conv (factory) != LlvmLowering.CALL_CONVENTION || (void*) dispatch == null || CApi.opcode (dispatch) != CApi.Opcode.SWITCH || (void*) CApi.operand (dispatch, 0) != (void*) pc_read || CApi.successor_count (dispatch) != plan.state_count + 1 || (void*) CApi.successor (dispatch, 0) != (void*) fallback) {
			throw new LlvmError.VERIFICATION ("async factory/resume/dispatcher lost exact channel and state authority");
		}
		for (uint s = 0; s < plan.state_count; s++) {
			if (CApi.const_int_zext (CApi.switch_case_value (dispatch, s + 1)) != plan.state (s).pc || (void*) CApi.successor (dispatch, s + 1) != (void*) resume_blocks[s]) {
				throw new LlvmError.VERIFICATION ("async dispatcher resumes a different source state: ordinal=%u tag=%u wanted=%d destination=%s", s, (uint) CApi.const_int_zext (CApi.switch_case_value (dispatch, s + 1)), plan.state (s).pc, ((void*) CApi.successor (dispatch, s + 1) == (void*) resume_blocks[s]).to_string ());
			}
		}
		foreach (var effect in effects) {
			effect.verify ();
		}
		foreach (var access in accesses) {
			access.verify ();
		}
	}
}
}
