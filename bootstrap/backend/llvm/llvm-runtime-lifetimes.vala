// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.NativeAbi;
using Astra.Source;

namespace Astra.Backend.LLVM {
// Detached native borrow authority. Construction consumes verified native
// contracts; only physical LLVM identity and a sealed emitted body survive.
// A copied physical cold-factory/context association. The caller retains
// the scoped backing obligation until the original task is joined or dropped.
internal class LlvmScopedTaskFrame : Object {
	private CApi.ValueRef instruction;
	private CApi.ValueRef context;
	internal CApi.ValueRef backing_context() {
		return context;
	}

	internal void verify_call(CApi.ValueRef actual) throws LlvmError {
		if ((void*) actual != (void*) instruction) {
			throw new LlvmError.VERIFICATION ("scoped task frame lost its original factory instruction");
		}
		verify ();
	}

	private CApi.ValueRef descriptor;
	private LlvmClassCallBinding call;
	private CApi.ValueRef caller;
	internal LlvmScopedTaskFrame (CApi.ValueRef instruction, CApi.ValueRef factory, CApi.TypeRef type, CApi.ValueRef[] arguments) throws LlvmError {
		if (arguments.length < 3) {
			throw new LlvmError.LOWERING ("scoped task frame lost its allocator/context channels");
		}
		this.instruction = instruction;
		context = arguments[arguments.length - 1];
		descriptor = arguments[arguments.length - 2];
		caller = CApi.block_parent (CApi.instruction_parent (instruction));
		call = new LlvmClassCallBinding (instruction, factory, type, arguments, LlvmLowering.CALL_CONVENTION, "scoped task frame factory");
		verify ();
	}

	internal void verify() throws LlvmError {
		call.verify ();
		var llvm_context = CApi.type_context (CApi.type_of (instruction));
		var pointer = CApi.pointer_type_in_context (llvm_context, 0);
		var word = CApi.int32_type_in_context (llvm_context);
		CApi.TypeRef[] parameters = {
			word
		};
		var signature = CApi.function_type (pointer, parameters, 1, 0);
		if ((void*) CApi.block_parent (CApi.instruction_parent (instruction)) != (void*) caller || (void*) CApi.is_instruction (descriptor) == null || CApi.opcode (descriptor) != CApi.Opcode.CALL || CApi.argument_count (descriptor) != 1 || (void*) CApi.called_function_type (descriptor) != (void*) signature || CApi.instruction_call_conv (descriptor) != CApi.CallConv.C || (void*) CApi.is_constant_int (CApi.operand (descriptor, 0)) == null || CApi.const_int_zext (CApi.operand (descriptor, 0)) != 3) {
			throw new LlvmError.VERIFICATION ("scoped task frame lost its exact affine caller-backing descriptor");
		}
		var target = CApi.called_value (descriptor);
		size_t length;
		if ((void*) CApi.is_function (target) == null || CApi.count_basic_blocks (target) != 0 || CApi.value_name (target, out length) != "astra_context17_frame_descriptor" || (void*) CApi.global_value_type (target) != (void*) signature || CApi.function_call_conv (target) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("scoped task frame lost its exact runtime descriptor ABI");
		}
	}

	internal bool context_use(CApi.ValueRef use, uint position) throws LlvmError {
		if ((void*) use != (void*) instruction || position + 1 != CApi.argument_count (instruction)) {
			return false;
		}
		verify ();
		return true;
	}

	internal static bool operation(CApi.ValueRef use, uint position, out bool retires) throws LlvmError {
		retires = false;
		if (CApi.opcode (use) != CApi.Opcode.CALL || (void*) CApi.is_function (CApi.called_value (use)) == null) {
			return false;
		}
		var target = CApi.called_value (use);
		size_t length;
		string name = CApi.value_name (target, out length);
		var llvm_context = CApi.type_context (CApi.type_of (use));
		var pointer = CApi.pointer_type_in_context (llvm_context, 0);
		var word = CApi.int32_type_in_context (llvm_context);
		var nothing = CApi.void_type_in_context (llvm_context);
		CApi.TypeRef[] parameters;
		CApi.TypeRef result;
		if (name == "astra_async_drop" && position == 0) {
			parameters = new CApi.TypeRef[] {
				pointer
			};
			result = nothing;
			retires = true;
		} else if (name == "astra_async_run" && position == 1) {
			parameters = new CApi.TypeRef[] {
				pointer, pointer, pointer
			};
			result = word;
			retires = true;
		} else if (name == "astra_async_start" && position == 1) {
			parameters = new CApi.TypeRef[] {
				pointer, pointer, pointer
			};
			result = word;
		} else if (name == "astra_async_host_cancel" && position == 1) {
			parameters = new CApi.TypeRef[] {
				pointer, pointer
			};
			result = nothing;
		} else if (name == "astra_async_cancel" && position == 0) {
			parameters = new CApi.TypeRef[] {
				pointer
			};
			result = nothing;
		} else if (name == "astra_async_phase" && position == 0) {
			parameters = new CApi.TypeRef[] {
				pointer
			};
			result = word;
		} else {
			return false;
		}
		var signature = CApi.function_type (result, parameters, parameters.length, 0);
		if (CApi.count_basic_blocks (target) != 0 || (void*) CApi.global_value_type (target) != (void*) signature || (void*) CApi.called_function_type (use) != (void*) signature || CApi.argument_count (use) != parameters.length || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.instruction_call_conv (use) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("scoped task observation lost its exact runtime ABI");
		}
		return true;
	}

}
// Native-unit capture authority retains no producer frame layout or body.
// Only exact imported symbols, physical ABI and copied owner channels survive.
internal class LlvmScopedImportedTask : Object {
	internal LlvmScopedOwnedInputs inputs { get; private set; }
	internal LlvmAsyncRecordResult? result { get; private set; }
	internal CApi.ValueRef factory;
	internal CApi.ValueRef checked_factory;
	private LlvmNativeModuleBinding normal;
	private LlvmNativeModuleBinding checked;
	private bool sealed;
	private LlvmScopedImportedTask () {
	}

	internal static LlvmScopedImportedTask? from_native(LlvmModuleArtifact artifact, NativeFunction source, NativeAbiProgram program, LlvmStructRegistry structs, CApi.ValueRef factory, CApi.ValueRef checked_factory, CApi.TypeRef type, string symbol) throws LlvmError {
		if (!LlvmScopedOwnedInputs.required (source.signature, program)) {
			return null;
		}
		var captures = LlvmScopedOwnedInputs.from_native (artifact, factory, type, source, program, structs, true, true);
		if (captures == null) {
			if (LlvmScopedOwnedInputs.required (source.signature, program)) {
				throw new LlvmError.LOWERING ("opaque scoped task requires its complete native capture contract");
			}
			return null;
		}
		var payload = LlvmAsyncRecordResult.from_native (artifact, source, program, captures);
		if (payload == null && !captures.deferred_error) {
			captures = LlvmScopedOwnedInputs.from_native (artifact, factory, type, source, program, structs, true);
			if (captures == null) {
				throw new LlvmError.LOWERING ("opaque scoped task requires its complete deferred result contract");
			}
		}
		var contract = new LlvmScopedImportedTask ();
		contract.inputs = captures;
		contract.result = payload;
		contract.factory = factory;
		contract.checked_factory = checked_factory;
		contract.normal = new LlvmNativeModuleBinding (factory, type, symbol, true);
		contract.checked = new LlvmNativeModuleBinding (checked_factory, type, symbol + "_checked", true);
		return contract;
	}

	internal void seal(HashTable<int, LlvmScopedDescriptorAuthority> descriptors) throws LlvmError {
		if (sealed) {
			throw new LlvmError.LOWERING ("opaque scoped task seals once");
		}
		normal.verify ();
		checked.verify ();
		inputs.seal_imported_capture (normal, descriptors);
		if (result != null) {
			result.verify (inputs);
		}
		sealed = true;
	}

	internal void verify() throws LlvmError {
		if (!sealed) {
			throw new LlvmError.VERIFICATION ("opaque scoped task capture contract is not sealed");
		}
		normal.verify ();
		checked.verify ();
		inputs.verify ();
		if (result != null) {
			result.verify (inputs);
		}
	}

}
// Original cold capture publication, copied before scoped inventories seal.
// The caller keeps allocation debt while the task owns the moved handle.
internal class LlvmScopedCapturedTask : Object {
	private LlvmAsyncFrameBinding? frame;
	private LlvmScopedImportedTask? imported;
	internal LlvmScopedOwnedInputs inputs { get { return frame == null ? imported.inputs : frame.scoped_captures; } }
	internal LlvmAsyncRecordResult? result { get { return frame == null ? imported.result : frame.scoped_result; } }
	internal bool checked_admission { get; private set; }
	private CApi.ValueRef original;
	private LlvmClassCallBinding binding;
	private bool sealed;
	private CApi.ValueRef admission;
	private CApi.BasicBlockRef refused;
	private CApi.BasicBlockRef accepted;
	internal CApi.ValueRef admission_branch() {
		return admission;
	}

	internal void seal() throws LlvmError {
		if (sealed) {
			throw new LlvmError.LOWERING ("scoped capture admission binds once");
		}
		if (checked_admission) {
			admission = CApi.block_terminator (CApi.instruction_parent (original));
			if (CApi.opcode (admission) != CApi.Opcode.COND_BR || CApi.successor_count (admission) != 2) {
				throw new LlvmError.LOWERING ("checked scoped capture lost its immediate admission branch");
			}
			refused = CApi.successor (admission, 0);
			accepted = CApi.successor (admission, 1);
		}
		sealed = true;
		verify (original);
	}

	internal LlvmScopedCapturedTask (CApi.ValueRef call, LlvmAsyncFrameBinding frame, CApi.ValueRef factory, CApi.TypeRef type, CApi.ValueRef[] arguments, bool checked_admission) {
		this.frame = frame;
		this.checked_admission = checked_admission;
		original = call;
		binding = new LlvmClassCallBinding (call, factory, type, arguments, LlvmLowering.CALL_CONVENTION, "scoped captured task original factory");
	}

	internal LlvmScopedCapturedTask.opaque (CApi.ValueRef call, LlvmScopedImportedTask imported, CApi.ValueRef factory, CApi.TypeRef type, CApi.ValueRef[] arguments, bool checked_admission) {
		this.imported = imported;
		this.checked_admission = checked_admission;
		original = call;
		binding = new LlvmClassCallBinding (call, factory, type, arguments, LlvmLowering.CALL_CONVENTION, "opaque scoped captured task original factory");
	}
	internal void verify(CApi.ValueRef call) throws LlvmError {
		var factory = frame == null ? (checked_admission ? imported.checked_factory : imported.factory) : (checked_admission ? frame.checked_factory : frame.factory);
		if ((void*) call != (void*) original || inputs == null || !sealed || (void*) CApi.called_value (call) != (void*) factory) {
			throw new LlvmError.VERIFICATION ("scoped captured task requires its original supported cold factory");
		}
		binding.verify ();
		if (frame == null) {
			imported.verify ();
		} else {
			frame.verify_captured_factory (checked_admission);
		} if (checked_admission) {
			if (CApi.opcode (admission) != CApi.Opcode.COND_BR || CApi.successor_count (admission) != 2 || (void*) CApi.block_terminator (CApi.instruction_parent (original)) != (void*) admission || (void*) CApi.successor (admission, 0) != (void*) refused || (void*) CApi.successor (admission, 1) != (void*) accepted) {
				throw new LlvmError.VERIFICATION ("checked scoped capture lost its original refusal/admission edges");
			}
			var condition = CApi.operand (admission, 0);
			if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ || (void*) CApi.operand (condition, 0) != (void*) original || (void*) CApi.is_constant_pointer_null (CApi.operand (condition, 1)) == null) {
				throw new LlvmError.VERIFICATION ("checked scoped capture requires its actual nullable factory result");
			}
		}
	}

	internal bool accepts(CApi.ValueRef call, uint position, CApi.ValueRef tag, CApi.ValueRef count, CApi.ValueRef size, CApi.ValueRef alignment) throws LlvmError {
		verify (call);
		return inputs.input_shape (position, tag, count, size, alignment);
	}

}
private class LlvmScopedHeldTask : Object {
	internal CApi.ValueRef call;
	internal LlvmScopedCapturedTask capture;
	internal int ordinal;
	internal HashTable<int, LlvmScopedPointer> results = new HashTable<int, LlvmScopedPointer> (direct_hash, direct_equal);
	internal HashTable<int, LlvmScopedPointer> owners = new HashTable<int, LlvmScopedPointer> (direct_hash, direct_equal);
	internal LlvmScopedHeldTask (CApi.ValueRef call, LlvmScopedCapturedTask capture, int ordinal) {
		this.call = call;
		this.capture = capture;
		this.ordinal = ordinal;
	}

}
internal class LlvmScopedBorrowBinding : Object {
	private CApi.ValueRef function;
	private CApi.TypeRef type;
	private uint parameters;
	private bool lifecycle;
	private int receiver_class = -1;
	internal bool scoped_receiver { get; private set; }
	internal bool checked_constructor { get; private set; }
	private CApi.ValueRef tag;
	private CApi.ValueRef size;
	private CApi.ValueRef alignment;
	private CApi.TypeRef carrier_layout = (CApi.TypeRef) null;
	private GenericArray<int> scoped_children = new GenericArray<int> ();
	private GenericArray<LlvmScopedMemberPath> scoped_paths = new GenericArray<LlvmScopedMemberPath> ();
	private LlvmSumSequence? body;
	private LlvmNativeModuleBinding? imported_body;
	private LlvmScopedBorrowBinding (CApi.ValueRef function, CApi.TypeRef type) {
		this.function = function;
		this.type = type;
		parameters = CApi.count_params (function);
	}

	internal static bool requires_layout(NativeFunction source) {
		var signature = source.signature;
		// Owning lifecycle effects use the separate field-transfer contract.
		// Allocating a heap exception clears the optimizer's receiver flag.
		// Checked scalar constructors instead require the complete normal,
		// exceptional and storage lifetime proof in from_native below.
		if ((source.kind == NativeCallableKind.CONSTRUCTOR || source.kind == NativeCallableKind.DESTRUCTOR) && (source.effect_facts == null || (source.effect_facts.flags & FunctionEffectFacts.RECEIVER_NO_CAPTURE) == 0) && !(source.kind == NativeCallableKind.CONSTRUCTOR && signature.exception_plan != null)) {
			return false;
		}
		// Optimizer purity is deliberately conservative for reads through an
		// owned child. The complete lifetime summary below proves no escape
		// independently and never grants an optimizer memory attribute.
		// A scalar constructor may fail without publishing its receiver. Its
		// exception channel must independently carry no scoped authority below.
		if (signature.receiver == null || signature.exception_plan != null && source.kind != NativeCallableKind.CONSTRUCTOR || signature.object_result != null || signature.sum_result != null || signature.buffer_result != null || signature.struct_result != null) {
			return false;
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type == NativeScalarType.PTR) {
				return false;
			}
		}
		return signature.result == null || signature.result.abi_type.get_type () == typeof (NativeScalarAbiType) && signature.result.scalar_type != NativeScalarType.PTR;
	}

	internal static LlvmScopedBorrowBinding? from_native(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.TypeRef type, NativeFunction source, NativeAbiProgram program, LlvmStructRegistry structs) throws LlvmError {
		var signature = source.signature;
		var classes = program.classes;
		// A lifecycle with no scoped descendants may use scalar fields/observers.
		// Its complete lifetime summary proves no retention independently of
		// optimizer purity, which opaque declarations intentionally do not infer.
		bool scalar_lifecycle = (source.kind == NativeCallableKind.CONSTRUCTOR || source.kind == NativeCallableKind.DESTRUCTOR) && source.declaring_type_is_class && source.declaring_type_ordinal >= 0 && source.declaring_type_ordinal < classes.length && signature.receiver != null && signature.result == null && signature.exception_plan == null && LlvmScopedClassGraph.value_scope_free (classes[source.declaring_type_ordinal], classes);
		foreach (var parameter in signature.parameters) {
			if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type == NativeScalarType.PTR) {
				scalar_lifecycle = false;
			}
		}
		if (!requires_layout (source) && !scalar_lifecycle) {
			return null;
		}
		var result = new LlvmScopedBorrowBinding (function, type);
		result.lifecycle = source.kind == NativeCallableKind.CONSTRUCTOR || source.kind == NativeCallableKind.DESTRUCTOR;
		result.checked_constructor = source.kind == NativeCallableKind.CONSTRUCTOR && signature.exception_plan != null;
		result.receiver_class = source.declaring_type_is_class ? source.declaring_type_ordinal : -1;
		if (result.receiver_class >= 0) {
			if (result.receiver_class >= classes.length || !classes[result.receiver_class].allocation_policy_valid ()) {
				throw new LlvmError.INVALID_INPUT ("scoped receiver lost its exact native Class declaration");
			}
			var owner = classes[result.receiver_class];
			var layout = structs.class_layout (owner.ordinal, owner.name);
			if (artifact.class_target == null) {
				artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
			}
			var data = artifact.class_target.enum_target_data (artifact);
			result.scoped_receiver = LlvmScopedClassGraph.contains_scope (owner, program);
			result.tag = new LlvmPolicyAllocation (artifact).tag (owner.name, "object");
			result.size = CApi.const_int (CApi.int_type_in_context (artifact.context, 64), CApi.abi_size_of_type (data, layout), 0);
			result.alignment = CApi.const_int (CApi.int32_type_in_context (artifact.context), uint.max (CApi.abi_alignment_of_type (data, layout), owner.allocation_policy == null ? 1 : owner.allocation_policy.alignment), 0);
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			if (!summary.complete || !summary.matches_exception (signature.exception_plan != null) || summary.equations.requirements (summary.result).length != 0 || summary.has_exception && summary.equations.requirements (summary.exception).length != 0) {
				return null;
			}
			for (uint s = 0; s < summary.store_count; s++) {
				if (summary.equations.requirements (summary.store (s).value).length != 0) {
					return null;
				}
			}
			var updates = summary.updated_inputs ();
			for (int u = 0; u < updates.length; u++) {
				int input = updates[u];
				var roots = summary.equations.requirements (summary.update (input), "", false);
				if (input != -1 || roots.length != 1 || roots[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || roots[0].ordinal != -1 || roots[0].path != "" || roots[0].descendants) {
					return null;
				}
			}
			if (summary.store_count == 0 && updates.length == 0 && source.declaring_type_is_class && source.declaring_type_ordinal >= 0 && source.declaring_type_ordinal < classes.length) {
				var owner = classes[source.declaring_type_ordinal];
				foreach (var field in owner.fields) {
					if (field.owns_record) {
						if (LlvmScopedPlainRecords.children (field, classes) == null) {
							return null;
						}
						foreach (var resource in field.record_value.ownership) {
							var child = classes[resource.cleanup_class_ordinal];
							if (LlvmScopedClassGraph.contains_scope (child, program)) {
								result.carrier_layout = structs.class_layout (owner.ordinal, owner.name);
								result.scoped_paths.add (new LlvmScopedMemberPath.record (field.ordinal + (owner.polymorphic ? 2 : owner.concurrency_policy == null ? 0 : 6), resource));
								result.scoped_children.add (child.ordinal);
							}
						}
						continue;
					}
					if (field.owned_class_ordinal < 0 || field.owned_class_ordinal >= classes.length) {
						continue;
					}
					var child = classes[field.owned_class_ordinal];
					if (LlvmScopedClassGraph.contains_scope (child, program)) {
						result.carrier_layout = structs.class_layout (owner.ordinal, owner.name);
						result.scoped_paths.add (new LlvmScopedMemberPath (field.ordinal + (owner.polymorphic ? 2 : owner.concurrency_policy == null ? 0 : 6)));
						result.scoped_children.add (child.ordinal);
					}
				}
			}
		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("invalid native borrow lifetime: %s", failure.message);
		}
		return result;
	}

	internal void attach_import(LlvmNativeModuleBinding binding) throws LlvmError {
		if (body != null || imported_body != null || CApi.count_basic_blocks (function) != 0) {
			throw new LlvmError.LOWERING ("scoped borrow requires its original opaque native declaration");
		}
		binding.verify ();
		imported_body = binding;
	}

	internal void seal() throws LlvmError {
		if (imported_body != null) {
			verify ();
			return;
		}
		if (body != null || CApi.count_basic_blocks (function) == 0) {
			throw new LlvmError.LOWERING ("scoped native borrow requires its unique actual emitted body");
		}
		body = new LlvmSumSequence (function, true);
	}

	internal void verify() throws LlvmError {
		if ((body == null && imported_body == null) || (void*) CApi.global_value_type (function) != (void*) type || CApi.count_params (function) != parameters || CApi.function_call_conv (function) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("scoped native borrow lost its exact signature/body authority");
		}
		if (imported_body != null) {
			imported_body.verify ();
			return;
		}
		body.verify ();
	}

	internal bool accepts(CApi.ValueRef call, uint parameter) throws LlvmError {
		verify ();
		return parameter == 0 && (void*) CApi.called_value (call) == (void*) function && (void*) CApi.called_function_type (call) == (void*) type && CApi.argument_count (call) == parameters && CApi.instruction_call_conv (call) == LlvmLowering.CALL_CONVENTION;
	}

	internal bool accepts_loan(CApi.ValueRef call, uint parameter, int owner) throws LlvmError {
		return !lifecycle && receiver_class == owner && accepts (call, parameter);
	}

	internal bool accepts_scope(CApi.ValueRef call, uint parameter, CApi.ValueRef actual_tag, CApi.ValueRef count, CApi.ValueRef actual_size, CApi.ValueRef actual_alignment) throws LlvmError {
		if (parameter != 0 || receiver_class < 0) {
			return false;
		}
		if ((void*) tag != (void*) actual_tag || (void*) size != (void*) actual_size || (void*) alignment != (void*) actual_alignment || (void*) CApi.is_constant_int (count) == null || CApi.const_int_zext (count) != 1) {
			throw new LlvmError.VERIFICATION ("scoped receiver lost its exact Class allocation shape");
		}
		return accepts (call, parameter);
	}

	private int child_receiver(CApi.ValueRef value) {
		if ((void*) carrier_layout == null || (void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.LOAD || CApi.type_kind (CApi.type_of (value)) != CApi.TypeKind.POINTER || CApi.get_volatile (value) != 0 || CApi.get_ordering (value) != 0) {
			return -1;
		}
		var address = CApi.operand (value, 0);
		for (int i = 0; i < scoped_paths.length; i++) {
			if (scoped_paths[i].matches (address, CApi.get_param (function, 0), carrier_layout)) {
				return scoped_children[i];
			}
		}
		return -1;
	}

	internal bool forwards_receiver(CApi.ValueRef value, LlvmScopedBorrowBinding target, CApi.ValueRef call, uint position) throws LlvmError {
		verify ();
		int child = child_receiver (value);
		return ((void*) value == (void*) CApi.get_param (function, 0) || child >= 0) && target.accepts_loan (call, position, (void*) value == (void*) CApi.get_param (function, 0) ? receiver_class : child);
	}

	internal bool forwards_loan(CApi.ValueRef value, LlvmScopedClassLoans target, CApi.ValueRef call, uint position) throws LlvmError {
		verify ();
		if (receiver_class >= 0 && (void*) value == (void*) CApi.get_param (function, 0)) {
			return target.accepts_scope (call, position, tag, CApi.const_int (CApi.type_of (size), 1, 0), size, alignment);
		}
		int child = child_receiver (value);
		return child >= 0 && target.accepts_class (call, position, child);
	}

	internal bool preserves_carrier(CApi.ValueRef call, CApi.TypeRef layout) throws LlvmError {
		return (void*) carrier_layout != null && (void*) carrier_layout == (void*) layout && accepts (call, 0);
	}

}
private class LlvmScopedClassLoan : Object {
	internal CApi.ValueRef value;
	internal int class_ordinal;
	internal CApi.TypeRef layout;
	internal CApi.ValueRef tag;
	internal CApi.ValueRef size;
	internal CApi.ValueRef alignment;
	internal uint position;
	internal GenericArray<int> scalar_members = new GenericArray<int> ();
	internal GenericArray<void*> scalar_types = new GenericArray<void*> ();
	internal GenericArray<uint> scalar_alignments = new GenericArray<uint> ();
	internal LlvmScopedClassLoan (CApi.ValueRef value, CApi.TypeRef layout, uint position, int class_ordinal) {
		this.class_ordinal = class_ordinal;
		this.value = value;
		this.layout = layout;
		this.position = position;
	}

	internal bool scalar_projection(CApi.ValueRef address) throws LlvmError {
		if (CApi.opcode (address) != CApi.Opcode.GEP || CApi.operand_count (address) != 3 || (void*) CApi.operand (address, 0) != (void*) value || (void*) CApi.gep_source_type (address) != (void*) layout || (void*) CApi.is_constant_int (CApi.operand (address, 1)) == null || CApi.const_int_zext (CApi.operand (address, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (address, 2)) == null) {
			return false;
		}
		uint64 member = CApi.const_int_zext (CApi.operand (address, 2));
		int field = -1;
		for (int f = 0; f < scalar_members.length; f++) {
			if (scalar_members[f] == member) {
				field = f;
			}
		}
		if (field < 0) {
			return false;
		}
		for (var use = CApi.first_use (address); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) == null || CApi.opcode (user) != CApi.Opcode.LOAD || (void*) CApi.operand (user, 0) != (void*) address || (void*) CApi.type_of (user) != scalar_types[field] || CApi.get_volatile (user) != 0 || CApi.get_ordering (user) != 0 || CApi.get_alignment (user) > scalar_alignments[field]) {
				throw new LlvmError.VERIFICATION ("scoped Class scalar field loan requires its exact nonretaining ordinary read");
			}
		}
		return true;
	}

}
internal class LlvmScopedClassLoans : Object {
	private LlvmNativeModuleBinding? imported_body;
	private CApi.ValueRef function;
	private CApi.TypeRef type;
	private uint parameters;
	private GenericArray<LlvmScopedClassLoan> loans = new GenericArray<LlvmScopedClassLoan> ();
	private bool sealed;
	private LlvmScopedClassLoans (CApi.ValueRef function, CApi.TypeRef type) {
		this.function = function;
		this.type = type;
		parameters = CApi.count_params (function);
	}

	internal bool covers_record_borrows(LlvmModuleArtifact artifact, NativeSignature signature, NativeAbiProgram program) throws LlvmError {
		if (signature.receiver != null || signature.heap_result != null || signature.object_result != null || signature.sum_result != null || signature.buffer_result != null || signature.result != null && (signature.result.abi_type.get_type () != typeof (NativeScalarAbiType) || signature.result.scalar_type == NativeScalarType.PTR)) {
			return false;
		}
		if (signature.struct_result != null) {
			var record = signature.struct_result;
			if (record.mode != NativeStructValueMode.COPY_VALUE || record.ownership.length != 0) {
				return false;
			}
			foreach (var leaf in record.leaves) {
				var scalar = leaf.abi_type as NativeScalarAbiType;
				if (leaf.buffer_component != -1 || scalar == null || leaf.abi_type.get_type () != typeof (NativeScalarAbiType) || scalar.scalar_type == NativeScalarType.PTR) {
					return false;
				}
			}
		}
		foreach (var group in signature.struct_parameters) {
			if (group.mode == NativeStructValueMode.MOVE_VALUE) {
				return false;
			}
		}
		int offset = signature.has_exception_success_slot ? 1 : 0;
		foreach (var parameter in signature.parameters) {
			var context = parameter.abi_type as NativeContextHandleType;
			if (context != null) {
				if (context.mode != "scoped-affine" || !artifact.has_scoped_context_inputs (function)) {
					return false;
				}
				continue;
			}
			if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType)) {
				return false;
			}
			var origin = parameter.object_origin;
			if (origin != null && (origin.heap ? LlvmScopedClassGraph.contains_scope (program.classes[origin.class_ordinal], program) : !LlvmScopedClassGraph.value_scope_free (program.classes[origin.class_ordinal], program.classes))) {
				return false;
			}
			int ordinal = parameter.borrowed_class_ordinal;
			if (ordinal >= 0 && LlvmScopedClassGraph.contains_scope (program.classes[ordinal], program)) {
				bool covered = false;
				foreach (var loan in loans) {
					covered = covered || loan.position == parameter.ordinal + offset && loan.class_ordinal == ordinal;
				}
				if (!covered) {
					return false;
				}
			} else if (parameter.scalar_type == NativeScalarType.PTR && ordinal < 0 && origin == null) {
				return false;
			}
		}
		return true;
	}

	internal static LlvmScopedClassLoans? from_native(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.TypeRef type, NativeFunction source, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs) throws LlvmError {
		var result = new LlvmScopedClassLoans (function, type);
		var signature = source.signature;
		if (signature.sum_result != null || signature.object_result != null || signature.buffer_result != null || signature.buffer_parameters.length != 0 || !LlvmScopedRecordInputs.bind (signature, classes, new HashTable<int, NativeObjectOriginPlan> (direct_hash, direct_equal))) {
			return null;
		}
		int offset = (signature.receiver == null ? 0 : 1) + (signature.has_exception_success_slot ? 1 : 0);
		foreach (var parameter in signature.parameters) {
			if (!(parameter.abi_type is NativeScalarAbiType) || signature.struct_parameters.length != 0 && parameter.abi_type.get_type () != typeof (NativeScalarAbiType) && !(parameter.abi_type is NativeContextHandleType)) {
				return null;
			}
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			foreach (var parameter in signature.parameters) {
				int ordinal = parameter.borrowed_class_ordinal;
				if (ordinal < 0) {
					continue;
				}
				if (ordinal >= classes.length || !classes[ordinal].allocation_policy_valid ()) {
					throw new LlvmError.INVALID_INPUT ("borrowed Class formal lost its native origin");
				}
				var owner = classes[ordinal];
				var policy = owner.allocation_policy;
				if (policy == null || policy.kind != AllocationKind.CONTEXT || policy.context_mode != "scoped-affine") {
					if (LlvmScopedClassGraph.scope_free (owner, classes)) {
						continue;
					}
					if (LlvmScopedOwnerGraph.from_native (artifact, owner, classes, structs) == null) {
						return null;
					}
				}
				if (!summary.complete || owner.parent_ordinal != -1 || owner.polymorphic || owner.foreign_export != null || owner.lazy_caches.length != 0) {
					throw new LlvmError.LOWERING ("scoped Class borrow requires its complete emitted loan authority");
				}
				int input = parameter.ordinal;
				var values = new GenericArray<int> ();
				values.add (summary.result);
				if (summary.has_exception) {
					values.add (summary.exception);
				}
				for (uint s = 0; s < summary.store_count; s++) {
					values.add (summary.store (s).value);
				}
				var updates = summary.updated_inputs ();
				for (int u = 0; u < updates.length; u++) {
					int updated = updates[u];
					if (updated == input) {
						throw new LlvmError.LOWERING ("scoped Class borrow requires exact mutable field effects");
					}
					values.add (summary.update (updated));
				}
				for (int v = 0; v < values.length; v++) {
					foreach (var root in summary.equations.requirements (values[v])) {
						if (root.kind == RuntimeScopeOriginKind.OWNER_PARAMETER && root.ordinal == input) {
							throw new LlvmError.LOWERING ("scoped Class borrow cannot escape its input loan");
						}
					}
				}
				var loan = new LlvmScopedClassLoan (CApi.get_param (function, input + offset), structs.class_layout (ordinal, owner.name), (uint) (input + offset), ordinal);
				if (artifact.class_target == null) {
					artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
				}
				var data = artifact.class_target.enum_target_data (artifact);
				loan.tag = new LlvmPolicyAllocation (artifact).tag (owner.name, "object");
				loan.size = CApi.const_int (CApi.int_type_in_context (artifact.context, 64), CApi.abi_size_of_type (data, loan.layout), 0);
				loan.alignment = CApi.const_int (CApi.int32_type_in_context (artifact.context), uint.max (CApi.abi_alignment_of_type (data, loan.layout), (policy == null ? 1 : policy.alignment)), 0);
				result.loans.add (loan);
				foreach (var field in owner.fields) {
					var scalar = field.storage_type as NativeScalarAbiType;
					if (scalar == null || field.storage_type.get_type () != typeof (NativeScalarAbiType) || scalar.scalar_type == NativeScalarType.PTR || field.owned_class_ordinal >= 0 || field.text_snapshot || field.owns_buffer || field.owns_record || field.resource_owner != null) {
						continue;
					}
					int member = field.ordinal + (owner.concurrency_policy == null ? 0 : 6);
					var storage = CApi.struct_type_at_index (loan.layout, (uint) member);
					loan.scalar_members.add (member);
					loan.scalar_types.add ((void*) storage);
					loan.scalar_alignments.add (CApi.abi_alignment_of_type (data, storage));
				}
			}
		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("invalid borrowed Class lifetime: %s", failure.message);
		}
		return result.loans.length == 0 ? null : result;
	}

	internal void attach_import(LlvmNativeModuleBinding binding) throws LlvmError {
		if (sealed || imported_body != null || CApi.count_basic_blocks (function) != 0) {
			throw new LlvmError.LOWERING ("scoped Class loan requires its original opaque native declaration");
		}
		binding.verify ();
		imported_body = binding;
	}

	internal void seal() throws LlvmError {
		if (imported_body != null) {
			imported_body.verify ();
			signature ();
			sealed = true;
			return;
		}
		if (sealed || CApi.count_basic_blocks (function) == 0) {
			throw new LlvmError.LOWERING ("scoped Class loans require one actual emitted body");
		}
		sealed = true;
	}

	private void signature() throws LlvmError {
		if (imported_body != null) {
			imported_body.verify ();
		}
		if ((void*) CApi.global_value_type (function) != (void*) type || CApi.count_params (function) != parameters || CApi.function_call_conv (function) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("scoped Class loan lost its exact physical signature");
		}
		foreach (var loan in loans) {
			if ((void*) loan.value != (void*) CApi.get_param (function, loan.position)) {
				throw new LlvmError.VERIFICATION ("scoped Class loan lost its original parameter");
			}
		}
	}

	internal bool accepts(CApi.ValueRef call, uint position, CApi.TypeRef layout) throws LlvmError {
		signature ();
		foreach (var loan in loans) {
			if (loan.position == position && (void*) loan.layout == (void*) layout) {
				if (!sealed) {
					throw new LlvmError.VERIFICATION ("scoped Class loan body is unsealed");
				}
				return (void*) CApi.called_value (call) == (void*) function && (void*) CApi.called_function_type (call) == (void*) type && CApi.argument_count (call) == parameters && CApi.instruction_call_conv (call) == LlvmLowering.CALL_CONVENTION;
			}
		}
		return false;
	}

	internal bool accepts_scope(CApi.ValueRef call, uint position, CApi.ValueRef tag, CApi.ValueRef count, CApi.ValueRef size, CApi.ValueRef alignment) throws LlvmError {
		foreach (var loan in loans) {
			if (loan.position != position) {
				continue;
			}
			if ((void*) loan.tag != (void*) tag || (void*) loan.size != (void*) size || (void*) loan.alignment != (void*) alignment || (void*) CApi.is_constant_int (count) == null || CApi.const_int_zext (count) != 1) {
				throw new LlvmError.VERIFICATION ("scoped Class loan lost its exact Class allocation shape");
			}
			return accepts (call, position, loan.layout);
		}
		return false;
	}

	internal bool class_position(uint position) {
		foreach (var loan in loans) {
			if (loan.position == position) {
				return true;
			}
		}
		return false;
	}

	internal bool accepts_class(CApi.ValueRef call, uint position, int owner) throws LlvmError {
		foreach (var loan in loans) {
			if (loan.position == position && loan.class_ordinal == owner) {
				return accepts (call, position, loan.layout);
			}
		}
		return false;
	}

	internal bool accepts_null(CApi.ValueRef call, uint position) throws LlvmError {
		foreach (var loan in loans) {
			if (loan.position == position) {
				return accepts (call, position, loan.layout);
			}
		}
		return false;
	}

	internal bool forwards(CApi.ValueRef value, LlvmScopedClassLoans target, CApi.ValueRef call, uint position) throws LlvmError {
		signature ();
		if (!sealed) {
			throw new LlvmError.VERIFICATION ("scoped Class loan body is unsealed");
		}
		foreach (var loan in loans) {
			if ((void*) loan.value == (void*) value) {
				return target.accepts_scope (call, position, loan.tag, CApi.const_int (CApi.type_of (loan.size), 1, 0), loan.size, loan.alignment);
			}
		}
		return false;
	}

	internal bool forwards_receiver(CApi.ValueRef value, LlvmScopedBorrowBinding target, CApi.ValueRef call, uint position) throws LlvmError {
		signature ();
		if (!sealed) {
			throw new LlvmError.VERIFICATION ("scoped Class loan body is unsealed");
		}
		foreach (var loan in loans) {
			if ((void*) loan.value == (void*) value) {
				return target.accepts_loan (call, position, loan.class_ordinal);
			}
		}
		return false;
	}

	internal void verify(HashTable<void*, LlvmScopedBorrowBinding> borrows, HashTable<void*, LlvmScopedClassLoans> callees) throws LlvmError {
		signature ();
		foreach (var loan in loans) {
			for (var use = CApi.first_use (loan.value); (void*) use != null; use = CApi.next_use (use)) {
				var user = CApi.user (use);
				if ((void*) CApi.is_instruction (user) == null) {
					throw new LlvmError.VERIFICATION ("scoped Class loan escaped its function");
				}
				var opcode = CApi.opcode (user);
				if (opcode == CApi.Opcode.ICMP && (CApi.predicate (user) == CApi.IntPredicate.EQ || CApi.predicate (user) == CApi.IntPredicate.NE) && ((void*) CApi.is_constant_pointer_null (CApi.operand (user, 0)) != null || (void*) CApi.is_constant_pointer_null (CApi.operand (user, 1)) != null)) {
					continue;
				}
				if (opcode == CApi.Opcode.GEP && loan.scalar_projection (user)) {
					continue;
				}
				if (opcode == CApi.Opcode.CALL && (void*) CApi.is_function (CApi.called_value (user)) != null) {
					bool accepted = true;
					for (uint p = 0; p < CApi.argument_count (user); p++) {
						if ((void*) CApi.operand (user, p) != (void*) loan.value) {
							continue;
						}
						var receiver = borrows.lookup ((void*) CApi.called_value (user));
						var target = callees.lookup ((void*) CApi.called_value (user));
						if (!(receiver != null && receiver.accepts_loan (user, p, loan.class_ordinal)) && !(target != null && target.accepts (user, p, loan.layout))) {
							accepted = false;
						}
					}
					if (accepted && (void*) CApi.called_value (user) != (void*) loan.value) {
						continue;
					}
				}
				throw new LlvmError.VERIFICATION ("scoped Class loan requires its exact nonretaining live borrow effect");
			}
		}
		if (!sealed) {
			throw new LlvmError.VERIFICATION ("scoped Class loan body is unsealed");
		}
	}

}
private class LlvmScopedPointer : Object {
	internal int allocation;
	internal bool root;
	internal int owner;
	internal LlvmScopedPointer (int allocation, bool root, int owner = -1) {
		this.allocation = allocation;
		this.root = root;
		this.owner = owner < 0 ? allocation : owner;
	}

}
private class LlvmScopedRecordCall : Object {
	internal HashTable<int, LlvmScopedPointer> fields = new HashTable<int, LlvmScopedPointer> (direct_hash, direct_equal);
}
private class LlvmScopedCheckedCall : Object {
	internal bool aggregate;
	internal HashTable<int, LlvmScopedPointer> fields = new HashTable<int, LlvmScopedPointer> (direct_hash, direct_equal);
	internal CApi.ValueRef call;
	internal CApi.ValueRef slot;
	internal int allocation;
	internal int owner;
	internal int ordinal;
	internal bool returns_allocation(int value) {
		if (!aggregate) {
			return allocation == value;
		}
		foreach (var field in fields.get_values ()) {
			if (field.allocation == value) {
				return true;
			}
		}
		return false;
	}

