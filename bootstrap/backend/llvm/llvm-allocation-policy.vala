// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Backend.LLVM {
// Actual emitted control-flow proof, independent of upstream owner graphs.
// Null construction still holds the exclusive loan until lexical cleanup.
internal class LlvmScopedBackingBinding : Object {
	internal int storage_ordinal;
	private int storage_origin;
	private CApi.ValueRef function;
	private CApi.ValueRef factory;
	private int expected_retirements;
	private GenericArray<void*> retirements = new GenericArray<void*> ();
	private GenericArray<void*> accesses = new GenericArray<void*> ();
	internal LlvmScopedBackingBinding (CApi.ValueRef function, int storage, int ends) {
		this.function = function;
		storage_ordinal = storage_origin = storage;
		expected_retirements = ends;
	}
	internal void acquire(CApi.ValueRef call) throws LlvmError {
		if ((void*) factory != null) {
			throw new LlvmError.LOWERING ("scoped backing has competing emitted factories");
		}
		factory = call;
	}
	internal CApi.ValueRef actual_factory() {
		return factory;
	}
	internal void retire(CApi.ValueRef call) {
		retirements.add ((void*) call);
	}
	internal void access(CApi.ValueRef instruction) {
		accesses.add ((void*) instruction);
	}
	private bool uses_context(CApi.ValueRef instruction) {
		for (uint i = 0; i < CApi.operand_count (instruction); i++) {
			if ((void*) CApi.operand (instruction, i) == (void*) factory) {
				return true;
			}
		}
		return false;
	}
	internal void verify() throws LlvmError {
		if (storage_ordinal != storage_origin) {
			throw new LlvmError.VERIFICATION ("scoped backing lost its original storage identity");
		}
		if ((void*) factory == null || retirements.length != expected_retirements || expected_retirements == 0 || (void*) CApi.block_parent (CApi.instruction_parent (factory)) != (void*) function) {
			throw new LlvmError.VERIFICATION ("scoped backing lost its actual factory and complete lexical cleanup inventory");
		}
		foreach (void* pointer in retirements) {
			var call = (CApi.ValueRef) pointer;
			size_t length;
			if ((void*) CApi.block_parent (CApi.instruction_parent (call)) != (void*) function || CApi.opcode (call) != CApi.Opcode.CALL || CApi.value_name (CApi.called_value (call), out length) != "astra_context17_destroy") {
				throw new LlvmError.VERIFICATION ("scoped backing requires actual null-safe context destruction");
			}
		}
		var blocks = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			blocks.add ((void*) block);
		}
		uint[] entries = new uint[blocks.length];
		entries[0] = 1;
		for (int pass = 0; pass < 2; pass++) {
			bool changed = false;
			do {
				changed = false;
				for (int b = 0; b < blocks.length; b++) {
					uint state = entries[b];
					if (state == 0) {
						continue;
					}
					var block = (CApi.BasicBlockRef) blocks[b];
					for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
						if ((void*) instruction == (void*) factory) {
							if (pass == 1 && state != 1) {
								throw new LlvmError.VERIFICATION ("scoped backing acquisition overlaps a live emitted loan");
							}
							state = 2;
						} else if (retirements.find ((void*) instruction)) {
							if (pass == 1 && state != 2) {
								throw new LlvmError.VERIFICATION ("scoped context cleanup lacks its exact live emitted loan");
							}
							state = 1;
						} else if (pass == 1 && accesses.find ((void*) instruction) && (state & 2) != 0) {
							throw new LlvmError.VERIFICATION ("emitted backing access or destruction overlaps a scoped context loan");
						} else if (pass == 1 && uses_context (instruction)) {
							if (state != 2) {
								throw new LlvmError.VERIFICATION ("scoped context use lacks its exact live emitted loan");
							}
							var opcode = CApi.opcode (instruction);
							if (opcode != CApi.Opcode.CALL && opcode != CApi.Opcode.ICMP || opcode == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) factory) {
								throw new LlvmError.VERIFICATION ("emitted scoped controller escaped through storage, return or an alias");
							}
							if (opcode == CApi.Opcode.CALL) {
								size_t length;
								if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_context17_destroy") {
									throw new LlvmError.VERIFICATION ("scoped context has an unregistered emitted retirement");
								}
							}
						}
					}
					var end = CApi.block_terminator (block);
					if (pass == 1 && CApi.opcode (end) == CApi.Opcode.RET && state != 1) {
						throw new LlvmError.VERIFICATION ("emitted return escapes an unretired scoped backing loan");
					}
					if (pass == 0) {
						for (uint s = 0; s < CApi.successor_count (end); s++) {
							void* next = (void*) CApi.successor (end, s);
							for (int n = 0; n < blocks.length; n++) {
								if (blocks[n] == next) {
									uint joined = entries[n] | state;
									if (joined != entries[n]) {
										entries[n] = joined;
										changed = true;
									}
								}
							}
						}
					}
				}
			} while (changed);
		}
	}
}
internal class LlvmPodLayoutBinding : Object {
	private PodRepresentation policy;
	private CApi.TypeRef layout;
	private CApi.TypeRef[] fields;
	internal LlvmPodLayoutBinding (PodRepresentation policy, CApi.TypeRef layout, CApi.ContextRef context) {
		this.policy = policy.copy ();
		this.layout = layout;
		fields = new CApi.TypeRef[policy.field_types.length];
		for (int i = 0; i < fields.length; i++) {
			string type = policy.field_types[i];
			fields[i] = type == "f32" ? CApi.float_type_in_context (context) : type == "f64" ? CApi.double_type_in_context (context) : CApi.int_type_in_context (context, PodRepresentation.width (type) * 8);
		}
	}
	internal void verify(CApi.TargetDataRef data) throws LlvmError {
		if (!policy.valid () || CApi.pointer_size (data) != 8 || CApi.is_packed_struct (layout) != 0 || CApi.count_struct_element_types (layout) != fields.length || CApi.abi_size_of_type (data, layout) != policy.size () || CApi.abi_alignment_of_type (data, layout) != policy.alignment ()) {
			throw new LlvmError.VERIFICATION ("Repr(C) lost its admitted natural LP64 size, padding or alignment");
		}
		for (uint i = 0; i < fields.length; i++) {
			if ((void*) CApi.struct_type_at_index (layout, i) != (void*) fields[i] || CApi.offset_of_element (data, layout, i) != policy.offset (i)) {
				throw new LlvmError.VERIFICATION ("Repr(C) field lost its admitted scalar type or C offset");
			}
		}
	}
}
internal class LlvmPolicyGlobalBinding : Object {
	internal CApi.ValueRef value;
	private CApi.TypeRef type;
	private CApi.ValueRef initializer;
	private uint alignment;
	internal LlvmPolicyGlobalBinding (CApi.ValueRef value, CApi.TypeRef type, CApi.ValueRef initializer, uint alignment) {
		this.value = value;
		this.type = type;
		this.initializer = initializer;
		this.alignment = alignment;
	}
	internal void verify() throws LlvmError {
		if ((void*) CApi.global_value_type (value) != (void*) type || (void*) CApi.get_initializer (value) != (void*) initializer || CApi.get_alignment (value) != alignment || CApi.is_global_constant (value) != 0 || CApi.get_linkage (value) != CApi.Linkage.LINK_ONCE_ODR) {
			throw new LlvmError.VERIFICATION ("allocation domain lost its exact backing/table/callback/layout initializer");
		}
	}
}

