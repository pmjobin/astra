// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.NativeAbi;
using Astra.Source;

namespace Astra.Backend.LLVM {
// A fresh result depends on one original borrowed context, rather than an
// owning input. Only physical LLVM identities and copied target shape survive.
internal class LlvmScopedFreshResult : Object {
	private CApi.ValueRef function;
	private CApi.TypeRef type;
	private uint parameters;
	internal uint context_position { get; private set; }
	internal CApi.ValueRef context;
	internal CApi.ValueRef tag;
	internal CApi.ValueRef size;
	internal CApi.ValueRef alignment;
	internal LlvmScopedOwnerGraph? graph { get; private set; }
	private GenericArray<uint> dependencies = new GenericArray<uint> ();
	internal uint dependency_count { get { return dependencies.length; } }
	internal uint dependency_position(int index) {
		return dependencies[index];
	}

	internal bool accepts_dependency(CApi.ValueRef value) {
		for (int d = 0; d < dependencies.length; d++) {
			if ((void*) value == (void*) CApi.get_param (function, dependencies[d])) {
				return true;
			}
		}
		return false;
	}

	private LlvmSumSequence? body;
	private LlvmNativeModuleBinding? imported_body;
	internal static int context_parameter(NativeFunction source, GenericArray<NativeClassPlan> classes) throws LlvmError {
		var signature = source.signature;
		var output = signature.heap_result;
		if (signature.receiver != null || signature.exception_plan != null || signature.struct_result != null || signature.struct_parameters.length != 0 || signature.object_result != null || signature.sum_result != null || signature.buffer_result != null || signature.buffer_parameters.length != 0 || output == null || !output.heap || signature.result == null || signature.result.abi_type.get_type () != typeof (NativeScalarAbiType) || signature.result.scalar_type != NativeScalarType.PTR) {
			return -1;
		}
		if (output.class_ordinal < 0 || output.class_ordinal >= classes.length) {
			throw new LlvmError.INVALID_INPUT ("fresh scoped result lost its native Class origin");
		}
		var owner = classes[output.class_ordinal];
		var policy = owner.allocation_policy;
		if (owner.name != output.class_name || !owner.allocation_policy_valid ()) {
			throw new LlvmError.INVALID_INPUT ("fresh scoped result changed its exact allocation policy");
		}
		if (policy == null || policy.kind != AllocationKind.CONTEXT || policy.context_mode != "scoped-affine" || owner.parent_ordinal >= 0 || owner.polymorphic || owner.concurrency_policy != null || owner.foreign_export != null || owner.lazy_caches.length != 0) {
			return -1;
		}
		// Descendant backing obligations are copied separately by from_native.
		// The root query below identifies only the outer allocation context.
		foreach (var parameter in signature.parameters) {
			var context = parameter.abi_type as NativeContextHandleType;
			if (context != null) {
				if (!context.valid () || context.mode != "scoped-affine" || context.cleanup != "astra_context17_destroy" || parameter.owns_resource || parameter.resource == null || parameter.resource.type_name != context.name || parameter.resource.cleanup_symbol != context.cleanup) {
					return -1;
				}
			} else if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type == NativeScalarType.PTR || parameter.object_origin != null || parameter.borrowed_class_ordinal >= 0 || parameter.resource != null) {
				return -1;
			}
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			if (!summary.complete || summary.has_exception || summary.store_count != 0 || summary.updated_inputs ().length != 0) {
				return -1;
			}
			foreach (var dependency in summary.equations.requirements (summary.result)) {
				if (!dependency.valid () || dependency.kind != RuntimeScopeOriginKind.CONTEXT_PARAMETER || dependency.ordinal >= signature.parameters.length || !(signature.parameters[dependency.ordinal].abi_type is NativeContextHandleType)) {
					return -1;
				}
			}
			var roots = summary.equations.requirements (summary.result, "", false);
			if (roots.length != 1 || !roots[0].valid () || roots[0].kind != RuntimeScopeOriginKind.CONTEXT_PARAMETER || roots[0].ordinal >= signature.parameters.length || !(signature.parameters[roots[0].ordinal].abi_type is NativeContextHandleType)) {
				return -1;
			}
			return roots[0].ordinal;
		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("fresh scoped result lifetime: %s", failure.message);
		}
	}