	internal LlvmScopedCheckedCall (CApi.ValueRef call, CApi.ValueRef slot, int allocation, int owner, int ordinal) {
		this.call = call;
		this.slot = slot;
		this.allocation = allocation;
		this.owner = owner;
		this.ordinal = ordinal;
	}

}
private class LlvmScopedState : Object {
	internal uint[] values;
	internal LlvmScopedState (int count) {
		values = new uint[count];
	}

}
private class LlvmScopedErrorCall : Object {
	internal CApi.ValueRef call;
	internal LlvmScopedOwnedInputs contract;
	internal LlvmScopedHeapCarrier heap;
	internal int ordinal;
	internal GenericArray<LlvmScopedOwnerSlot> slots = new GenericArray<LlvmScopedOwnerSlot> ();
	internal LlvmScopedErrorCall (CApi.ValueRef call, LlvmScopedOwnedInputs contract, LlvmScopedHeapCarrier heap, int ordinal) {
		this.call = call;
		this.contract = contract;
		this.heap = heap;
		this.ordinal = ordinal;
	}

}
// A storage channel is discovered from actual stores, not lowering markers.
// Its address must be a nonescaping local pointer slot or exact struct field.
private class LlvmScopedOwnerCell : Object {
	internal GenericArray<LlvmScopedOwnerSlot> variants = new GenericArray<LlvmScopedOwnerSlot> ();
}
private class LlvmScopedOwnerRead : Object {
	internal CApi.ValueRef instruction;
	internal LlvmScopedOwnerCell cell;
	internal int ordinal;
	internal LlvmScopedOwnerRead (CApi.ValueRef instruction, LlvmScopedOwnerCell cell, int ordinal) {
		this.instruction = instruction;
		this.cell = cell;
		this.ordinal = ordinal;
	}

}
private class LlvmScopedOwnerSlot : Object {
	internal CApi.ValueRef store;
	internal CApi.ValueRef root;
	internal int allocation;
	internal int owner;
	internal bool entry_live;
	internal int ordinal;
	internal int cell;
	internal uint source_position;
	internal LlvmScopedOwnerSlot (CApi.ValueRef store, CApi.ValueRef root, int allocation, int owner) {
		this.store = store;
		this.root = root;
		this.allocation = allocation;
		this.owner = owner;
	}

}
// Common layout permits static use checking; it never selects ownership.
// Each solving state retains the actual predecessor/SELECT origin separately.
private class LlvmScopedHostError : Object {
	internal CApi.ValueRef call;
	internal CApi.ValueRef read;
	internal LlvmScopedHeldTask task;
	internal int ordinal;
	internal bool asynchronous;
	internal GenericArray<LlvmScopedHeapCarrier> alternatives;
	internal GenericArray<LlvmScopedOwnerSlot> fields = new GenericArray<LlvmScopedOwnerSlot> ();
	internal LlvmScopedHostError (CApi.ValueRef call, CApi.ValueRef read, LlvmScopedHeldTask task, int ordinal, GenericArray<LlvmScopedHeapCarrier> alternatives) {
		this.call = call;
		this.read = read;
		this.task = task;
		this.ordinal = ordinal;
		this.alternatives = alternatives;
	}

}
private class LlvmScopedWork : Object {
	internal uint[] values;
	internal CApi.ValueRef start;
	internal bool prepared;
	internal LlvmScopedWork (uint[] values, CApi.ValueRef start, bool prepared = false) {
		this.values = values;
		this.start = start;
		this.prepared = prepared;
	}

}
private class LlvmScopedHeapChoice : Object {
	internal CApi.ValueRef value;
	internal GenericArray<LlvmScopedHeapCarrier> alternatives;
	internal int ordinal;
	internal LlvmScopedHeapChoice (CApi.ValueRef value, GenericArray<LlvmScopedHeapCarrier> alternatives, int ordinal) {
		this.value = value;
		this.alternatives = alternatives;
		this.ordinal = ordinal;
	}

}
private class LlvmScopedHeapSlot : Object {
	internal CApi.ValueRef address;
	internal int frame_field = -1;
	internal GenericArray<LlvmScopedHeapCarrier> alternatives;
	internal int ordinal;
	internal LlvmScopedHeapSlot (CApi.ValueRef address, GenericArray<LlvmScopedHeapCarrier> alternatives, int ordinal) {
		this.address = address;
		this.alternatives = alternatives;
		this.ordinal = ordinal;
	}

}
private class LlvmScopedOwnerStorage : Object {
	private GenericArray<LlvmScopedOwnerCell> owner_cells = new GenericArray<LlvmScopedOwnerCell> ();
	private HashTable<void*, LlvmScopedOwnerRead> owner_reads = new HashTable<void*, LlvmScopedOwnerRead> (direct_hash, direct_equal);
	private GenericArray<LlvmScopedOwnerRead> owner_read_channels = new GenericArray<LlvmScopedOwnerRead> ();
	private int active_storage_offset;
	private void add_slot(string key, LlvmScopedOwnerSlot slot) {
		var prior = addresses.lookup (key);
		if (prior == null) {
			slot.cell = (int) owner_cells.length;
			owner_cells.add (new LlvmScopedOwnerCell ());
			addresses.insert (key, slot);
		} else {
			slot.cell = prior.cell;
		}
		slot.ordinal = (int) slots.length;
		owner_cells[slot.cell].variants.add (slot);
		slots.add (slot);
	}

	private LlvmScopedOwnerSlot? current_slot(LlvmScopedOwnerSlot? first) {
		if (first == null || active_state == null || owner_cells[first.cell].variants.length == 1) {
			return first;
		}
		foreach (var slot in owner_cells[first.cell].variants) {
			if (active_state[active_storage_offset + slot.ordinal] == 2) {
				return slot;
			}
		}
		foreach (var slot in owner_cells[first.cell].variants) {
			if (active_state[active_storage_offset + slot.ordinal] == 8) {
				return slot;
			}
		}
		return first;
	}

	internal void append_owner_state(StringBuilder key, uint[] state, int offset) {
		foreach (var cell in owner_cells) {
			if (cell.variants.length > 1) {
				foreach (var slot in cell.variants) {
					key.append_printf ("%u;", state[offset + slot.ordinal]);
				}
			}
		}
	}

	internal bool current_variant(LlvmScopedOwnerSlot slot) {
		return current_slot (owner_cells[slot.cell].variants[0]) == slot;
	}

	internal LlvmScopedOwnerSlot? publication_slot(CApi.ValueRef instruction, LlvmScopedOwnerSlot? first) {
		if (first == null) {
			return null;
		}
		foreach (var slot in owner_cells[first.cell].variants) {
			if ((void*) slot.store == (void*) instruction) {
				return slot;
			}
		}
		return null;
	}

	internal void prepare_owner_reads(GenericArray<void*> blocks) throws LlvmError {
		foreach (void* block in blocks) {
			for (var i = CApi.first_instruction ((CApi.BasicBlockRef) block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) != CApi.Opcode.LOAD || CApi.type_kind (CApi.type_of (i)) != CApi.TypeKind.POINTER) {
					continue;
				}
				var slot = lookup (CApi.operand (i, 0));
				if (slot == null || owner_cells[slot.cell].variants.length == 1) {
					continue;
				}
				if (CApi.get_volatile (i) != 0 || CApi.get_ordering (i) != 0) {
					throw new LlvmError.VERIFICATION ("scoped field snapshot requires an ordinary pointer load");
				}
				var read = new LlvmScopedOwnerRead (i, owner_cells[slot.cell], (int) owner_read_channels.length);
				owner_read_channels.add (read);
				owner_reads.insert ((void*) i, read);
			}
		}
	}

	private int owner_read_offset() {
		return choice_offset + (int) choices.length + (int) heap_channels.length;
	}

	internal void owner_read_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		var read = owner_reads.lookup ((void*) instruction);
		if (read == null) {
			return;
		}
		var slot = current_slot (read.cell.variants[0]);
		uint live = state[active_storage_offset + slot.ordinal];
		if (strict && live != 2 && live != 8) {
			throw new LlvmError.VERIFICATION ("scoped field snapshot lacks its original occupied cell");
		}
		state[owner_read_offset () + read.ordinal] = (uint) slot.ordinal + 1;
	}

	internal LlvmScopedPointer? owner_read_pointer(CApi.ValueRef instruction) {
		var read = owner_reads.lookup ((void*) instruction);
		if (read == null || active_state == null) {
			return null;
		}
		uint selected = active_state[owner_read_offset () + read.ordinal];
		if (selected == 0 || selected == uint.MAX || selected > slots.length) {
			return null;
		}
		var slot = slots[(int) selected - 1];
		return slot.cell != read.cell.variants[0].cell || slot.allocation < 0 ? null : new LlvmScopedPointer (slot.allocation, true, slot.owner);
	}

	internal void verify_owner_read_use(CApi.ValueRef instruction) throws LlvmError {
		for (uint p = 0; p < CApi.operand_count (instruction); p++) {
			var read = owner_reads.lookup ((void*) CApi.operand (instruction, p));
			if (read == null) {
				continue;
			}
			uint selected = active_state[owner_read_offset () + read.ordinal];
			if (selected == 0 || selected == uint.MAX) {
				throw new LlvmError.VERIFICATION ("scoped field snapshot outlived its original generation");
			}
			if (CApi.opcode (instruction) == CApi.Opcode.PHI || CApi.opcode (instruction) == CApi.Opcode.SELECT) {
				throw new LlvmError.VERIFICATION ("scoped field snapshot join requires its exact selected owner generation");
			}
		}
	}

	internal void invalidate_owner_allocation(int allocation, uint[] state) {
		foreach (var read in owner_read_channels) {
			uint selected = state[owner_read_offset () + read.ordinal];
			if (selected != 0 && selected != uint.MAX && selected <= slots.length && slots[(int) selected - 1].allocation == allocation) {
				state[owner_read_offset () + read.ordinal] = uint.MAX;
			}
		}
	}

	internal void publish(LlvmScopedOwnerSlot slot, uint[] state, bool strict) throws LlvmError {
		foreach (var read in owner_read_channels) {
			if (read.cell == owner_cells[slot.cell]) {
				state[owner_read_offset () + read.ordinal] = uint.MAX;
			}
		}
		foreach (var prior in owner_cells[slot.cell].variants) {
			uint live = state[active_storage_offset + prior.ordinal];
			if (strict && (live == 0 || (live & ~13U) != 0)) {
				throw new LlvmError.VERIFICATION ("scoped owner store overwrites occupied storage");
			}
			if (prior != slot) {
				state[active_storage_offset + prior.ordinal] = 4;
			}
		}
	}

	private HashTable<string, LlvmScopedOwnerSlot> addresses = new HashTable<string, LlvmScopedOwnerSlot> (str_hash, str_equal);
	private LlvmScopedFieldContract? fields;
	private HashTable<void*, LlvmScopedHeapChoice> heap_choices = new HashTable<void*, LlvmScopedHeapChoice> (direct_hash, direct_equal);
	private GenericArray<LlvmScopedHeapChoice> choices = new GenericArray<LlvmScopedHeapChoice> ();
	private unowned uint[]? active_state;
	private int choice_offset;
	private HashTable<void*, LlvmScopedHeapSlot> heap_slots = new HashTable<void*, LlvmScopedHeapSlot> (direct_hash, direct_equal);
	private GenericArray<LlvmScopedHeapSlot> heap_channels = new GenericArray<LlvmScopedHeapSlot> ();
	private HashTable<int, LlvmScopedHeapSlot> frame_channels = new HashTable<int, LlvmScopedHeapSlot> (direct_hash, direct_equal);
	private HashTable<int, bool> frame_choice_fields = new HashTable<int, bool> (direct_hash, direct_equal);
	internal uint choice_count { get { return choices.length + heap_channels.length + owner_read_channels.length; } }
	internal void select_state(uint[] state, int offset, int storage_offset) {
		active_state = state;
		choice_offset = offset;
		active_storage_offset = storage_offset;
	}

	private LlvmScopedHeapCarrier? selected_heap(CApi.ValueRef value) {
		var direct = heap_roots.lookup ((void*) value);
		if (direct != null) {
			return direct;
		}
		var choice = heap_choices.lookup ((void*) value);
		if (choice == null || active_state == null) {
			return null;
		}
		uint selected = active_state[choice_offset + choice.ordinal];
		if (selected == 0 || selected == uint.MAX || selected > heaps.length) {
			return null;
		}
		var heap = heaps[(int) selected - 1];
		return choice.alternatives.find (heap) ? heap : null;
	}

	private GenericArray<LlvmScopedHeapCarrier>? candidates(CApi.ValueRef value) {
		var direct = heap_roots.lookup ((void*) value);
		if (direct != null) {
			var result = new GenericArray<LlvmScopedHeapCarrier> ();
			result.add (direct);
			return result;
		}
		var choice = heap_choices.lookup ((void*) value);
		return choice == null ? null : choice.alternatives;
	}

	private LlvmScopedExceptionShape? common_exception(GenericArray<LlvmScopedHeapCarrier> options) {
		var base_shape = options[0].empty_base_shape ?? options[0].exception_shape;
		if (base_shape == null) {
			return null;
		}
		foreach (var heap in options) {
			if (heap.exception_shape == null || !heap.exception_shape.same (base_shape) && (heap.empty_base_shape == null || !heap.empty_base_shape.same (base_shape))) {
				return null;
			}
		}
		return base_shape;
	}

	internal bool error_view(CApi.ValueRef value, LlvmScopedExceptionShape shape) {
		var options = candidates (value);
		var view = options == null ? null : common_exception (options);
		return view != null && view.same (shape);
	}

	private CApi.TypeRef choice_layout(CApi.ValueRef value, LlvmScopedHeapCarrier heap) {
		var options = candidates (value);
		var base_shape = options == null ? null : common_exception (options);
		return heap_choices.contains ((void*) value) && base_shape != null ? base_shape.layout : heap.layout;
	}

	private LlvmScopedHeapCarrier? shape_heap(CApi.ValueRef value) {
		var options = candidates (value);
		return options == null || options.length == 0 ? null : options[0];
	}

	private bool aliases_into(CApi.ValueRef value, CApi.ValueRef user) {
		var source = candidates (value);
		var target = candidates (user);
		if (source == null || target == null) {
			return false;
		}
		foreach (var heap in source) {
			if (!target.find (heap)) {
				return false;
			}
		}
		return true;
	}

	internal bool choice_null(CApi.ValueRef value) {
		var choice = heap_choices.lookup ((void*) value);
		return choice != null && active_state != null && active_state[choice_offset + choice.ordinal] == 0;
	}

	// Origin facts are ordinals, not bit masks: 0 is null, MAX is unproved.
	// They participate in the state key and must never join with bitwise OR.
	private uint chosen(CApi.ValueRef value, uint[] state, int offset) {
		if ((void*) CApi.is_constant_pointer_null (value) != null) {
			return 0;
		}
		var choice = heap_choices.lookup ((void*) value);
		if (choice != null) {
			return state[offset + choice.ordinal];
		}
		var heap = heap_roots.lookup ((void*) value);
		uint position = 0;
		return heap != null && heaps.find (heap, out position) ? position + 1 : uint.MAX;
	}

	internal void choice_phi_edge(CApi.BasicBlockRef block, CApi.BasicBlockRef prior, uint[] state, int offset) {
		var selected = new uint[choices.length];
		for (int c = 0; c < choices.length; c++) {
			selected[c] = uint.MAX;
			var value = choices[c].value;
			if (CApi.opcode (value) != CApi.Opcode.PHI || (void*) CApi.instruction_parent (value) != (void*) block) {
				continue;
			}
			for (uint i = 0; i < CApi.incoming_count (value); i++) {
				if ((void*) CApi.incoming_block (value, i) == (void*) prior) {
					selected[c] = chosen (CApi.incoming_value (value, i), state, offset);
				}
			}
		}
		for (int c = 0; c < choices.length; c++) {
			if (CApi.opcode (choices[c].value) == CApi.Opcode.PHI && (void*) CApi.instruction_parent (choices[c].value) == (void*) block) {
				state[offset + c] = selected[c];
			}
		}
	}

	internal void choice_select(CApi.ValueRef value, int condition, uint[] state, int offset) {
		var choice = heap_choices.lookup ((void*) value);
		if (choice == null || CApi.opcode (value) != CApi.Opcode.SELECT) {
			return;
		}
		uint left = chosen (CApi.operand (value, 1), state, offset);
		uint right = chosen (CApi.operand (value, 2), state, offset);
		state[offset + choice.ordinal] = condition == 1 ? left : condition == 0 ? right : left == right ? left : uint.MAX;
	}

	internal void verify_choice_use(CApi.ValueRef instruction) throws LlvmError {
		var opcode = CApi.opcode (instruction);
		if (opcode == CApi.Opcode.PHI || opcode == CApi.Opcode.SELECT) {
			return;
		}
		for (uint p = 0; p < CApi.operand_count (instruction); p++) {
			var choice = heap_choices.lookup ((void*) CApi.operand (instruction, p));
			if (choice == null) {
				continue;
			}
			uint selected = active_state == null ? uint.MAX : active_state[choice_offset + choice.ordinal];
			if (selected == uint.MAX) {
				throw new LlvmError.VERIFICATION ("heap choice requires its actual predecessor or selected origin");
			}
			if (selected == 0 && opcode != CApi.Opcode.ICMP && opcode != CApi.Opcode.RET && !(opcode == CApi.Opcode.STORE && p == 0 && heap_slot_store (instruction))) {
				throw new LlvmError.VERIFICATION ("nullable heap choice lacks its actual live origin (opcode=%d)", (int) opcode);
			}
		}
	}

	private HashTable<void*, LlvmScopedHeapCarrier> heap_roots = new HashTable<void*, LlvmScopedHeapCarrier> (direct_hash, direct_equal);
	private HashTable<void*, bool> handle_aliases = new HashTable<void*, bool> (direct_hash, direct_equal);
	internal bool handle_alias(CApi.ValueRef value) {
		return handle_aliases.contains ((void*) value);
	}

	internal GenericArray<LlvmScopedHeapCarrier> heaps = new GenericArray<LlvmScopedHeapCarrier> ();
	internal GenericArray<LlvmScopedOwnerSlot> slots = new GenericArray<LlvmScopedOwnerSlot> ();
	internal void admit(LlvmScopedFieldContract fields) {
		this.fields = fields;
	}

	private string field_key(string path) {
		return "%p".printf ((void*) fields.receiver) + path;
	}

	internal LlvmScopedOwnerSlot? field_slot(string path) {
		return current_slot (addresses.lookup (field_key (path)));
	}

	internal LlvmScopedOwnerSlot? result_field(CApi.ValueRef root, int member, string? path = null) {
		var heap = selected_heap (root);
		return current_slot (addresses.lookup ("%p".printf ((void*) (heap == null ? root : heap.root)) + (path ?? "/" + member.to_string ())));
	}

	internal bool is_heap_root(CApi.ValueRef value, LlvmScopedHeapCarrier heap) {
		return selected_heap (value) == heap;
	}

	private bool common_shape(GenericArray<LlvmScopedHeapCarrier> options) {
		if (common_exception (options) != null) {
			return true;
		}
		foreach (var heap in options) {
			if ((void*) heap.layout != (void*) options[0].layout || (heap.exception_shape == null) != (options[0].exception_shape == null) || heap.exception_shape != null && !heap.exception_shape.same (options[0].exception_shape)) {
				return false;
			}
		}
		return true;
	}

	private LlvmScopedHeapSlot? private_heap_slot(CApi.ValueRef address) throws LlvmError {
		var known = heap_slots.lookup ((void*) address);
		if (known != null) {
			return known;
		}
		int field = coroutine == null ? -1 : coroutine.lifetime_field (address);
		if (field >= 0 && frame_choice_fields.contains (field)) {
			return private_frame_slot (field);
		}
		if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.ALLOCA || CApi.type_kind (CApi.allocated_type (address)) != CApi.TypeKind.POINTER || CApi.operand_count (address) != 1 || (void*) CApi.is_constant_int (CApi.operand (address, 0)) == null || CApi.const_int_zext (CApi.operand (address, 0)) != 1) {
			return null;
		}
		var options = new GenericArray<LlvmScopedHeapCarrier> ();
		for (var use = CApi.first_use (address); (void*) use != null; use = CApi.next_use (use)) {
			var access = CApi.user (use);
			if ((void*) CApi.is_instruction (access) == null) {
				return null;
			}
			var opcode = CApi.opcode (access);
			if (opcode == CApi.Opcode.LOAD && (void*) CApi.operand (access, 0) == (void*) address && (void*) CApi.type_of (access) == (void*) CApi.allocated_type (address) && CApi.get_volatile (access) == 0 && CApi.get_ordering (access) == 0) {
				continue;
			}
			if (opcode != CApi.Opcode.STORE || (void*) CApi.operand (access, 1) != (void*) address || (void*) CApi.type_of (CApi.operand (access, 0)) != (void*) CApi.allocated_type (address) || CApi.get_volatile (access) != 0 || CApi.get_ordering (access) != 0) {
				return null;
			}
			var input = CApi.operand (access, 0);
			if ((void*) CApi.is_constant_pointer_null (input) != null) {
				continue;
			}
			var incoming = candidates (input);
			if (incoming == null) {
				return null;
			}
			foreach (var heap in incoming) {
				if (!options.find (heap)) {
					options.add (heap);
				}
			}
		}
		if (options.length == 0 || !common_shape (options)) {
			return null;
		}
		var slot = new LlvmScopedHeapSlot (address, options, (int) heap_channels.length);
		heap_channels.add (slot);
		heap_slots.insert ((void*) address, slot);
		return slot;
	}

	private LlvmScopedHeapSlot? private_frame_slot(int field) throws LlvmError {
		var known = frame_channels.lookup (field);
		if (known != null) {
			return known;
		}
		if (CApi.type_kind (CApi.struct_type_at_index (coroutine.frame_type, (uint) field)) != CApi.TypeKind.POINTER) {
			return null;
		}
		var locations = new GenericArray<void*> ();
		var options = new GenericArray<LlvmScopedHeapCarrier> ();
		foreach (var code in new CApi.ValueRef[] { coroutine.resume, coroutine.destroy }) {
			for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
				for (var address = CApi.first_instruction (block); (void*) address != null; address = CApi.next_instruction (address)) {
					if (coroutine.lifetime_field (address) != field) {
						continue;
					}
					locations.add ((void*) address);
					for (var use = CApi.first_use (address); (void*) use != null; use = CApi.next_use (use)) {
						var access = CApi.user (use);
						if ((void*) CApi.is_instruction (access) == null) {
							return null;
						}
						var opcode = CApi.opcode (access);
						if (opcode == CApi.Opcode.LOAD && (void*) CApi.operand (access, 0) == (void*) address && (void*) CApi.type_of (access) == (void*) CApi.struct_type_at_index (coroutine.frame_type, (uint) field) && CApi.get_volatile (access) == 0 && CApi.get_ordering (access) == 0) {
							continue;
						}
						if (opcode != CApi.Opcode.STORE || (void*) CApi.operand (access, 1) != (void*) address || (void*) CApi.type_of (CApi.operand (access, 0)) != (void*) CApi.struct_type_at_index (coroutine.frame_type, (uint) field) || CApi.get_volatile (access) != 0 || CApi.get_ordering (access) != 0) {
							return null;
						}
						var input = CApi.operand (access, 0);
						if ((void*) CApi.is_constant_pointer_null (input) != null) {
							continue;
						}
						var incoming = candidates (input);
						if (incoming == null) {
							return null;
						}
						foreach (var heap in incoming) {
							if (!options.find (heap)) {
								options.add (heap);
							}
						}
					}
				}
			}
		}
		if (options.length == 0 || !common_shape (options)) {
			return null;
		}
		var slot = new LlvmScopedHeapSlot ((CApi.ValueRef) locations[0], options, (int) heap_channels.length);
		slot.frame_field = field;
		heap_channels.add (slot);
		frame_channels.insert (field, slot);
		foreach (void* address in locations) {
			heap_slots.insert (address, slot);
		}
		return slot;
	}

	internal void initialize_frame_origins(uint[] state, int offset) {
		foreach (var slot in heap_channels) {
			if (slot.frame_field >= 0) {
				state[offset + choices.length + slot.ordinal] = 0;
			}
		}
	}

	internal bool frame_origin_field(int field) {
		return frame_channels.contains (field);
	}

	internal bool retained_heap(LlvmScopedHeapCarrier heap, uint[] state, int frame_offset, int offset) {
		foreach (int field in frame_heaps.get_keys ()) {
			if (frame_heaps.lookup (field) == heap && state[frame_offset + field] == 2) {
				return true;
			}
		}
		uint position = 0;
		if (!heaps.find (heap, out position)) {
			return false;
		}
		foreach (var slot in heap_channels) {
			if (slot.frame_field >= 0 && state[offset + choices.length + slot.ordinal] == position + 1) {
				return true;
			}
		}
		return false;
	}

	private bool bind_heap_load(CApi.ValueRef value) throws LlvmError {
		if (heap_choices.contains ((void*) value) || CApi.type_kind (CApi.type_of (value)) != CApi.TypeKind.POINTER || CApi.get_volatile (value) != 0 || CApi.get_ordering (value) != 0) {
			return false;
		}
		var slot = private_heap_slot (CApi.operand (value, 0));
		if (slot == null) {
			return false;
		}
		foreach (var heap in slot.alternatives) {
			if (LlvmBufferExchangeOrder.precedes (value, heap.allocation)) {
				throw new LlvmError.VERIFICATION ("heap slot load predates its backing generation");
			}
		}
		var choice = new LlvmScopedHeapChoice (value, slot.alternatives, (int) choices.length);
		choices.add (choice);
		heap_choices.insert ((void*) value, choice);
		return true;
	}

	internal bool checked_pointer_store(CApi.ValueRef store) {
		return heap_slot_store (store);
	}

	private bool heap_slot_store(CApi.ValueRef store) {
		return CApi.opcode (store) == CApi.Opcode.STORE && heap_slots.contains ((void*) CApi.operand (store, 1));
	}

	internal void heap_slot_effect(CApi.ValueRef instruction, uint[] state, int offset, bool strict) throws LlvmError {
		var opcode = CApi.opcode (instruction);
		if (opcode == CApi.Opcode.ALLOCA) {
			var slot = heap_slots.lookup ((void*) instruction);
			if (slot != null) {
				state[offset + choices.length + slot.ordinal] = uint.MAX;
			}
		}
		if (opcode == CApi.Opcode.STORE) {
			var slot = heap_slots.lookup ((void*) CApi.operand (instruction, 1));
			if (slot != null) {
				uint origin = chosen (CApi.operand (instruction, 0), state, offset);
				if (strict && origin == uint.MAX) {
					throw new LlvmError.VERIFICATION ("heap slot store requires its actual original carrier");
				}
				state[offset + choices.length + slot.ordinal] = origin;
			}
		}
		if (opcode == CApi.Opcode.LOAD) {
			var choice = heap_choices.lookup ((void*) instruction);
			var slot = heap_slots.lookup ((void*) CApi.operand (instruction, 0));
			if (choice != null && slot != null) {
				uint origin = state[offset + choices.length + slot.ordinal];
				if (strict && origin == uint.MAX) {
					throw new LlvmError.VERIFICATION ("heap slot read requires an initialized original carrier");
				}
				state[offset + choice.ordinal] = origin;
			}
		}
	}

	internal bool bind_heap_alias(CApi.ValueRef value) throws LlvmError {
		if (CApi.opcode (value) == CApi.Opcode.LOAD) {
			return bind_heap_load (value);
		}
		bool selected = CApi.opcode (value) == CApi.Opcode.SELECT;
		uint count = selected ? 2 : CApi.opcode (value) == CApi.Opcode.PHI ? CApi.incoming_count (value) : 0;
		if (heap_roots.contains ((void*) value) || heap_choices.contains ((void*) value) || count == 0 || CApi.type_kind (CApi.type_of (value)) != CApi.TypeKind.POINTER) {
			return false;
		}
		var options = new GenericArray<LlvmScopedHeapCarrier> ();
		bool nullable = false;
		bool handle = selected;
		for (uint i = 0; i < count; i++) {
			var operand = selected ? CApi.operand (value, i + 1) : CApi.incoming_value (value, i);
			if ((void*) CApi.is_constant_pointer_null (operand) != null) {
				nullable = true;
				continue;
			}
			var incoming = candidates (operand);
			if (incoming == null) {
				return false;
			}
			handle = handle || handle_alias (operand);
			foreach (var heap in incoming) {
				if (!options.find (heap)) {
					options.add (heap);
				}
			}
		}
		if (options.length == 0 || !common_shape (options)) {
			return false;
		}
		foreach (var heap in options) {
			if (LlvmBufferExchangeOrder.precedes (value, heap.allocation)) {
				throw new LlvmError.VERIFICATION ("loop-carried exception carrier predates its backing generation");
			}
		}
		if (options.length == 1) {
			options[0].alias_nullable = options[0].alias_nullable || nullable;
			heap_roots.insert ((void*) value, options[0]);
			if (handle) {
				handle_aliases.insert ((void*) value, true);
			}
		} else {
			var choice = new LlvmScopedHeapChoice (value, options, (int) choices.length);
			choices.add (choice);
			heap_choices.insert ((void*) value, choice);
		}
		return true;
	}

	internal void verify_heap_phi_edge(CApi.BasicBlockRef target, CApi.BasicBlockRef prior, uint[] state, int heap_offset) throws LlvmError {
		for (var instruction = CApi.first_instruction (target); (void*) instruction != null && CApi.opcode (instruction) == CApi.Opcode.PHI; instruction = CApi.next_instruction (instruction)) {
			var heap = heap_roots.lookup ((void*) instruction);
			if (heap == null || (void*) heap.root == (void*) instruction || handle_alias (instruction)) {
				continue;
			}
			for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
				if ((void*) CApi.incoming_block (instruction, i) != (void*) prior || (void*) CApi.is_constant_pointer_null (CApi.incoming_value (instruction, i)) == null) {
					continue;
				}
				uint h = 0;
				assert (heaps.find (heap, out h));
				if (state[heap_offset + (int) h] != 1) {
					throw new LlvmError.VERIFICATION ("nullable exception alias discards its live backing and payload");
				}
			}
		}
	}

	internal void verify_exception(LlvmScopedHeapCarrier heap, CApi.ValueRef publication) throws LlvmError {
		if (heap.exception_shape == null) {
			throw new LlvmError.VERIFICATION ("scoped exception lost its physical descriptor shape");
		}
		if (heap.returned_error) {
			heap.exception_shape.verify_inherited (heap.root);
			return;
		}
		var roots = new GenericArray<void*> ();
		foreach (void* root in heap_roots.get_keys ()) {
			if (heap_roots.lookup (root) == heap && (root == (void*) heap.root || frame_heap_aliases.contains (root))) {
				roots.add (root);
			}
		}
		heap.exception_shape.verify_roots (roots, publication);
	}

	internal bool known_destructor(CApi.ValueRef value) {
		foreach (var choice in choices) {
			var heap = choice.alternatives[0];
			if (heap.exception_shape != null && heap.exception_shape.destructor_value (value, choice.value)) {
				return true;
			}
		}
		foreach (void* root in heap_roots.get_keys ()) {
			var heap = heap_roots.lookup (root);
			if (heap.exception_shape != null && heap.exception_shape.destructor_value (value, (CApi.ValueRef) root)) {
				return true;
			}
		}
		return false;
	}

	internal GenericArray<LlvmScopedHeapCarrier> bind_observed_error(CApi.ValueRef read, LlvmScopedOwnedInputs shape, GenericArray<LlvmScopedOwnedInputs> empty) {
		var options = new GenericArray<LlvmScopedHeapCarrier> ();
		var original = LlvmScopedHeapCarrier.from_error_call (read, shape);
		original.observed_error = true;
		heaps.add (original);
		options.add (original);
		foreach (var contract in empty) {
			var heap = LlvmScopedHeapCarrier.from_error_call (read, shape);
			heap.layout = contract.empty_backing.layout;
			heap.exception_shape = contract.empty_backing.exception_shape;
			heap.empty_base_shape = contract.empty_backing.empty_base_shape;
			heap.empty_contract = contract;
			heap.observed_error = true;
			heaps.add (heap);
			options.add (heap);
		}
		var choice = new LlvmScopedHeapChoice (read, options, (int) choices.length);
		choices.add (choice);
		heap_choices.insert ((void*) read, choice);
		return options;
	}

	internal void invalidate_heap_origin(LlvmScopedHeapCarrier heap, uint[] state, int offset) {
		uint position = 0;
		assert (heaps.find (heap, out position));
		for (int c = 0; c < choices.length + heap_channels.length; c++) {
			if (state[offset + c] == position + 1) {
				state[offset + c] = uint.MAX;
			}
		}
	}

	internal void select_observed_error(CApi.ValueRef read, LlvmScopedHeapCarrier? heap, uint[] state, int offset) {
		uint position = 0;
		state[offset + heap_choices.lookup ((void*) read).ordinal] = heap != null && heaps.find (heap, out position) ? position + 1 : 0;
	}

	internal LlvmScopedOwnerSlot bind_empty_error_field(CApi.ValueRef root, int member) {
		var slot = new LlvmScopedOwnerSlot (root, root, -1, -1);
		add_slot ("%p/%d".printf ((void*) root, member), slot);
		return slot;
	}

	internal LlvmScopedHeapCarrier bind_error_root(CApi.ValueRef call, LlvmScopedOwnedInputs contract) {
		var heap = LlvmScopedHeapCarrier.from_error_call (call, contract);
		heap_roots.insert ((void*) call, heap);
		heaps.add (heap);
		return heap;
	}

	internal LlvmScopedOwnerSlot bind_error_field(CApi.ValueRef call, int member, uint source_position, LlvmScopedPointer pointer, ref int owner_count) {
		var slot = new LlvmScopedOwnerSlot (call, call, pointer.allocation, owner_count++);
		slot.source_position = source_position;
		add_slot ("%p/%d".printf ((void*) call, member), slot);
		return slot;
	}

	internal void seed_field(string path, int allocation) {
		var slot = new LlvmScopedOwnerSlot ((CApi.ValueRef) null, fields.receiver, allocation, allocation);
		slot.entry_live = true;
		add_slot (field_key (path), slot);
	}

	private string? address(CApi.ValueRef value, out CApi.ValueRef root, out CApi.TypeRef type) {
		root = (CApi.ValueRef) null;
		type = (CApi.TypeRef) null;
		if (fields != null && (void*) value == (void*) fields.receiver) {
			root = value;
			type = fields.layout;
			return "%p".printf ((void*) value);
		}
		var heap = selected_heap (value);
		if (heap != null) {
			root = heap.root;
			type = choice_layout (value, heap);
			return "%p".printf ((void*) root);
		}
		if (active_state == null && heap_choices.contains ((void*) value)) {
			root = value;
			type = choice_layout (value, shape_heap (value));
			return "%p".printf ((void*) root);
		}
		if ((void*) CApi.is_instruction (value) == null) {
			return null;
		}
		if (CApi.opcode (value) == CApi.Opcode.ALLOCA) {
			if (CApi.operand_count (value) != 1 || (void*) CApi.is_constant_int (CApi.operand (value, 0)) == null || CApi.const_int_zext (CApi.operand (value, 0)) != 1) {
				return null;
			}
			root = value;
			type = CApi.allocated_type (value);
			return "%p".printf ((void*) value);
		}
		if (CApi.opcode (value) != CApi.Opcode.GEP || CApi.operand_count (value) != 3) {
			return null;
		}
		var key = address (CApi.operand (value, 0), out root, out type);
		var carrier = shape_heap (root);
		if (carrier != null && carrier.exception_shape != null && carrier.exception_shape.member (value, CApi.operand (value, 0)) >= 0) {
			type = CApi.gep_source_type (value);
		}
		if (key == null || (void*) CApi.gep_source_type (value) != (void*) type || CApi.type_kind (type) != CApi.TypeKind.STRUCT || (void*) CApi.is_constant_int (CApi.operand (value, 1)) == null || CApi.const_int_zext (CApi.operand (value, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (value, 2)) == null) {
			return null;
		}
		uint64 member = CApi.const_int_zext (CApi.operand (value, 2));
		if (member >= CApi.count_struct_element_types (type)) {
			return null;
		}
		type = CApi.struct_type_at_index (type, (uint) member);
		return key + "/" + member.to_string ();
	}

	internal LlvmScopedOwnerSlot? lookup(CApi.ValueRef value) {
		CApi.ValueRef root;
		CApi.TypeRef type;
		var key = address (value, out root, out type);
		return key == null ? null : current_slot (addresses.lookup (key));
	}

	internal bool exception_header(CApi.ValueRef address) {
		var heap = heap_owner (address);
		return heap != null && heap.exception_shape != null && heap.exception_shape.member (address, CApi.operand (address, 0)) >= 0;
	}

	internal LlvmScopedHeapCarrier? admit_heap(CApi.ValueRef root, LlvmScopedFieldContract fields) throws LlvmError {
		var prior = heap_roots.lookup ((void*) root);
		if (prior != null) {
			if ((void*) prior.layout != (void*) fields.layout) {
				throw new LlvmError.VERIFICATION ("scoped graph backing changed its exact Class layout");
			}
			return prior;
		}
		var heap = LlvmScopedHeapCarrier.recognize (root, fields);
		if (heap != null) {
			heap_roots.insert ((void*) root, heap);
			heap_roots.insert ((void*) heap.allocation, heap);
			heaps.add (heap);
		}
		return heap;
	}

	private LlvmScopedHeapCarrier? shape_owner(CApi.ValueRef value) {
		CApi.ValueRef root;
		CApi.TypeRef type;
		return address (value, out root, out type) == null ? null : shape_heap (root);
	}

	internal LlvmScopedHeapCarrier? heap_owner(CApi.ValueRef value) {
		CApi.ValueRef root;
		CApi.TypeRef type;
		return address (value, out root, out type) == null ? null : selected_heap (root);
	}

	internal void graph_input(CApi.ValueRef call, CApi.ValueRef input, LlvmScopedOwnerGraph graph, bool forwarding, bool complete = false) throws LlvmError {
		var heap = heap_owner (input);
		if (heap == null && !complete) {
			return;
		}
		if (heap == null || !is_heap_root (input, heap) || (void*) heap.layout != (void*) graph.layout) {
			size_t length;
			throw new LlvmError.VERIFICATION ("scoped graph forwarding requires its complete original field carrier (value=%s, opcode=%d, known=%d)", CApi.value_name (input, out length), (void*) CApi.is_instruction (input) == null ? -1 : (int) CApi.opcode (input), heap == null ? 0 : 1);
		}
		var prior = heap_roots.lookup ((void*) call);
		if (prior != null && prior != heap) {
			throw new LlvmError.VERIFICATION ("scoped graph forwarding changed its original carrier");
		}
		if (forwarding) {
			heap_roots.insert ((void*) call, heap);
		}
	}

	internal CApi.ValueRef receiver_root(CApi.ValueRef call, LlvmScopedBorrowBinding contract) throws LlvmError {
		CApi.ValueRef root;
		CApi.TypeRef type;
		if (address (CApi.operand (call, 0), out root, out type) != null) {
			var heap = selected_heap (CApi.operand (call, 0));
			if (heap != null && heap.empty_contract != null && contract.preserves_carrier (call, heap.empty_base_shape.layout)) {
				return heap.root;
			}
		}
		if (address (CApi.operand (call, 0), out root, out type) != null && contract.preserves_carrier (call, type)) {
			foreach (var slot in slots) {
				if ((void*) slot.root == (void*) root) {
					return root;
				}
			}
		}
		return (CApi.ValueRef) null;
	}

	internal bool bind(CApi.ValueRef store, LlvmScopedPointer pointer, ref int owner_count) throws LlvmError {
		CApi.ValueRef root;
		CApi.TypeRef type;
		var key = address (CApi.operand (store, 1), out root, out type);
		if (key == null || CApi.type_kind (type) != CApi.TypeKind.POINTER || !pointer.root) {
			return false;
		}
		var prior = publication_slot (store, addresses.lookup (key));
		if (prior != null) {
			if (prior.allocation != pointer.allocation) {
				throw new LlvmError.VERIFICATION ("scoped owner write changed its exact incoming allocation");
			}
			return false;
		}
		var slot = new LlvmScopedOwnerSlot (store, root, pointer.allocation, owner_count++);
		add_slot (key, slot);
		return true;
	}

	private string? call_key(CApi.ValueRef call, LlvmScopedFieldContract fields, int field, out CApi.ValueRef root) {
		CApi.TypeRef type;
		var key = address (CApi.operand (call, 0), out root, out type);
		return key == null || (void*) type != (void*) fields.layout ? null : key + fields.path (field);
	}

	internal LlvmScopedOwnerSlot? call_slot(CApi.ValueRef call, LlvmScopedFieldContract fields, int field) {
		CApi.ValueRef root;
		var key = call_key (call, fields, field, out root);
		return key == null ? null : current_slot (addresses.lookup (key));
	}

	private LlvmAsyncFrameBinding? coroutine;
	private HashTable<void*, bool> frame_heap_aliases = new HashTable<void*, bool> (direct_hash, direct_equal);
	private HashTable<int, LlvmScopedHeapCarrier> frame_heaps = new HashTable<int, LlvmScopedHeapCarrier> (direct_hash, direct_equal);
	internal void admit_coroutine(LlvmAsyncFrameBinding frame) {
		coroutine = frame;
		var values = new HashTable<void*, bool> (direct_hash, direct_equal);
		bool changed = false;
		do {
			changed = false;
			foreach (var code in new CApi.ValueRef[] { frame.resume, frame.destroy }) {
				for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
					for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
						var opcode = CApi.opcode (i);
						if (LlvmScopedHeapCarrier.named_call (i, "astra_async_exception") && !values.contains ((void*) i)) {
							values.insert ((void*) i, true);
							changed = true;
						}
						if (opcode == CApi.Opcode.STORE && values.contains ((void*) CApi.operand (i, 0))) {
							int field = frame.lifetime_field (CApi.operand (i, 1));
							if (field >= 0 && !frame_choice_fields.contains (field)) {
								frame_choice_fields.insert (field, true);
								changed = true;
							}
						}
						if (opcode == CApi.Opcode.LOAD && frame_choice_fields.contains (frame.lifetime_field (CApi.operand (i, 0))) && !values.contains ((void*) i)) {
							values.insert ((void*) i, true);
							changed = true;
						}
						if ((opcode == CApi.Opcode.PHI || opcode == CApi.Opcode.SELECT) && CApi.type_kind (CApi.type_of (i)) == CApi.TypeKind.POINTER && !values.contains ((void*) i)) {
							uint count = opcode == CApi.Opcode.PHI ? CApi.incoming_count (i) : 2;
							for (uint p = 0; p < count; p++) {
								if (values.contains ((void*) (opcode == CApi.Opcode.PHI ? CApi.incoming_value (i, p) : CApi.operand (i, p + 1)))) {
									values.insert ((void*) i, true);
									changed = true;
									break;
								}
							}
						}
					}
				}
			}
		} while (changed);
	}

	internal LlvmScopedHeapCarrier? frame_heap(int field) {
		return frame_heaps.lookup (field);
	}

	internal bool frame_heap_store(CApi.ValueRef store, LlvmScopedHeapCarrier heap) {
		return coroutine != null && CApi.opcode (store) == CApi.Opcode.STORE && frame_heaps.lookup (coroutine.lifetime_field (CApi.operand (store, 1))) == heap;
	}

	private LlvmScopedHeapCarrier? resolve_frame_heap(CApi.ValueRef value, LlvmScopedFieldContract fields, HashTable<void*, bool> active) throws LlvmError {
		var known = heap_roots.lookup ((void*) value);
		if (known != null) {
			return known;
		}
		var original = admit_heap (value, fields);
		if (original != null) {
			return original;
		}
		if (coroutine == null || (void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.LOAD || CApi.type_kind (CApi.type_of (value)) != CApi.TypeKind.POINTER || CApi.get_volatile (value) != 0 || CApi.get_ordering (value) != 0 || active.contains ((void*) value)) {
			return null;
		}
		int field = coroutine.lifetime_field (CApi.operand (value, 0));
		if (field < 0 || frame_choice_fields.contains (field)) {
			return null;
		}
		active.insert ((void*) value, true);
		LlvmScopedHeapCarrier? found = null;
		foreach (var code in new CApi.ValueRef[] { coroutine.resume, coroutine.destroy }) {
			for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
				for (var store = CApi.first_instruction (block); (void*) store != null; store = CApi.next_instruction (store)) {
					if (CApi.opcode (store) != CApi.Opcode.STORE || coroutine.lifetime_field (CApi.operand (store, 1)) != field || (void*) CApi.is_constant_pointer_null (CApi.operand (store, 0)) != null) {
						continue;
					}
					var incoming = resolve_frame_heap (CApi.operand (store, 0), fields, active);
					if (incoming == null || found != null && incoming != found) {
						active.remove ((void*) value);
						return null;
					}
					found = incoming;
				}
			}
		}
		active.remove ((void*) value);
		if (found == null) {
			return null;
		}
		var prior = frame_heaps.lookup (field);
		if (prior != null && prior != found) {
			throw new LlvmError.VERIFICATION ("coroutine heap field changed its original backing identity");
		}
		frame_heaps.insert (field, found);
		frame_heap_aliases.insert ((void*) value, true);
		heap_roots.insert ((void*) value, found);
		return found;
	}

	// Discover actual frame cells receiving an original checked-empty
	// allocation. Their null/value accesses still require full cell proof.
	private bool empty_frame_origins(CApi.ValueRef root) {
		if (coroutine == null) {
			return false;
		}
		var values = new HashTable<void*, bool> (direct_hash, direct_equal);
		values.insert ((void*) root, true);
		bool changed = false;
		bool added = false;
		do {
			changed = false;
			foreach (var code in new CApi.ValueRef[] { coroutine.resume, coroutine.destroy }) {
				for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
					for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
						var opcode = CApi.opcode (i);
						if (opcode == CApi.Opcode.STORE && values.contains ((void*) CApi.operand (i, 0))) {
							int field = coroutine.lifetime_field (CApi.operand (i, 1));
							if (field >= 0 && !frame_choice_fields.contains (field)) {
								frame_choice_fields.insert (field, true);
								changed = true;
								added = true;
							}
						}
						if (opcode == CApi.Opcode.LOAD && frame_choice_fields.contains (coroutine.lifetime_field (CApi.operand (i, 0))) && CApi.type_kind (CApi.type_of (i)) == CApi.TypeKind.POINTER && !values.contains ((void*) i)) {
							values.insert ((void*) i, true);
							changed = true;
						}
						if ((opcode == CApi.Opcode.PHI || opcode == CApi.Opcode.SELECT) && CApi.type_kind (CApi.type_of (i)) == CApi.TypeKind.POINTER && !values.contains ((void*) i)) {
							uint count = opcode == CApi.Opcode.PHI ? CApi.incoming_count (i) : 2;
							for (uint p = 0; p < count; p++) {
								if (values.contains ((void*) (opcode == CApi.Opcode.PHI ? CApi.incoming_value (i, p) : CApi.operand (i, p + 1)))) {
									values.insert ((void*) i, true);
									changed = true;
									break;
								}
							}
						}
					}
				}
			}
		} while (changed);
		return added;
	}

	internal bool bind_empty_error(CApi.ValueRef call, LlvmScopedOwnedInputs contract) throws LlvmError {
		if (!contract.empty_constructor_call (call)) {
			return false;
		}
		bool required = coroutine != null && coroutine.scoped_captures != null && coroutine.scoped_captures.deferred_error;
		foreach (var existing in heaps) {
			required = required || existing.exception_shape != null && existing.exception_shape.same (contract.empty_backing.empty_base_shape);
		}
		if (!required) {
			return false;
		}
		uint prior = heap_roots.size () + frame_heaps.size ();
		var heap = coroutine == null ? admit_heap(CApi.operand (call, 0), contract.empty_backing) : resolve_frame_heap (CApi.operand (call, 0), contract.empty_backing, new HashTable<void*, bool> (direct_hash, direct_equal));
		if (heap != null) {
			if (heap.empty_contract != null && heap.empty_contract != contract) {
				throw new LlvmError.VERIFICATION ("empty inherited carrier changed its exact initialization contract");
			}
			if (heap.empty_base_shape == null) {
				if (heap.exception_shape == null || !heap.exception_shape.same (contract.empty_backing.exception_shape) || (void*) heap.layout != (void*) contract.empty_backing.layout) {
					throw new LlvmError.VERIFICATION ("empty error constructor lost its original carrier layout and descriptor");
				}
				heap.empty_base_shape = contract.empty_backing.empty_base_shape;
			}
			heap.empty_contract = contract;
		}
		bool origins = heap != null && (void*) CApi.operand (call, 0) == (void*) heap.root && empty_frame_origins (heap.root);
		return origins || heap_roots.size () + frame_heaps.size () != prior;
	}

	internal bool bind_frame_heap_alias(CApi.ValueRef value) throws LlvmError {
		if (coroutine == null) {
			return false;
		}
		int selected_field = coroutine.lifetime_field (CApi.operand (value, CApi.opcode (value) == CApi.Opcode.LOAD ? 0 : 1));
		if (frame_choice_fields.contains (selected_field)) {
			private_frame_slot (selected_field);
			return false;
		}
		if (CApi.opcode (value) == CApi.Opcode.STORE) {
			int field = coroutine.lifetime_field (CApi.operand (value, 1));
			var incoming = heap_roots.lookup ((void*) CApi.operand (value, 0));
			if (field < 0 || incoming == null) {
				return false;
			}
			if (CApi.get_volatile (value) != 0 || CApi.get_ordering (value) != 0) {
				throw new LlvmError.VERIFICATION ("coroutine heap storage requires exact ordinary pointer accesses");
			}
			var prior = frame_heaps.lookup (field);
			if (prior != null && prior != incoming) {
				throw new LlvmError.VERIFICATION ("coroutine heap field changed its original backing identity");
			}
			if (prior != null) {
				return false;
			}
			frame_heaps.insert (field, incoming);
			return true;
		}
		if (heap_roots.contains ((void*) value) || CApi.opcode (value) != CApi.Opcode.LOAD || CApi.type_kind (CApi.type_of (value)) != CApi.TypeKind.POINTER) {
			return false;
		}
		var heap = frame_heaps.lookup (coroutine.lifetime_field (CApi.operand (value, 0)));
		if (heap == null) {
			return false;
		}
		if (CApi.get_volatile (value) != 0 || CApi.get_ordering (value) != 0) {
			throw new LlvmError.VERIFICATION ("coroutine heap storage requires exact ordinary pointer accesses");
		}
		heap_roots.insert ((void*) value, heap);
		frame_heap_aliases.insert ((void*) value, true);
		return true;
	}

	internal bool bind_call(CApi.ValueRef call, LlvmScopedFieldContract fields, int field, LlvmScopedPointer? pointer, ref int owner_count) throws LlvmError {
		CApi.ValueRef existing;
		CApi.TypeRef physical;
		var receiver = CApi.operand (call, 0);
		if (coroutine != null) {
			resolve_frame_heap (receiver, fields, new HashTable<void*, bool> (direct_hash, direct_equal));
		}
		if (address (receiver, out existing, out physical) == null) {
			var heap = LlvmScopedHeapCarrier.recognize (receiver, fields);
			if (heap != null) {
				heap_roots.insert ((void*) receiver, heap);
				heap_roots.insert ((void*) heap.allocation, heap);
				heaps.add (heap);
			}
		} else if (!fields.default_backing && !heap_roots.contains ((void*) receiver)) {
			throw new LlvmError.VERIFICATION ("scoped field carrier cannot bypass its prescribed allocator backing");
		}
		CApi.ValueRef root;
		var key = call_key (call, fields, field, out root);
		if (key == null || pointer != null && !pointer.root || pointer == null && !fields.empty_field (field) && (void*) CApi.is_constant_pointer_null (CApi.operand (call, (uint) fields.input (field) + 1)) == null) {
			throw new LlvmError.VERIFICATION ("scoped field transfer requires its exact nonescaping local carrier");
		}
		var prior = publication_slot (call, addresses.lookup (key));
		if (prior != null) {
			if (prior.allocation != (pointer == null ? -1 : pointer.allocation) || prior.source_position != fields.input (field) + 1) {
				throw new LlvmError.VERIFICATION ("scoped field calls require one exact transfer per physical slot");
			}
			return false;
		}
		// A proven empty field has a storage obligation, never an allocation.
		var slot = new LlvmScopedOwnerSlot (call, root, pointer == null ? -1 : pointer.allocation, pointer == null ? -1 : owner_count++);
		slot.source_position = (uint) fields.input (field) + 1;
		add_slot (key, slot);
		return true;
	}

	internal bool checked_destructor(LlvmScopedHeapCarrier heap, CApi.ValueRef call, CApi.ValueRef root, HashTable<void*, LlvmScopedOwnedInputs>? contracts) throws LlvmError {
		if (heap.exception_shape == null || !heap.exception_shape.destructor_call (call, root)) {
			return false;
		}
		var shape = heap.empty_contract == null ? heap.exception_shape : heap.empty_base_shape;
		var contract = contracts == null ? null : contracts.lookup ((void*) shape.destructor_target ());
		if (contract == null || contract.fields == null || contract.fields.constructor || (void*) contract.fields.layout != (void*) shape.layout) {
			throw new LlvmError.VERIFICATION ("scoped exception dynamic retirement requires its exact native field contract");
		}
		contract.verify ();
		if (heap.empty_contract != null) {
			heap.empty_contract.verify ();
		}
		return true;
	}

	private bool empty_payload_address(CApi.ValueRef value) {
		CApi.ValueRef root;
		CApi.TypeRef type;
		if (address (value, out root, out type) == null) {
			return false;
		}
		var options = candidates (root);
		if (options == null) {
			return false;
		}
		foreach (var heap in options) {
			if (heap.empty_contract != null && heap.exception_shape.member (value, CApi.operand (value, 0)) < 0) {
				return true;
			}
		}
		return false;
	}

	internal void verify_addresses(HashTable<void*, LlvmScopedOwnedInputs>? contracts, HashTable<void*, LlvmScopedBorrowBinding>? borrows, LlvmScopedOwnedInputs? output, LlvmScopedFreshResult? fresh_output) throws LlvmError {
		var roots = new HashTable<void*, bool> (direct_hash, direct_equal);
		foreach (var slot in slots) {
			roots.insert ((void*) slot.root, true);
		}
		foreach (void* root in heap_roots.get_keys ()) {
			roots.insert (root, true);
		}
		foreach (var choice in choices) {
			roots.insert ((void*) choice.value, true);
		}
		if (fields != null) {
			roots.insert ((void*) fields.receiver, true);
		}
		var seen = new HashTable<void*, bool> (direct_hash, direct_equal);
		var pending = new GenericArray<void*> ();
		foreach (void* root in roots.get_keys ()) {
			pending.add (root);
		}
		for (int p = 0; p < pending.length; p++) {
			var value = (CApi.ValueRef) pending[p];
			if (seen.contains ((void*) value)) {
				continue;
			}
			seen.insert ((void*) value, true);
			for (var use = CApi.first_use (value); (void*) use != null; use = CApi.next_use (use)) {
				var user = CApi.user (use);
				if ((void*) CApi.is_instruction (user) == null) {
					throw new LlvmError.VERIFICATION ("scoped owner storage address escaped its local frame");
				}
				var opcode = CApi.opcode (user);
				if (opcode == CApi.Opcode.STORE && (void*) CApi.operand (user, 0) == (void*) value && shape_heap (value) != null && (frame_heap_store (user, shape_heap (value)) || heap_slot_store (user))) {
					continue;
				}
				if (opcode == CApi.Opcode.GEP && (void*) CApi.operand (user, 0) == (void*) value) {
					CApi.ValueRef root;
					CApi.TypeRef type;
					if (address (user, out root, out type) == null) {
						throw new LlvmError.VERIFICATION ("scoped owner storage lost its exact physical field path");
					}
					pending.add ((void*) user);
					continue;
				}
				if ((opcode == CApi.Opcode.PHI || opcode == CApi.Opcode.SELECT) && shape_heap (value) != null && aliases_into (value, user)) {
					pending.add ((void*) user);
					continue;
				}
				if (opcode == CApi.Opcode.STORE) {
					if (empty_payload_address (value)) {
						throw new LlvmError.VERIFICATION ("checked-empty inherited error cannot acquire a payload store");
					}
					var heap = shape_owner (value);
					if (heap != null && heap.exception_shape != null && (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.GEP && heap.exception_shape.member (value, CApi.operand (value, 0)) == 0 && (heap.returned_error || (void*) CApi.operand (value, 0) != (void*) heap.root && !frame_heap_aliases.contains ((void*) CApi.operand (value, 0)))) {
						throw new LlvmError.VERIFICATION ("scoped exception caller cannot overwrite its inherited descriptor");
					}
				}
				if (opcode == CApi.Opcode.CALL && coroutine != null && output != null && output.deferred_error && LlvmScopedHeapCarrier.named_call (user, "astra_async_complete") && CApi.argument_count (user) == 3 && (void*) CApi.operand (user, 0) == (void*) coroutine.task && (void*) CApi.operand (user, 2) == (void*) value && shape_heap (value) != null && shape_heap (value).exception_shape != null && (shape_heap (value).exception_shape.same (output.error_shape) || shape_heap (value).empty_base_shape != null && shape_heap (value).empty_base_shape.same (output.error_shape))) {
					continue;
				}
				if (opcode == CApi.Opcode.RET && output != null && output.error_count != 0 && error_view (value, output.error_shape)) {
					continue;
				}
				// Fresh publication is checked against its original allocation,
				// context and complete live child graph by the return verifier.
				if (opcode == CApi.Opcode.RET && fresh_output != null && fresh_output.graph != null && shape_heap (value) != null && (void*) shape_heap (value).layout == (void*) fresh_output.graph.layout) {
					continue;
				}
				if (opcode == CApi.Opcode.CALL && shape_heap (value) != null) {
					var options = candidates (value);
					bool cleanup = true;
					foreach (var heap in options) {
						cleanup = checked_destructor (heap, user, value, contracts) && cleanup;
					}
					if (cleanup) {
						continue;
					}
				}
				if (shape_heap (value) != null) {
					if (opcode == CApi.Opcode.ICMP && (CApi.predicate (user) == CApi.IntPredicate.EQ || CApi.predicate (user) == CApi.IntPredicate.NE) && ((void*) CApi.is_constant_pointer_null (CApi.operand (user, 0)) != null || (void*) CApi.is_constant_pointer_null (CApi.operand (user, 1)) != null)) {
						continue;
					}
					if (opcode == CApi.Opcode.CALL && CApi.argument_count (user) > 0 && (void*) CApi.operand (user, 0) == (void*) value && shape_heap (value).release_call (user)) {
						continue;
					}
				}
				if (opcode == CApi.Opcode.CALL && contracts != null && CApi.argument_count (user) > 0 && (void*) CApi.operand (user, 0) == (void*) value && shape_heap (value) != null) {
					var contract = contracts.lookup ((void*) CApi.called_value (user));
					var heap = shape_heap (value);
					if (contract != null && contract.empty_backing != null && (void*) contract.empty_backing.layout == (void*) heap.layout && contract.empty_constructor_call (user)) {
						continue;
					}
				}
				if (opcode == CApi.Opcode.CALL && contracts != null && CApi.argument_count (user) > 0 && (void*) CApi.operand (user, 0) == (void*) value) {
					var contract = contracts.lookup ((void*) CApi.called_value (user));
					if (contract != null && contract.fields != null && contract.field_call (user)) {
						CApi.ValueRef root;
						CApi.TypeRef type;
						var key = address (value, out root, out type);
						bool unique = true;
						for (uint a = 1; a < CApi.argument_count (user); a++) {
							unique = unique && (void*) CApi.operand (user, a) != (void*) value;
						}
						if (key != null && (void*) type == (void*) contract.fields.layout && unique) {
							continue;
						}
					}
				}
				if (opcode == CApi.Opcode.CALL && contracts != null) {
					var contract = contracts.lookup ((void*) CApi.called_value (user));
					if (contract != null && contract.owner_graph != null && contract.graph_parameter >= 0 && (uint) contract.graph_parameter < CApi.argument_count (user) && (void*) CApi.operand (user, contract.graph_parameter) == (void*) value && shape_heap (value) != null && (void*) shape_heap (value).layout == (void*) contract.owner_graph.layout && (!contract.graph_forwarding || heap_roots.lookup ((void*) user) == shape_heap (value))) {
						contract.verify ();
						if (contract.graph_forwarding) {
							pending.add ((void*) user);
						}
						continue;
					}
				}
				if (opcode == CApi.Opcode.CALL && contracts != null) {
					var contract = contracts.lookup ((void*) CApi.called_value (user));
					if (contract != null && contract.fields != null && contract.fields.publishes) {
						bool admitted = false;
						for (int g = 0; g < contract.count; g++) {
							var graph = contract.input_graph (g);
							if (graph != null && contract.physical_position (g) < CApi.argument_count (user) && (void*) CApi.operand (user, contract.physical_position (g)) == (void*) value && shape_heap (value) != null && (void*) shape_heap (value).layout == (void*) graph.layout) {
								contract.field_call (user);
								admitted = true;
							}
						}
						if (admitted) {
							continue;
						}
					}
				}
				if (opcode == CApi.Opcode.CALL && borrows != null && CApi.argument_count (user) > 0 && (void*) CApi.operand (user, 0) == (void*) value) {
					var contract = borrows.lookup ((void*) CApi.called_value (user));
					if (contract != null) {
						CApi.ValueRef root;
						CApi.TypeRef type;
						var heap = shape_heap (value);
						if (address (value, out root, out type) != null && (contract.preserves_carrier (user, type) || heap != null && heap.empty_contract != null && contract.preserves_carrier (user, heap.empty_base_shape.layout))) {
							continue;
						}
					}
				}
				if (opcode == CApi.Opcode.LOAD && (void*) CApi.operand (user, 0) == (void*) value || opcode == CApi.Opcode.STORE && (void*) CApi.operand (user, 1) == (void*) value && (void*) CApi.operand (user, 0) != (void*) value) {
					CApi.ValueRef root;
					CApi.TypeRef type;
					address (value, out root, out type);
					var accessed = opcode == CApi.Opcode.LOAD ? CApi.type_of (user) : CApi.type_of (CApi.operand (user, 0));
					if ((void*) type != (void*) accessed || CApi.type_kind (type) != CApi.TypeKind.POINTER && CApi.type_kind (type) != CApi.TypeKind.INTEGER && (fields == null || !fields.buffer_address (value, type)) || CApi.get_volatile (user) != 0 || CApi.get_ordering (user) != 0) {
						throw new LlvmError.VERIFICATION ("scoped owner storage requires exact ordinary scalar accesses");
					}
					continue;
				}
				size_t name_length;
				string name = CApi.value_name (user, out name_length);
				var detail = new StringBuilder ();
				if (opcode == CApi.Opcode.PHI) {
					for (uint i = 0; i < CApi.incoming_count (user); i++) {
						var incoming = CApi.incoming_value (user, i);
						detail.append_printf (" [%s:null=%d,carrier=%d]", CApi.value_name (incoming, out name_length), (void*) CApi.is_constant_pointer_null (incoming) != null ? 1 : 0, heap_roots.contains ((void*) incoming) ? 1 : 0);
					}
				}
				if (opcode == CApi.Opcode.CALL) {
					detail.append_printf (" [callee=%s]", CApi.value_name (CApi.called_value (user), out name_length));
				}
				throw new LlvmError.VERIFICATION ("scoped owner storage address escaped its local frame (opcode=%d, value=%s)%s", (int) opcode, name, detail.str);
			}
		}
	}

}
// Reconstruct local scoped allocation obligations from actual IR. No upstream
// owner graph, lowering event inventory or mutable artifact snapshot is used.
// Carriers and calls need their exact ownership effects before admission here.
internal class LlvmScopedAllocationVerifier : Object {
	private CApi.ValueRef function;
	private LlvmAsyncFrameBinding? coroutine;
	private int frame_offset;
	private int held_offset;
	private int wait_offset;
	private int phase_offset;
	private int observed_offset;
	private HashTable<void*, LlvmScopedHeldTask> result_data = new HashTable<void*, LlvmScopedHeldTask> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedHeldTask> empty_result_values = new HashTable<void*, LlvmScopedHeldTask> (direct_hash, direct_equal);
	private HashTable<void*, uint> empty_body_values = new HashTable<void*, uint> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedHeldTask> result_reads = new HashTable<void*, LlvmScopedHeldTask> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedHeldTask> plain_result_reads = new HashTable<void*, LlvmScopedHeldTask> (direct_hash, direct_equal);
	private LlvmScopedErrorCall? deferred_error;
	private int deferred_offset;
	private int deferred_empty_offset;
	private int result_offset;
	private int result_live_offset;
	private int result_discard_offset;
	private GenericArray<LlvmScopedPointer?> result_owners = new GenericArray<LlvmScopedPointer?> ();
	private GenericArray<void*> result_stores = new GenericArray<void*> ();
	private LlvmAsyncRecordResult? result_shape { get { return coroutine == null ? null : coroutine.scoped_result; } }
	private bool result_store(CApi.ValueRef instruction) {
		return result_shape != null && CApi.opcode (instruction) == CApi.Opcode.STORE && frame_field (CApi.operand (instruction, 1)) == 0;
	}