internal class LlvmPolicyAllocation : Object {
	private LlvmModuleArtifact artifact;
	private CApi.TypeRef pointer;
	private CApi.TypeRef size;
	private CApi.TypeRef word;
	internal LlvmPolicyAllocation (LlvmModuleArtifact artifact) {
		this.artifact = artifact;
		pointer = CApi.pointer_type_in_context (artifact.context, 0);
		size = CApi.int_type_in_context (artifact.context, 64);
		word = CApi.int32_type_in_context (artifact.context);
	}
	private CApi.ValueRef integer(uint64 value) {
		return CApi.const_int (size, value, 0);
	}
	internal CApi.ValueRef open_scoped(CApi.BuilderRef builder, CApi.ValueRef backing, CApi.ValueRef length, CApi.ValueRef kind, CApi.ValueRef slots) throws LlvmError {
		CApi.TypeRef[] parameters = {
			pointer, word, word, word
		};
		var type = CApi.function_type (pointer, parameters, parameters.length, 0);
		var target = declaration ("astra_context17_open_scoped", type);
		CApi.ValueRef[] arguments = {
			backing, length, kind, slots
		};
		var call = CApi.build_call (builder, type, target, arguments, arguments.length, "scoped.context");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, type, arguments, CApi.CallConv.C, "exact complete exclusively loaned byte backing and scoped affine context"));
		return call;
	}
	private CApi.ValueRef number(uint value) {
		return CApi.const_int (word, value, 0);
	}
	private CApi.ValueRef global(string name, CApi.TypeRef type, CApi.ValueRef initializer, uint alignment) throws LlvmError {
		if ((void*) CApi.named_global (artifact.module, name) != null || (void*) CApi.named_function (artifact.module, name) != null) {
			throw new LlvmError.LOWERING ("allocation global collides with an existing symbol");
		}
		var value = CApi.add_global (artifact.module, type, name);
		CApi.set_linkage (value, CApi.Linkage.LINK_ONCE_ODR);
		CApi.set_alignment (value, alignment);
		CApi.set_initializer (value, initializer);
		artifact.allocation_globals.add (new LlvmPolicyGlobalBinding (value, type, initializer, alignment));
		return value;
	}
	internal CApi.ValueRef declaration(string name, CApi.TypeRef type) throws LlvmError {
		var value = CApi.named_function (artifact.module, name);
		if ((void*) value == null) {
			value = CApi.add_function (artifact.module, name, type);
			CApi.set_linkage (value, CApi.Linkage.EXTERNAL);
			CApi.set_function_call_conv (value, CApi.CallConv.C);
		}
		if ((void*) CApi.global_value_type (value) != (void*) type || CApi.function_call_conv (value) != CApi.CallConv.C || CApi.count_basic_blocks (value) != 0) {
			throw new LlvmError.LOWERING ("allocator provider lost its exact C ABI declaration");
		}
		CApi.add_attribute (value, uint.MAX, CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("nobuiltin", 9), 0));
		return value;
	}
	private CApi.ValueRef callback(string name, bool allocation) throws LlvmError {
		var parameters = allocation ? new CApi.TypeRef[] {
			word, word, word, word
		} : new CApi.TypeRef[] {
			word, word
		};
		var type = CApi.function_type (allocation ? word : CApi.void_type_in_context (artifact.context), parameters, parameters.length, 0);
		var value = CApi.named_function (artifact.module, name);
		if ((void*) value == null || (void*) CApi.global_value_type (value) != (void*) type || CApi.function_call_conv (value) != CApi.CallConv.C) {
			throw new LlvmError.LOWERING ("custom allocation callback lost its exact admitted scalar C export");
		}
		return value;
	}
	internal CApi.ValueRef domain(AllocationPolicy policy) throws LlvmError {
		if (!policy.valid ()) {
			throw new LlvmError.LOWERING ("invalid original allocation policy");
		}
		string key = policy.domain_identity;
		if (artifact.allocation_domains.contains (key)) {
			return (CApi.ValueRef) artifact.allocation_domains.lookup (key);
		}
		string prefix = "astra_alloc12_domain_" + key;
		var backing = CApi.const_null (pointer);
		var blocks = backing;
		var placement = backing;
		var released = backing;
		var heap_allocate = backing;
		var heap_release = backing;
		if (policy.kind != AllocationKind.HEAP) {
			var bytes = CApi.array_type (CApi.int_type_in_context (artifact.context, 8), policy.capacity);
			backing = global (prefix + "_bytes", bytes, CApi.const_null (bytes), 4096);
			CApi.TypeRef[] fields = {
				size, size, size, size, word
			};
			var block = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
			var table = CApi.array_type (block, policy.blocks);
			blocks = global (prefix + "_blocks", table, CApi.const_null (table), 8);
			if (policy.kind == AllocationKind.CUSTOM) {
				placement = callback (policy.allocate_hook, true);
				released = callback (policy.release_hook, false);
			}
		} else {
			artifact.requires_policy_heap = true;
			CApi.TypeRef[] allocation_parameters = {
				size, word
			};
			var allocate_type = CApi.function_type (pointer, allocation_parameters, allocation_parameters.length, 0);
			var release_type = CApi.function_type (CApi.void_type_in_context (artifact.context), &pointer, 1, 0);
			heap_allocate = declaration ("astra_alloc12_heap_allocate", allocate_type);
			heap_release = declaration ("astra_alloc12_heap_release", release_type);
		}
		CApi.TypeRef[] types = {
			pointer, pointer, size, size, size, size, size, size, size, size, size, word, word, word, pointer, pointer, pointer, pointer, pointer
		};
		var layout = CApi.struct_type_in_context (artifact.context, types, types.length, 0);
		CApi.ValueRef[] values = {
			backing, blocks, integer (policy.capacity), integer (policy.blocks), integer (0), integer (0), integer (0), integer (0), integer (0), integer (0), integer (0), number ((uint) policy.kind), number (0), number (0), placement, released, heap_allocate, heap_release, CApi.const_null (pointer)
		};
		var initial = CApi.const_struct (artifact.context, values, values.length, 0);
		var value = global (prefix, layout, initial, 8);
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		var data = artifact.class_target.enum_target_data (artifact);
		if (CApi.pointer_size (data) != 8 || CApi.abi_size_of_type (data, layout) != 144 || CApi.abi_alignment_of_type (data, layout) != 8 || CApi.offset_of_element (data, layout, 11) != 88 || CApi.offset_of_element (data, layout, 14) != 104) {
			throw new LlvmError.TARGET ("allocator domain does not match its independently qualified 64-bit physical ABI");
		}
		artifact.allocation_domains.insert (key, (void*) value);
		artifact.requires_policy_runtime = true;
		return value;
	}
	internal CApi.ValueRef tag(string class_name, string role) throws LlvmError {
		string canonical = class_name + "/" + role;
		string digest = Checksum.compute_for_string (ChecksumType.SHA256, canonical).substring (0, 16);
		if (digest == "0000000000000000") {
			digest = "0000000000000001";
		}
		var previous = artifact.allocation_tags.lookup (digest);
		if (previous != null && previous != canonical) {
			throw new LlvmError.LOWERING ("allocation type/release identity collision");
		}
		artifact.allocation_tags.insert (digest, canonical);
		uint64 result = 0;
		for (int i = 0; i < digest.length; i++) {
			char c = digest[i];
			result = (result << 4) | (uint64) (c <= '9' ? c - '0' : c - 'a' + 10);
		}
		return integer (result == 0 ? 1 : result);
	}
	internal CApi.ValueRef frame_descriptor(CApi.BuilderRef builder, string mode) throws LlvmError {
		if (mode != "owned-affine" && mode != "owned-transfer" && mode != "owned-concurrent" && mode != "scoped-affine") {
			throw new LlvmError.LOWERING ("task frame lost exact backing capability");
		}
		CApi.TypeRef[] parameters = {
			word
		};
		var type = CApi.function_type (pointer, parameters, parameters.length, 0);
		var target = declaration ("astra_context17_frame_descriptor", type);
		CApi.ValueRef[] arguments = {
			number (mode == "scoped-affine" ? 3 : mode == "owned-concurrent" ? 2 : mode == "owned-transfer" ? 1 : 0)
		};
		var call = CApi.build_call (builder, type, target, arguments, 1, "frame.allocator.contract");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, type, arguments, CApi.CallConv.C, "exact checked task frame allocator version and capability"));
		return call;
	}
	internal CApi.ValueRef origin(CApi.BuilderRef builder, CApi.ValueRef owner, string class_name) throws LlvmError {
		CApi.TypeRef[] parameters = {
			pointer, size
		};
		var type = CApi.function_type (pointer, parameters, parameters.length, 0);
		var target = declaration ("astra_context17_origin", type);
		CApi.ValueRef[] arguments = {
			owner, tag (class_name, "object")
		};
		var call = CApi.build_call (builder, type, target, arguments, arguments.length, "allocation.original.context");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, type, arguments, CApi.CallConv.C, "borrow original allocation context while receiver owner remains live"));
		return call;
	}
	internal CApi.ValueRef allocate(CApi.BuilderRef builder, AllocationPolicy policy, string class_name, string role, CApi.ValueRef count, CApi.TypeRef element, string name, bool object, CApi.ValueRef context = (CApi.ValueRef) null) throws LlvmError {
		if (class_name == "" || (role != "object" && role != "slots" && role != "closure" && role != "buffer")) {
			throw new LlvmError.LOWERING ("allocation request lost its closed type and storage role");
		}
		if (policy.kind == AllocationKind.CONTEXT && (void*) context == null) {
			throw new LlvmError.LOWERING ("context allocation lost its original runtime instance");
		}
		var owner = policy.kind == AllocationKind.CONTEXT ? context : domain (policy);
		var data = artifact.class_target.enum_target_data (artifact);
		uint alignment = CApi.abi_alignment_of_type (data, element);
		if (object) {
			alignment = uint.max (alignment, policy.alignment);
		}
		if (!AllocationPolicy.power_of_two (alignment) || alignment > 4096) {
			throw new LlvmError.TARGET ("allocation has unsupported effective target alignment");
		}
		CApi.TypeRef[] parameters = policy.kind == AllocationKind.CONTEXT ? new CApi.TypeRef[] {
			pointer, size, size, word, size, word
		} : new CApi.TypeRef[] {
			pointer, size, size, word, size
		};
		var type = CApi.function_type (pointer, parameters, parameters.length, 0);
		var target = declaration (policy.kind == AllocationKind.CONTEXT ? "astra_context17_allocate_mode" : "astra_alloc12_allocate", type);
		uint mode = policy.context_mode == "owned-concurrent" ? 2 : policy.context_mode == "owned-transfer" ? 1 : policy.context_mode == "scoped-affine" ? 3 : 0;
		// Scoped native contracts use the same independently qualified target
		// extent, rather than an unevaluated sizeof constant expression.
		var extent = policy.kind == AllocationKind.CONTEXT && mode == 3 ? integer (CApi.abi_size_of_type (data, element)) : CApi.size_of (element);
		CApi.ValueRef[] arguments = policy.kind == AllocationKind.CONTEXT ? new CApi.ValueRef[] {
			owner, count, extent, number (alignment), tag (class_name, role), number (mode)
		} : new CApi.ValueRef[] {
			owner, count, extent, number (alignment), tag (class_name, role)
		};
		var call = CApi.build_call (builder, type, target, arguments, arguments.length, name);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, type, arguments, CApi.CallConv.C, "typed allocation domain/extent/alignment/admission"));
		return call;
	}
	internal CApi.ValueRef release(CApi.BuilderRef builder, AllocationPolicy policy, string class_name, string role, CApi.ValueRef value, string name) throws LlvmError {
		if (class_name == "" || (role != "object" && role != "slots" && role != "closure" && role != "buffer")) {
			throw new LlvmError.LOWERING ("allocation release lost its closed type and storage role");
		}
		if (policy.kind == AllocationKind.CONTEXT) {
			CApi.TypeRef[] context_parameters = {
				pointer, size
			};
			var type = CApi.function_type (word, context_parameters, context_parameters.length, 0);
			var target = declaration ("astra_context17_release_origin_checked", type);
			CApi.ValueRef[] arguments = {
				value, tag (class_name, role)
			};
			var call = CApi.build_call (builder, type, target, arguments, arguments.length, name);
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			artifact.class_calls.add (new LlvmClassCallBinding (call, target, type, arguments, CApi.CallConv.C, "original runtime context/generation and exact destructor/release authority"));
			return call;
		}
		CApi.TypeRef[] parameters = {
			pointer, pointer, size, size
		};
		var type = CApi.function_type (word, parameters, parameters.length, 0);
		var target = declaration ("astra_alloc12_release", type);
		CApi.ValueRef[] arguments = {
			domain (policy), value, tag (class_name, role), integer (0)
		};
		var call = CApi.build_call (builder, type, target, arguments, arguments.length, name);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, type, arguments, CApi.CallConv.C, "original allocation domain and exact type/release authority"));
		return call;
	}
}
}