	internal static LlvmScopedFreshResult? from_native(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.TypeRef type, NativeFunction source, GenericArray<NativeClassPlan> classes, LlvmStructRegistry structs) throws LlvmError {
		int position = context_parameter (source, classes);
		if (position < 0) {
			return null;
		}
		var owner = classes[source.signature.heap_result.class_ordinal];
		var layout = structs.class_layout (owner.ordinal, owner.name);
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		var data = artifact.class_target.enum_target_data (artifact);
		var result = new LlvmScopedFreshResult ();
		result.function = function;
		result.type = type;
		result.parameters = CApi.count_params (function);
		result.context_position = (uint) position;
		result.context = CApi.get_param (function, position);
		result.tag = new LlvmPolicyAllocation (artifact).tag (owner.name, "object");
		result.size = CApi.const_int (CApi.int_type_in_context (artifact.context, 64), CApi.abi_size_of_type (data, layout), 0);
		result.alignment = CApi.const_int (CApi.int32_type_in_context (artifact.context), uint.max (CApi.abi_alignment_of_type (data, layout), owner.allocation_policy.alignment), 0);
		if (!LlvmScopedClassGraph.value_scope_free (owner, classes)) {
			result.graph = LlvmScopedOwnerGraph.from_native (artifact, owner, classes, structs);
			if (result.graph == null) {
				return null;
			}
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			foreach (var dependency in summary.equations.requirements (summary.result)) {
				result.dependencies.add ((uint) dependency.ordinal);
			}
		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("fresh scoped result dependencies: %s", failure.message);
		}
		return result;
	}

	internal void verify_signature() throws LlvmError {
		if ((void*) CApi.global_value_type (function) != (void*) type || CApi.count_params (function) != parameters || context_position >= parameters || (void*) CApi.get_param (function, context_position) != (void*) context || CApi.function_call_conv (function) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("fresh scoped result lost its exact physical signature/context");
		}
	}

	internal void attach_import(LlvmNativeModuleBinding binding) throws LlvmError {
		if (body != null || imported_body != null || CApi.count_basic_blocks (function) != 0) {
			throw new LlvmError.LOWERING ("scoped native declaration requires its original external body role");
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
			throw new LlvmError.LOWERING ("fresh scoped result requires one actual emitted body");
		}
		verify_signature ();
		body = new LlvmSumSequence (function, true);
	}

	internal void verify() throws LlvmError {
		verify_signature ();
		if (imported_body != null) {
			imported_body.verify ();
			return;
		}
		if (body == null) {
			throw new LlvmError.VERIFICATION ("fresh scoped result body is unsealed");
		}
		body.verify ();
	}

	internal void verify_call(CApi.ValueRef call) throws LlvmError {
		verify ();
		if ((void*) CApi.called_value (call) != (void*) function || (void*) CApi.called_function_type (call) != (void*) type || CApi.argument_count (call) != parameters || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("fresh scoped result call lost its exact ABI/context position");
		}
	}

	internal bool matches(CApi.ValueRef actual_context, CApi.ValueRef actual_tag, CApi.ValueRef count, CApi.ValueRef actual_size, CApi.ValueRef actual_alignment) throws LlvmError {
		verify_signature ();
		return (void*) actual_context == (void*) context && (void*) actual_tag == (void*) tag && (void*) actual_size == (void*) size && (void*) actual_alignment == (void*) alignment && (void*) CApi.is_constant_int (count) != null && CApi.const_int_zext (count) == 1;
	}

}
// Physical borrowed-input authority copied from verified native types. No
// native/SSA node survives; a separate body seal protects admitted lowering.
internal class LlvmScopedContextInputs : Object {
	private CApi.ValueRef function;
	private CApi.TypeRef type;
	private uint parameter_count;
	private GenericArray<int> positions = new GenericArray<int> ();
	private GenericArray<void*> values = new GenericArray<void*> ();
	private LlvmSumSequence? body;
	private LlvmNativeModuleBinding? imported_body;
	private LlvmScopedContextInputs (CApi.ValueRef function, CApi.TypeRef type) {
		this.function = function;
		this.type = type;
		parameter_count = CApi.count_params (function);
	}