	private HashTable<void*, LlvmScopedCapturedTask>? captured_tasks;
	private GenericArray<LlvmScopedHeldTask> held_tasks = new GenericArray<LlvmScopedHeldTask> ();
	private HashTable<void*, LlvmScopedHeldTask> held_aliases = new HashTable<void*, LlvmScopedHeldTask> (direct_hash, direct_equal);
	private HashTable<int, LlvmScopedHeldTask> held_fields = new HashTable<int, LlvmScopedHeldTask> (direct_hash, direct_equal);
	private HashTable<int, LlvmScopedPointer> frame_values = new HashTable<int, LlvmScopedPointer> (direct_hash, direct_equal);
	private HashTable<int, LlvmScopedPointer> frame_flags = new HashTable<int, LlvmScopedPointer> (direct_hash, direct_equal);
	private int frame_field(CApi.ValueRef address) {
		return coroutine == null ? -1 : coroutine.lifetime_field (address);
	}

	private int heap_choice_offset;
	private int host_error_offset;
	private GenericArray<LlvmScopedHostError> host_errors = new GenericArray<LlvmScopedHostError> ();
	private HashTable<void*, LlvmScopedHostError> host_error_calls = new HashTable<void*, LlvmScopedHostError> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedHostError> host_error_reads = new HashTable<void*, LlvmScopedHostError> (direct_hash, direct_equal);
	private int owner_count;
	private int owner_offset;
	private int storage_offset;
	private int heap_offset;
	private int empty_heap_offset;
	private int success_offset;
	private int call_offset;
	private int error_offset;
	private int phi_offset;
	private int stack_offset;
	private int graph_offset;
	private int condition_offset;
	private GenericArray<void*> condition_phis = new GenericArray<void*> ();
	private HashTable<void*, int> condition_positions = new HashTable<void*, int> (direct_hash, direct_equal);
	private LlvmScopedConstructorStack? constructor_stack;
	private GenericArray<void*> pointer_phis = new GenericArray<void*> ();
	private HashTable<void*, int> phi_positions = new HashTable<void*, int> (direct_hash, direct_equal);
	private HashTable<void*, bool> constructor_results = new HashTable<void*, bool> (direct_hash, direct_equal);
	private GenericArray<LlvmScopedErrorCall> error_channels = new GenericArray<LlvmScopedErrorCall> ();
	private HashTable<void*, LlvmScopedErrorCall> error_calls = new HashTable<void*, LlvmScopedErrorCall> (direct_hash, direct_equal);
	private GenericArray<LlvmScopedCheckedCall> checked_channels = new GenericArray<LlvmScopedCheckedCall> ();
	private HashTable<void*, LlvmScopedCheckedCall> checked_calls = new HashTable<void*, LlvmScopedCheckedCall> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedCheckedCall> checked_slots = new HashTable<void*, LlvmScopedCheckedCall> (direct_hash, direct_equal);
	private LlvmScopedOwnerStorage storage = new LlvmScopedOwnerStorage ();
	private GenericArray<void*> blocks = new GenericArray<void*> ();
	private GenericArray<void*> allocations = new GenericArray<void*> ();
	private GenericArray<bool> contextual_allocations = new GenericArray<bool> ();
	private GenericArray<bool> scoped_allocations = new GenericArray<bool> ();
	private GenericArray<void*> counts = new GenericArray<void*> ();
	private GenericArray<void*> sizes = new GenericArray<void*> ();
	private GenericArray<void*> alignments = new GenericArray<void*> ();
	private GenericArray<void*> tags = new GenericArray<void*> ();
	private LlvmScopedOwnedInputs? owned_inputs;
	private HashTable<void*, LlvmScopedOwnedInputs>? consuming;
	private GenericArray<void*> contexts = new GenericArray<void*> ();
	private HashTable<void*, LlvmScopedTaskFrame>? task_frames;
	private HashTable<int, LlvmScopedTaskFrame> task_allocations = new HashTable<int, LlvmScopedTaskFrame> (direct_hash, direct_equal);
	private HashTable<int, LlvmScopedOwnerGraph> fresh_graphs = new HashTable<int, LlvmScopedOwnerGraph> (direct_hash, direct_equal);
	private HashTable<int, GenericArray<void*>> fresh_dependencies = new HashTable<int, GenericArray<void*>> (direct_hash, direct_equal);
	private GenericArray<void*> loans = new GenericArray<void*> ();
	private LlvmScopedContextInputs? inputs;
	private HashTable<void*, LlvmScopedPointer> pointers = new HashTable<void*, LlvmScopedPointer> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedRecordCall> record_calls = new HashTable<void*, LlvmScopedRecordCall> (direct_hash, direct_equal);
	private bool has_record_calls;
	private bool has_class_calls;
	private HashTable<void*, bool> null_results = new HashTable<void*, bool> (direct_hash, direct_equal);
	private HashTable<void*, uint> null_lifetimes = new HashTable<void*, uint> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedBorrowBinding>? borrows;
	private HashTable<void*, LlvmScopedContextInputs>? context_callees;
	private HashTable<void*, LlvmScopedClassLoans>? class_callees;
	private HashTable<void*, LlvmScopedFreshResult>? fresh_callees;
	private LlvmScopedFreshResult? fresh_result;
	private LlvmScopedAllocationVerifier (CApi.ValueRef function, HashTable<void*, LlvmScopedBorrowBinding>? borrows, LlvmScopedContextInputs? inputs, HashTable<void*, LlvmScopedOwnedInputs>? consuming, HashTable<void*, LlvmScopedContextInputs>? context_callees, HashTable<void*, LlvmScopedClassLoans>? class_callees, HashTable<void*, LlvmScopedFreshResult>? fresh_callees, HashTable<void*, LlvmScopedTaskFrame>? task_frames, LlvmAsyncFrameBinding? coroutine = null, HashTable<void*, LlvmScopedCapturedTask>? captured_tasks = null) {
		this.captured_tasks = captured_tasks;
		this.coroutine = coroutine;
		this.task_frames = task_frames;
		this.fresh_callees = fresh_callees;
		fresh_result = fresh_callees == null ? null : fresh_callees.lookup ((void*) function);
		this.class_callees = class_callees;
		this.context_callees = context_callees;
		this.function = function;
		this.borrows = borrows;
		this.inputs = inputs;
		this.consuming = consuming;
		owned_inputs = coroutine == null ? consuming == null ? null : consuming.lookup ((void*) function) : coroutine.scoped_captures;
	}

	private static string callee(CApi.ValueRef call) {
		var target = CApi.called_value (call);
		if ((void*) CApi.is_function (target) == null) {
			return "";
		}
		size_t length;
		return CApi.value_name (target, out length);
	}

	private static void provider(CApi.ValueRef call, string role) throws LlvmError {
		var context = CApi.type_context (CApi.type_of (call));
		var pointer = CApi.pointer_type_in_context (context, 0);
		var word = CApi.int32_type_in_context (context);
		var size = CApi.int_type_in_context (context, 64);
		CApi.TypeRef[] parameters = role == "allocate" ? new CApi.TypeRef[] {
			pointer, size, size, word, size, word
		} : role == "open" ? new CApi.TypeRef[] {
			pointer, word, word, word
		} : role == "release" ? new CApi.TypeRef[] {
			pointer, size
		} : new CApi.TypeRef[] {
			pointer
		};
		var type = CApi.function_type (role == "destroy" ? CApi.void_type_in_context (context) : role == "release" ? word : pointer, parameters, parameters.length, 0);
		var target = CApi.called_value (call);
		if ((void*) CApi.is_function (target) == null || CApi.count_basic_blocks (target) != 0 || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.instruction_call_conv (call) != CApi.CallConv.C || (void*) CApi.global_value_type (target) != (void*) type || (void*) CApi.called_function_type (call) != (void*) type) {
			throw new LlvmError.VERIFICATION ("scoped lifetime operation lost its exact external runtime ABI");
		}
	}

	private static bool number(CApi.ValueRef value, uint64 expected) {
		return (void*) CApi.is_constant_int (value) != null && CApi.const_int_zext (value) == expected;
	}

	private static bool null_pointer(CApi.ValueRef value) {
		return (void*) CApi.is_constant_pointer_null (value) != null;
	}

	private static bool empty_join(CApi.ValueRef value, HashTable<void*, bool> active) {
		if (null_pointer (value)) {
			return true;
		}
		if ((void*) CApi.is_instruction (value) == null || active.contains ((void*) value)) {
			return false;
		}
		var opcode = CApi.opcode (value);
		if (opcode != CApi.Opcode.PHI && opcode != CApi.Opcode.SELECT) {
			return false;
		}
		active.insert ((void*) value, true);
		uint count = opcode == CApi.Opcode.PHI ? CApi.incoming_count (value) : 2;
		bool empty = count != 0;
		for (uint i = 0; i < count && empty; i++) {
			empty = empty_join (opcode == CApi.Opcode.PHI ? CApi.incoming_value (value, i) : CApi.operand (value, i + 1), active);
		}
		active.remove ((void*) value);
		return empty;
	}

	private LlvmScopedPointer? pointer(CApi.ValueRef value) {
		return storage.owner_read_pointer (value) ?? pointers.lookup ((void*) value);
	}