	internal static LlvmScopedContextInputs? from_native(CApi.ValueRef function, CApi.TypeRef type, NativeFunction source, GenericArray<NativeClassPlan> classes) throws LlvmError {
		var signature = source.signature;
		if (signature.receiver != null || signature.object_result != null || signature.sum_result != null || signature.buffer_result != null) {
			return null;
		}
		if (signature.result != null && (signature.result.abi_type.get_type () != typeof (NativeScalarAbiType) || signature.result.scalar_type == NativeScalarType.PTR && signature.heap_result == null)) {
			return null;
		}
		// A record leaf is admitted here only as a companion to the context.
		// Fresh context-derived results require their separate allocation proof.
		// The independent owning-input or Class-loan contract still proves its
		// actual pointer uses, allocation shape and retirement responsibility.
		var record_origins = new HashTable<int, NativeObjectOriginPlan> (direct_hash, direct_equal);
		if (!LlvmScopedRecordInputs.bind (signature, classes, record_origins)) {
			return null;
		}
		var record_positions = new HashTable<int, bool> (direct_hash, direct_equal);
		foreach (var group in signature.struct_parameters) {
			for (int f = 0; f < group.value_plan.leaves.length; f++) {
				record_positions.insert (group.first_leaf + f, true);
			}
		}
		var result = new LlvmScopedContextInputs (function, type);
		int at = signature.has_exception_success_slot ? 1 : 0;
		int logical = 0;
		foreach (var parameter in signature.parameters) {
			if (!(parameter.abi_type is NativeScalarAbiType)) {
				return null;
			}
			var context = parameter.abi_type as NativeContextHandleType;
			if (context != null && context.mode == "scoped-affine") {
				if (!context.valid () || context.cleanup != "astra_context17_destroy" || parameter.resource == null || parameter.owns_resource || parameter.resource.type_name != context.name || parameter.resource.cleanup_symbol != context.cleanup || at >= CApi.count_params (function)) {
					throw new LlvmError.INVALID_INPUT ("scoped context input lost its exact native noescape/cleanup role");
				}
				result.positions.add (at);
				result.values.add ((void*) CApi.get_param (function, at));
			} else if (parameter.borrowed_class_ordinal >= 0) {
				int ordinal = parameter.borrowed_class_ordinal;
				if (ordinal >= classes.length || parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type != NativeScalarType.PTR || parameter.object_origin != null || !classes[ordinal].allocation_policy_valid ()) {
					return null;
				}
				var owner = classes[ordinal];
				var policy = owner.allocation_policy;
				if (!(policy != null && policy.kind == AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") && !LlvmScopedClassGraph.scope_free (owner, classes)) {
					return null;
				}
			} else if (parameter.object_origin != null && !parameter.object_origin.heap) {
				var origin = parameter.object_origin;
				if (origin.class_ordinal < 0 || origin.class_ordinal >= classes.length || classes[origin.class_ordinal].name != origin.class_name || !LlvmScopedClassGraph.value_scope_free (classes[origin.class_ordinal], classes)) {
					return null;
				}
			} else if (parameter.abi_type.get_type () != typeof (NativeScalarAbiType) || parameter.scalar_type == NativeScalarType.PTR && !record_positions.contains (logical) && (parameter.object_origin == null || !parameter.object_origin.heap)) {
				return null;
			}
			at++;
			logical++;
		}
		if (result.values.length == 0) {
			return null;
		}
		try {
			var summary = RuntimeLifetimeSummary.decode (source.runtime_lifetimes);
			if (!summary.complete || !summary.matches_exception (signature.exception_plan != null) || summary.store_count != 0 || summary.updated_inputs ().length != 0) {
				return null;
			}
			if (summary.has_exception) {
				foreach (var root in summary.equations.requirements (summary.exception)) {
					if (root.kind != RuntimeScopeOriginKind.OWNER_PARAMETER || root.ordinal < 0 || root.ordinal >= signature.parameters.length || root.path != "" || !root.descendants || root.exclusion_count != 0) {
						return null;
					}
					var origin = signature.parameters[root.ordinal].object_origin;
					if (origin == null || !origin.heap) {
						return null;
					}
				}
			}
			var roots = summary.equations.requirements (summary.result);
			if (roots.length != 0) {
				if (LlvmScopedFreshResult.context_parameter (source, classes) >= 0) {
					return result;
				}
				if (signature.struct_result != null) {
					foreach (var root in roots) {
						if (root.kind != RuntimeScopeOriginKind.OWNER_PARAMETER || root.ordinal < 0 || root.ordinal >= signature.parameters.length || root.path != "" || !root.descendants || root.exclusion_count != 0) {
							return null;
						}
						var owner = record_origins.lookup (root.ordinal) ?? signature.parameters[root.ordinal].object_origin;
						if (owner == null || !owner.heap || owner.class_ordinal < 0 || owner.class_ordinal >= classes.length || classes[owner.class_ordinal].name != owner.class_name) {
							return null;
						}
					}
				} else {
					if (signature.heap_result == null || roots.length != 1 || roots[0].kind != RuntimeScopeOriginKind.OWNER_PARAMETER || roots[0].ordinal < 0 || roots[0].ordinal >= signature.parameters.length || roots[0].path != "" || !roots[0].descendants || roots[0].exclusion_count != 0) {
						return null;
					}
					var owner = signature.parameters[roots[0].ordinal].object_origin;
					if (owner == null || !owner.heap || owner.class_ordinal != signature.heap_result.class_ordinal || owner.class_name != signature.heap_result.class_name) {
						return null;
					}
				}
			}
		} catch (RuntimeLifetimeError failure) {
			throw new LlvmError.INVALID_INPUT ("scoped context input lifetime contract: %s", failure.message);
		}
		return result;
	}

	internal bool contains(CApi.ValueRef value) {
		return values.find ((void*) value);
	}

	internal uint count { get { return values.length; } }
	internal CApi.ValueRef parameter(int index) {
		return (CApi.ValueRef) values[index];
	}

	internal void verify_signature() throws LlvmError {
		if ((void*) CApi.global_value_type (function) != (void*) type || CApi.count_params (function) != parameter_count || CApi.function_call_conv (function) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("scoped context input lost its original physical signature");
		}
		for (int i = 0; i < positions.length; i++) {
			if (values[i] != (void*) CApi.get_param (function, positions[i]) || CApi.type_kind (CApi.type_of ((CApi.ValueRef) values[i])) != CApi.TypeKind.POINTER) {
				throw new LlvmError.VERIFICATION ("scoped context input lost its exact borrowed parameter");
			}
		}
	}

	internal void attach_import(LlvmNativeModuleBinding binding) throws LlvmError {
		if (body != null || imported_body != null || CApi.count_basic_blocks (function) != 0) {
			throw new LlvmError.LOWERING ("scoped native declaration requires its original external body role");
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
			throw new LlvmError.LOWERING ("scoped context inputs require their unique emitted body");
		}
		verify_signature ();
		body = new LlvmSumSequence (function, true);
	}

	internal void verify() throws LlvmError {
		verify_signature ();
		if (imported_body != null) {
			imported_body.verify ();
			return;
		}
		if (body == null) {
			throw new LlvmError.VERIFICATION ("scoped context input body is not sealed");
		}
		body.verify ();
	}

	internal bool accepts(CApi.ValueRef call, uint position) throws LlvmError {
		if (!positions.find ((int) position)) {
			return false;
		}
		verify ();
		if ((void*) CApi.called_value (call) != (void*) function || (void*) CApi.called_function_type (call) != (void*) type || CApi.argument_count (call) != parameter_count || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("scoped context call lost its exact physical signature/parameter");
		}
		return true;
	}

	internal void verify_use(CApi.ValueRef instruction, HashTable<void*, LlvmScopedContextInputs>? callees = null, HashTable<void*, LlvmScopedTaskFrame>? task_frames = null) throws LlvmError {
		for (uint i = 0; i < CApi.operand_count (instruction); i++) {
			if (!contains (CApi.operand (instruction, i))) {
				continue;
			}
			var opcode = CApi.opcode (instruction);
			if (opcode == CApi.Opcode.ICMP) {
				continue;
			}
			if (opcode != CApi.Opcode.CALL || (void*) CApi.is_function (CApi.called_value (instruction)) == null || contains (CApi.called_value (instruction))) {
				throw new LlvmError.VERIFICATION ("borrowed scoped context escaped through an emitted alias");
			}
			size_t length;
			string target = CApi.value_name (CApi.called_value (instruction), out length);
			if (target == "astra_context17_destroy") {
				throw new LlvmError.VERIFICATION ("borrowed scoped context cannot be retired by its callee");
			}
			if (target == "astra_context17_allocate_mode" && i == 0) {
				continue;
			}
			var task = task_frames == null ? null : task_frames.lookup ((void*) instruction);
			if (task != null && task.context_use (instruction, i)) {
				continue;
			}
			var callee = callees == null ? null : callees.lookup ((void*) CApi.called_value (instruction));
			if (callee != null && callee.accepts (instruction, i)) {
				continue;
			}
			if (CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.POINTER) {
				throw new LlvmError.VERIFICATION ("borrowed scoped context call requires its exact pointer-result lifetime effect");
			}
			// Scalar calls may use the original checked noescape body only.
			// A new arbitrary void/scalar callee has no lifetime authority.
			verify ();
		}
	}

}
}