	internal static void verify(CApi.ModuleRef module, HashTable<void*, LlvmScopedBorrowBinding>? borrows = null, HashTable<void*, LlvmScopedContextInputs>? inputs = null, HashTable<void*, LlvmScopedOwnedInputs>? consuming = null, HashTable<void*, LlvmScopedClassLoans>? class_callees = null, HashTable<void*, LlvmScopedFreshResult>? fresh_callees = null, HashTable<void*, LlvmScopedTaskFrame>? task_frames = null, GenericArray<LlvmAsyncFrameBinding>? coroutines = null, HashTable<void*, LlvmScopedCapturedTask>? captured_tasks = null) throws LlvmError {
		// A mode-3 descriptor may enter only an original registered cold factory.
		// Reconstruct membership from LLVM uses so deleting a sidecar is not a bypass.
		for (var function = CApi.first_function (module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || callee (instruction) != "astra_context17_frame_descriptor" || CApi.argument_count (instruction) != 1 || !number (CApi.operand (instruction, 0), 3)) {
						continue;
					}
					for (var use = CApi.first_use (instruction); (void*) use != null; use = CApi.next_use (use)) {
						var user = CApi.user (use);
						var frame = task_frames == null ? null : task_frames.lookup ((void*) user);
						if (frame == null || CApi.opcode (user) != CApi.Opcode.CALL || CApi.argument_count (user) < 3 || (void*) CApi.operand (user, CApi.argument_count (user) - 2) != (void*) instruction) {
							throw new LlvmError.VERIFICATION ("unregistered scoped task frame lacks its original context lifetime proof");
						}
						frame.verify_call (user);
					}
				}
			}
		}
		// Scope-free buffer companions delegate their indivisible ownership to
		// the exact emitted lifecycle, including when no scoped child is formal.
		if (consuming != null) {
			foreach (var contract in consuming.get_values ()) {
				if (contract.fields != null && (contract.fields.plain_buffers || contract.fields.plain_records)) {
					contract.verify ();
				}
			}
		}
		var joined = new HashTable<void*, LlvmAsyncFrameBinding> (direct_hash, direct_equal);
		if (coroutines != null) {
			foreach (var frame in coroutines) {
				if (frame.scoped_captures != null) {
					frame.verify_continuations ();
					frame.scoped_captures.verify ();
					joined.insert ((void*) frame.resume, frame);
					joined.insert ((void*) frame.destroy, frame);
				}
			}
		}
		for (var function = CApi.first_function (module); (void*) function != null; function = CApi.next_function (function)) {
			if (CApi.count_basic_blocks (function) == 0) {
				continue;
			}
			var frame = joined.lookup ((void*) function);
			if (frame != null && (void*) function == (void*) frame.destroy) {
				continue;
			}
			new LlvmScopedAllocationVerifier (function, borrows, inputs == null ? null : inputs.lookup ((void*) function), consuming, inputs, class_callees, fresh_callees, task_frames, frame, captured_tasks).analyze ();
		}
	}

	private void inventory() throws LlvmError {
		if (fresh_result != null) {
			fresh_result.verify_signature ();
		}
		if (owned_inputs != null && owned_inputs.fields != null) {
			storage.admit (owned_inputs.fields);
		}
		if (owned_inputs != null && owned_inputs.fields != null && owned_inputs.fields.checked_constructor && owned_inputs.fields.count != 0) {
			constructor_stack = new LlvmScopedConstructorStack (function, owned_inputs.fields.unwind_field_count);
		}
		if (owned_inputs != null) {
			owned_inputs.verify_signature ();
			owned_inputs.verify_success_slot ();
			for (int p = 0; p < owned_inputs.count; p++) {
				int ordinal = allocations.length;
				var value = owned_inputs.parameter (p);
				allocations.add ((void*) value);
				contextual_allocations.add (owned_inputs.contextual_input (p));
				scoped_allocations.add (owned_inputs.scoped_input (p));
				contexts.add (null);
				tags.add ((void*) owned_inputs.tag (p));
				counts.add ((void*) CApi.const_int (CApi.type_of (owned_inputs.size (p)), 1, 0));
				sizes.add ((void*) owned_inputs.size (p));
				alignments.add ((void*) owned_inputs.alignment (p));
				pointers.insert ((void*) value, new LlvmScopedPointer (ordinal, true));
				null_lifetimes.insert ((void*) value, 1);
			}
		}
		if (owned_inputs != null && owned_inputs.fields != null && !owned_inputs.fields.constructor) {
			for (int f = 0; f < owned_inputs.fields.count; f++) {
				storage.seed_field (owned_inputs.fields.path (f), owned_inputs.field_slot (f));
			}
		}
		if (inputs != null) {
			inputs.verify_signature ();
			for (int p = 0; p < inputs.count; p++) {
				loans.add ((void*) inputs.parameter (p));
			}
		}
		// Avoid merging differently sized pointer arrays: GLib's sized-free
		// optimization can select the larger size for the scalar path.
		int code_count = coroutine == null ? 1 : 2;
		for (int c = 0; c < code_count; c++) {
			var code = coroutine == null ? function : c == 0 ? coroutine.resume : coroutine.destroy;
			for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
				blocks.add ((void*) block);
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (task_frames != null && task_frames.contains ((void*) instruction)) {
						var frame = task_frames.lookup ((void*) instruction);
						frame.verify_call (instruction);
						var context = frame.backing_context ();
						bool local = (void*) CApi.is_instruction (context) != null && CApi.opcode (context) == CApi.Opcode.CALL && callee (context) == "astra_context17_open_scoped";
						if (!local && !(inputs != null && inputs.contains (context))) {
							throw new LlvmError.VERIFICATION ("scoped task frame requires its exact local or borrowed context");
						}
						if (local) {
							provider (context, "open");
						}
						int ordinal = allocations.length;
						allocations.add ((void*) instruction);
						contextual_allocations.add (true);
						scoped_allocations.add (true);
						contexts.add ((void*) context);
						var word = CApi.int32_type_in_context (CApi.type_context (CApi.type_of (instruction)));
						tags.add ((void*) CApi.const_null (word));
						counts.add ((void*) CApi.const_int (word, 1, 0));
						sizes.add ((void*) CApi.const_int (word, 1, 0));
						alignments.add ((void*) CApi.const_int (word, 1, 0));
						task_allocations.insert (ordinal, frame);
						pointers.insert ((void*) instruction, new LlvmScopedPointer (ordinal, true));
						null_lifetimes.insert ((void*) instruction, 1);
						if (!loans.find ((void*) context)) {
							loans.add ((void*) context);
						}
					}
					if (captured_tasks != null && captured_tasks.contains ((void*) instruction)) {
						has_class_calls = true;
					}
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && borrows != null) {
						var receiver = borrows.lookup ((void*) CApi.called_value (instruction));
						if (receiver != null && receiver.scoped_receiver) {
							has_class_calls = true;
						}
					}
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && class_callees != null && class_callees.contains ((void*) CApi.called_value (instruction))) {
						has_class_calls = true;
					}
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null) {
							if (contract.aggregate_fields != 0) {
								contract.verify_record_call (instruction);
							}
							has_record_calls = true;
						}
					}
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && fresh_callees != null) {
						var fresh = fresh_callees.lookup ((void*) CApi.called_value (instruction));
						if (fresh != null) {
							fresh.verify_call (instruction);
							var context = CApi.operand (instruction, fresh.context_position);
							bool local = (void*) CApi.is_instruction (context) != null && CApi.opcode (context) == CApi.Opcode.CALL && callee (context) == "astra_context17_open_scoped";
							bool borrowed = inputs != null && inputs.contains (context);
							if (!local && !borrowed) {
								throw new LlvmError.VERIFICATION ("fresh scoped caller requires its original live context or borrowed input");
							}
							if (local) {
								provider (context, "open");
							}
							int ordinal = allocations.length;
							var dependencies = new GenericArray<void*> ();
							for (int d = 0; d < fresh.dependency_count; d++) {
								var dependency = CApi.operand (instruction, fresh.dependency_position (d));
								bool local_dependency = (void*) CApi.is_instruction (dependency) != null && CApi.opcode (dependency) == CApi.Opcode.CALL && callee (dependency) == "astra_context17_open_scoped";
								if (!local_dependency && !(inputs != null && inputs.contains (dependency))) {
									throw new LlvmError.VERIFICATION ("fresh scoped graph requires every original borrowed or local context");
								}
								if (local_dependency) {
									provider (dependency, "open");
								}
								if (!loans.find ((void*) dependency)) {
									loans.add ((void*) dependency);
								}
								dependencies.add ((void*) dependency);
							}
							fresh_dependencies.insert (ordinal, dependencies);
							if (fresh.graph != null) {
								fresh_graphs.insert (ordinal, fresh.graph);
							}
							allocations.add ((void*) instruction);
							contextual_allocations.add (true);
							scoped_allocations.add (true);
							contexts.add ((void*) context);
							tags.add ((void*) fresh.tag);
							counts.add ((void*) CApi.const_int (CApi.type_of (fresh.size), 1, 0));
							sizes.add ((void*) fresh.size);
							alignments.add ((void*) fresh.alignment);
							if (!loans.find ((void*) context)) {
								loans.add ((void*) context);
							}
							pointers.insert ((void*) instruction, new LlvmScopedPointer (ordinal, true));
							null_lifetimes.insert ((void*) instruction, 1);
						}
					}
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						var fields = contract == null ? null : contract.fields;
						if (fields != null && fields.constructor && !fields.scoped_receiver && fields.count != 0 && !fields.empty_exception) {
							contract.field_call (instruction);
							var heap = storage.admit_heap (CApi.operand (instruction, 0), fields);
							if (heap != null && pointer (heap.allocation) == null) {
								int ordinal = allocations.length;
								allocations.add ((void*) heap.allocation);
								contextual_allocations.add (!fields.default_backing);
								scoped_allocations.add (false);
								contexts.add (null);
								tags.add ((void*) fields.receiver_tag);
								counts.add ((void*) CApi.const_int (CApi.type_of (fields.receiver_size), 1, 0));
								sizes.add ((void*) fields.receiver_size);
								alignments.add ((void*) fields.receiver_alignment);
								pointers.insert ((void*) heap.allocation, new LlvmScopedPointer (ordinal, true));
								null_lifetimes.insert ((void*) heap.allocation, 1);
							}
						}
					}
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || callee (instruction) != "astra_context17_allocate_mode") {
						continue;
					}
					if (CApi.argument_count (instruction) != 6) {
						throw new LlvmError.VERIFICATION ("scoped allocation requires the exact allocator ABI");
					}
					var context = CApi.operand (instruction, 0);
					bool local = (void*) CApi.is_instruction (context) != null && CApi.opcode (context) == CApi.Opcode.CALL && callee (context) == "astra_context17_open_scoped";
					bool borrowed = inputs != null && inputs.contains (context);
					if ((local || borrowed) && !number (CApi.operand (instruction, 5), 3)) {
						throw new LlvmError.VERIFICATION ("local scoped allocation lost its exact affine mode");
					}
					if (!number (CApi.operand (instruction, 5), 3)) {
						continue;
					}
					if (!local && !borrowed) {
						throw new LlvmError.VERIFICATION ("scoped allocation requires a complete emitted context-input contract");
					}
					provider (instruction, "allocate");
					if (local) {
						provider (context, "open");
					}
					int ordinal = allocations.length;
					allocations.add ((void*) instruction);
					contextual_allocations.add (true);
					scoped_allocations.add (true);
					contexts.add ((void*) context);
					tags.add ((void*) CApi.operand (instruction, 4));
					counts.add ((void*) CApi.operand (instruction, 1));
					sizes.add ((void*) CApi.operand (instruction, 2));
					alignments.add ((void*) CApi.operand (instruction, 3));
					if (!loans.find ((void*) context)) {
						loans.add ((void*) context);
					}
					pointers.insert ((void*) instruction, new LlvmScopedPointer (ordinal, true));
					null_lifetimes.insert ((void*) instruction, 1);
				}
			}
		}
	}

	private bool checked_alias(CApi.ValueRef call, LlvmScopedOwnedInputs contract) throws LlvmError {
		if (contract.checked_success && contract.aggregate_fields != 0) {
			return checked_record_alias (call, contract);
		}
		if (!contract.checked_success || checked_calls.contains ((void*) call)) {
			return false;
		}
		var incoming = pointer (CApi.operand (call, (uint) contract.returned_parameter));
		if (incoming == null) {
			return false;
		}
		if (!incoming.root || !contract.accepts (call, (uint) contract.returned_parameter, (CApi.ValueRef) tags[incoming.allocation], (CApi.ValueRef) counts[incoming.allocation], (CApi.ValueRef) sizes[incoming.allocation], (CApi.ValueRef) alignments[incoming.allocation], true)) {
			throw new LlvmError.VERIFICATION ("checked scoped call lost its exact returned allocation");
		}
		var slot = CApi.operand (call, 0);
		if ((void*) CApi.is_instruction (slot) == null || CApi.opcode (slot) != CApi.Opcode.ALLOCA || CApi.type_kind (CApi.allocated_type (slot)) != CApi.TypeKind.POINTER || CApi.operand_count (slot) != 1 || (void*) CApi.is_constant_int (CApi.operand (slot, 0)) == null || CApi.const_int_zext (CApi.operand (slot, 0)) != 1 || checked_slots.contains ((void*) slot)) {
			throw new LlvmError.VERIFICATION ("checked scoped result requires its unique local success slot");
		}
		for (var use = CApi.first_use (slot); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) user == (void*) call) {
				for (uint p = 1; p < CApi.argument_count (call); p++) {
					if ((void*) CApi.operand (call, p) == (void*) slot) {
						throw new LlvmError.VERIFICATION ("checked scoped success slot aliases another argument");
					}
				}
				continue;
			}
			if ((void*) CApi.is_instruction (user) == null || CApi.opcode (user) != CApi.Opcode.LOAD || (void*) CApi.operand (user, 0) != (void*) slot || CApi.type_kind (CApi.type_of (user)) != CApi.TypeKind.POINTER || CApi.get_volatile (user) != 0 || CApi.get_ordering (user) != 0) {
				throw new LlvmError.VERIFICATION ("checked scoped caller success slot escaped its exact channel");
			}
		}
		var channel = new LlvmScopedCheckedCall (call, slot, incoming.allocation, owner_count++, checked_channels.length);
		checked_channels.add (channel);
		checked_calls.insert ((void*) call, channel);
		checked_slots.insert ((void*) slot, channel);
		return true;
	}

	private bool checked_record_alias(CApi.ValueRef call, LlvmScopedOwnedInputs contract) throws LlvmError {
		var channel = checked_calls.lookup ((void*) call);
		bool changed = false;
		if (channel == null) {
			var slot = CApi.operand (call, 0);
			if ((void*) CApi.is_instruction (slot) == null || CApi.opcode (slot) != CApi.Opcode.ALLOCA || (void*) CApi.allocated_type (slot) != (void*) contract.success_type () || CApi.operand_count (slot) != 1 || !number (CApi.operand (slot, 0), 1) || checked_slots.contains ((void*) slot)) {
				throw new LlvmError.VERIFICATION ("checked scoped record requires its unique exact local success tuple");
			}
			for (var use = CApi.first_use (slot); (void*) use != null; use = CApi.next_use (use)) {
				var user = CApi.user (use);
				if ((void*) user == (void*) call) {
					for (uint p = 1; p < CApi.argument_count (call); p++) {
						if ((void*) CApi.operand (call, p) == (void*) slot) {
							throw new LlvmError.VERIFICATION ("checked scoped record success tuple aliases another argument");
						}
					}
					continue;
				}
				if ((void*) CApi.is_instruction (user) == null || CApi.opcode (user) != CApi.Opcode.LOAD || (void*) CApi.operand (user, 0) != (void*) slot || (void*) CApi.type_of (user) != (void*) contract.success_type () || CApi.get_volatile (user) != 0 || CApi.get_ordering (user) != 0) {
					throw new LlvmError.VERIFICATION ("checked scoped record caller tuple escaped its exact channel");
				}
				for (var read = CApi.first_use (user); (void*) read != null; read = CApi.next_use (read)) {
					if (contract.extracted_field (CApi.user (read)) < 0) {
						throw new LlvmError.VERIFICATION ("checked scoped record load escaped exact member extraction");
					}
				}
			}
			channel = new LlvmScopedCheckedCall (call, slot, -1, -1, checked_channels.length);
			channel.aggregate = true;
			checked_channels.add (channel);
			checked_calls.insert ((void*) call, channel);
			checked_slots.insert ((void*) slot, channel);
			changed = true;
		}
		for (int f = 0; f < contract.aggregate_fields; f++) {
			int slot = contract.result_slot (f);
			if (slot < 0) {
				continue;
			}
			var incoming = pointer (CApi.operand (call, contract.physical_position (slot)));
			if (incoming == null) {
				continue;
			}
			if (!incoming.root) {
				throw new LlvmError.VERIFICATION ("checked scoped record requires a complete original input allocation");
			}
			var old = channel.fields.lookup (f);
			if (old == null) {
				channel.fields.insert (f, new LlvmScopedPointer (incoming.allocation, true, owner_count++));
				changed = true;
			} else if (old.allocation != incoming.allocation) {
				throw new LlvmError.VERIFICATION ("checked scoped record changed its field allocation identity");
			}
		}
		return changed;
	}

	private bool error_alias(CApi.ValueRef call, LlvmScopedOwnedInputs contract) throws LlvmError {
		if (contract.error_count == 0 || error_calls.contains ((void*) call)) {
			return false;
		}
		int tracked = 0;
		for (int f = 0; f < contract.error_count; f++) {
			uint position = contract.physical_position (contract.error_slot (f));
			if (position >= CApi.argument_count (call)) {
				throw new LlvmError.VERIFICATION ("scoped exception call lost its payload input group");
			}
			if (null_record_input (CApi.operand (call, position), new HashTable<void*, bool> (direct_hash, direct_equal))) {
				continue;
			}
			var incoming = pointer (CApi.operand (call, position));
			if (incoming == null) {
				return false;
			}
			tracked++;
			if (!incoming.root || !contract.accepts (call, position, (CApi.ValueRef) tags[incoming.allocation], (CApi.ValueRef) counts[incoming.allocation], (CApi.ValueRef) sizes[incoming.allocation], (CApi.ValueRef) alignments[incoming.allocation], true)) {
				throw new LlvmError.VERIFICATION ("scoped exception call lost its exact payload allocation");
			}
		}
		if (tracked == 0) {
			return false;
		}
		var channel = new LlvmScopedErrorCall (call, contract, storage.bind_error_root (call, contract), error_channels.length);
		for (int f = 0; f < contract.error_count; f++) {
			uint position = contract.physical_position (contract.error_slot (f));
			if (null_record_input (CApi.operand (call, position), new HashTable<void*, bool> (direct_hash, direct_equal))) {
				continue;
			}
			channel.slots.add (storage.bind_error_field (call, contract.error_member (f), position, pointer (CApi.operand (call, position)), ref owner_count));
		}
		error_channels.add (channel);
		error_calls.insert ((void*) call, channel);
		return true;
	}

	// A null task result means either original absence or callee retirement.
	// It never proves that the original backing allocation is still live.
	private uint frame_null_mask(LlvmScopedPointer pointer) {
		foreach (var task in held_tasks) {
			foreach (var result in task.results.get_values ()) {
				if (result.owner == pointer.owner && result.allocation == pointer.allocation) {
					return 5;
				}
			}
		}
		return 1;
	}

	private bool bind_host_error(CApi.ValueRef call) throws LlvmError {
		if (host_error_calls.contains ((void*) call) || callee (call) != "astra_async_run" || CApi.argument_count (call) != 3) {
			return false;
		}
		var task = held_aliases.lookup ((void*) CApi.operand (call, 1));
		if (task == null || !task.capture.inputs.deferred_error) {
			return false;
		}
		bool retires;
		if (!LlvmScopedTaskFrame.operation (call, 1, out retires) || !retires) {
			throw new LlvmError.VERIFICATION ("scoped host error lacks its exact observing runtime call");
		}
		var slot = CApi.operand (call, 2);
		if ((void*) CApi.is_instruction (slot) == null || CApi.opcode (slot) != CApi.Opcode.ALLOCA || (void*) CApi.allocated_type (slot) != (void*) CApi.type_of (slot) || CApi.operand_count (slot) != 1 || !number (CApi.operand (slot, 0), 1) || !LlvmBufferExchangeOrder.precedes (slot, call)) {
			throw new LlvmError.VERIFICATION ("scoped host error requires its exact private output slot");
		}
		CApi.ValueRef read = (CApi.ValueRef) null;
		for (var use = CApi.first_use (slot); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) user == (void*) call) {
				if ((void*) CApi.operand (call, 0) == (void*) slot || (void*) CApi.operand (call, 1) == (void*) slot) {
					throw new LlvmError.VERIFICATION ("scoped host error output aliases another runtime input");
				}
				continue;
			}
			if ((void*) CApi.is_instruction (user) == null || CApi.opcode (user) != CApi.Opcode.LOAD || (void*) CApi.operand (user, 0) != (void*) slot || (void*) CApi.type_of (user) != (void*) CApi.allocated_type (slot) || CApi.get_volatile (user) != 0 || CApi.get_ordering (user) != 0 || (void*) read != null || !LlvmBufferExchangeOrder.precedes (call, user)) {
				throw new LlvmError.VERIFICATION ("scoped host error output escaped its unique actual read");
			}
			read = user;
		}
		if ((void*) read == null) {
			throw new LlvmError.VERIFICATION ("scoped host error lost its actual output read");
		}
		var shape = task.capture.inputs;
		var empty = new GenericArray<LlvmScopedOwnedInputs> ();
		foreach (var contract in consuming.get_values ()) {
			if (contract.empty_backing != null && contract.empty_backing.empty_base_shape.same (shape.error_shape)) {
				contract.verify ();
				empty.add (contract);
			}
		}
		for (int f = 0; f < shape.error_count; f++) {
			int position = (int) shape.physical_position (shape.error_slot (f));
			if (!task.owners.contains (position) && !null_pointer (CApi.operand (task.call, (uint) position))) {
				return false;
			}
		}
		var observer = new LlvmScopedHostError (call, read, task, (int) host_errors.length, storage.bind_observed_error (read, shape, empty));
		for (int f = 0; f < shape.error_count; f++) {
			int capture = shape.error_slot (f);
			int position = (int) shape.physical_position (capture);
			var held = task.owners.lookup (position);
			if (held == null) {
				if (!null_pointer (CApi.operand (task.call, (uint) position))) {
					throw new LlvmError.VERIFICATION ("scoped host error lost its original capture mapping");
				}
				observer.fields.add (storage.bind_empty_error_field (read, shape.error_member (f)));
			} else {
				observer.fields.add (storage.bind_error_field (read, shape.error_member (f), (uint) position, held, ref owner_count));
			}
		}
		host_errors.add (observer);
		host_error_calls.insert ((void*) call, observer);
		host_error_reads.insert ((void*) read, observer);
		return true;
	}

	private bool bind_wait_error(CApi.ValueRef call) throws LlvmError {
		if (coroutine == null || host_error_calls.contains ((void*) call) || callee (call) != "astra_async_exception" || CApi.argument_count (call) != 1) {
			return false;
		}
		var waited = CApi.operand (call, 0);
		var task = held_aliases.lookup ((void*) waited);
		if (task == null || !task.capture.inputs.deferred_error) {
			return false;
		}
		observed_abi (call, false);
		if (!LlvmScopedHeapCarrier.named_call (waited, "astra_async_waited") || CApi.argument_count (waited) != 1 || (void*) CApi.operand (waited, 0) != (void*) coroutine.task) {
			throw new LlvmError.VERIFICATION ("scoped wait error requires its actual waited child");
		}
		observed_abi (waited, false);
		var shape = task.capture.inputs;
		for (int f = 0; f < shape.error_count; f++) {
			int position = (int) shape.physical_position (shape.error_slot (f));
			if (!task.owners.contains (position) && !null_pointer (CApi.operand (task.call, (uint) position))) {
				return false;
			}
		}
		var empty = new GenericArray<LlvmScopedOwnedInputs> ();
		foreach (var contract in consuming.get_values ()) {
			if (contract.empty_backing != null && contract.empty_backing.empty_base_shape.same (shape.error_shape)) {
				contract.verify ();
				empty.add (contract);
			}
		}
		var observer = new LlvmScopedHostError (call, call, task, (int) host_errors.length, storage.bind_observed_error (call, shape, empty));
		observer.asynchronous = true;
		for (int f = 0; f < shape.error_count; f++) {
			int position = (int) shape.physical_position (shape.error_slot (f));
			var held = task.owners.lookup (position);
			observer.fields.add (held == null ? storage.bind_empty_error_field (call, shape.error_member (f)) : storage.bind_error_field (call, shape.error_member (f), (uint) position, held, ref owner_count));
		}
		host_errors.add (observer);
		host_error_calls.insert ((void*) call, observer);
		return true;
	}

	private bool wait_error_bound(LlvmScopedHeldTask task) {
		foreach (var observer in host_errors) {
			if (observer.asynchronous && observer.task == task) {
				return true;
			}
		}
		return false;
	}

	private bool wait_error_owner(LlvmScopedHeldTask task, LlvmScopedPointer held, uint[] state) {
		foreach (var observer in host_errors) {
			if (!observer.asynchronous || observer.task != task || state[observed_offset + task.ordinal] != 2) {
				continue;
			}
			uint mode = state[host_error_offset + observer.ordinal];
			if (mode == 4) {
				foreach (var field in observer.fields) {
					if (field.allocation == held.allocation && field.owner >= 0 && state[owner_offset + field.owner] == 2) {
						return true;
					}
				}
			} else if (mode >= 5 && mode < 4 + observer.alternatives.length && no_live_allocation (state[held.allocation])) {
				return true;
			}
		}
		return false;
	}

	private int host_error_phase(LlvmScopedHostError observer, uint[] state) {
		uint mode = state[host_error_offset + observer.ordinal];
		return mode == 1 ? -1 : mode == 2 ? 5 : mode == 3 ? 7 : mode >= 4 && mode < 4 + observer.alternatives.length ? 6 : mode >= 4 + observer.alternatives.length ? -(int) (mode - (3 + observer.alternatives.length) + 1) : 0;
	}

	private int host_error_condition(CApi.ValueRef condition, uint[] state) {
		if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP) {
			return -1;
		}
		var observer = host_error_calls.lookup ((void*) CApi.operand (condition, 0));
		if (observer == null || observer.asynchronous || (void*) CApi.is_constant_int (CApi.operand (condition, 1)) == null || state[host_error_offset + observer.ordinal] == 0) {
			return -1;
		}
		int phase = host_error_phase (observer, state);
		int target = (int) CApi.const_int_zext (CApi.operand (condition, 1));
		switch (CApi.predicate (condition)) {
		case CApi.IntPredicate.EQ: return phase == target ? 1 : 0;
		case CApi.IntPredicate.NE: return phase != target ? 1 : 0;
		case CApi.IntPredicate.SLT: return phase < target ? 1 : 0;
			default: return -1;
		}
	}

	private void host_error_fork(CApi.ValueRef instruction, uint[] state, GenericArray<LlvmScopedWork> pending) {
		var observer = host_error_calls.lookup ((void*) instruction);
		if (observer == null) {
			return;
		}
		uint first = observer.asynchronous ? 4U : 1U;
		uint last = observer.asynchronous ? 3 + observer.alternatives.length : 7 + observer.alternatives.length;
		for (uint mode = first + 1; mode <= last; mode++) {
			uint[] alternative = state.copy ();
			alternative[host_error_offset + observer.ordinal] = mode;
			pending.add (new LlvmScopedWork (alternative, instruction, true));
		}
		state[host_error_offset + observer.ordinal] = first;
	}

	private void host_error_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		var observer = host_error_reads.lookup ((void*) instruction);
		if (observer != null) {
			uint mode = state[host_error_offset + observer.ordinal];
			if (strict && mode == 0) {
				throw new LlvmError.VERIFICATION ("scoped host error read precedes its actual observation");
			}
			storage.select_observed_error (observer.read, mode >= 4 && mode < 4 + observer.alternatives.length ? observer.alternatives[(int) mode - 4] : null, state, heap_choice_offset);
			return;
		}
		observer = host_error_calls.lookup ((void*) instruction);
		if (observer == null) {
			return;
		}
		var task = observer.task;
		if (observer.asynchronous && strict && (state[wait_offset] != (uint) task.ordinal + 1 || state[held_offset + task.ordinal] != 8 || state[phase_offset + task.ordinal] != 6 || state[observed_offset + task.ordinal] != 1)) {
			throw new LlvmError.VERIFICATION ("scoped wait error requires its original admitted child and actual exception phase (wait=%u, child=%d, held=%u, phase=%u, observed=%u)", state[wait_offset], task.ordinal, state[held_offset + task.ordinal], state[phase_offset + task.ordinal], state[observed_offset + task.ordinal]);
		}
		if (!observer.asynchronous && strict && state[held_offset + task.ordinal] != 2) {
			throw new LlvmError.VERIFICATION ("scoped host error duplicates or changes its original task observation");
		}
		uint mode = state[host_error_offset + observer.ordinal];
		bool payload = mode == 4;
		if (strict) {
			foreach (var heap in observer.alternatives) {
				uint h = 0;
				assert (storage.heaps.find (heap, out h));
				if ((state[heap_offset + (int) h] & 2) != 0) {
					throw new LlvmError.VERIFICATION ("scoped host error reacquired before its previous carrier retired");
				}
			}
		}
		if (observer.asynchronous) {
			state[observed_offset + task.ordinal] = 2;
		} else {
			state[held_offset + task.ordinal] = 4;
		}
		foreach (var held in task.owners.get_values ()) {
			bool returned = false;
			foreach (var field in observer.fields) {
				returned = returned || payload && field.allocation == held.allocation;
			}
			if (strict && state[owner_offset + held.owner] != 1 && (state[held.allocation] != 2 || state[owner_offset + held.owner] != 2)) {
				throw new LlvmError.VERIFICATION ("scoped host error lost its exact held original input");
			}
			if (observer.asynchronous && payload && !returned) {
				continue;
			}
			if (state[owner_offset + held.owner] != 1 && !returned) {
				state[held.allocation] = 4;
			}
			state[owner_offset + held.owner] = 4;
		}
		foreach (var field in observer.fields) {
			uint position = 0;
			assert (storage.slots.find (field, out position));
			bool live = payload && field.allocation >= 0 && state[field.allocation] == 2;
			state[storage_offset + (int) position] = live ? 2U : 8U;
			if (field.owner >= 0) {
				state[owner_offset + field.owner] = live ? 2U : 1U;
			}
		}
		for (int h = 0; h < observer.alternatives.length; h++) {
			uint index = 0;
			assert (storage.heaps.find (observer.alternatives[h], out index));
			bool live = mode == h + 4;
			storage.invalidate_heap_origin (observer.alternatives[h], state, heap_choice_offset);
			state[heap_offset + (int) index] = live ? 2U : 1U;
			state[empty_heap_offset + (int) index] = live ? 2U : 1U;
		}
		if (observer.asynchronous) {
			storage.select_observed_error (observer.read, observer.alternatives[(int) mode - 4], state, heap_choice_offset);
		}
	}

	private void aliases() throws LlvmError {
		if (coroutine != null) {
			storage.admit_coroutine (coroutine);
		}
		owner_count = allocations.length;
		bool changed = false;
		if (coroutine != null && owned_inputs.deferred_error) {
			CApi.ValueRef callback = (CApi.ValueRef) null;
			for (var block = CApi.first_block (coroutine.destroy); (void*) block != null; block = CApi.next_block (block)) {
				for (var call = CApi.first_instruction (block); (void*) call != null; call = CApi.next_instruction (call)) {
					if (CApi.opcode (call) == CApi.Opcode.CALL && callee (call) == "astra_async_discarded_exception") {
						if ((void*) callback != null) {
							throw new LlvmError.VERIFICATION ("scoped deferred error requires one original retirement callback");
						}
						callback = call;
					}
				}
			}
			if ((void*) callback == null) {
				throw new LlvmError.VERIFICATION ("scoped deferred error lost its actual retirement callback");
			}
			var pointer_type = CApi.type_of (coroutine.task);
			var word = CApi.int32_type_in_context (CApi.type_context (pointer_type));
			CApi.TypeRef[] parameters = {
				pointer_type, word
			};
			var type = CApi.function_type (pointer_type, parameters, 2, 0);
			if (CApi.argument_count (callback) != 2 || (void*) CApi.operand (callback, 0) != (void*) CApi.get_param (coroutine.destroy, 0) || (void*) CApi.operand (callback, 1) != (void*) CApi.get_param (coroutine.destroy, 1) || (void*) CApi.called_function_type (callback) != (void*) type || (void*) CApi.global_value_type (CApi.called_value (callback)) != (void*) type || CApi.instruction_call_conv (callback) != CApi.CallConv.C || CApi.function_call_conv (CApi.called_value (callback)) != CApi.CallConv.C || CApi.count_basic_blocks (CApi.called_value (callback)) != 0) {
				throw new LlvmError.VERIFICATION ("scoped deferred error lost its exact retirement callback ABI");
			}
			deferred_error = new LlvmScopedErrorCall (callback, owned_inputs, storage.bind_error_root (callback, owned_inputs), 0);
			for (int f = 0; f < owned_inputs.error_count; f++) {
				int slot = owned_inputs.error_slot (f);
				deferred_error.slots.add (storage.bind_error_field (callback, owned_inputs.error_member (f), owned_inputs.physical_position (slot), pointer (owned_inputs.parameter (slot)), ref owner_count));
			}
		}
		if (result_shape != null) {
			for (uint f = 0; f < result_shape.field_count; f++) {
				int slot = result_shape.capture (f);
				result_owners.add (slot < 0 ? null : new LlvmScopedPointer (slot, true, owner_count++));
			}
			foreach (void* address in blocks) {
				for (var instruction = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (result_store (instruction)) {
						for (uint f = 0; f < result_shape.field_count; f++) {
							result_shape.publication_value (instruction, f);
						}
						result_stores.add ((void*) instruction);
					}
				}
			}
		}

		if (coroutine != null) {
			for (int p = 0; p < owned_inputs.count; p++) {
				int position = (int) owned_inputs.physical_position (p);
				int owner = coroutine.captured_owner (position);
				if (owner < 0) {
					throw new LlvmError.VERIFICATION ("scoped coroutine capture lacks its exact cold owner field");
				}
				var alias = pointer (owned_inputs.parameter (p));
				frame_values.insert (position + 1, alias);
				frame_values.insert (owner, alias);
				frame_flags.insert (owner + 1, alias);
			}
		}
		do {
			changed = false;
			foreach (void* address in blocks) {
				var block = (CApi.BasicBlockRef) address;
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					var opcode = CApi.opcode (instruction);
					if (result_shape != null && opcode == CApi.Opcode.EXTRACT_VALUE && CApi.index_count (instruction) == 1) {
						var carrier = CApi.operand (instruction, 0);
						uint field = CApi.indices (instruction)[0];
						if ((void*) CApi.is_instruction (carrier) != null && CApi.opcode (carrier) == CApi.Opcode.LOAD && frame_field (CApi.operand (carrier, 0)) == 0 && field < result_shape.field_count && result_shape.empty_field (field)) {
							if ((void*) CApi.type_of (carrier) != (void*) result_shape.result_type ()) {
								throw new LlvmError.VERIFICATION ("empty scoped result changed its complete typed carrier");
							}
							empty_body_values.insert ((void*) instruction, field);
						}
					}
					if (result_shape != null && result_shape.field_count == 1 && result_shape.empty_field (0) && opcode == CApi.Opcode.LOAD && frame_field (CApi.operand (instruction, 0)) == 0) {
						empty_body_values.insert ((void*) instruction, 0);
					}
					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null && contract.literal_null_call (instruction)) {
							null_results.insert ((void*) instruction, true);
						}
					}
					if (result_shape != null && opcode == CApi.Opcode.LOAD && frame_field (CApi.operand (instruction, 0)) == 0 && result_shape.field_count == 1 && result_owners[0] != null && pointer (instruction) == null) {
						if ((void*) CApi.type_of (instruction) != (void*) result_shape.result_type ()) {
							throw new LlvmError.VERIFICATION ("scoped result read changed its exact carrier");
						}
						pointers.insert ((void*) instruction, result_owners[0]);
						null_lifetimes.insert ((void*) instruction, 1);
						changed = true;
					}
					if (result_shape != null && opcode == CApi.Opcode.EXTRACT_VALUE && CApi.index_count (instruction) == 1) {
						var carrier = CApi.operand (instruction, 0);
						uint field = CApi.indices (instruction)[0];
						if ((void*) CApi.is_instruction (carrier) != null && CApi.opcode (carrier) == CApi.Opcode.LOAD && frame_field (CApi.operand (carrier, 0)) == 0) {
							if ((void*) CApi.type_of (carrier) != (void*) result_shape.result_type () || field >= result_owners.length) {
								throw new LlvmError.VERIFICATION ("scoped result extraction lost its original physical carrier");
							}
							if (result_owners[field] != null && pointer (instruction) == null) {
								pointers.insert ((void*) instruction, result_owners[field]);
								null_lifetimes.insert ((void*) instruction, 1);
								changed = true;
							}
						}
					}
					if (captured_tasks != null && captured_tasks.contains ((void*) instruction)) {
						var capture = captured_tasks.lookup ((void*) instruction);
						capture.verify (instruction);
						var task = held_aliases.lookup ((void*) instruction);
						if (task == null) {
							task = new LlvmScopedHeldTask (instruction, capture, (int) held_tasks.length);
							held_tasks.add (task);
							held_aliases.insert ((void*) instruction, task);
							changed = true;
						}
						var shape = capture.inputs;
						for (int p = 0; p < shape.count; p++) {
							int position = (int) shape.physical_position (p);
							var incoming = pointer (CApi.operand (instruction, (uint) position));
							if (incoming == null) {
								continue;
							}
							var old = task.owners.lookup (position);
							if (old == null) {
								task.owners.insert (position, new LlvmScopedPointer (incoming.allocation, true, owner_count++));
								changed = true;
							} else if (old.allocation != incoming.allocation) {
								throw new LlvmError.VERIFICATION ("scoped captured task changed its original input allocation");
							}
						}
					}
					if (coroutine != null && opcode == CApi.Opcode.CALL && callee (instruction) == "astra_async_waited" && CApi.argument_count (instruction) == 1 && (void*) CApi.operand (instruction, 0) == (void*) coroutine.task) {
						observed_abi (instruction, false);
						for (uint e = 0; e < coroutine.continuation_count; e++) {
							var edge = coroutine.continuation (e);
							if ((void*) CApi.instruction_parent (instruction) != (void*) edge.next_state ()) {
								continue;
							}
							var task = held_aliases.lookup ((void*) CApi.operand (edge.admission (), 1));
							if (task != null && !held_aliases.contains ((void*) instruction)) {
								held_aliases.insert ((void*) instruction, task);
								changed = true;
							}
						}
					}
					if (opcode == CApi.Opcode.CALL && callee (instruction) == "astra_async_data" && CApi.argument_count (instruction) == 1) {
						var task = held_aliases.lookup ((void*) CApi.operand (instruction, 0));
						if (task != null && (task.capture.result != null || (void*) task.capture.inputs.plain_task_result != null) && !result_data.contains ((void*) instruction)) {
							observed_abi (instruction, false);
							result_data.insert ((void*) instruction, task);
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.LOAD) {
						var task = result_data.lookup ((void*) CApi.operand (instruction, 0));
						if (task != null && (void*) task.capture.inputs.plain_task_result != null && task.capture.result == null) {
							if ((void*) CApi.type_of (instruction) != (void*) task.capture.inputs.plain_task_result || CApi.get_volatile (instruction) != 0 || CApi.get_ordering (instruction) != 0) {
								throw new LlvmError.VERIFICATION ("scoped child scalar read lost its exact pointer-free result type");
							}
							if (!plain_result_reads.contains ((void*) instruction)) {
								plain_result_reads.insert ((void*) instruction, task);
								changed = true;
							}
						}
						if (task != null && task.capture.result != null) {
							var shape = task.capture.result;
							if ((void*) CApi.type_of (instruction) != (void*) shape.result_type () || CApi.get_volatile (instruction) != 0 || CApi.get_ordering (instruction) != 0) {
								throw new LlvmError.VERIFICATION ("scoped child success read lost its exact complete typed carrier");
							}
							if (!result_reads.contains ((void*) instruction)) {
								result_reads.insert ((void*) instruction, task);
								changed = true;
							}
							for (uint f = 0; f < shape.field_count; f++) {
								int capture = shape.capture (f);
								if (capture < 0) {
									continue;
								}
								int position = (int) task.capture.inputs.physical_position (capture);
								var source = task.owners.lookup (position);
								if (source == null) {
									continue;
								}
								if (!task.results.contains ((int) f)) {
									task.results.insert ((int) f, new LlvmScopedPointer (source.allocation, true, owner_count++));
									changed = true;
								}
							}
							if (shape.field_count == 1 && shape.empty_field (0)) {
								empty_result_values.insert ((void*) instruction, task);
							}
							if (shape.field_count == 1 && task.results.contains (0) && pointer (instruction) == null) {
								pointers.insert ((void*) instruction, task.results.lookup (0));
								null_lifetimes.insert ((void*) instruction, 5);
								changed = true;
							}
						}
					}
					if (opcode == CApi.Opcode.EXTRACT_VALUE && CApi.index_count (instruction) == 1) {
						var task = result_reads.lookup ((void*) CApi.operand (instruction, 0));
						if (task != null) {
							uint field = CApi.indices (instruction)[0];
							if (field >= task.capture.result.field_count) {
								throw new LlvmError.VERIFICATION ("scoped child success extraction lost its physical field");
							}
							if (task.capture.result.empty_field (field)) {
								empty_result_values.insert ((void*) instruction, task);
							}
							var returned = task.results.lookup ((int) field);
							if (returned != null && pointer (instruction) == null) {
								pointers.insert ((void*) instruction, returned);
								null_lifetimes.insert ((void*) instruction, 5);
								changed = true;
							}
						}
					}
					if (coroutine != null && opcode == CApi.Opcode.STORE) {
						int field = frame_field (CApi.operand (instruction, 1));
						var task = held_aliases.lookup ((void*) CApi.operand (instruction, 0));
						if (field >= 0 && task != null) {
							var prior = held_fields.lookup (field);
							if (prior != null && prior != task) {
								throw new LlvmError.VERIFICATION ("coroutine task field changes its exact captured task");
							}
							if (prior == null) {
								held_fields.insert (field, task);
								changed = true;
							}
						}
					}
					if (coroutine != null && opcode == CApi.Opcode.LOAD) {
						int field = frame_field (CApi.operand (instruction, 0));
						var task = held_fields.lookup (field);
						if (field >= 0 && task != null && !held_aliases.contains ((void*) instruction)) {
							held_aliases.insert ((void*) instruction, task);
							changed = true;
						}
					}
					if (coroutine != null && opcode == CApi.Opcode.STORE && !result_store (instruction)) {
						int field = frame_field (CApi.operand (instruction, 1));
						var incoming = pointer (CApi.operand (instruction, 0));
						if (field >= 0 && incoming != null) {
							var old = frame_values.lookup (field);
							if (old != null && (old.allocation != incoming.allocation || old.owner != incoming.owner)) {
								throw new LlvmError.VERIFICATION ("coroutine frame field changes its exact allocation/owner identity");
							}
							if (old == null) {
								frame_values.insert (field, incoming);
								changed = true;
							}
						}
					}
					if (coroutine != null && opcode == CApi.Opcode.LOAD) {
						int field = frame_field (CApi.operand (instruction, 0));
						var incoming = frame_values.lookup (field);
						if (field >= 0 && incoming != null && pointer (instruction) == null) {
							pointers.insert ((void*) instruction, incoming);
							null_lifetimes.insert ((void*) instruction, frame_null_mask (incoming));
							if (!phi_positions.contains ((void*) instruction)) {
								phi_positions.insert ((void*) instruction, (int) pointer_phis.length);
								pointer_phis.add ((void*) instruction);
							}
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null && contract.aggregate_fields != 0 && !contract.checked_success) {
							var channel = record_calls.lookup ((void*) instruction);
							if (channel == null) {
								channel = new LlvmScopedRecordCall ();
								record_calls.insert ((void*) instruction, channel);
							}
							for (int f = 0; f < contract.aggregate_fields; f++) {
								int slot = contract.result_slot (f);
								if (slot < 0) {
									continue;
								}
								var incoming = pointer (CApi.operand (instruction, contract.physical_position (slot)));
								if (incoming == null) {
									continue;
								}
								if (!incoming.root) {
									throw new LlvmError.VERIFICATION ("scoped record result requires its complete input allocation");
								}
								var old = channel.fields.lookup (f);
								if (old == null) {
									channel.fields.insert (f, new LlvmScopedPointer (incoming.allocation, true, owner_count++));
									changed = true;
								} else if (old.allocation != incoming.allocation) {
									throw new LlvmError.VERIFICATION ("scoped record result changed its allocation identity");
								}
							}
						}
					}
					if (opcode == CApi.Opcode.EXTRACT_VALUE && consuming != null) {
						var call = CApi.operand (instruction, 0);
						var channel = record_calls.lookup ((void*) call);
						if (channel != null) {
							var contract = consuming.lookup ((void*) CApi.called_value (call));
							int field = contract.extracted_field (instruction);
							var incoming = field < 0 ? null : channel.fields.lookup (field);
							if (incoming != null && pointer (instruction) == null) {
								pointers.insert ((void*) instruction, incoming);
								changed = true;
							}
						}
						if ((void*) CApi.is_instruction (call) != null && CApi.opcode (call) == CApi.Opcode.LOAD) {
							var checked = checked_slots.lookup ((void*) CApi.operand (call, 0));
							if (checked != null && checked.aggregate) {
								var contract = consuming.lookup ((void*) CApi.called_value (checked.call));
								int field = contract.extracted_field (instruction);
								var incoming = field < 0 ? null : checked.fields.lookup (field);
								if (incoming != null && pointer (instruction) == null) {
									pointers.insert ((void*) instruction, incoming);
									null_lifetimes.insert ((void*) instruction, 5);
									changed = true;
								}
							}
						}
					}
					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null && contract.empty_backing != null && storage.bind_empty_error (instruction, contract)) {
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.CALL && consuming != null && (bind_host_error (instruction) || bind_wait_error (instruction))) {
						changed = true;
					}
					if ((opcode == CApi.Opcode.LOAD || opcode == CApi.Opcode.STORE) && storage.bind_frame_heap_alias (instruction)) {
						changed = true;
					}
					if ((opcode == CApi.Opcode.PHI || opcode == CApi.Opcode.SELECT || opcode == CApi.Opcode.LOAD) && storage.bind_heap_alias (instruction)) {
						changed = true;
					}
					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var checked = consuming.lookup ((void*) CApi.called_value (instruction));
						if (checked != null && checked.checked_success && checked_alias (instruction, checked)) {
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null && error_alias (instruction, contract)) {
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null && contract.fields != null && contract.fields.publishes && !(owned_inputs != null && owned_inputs.empty_base_call (instruction, contract))) {
							for (int f = 0; f < contract.fields.count; f++) {
								if (contract.fields.empty_field (f)) {
									contract.field_call (instruction);
									if (storage.bind_call (instruction, contract.fields, f, null, ref owner_count)) {
										changed = true;
									}
									continue;
								}
								if ((uint) contract.fields.input (f) + 1 >= CApi.argument_count (instruction)) {
									throw new LlvmError.VERIFICATION ("scoped field call lost its complete input group");
								}
								var value = CApi.operand (instruction, (uint) contract.fields.input (f) + 1);
								var incoming = pointer (value);
								if (incoming != null || null_pointer (value)) {
									contract.field_call (instruction);
									if (storage.bind_call (instruction, contract.fields, f, incoming, ref owner_count)) {
										changed = true;
									}
								}
							}
						}
					}
					if (opcode == CApi.Opcode.STORE) {
						var incoming = pointer (CApi.operand (instruction, 0));
						if (incoming != null && storage.bind (instruction, incoming, ref owner_count)) {
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.LOAD && CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.POINTER) {
						var channel = checked_slots.lookup ((void*) CApi.operand (instruction, 0));
						if (channel != null && pointer (instruction) == null) {
							pointers.insert ((void*) instruction, new LlvmScopedPointer (channel.allocation, true, channel.owner));
							null_lifetimes.insert ((void*) instruction, 5);
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.LOAD && CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.POINTER) {
						var slot = storage.lookup (CApi.operand (instruction, 0));
						if (slot != null && slot.allocation >= 0 && pointer (instruction) == null) {
							pointers.insert ((void*) instruction, new LlvmScopedPointer (slot.allocation, true, slot.owner));
							changed = true;
						}
					}
					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null && contract.owner_graph != null && !contract.graph_forwarding) {
							var incoming = pointer (CApi.operand (instruction, contract.graph_parameter));
							if (incoming != null) {
								if (!incoming.root) {
									throw new LlvmError.VERIFICATION ("scoped graph consumption requires its complete original allocation");
								}
								if (!fresh_graphs.contains (incoming.allocation)) {
									storage.graph_input (instruction, CApi.operand (instruction, contract.graph_parameter), contract.owner_graph, false);
								}
							}
						}
					}

					if (opcode == CApi.Opcode.CALL && consuming != null) {
						var contract = consuming.lookup ((void*) CApi.called_value (instruction));
						if (contract != null && !contract.checked_success && contract.returned_parameter >= 0) {
							if (contract.returned_parameter >= CApi.argument_count (instruction)) {
								throw new LlvmError.VERIFICATION ("forwarded owner lost its exact call input");
							}
							var incoming = pointer (CApi.operand (instruction, contract.returned_parameter));
							if (incoming == null) {
								continue;
							}
							if (!incoming.root) {
								throw new LlvmError.VERIFICATION ("forwarded owner requires its complete original allocation");
							}
							if (contract.owner_graph != null && !fresh_graphs.contains (incoming.allocation)) {
								storage.graph_input (instruction, CApi.operand (instruction, contract.returned_parameter), contract.owner_graph, true);
							}
							var old = pointer (instruction);
							if (old == null) {
								pointers.insert ((void*) instruction, new LlvmScopedPointer (incoming.allocation, true, owner_count++));
								changed = true;
							} else if (old.allocation != incoming.allocation) {
								throw new LlvmError.VERIFICATION ("forwarded owner changed its allocation identity");
							}
							continue;
						}
					}
					if (opcode != CApi.Opcode.PHI && opcode != CApi.Opcode.SELECT && opcode != CApi.Opcode.GEP) {
						continue;
					}
					LlvmScopedPointer? incoming = null;
					bool root = opcode != CApi.Opcode.GEP;
					uint count = opcode == CApi.Opcode.PHI ? CApi.incoming_count (instruction) : opcode == CApi.Opcode.SELECT ? 2 : 1;
					for (uint i = 0; i < count; i++) {
						var value = opcode == CApi.Opcode.PHI ? CApi.incoming_value (instruction, i) : CApi.operand (instruction, opcode == CApi.Opcode.SELECT ? i + 1 : i);
						var alias = pointer (value);
						if (alias == null) {
							continue;
						}
						if (incoming != null && (incoming.allocation != alias.allocation || incoming.owner != alias.owner)) {
							throw new LlvmError.VERIFICATION ("scoped pointer join requires exact ownership alternatives");
						}
						incoming = alias;
						root = root && alias.root;
					}
					if (incoming == null) {
						continue;
					}
					var old = pointer (instruction);
					if (old == null || old.root != root || old.owner != incoming.owner) {
						pointers.insert ((void*) instruction, new LlvmScopedPointer (incoming.allocation, root, incoming.owner));
						changed = true;
					}
				}
			}
		} while (changed);
		// Constructor carriers may be discovered after their graph call in
		// block order. Require the complete physical carrier at the fixed point.
		if (consuming != null) {
			foreach (void* address in blocks) {
				for (var instruction = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					var contract = consuming.lookup ((void*) CApi.called_value (instruction));
					if (contract == null || contract.owner_graph == null) {
						continue;
					}
					var value = CApi.operand (instruction, contract.graph_parameter);
					if (pointer (value) != null && !fresh_graphs.contains (pointer (value).allocation)) {
						storage.graph_input (instruction, value, contract.owner_graph, contract.graph_forwarding, true);
					}
				}
			}
		}

		// Deferred f1 shape and producer publication are independent of
		// observer acquisition. Keep the latter closed until its actual
		// output-slot/phase carrier can retain the original allocation debt.
		foreach (void* address in blocks) {
			for (var call = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) call != null; call = CApi.next_instruction (call)) {
				if (CApi.opcode (call) != CApi.Opcode.CALL) {
					continue;
				}
				string name = callee (call);
				if (name == "astra_async_run" && CApi.argument_count (call) == 3) {
					var task = held_aliases.lookup ((void*) CApi.operand (call, 1));
					if (task != null && task.capture.inputs.deferred_error && !host_error_calls.contains ((void*) call)) {
						throw new LlvmError.VERIFICATION ("scoped deferred error observation requires its complete output-slot and payload authority");
					}
				}
				if ((name == "astra_async_wait" || name == "astra_async_bridge_wait") && CApi.argument_count (call) >= 3) {
					var task = held_aliases.lookup ((void*) CApi.operand (call, 1));
					if (task != null && task.capture.inputs.deferred_error && !number (CApi.operand (call, name == "astra_async_bridge_wait" ? 3 : 2), 1) && !wait_error_bound (task)) {
						throw new LlvmError.VERIFICATION ("scoped deferred error observation requires its complete admitted payload authority");
					}
				}
			}
		}
		storage.prepare_owner_reads (blocks);
		storage.verify_addresses (consuming, borrows, owned_inputs, fresh_result);
		foreach (int allocation in task_allocations.get_keys ()) {
			void* task = (void*) allocations[allocation];
			if (!phi_positions.contains (task)) {
				phi_positions.insert (task, (int) pointer_phis.length);
				pointer_phis.add (task);
			}
			constructor_results.insert (task, true);
		}
		// Preserve physical error-result observations through backing cleanup
		// joins. These are branch facts, never implicit allocation retirement.
		foreach (void* address in blocks) {
			for (var instruction = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				var contract = borrows == null ? null : borrows.lookup ((void*) CApi.called_value (instruction));
				var owner_contract = consuming == null ? null : consuming.lookup ((void*) CApi.called_value (instruction));
				bool checked = contract != null && contract.scoped_receiver && contract.checked_constructor && contract.accepts (instruction, 0);
				if (owner_contract != null && owner_contract.fields != null && owner_contract.fields.scoped_receiver && owner_contract.fields.checked_constructor) {
					owner_contract.field_call (instruction);
					checked = true;
				}
				if (checked) {
					phi_positions.insert ((void*) instruction, (int) pointer_phis.length);
					pointer_phis.add ((void*) instruction);
					constructor_results.insert ((void*) instruction, true);
				}
			}
		}
		// Track only explicit pointer/null comparisons in scoped-frame callers.
		// Their branch facts prove the nominated error backing is nonnull after
		// its actual allocation trap edge, without assuming arbitrary calls succeed.
		if (task_allocations.size () != 0 || held_tasks.length != 0) {
			foreach (void* address in blocks) {
				for (var instruction = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.ICMP || CApi.predicate (instruction) != CApi.IntPredicate.EQ && CApi.predicate (instruction) != CApi.IntPredicate.NE) {
						continue;
					}
					var left = CApi.operand (instruction, 0);
					var right = CApi.operand (instruction, 1);
					var value = null_pointer (left) ? right : null_pointer (right) ? left : (CApi.ValueRef) null;
					if ((void*) value == null || null_pointer (value) || CApi.type_kind (CApi.type_of (value)) != CApi.TypeKind.POINTER) {
						continue;
					}
					var tracked = pointer (value);
					if (tracked != null && !task_allocations.contains (tracked.allocation)) {
						continue;
					}
					if (!phi_positions.contains ((void*) value)) {
						phi_positions.insert ((void*) value, (int) pointer_phis.length);
						pointer_phis.add ((void*) value);
					}
					constructor_results.insert ((void*) value, true);
				}
			}
		}
		do {
			changed = false;
			foreach (void* address in blocks) {
				for (var instruction = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) instruction != null && CApi.opcode (instruction) == CApi.Opcode.PHI; instruction = CApi.next_instruction (instruction)) {
					if (phi_positions.contains ((void*) instruction) || CApi.type_kind (CApi.type_of (instruction)) != CApi.TypeKind.POINTER) {
						continue;
					}
					for (uint p = 0; p < CApi.incoming_count (instruction); p++) {
						if (constructor_results.contains ((void*) CApi.incoming_value (instruction, p))) {
							phi_positions.insert ((void*) instruction, (int) pointer_phis.length);
							pointer_phis.add ((void*) instruction);
							constructor_results.insert ((void*) instruction, true);
							changed = true;
							break;
						}
					}
				}
			}
		} while (changed);
		if (coroutine != null) {
			for (uint o = 0; o < coroutine.plan.owner_count; o++) {
				int field = (int) coroutine.owner_field (o);
				var alias = frame_values.lookup (field);
				if (alias != null) {
					frame_flags.insert (field + 1, alias);
				}
			}
		}
		foreach (void* data in result_data.get_keys ()) {
			var task = result_data.lookup (data);
			for (var use = CApi.first_use ((CApi.ValueRef) data); (void*) use != null; use = CApi.next_use (use)) {
				var user = CApi.user (use);
				if (result_reads.lookup ((void*) user) != task && plain_result_reads.lookup ((void*) user) != task || (void*) CApi.operand (user, 0) != data) {
					throw new LlvmError.VERIFICATION ("scoped child success storage escaped its original typed observation");
				}
			}
		}

		// Scoped frame admission produces an ordinary pointer error PHI. Keep
		// its actual predecessor's null fact; a live task must not follow the
		// impossible failure cleanup edge after successful checked admission.
		if (task_allocations.size () != 0 || held_tasks.length != 0) {
			foreach (void* address in blocks) {
				for (var instruction = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) instruction != null && CApi.opcode (instruction) == CApi.Opcode.PHI; instruction = CApi.next_instruction (instruction)) {
					if (CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.POINTER && !phi_positions.contains ((void*) instruction)) {
						phi_positions.insert ((void*) instruction, (int) pointer_phis.length);
						pointer_phis.add ((void*) instruction);
					}
				}
			}
		}

		foreach (void* address in blocks) {
			for (var instruction = CApi.first_instruction ((CApi.BasicBlockRef) address); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				var alias = pointer (instruction);
				var opcode = CApi.opcode (instruction);
				if (opcode == CApi.Opcode.PHI && (void*) CApi.type_of (instruction) == (void*) CApi.int1_type_in_context (CApi.type_context (CApi.type_of (instruction)))) {
					condition_positions.insert ((void*) instruction, (int) condition_phis.length);
					condition_phis.add ((void*) instruction);
				}
				if (alias == null || opcode != CApi.Opcode.PHI && opcode != CApi.Opcode.SELECT) {
					continue;
				}
				if (opcode == CApi.Opcode.PHI && !phi_positions.contains ((void*) instruction)) {
					phi_positions.insert ((void*) instruction, (int) pointer_phis.length);
					pointer_phis.add ((void*) instruction);
				}
				if (opcode == CApi.Opcode.PHI && LlvmBufferExchangeOrder.precedes (instruction, (CApi.ValueRef) allocations[alias.allocation])) {
					throw new LlvmError.VERIFICATION ("loop-carried scoped pointer predates its allocation generation");
				}
				if (opcode == CApi.Opcode.PHI) {
					foreach (var slot in storage.slots) {
						if ((void*) slot.store != null && slot.owner == alias.owner && LlvmBufferExchangeOrder.precedes (instruction, slot.store)) {
							throw new LlvmError.VERIFICATION ("loop-carried scoped pointer predates its storage transfer");
						}
					}
				}
				uint count = opcode == CApi.Opcode.PHI ? CApi.incoming_count (instruction) : 2;
				for (uint i = 0; i < count; i++) {
					var value = opcode == CApi.Opcode.PHI ? CApi.incoming_value (instruction, i) : CApi.operand (instruction, i + 1);
					var source = pointer (value);
					if (!empty_join (value, new HashTable<void*, bool> (direct_hash, direct_equal)) && (source == null || source.allocation != alias.allocation || source.root != alias.root || source.owner != alias.owner)) {
						size_t length;
						throw new LlvmError.VERIFICATION ("scoped pointer alias lost its complete allocation identity (caller=%s, alias=%s, input=%s, original-owner=%d, input-owner=%d)", CApi.value_name (function, out length), CApi.value_name (instruction, out length), CApi.value_name (value, out length), alias.owner, source == null ? -1 : source.owner);
					}
				}
			}
		}
	}

	// A restore SELECT can be null while its original allocation is owned by
	// a carrier. Resolve only exact physical conditions; null transport never
	// discharges that separate allocation or its current owner handle.
	private int known_condition(CApi.ValueRef condition, uint[] state) {
		int host = host_error_condition (condition, state);
		if (host >= 0) {
			return host;
		}
		if ((void*) CApi.is_constant_int (condition) != null) {
			return CApi.const_int_zext (condition) == 0 ? 0 : 1;
		}
		if (condition_positions.contains ((void*) condition)) {
			uint observed = state[condition_offset + condition_positions.lookup ((void*) condition)];
			return observed == 1 ? 0 : observed == 2 ? 1 : -1;
		}
		if ((void*) CApi.is_instruction (condition) != null && CApi.opcode (condition) == CApi.Opcode.XOR && (void*) CApi.type_of (condition) == (void*) CApi.int1_type_in_context (CApi.type_context (CApi.type_of (condition)))) {
			int left = known_condition (CApi.operand (condition, 0), state);
			int right = known_condition (CApi.operand (condition, 1), state);
			return left < 0 || right < 0 ? -1 : left ^ right;
		}
		if (result_shape != null && (void*) CApi.is_instruction (condition) != null) {
			if (CApi.opcode (condition) == CApi.Opcode.LOAD && frame_field (CApi.operand (condition, 0)) == (int) coroutine.result_live_field ()) {
				return state[result_live_offset] == 1 ? 0 : state[result_live_offset] == 2 ? 1 : -1;
			}
			if (CApi.opcode (condition) == CApi.Opcode.AND && (void*) CApi.type_of (condition) == (void*) CApi.int1_type_in_context (CApi.type_context (CApi.type_of (condition)))) {
				int left = known_condition (CApi.operand (condition, 0), state);
				int right = known_condition (CApi.operand (condition, 1), state);
				return left == 0 || right == 0 ? 0 : left == 1 && right == 1 ? 1 : -1;
			}
			if (CApi.opcode (condition) == CApi.Opcode.ICMP && (CApi.predicate (condition) == CApi.IntPredicate.EQ || CApi.predicate (condition) == CApi.IntPredicate.NE) && (void*) CApi.operand (condition, 0) == (void*) CApi.get_param (coroutine.destroy, 1) && number (CApi.operand (condition, 1), 0)) {
				uint disposition = state[result_discard_offset];
				return disposition == 1 ? CApi.predicate (condition) == CApi.IntPredicate.EQ ? 1 : 0 : disposition == 2 ? CApi.predicate (condition) == CApi.IntPredicate.NE ? 1 : 0 : -1;
			}
		}
		if (coroutine != null && (void*) CApi.is_instruction (condition) != null && CApi.opcode (condition) == CApi.Opcode.LOAD) {
			int field = frame_field (CApi.operand (condition, 0));
			if (field >= 0 && (void*) CApi.type_of (condition) == (void*) CApi.int1_type_in_context (CApi.type_context (CApi.type_of (condition)))) {
				uint flag = state[frame_offset + field];
				return flag == 1 ? 0 : flag == 2 ? 1 : -1;
			}
		}
		if (constructor_stack != null) {
			int known = constructor_stack.condition (condition, state, stack_offset);
			if (known >= 0) {
				return known;
			}
		}
		if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ && CApi.predicate (condition) != CApi.IntPredicate.NE) {
			return -1;
		}
		var left = CApi.operand (condition, 0);
		var right = CApi.operand (condition, 1);
		var value = null_pointer (left) ? right : null_pointer (right) ? left : (CApi.ValueRef) null;
		if ((void*) value == null) {
			return -1;
		}
		// A nullable owner selection can mean that ownership moved into a
		// live parent. Its null arm is not evidence of backing absence.
		if (storage.handle_alias (value)) {
			var selected = selected_value (value, state);
			int absent = -1;
			if (null_pointer (selected)) {
				absent = 1;
			} else if ((void*) selected == (void*) value) {
				var alias = pointer (value);
				if (alias != null && state[alias.allocation] == 1) {
					absent = 1;
				} else if (alias != null && state[alias.allocation] == 2 && (selected_null_lifetimes (value, state) & 2) == 0) {
					absent = 0;
				} else {
					return -1;
				}
			}
			if (absent >= 0) {
				return CApi.predicate (condition) == CApi.IntPredicate.EQ ? absent : 1 - absent;
			}
			value = selected;
		}
		value = selected_value (value, state);
		int presence = pointer_presence (value, state);
		int empty = presence == 1 ? 1 : presence == 2 ? 0 : -1;
		var heap = storage.heap_owner (value);
		var held = held_aliases.lookup ((void*) value);
		if (held != null) {
			uint lifetime = state[held_offset + held.ordinal];
			if (lifetime == 1) {
				empty = 1;
			} else if (lifetime == 2 || lifetime == 8) {
				empty = 0;
			}
		}
		if (constructor_results.contains ((void*) value)) {
			uint observed = state[phi_offset + phi_positions.lookup ((void*) value)];
			if (observed == 1 || observed == 2) {
				empty = observed == 1 ? 1 : 0;
			}
		}

		if (heap != null && storage.is_heap_root (value, heap)) {
			uint h = 0;
			assert (storage.heaps.find (heap, out h));
			uint backing = state[heap_offset + (int) h];
			if (backing == 1) {
				empty = 1;
			} else if (backing == 2 || backing == 4) {
				empty = 0;
			}
		}
		if (empty < 0 && storage.known_destructor (value)) {
			empty = 0;
		}
		if (empty < 0 && null_pointer (selected_value (value, state))) {
			empty = 1;
		}
		return empty < 0 ? -1 : CApi.predicate (condition) == CApi.IntPredicate.EQ ? empty : 1 - empty;
	}

	private CApi.ValueRef selected_value(CApi.ValueRef value, uint[] state) {
		if (storage.choice_null (value)) {
			return CApi.const_null (CApi.type_of (value));
		}
		var empty_task = empty_result_values.lookup ((void*) value);
		if (empty_task != null && state[observed_offset + empty_task.ordinal] == 2 && state[phase_offset + empty_task.ordinal] == 5) {
			return CApi.const_null (CApi.type_of (value));
		}
		if (result_shape != null && empty_body_values.contains ((void*) value) && state[result_live_offset] == 2 && state[result_offset + (int) empty_body_values.lookup ((void*) value)] == 1) {
			return CApi.const_null (CApi.type_of (value));
		}
		if (null_results.contains ((void*) value)) {
			return CApi.const_null (CApi.type_of (value));
		}
		if (result_shape != null && state[result_live_offset] == 2) {
			var alias = pointer (value);
			if (alias != null && alias.root) {
				for (uint f = 0; f < result_owners.length; f++) {
					var owner = result_owners[f];
					if (owner != null && owner.owner == alias.owner && owner.allocation == alias.allocation && state[result_offset + f] == 1) {
						return CApi.const_null (CApi.type_of (value));
					}
				}
			}
		}
		if (coroutine != null && (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.LOAD && CApi.type_kind (CApi.type_of (value)) == CApi.TypeKind.POINTER) {
			int field = frame_field (CApi.operand (value, 0));
			if (field >= 0 && !frame_values.contains (field) && state[frame_offset + field] == 1) {
				return CApi.const_null (CApi.type_of (value));
			}
		}
		if (empty_join (value, new HashTable<void*, bool> (direct_hash, direct_equal))) {
			return CApi.const_null (CApi.type_of (value));
		}
		if (phi_positions.contains ((void*) value) && state[phi_offset + phi_positions.lookup ((void*) value)] == 1) {
			return CApi.const_null (CApi.type_of (value));
		}
		if ((void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.SELECT) {
			return value;
		}
		int condition = known_condition (CApi.operand (value, 0), state);
		return condition < 0 ? value : selected_value (CApi.operand (value, condition == 1 ? 1 : 2), state);
	}

	// A loop may revisit a nullable publication after an older generation
	// retired. Use this edge's incoming null alternative, not the union of
	// all predecessor generations accumulated by correlate_null.
	private uint selected_null_lifetimes(CApi.ValueRef value, uint[] state) {
		value = selected_value (value, state);
		if (!constructor_results.contains ((void*) value) && phi_positions.contains ((void*) value)) {
			uint selected = state[phi_offset + phi_positions.lookup ((void*) value)];
			if ((selected & 2) != 0) {
				return selected >> 2;
			}
		}
		return null_lifetimes.lookup ((void*) value);
	}

	private void select_pointer_phis(CApi.BasicBlockRef target, CApi.BasicBlockRef prior, uint[] state) {
		uint[] previous = state.copy ();
		// Short-circuit boolean PHIs retain the exact incoming edge's truth.
		// Otherwise an already-taken `a || b` arm could spuriously execute b
		// and consume an owner that was transferred on the preceding arm.
		for (var instruction = CApi.first_instruction (target); (void*) instruction != null && CApi.opcode (instruction) == CApi.Opcode.PHI; instruction = CApi.next_instruction (instruction)) {
			if (!condition_positions.contains ((void*) instruction)) {
				continue;
			}
			for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
				if ((void*) CApi.incoming_block (instruction, i) != (void*) prior) {
					continue;
				}
				int known = known_condition (CApi.incoming_value (instruction, i), previous);
				state[condition_offset + condition_positions.lookup ((void*) instruction)] = known < 0 ? 0U : known == 0 ? 1U : 2U;
			}
		}
		for (var instruction = CApi.first_instruction (target); (void*) instruction != null && CApi.opcode (instruction) == CApi.Opcode.PHI; instruction = CApi.next_instruction (instruction)) {
			if (!phi_positions.contains ((void*) instruction)) {
				continue;
			}
			for (uint i = 0; i < CApi.incoming_count (instruction); i++) {
				if ((void*) CApi.incoming_block (instruction, i) == (void*) prior) {
					var value = selected_value (CApi.incoming_value (instruction, i), previous);
					state[phi_offset + phi_positions.lookup ((void*) instruction)] = null_pointer (value) ? 1U : constructor_results.contains ((void*) instruction) ? constructor_results.contains ((void*) value) ? previous[phi_offset + phi_positions.lookup ((void*) value)] : 0U : 2U | (selected_null_lifetimes (value, previous) << 2);
				}
			}
		}
	}

	private bool null_record_input(CApi.ValueRef value, HashTable<void*, bool> seen) {
		if (null_pointer (value)) {
			return true;
		}
		if (seen.contains ((void*) value)) {
			return false;
		}
		seen.insert ((void*) value, true);
		if (consuming == null || (void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.EXTRACT_VALUE) {
			return false;
		}
		var call = CApi.operand (value, 0);
		if ((void*) CApi.is_instruction (call) != null && CApi.opcode (call) == CApi.Opcode.LOAD) {
			var channel = checked_slots.lookup ((void*) CApi.operand (call, 0));
			if (channel == null || !channel.aggregate) {
				return false;
			}
			call = channel.call;
		}
		if ((void*) CApi.is_instruction (call) == null || CApi.opcode (call) != CApi.Opcode.CALL) {
			return false;
		}
		var contract = consuming.lookup ((void*) CApi.called_value (call));
		int field = contract == null ? -1 : contract.extracted_field (value);
		if (field < 0 || contract.result_slot (field) < 0) {
			return false;
		}
		return null_record_input (CApi.operand (call, contract.physical_position (contract.result_slot (field))), seen);
	}

	private bool fresh_return(CApi.ValueRef value, LlvmScopedPointer? alias, uint[] state) throws LlvmError {
		if (fresh_result == null || alias == null || !alias.root) {
			return false;
		}
		uint lifetime = state[alias.allocation];
		uint owner = state[owner_offset + alias.owner];
		// A checked factory can return either its live owner or actual absence.
		// A null alternative that discards live backing is never publication.
		if (lifetime == 0 || owner == 0 || (lifetime & ~3U) != 0 || (owner & ~3U) != 0 || (lifetime & 2) != (owner & 2) || (null_lifetimes.lookup ((void*) value) & ~1U) != 0) {
			return false;
		}
		return fresh_result.matches ((CApi.ValueRef) contexts[alias.allocation], (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation]);
	}

	private bool absent_graph_call(CApi.ValueRef call, uint position, uint[] state) throws LlvmError {
		if (consuming == null || CApi.opcode (call) != CApi.Opcode.CALL) {
			return false;
		}
		var contract = consuming.lookup ((void*) CApi.called_value (call));
		if (contract == null || contract.owner_graph == null || contract.graph_forwarding || contract.graph_parameter != position) {
			return false;
		}
		var value = CApi.operand (call, position);
		var heap = storage.heap_owner (value);
		var alias = pointer (value);
		uint index = 0;
		if (heap == null || alias == null || !alias.root || !storage.is_heap_root (value, heap) || !storage.heaps.find (heap, out index) || state[heap_offset + (int) index] != 1) {
			return false;
		}
		if ((void*) heap.layout != (void*) contract.owner_graph.layout || state[alias.allocation] != 1 || state[owner_offset + alias.owner] != 1 || !contract.accepts (call, position, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation])) {
			throw new LlvmError.VERIFICATION ("absent scoped graph lost its exact allocation or native call authority");
		}
		for (int f = 0; f < contract.owner_graph.members.length; f++) {
			var slot = storage.result_field (value, contract.owner_graph.members[f], contract.owner_graph.path (f));
			uint field = 0;
			if (slot == null || !storage.slots.find (slot, out field) || state[storage_offset + (int) field] != 8) {
				throw new LlvmError.VERIFICATION ("absent scoped graph retains an occupied child field");
			}
		}
		return true;
	}

	private void owner_transport(CApi.ValueRef value, uint[] state) throws LlvmError {
		// Null can mean actual absence, or a discarded still-live allocation.
		// A consuming call cannot discharge the latter backing obligation.
		var transported = selected_value (value, state);
		bool observed_nonnull = constructor_results.contains ((void*) transported) && state[phi_offset + phi_positions.lookup ((void*) transported)] == 2;
		if (null_pointer (transported) || !observed_nonnull && (selected_null_lifetimes (transported, state) & 2) != 0) {
			size_t name_length;
			throw new LlvmError.VERIFICATION ("scoped owner transport requires exact allocation absence for every null alternative (caller=%s, value=%s, selected=%s, null-lifetime=%u)", CApi.value_name (function, out name_length), CApi.value_name (value, out name_length), CApi.value_name (transported, out name_length), selected_null_lifetimes (transported, state));
		}
	}

	private bool capture_use(CApi.ValueRef instruction, uint position, LlvmScopedPointer alias, uint[] state) throws LlvmError {
		var task = held_aliases.lookup ((void*) instruction);
		if (task == null || CApi.opcode (instruction) != CApi.Opcode.CALL || !alias.root || !task.owners.contains ((int) position)) {
			return false;
		}
		if (!task.capture.accepts (instruction, position, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation])) {
			return false;
		}
		owner_transport (CApi.operand (instruction, position), state);
		return true;
	}

	private bool held_wait(CApi.ValueRef call, uint position) throws LlvmError {
		if (coroutine == null || position != 1) {
			return false;
		}
		for (uint e = 0; e < coroutine.continuation_count; e++) {
			var edge = coroutine.continuation (e);
			if ((void*) edge.admission () == (void*) call && (callee (call) == "astra_async_wait" || callee (call) == "astra_async_bridge_wait")) {
				edge.verify (coroutine.resume, edge.next_state ());
				return true;
			}
		}
		return false;
	}

	private static void observed_abi(CApi.ValueRef call, bool phase) throws LlvmError {
		var context = CApi.type_context (CApi.type_of (call));
		var pointer = CApi.pointer_type_in_context (context, 0);
		CApi.TypeRef[] parameters = {
			pointer
		};
		var type = CApi.function_type (phase ? CApi.int32_type_in_context (context) : pointer, parameters, 1, 0);
		if (CApi.argument_count (call) != 1 || (void*) CApi.called_function_type (call) != (void*) type || CApi.instruction_call_conv (call) != CApi.CallConv.C || CApi.count_basic_blocks (CApi.called_value (call)) != 0 || (void*) CApi.global_value_type (CApi.called_value (call)) != (void*) type || CApi.function_call_conv (CApi.called_value (call)) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("scoped child observation lost its exact external runtime ABI");
		}
	}

	// The typed read acquires the original f0 owners only on an admitted
	// successful observation. release_wait must then transfer that payload.
	private void result_observation(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		var plain = plain_result_reads.lookup ((void*) instruction);
		if (plain != null) {
			if (strict && (coroutine == null || state[wait_offset] != (uint) plain.ordinal + 1 || state[held_offset + plain.ordinal] != 8 || state[phase_offset + plain.ordinal] != 5 || state[observed_offset + plain.ordinal] != 1)) {
				throw new LlvmError.VERIFICATION ("scoped child scalar read requires its original admitted successful observation");
			}
			state[observed_offset + plain.ordinal] = 2;
			return;
		}
		var task = result_reads.lookup ((void*) instruction);
		if (task == null) {
			return;
		}
		if (strict && (coroutine == null || state[wait_offset] != (uint) task.ordinal + 1 || state[held_offset + task.ordinal] != 8 || state[phase_offset + task.ordinal] != 5 || state[observed_offset + task.ordinal] != 1)) {
			throw new LlvmError.VERIFICATION ("scoped result read requires its original admitted child and actual successful phase");
		}
		var shape = task.capture.result;
		for (uint f = 0; f < shape.field_count; f++) {
			int capture = shape.capture (f);
			if (capture < 0) {
				continue;
			}
			int position = (int) task.capture.inputs.physical_position (capture);
			var held = task.owners.lookup (position);
			var result = task.results.lookup ((int) f);
			if (held == null || result == null) {
				if (!null_pointer (CApi.operand (task.call, (uint) position))) {
					throw new LlvmError.VERIFICATION ("scoped result observation lacks its complete original capture mapping");
				}
				continue;
			}
			if (state[owner_offset + held.owner] == 1) {
				state[owner_offset + result.owner] = 1;
				continue;
			}
			if (strict && (state[held.allocation] != 2 || state[owner_offset + held.owner] != 2)) {
				throw new LlvmError.VERIFICATION ("scoped result observation lost its original retained owner");
			}
			state[owner_offset + held.owner] = 4;
			state[owner_offset + result.owner] = 2;
		}
		state[observed_offset + task.ordinal] = 2;
	}

	private void child_phase_edge(CApi.ValueRef end, uint successor, uint[] state, bool strict) throws LlvmError {
		if (CApi.opcode (end) != CApi.Opcode.SWITCH) {
			return;
		}
		var phase = CApi.operand (end, 0);
		if ((void*) CApi.is_instruction (phase) == null || CApi.opcode (phase) != CApi.Opcode.CALL || callee (phase) != "astra_async_phase" || CApi.argument_count (phase) != 1) {
			return;
		}
		var task = held_aliases.lookup ((void*) CApi.operand (phase, 0));
		if (task == null || task.capture.result == null && (void*) task.capture.inputs.plain_task_result == null && !task.capture.inputs.deferred_error) {
			return;
		}
		observed_abi (phase, true);
		if (strict && (coroutine == null || state[held_offset + task.ordinal] != 8 || state[wait_offset] != (uint) task.ordinal + 1)) {
			throw new LlvmError.VERIFICATION ("scoped result phase requires its original admitted child observation");
		}
		uint value = successor == 0 ? 0U : (uint) CApi.const_int_zext (CApi.switch_case_value (end, successor));
		state[phase_offset + task.ordinal] = value == 5 || value == 6 || value == 7 ? value : 0;
	}

	private void retire_held(LlvmScopedHeldTask task, uint[] state, bool strict, bool observed_result = false) throws LlvmError {
		if (strict && state[held_offset + task.ordinal] != 2 && state[held_offset + task.ordinal] != 8) {
			throw new LlvmError.VERIFICATION ("scoped task retirement lacks its actual held obligation");
		}
		state[held_offset + task.ordinal] = 4;
		foreach (var owner in task.owners.get_values ()) {
			if (observed_result && state[owner_offset + owner.owner] == 4) {
				bool returned = false;
				foreach (var result in task.results.get_values ()) {
					if (result.allocation == owner.allocation && state[owner_offset + result.owner] == 2) {
						returned = true;
					}
				}
				if (!returned && !wait_error_owner (task, owner, state)) {
					throw new LlvmError.VERIFICATION ("scoped task transfer lost its observed result or error owner");
				}
				continue;
			}
			if (state[owner_offset + owner.owner] == 1) {
				continue;
			}
			if (strict && state[owner_offset + owner.owner] != 2) {
				throw new LlvmError.VERIFICATION ("scoped task observation lost its exact held owner");
			}
			state[owner.allocation] = 4;
			state[owner_offset + owner.owner] = 4;
		}
	}

	private void transfer_held(LlvmScopedHeldTask task, uint[] state, bool strict) throws LlvmError {
		foreach (int position in task.owners.get_keys ()) {
			var source = pointer (CApi.operand (task.call, (uint) position));
			var held = task.owners.lookup (position);
			if (null_pointer (selected_value (CApi.operand (task.call, (uint) position), state)) || state[source.allocation] == 1 && state[owner_offset + source.owner] == 1) {
				state[owner_offset + held.owner] = 1;
				continue;
			}
			if (strict && (state[source.allocation] != 2 || state[owner_offset + source.owner] != 2)) {
				throw new LlvmError.VERIFICATION ("scoped capture transfer lacks its exact live owner");
			}
			state[owner_offset + source.owner] = 4;
			state[owner_offset + held.owner] = 2;
		}
	}

	private void held_edge(CApi.ValueRef end, uint successor, uint[] state, bool strict) throws LlvmError {
		if (CApi.opcode (end) != CApi.Opcode.COND_BR || CApi.successor_count (end) != 2) {
			return;
		}
		foreach (var task in held_tasks) {
			if (!task.capture.checked_admission || (void*) task.capture.admission_branch () != (void*) end) {
				continue;
			}
			task.capture.verify (task.call);
			if (strict && state[held_offset + task.ordinal] != 16) {
				throw new LlvmError.VERIFICATION ("checked scoped capture admission lacks its original pending transfer");
			}
			if (successor == 0) {
				state[held_offset + task.ordinal] = 1;
				foreach (var held in task.owners.get_values ()) {
					state[owner_offset + held.owner] = 1;
				}
			} else {
				state[held_offset + task.ordinal] = 2;
				transfer_held (task, state, strict);
			}
		}
		if (coroutine == null) {
			return;
		}
		for (uint e = 0; e < coroutine.continuation_count; e++) {
			var edge = coroutine.continuation (e);
			if ((void*) CApi.instruction_parent (edge.admission ()) != (void*) CApi.instruction_parent (end) || !held_wait (edge.admission (), 1)) {
				continue;
			}
			var task = held_aliases.lookup ((void*) CApi.operand (edge.admission (), 1));
			state[wait_offset] = successor == 0 ? task == null ? 0U : (uint) task.ordinal + 1 : uint.MAX;
			if (task != null) {
				if (successor == 0) {
					state[held_offset + task.ordinal] = 8;
				} else {
					retire_held (task, state, strict);
				}
			}
		}
		if ((void*) CApi.instruction_parent (end) == (void*) coroutine.cancel_entry && successor == 0) {
			state[wait_offset] = uint.MAX;
			foreach (var task in held_tasks) {
				if ((state[held_offset + task.ordinal] & 10) == 0) {
					continue;
				}
				if ((void*) CApi.operand (task.call, CApi.argument_count (task.call) - 3) != (void*) coroutine.task) {
					throw new LlvmError.VERIFICATION ("scoped child drain requires its original parent association");
				}
				retire_held (task, state, strict);
			}
		}
	}

	private void held_use(CApi.ValueRef instruction, uint[] state) throws LlvmError {
		var opcode = CApi.opcode (instruction);
		for (uint p = 0; p < CApi.operand_count (instruction); p++) {
			var task = held_aliases.lookup ((void*) CApi.operand (instruction, p));
			if (task == null) {
				continue;
			}
			if (opcode == CApi.Opcode.ICMP && state[held_offset + task.ordinal] == 1) {
				continue;
			}
			if (opcode == CApi.Opcode.ICMP && state[held_offset + task.ordinal] == 16 && (void*) CApi.operand (task.capture.admission_branch (), 0) == (void*) instruction) {
				continue;
			}
			if (opcode == CApi.Opcode.STORE && p == 0 && state[held_offset + task.ordinal] == 16 && held_fields.lookup (frame_field (CApi.operand (instruction, 1))) == task) {
				continue;
			}
			if (state[held_offset + task.ordinal] != 2 && state[held_offset + task.ordinal] != 8) {
				throw new LlvmError.VERIFICATION ("scoped captured task use lacks its exact retained ownership");
			}
			if (opcode == CApi.Opcode.ICMP) {
				continue;
			}
			if (opcode == CApi.Opcode.STORE && p == 0 && held_fields.lookup (frame_field (CApi.operand (instruction, 1))) == task) {
				continue;
			}
			if (opcode == CApi.Opcode.CALL) {
				if (held_wait (instruction, p)) {
					if (state[held_offset + task.ordinal] != 2) {
						throw new LlvmError.VERIFICATION ("scoped child wait duplicates an admitted observation");
					}
					continue;
				}
				if (p == 0 && callee (instruction) == "astra_async_data" && result_data.lookup ((void*) instruction) == task && state[held_offset + task.ordinal] == 8) {
					observed_abi (instruction, false);
					continue;
				}
				if (p == 0 && callee (instruction) == "astra_async_exception" && state[held_offset + task.ordinal] == 8 && CApi.argument_count (instruction) == 1) {
					var pointer_type = CApi.type_of (CApi.operand (instruction, 0));
					CApi.TypeRef[] parameters = {
						pointer_type
					};
					var type = CApi.function_type (pointer_type, parameters, 1, 0);
					if ((void*) CApi.called_function_type (instruction) != (void*) type || CApi.instruction_call_conv (instruction) != CApi.CallConv.C || CApi.count_basic_blocks (CApi.called_value (instruction)) != 0 || (void*) CApi.global_value_type (CApi.called_value (instruction)) != (void*) type || CApi.function_call_conv (CApi.called_value (instruction)) != CApi.CallConv.C) {
						throw new LlvmError.VERIFICATION ("scoped child exception observation lost its exact runtime ABI");
					}
					continue;
				}
				bool retires;
				if (LlvmScopedTaskFrame.operation (instruction, p, out retires)) {
					if (retires && state[held_offset + task.ordinal] != 2) {
						throw new LlvmError.VERIFICATION ("scoped waiting child requires its actual release-wait observation");
					}
					continue;
				}
			}
			throw new LlvmError.VERIFICATION ("scoped captured task escaped its exact observation operations");
		}
		var created = captured_tasks == null ? null : captured_tasks.lookup ((void*) instruction);
		if (created != null) {
			created.verify (instruction);
			var used = new HashTable<int, bool> (direct_hash, direct_equal);
			var shape = created.inputs;
			for (int p = 0; p < shape.count; p++) {
				var value = CApi.operand (instruction, shape.physical_position (p));
				if (null_pointer (selected_value (value, state))) {
					continue;
				}
				var incoming = pointer (value);
				if (incoming == null || !incoming.root || used.contains (incoming.allocation)) {
					size_t length;
					throw new LlvmError.VERIFICATION ("scoped captured task requires distinct actual input allocations (caller=%s, value=%s, position=%u, tracked=%d, root=%d)", CApi.value_name (function, out length), CApi.value_name (value, out length), shape.physical_position (p), incoming == null ? 0 : 1, incoming != null && incoming.root ? 1 : 0);
				}
				used.insert (incoming.allocation, true);
			}
		}
	}

	private void held_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		var task = held_aliases.lookup ((void*) instruction);
		if (task != null && (void*) task.call == (void*) instruction) {
			if (strict && (state[held_offset + task.ordinal] & 26) != 0) {
				throw new LlvmError.VERIFICATION ("scoped captured task recreated before observation");
			}
			state[held_offset + task.ordinal] = task.capture.checked_admission ? 16U : 2U;
			state[phase_offset + task.ordinal] = 0;
			state[observed_offset + task.ordinal] = 1;
			if (!task.capture.checked_admission) {
				transfer_held (task, state, strict);
			}
		}
		if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
			return;
		}
		if (coroutine != null && callee (instruction) == "astra_async_release_wait") {
			var word = CApi.int32_type_in_context (CApi.type_context (CApi.type_of (instruction)));
			var pointer_type = CApi.type_of (coroutine.task);
			CApi.TypeRef[] parameters = {
				pointer_type, word
			};
			var type = CApi.function_type (word, parameters, 2, 0);
			if (CApi.argument_count (instruction) != 2 || (void*) CApi.operand (instruction, 0) != (void*) coroutine.task || !number (CApi.operand (instruction, 1), 0) && !number (CApi.operand (instruction, 1), 1) || (void*) CApi.called_function_type (instruction) != (void*) type || CApi.instruction_call_conv (instruction) != CApi.CallConv.C || CApi.count_basic_blocks (CApi.called_value (instruction)) != 0 || (void*) CApi.global_value_type (CApi.called_value (instruction)) != (void*) type || CApi.function_call_conv (CApi.called_value (instruction)) != CApi.CallConv.C) {
				throw new LlvmError.VERIFICATION ("scoped child release requires its exact parent and observation ABI");
			}
			if (strict && state[wait_offset] == uint.MAX) {
				throw new LlvmError.VERIFICATION ("scoped child release lacks its actual admitted observation");
			}
			uint pending = state[wait_offset];
			state[wait_offset] = uint.MAX;
			uint waiting = 0;
			foreach (var held in held_tasks) {
				if (state[held_offset + held.ordinal] == 8) {
					if (strict && pending != (uint) held.ordinal + 1) {
						throw new LlvmError.VERIFICATION ("scoped child release changed its exact waiting target");
					}
					waiting++;
					bool transferred = held.capture.result != null && number (CApi.operand (instruction, 1), 1) && state[phase_offset + held.ordinal] == 5;
					bool error_transfer = held.capture.inputs.deferred_error && number (CApi.operand (instruction, 1), 1) && state[phase_offset + held.ordinal] == 6;
					if (strict && held.capture.inputs.deferred_error && ((error_transfer && state[observed_offset + held.ordinal] != 2) || (!error_transfer && state[observed_offset + held.ordinal] == 2))) {
						throw new LlvmError.VERIFICATION ("scoped child release lost its actual exception acquisition or discard");
					}
					if (strict && held.capture.result != null && (number (CApi.operand (instruction, 1), 1) && (state[phase_offset + held.ordinal] != 5 && state[phase_offset + held.ordinal] != 6 && state[phase_offset + held.ordinal] != 7 || transferred && state[observed_offset + held.ordinal] != 2) || !transferred && state[observed_offset + held.ordinal] == 2)) {
						throw new LlvmError.VERIFICATION ("scoped child release lost actual result observation or discard");
					}
					if (strict && (void*) held.capture.inputs.plain_task_result != null && state[observed_offset + held.ordinal] == 2 && (!number (CApi.operand (instruction, 1), 1) || state[phase_offset + held.ordinal] != 5)) {
						throw new LlvmError.VERIFICATION ("scoped scalar child release lost its actual successful observation");
					}
					retire_held (held, state, strict, transferred || error_transfer);
				}
			}
			if (waiting > 1) {
				throw new LlvmError.VERIFICATION ("scoped child release observes more than its original waiting target");
			}
		}
		for (uint p = 0; p < CApi.argument_count (instruction); p++) {
			var observed = held_aliases.lookup ((void*) CApi.operand (instruction, p));
			if (observed == null) {
				continue;
			}
			bool retires;
			if (LlvmScopedTaskFrame.operation (instruction, p, out retires) && retires && !host_error_calls.contains ((void*) instruction)) {
				retire_held (observed, state, strict);
			}
		}
	}

	private void empty_error_effect(CApi.ValueRef call, uint[] state, bool strict) throws LlvmError {
		if (CApi.opcode (call) != CApi.Opcode.CALL || consuming == null || CApi.argument_count (call) == 0) {
			return;
		}
		var retiring = storage.heap_owner (CApi.operand (call, 0));
		if (retiring != null && retiring.empty_contract != null && storage.checked_destructor (retiring, call, CApi.operand (call, 0), consuming)) {
			uint h = 0;
			assert (storage.heaps.find (retiring, out h));
			if (strict && (state[heap_offset + (int) h] != 2 || state[empty_heap_offset + (int) h] != 2 && !(retiring.empty_contract != null && !retiring.empty_contract.empty_base && state[empty_heap_offset + (int) h] == 8))) {
				throw new LlvmError.VERIFICATION ("empty inherited retirement lacks its initialized original carrier");
			}
			state[empty_heap_offset + (int) h] = 4;
			return;
		}
		var contract = consuming.lookup ((void*) CApi.called_value (call));
		if (contract == null || contract.empty_backing == null) {
			return;
		}
		var heap = storage.heap_owner (CApi.operand (call, 0));
		uint h = 0;
		if (heap == null || heap.empty_base_shape == null) {
			return;
		}
		if (!contract.empty_constructor_call (call) || !storage.is_heap_root (CApi.operand (call, 0), heap) || !storage.heaps.find (heap, out h) || (void*) contract.empty_backing.layout != (void*) heap.layout || state[heap_offset + (int) h] != 2 || state[empty_heap_offset + (int) h] != 1) {
			throw new LlvmError.VERIFICATION ("empty inherited error requires its original live uninitialized carrier");
		}
		storage.verify_exception (heap, call);
		state[empty_heap_offset + (int) h] = 2;
	}

	private bool deferred_publication(CApi.ValueRef call, CApi.ValueRef value) throws LlvmError {
		if (coroutine == null || deferred_error == null || !LlvmScopedHeapCarrier.named_call (call, "astra_async_complete") || CApi.argument_count (call) != 3 || (void*) CApi.operand (call, 0) != (void*) coroutine.task || !number (CApi.operand (call, 1), 6) || (void*) CApi.operand (call, 2) != (void*) value) {
			return false;
		}
		var context = CApi.type_context (CApi.type_of (call));
		var pointer = CApi.pointer_type_in_context (context, 0);
		CApi.TypeRef[] parameters = {
			pointer, CApi.int32_type_in_context (context), pointer
		};
		var type = CApi.function_type (CApi.void_type_in_context (context), parameters, 3, 0);
		var target = CApi.called_value (call);
		if ((void*) CApi.global_value_type (target) != (void*) type || (void*) CApi.called_function_type (call) != (void*) type || CApi.count_basic_blocks (target) != 0 || CApi.get_linkage (target) != CApi.Linkage.EXTERNAL || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.instruction_call_conv (call) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("deferred scoped error lost its exact external completion ABI");
		}
		var heap = storage.heap_owner (value);
		return heap != null && storage.is_heap_root (value, heap) && heap.exception_shape != null && (heap.exception_shape.same (owned_inputs.error_shape) || heap.empty_base_shape != null && heap.empty_base_shape.same (owned_inputs.error_shape));
	}

	private void deferred_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		if (deferred_error == null || CApi.opcode (instruction) != CApi.Opcode.CALL) {
			return;
		}
		uint target = 0;
		assert (storage.heaps.find (deferred_error.heap, out target));
		if ((void*) instruction == (void*) deferred_error.call) {
			state[heap_offset + (int) target] = state[deferred_offset] == 2 ? 3U : 1U;
			return;
		}
		if (callee (instruction) != "astra_async_complete") {
			return;
		}
		if (CApi.argument_count (instruction) != 3) {
			throw new LlvmError.VERIFICATION ("deferred scoped error lost its complete publication ABI");
		}
		if (!number (CApi.operand (instruction, 1), 6)) {
			if (!null_pointer (CApi.operand (instruction, 2))) {
				throw new LlvmError.VERIFICATION ("retained scoped owner: deferred scoped error requires its actual exception completion phase");
			}
			return;
		}
		if (!deferred_publication (instruction, CApi.operand (instruction, 2))) {
			throw new LlvmError.VERIFICATION ("deferred scoped exception requires its exact live publication carrier");
		}
		var value = CApi.operand (instruction, 2);
		var heap = storage.heap_owner (value);
		uint h = 0;
		if (heap == null || !storage.is_heap_root (value, heap) || heap.exception_shape == null || !(heap.exception_shape.same (owned_inputs.error_shape) || heap.empty_base_shape != null && heap.empty_base_shape.same (owned_inputs.error_shape)) || !storage.heaps.find (heap, out h) || state[heap_offset + (int) h] != 2 || strict && state[deferred_offset] != 1) {
			size_t length;
			throw new LlvmError.VERIFICATION ("deferred scoped exception requires its exact live publication carrier (function=%s, value=%s, heap=%d)", CApi.value_name (function, out length), CApi.value_name (value, out length), heap == null ? 0 : 1);
		}
		bool empty_payload = heap.empty_base_shape != null && (heap.empty_contract.empty_base || state[empty_heap_offset + (int) h] == 2);
		if (!empty_payload) {
			try {
				if (heap.empty_contract != null && !heap.empty_contract.empty_base && state[empty_heap_offset + (int) h] == 8) {
					heap.empty_contract.verify ();
					heap.exception_shape.verify_descriptor ();
				} else {
					storage.verify_exception (heap, instruction);
				}
			} catch (LlvmError failure) {
				size_t length;
				throw new LlvmError.VERIFICATION ("%s (carrier=%s, value=%s, empty-contract=%d, empty-state=%u, heap-state=%u)", failure.message, CApi.value_name (heap.root, out length), CApi.value_name (value, out length), heap.empty_contract == null ? 0 : 1, state[empty_heap_offset + (int) h], state[heap_offset + (int) h]);
			}
		} else {
			heap.exception_shape.verify_descriptor ();
			heap.empty_base_shape.verify_descriptor ();
		} if (empty_payload) {
			if (state[empty_heap_offset + (int) h] != 2) {
				throw new LlvmError.VERIFICATION ("empty deferred error lacks its exact constructor initialization");
			}
			for (int a = 0; a < owned_inputs.count; a++) {
				if (!no_live_allocation (state[a])) {
					throw new LlvmError.VERIFICATION ("empty deferred error retains an unretired captured owner");
				}
			}
		}

		for (int f = 0; f < owned_inputs.error_count; f++) {
			var source = storage.result_field (value, owned_inputs.error_member (f));
			var held = deferred_error.slots[f];
			uint s = 0;
			uint t = 0;
			if (empty_payload) {
				assert (storage.slots.find (held, out t));
				state[storage_offset + (int) t] = 8;
				state[owner_offset + held.owner] = 1;
				continue;
			}
			if (source == null || source.allocation != held.allocation || !storage.slots.find (source, out s) || !storage.slots.find (held, out t) || state[storage_offset + (int) s] != 2 || state[source.allocation] != 2 || state[owner_offset + source.owner] != 2) {
				throw new LlvmError.VERIFICATION ("deferred scoped exception lost its original live payload field");
			}
			state[owner_offset + source.owner] = 4;
			state[storage_offset + (int) s] = 4;
			state[owner_offset + held.owner] = 2;
			state[storage_offset + (int) t] = 2;
		}
		var root_owner = pointer (value);
		if (root_owner != null && root_owner.root) {
			state[root_owner.allocation] = 4;
			state[owner_offset + root_owner.owner] = 4;
		}
		state[heap_offset + (int) h] = 4;
		state[heap_offset + (int) target] = 2;
		state[deferred_offset] = 2;
		state[deferred_empty_offset] = empty_payload ? 2U : 1U;
	}

	private void deferred_edge(CApi.ValueRef end, uint successor, uint[] state) throws LlvmError {
		if (deferred_error == null || CApi.opcode (end) != CApi.Opcode.COND_BR || CApi.successor_count (end) != 2) {
			return;
		}
		var test = CApi.operand (end, 0);
		if ((void*) CApi.is_instruction (test) == null || CApi.opcode (test) != CApi.Opcode.ICMP || CApi.predicate (test) != CApi.IntPredicate.EQ && CApi.predicate (test) != CApi.IntPredicate.NE || (void*) CApi.operand (test, 0) != (void*) deferred_error.call || !null_pointer (CApi.operand (test, 1))) {
			return;
		}
		bool empty = (CApi.predicate (test) == CApi.IntPredicate.EQ) == (successor == 0);
		if (!empty || state[deferred_offset] != 2) {
			return;
		}
		uint h = 0;
		assert (storage.heaps.find (deferred_error.heap, out h));
		state[heap_offset + (int) h] = 4;
		state[deferred_offset] = 4;
		foreach (var slot in deferred_error.slots) {
			uint s = 0;
			assert (storage.slots.find (slot, out s));
			if (state[deferred_empty_offset] == 2) {
				if (state[storage_offset + (int) s] != 8 || !no_live_allocation (state[slot.allocation])) {
					throw new LlvmError.VERIFICATION ("empty deferred error invented a retained scoped field");
				}
				continue;
			}
			if (state[storage_offset + (int) s] != 2 || state[slot.allocation] != 2 || state[owner_offset + slot.owner] != 2) {
				throw new LlvmError.VERIFICATION ("deferred scoped exception transfer lost its retained payload");
			}
			state[storage_offset + (int) s] = 4;
			state[slot.allocation] = 4;
			state[owner_offset + slot.owner] = 4;
		}
	}

	private void result_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		if (result_shape == null) {
			return;
		}
		var opcode = CApi.opcode (instruction);
		if (opcode == CApi.Opcode.STORE && frame_field (CApi.operand (instruction, 1)) == (int) coroutine.result_live_field ()) {
			if (!number (CApi.operand (instruction, 0), 1)) {
				throw new LlvmError.VERIFICATION ("scoped result publication lost its initialized flag");
			}
			state[result_live_offset] = 2;
		}
		if (result_store (instruction)) {
			if (strict && state[result_live_offset] != 1) {
				throw new LlvmError.VERIFICATION ("scoped result publication overwrites an initialized payload");
			}
			for (uint f = 0; f < result_owners.length; f++) {
				var held = result_owners[f];
				var value = result_shape.publication_value (instruction, f);
				if (result_shape.empty_field (f)) {
					if (!null_pointer (selected_value (value, state))) {
						throw new LlvmError.VERIFICATION ("empty scoped result publication requires its exact proved-null field");
					}
					state[result_offset + f] = 1;
					continue;
				}
				if (held == null) {
					continue;
				}
				if (null_pointer (selected_value (value, state))) {
					state[result_offset + f] = 1;
					state[owner_offset + held.owner] = 1;
					continue;
				}
				var incoming = pointer (value);
				if (incoming == null || !incoming.root || incoming.allocation != held.allocation || strict && (state[incoming.allocation] != 2 || state[owner_offset + incoming.owner] != 2)) {
					throw new LlvmError.VERIFICATION ("scoped result publication lacks its exact original live input");
				}
				state[owner_offset + incoming.owner] = 4;
				state[owner_offset + held.owner] = 2;
				state[result_offset + f] = 2;
			}
		}
		if (opcode == CApi.Opcode.LOAD && frame_field (CApi.operand (instruction, 0)) == 0) {
			if ((void*) CApi.type_of (instruction) != (void*) result_shape.result_type () || strict && state[result_live_offset] != 2) {
				throw new LlvmError.VERIFICATION ("scoped result payload read lacks its exact initialized carrier");
			}
		}
	}

	private void result_return(CApi.ValueRef end, uint[] state) throws LlvmError {
		if (result_shape == null || CApi.opcode (end) != CApi.Opcode.RET || (void*) CApi.block_parent (CApi.instruction_parent (end)) != (void*) coroutine.destroy) {
			return;
		}
		for (uint f = 0; f < result_owners.length; f++) {
			var held = result_owners[f];
			if (held == null || (state[held.allocation] & 2) == 0 || state[result_offset + f] != 2) {
				continue;
			}
			if (state[result_live_offset] != 2 || state[result_discard_offset] != 1 || state[owner_offset + held.owner] != 2) {
				throw new LlvmError.VERIFICATION ("scoped result destruction lost actual discard or observed transfer");
			}
			state[held.allocation] = 4;
			state[owner_offset + held.owner] = 4;
			state[result_offset + f] = 4;
		}
	}

	private int pointer_presence(CApi.ValueRef value, uint[] state) {
		value = selected_value (value, state);
		if (null_pointer (value)) {
			return 1;
		}
		if ((void*) CApi.is_instruction (value) == null) {
			return 0;
		}
		if (CApi.opcode (value) == CApi.Opcode.LOAD) {
			int field = frame_field (CApi.operand (value, 0));
			if (field >= 0 && !frame_values.contains (field)) {
				uint fact = state[frame_offset + field];
				return fact == 1 || fact == 2 ? (int) fact : 0;
			}
		}
		if (constructor_results.contains ((void*) value)) {
			uint fact = state[phi_offset + phi_positions.lookup ((void*) value)];
			return fact == 1 || fact == 2 ? (int) fact : 0;
		}
		if (CApi.opcode (value) == CApi.Opcode.CALL && callee (value) == "astra_async_exception" && CApi.argument_count (value) == 1) {
			var task = held_aliases.lookup ((void*) CApi.operand (value, 0));
			if (task != null && state[phase_offset + task.ordinal] == 6) {
				return 2;
			}
		}
		return 0;
	}

	private void frame_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		if (coroutine == null) {
			return;
		}
		var opcode = CApi.opcode (instruction);
		if (opcode != CApi.Opcode.LOAD && opcode != CApi.Opcode.STORE) {
			return;
		}
		int field = frame_field (CApi.operand (instruction, opcode == CApi.Opcode.LOAD ? 0 : 1));
		if (field < 0) {
			return;
		}
		if (storage.frame_origin_field (field)) {
			if (opcode == CApi.Opcode.STORE) {
				state[frame_offset + field] = (uint) pointer_presence (CApi.operand (instruction, 0), state);
			}
			return;
		}
		var heap = storage.frame_heap (field);
		if (heap != null) {
			if (CApi.get_volatile (instruction) != 0 || CApi.get_ordering (instruction) != 0 || CApi.type_kind (opcode == CApi.Opcode.LOAD ? CApi.type_of (instruction) : CApi.type_of (CApi.operand (instruction, 0))) != CApi.TypeKind.POINTER) {
				throw new LlvmError.VERIFICATION ("coroutine heap storage requires exact ordinary pointer accesses");
			}
			if (opcode == CApi.Opcode.LOAD) {
				if (strict && state[frame_offset + field] != 1 && state[frame_offset + field] != 2) {
					size_t length;
					throw new LlvmError.VERIFICATION ("coroutine heap read requires its exact initialized backing field (function=%s, field=%d, state=%u)", CApi.value_name (function, out length), field, state[frame_offset + field]);
				}
			} else {
				var value = CApi.operand (instruction, 0);
				if (null_pointer (value)) {
					state[frame_offset + field] = 1;
				} else {
					if (!storage.is_heap_root (value, heap)) {
						throw new LlvmError.VERIFICATION ("coroutine heap store changed its exact backing identity");
					}
					state[frame_offset + field] = 2;
				}
			} return;
		}
		var alias = frame_values.lookup (field);
		if (alias == null && !frame_flags.contains (field) && opcode == CApi.Opcode.STORE) {
			var value = CApi.operand (instruction, 0);
			if (CApi.type_kind (CApi.type_of (value)) == CApi.TypeKind.POINTER) {
				state[frame_offset + field] = (uint) pointer_presence (value, state);
			} else if ((void*) CApi.type_of (value) == (void*) CApi.int1_type_in_context (CApi.type_context (CApi.type_of (value)))) {
				int truth = known_condition (value, state);
				state[frame_offset + field] = truth < 0 ? 0U : truth == 0 ? 1U : 2U;
			}
		}
		if (alias != null) {
			if (opcode == CApi.Opcode.LOAD) {
				uint stored = state[frame_offset + field];
				if (strict && stored != 1 && stored != 2) {
					throw new LlvmError.VERIFICATION ("coroutine scoped field read lacks initialized storage");
				}
				state[phi_offset + phi_positions.lookup ((void*) instruction)] = stored == 1 ? 1U : 0U;
			} else {
				var value = CApi.operand (instruction, 0);
				if (null_pointer (value)) {
					state[frame_offset + field] = 1;
				} else {
					var incoming = pointer (value);
					if (incoming == null || incoming.allocation != alias.allocation || incoming.owner != alias.owner || strict && (state[alias.allocation] != 2 || state[owner_offset + alias.owner] != 2)) {
						size_t length;
						throw new LlvmError.VERIFICATION ("coroutine scoped field store lacks its exact live allocation (caller=%s, field=%d, value=%s, allocation=%u, owner=%u, handle=%d)", CApi.value_name (function, out length), field, CApi.value_name (value, out length), state[alias.allocation], state[owner_offset + alias.owner], alias.owner);
					}
					state[frame_offset + field] = 2;
				}
			}
		}
		if (opcode == CApi.Opcode.STORE && frame_flags.contains (field)) {
			var value = CApi.operand (instruction, 0);
			if (number (value, 0)) {
				state[frame_offset + field] = 1;
			} else {
				if ((void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.ICMP || CApi.predicate (value) != CApi.IntPredicate.NE || !null_pointer (CApi.operand (value, 1))) {
					throw new LlvmError.VERIFICATION ("coroutine scoped liveness requires its exact pointer null test");
				}
				var incoming = pointer (CApi.operand (value, 0));
				if (incoming == null || incoming.allocation != frame_flags.lookup (field).allocation || incoming.owner != frame_flags.lookup (field).owner) {
					throw new LlvmError.VERIFICATION ("coroutine scoped liveness changed its captured allocation");
				}
				state[frame_offset + field] = state[incoming.allocation] == 1 || state[owner_offset + incoming.owner] == 1 ? 1U : 3U;
			}
		}
	}

	private void frame_boundary(CApi.ValueRef end, uint[] state) throws LlvmError {
		if (coroutine == null || CApi.opcode (end) != CApi.Opcode.RET || (void*) CApi.block_parent (CApi.instruction_parent (end)) == (void*) coroutine.destroy) {
			return;
		}
		for (int a = 0; a < allocations.length; a++) {
			if ((state[a] & 2) == 0) {
				continue;
			}
			bool retained = false;
			foreach (int flag in frame_flags.get_keys ()) {
				if (frame_flags.lookup (flag).allocation == a && state[owner_offset + frame_flags.lookup (flag).owner] == 2 && state[frame_offset + flag] != 1 && state[frame_offset + flag - 1] == 2) {
					retained = true;
				}
			}
			foreach (var held in held_tasks) {
				if ((state[held_offset + held.ordinal] & 10) == 0) {
					continue;
				}
				foreach (var owner in held.owners.get_values ()) {
					if (owner.allocation == a && state[owner_offset + owner.owner] == 2) {
						retained = true;
					}
				}
			}
			if (result_shape != null) {
				for (uint f = 0; f < result_owners.length; f++) {
					var owner = result_owners[f];
					if (owner != null && owner.allocation == a && state[result_offset + f] == 2 && state[owner_offset + owner.owner] == 2 && state[result_live_offset] == 2) {
						var complete = CApi.first_instruction (CApi.instruction_parent (end));
						CApi.ValueRef previous = (CApi.ValueRef) null;
						for (; (void*) complete != null && (void*) complete != (void*) end; complete = CApi.next_instruction (complete)) {
							previous = complete;
						}
						if ((void*) previous == null || CApi.opcode (previous) != CApi.Opcode.CALL || callee (previous) != "astra_async_complete" || !number (CApi.operand (previous, 1), 5)) {
							throw new LlvmError.VERIFICATION ("scoped result retention requires actual successful completion");
						}
						retained = true;
					}
				}
			}
			if (deferred_error != null && state[deferred_offset] == 2) {
				foreach (var slot in deferred_error.slots) {
					if (slot.allocation == a && state[owner_offset + slot.owner] == 2) {
						CApi.ValueRef complete = (CApi.ValueRef) null;
						for (var prior = CApi.first_instruction (CApi.instruction_parent (end)); (void*) prior != null && (void*) prior != (void*) end; prior = CApi.next_instruction (prior)) {
							complete = prior;
						}
						if ((void*) complete == null || CApi.opcode (complete) != CApi.Opcode.CALL || callee (complete) != "astra_async_complete" || !number (CApi.operand (complete, 1), 6)) {
							throw new LlvmError.VERIFICATION ("deferred scoped exception retention requires actual error completion");
						}
						retained = true;
					}
				}
			}
			foreach (var heap in storage.heaps) {
				uint h = 0;
				assert (storage.heaps.find (heap, out h));
				if (state[heap_offset + (int) h] != 2 || !storage.retained_heap (heap, state, frame_offset, heap_choice_offset)) {
					continue;
				}
				foreach (var field in storage.slots) {
					if ((void*) field.root == (void*) heap.root && field.allocation == a && field.owner >= 0 && state[owner_offset + field.owner] == 2) {
						retained = true;
					}
				}
			}
			if (!retained) {
				size_t length;
				var detail = new StringBuilder ();
				foreach (int flag in frame_flags.get_keys ()) {
					var owner = frame_flags.lookup (flag);
					if (owner.allocation == a) {
						detail.append_printf (" field%d=%u/live=%u/owner%d=%u", flag - 1, state[frame_offset + flag - 1], state[frame_offset + flag], owner.owner, state[owner_offset + owner.owner]);
					}
				}
				throw new LlvmError.VERIFICATION ("coroutine return lost its exact retained scoped owner (caller=%s, allocation=%d, state=%u)%s", CApi.value_name (function, out length), a, state[a], detail.str);
			}
		}
	}

	private void use(CApi.ValueRef instruction, uint[] state) throws LlvmError {
		held_use (instruction, state);
		var opcode = CApi.opcode (instruction);
		if (opcode == CApi.Opcode.PHI || opcode == CApi.Opcode.SELECT) {
			return;
		}
		if (opcode == CApi.Opcode.CALL && consuming != null) {
			var contract = consuming.lookup ((void*) CApi.called_value (instruction));
			if (contract != null) {
				if (contract.fields != null && contract.fields.scoped_receiver && pointer (CApi.operand (instruction, 0)) == null) {
					throw new LlvmError.VERIFICATION ("scoped lifecycle receiver requires its actual tracked allocation");
				}
				for (int p = 0; p < contract.count; p++) {
					if (contract.fields != null && !contract.fields.constructor) {
						continue;
					}
					var value = CApi.operand (instruction, contract.physical_position (p));
					if (pointer (value) == null && !null_pointer (selected_value (value, state)) && !null_record_input (value, new HashTable<void*, bool> (direct_hash, direct_equal))) {
						throw new LlvmError.VERIFICATION (contract.aggregate_fields != 0 ? "scoped record call requires an actual tracked allocation or proven null input" : "scoped Class call requires an actual tracked allocation or proven null input");
					}
				}
			}
		}
		var consumed = new HashTable<int, bool> (direct_hash, direct_equal);
		var borrowed = new HashTable<int, bool> (direct_hash, direct_equal);
		for (uint i = 0; i < CApi.operand_count (instruction); i++) {
			var operand = CApi.operand (instruction, i);
			if (opcode == CApi.Opcode.CALL && i < CApi.argument_count (instruction) && loans.find ((void*) operand) && class_callees != null) {
				var target = class_callees.lookup ((void*) CApi.called_value (instruction));
				if (target != null && target.class_position (i)) {
					throw new LlvmError.VERIFICATION ("scoped context cannot substitute for a Class loan");
				}
			}
			var alias = pointer (operand);
			if (alias == null && opcode == CApi.Opcode.CALL && i < CApi.argument_count (instruction) && class_callees != null) {
				var target = class_callees.lookup ((void*) CApi.called_value (instruction));
				if (target != null && target.class_position (i)) {
					var caller = class_callees.lookup ((void*) function);
					var receiver = borrows == null ? null : borrows.lookup ((void*) function);
					if (!(null_pointer (selected_value (operand, state)) && target.accepts_null (instruction, i)) && !(caller != null && caller.forwards (operand, target, instruction, i)) && !(receiver != null && receiver.forwards_loan (operand, target, instruction, i))) {
						size_t length;
						throw new LlvmError.VERIFICATION ("scoped Class loan requires an actual tracked allocation or matching borrowed parameter (caller=%s, value=%s)", CApi.value_name (function, out length), CApi.value_name (operand, out length));
					}
				}
			}
			if (alias == null && opcode == CApi.Opcode.CALL && i == 0 && borrows != null) {
				var target = borrows.lookup ((void*) CApi.called_value (instruction));
				if (target != null && target.scoped_receiver) {
					var caller = borrows.lookup ((void*) function);
					var formal = class_callees == null ? null : class_callees.lookup ((void*) function);
					if (!(caller != null && caller.forwards_receiver (operand, target, instruction, i)) && !(formal != null && formal.forwards_receiver (operand, target, instruction, i)) && !carrier_receiver (instruction, target, state)) {
						throw new LlvmError.VERIFICATION ("scoped receiver requires its exact allocation or borrowed origin");
					}
				}
			}
			if (alias == null) {
				continue;
			}
			if (opcode == CApi.Opcode.CALL && captured_tasks != null && captured_tasks.contains ((void*) instruction) && (null_pointer (selected_value (operand, state)) || state[alias.allocation] == 1 && state[owner_offset + alias.owner] == 1)) {
				continue;
			}
			if (opcode == CApi.Opcode.CALL && i < CApi.argument_count (instruction) && absent_graph_call (instruction, i, state)) {
				continue;
			}
			if (coroutine != null && null_pointer (selected_value (operand, state))) {
				continue;
			}
			if ((opcode == CApi.Opcode.ICMP || opcode == CApi.Opcode.RET) && null_pointer (selected_value (operand, state))) {
				continue;
			}
			if (opcode == CApi.Opcode.RET && owned_inputs != null && owned_inputs.error_count != 0 && alias.root) {
				var heap = storage.heap_owner (operand);
				if (heap != null && storage.is_heap_root (operand, heap) && heap.exception_shape != null && (heap.exception_shape.same (owned_inputs.error_shape) || heap.empty_base_shape != null && heap.empty_base_shape.same (owned_inputs.error_shape))) {
					continue;
				}
			}
			if (opcode == CApi.Opcode.RET && fresh_result != null) {
				if (fresh_return (operand, alias, state)) {
					continue;
				}
				throw new LlvmError.VERIFICATION ("fresh scoped return lost its exact live allocation and context origin");
			}
			if (opcode == CApi.Opcode.STORE && i == 0 && alias.root && state[owner_offset + alias.owner] != 2 && storage.publication_slot (instruction, storage.lookup (CApi.operand (instruction, 1))) != null) {
				throw new LlvmError.VERIFICATION ("scoped owner storage requires one exact allocation transfer from its original live input");
			}
			uint lifetime = state[alias.allocation];
			if ((lifetime & 4) != 0 || opcode != CApi.Opcode.ICMP && lifetime != 2) {
				size_t length;
				throw new LlvmError.VERIFICATION ("emitted scoped allocation use lacks its exact live owner (caller=%s, value=%s, instruction=%s, opcode=%d, state=%u)", CApi.value_name (function, out length), CApi.value_name (operand, out length), CApi.value_name (instruction, out length), (int) opcode, lifetime);
			}
			uint owner = state[owner_offset + alias.owner];
			if ((owner & 4) != 0 || opcode != CApi.Opcode.ICMP && owner != 2) {
				size_t name_length;
				throw new LlvmError.VERIFICATION ("emitted scoped pointer lacks its exact live owner handle (caller=%s, value=%s, instruction=%s, opcode=%d, allocation=%d, owner=%d, allocation-state=%u, owner-state=%u)", CApi.value_name (function, out name_length), CApi.value_name (operand, out name_length), CApi.value_name (instruction, out name_length), (int) opcode, alias.allocation, alias.owner, state[alias.allocation], state[owner_offset + alias.owner]);
			}
			if (task_allocations.contains (alias.allocation)) {
				if (opcode == CApi.Opcode.ICMP) {
					continue;
				}
				if (opcode == CApi.Opcode.CALL && alias.root) {
					bool retires;
					if (LlvmScopedTaskFrame.operation (instruction, i, out retires)) {
						owner_transport (operand, state);
						continue;
					}
				}
				throw new LlvmError.VERIFICATION ("scoped task pointer escaped its exact task observation operations");
			}
			if (opcode == CApi.Opcode.CALL && capture_use (instruction, i, alias, state)) {
				if (consumed.contains (alias.allocation) || borrowed.contains (alias.allocation)) {
					throw new LlvmError.VERIFICATION ("scoped task capture aliases another call input");
				}
				consumed.insert (alias.allocation, true);
				continue;
			}
			if (result_shape != null && opcode == CApi.Opcode.STORE && i == 0 && alias.root && result_store (instruction)) {
				continue;
			}
			if (result_shape != null && opcode == CApi.Opcode.INSERT_VALUE && i == 1 && alias.root) {
				bool publication = false;
				foreach (void* address in result_stores) {
					if (result_shape.publication_chain (instruction, (CApi.ValueRef) address)) {
						publication = true;
					}
				}
				if (publication) {
					continue;
				}
			}
			if (opcode == CApi.Opcode.RET && owned_inputs != null && owned_inputs.returned_slot == alias.allocation && alias.root) {
				continue;
			}
			if (opcode == CApi.Opcode.INSERT_VALUE && i == 1 && alias.root && owned_inputs != null && owned_inputs.publishes (instruction, alias.allocation)) {
				continue;
			}
			if (opcode == CApi.Opcode.ICMP || opcode == CApi.Opcode.GEP && i == 0) {
				continue;
			}
			if (opcode == CApi.Opcode.LOAD && i == 0 && (CApi.type_kind (CApi.type_of (instruction)) != CApi.TypeKind.POINTER || storage.exception_header (operand) || storage.lookup (operand) != null)) {
				continue;
			}
			if (opcode == CApi.Opcode.STORE && i == 1 && pointer (CApi.operand (instruction, 0)) == null) {
				continue;
			}
			if (opcode == CApi.Opcode.CALL && i == 2 && alias.root && deferred_publication (instruction, operand)) {
				owner_transport (operand, state);
				continue;
			}
			if (opcode == CApi.Opcode.STORE && i == 0 && alias.root && success_store (instruction) && alias.allocation == owned_inputs.returned_slot) {
				continue;
			}
			if (opcode == CApi.Opcode.STORE && i == 0 && alias.root && frame_values.lookup (frame_field (CApi.operand (instruction, 1))) == alias) {
				continue;
			}
			if (opcode == CApi.Opcode.STORE && i == 0 && alias.root) {
				var slot = storage.publication_slot (instruction, storage.lookup (CApi.operand (instruction, 1)));
				if (slot != null) {
					continue;
				}
			}
			if (opcode == CApi.Opcode.CALL && i == 0 && alias.root && !contextual_allocations[alias.allocation] && LlvmScopedHeapCarrier.free_call (instruction)) {
				owner_transport (operand, state);
				continue;
			}
			if (opcode == CApi.Opcode.CALL && i == 0 && callee (instruction) == "astra_context17_release_origin_checked" && CApi.argument_count (instruction) == 2 && alias.root) {
				provider (instruction, "release");
				if (!contextual_allocations[alias.allocation]) {
					throw new LlvmError.VERIFICATION ("default heap graph cannot retire through a context operation");
				}
				if ((void*) CApi.operand (instruction, 1) != tags[alias.allocation]) {
					throw new LlvmError.VERIFICATION ("scoped retirement lost its exact allocation tag");
				}
				owner_transport (operand, state);
				continue;
			}
			if (opcode == CApi.Opcode.CALL && i == 0 && alias.root && consuming != null) {
				var heap = storage.heap_owner (operand);
				if (heap != null && heap.exception_shape != null && heap.exception_shape.destructor_call (instruction, operand)) {
					var contract = consuming.lookup ((void*) heap.exception_shape.destructor_target ());
					if (contract == null || contract.fields == null || contract.fields.constructor || (void*) contract.fields.layout != (void*) heap.layout) {
						throw new LlvmError.VERIFICATION ("scoped exception dynamic retirement lost its exact field body");
					}
					contract.verify ();
					if (heap.returned_error) {
						heap.exception_shape.verify_inherited (operand);
					} else {
						heap.exception_shape.verify (operand, instruction);
					} owner_transport (operand, state);
					if (consumed.contains (alias.allocation)) {
						throw new LlvmError.VERIFICATION ("scoped call aliases one allocation through consuming and borrowed inputs");
					}
					borrowed.insert (alias.allocation, true);
					continue;
				}
			}
			if (opcode == CApi.Opcode.CALL && alias.root && consuming != null) {
				var contract = consuming.lookup ((void*) CApi.called_value (instruction));
				if (contract != null && contract.accepts (instruction, i, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation], (checked_calls.contains ((void*) instruction) || error_calls.contains ((void*) instruction) || empty_error_call (instruction, contract)))) {
					owner_transport (operand, state);
					for (int g = 0; g < contract.count; g++) {
						if (contract.input_graph (g) != null && contract.physical_position (g) == i) {
							verify_graph (operand, contract.input_graph (g), state, new HashTable<int, bool> (direct_hash, direct_equal));
						}
					}
					if (consumed.contains (alias.allocation)) {
						throw new LlvmError.VERIFICATION ("owned scoped call duplicates one allocation across consuming inputs");
					}
					if (borrowed.contains (alias.allocation)) {
						throw new LlvmError.VERIFICATION ("scoped call aliases one allocation through both consuming and borrowed inputs");
					}
					consumed.insert (alias.allocation, true);
					continue;
				}
			}
			if (opcode == CApi.Opcode.CALL && alias.root && consuming != null) {
				var contract = consuming.lookup ((void*) CApi.called_value (instruction));
				if (contract != null && contract.fields != null && contract.fields.accepts_receiver (i, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation])) {
					contract.field_call (instruction);
					owner_transport (operand, state);
					if (consumed.contains (alias.allocation)) {
						throw new LlvmError.VERIFICATION ("scoped call aliases one allocation through both consuming and borrowed inputs");
					}
					borrowed.insert (alias.allocation, true);
					continue;
				}
			}
			if (opcode == CApi.Opcode.CALL && alias.root && class_callees != null) {
				var target = class_callees.lookup ((void*) CApi.called_value (instruction));
				if (target != null && target.accepts_scope (instruction, i, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation])) {
					if (consumed.contains (alias.allocation)) {
						throw new LlvmError.VERIFICATION ("scoped call aliases one allocation through both consuming and borrowed inputs");
					}
					borrowed.insert (alias.allocation, true);
					continue;
				}
			}
			if (opcode == CApi.Opcode.CALL && alias.root && borrows != null) {
				var contract = borrows.lookup ((void*) CApi.called_value (instruction));
				if (contract != null && contract.accepts_scope (instruction, i, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation])) {
					carrier_receiver (instruction, contract, state);
					owner_transport (operand, state);
					if (consumed.contains (alias.allocation)) {
						throw new LlvmError.VERIFICATION ("scoped call aliases one allocation through both consuming and borrowed inputs");
					}
					borrowed.insert (alias.allocation, true);
					continue;
				}
			}
			size_t length;
			throw new LlvmError.VERIFICATION ("emitted scoped pointer transport requires its exact ownership effect (caller=%s, value=%s, instruction=%s, opcode=%d, callee=%s)", CApi.value_name (function, out length), CApi.value_name (operand, out length), CApi.value_name (instruction, out length), (int) opcode, opcode == CApi.Opcode.CALL ? callee (instruction) : "");
		}
	}

	private LlvmScopedOwnerGraph? graph_obligation(int allocation) {
		var fresh = fresh_graphs.lookup (allocation);
		return fresh ?? (owned_inputs == null ? null : owned_inputs.input_graph (allocation));
	}

	private bool formal_graph(CApi.ValueRef value, LlvmScopedOwnerGraph graph, uint[] state, bool consume = false) throws LlvmError {
		var alias = pointer (value);
		var original = alias == null ? null : graph_obligation (alias.allocation);
		if (original == null) {
			return false;
		}
		if (!alias.root || (void*) original.layout != (void*) graph.layout || state[graph_offset + alias.allocation] != 2) {
			throw new LlvmError.VERIFICATION ("scoped graph transfer lost its exact live formal obligation");
		}
		if (consume) {
			state[graph_offset + alias.allocation] = 4;
		}
		return true;
	}

	private void verify_graph(CApi.ValueRef value, LlvmScopedOwnerGraph graph, uint[] state, HashTable<int, bool> seen) throws LlvmError {
		if (formal_graph (value, graph, state)) {
			return;
		}
		var heap = storage.heap_owner (value);
		if (heap == null || (void*) heap.layout != (void*) graph.layout) {
			throw new LlvmError.VERIFICATION ("scoped graph forwarding lost its exact physical carrier");
		}
		for (int f = 0; f < graph.members.length; f++) {
			var slot = storage.result_field (value, graph.members[f], graph.path (f));
			uint position = 0;
			if (slot == null || !storage.slots.find (slot, out position)) {
				throw new LlvmError.VERIFICATION ("scoped graph forwarding lost an original owned field");
			}
			uint status = state[storage_offset + (int) position];
			if (status == 8) {
				continue;
			}
			if (slot.allocation < 0 || status != 2 || state[slot.allocation] != 2 || state[owner_offset + slot.owner] != 2 || !graph.matches (f, (CApi.ValueRef) tags[slot.allocation], (CApi.ValueRef) sizes[slot.allocation], (CApi.ValueRef) alignments[slot.allocation])) {
				throw new LlvmError.VERIFICATION ("scoped graph forwarding requires every exact live child owner");
			}
			if (seen.contains (slot.allocation)) {
				throw new LlvmError.VERIFICATION ("scoped graph duplicates one allocation across its owned child graph");
			}
			seen.insert (slot.allocation, true);
			if (graph.children[f] != null) {
				verify_graph ((CApi.ValueRef) allocations[slot.allocation], graph.children[f], state, seen);
			}
		}
	}

	private void verify_result_contexts(CApi.ValueRef value, LlvmScopedOwnerGraph graph, uint[] state, HashTable<int, bool> seen) throws LlvmError {
		var root = pointer (value);
		if (root == null || !root.root || seen.contains (root.allocation)) {
			throw new LlvmError.VERIFICATION ("fresh scoped graph publication lost its distinct root allocation");
		}
		seen.insert (root.allocation, true);
		var dependencies = fresh_dependencies.lookup (root.allocation);
		if (dependencies != null) {
			foreach (void* dependency in dependencies) {
				if (!fresh_result.accepts_dependency ((CApi.ValueRef) dependency)) {
					throw new LlvmError.VERIFICATION ("fresh scoped graph publication omits a descendant context");
				}
			}
		} else if (scoped_allocations[root.allocation] && !fresh_result.accepts_dependency ((CApi.ValueRef) contexts[root.allocation])) {
			throw new LlvmError.VERIFICATION ("fresh scoped graph publication omits a descendant context");
		}
		if (fresh_graphs.contains (root.allocation)) {
			return;
		}
		for (int f = 0; f < graph.members.length; f++) {
			var slot = storage.result_field (value, graph.members[f], graph.path (f));
			uint position = 0;
			if (slot == null || !storage.slots.find (slot, out position)) {
				throw new LlvmError.VERIFICATION ("fresh scoped graph publication lost its original child slot");
			}
			if (state[storage_offset + (int) position] == 8) {
				continue;
			}
			if (slot.allocation < 0) {
				throw new LlvmError.VERIFICATION ("fresh scoped graph publication lost its child allocation");
			}
			if (graph.children[f] != null) {
				verify_result_contexts ((CApi.ValueRef) allocations[slot.allocation], graph.children[f], state, seen);
			} else if (scoped_allocations[slot.allocation] && !fresh_result.accepts_dependency ((CApi.ValueRef) contexts[slot.allocation])) {
				throw new LlvmError.VERIFICATION ("fresh scoped graph publication omits a descendant context");
			}
		}
	}

	private void consume_graph(CApi.ValueRef call, LlvmScopedOwnedInputs contract, uint[] state) throws LlvmError {
		consume_graph_value (CApi.operand (call, contract.graph_parameter), contract.owner_graph, state, new HashTable<int, bool> (direct_hash, direct_equal));
	}

	private void consume_graph_value(CApi.ValueRef value, LlvmScopedOwnerGraph graph, uint[] state, HashTable<int, bool> seen) throws LlvmError {
		if (formal_graph (value, graph, state, true)) {
			return;
		}
		var heap = storage.heap_owner (value);
		if (heap == null || (void*) heap.layout != (void*) graph.layout) {
			throw new LlvmError.VERIFICATION ("scoped graph consumption lost its original backing carrier");
		}
		uint index = 0;
		assert (storage.heaps.find (heap, out index));
		if (state[heap_offset + (int) index] == 1) {
			for (int f = 0; f < graph.members.length; f++) {
				var slot = storage.result_field (value, graph.members[f], graph.path (f));
				uint position = 0;
				if (slot == null || !storage.slots.find (slot, out position) || state[storage_offset + (int) position] != 8) {
					throw new LlvmError.VERIFICATION ("absent scoped graph retains an occupied child field");
				}
			}
			return;
		}
		for (int f = 0; f < graph.members.length; f++) {
			var slot = storage.result_field (value, graph.members[f], graph.path (f));
			uint position = 0;
			if (slot == null || !storage.slots.find (slot, out position)) {
				throw new LlvmError.VERIFICATION ("scoped graph consumption lost an original child field");
			}
			int field = storage_offset + (int) position;
			if (state[field] == 8) {
				continue;
			}
			if (slot.allocation < 0 || seen.contains (slot.allocation)) {
				throw new LlvmError.VERIFICATION ("scoped graph consumption lost its exact distinct child owner");
			}
			seen.insert (slot.allocation, true);
			if (graph.children[f] != null) {
				consume_graph_value ((CApi.ValueRef) allocations[slot.allocation], graph.children[f], state, seen);
			}
			state[slot.allocation] = 4;
			state[owner_offset + slot.owner] = 4;
			state[field] = 4;
		}
		state[heap_offset + (int) index] = 4;
	}

	private bool carrier_receiver(CApi.ValueRef call, LlvmScopedBorrowBinding contract, uint[] state) throws LlvmError {
		var root = storage.receiver_root (call, contract);
		if ((void*) root == null) {
			return false;
		}
		var heap = storage.heap_owner (CApi.operand (call, 0));
		if (heap != null && heap.empty_contract != null) {
			uint h = 0;
			assert (storage.heaps.find (heap, out h));
			if (state[empty_heap_offset + (int) h] != 2 && !(heap.empty_contract != null && !heap.empty_contract.empty_base && state[empty_heap_offset + (int) h] == 8)) {
				throw new LlvmError.VERIFICATION ("empty inherited receiver lacks its checked initialization");
			}
		}
		for (int s = 0; s < storage.slots.length; s++) {
			var slot = storage.slots[s];
			if ((void*) slot.root != (void*) root || !storage.current_variant (slot)) {
				continue;
			}
			uint status = state[storage_offset + s];
			if (status == 8) {
				continue;
			}
			if (slot.allocation < 0 || status != 2 || state[slot.allocation] != 2 || state[owner_offset + slot.owner] != 2) {
				throw new LlvmError.VERIFICATION ("scoped receiver field loan lacks its exact occupied live carrier");
			}
		}
		return true;
	}

	// A null PHI/select may discard a still-live allocation. Its null edge can
	// discharge the obligation only when actual incoming paths prove absence.
	private bool correlate_null(CApi.ValueRef instruction, uint[] state, GenericArray<LlvmScopedState> outputs) {
		var alias = pointer (instruction);
		var opcode = CApi.opcode (instruction);
		if (alias == null || !alias.root) {
			return false;
		}
		if (opcode == CApi.Opcode.EXTRACT_VALUE && consuming != null) {
			var call = CApi.operand (instruction, 0);
			if ((void*) CApi.is_instruction (call) != null && CApi.opcode (call) == CApi.Opcode.CALL) {
				var contract = consuming.lookup ((void*) CApi.called_value (call));
				if (contract != null) {
					int field = contract.extracted_field (instruction);
					if (field >= 0 && contract.result_slot (field) >= 0) {
						uint mask = null_lifetimes.lookup ((void*) CApi.operand (call, contract.physical_position (contract.result_slot (field))));
						if (mask != null_lifetimes.lookup ((void*) instruction)) {
							null_lifetimes.insert ((void*) instruction, mask);
							return true;
						}
					}
				}
			}
			return false;
		}
		if (opcode == CApi.Opcode.LOAD) {
			var slot = storage.lookup (CApi.operand (instruction, 0));
			if (slot != null) {
				uint mask = (void*) slot.store == null ? 1 : null_lifetimes.lookup ((void*) CApi.operand (slot.store, slot.source_position));
				if (mask != null_lifetimes.lookup ((void*) instruction)) {
					null_lifetimes.insert ((void*) instruction, mask);
					return true;
				}
			}
			return false;
		}
		if (opcode == CApi.Opcode.CALL && consuming != null) {
			var contract = consuming.lookup ((void*) CApi.called_value (instruction));
			if (contract != null && !contract.checked_success && contract.returned_parameter >= 0) {
				uint mask = null_lifetimes.lookup ((void*) CApi.operand (instruction, contract.returned_parameter));
				if (mask != null_lifetimes.lookup ((void*) instruction)) {
					null_lifetimes.insert ((void*) instruction, mask);
					return true;
				}
			}
			return false;
		}
		if (opcode != CApi.Opcode.PHI && opcode != CApi.Opcode.SELECT) {
			return false;
		}
		uint mask = null_lifetimes.lookup ((void*) instruction);
		uint count = opcode == CApi.Opcode.PHI ? CApi.incoming_count (instruction) : 2;
		for (uint i = 0; i < count; i++) {
			var value = opcode == CApi.Opcode.PHI ? CApi.incoming_value (instruction, i) : CApi.operand (instruction, i + 1);
			if (empty_join (value, new HashTable<void*, bool> (direct_hash, direct_equal))) {
				if (opcode == CApi.Opcode.SELECT) {
					mask |= state[alias.allocation];
				} else {
					void* predecessor = (void*) CApi.incoming_block (instruction, i);
					for (int b = 0; b < blocks.length; b++) {
						if (blocks[b] == predecessor) {
							mask |= outputs[b].values[alias.allocation];
						}
					}
				}
			} else {
				mask |= null_lifetimes.lookup ((void*) value);
			}
		}
		if (mask == null_lifetimes.lookup ((void*) instruction)) {
			return false;
		}
		null_lifetimes.insert ((void*) instruction, mask);
		return true;
	}

	private void checked_read(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		if (CApi.opcode (instruction) != CApi.Opcode.LOAD) {
			return;
		}
		var channel = checked_slots.lookup ((void*) CApi.operand (instruction, 0));
		if (channel == null) {
			return;
		}
		int flag = call_offset + channel.ordinal;
		if (strict && state[flag] != 4) {
			throw new LlvmError.VERIFICATION ("checked scoped success read lacks its observed successful target");
		}
		state[flag] = 16;
		if (channel.aggregate) {
			foreach (var field in channel.fields.get_values ()) {
				state[owner_offset + field.owner] = 2;
			}
		} else {
			state[owner_offset + channel.owner] = 2;
		}
	}

	private void checked_effect(CApi.ValueRef instruction, LlvmScopedOwnedInputs contract, uint[] state, bool strict) throws LlvmError {
		var channel = checked_calls.lookup ((void*) instruction);
		if (channel == null) {
			throw new LlvmError.VERIFICATION ("checked scoped call requires its exact caller success-slot transport");
		}
		int flag = call_offset + channel.ordinal;
		if (channel.aggregate) {
			checked_record_effect (instruction, contract, channel, state, strict);
			return;
		}
		if (strict && (state[flag] == 2 || state[flag] == 4 || (state[owner_offset + channel.owner] & 2) != 0)) {
			throw new LlvmError.VERIFICATION ("checked scoped call overwrites an unobserved or live result");
		}
		for (uint p = 0; p < CApi.argument_count (instruction); p++) {
			var alias = pointer (CApi.operand (instruction, p));
			if (alias != null && alias.root && contract.accepts (instruction, p, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation], true)) {
				state[owner_offset + alias.owner] = 4;
				if (p != contract.returned_parameter) {
					state[alias.allocation] = 4;
				}
			}
		}
		state[owner_offset + channel.owner] = 1;
		state[flag] = 2;
	}

	private void checked_record_effect(CApi.ValueRef call, LlvmScopedOwnedInputs contract, LlvmScopedCheckedCall channel, uint[] state, bool strict) throws LlvmError {
		int flag = call_offset + channel.ordinal;
		bool live = state[flag] == 2 || state[flag] == 4;
		foreach (var field in channel.fields.get_values ()) {
			live = live || (state[owner_offset + field.owner] & 2) != 0;
		}
		if (strict && live) {
			throw new LlvmError.VERIFICATION ("checked scoped record overwrites an unobserved or live result");
		}
		for (uint p = 0; p < CApi.argument_count (call); p++) {
			var alias = pointer (CApi.operand (call, p));
			if (alias == null || !alias.root || !contract.accepts (call, p, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation], true)) {
				continue;
			}
			state[owner_offset + alias.owner] = 4;
			int field = contract.result_field (p);
			if (field < 0) {
				state[alias.allocation] = 4;
			} else {
				var returned = channel.fields.lookup (field);
				if (returned == null || returned.allocation != alias.allocation) {
					throw new LlvmError.VERIFICATION ("checked scoped record lost its exact actual result allocation");
				}
				state[owner_offset + returned.owner] = 1;
			}
		}
		state[flag] = 2;
	}

	private bool checked_edge(CApi.ValueRef end, uint successor, uint[] state) {
		if (CApi.opcode (end) != CApi.Opcode.COND_BR || CApi.successor_count (end) != 2) {
			return true;
		}
		var condition = CApi.operand (end, 0);
		if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ && CApi.predicate (condition) != CApi.IntPredicate.NE) {
			return true;
		}
		var left = CApi.operand (condition, 0);
		var right = CApi.operand (condition, 1);
		var channel = null_pointer (left) ? checked_calls.lookup ((void*) right) : null_pointer (right) ? checked_calls.lookup ((void*) left) : null;
		if (channel == null) {
			return true;
		}
		bool success = (CApi.predicate (condition) == CApi.IntPredicate.EQ) == (successor == 0);
		int flag = call_offset + channel.ordinal;
		if (state[flag] == 2) {
			state[flag] = success ? 4U : 8U;
			if (!success) {
				if (channel.aggregate) {
					foreach (var field in channel.fields.get_values ()) {
						state[field.allocation] = 4;
						state[owner_offset + field.owner] = 4;
					}
				} else {
					state[channel.allocation] = 4;
					state[owner_offset + channel.owner] = 4;
				}
			}
			return true;
		}
		return success ? state[flag] == 4 || state[flag] == 16 : state[flag] == 8;
	}

	private static bool no_live_allocation(uint value) {
		return value != 0 && (value & ~5U) == 0;
	}

	private bool empty_error_call(CApi.ValueRef call, LlvmScopedOwnedInputs contract) throws LlvmError {
		if (contract.error_count == 0) {
			return false;
		}
		for (int f = 0; f < contract.error_count; f++) {
			if (!null_record_input (CApi.operand (call, contract.physical_position (contract.error_slot (f))), new HashTable<void*, bool> (direct_hash, direct_equal))) {
				return false;
			}
		}
		return contract.empty_error_call (call, true);
	}

	private void error_effect(CApi.ValueRef call, LlvmScopedOwnedInputs contract, uint[] state, bool strict) throws LlvmError {
		var channel = error_calls.lookup ((void*) call);
		if (channel == null) {
			if (!empty_error_call (call, contract)) {
				throw new LlvmError.VERIFICATION ("scoped exception call requires its exact caller payload transport");
			}
			for (uint p = 0; p < CApi.argument_count (call); p++) {
				var incoming = pointer (CApi.operand (call, p));
				if (incoming == null || !incoming.root || !contract.accepts (call, p, (CApi.ValueRef) tags[incoming.allocation], (CApi.ValueRef) counts[incoming.allocation], (CApi.ValueRef) sizes[incoming.allocation], (CApi.ValueRef) alignments[incoming.allocation], true)) {
					continue;
				}
				state[owner_offset + incoming.owner] = 4;
				if (!contract.checked_success || p != contract.returned_parameter && contract.result_field (p) < 0) {
					state[incoming.allocation] = 4;
				}
			}
			return;
		}
		int flag = error_offset + channel.ordinal;
		if (strict && state[flag] != 1 && state[flag] != 4 && state[flag] != 16) {
			throw new LlvmError.VERIFICATION ("scoped exception call overwrites an unobserved or live error");
		}
		channel.heap.exception_shape.verify_inherited (call);
		for (uint p = 0; p < CApi.argument_count (call); p++) {
			var incoming = pointer (CApi.operand (call, p));
			if (incoming == null || !incoming.root || !channel.contract.accepts (call, p, (CApi.ValueRef) tags[incoming.allocation], (CApi.ValueRef) counts[incoming.allocation], (CApi.ValueRef) sizes[incoming.allocation], (CApi.ValueRef) alignments[incoming.allocation], true)) {
				continue;
			}
			state[incoming.allocation] = 4;
			state[owner_offset + incoming.owner] = 4;
		}
		foreach (var slot in channel.slots) {
			uint s = 0;
			assert (storage.slots.find (slot, out s));
			state[slot.allocation] = 2;
			state[owner_offset + slot.owner] = 2;
			state[storage_offset + (int) s] = 2;
		}
		var success = checked_calls.lookup ((void*) call);
		if (success != null) {
			if (success.aggregate) {
				foreach (var field in success.fields.get_values ()) {
					state[field.allocation] = 2;
				}
			} else {
				state[success.allocation] = 2;
			}
		}
		state[flag] = 2;
	}

	private bool error_edge(CApi.ValueRef end, uint successor, uint[] state) {
		if (CApi.opcode (end) != CApi.Opcode.COND_BR || CApi.successor_count (end) != 2) {
			return true;
		}
		var condition = CApi.operand (end, 0);
		if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ && CApi.predicate (condition) != CApi.IntPredicate.NE) {
			return true;
		}
		var left = CApi.operand (condition, 0);
		var right = CApi.operand (condition, 1);
		var channel = null_pointer (left) ? error_calls.lookup ((void*) right) : null_pointer (right) ? error_calls.lookup ((void*) left) : null;
		if (channel == null) {
			return true;
		}
		bool success = (CApi.predicate (condition) == CApi.IntPredicate.EQ) == (successor == 0);
		int flag = error_offset + channel.ordinal;
		if (state[flag] != 2) {
			return success ? state[flag] == 4 : state[flag] == 8;
		}
		state[flag] = success ? 4U : 8U;
		var normal = checked_calls.lookup ((void*) channel.call);
		foreach (var slot in channel.slots) {
			uint s = 0;
			assert (storage.slots.find (slot, out s));
			state[slot.allocation] = !success || normal != null && normal.returns_allocation (slot.allocation) ? 2U : 4U;
			state[owner_offset + slot.owner] = success ? 4U : 2U;
			state[storage_offset + (int) s] = success ? 8U : 2U;
		}
		return true;
	}

	private bool success_store(CApi.ValueRef instruction) {
		return owned_inputs != null && owned_inputs.checked_success && CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) owned_inputs.success_slot ();
	}

	private void record_success_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		if (strict && state[success_offset] != 1) {
			throw new LlvmError.VERIFICATION ("checked scoped record success was published more than once");
		}
		for (int f = 0; f < owned_inputs.aggregate_fields; f++) {
			int allocation = owned_inputs.result_slot (f);
			if (allocation < 0) {
				continue;
			}
			var value = owned_inputs.publication (instruction, f);
			if (null_pointer (selected_value (value, state))) {
				if (strict && !no_live_allocation (state[allocation])) {
					throw new LlvmError.VERIFICATION ("checked scoped record null field retains its live input owner");
				}
				continue;
			}
			var alias = pointer (value);
			if (alias == null || !alias.root || alias.allocation != allocation) {
				if (strict) {
					throw new LlvmError.VERIFICATION ("checked scoped record success lost its exact input allocation");
				}
				state[success_offset] = 8;
				return;
			}
			if (strict && (state[allocation] != 2 || state[owner_offset + alias.owner] != 2)) {
				throw new LlvmError.VERIFICATION ("checked scoped record publication lacks its exact live owner");
			}
			state[owner_offset + alias.owner] = 4;
		}
		state[success_offset] = 2;
	}

	private void record_checked_return(CApi.ValueRef end, uint[] state) throws LlvmError {
		bool success = null_pointer (selected_value (CApi.operand (end, 0), state));
		if (success ? state[success_offset] != 2 : state[success_offset] != 1) {
			throw new LlvmError.VERIFICATION ("checked scoped record return lost its exact success/error publication");
		}
		for (int f = 0; f < owned_inputs.aggregate_fields; f++) {
			int allocation = owned_inputs.result_slot (f);
			if (allocation < 0) {
				continue;
			}
			if (!success && !no_live_allocation (state[allocation])) {
				throw new LlvmError.VERIFICATION ("checked scoped record error retains a live success input owner");
			}
			if (success && state[allocation] != 2 && !no_live_allocation (state[allocation])) {
				throw new LlvmError.VERIFICATION ("checked scoped record return lost its exact field lifetime");
			}
			if (success) {
				state[allocation] = 4;
			}
		}
	}

	private void success_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		if (!success_store (instruction)) {
			return;
		}
		if (owned_inputs.aggregate_fields != 0) {
			record_success_effect (instruction, state, strict);
			return;
		}
		int allocation = owned_inputs.returned_slot;
		var incoming = CApi.operand (instruction, 0);
		var alias = pointer (incoming);
		if (strict && state[success_offset] != 1) {
			throw new LlvmError.VERIFICATION ("checked scoped success output was published more than once");
		}
		if (null_pointer (selected_value (incoming, state))) {
			if (strict && !no_live_allocation (state[allocation])) {
				throw new LlvmError.VERIFICATION ("checked scoped null success retains its input owner");
			}
			state[success_offset] = 4;
			return;
		}
		if (alias == null || !alias.root || alias.allocation != allocation) {
			if (strict) {
				throw new LlvmError.VERIFICATION ("checked scoped success lost its exact input allocation");
			}
			state[success_offset] = 8;
			return;
		}
		if (strict && (state[allocation] != 2 || state[owner_offset + alias.owner] != 2)) {
			throw new LlvmError.VERIFICATION ("checked scoped success lacks its live input owner");
		}
		state[owner_offset + alias.owner] = 4;
		state[success_offset] = 2;
	}

	private void transfer_return(CApi.ValueRef end, uint[] state) throws LlvmError {
		if (fresh_result != null) {
			if (CApi.operand_count (end) != 1) {
				throw new LlvmError.VERIFICATION ("fresh scoped return requires one exact pointer result");
			}
			var value = CApi.operand (end, 0);
			if (null_pointer (selected_value (value, state))) {
				return;
			}
			var alias = pointer (value);
			if (!fresh_return (value, alias, state)) {
				throw new LlvmError.VERIFICATION ("fresh scoped return lost its exact live allocation and context origin");
			}
			if (fresh_result.graph != null) {
				verify_graph (value, fresh_result.graph, state, new HashTable<int, bool> (direct_hash, direct_equal));
				verify_result_contexts (value, fresh_result.graph, state, new HashTable<int, bool> (direct_hash, direct_equal));
				consume_graph_value (value, fresh_result.graph, state, new HashTable<int, bool> (direct_hash, direct_equal));
			}
			state[alias.allocation] = 4;
			state[owner_offset + alias.owner] = 4;
			return;
		}
		if (owned_inputs != null && owned_inputs.aggregate_fields != 0) {
			if (owned_inputs.checked_success) {
				if (owned_inputs.error_count != 0 && !null_pointer (selected_value (CApi.operand (end, 0), state))) {
					transfer_exception (end, state);
				}
				record_checked_return (end, state);
				return;
			}
			for (int f = 0; f < owned_inputs.aggregate_fields; f++) {
				int allocation = owned_inputs.result_slot (f);
				if (allocation < 0) {
					continue;
				}
				var value = owned_inputs.publication (end, f);
				if (null_pointer (selected_value (value, state))) {
					if (!no_live_allocation (state[allocation])) {
						throw new LlvmError.VERIFICATION ("scoped record null result retains its original live input allocation");
					}
					continue;
				}
				var alias = pointer (value);
				if (alias == null || !alias.root || alias.allocation != allocation || state[allocation] != 2 || state[owner_offset + alias.owner] != 2) {
					throw new LlvmError.VERIFICATION ("scoped record return lost its exact live input allocation");
				}
				state[allocation] = 4;
				state[owner_offset + alias.owner] = 4;
			}
			return;
		}
		if (coroutine == null && owned_inputs != null && owned_inputs.error_count != 0 && CApi.operand_count (end) == 1 && !null_pointer (selected_value (CApi.operand (end, 0), state))) {
			transfer_exception (end, state);
		}
		if (owned_inputs != null && owned_inputs.fields != null && owned_inputs.fields.publishes) {
			var fields = owned_inputs.fields;
			bool failure = fields.checked_constructor && CApi.operand_count (end) == 1 && !null_pointer (selected_value (CApi.operand (end, 0), state));
			for (int f = 0; f < fields.count; f++) {
				if (fields.empty_field (f)) {
					if (!fields.null_initialization (function, end, f, consuming)) {
						throw new LlvmError.VERIFICATION ("empty scoped field lacks its actual null initialization");
					}
					continue;
				}
				int allocation = owned_inputs.input_slot (fields.input (f));
				var slot = storage.field_slot (fields.path (f));
				uint position = 0;
				if (allocation < 0 || slot == null || !storage.slots.find (slot, out position) || slot.allocation != allocation) {
					throw new LlvmError.VERIFICATION ("scoped constructor return lost its exact live field transfer");
				}
				if (failure) {
					if (!no_live_allocation (state[allocation]) || (state[storage_offset + (int) position] & 2) != 0) {
						throw new LlvmError.VERIFICATION ("checked scoped constructor error retains an input or initialized field (input=%d, lifetime=%u, field=%u, count=%u)", allocation, state[allocation], state[storage_offset + (int) position], constructor_stack == null ? 0 : state[stack_offset]);
					}
					continue;
				}
				if (state[storage_offset + (int) position] != 2 || state[allocation] != 2 || state[owner_offset + slot.owner] != 2) {
					throw new LlvmError.VERIFICATION ("scoped constructor return lost its exact live field transfer");
				}
				if (owned_inputs.input_graph (allocation) != null) {
					if (state[graph_offset + allocation] != 2) {
						throw new LlvmError.VERIFICATION ("scoped constructor lost its delegated child graph");
					}
					state[graph_offset + allocation] = 4;
				}
				state[allocation] = 4;
				state[owner_offset + slot.owner] = 4;
			}
		}
		if (owned_inputs == null || owned_inputs.returned_slot < 0) {
			return;
		}
		int allocation = owned_inputs.returned_slot;
		var value = CApi.operand (end, 0);
		if (owned_inputs.checked_success) {
			if (null_pointer (selected_value (value, state))) {
				if (state[success_offset] == 2 && state[allocation] == 2) {
					state[allocation] = 4;
					state[success_offset] = 4;
					return;
				}
				if (state[success_offset] == 4 && no_live_allocation (state[allocation])) {
					return;
				}
				throw new LlvmError.VERIFICATION ("checked scoped normal return lost its exact success publication");
			}
			if (state[success_offset] != 1 || !no_live_allocation (state[allocation])) {
				throw new LlvmError.VERIFICATION ("checked scoped error return retains a success owner or publication (%u/%u)".printf (state[allocation], state[success_offset]));
			}
			return;
		}
		if (null_pointer (selected_value (value, state))) {
			if (state[allocation] == 1 || state[allocation] == 4) {
				return;
			}
			throw new LlvmError.VERIFICATION ("owned scoped return lost its exact live input allocation: null result retains the original owner");
		}
		var alias = pointer (value);
		if (alias == null || !alias.root || alias.allocation != allocation || state[allocation] != 2 || state[owner_offset + alias.owner] != 2) {
			throw new LlvmError.VERIFICATION ("owned scoped return lost its exact live input allocation");
		}
		state[allocation] = 4;
		state[owner_offset + alias.owner] = 4;
	}

	private void transfer_exception(CApi.ValueRef end, uint[] state) throws LlvmError {
		var value = CApi.operand (end, 0);
		var heap = storage.heap_owner (value);
		uint h = 0;
		if (heap == null || !storage.is_heap_root (value, heap) || heap.exception_shape == null || !(heap.exception_shape.same (owned_inputs.error_shape) || heap.empty_base_shape != null && heap.empty_base_shape.same (owned_inputs.error_shape)) || !storage.heaps.find (heap, out h) || state[heap_offset + (int) h] != 2) {
			throw new LlvmError.VERIFICATION ("scoped exception return requires its exact live heap carrier");
		}
		bool empty_payload = heap.empty_contract != null && (heap.empty_contract.empty_base || state[empty_heap_offset + (int) h] == 2);
		if (empty_payload) {
			heap.empty_contract.verify ();
			if (state[empty_heap_offset + (int) h] != 2) {
				throw new LlvmError.VERIFICATION ("empty exception return lacks its checked initialized carrier");
			}
			for (int a = 0; a < owned_inputs.count; a++) {
				if (!no_live_allocation (state[a])) {
					throw new LlvmError.VERIFICATION ("empty exception return retains an original scoped input");
				}
			}
		} else if (heap.returned_error) {
			owned_inputs.error_shape.verify_inherited (value);
		} else {
			owned_inputs.error_shape.verify (value, end);
		}
		if (!empty_payload) {
			for (int f = 0; f < owned_inputs.error_count; f++) {
				int allocation = owned_inputs.error_slot (f);
				var slot = storage.result_field (value, owned_inputs.error_member (f));
				uint s = 0;
				if (slot == null || slot.allocation != allocation || !storage.slots.find (slot, out s) || state[storage_offset + (int) s] != 2 || state[allocation] != 2 || state[owner_offset + slot.owner] != 2) {
					throw new LlvmError.VERIFICATION ("scoped exception return lost its exact live payload field");
				}
				state[allocation] = 4;
				state[owner_offset + slot.owner] = 4;
				state[storage_offset + (int) s] = 4;
			}
		}
		var root = pointer (value);
		if (root != null) {
			if (!root.root || state[root.allocation] != 2 || state[owner_offset + root.owner] != 2) {
				throw new LlvmError.VERIFICATION ("scoped exception publication lost its exact live backing owner");
			}
			state[root.allocation] = 4;
			state[owner_offset + root.owner] = 4;
		}
		state[heap_offset + (int) h] = 4;
	}

	private void mutate_fields(CApi.ValueRef call, LlvmScopedOwnedInputs contract, uint[] state, bool strict) throws LlvmError {
		contract.field_call (call);
		var fields = contract.fields;
		// Check every incoming owner before retiring any old field, including
		// distinctness across the complete original receiver graph.
		var inputs = new GenericArray<int> ();
		for (int f = 0; f < fields.count; f++) {
			var value = CApi.operand (call, (uint) fields.input (f) + 1);
			var incoming = pointer (value);
			if (null_pointer (value)) {
				continue;
			}
			if (incoming == null || !incoming.root || !contract.accepts (call, (uint) fields.input (f) + 1, (CApi.ValueRef) tags[incoming.allocation], (CApi.ValueRef) counts[incoming.allocation], (CApi.ValueRef) sizes[incoming.allocation], (CApi.ValueRef) alignments[incoming.allocation])) {
				throw new LlvmError.VERIFICATION ("scoped mutation lacks its exact incoming owner");
			}
			if (strict && (inputs.find (incoming.allocation) || state[incoming.allocation] != 2 || state[owner_offset + incoming.owner] != 2)) {
				throw new LlvmError.VERIFICATION ("scoped mutation requires distinct original live inputs");
			}
			inputs.add (incoming.allocation);
		}
		for (int f = 0; f < fields.count; f++) {
			var old = storage.call_slot (call, fields, f);
			if (old == null) {
				throw new LlvmError.VERIFICATION ("scoped mutation lost its actual receiver cell");
			}
			int index = storage_offset + old.ordinal;
			if (state[index] == 8) {
				continue;
			}
			if (strict && (old.allocation < 0 || inputs.find (old.allocation) || state[index] != 2 || state[old.allocation] != 2 || state[owner_offset + old.owner] != 2)) {
				throw new LlvmError.VERIFICATION ("scoped mutation lost its distinct live prior field");
			}
			if (old.allocation >= 0) {
				if (fields.graph (f) != null) {
					consume_graph_value ((CApi.ValueRef) allocations[old.allocation], fields.graph (f), state, new HashTable<int, bool> (direct_hash, direct_equal));
				}
				state[old.allocation] = 4;
				state[owner_offset + old.owner] = 4;
			}
			state[index] = 4;
		}
		for (int f = 0; f < fields.count; f++) {
			var value = CApi.operand (call, (uint) fields.input (f) + 1);
			var first = storage.call_slot (call, fields, f);
			var slot = storage.publication_slot (call, first);
			if (slot == null) {
				throw new LlvmError.VERIFICATION ("scoped mutation lost its original field publication");
			}
			storage.publish (slot, state, strict);
			if (null_pointer (value)) {
				state[storage_offset + slot.ordinal] = 8;
				continue;
			}
			var incoming = pointer (value);
			if (slot.allocation != incoming.allocation) {
				throw new LlvmError.VERIFICATION ("scoped mutation changed its published allocation");
			}
			state[owner_offset + incoming.owner] = 4;
			state[owner_offset + slot.owner] = 2;
			state[storage_offset + slot.ordinal] = 2;
		}
		var heap = storage.heap_owner (CApi.operand (call, 0));
		uint h = 0;
		if (heap != null && heap.empty_contract != null && !heap.empty_contract.empty_base && storage.heaps.find (heap, out h)) {
			if (strict && state[empty_heap_offset + (int) h] != 2 && state[empty_heap_offset + (int) h] != 8) {
				throw new LlvmError.VERIFICATION ("scoped error mutation lacks its actual initialized carrier");
			}
			bool filled = false;
			for (int f = 0; f < fields.count; f++) {
				var slot = storage.call_slot (call, fields, f);
				filled = filled || slot == null || state[storage_offset + slot.ordinal] != 8;
			}
			state[empty_heap_offset + (int) h] = filled ? 8U : 2U;
		}

	}

	private void field_call(CApi.ValueRef call, LlvmScopedOwnedInputs contract, uint[] state, bool strict, bool indirect = false) throws LlvmError {
		var fields = contract.fields;
		if (fields == null) {
			return;
		}
		if (fields.mutation) {
			mutate_fields (call, contract, state, strict);
			return;
		}
		if (!fields.constructor && CApi.argument_count (call) > 0) {
			var root = pointer (CApi.operand (call, 0));
			var graph = root == null ? null : fresh_graphs.lookup (root.allocation);
			if (graph != null && (void*) fields.layout == (void*) graph.layout) {
				if (indirect) {
					contract.verify ();
				} else {
					contract.field_call (call);
				} if (strict && state[graph_offset + root.allocation] != 2) {
					throw new LlvmError.VERIFICATION ("fresh scoped graph cleanup lost its exact live child obligation");
				}
				state[graph_offset + root.allocation] = 4;
			}
		}
		if (owned_inputs != null && !fields.constructor && CApi.argument_count (call) > 0) {
			var receiver = pointer (CApi.operand (call, 0));
			if (receiver != null && receiver.root) {
				var graph = owned_inputs.input_graph (receiver.allocation);
				if (graph != null && (void*) fields.layout == (void*) graph.layout) {
					contract.field_call (call);
					if (strict && state[graph_offset + receiver.allocation] != 2) {
						throw new LlvmError.VERIFICATION ("scoped graph cleanup lost its exact live child obligation");
					}
					state[graph_offset + receiver.allocation] = 4;
				}
			}
		}
		if (CApi.argument_count (call) == 0) {
			throw new LlvmError.VERIFICATION ("scoped field call lost its exact physical signature");
		}
		bool relevant = false;
		for (int f = 0; f < fields.count; f++) {
			relevant = relevant || storage.call_slot (call, fields, f) != null;
		}
		if (fields.constructor) {
			for (uint p = 1; p < CApi.argument_count (call); p++) {
				relevant = relevant || pointer (CApi.operand (call, p)) != null;
			}
		}
		if (!relevant) {
			return;
		}
		if (indirect) {
			contract.verify ();
		} else {
			contract.field_call (call);
		}
		for (int f = 0; f < fields.count; f++) {
			var slot = storage.call_slot (call, fields, f);
			if (slot == null) {
				continue;
			}
			uint position = 0;
			assert (storage.slots.find (slot, out position));
			int index = storage_offset + (int) position;
			if (slot.allocation < 0) {
				if (fields.constructor && (fields.empty_field (f) || null_pointer (CApi.operand (call, (uint) fields.input (f) + 1)))) {
					state[index] = 8;
					continue;
				}
				if (!fields.constructor && state[index] == 8) {
					continue;
				}
				throw new LlvmError.VERIFICATION ("empty scoped field lost its exact null initialization or retirement");
			}
			if (!fields.constructor) {
				if (state[index] == 8) {
					continue;
				}
				if (strict && (state[index] != 2 || !(state[slot.allocation] == 2 && state[owner_offset + slot.owner] == 2 || state[slot.allocation] == 1 && state[owner_offset + slot.owner] == 1))) {
					throw new LlvmError.VERIFICATION ("scoped field retirement lacks its exact occupied live carrier");
				}
				if (fields.graph (f) != null) {
					consume_graph_value ((CApi.ValueRef) allocations[slot.allocation], fields.graph (f), state, new HashTable<int, bool> (direct_hash, direct_equal));
				}
				state[slot.allocation] = 4;
				state[owner_offset + slot.owner] = 4;
				state[index] = 4;
			} else if ((void*) slot.store != (void*) call) {
				if (strict && (!null_pointer (CApi.operand (call, (uint) fields.input (f) + 1)) || state[index] == 0 || (state[index] & ~9U) != 0)) {
					throw new LlvmError.VERIFICATION ("scoped constructor overwrites an occupied carrier field");
				}
				state[index] = 8;
			}
		}
		if (!fields.constructor) {
			return;
		}
		for (uint p = 1; p < CApi.argument_count (call); p++) {
			var moved = pointer (CApi.operand (call, p));
			if (moved == null || !moved.root || !contract.accepts (call, p, (CApi.ValueRef) tags[moved.allocation], (CApi.ValueRef) counts[moved.allocation], (CApi.ValueRef) sizes[moved.allocation], (CApi.ValueRef) alignments[moved.allocation])) {
				continue;
			}
			state[owner_offset + moved.owner] = 4;
			int field = contract.stored_field (p);
			if (field < 0) {
				state[moved.allocation] = 4;
				continue;
			}
			var slot = storage.call_slot (call, fields, field);
			if (slot == null || slot.allocation != moved.allocation || (void*) slot.store != (void*) call) {
				throw new LlvmError.VERIFICATION ("scoped constructor lost its exact caller carrier loan");
			}
			uint position = 0;
			assert (storage.slots.find (slot, out position));
			int index = storage_offset + (int) position;
			if (strict && (state[index] == 0 || (state[index] & ~9U) != 0)) {
				throw new LlvmError.VERIFICATION ("scoped constructor overwrites an occupied carrier field");
			}
			state[index] = 2;
			state[owner_offset + slot.owner] = 2;
		}
	}

	private void constructor_error_edge(CApi.ValueRef end, uint successor, uint[] state, bool strict) throws LlvmError {
		if (consuming == null || CApi.opcode (end) != CApi.Opcode.COND_BR || CApi.successor_count (end) != 2) {
			return;
		}
		var condition = CApi.operand (end, 0);
		if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ && CApi.predicate (condition) != CApi.IntPredicate.NE) {
			return;
		}
		var left = CApi.operand (condition, 0), right = CApi.operand (condition, 1);
		var call = null_pointer (left) ? right : null_pointer (right) ? left : (CApi.ValueRef) null;
		if ((void*) CApi.is_instruction (call) == null || CApi.opcode (call) != CApi.Opcode.CALL || (void*) CApi.block_terminator (CApi.instruction_parent (call)) != (void*) end || (CApi.predicate (condition) == CApi.IntPredicate.EQ) == (successor == 0)) {
			return;
		}
		var contract = consuming.lookup ((void*) CApi.called_value (call));
		if (contract == null || contract.fields == null || !contract.fields.checked_constructor || contract.fields.count == 0) {
			return;
		}
		contract.field_call (call);
		var fields = contract.fields;
		for (int f = 0; f < fields.count; f++) {
			var slot = storage.call_slot (call, fields, f);
			uint position = 0;
			if (slot == null || !storage.slots.find (slot, out position)) {
				throw new LlvmError.VERIFICATION ("checked scoped constructor error lost its exact caller field");
			}
			int index = storage_offset + (int) position;
			if (slot.allocation < 0 && state[index] == 8) {
				continue;
			}
			if (slot.allocation < 0 || strict && (state[index] != 2 || state[slot.allocation] != 2 || state[owner_offset + slot.owner] != 2)) {
				throw new LlvmError.VERIFICATION ("checked scoped constructor error lost its transferred child obligation");
			}
			if (fields.graph (f) != null) {
				consume_graph_value ((CApi.ValueRef) allocations[slot.allocation], fields.graph (f), state, new HashTable<int, bool> (direct_hash, direct_equal));
			}
			state[slot.allocation] = 4;
			state[owner_offset + slot.owner] = 4;
			state[index] = 8;
		}
	}

	private void heap_effect(CApi.ValueRef instruction, uint[] state, bool strict) throws LlvmError {
		if (strict) {
			storage.verify_choice_use (instruction);
		}
		if (CApi.opcode (instruction) != CApi.Opcode.PHI && CApi.opcode (instruction) != CApi.Opcode.SELECT) {
			for (uint p = 0; p < CApi.operand_count (instruction); p++) {
				var heap = storage.heap_owner (CApi.operand (instruction, p));
				if (heap == null) {
					continue;
				}
				if ((CApi.opcode (instruction) == CApi.Opcode.ICMP || CApi.opcode (instruction) == CApi.Opcode.RET) && null_pointer (selected_value (CApi.operand (instruction, p), state))) {
					continue;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && p < CApi.argument_count (instruction) && absent_graph_call (instruction, p, state)) {
					continue;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && p == 0 && storage.checked_pointer_store (instruction)) {
					continue;
				}
				if (strict && CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.is_instruction (CApi.operand (instruction, p)) != null && CApi.opcode (CApi.operand (instruction, p)) == CApi.Opcode.SELECT && pointer (CApi.operand (instruction, p)) != null) {
					owner_transport (CApi.operand (instruction, p), state);
				}
				uint h = 0;
				assert (storage.heaps.find (heap, out h));
				if (CApi.opcode (instruction) == CApi.Opcode.RET && fresh_result != null && fresh_result.graph != null && (void*) heap.layout == (void*) fresh_result.graph.layout && state[heap_offset + (int) h] == 1) {
					var absent = pointer (CApi.operand (instruction, p));
					if (absent != null && absent.root && state[absent.allocation] == 1 && state[owner_offset + absent.owner] == 1 && fresh_return (CApi.operand (instruction, p), absent, state)) {
						continue;
					}
				}
				bool compared = CApi.opcode (instruction) == CApi.Opcode.ICMP && (CApi.predicate (instruction) == CApi.IntPredicate.EQ || CApi.predicate (instruction) == CApi.IntPredicate.NE) && ((void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) != null || (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 1)) != null);
				if (strict && (compared ? (state[heap_offset + (int) h] & ~3U) != 0 : state[heap_offset + (int) h] != 2)) {
					size_t length;
					throw new LlvmError.VERIFICATION ("heap carrier use lacks its exact live backing or nonnull allocation guard (function=%s, instruction=%s, opcode=%d, value=%s, state=%u)", CApi.value_name (function, out length), CApi.value_name (instruction, out length), (int) CApi.opcode (instruction), CApi.value_name (CApi.operand (instruction, p), out length), state[heap_offset + (int) h]);
				}
			}
		}
		for (int h = 0; h < storage.heaps.length; h++) {
			var heap = storage.heaps[h];
			if (!heap.observed_error && (void*) instruction == (void*) heap.allocation && (deferred_error == null || heap != deferred_error.heap)) {
				if (strict && (state[heap_offset + h] & 2) != 0) {
					throw new LlvmError.VERIFICATION ("heap carrier backing reacquired before retirement");
				}
				storage.invalidate_heap_origin (heap, state, heap_choice_offset);
				state[heap_offset + h] = heap.nullable ? 3U : 2U;
				state[empty_heap_offset + h] = 1;
				for (int s = 0; s < storage.slots.length; s++) {
					if ((void*) storage.slots[s].root == (void*) heap.root) {
						state[storage_offset + s] = 8;
					}
				}
			}
			if (CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.argument_count (instruction) > 0 && storage.is_heap_root (CApi.operand (instruction, 0), heap) && heap.release_call (instruction)) {
				if (strict && heap.empty_contract != null && state[empty_heap_offset + h] != 4) {
					throw new LlvmError.VERIFICATION ("empty inherited backing retired before its checked cleanup");
				}
				for (int s = 0; s < storage.slots.length; s++) {
					if ((void*) storage.slots[s].root == (void*) heap.root && strict && (state[storage_offset + s] & ~13U) != 0) {
						throw new LlvmError.VERIFICATION ("heap carrier retired before its owned field cleanup");
					}
				}
				state[heap_offset + h] = 4;
				var channel = error_calls.lookup ((void*) heap.root);
				if (channel != null) {
					state[error_offset + channel.ordinal] = 16;
				}
			}
		}
	}

	// Preserve field/allocation correlations across nullable backing alternatives.
	// Other facts still join monotonically within the same backing state.
	private string state_key(uint[] values) {
		var key = new StringBuilder ();
		storage.append_owner_state (key, values, storage_offset);
		for (int h = 0; h < host_errors.length; h++) {
			key.append_printf ("%u;", values[host_error_offset + h]);
		}
		for (int c = 0; c < storage.choice_count; c++) {
			key.append_printf ("%u;", values[heap_choice_offset + c]);
		}
		if (deferred_error != null) {
			key.append_printf ("%u;%u;", values[deferred_offset], values[deferred_empty_offset]);
		}
		if (result_shape != null) {
			key.append_printf ("%u;%u;", values[result_live_offset], values[result_discard_offset]);
			for (uint f = 0; f < result_owners.length; f++) {
				key.append_printf ("%u;", values[result_offset + f]);
			}
		}
		if (coroutine != null) {
			key.append_printf ("%u;", values[wait_offset]);
		}
		foreach (var task in held_tasks) {
			key.append_printf ("%u;%u;%u;", values[held_offset + task.ordinal], values[phase_offset + task.ordinal], values[observed_offset + task.ordinal]);
		}
		if (coroutine != null) {
			for (int f = 0; f < CApi.count_struct_element_types (coroutine.frame_type); f++) {
				key.append_printf ("%u;", values[frame_offset + f]);
			}
		}
		for (int h = 0; h < storage.heaps.length; h++) {
			if (storage.heaps[h].empty_base_shape != null) {
				key.append_printf ("%u;", values[empty_heap_offset + h]);
			}
			if (storage.heaps[h].nullable || storage.heaps[h].alias_nullable) {
				key.append_printf ("%u;", values[heap_offset + h]);
			}
		}
		for (int c = 0; c < checked_channels.length; c++) {
			key.append_printf ("%u;", values[call_offset + c]);
		}
		for (int c = 0; c < error_channels.length; c++) {
			key.append_printf ("%u;", values[error_offset + c]);
		}
		for (int p = 0; p < pointer_phis.length; p++) {
			key.append_printf ("%u;", values[phi_offset + p]);
		}
		if (constructor_stack != null) {
			for (int p = 0; p < constructor_stack.slots; p++) {
				key.append_printf ("%u;", values[stack_offset + p]);
			}
		}
		if (owned_inputs != null) {
			for (int p = 0; p < owned_inputs.count; p++) {
				if (owned_inputs.input_graph (p) != null) {
					key.append_printf ("%u;", values[graph_offset + p]);
				}
			}
		}
		foreach (int allocation in fresh_graphs.get_keys ()) {
			key.append_printf ("%u;", values[graph_offset + allocation]);
		}
		for (int p = 0; p < condition_phis.length; p++) {
			key.append_printf ("%u;", values[condition_offset + p]);
		}
		return key.str;
	}

	private void analyze() throws LlvmError {
		inventory ();
		if (allocations.length == 0 && inputs == null && !has_record_calls && !has_class_calls && result_shape == null && !(owned_inputs != null && owned_inputs.fields != null && owned_inputs.fields.publishes)) {
			return;
		}
		aliases ();
		owner_offset = allocations.length + loans.length;
		storage_offset = owner_offset + owner_count;
		heap_offset = storage_offset + storage.slots.length;
		empty_heap_offset = heap_offset + storage.heaps.length;
		success_offset = empty_heap_offset + storage.heaps.length;
		call_offset = success_offset + (owned_inputs != null && owned_inputs.checked_success ? 1 : 0);
		error_offset = call_offset + checked_channels.length;
		phi_offset = error_offset + error_channels.length;
		stack_offset = phi_offset + pointer_phis.length;
		graph_offset = stack_offset + (constructor_stack == null ? 0 : constructor_stack.slots);
		condition_offset = graph_offset + allocations.length;
		frame_offset = condition_offset + condition_phis.length;
		held_offset = frame_offset + (coroutine == null ? 0 : (int) CApi.count_struct_element_types (coroutine.frame_type));
		wait_offset = held_offset + held_tasks.length;
		phase_offset = wait_offset + (coroutine == null ? 0 : 1);
		observed_offset = phase_offset + held_tasks.length;
		result_offset = observed_offset + held_tasks.length;
		result_live_offset = result_offset + result_owners.length;
		result_discard_offset = result_live_offset + (result_shape == null ? 0 : 1);
		deferred_offset = result_discard_offset + (result_shape == null ? 0 : 1);
		deferred_empty_offset = deferred_offset + (deferred_error == null ? 0 : 1);
		heap_choice_offset = deferred_empty_offset + (deferred_error == null ? 0 : 1);
		host_error_offset = heap_choice_offset + (int) storage.choice_count;
		int count = host_error_offset + host_errors.length;
		var entries = new GenericArray<HashTable<string, LlvmScopedState>> ();
		var outputs = new GenericArray<LlvmScopedState> ();
		for (int b = 0; b < blocks.length; b++) {
			entries.add (new HashTable<string, LlvmScopedState> (str_hash, str_equal));
			outputs.add (new LlvmScopedState (count));
		}
		var initial = new LlvmScopedState (count);
		for (int a = 0; a < count; a++) {
			initial.values[a] = a >= phi_offset ? 0U : 1U;
		}
		if (owned_inputs != null) {
			for (int p = 0; p < owned_inputs.count; p++) {
				initial.values[p] = 2;
				initial.values[owner_offset + p] = 2;
			}
		}
		if (owned_inputs != null) {
			for (int p = 0; p < owned_inputs.count; p++) {
				initial.values[graph_offset + p] = owned_inputs.input_graph (p) == null ? 1U : 2U;
			}
		}
		for (int s = 0; s < storage.slots.length; s++) {
			if (storage.slots[s].entry_live) {
				initial.values[storage_offset + s] = 2;
			}
		}
		if (inputs != null) {
			for (int l = 0; l < loans.length; l++) {
				if (inputs.contains ((CApi.ValueRef) loans[l])) {
					initial.values[allocations.length + l] = 2;
				}
			}
		}
		if (coroutine != null) {
			for (int f = 0; f < CApi.count_struct_element_types (coroutine.frame_type); f++) {
				initial.values[frame_offset + f] = 1;
			}
			initial.values[wait_offset] = uint.MAX;
			for (int p = 0; p < owned_inputs.count; p++) {
				int position = (int) owned_inputs.physical_position (p);
				int owner = coroutine.captured_owner (position);
				initial.values[frame_offset + position + 1] = 2;
				initial.values[frame_offset + owner] = 2;
				initial.values[frame_offset + owner + 1] = 3;
			}
		}
		if (result_shape != null) {
			initial.values[result_live_offset] = 1;
			for (uint f = 0; f < result_owners.length; f++) {
				initial.values[result_offset + f] = 1;
			}
		}
		if (deferred_error != null) {
			initial.values[deferred_offset] = 1;
		}
		for (int c = 0; c < storage.choice_count; c++) {
			initial.values[heap_choice_offset + c] = uint.MAX;
		}
		storage.initialize_frame_origins (initial.values, heap_choice_offset);
		entries[0].insert (state_key (initial.values), initial);
		if (coroutine != null) {
			var cold_destroy = CApi.first_block (coroutine.destroy);
			for (int b = 0; b < blocks.length; b++) {
				if (blocks[b] == (void*) cold_destroy) {
					var cold = new LlvmScopedState (count);
					cold.values = initial.values.copy ();
					if (result_shape != null) {
						cold.values[result_discard_offset] = 2;
					}
					entries[b].insert (state_key (cold.values), cold);
				}
			}
		}
		for (int pass = 0; pass < 2; pass++) {
			bool changed = false;
			do {
				changed = false;
				for (int b = 0; b < blocks.length; b++) {
					foreach (var incoming in entries[b].get_values ()) {
						var block = (CApi.BasicBlockRef) blocks[b];
						var pending = new GenericArray<LlvmScopedWork> ();
						pending.add (new LlvmScopedWork (incoming.values.copy (), CApi.first_instruction (block)));
						for (int work = 0; work < pending.length; work++) {
							uint[] state = pending[work].values;
							storage.select_state (state, heap_choice_offset, storage_offset);
							for (var instruction = pending[work].start; (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
								if (!pending[work].prepared || (void*) instruction != (void*) pending[work].start) {
									host_error_fork (instruction, state, pending);
								}
								if ((CApi.opcode (instruction) == CApi.Opcode.CALL || CApi.opcode (instruction) == CApi.Opcode.SELECT) && phi_positions.contains ((void*) instruction)) {
									state[phi_offset + phi_positions.lookup ((void*) instruction)] = 0;
								}
								if (constructor_stack != null) {
									constructor_stack.effect (instruction, state, stack_offset, pass == 1);
								}
								storage.owner_read_effect (instruction, state, pass == 1);
								storage.heap_slot_effect (instruction, state, heap_choice_offset, pass == 1);
								storage.choice_select (instruction, CApi.opcode (instruction) == CApi.Opcode.SELECT ? known_condition (CApi.operand (instruction, 0), state) : -1, state, heap_choice_offset);
								heap_effect (instruction, state, pass == 1);
								if (pass == 0 && correlate_null (instruction, state, outputs)) {
									changed = true;
								}
								if (pass == 1) {
									storage.verify_owner_read_use (instruction);
									if (inputs != null) {
										inputs.verify_use (instruction, context_callees, task_frames);
									}
									use (instruction, state);
								}
								result_observation (instruction, state, pass == 1);
								frame_effect (instruction, state, pass == 1);
								held_effect (instruction, state, pass == 1);
								host_error_effect (instruction, state, pass == 1);
								result_effect (instruction, state, pass == 1);
								empty_error_effect (instruction, state, pass == 1);
								deferred_effect (instruction, state, pass == 1);
								checked_read (instruction, state, pass == 1);
								success_effect (instruction, state, pass == 1);
								if (CApi.opcode (instruction) == CApi.Opcode.LOAD || CApi.opcode (instruction) == CApi.Opcode.STORE) {
									bool load = CApi.opcode (instruction) == CApi.Opcode.LOAD;
									var cell_slot = storage.lookup (CApi.operand (instruction, load ? 0 : 1));
									var slot = load ? cell_slot : storage.publication_slot (instruction, cell_slot) ?? cell_slot;
									if (slot != null) {
										uint position = 0;
										assert (storage.slots.find (slot, out position));
										int index = storage_offset + (int) position;
										if (load) {
											if (pass == 1 && (slot.allocation < 0 ? state[index] != 8 : state[index] != 2 || state[slot.allocation] != 2 || state[owner_offset + slot.owner] != 2)) {
												throw new LlvmError.VERIFICATION ("scoped owner load lacks its exact occupied live storage");
											}
										} else if ((void*) slot.store == (void*) instruction) {
											storage.publish (slot, state, pass == 1);
											var moved = pointer (CApi.operand (instruction, 0));
											assert (moved != null);
											state[owner_offset + moved.owner] = 4;
											state[owner_offset + slot.owner] = 2;
											state[index] = 2;
										} else if (null_pointer (CApi.operand (instruction, 0))) {
											state[index] = 8;
										} else if (pass == 1) {
											throw new LlvmError.VERIFICATION ("scoped owner storage overwritten by an unproved pointer");
										}
									}
								}
								for (int l = 0; l < loans.length; l++) {
									if ((void*) instruction == loans[l]) {
										if (pass == 1 && (state[allocations.length + l] & 2) != 0) {
											throw new LlvmError.VERIFICATION ("emitted scoped loan reacquired before retirement");
										}
										state[allocations.length + l] = 2;
									}
								}
								var allocated = pointer (instruction);
								if (allocated != null && (void*) instruction == allocations[allocated.allocation] && (owned_inputs == null || allocated.allocation >= owned_inputs.count)) {
									if (pass == 1 && (state[allocated.allocation] & 2) != 0) {
										throw new LlvmError.VERIFICATION ("emitted scoped allocation reacquired before retirement");
									}
									storage.invalidate_owner_allocation (allocated.allocation, state);
									for (int l = 0; l < loans.length; l++) {
										if (contexts[allocated.allocation] == loans[l] && pass == 1 && state[allocations.length + l] != 2) {
											throw new LlvmError.VERIFICATION ("emitted scoped allocation lacks its exact live context");
										}
									}
									var dependencies = fresh_dependencies.lookup (allocated.allocation);
									if (dependencies != null) {
										foreach (void* dependency in dependencies) {
											for (int l = 0; l < loans.length; l++) {
												if (loans[l] == dependency && pass == 1 && state[allocations.length + l] != 2) {
													throw new LlvmError.VERIFICATION ("fresh scoped graph lacks a live descendant context");
												}
											}
										}
									}
									state[allocated.allocation] = 2;
									state[owner_offset + allocated.owner] = 2;
									if (fresh_graphs.contains (allocated.allocation)) {
										state[graph_offset + allocated.allocation] = 2;
									}
								}
								if (CApi.opcode (instruction) == CApi.Opcode.CALL) {
									string target = callee (instruction);
									for (uint p = 0; p < CApi.argument_count (instruction); p++) {
										var task = pointer (CApi.operand (instruction, p));
										if (task == null || !task.root || !task_allocations.contains (task.allocation)) {
											continue;
										}
										bool retires;
										if (LlvmScopedTaskFrame.operation (instruction, p, out retires) && retires) {
											state[task.allocation] = 4;
											state[owner_offset + task.owner] = 4;
										}
									}

									var contract = consuming == null ? null : consuming.lookup ((void*) CApi.called_value (instruction));
									bool indirect = false;
									if (contract == null && CApi.argument_count (instruction) == 1) {
										var heap = storage.heap_owner (CApi.operand (instruction, 0));
										if (heap != null && heap.exception_shape != null && heap.exception_shape.destructor_call (instruction, CApi.operand (instruction, 0))) {
											if (heap.empty_contract != null) {
												heap.empty_contract.verify ();
											} else if (heap.returned_error) {
												heap.exception_shape.verify_inherited (heap.root);
											} else {
												heap.exception_shape.verify (heap.root, instruction);
											} contract = heap.empty_contract == null ? consuming.lookup((void*) heap.exception_shape.destructor_target ()) : null;
											indirect = true;
										}
									}
									if (contract != null && contract.fields != null) {
										field_call (instruction, contract, state, pass == 1, indirect);
									} else if (contract != null && contract.error_count != 0) {
										if (contract.checked_success) {
											checked_effect (instruction, contract, state, pass == 1);
										}
										error_effect (instruction, contract, state, pass == 1);
									} else if (contract != null && contract.checked_success) {
										checked_effect (instruction, contract, state, pass == 1);
									} else if (contract != null) {
										for (uint p = 0; p < CApi.argument_count (instruction); p++) {
											var alias = pointer (CApi.operand (instruction, p));
											if (alias != null && alias.root && !absent_graph_call (instruction, p, state) && contract.accepts (instruction, p, (CApi.ValueRef) tags[alias.allocation], (CApi.ValueRef) counts[alias.allocation], (CApi.ValueRef) sizes[alias.allocation], (CApi.ValueRef) alignments[alias.allocation])) {
												state[owner_offset + alias.owner] = 4;
												int field = contract.result_field (p);
												if (field >= 0) {
													var channel = record_calls.lookup ((void*) instruction);
													var returned = channel == null ? null : channel.fields.lookup (field);
													if (returned == null || returned.allocation != alias.allocation) {
														throw new LlvmError.VERIFICATION ("scoped record call lost its actual result owner");
													}
													state[owner_offset + returned.owner] = 2;
												} else if (p != contract.returned_parameter) {
													if (contract.owner_graph != null) {
														consume_graph (instruction, contract, state);
													}
													state[alias.allocation] = 4;
												} else {
													var returned = pointer (instruction);
													if (returned == null || returned.allocation != alias.allocation) {
														throw new LlvmError.VERIFICATION ("forwarded call lost its actual result owner");
													}
													state[owner_offset + returned.owner] = 2;
												}
											}
										}
									}
									if (target == "astra_context17_release_origin_checked" && CApi.argument_count (instruction) == 2 || target == "free" && LlvmScopedHeapCarrier.free_call (instruction)) {
										var released = pointer (CApi.operand (instruction, 0));
										if (released != null) {
											if (pass == 1 && graph_obligation (released.allocation) != null && state[graph_offset + released.allocation] != 4) {
												throw new LlvmError.VERIFICATION ("scoped graph backing retired before its delegated child cleanup");
											}
											state[released.allocation] = 4;
											state[owner_offset + released.owner] = 4;
											for (int f = 0; f < storage.slots.length; f++) {
												if (storage.slots[f].allocation == released.allocation && storage.slots[f].owner == released.owner) {
													state[storage_offset + f] = 4;
												}
											}
										}
									}
									if (target == "astra_context17_destroy" && CApi.argument_count (instruction) == 1) {
										if (pass == 1) {
											provider (instruction, "destroy");
										}
										for (int a = 0; a < allocations.length; a++) {
											if (pass == 1 && (contexts[a] == (void*) CApi.operand (instruction, 0) || fresh_dependencies.contains (a) && fresh_dependencies.lookup (a).find ((void*) CApi.operand (instruction, 0))) && (state[a] & 2) != 0) {
												size_t name_length;
												throw new LlvmError.VERIFICATION ("emitted scoped context retired before its derived allocation (caller=%s, value=%s, allocation=%d, state=%u)", CApi.value_name (function, out name_length), CApi.value_name ((CApi.ValueRef) allocations[a], out name_length), a, state[a]);
											}
										}
										for (int l = 0; l < loans.length; l++) {
											if (loans[l] == (void*) CApi.operand (instruction, 0)) {
												if (pass == 1 && state[allocations.length + l] != 2) {
													throw new LlvmError.VERIFICATION ("emitted scoped context retirement lacks its exact live loan");
												}
												state[allocations.length + l] = 4;
											}
										}
									}
								}
							}
							var end = CApi.block_terminator (block);
							if (pass == 1) {
								frame_boundary (end, state);
							}
							result_return (end, state);
							if (pass == 1 && CApi.opcode (end) == CApi.Opcode.RET && (coroutine == null || (void*) CApi.block_parent (block) == (void*) coroutine.destroy)) {
								foreach (var channel in checked_channels) {
									uint flag = state[call_offset + channel.ordinal];
									if (flag != 1 && flag != 8 && flag != 16) {
										throw new LlvmError.VERIFICATION ("checked scoped return leaves an unobserved success channel");
									}
								}
								foreach (var channel in error_channels) {
									uint flag = state[error_offset + channel.ordinal];
									if (flag != 1 && flag != 4 && flag != 8 && flag != 16) {
										throw new LlvmError.VERIFICATION ("scoped exception return leaves an unobserved call outcome");
									}
								}
								foreach (var task in held_tasks) {
									if ((state[held_offset + task.ordinal] & 26) != 0) {
										throw new LlvmError.VERIFICATION ("emitted return retains an unobserved scoped captured task");
									}
								}
								transfer_return (end, state);
								if (owned_inputs != null) {
									for (int p = 0; p < owned_inputs.count; p++) {
										if (owned_inputs.input_graph (p) != null && (owned_inputs.graph_forwarding && owned_inputs.returned_slot == p ? state[graph_offset + p] != 2 : state[graph_offset + p] != 1 && state[graph_offset + p] != 4)) {
											throw new LlvmError.VERIFICATION ("scoped graph return retains or loses its exact child obligation");
										}
									}
								}
								foreach (int allocation in fresh_graphs.get_keys ()) {
									if (state[graph_offset + allocation] == 2) {
										throw new LlvmError.VERIFICATION ("emitted return retains an unretired fresh graph obligation");
									}
								}
								for (int a = 0; a < allocations.length; a++) {
									if ((state[a] & 2) != 0) {
										size_t name_length;
										throw new LlvmError.VERIFICATION ("%s (caller=%s, allocation=%s, ordinal=%d, lifetime=%u, original-owner=%u)", scoped_allocations[a] ? "emitted return retains an unretired scoped allocation" : "emitted return retains an unretired heap carrier", CApi.value_name (function, out name_length), CApi.value_name ((CApi.ValueRef) allocations[a], out name_length), a, state[a], state[owner_offset + a]);
									}
								}
								for (int l = 0; l < loans.length; l++) {
									if ((inputs == null || !inputs.contains ((CApi.ValueRef) loans[l])) && (state[allocations.length + l] & 2) != 0) {
										throw new LlvmError.VERIFICATION ("emitted return retains an unretired scoped context");
									}
								}
								for (int h = 0; h < storage.heaps.length; h++) {
									if ((state[heap_offset + h] & 2) != 0) {
										throw new LlvmError.VERIFICATION ("emitted return retains an unretired heap carrier");
									}
								}
							}
							if (pass == 0) {
								for (int a = 0; a < count; a++) {
									uint joined = outputs[b].values[a] | state[a];
									if (joined != outputs[b].values[a]) {
										outputs[b].values[a] = joined;
										changed = true;
									}
								}
							}
							var successors = coroutine == null ? new CApi.BasicBlockRef[CApi.successor_count (end)] : coroutine.lifetime_successors (block);
							if (coroutine == null) {
								for (uint s = 0; s < successors.length; s++) {
									successors[s] = CApi.successor (end, s);
								}
							}
							for (uint s = 0; s < successors.length; s++) {
								storage.select_state (state, heap_choice_offset, storage_offset);
								if (constructor_stack != null && !constructor_stack.edge (end, s, state, stack_offset)) {
									continue;
								}
								if (CApi.opcode (end) == CApi.Opcode.COND_BR && CApi.successor_count (end) == 2) {
									var condition = CApi.operand (end, 0);
									int known = known_condition (condition, state);
									if (known >= 0 && (known == 1) != (s == 0)) {
										continue;
									}
								}
								uint[] edge = state.copy ();
								storage.select_state (edge, heap_choice_offset, storage_offset);
								deferred_edge (end, s, edge);
								if (coroutine != null && CApi.opcode (end) == CApi.Opcode.COND_BR && CApi.successor_count (end) == 2) {
									var condition = CApi.operand (end, 0);
									if ((void*) CApi.is_instruction (condition) != null && CApi.opcode (condition) == CApi.Opcode.LOAD) {
										int flag = frame_field (CApi.operand (condition, 0));
										if (frame_flags.contains (flag)) {
											bool nullable = edge[frame_offset + flag] == 3;
											edge[frame_offset + flag] = s == 0 ? 2U : 1U;
											if (nullable && s == 1 && edge[frame_offset + flag - 1] == 2) {
												var owner = frame_flags.lookup (flag);
												int a = owner.allocation;
												edge[a] = frame_null_mask (owner);
												edge[owner_offset + owner.owner] = frame_null_mask (owner);
												edge[frame_offset + flag - 1] = 1;
											}
										}
									}
								}
								if (result_shape != null && (void*) CApi.block_parent (block) == (void*) coroutine.destroy && CApi.opcode (end) == CApi.Opcode.COND_BR && CApi.successor_count (end) == 2) {
									var condition = CApi.operand (end, 0);
									if ((void*) CApi.is_instruction (condition) != null && CApi.opcode (condition) == CApi.Opcode.AND && state[result_live_offset] == 2) {
										for (uint term = 0; term < 2; term++) {
											var tested = CApi.operand (condition, term);
											if ((void*) CApi.is_instruction (tested) != null && CApi.opcode (tested) == CApi.Opcode.ICMP && CApi.predicate (tested) == CApi.IntPredicate.NE && (void*) CApi.operand (tested, 0) == (void*) CApi.get_param (coroutine.destroy, 1) && number (CApi.operand (tested, 1), 0)) {
												if (s == 0 || known_condition (CApi.operand (condition, 1 - term), state) == 1) {
													edge[result_discard_offset] = s == 0 ? 2U : 1U;
												}
											}
										}
									}
								}
								bool possible = checked_edge (end, s, edge) && error_edge (end, s, edge);
								child_phase_edge (end, s, edge, pass == 1);
								held_edge (end, s, edge, pass == 1);
								constructor_error_edge (end, s, edge, pass == 1);
								if (CApi.opcode (end) == CApi.Opcode.COND_BR && CApi.successor_count (end) == 2) {
									var condition = CApi.operand (end, 0);
									if ((void*) CApi.is_instruction (condition) != null && CApi.opcode (condition) == CApi.Opcode.ICMP && (CApi.predicate (condition) == CApi.IntPredicate.EQ || CApi.predicate (condition) == CApi.IntPredicate.NE)) {
										var left = CApi.operand (condition, 0);
										var right = CApi.operand (condition, 1);
										var alias = null_pointer (left) ? pointer (right) : null_pointer (right) ? pointer (left) : null;
										var tested = null_pointer (left) ? right : null_pointer (right) ? left : (CApi.ValueRef) null;
										if ((void*) tested != null && constructor_results.contains ((void*) tested) && !(alias != null && task_allocations.contains (alias.allocation))) {
											edge[phi_offset + phi_positions.lookup ((void*) tested)] = (CApi.predicate (condition) == CApi.IntPredicate.EQ) == (s == 0) ? 1U : 2U;
										}
										var heap = null_pointer (left) ? storage.heap_owner (right) : null_pointer (right) ? storage.heap_owner (left) : null;
										if (heap != null && storage.is_heap_root (null_pointer (left) ? right : left, heap) && !storage.handle_alias (tested) && !(deferred_error != null && heap == deferred_error.heap && edge[deferred_offset] == 4)) {
											uint h = 0;
											assert (storage.heaps.find (heap, out h));
											uint selected = (CApi.predicate (condition) == CApi.IntPredicate.EQ) == (s == 0) ? 1U : 2U;
											edge[heap_offset + (int) h] &= selected;
											possible = possible && edge[heap_offset + (int) h] != 0;
										}
										// Checked admission selects either the original caller owner or null.
										// Use the proven alternative on this edge; an unknown selection
										// retains the complete live-allocation mask and cannot hide a leak.
										if (alias != null && alias.root && !null_pointer (selected_value (null_pointer (left) ? right : left, edge))) {
											bool empty = (CApi.predicate (condition) == CApi.IntPredicate.EQ) == (s == 0);
											if (empty) {
												uint mask = selected_null_lifetimes (null_pointer (left) ? right : left, edge);
												if ((edge[alias.allocation] & 2) != 0 && mask == 0) {
													possible = false;
												}
												edge[alias.allocation] = (edge[alias.allocation] & ~2U) | ((edge[alias.allocation] & 2) == 0 ? 0 : mask);
												edge[owner_offset + alias.owner] = (edge[owner_offset + alias.owner] & ~2U) | ((edge[owner_offset + alias.owner] & 2) == 0 ? 0 : mask);
												if (edge[alias.allocation] == 1 && edge[owner_offset + alias.owner] == 1) {
													for (int f = 0; f < storage.slots.length; f++) {
														if (storage.slots[f].allocation == alias.allocation && storage.slots[f].owner == alias.owner) {
															edge[storage_offset + f] = 8;
														}
													}
												}
											} else {
												edge[alias.allocation] &= ~1U;
												edge[owner_offset + alias.owner] &= ~1U;
												possible = edge[alias.allocation] != 0;
											}
										}
										if ((void*) tested != null && constructor_results.contains ((void*) tested) && alias != null && task_allocations.contains (alias.allocation)) {
											edge[phi_offset + phi_positions.lookup ((void*) tested)] = (CApi.predicate (condition) == CApi.IntPredicate.EQ) == (s == 0) ? 1U : 2U;
										}


									}
								}
								if (owned_inputs != null) {
									for (int p = 0; p < owned_inputs.count; p++) {
										if (owned_inputs.input_graph (p) != null && edge[p] == 1) {
											edge[graph_offset + p] = 1;
										}
									}
								}
								foreach (int allocation in fresh_graphs.get_keys ()) {
									if (edge[allocation] == 1) {
										edge[graph_offset + allocation] = 1;
									}
								}
								if (!possible) {
									continue;
								}
								void* next = (void*) successors[s];
								select_pointer_phis ((CApi.BasicBlockRef) next, block, edge);
								storage.choice_phi_edge ((CApi.BasicBlockRef) next, block, edge, heap_choice_offset);
								if (pass == 1) {
									storage.verify_heap_phi_edge ((CApi.BasicBlockRef) next, block, edge, heap_offset);
									continue;
								}
								for (int n = 0; n < blocks.length; n++) {
									if (blocks[n] != next) {
										continue;
									}
									var key = state_key (edge);
									var entry = entries[n].lookup (key);
									if (entry == null) {
										entry = new LlvmScopedState (count);
										entries[n].insert (key, entry);
										changed = true;
									}
									for (int a = 0; a < count; a++) {
										uint joined = entry.values[a] | edge[a];
										if (joined != entry.values[a]) {
											entry.values[a] = joined;
											changed = true;
										}
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
}
