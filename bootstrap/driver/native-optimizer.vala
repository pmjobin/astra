// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Driver {
// Construction-local correspondence to the independently admitted native
// signature and nominal scalar layout. Only a detached evidence receipt leaves
// module binding. No producer body is read by a consuming compilation.
internal class NativeOptimizerSpec : Object {
	[CCode (cname = "astra_native_object_proof", cheader_filename = "native-proof.h")]
	private static extern uint leaf_proof(uint8[] bytes, string symbol, uint[] types,
		uint result_type, uint[] offsets, uint[] sizes, string[] callee_symbols, string[] callee_contracts);
	private uint[] types = {};
	private uint[] offsets = {};
	private uint[] sizes = {};
	private uint result_type;
	private int pointer_ordinal = -2;
	private int parameter_count;
	private bool supported;
	private Object? pointer_identity;
	private static uint scalar_type(SemanticType type) {
		NativeScalarAbiType? native;
		try {
			native = NativeTypeMapper.map_type (type) as NativeScalarAbiType;
		} catch (NativeAbiError error) {
			return 0;
		}
		if (native == null) {
			return 0;
		}
		switch (native.scalar_type) {
		case NativeScalarType.B1: case NativeScalarType.I8: case NativeScalarType.U8: return 1;
		case NativeScalarType.I16:
		case NativeScalarType.U16:
			return 2;
		case NativeScalarType.I32:
		case NativeScalarType.U32:
			return 4;
		case NativeScalarType.I64:
		case NativeScalarType.U64:
			return 8;
		case NativeScalarType.F32:
			return 16;
		case NativeScalarType.F64:
			return 17;
		default:
			return 0;
		}
	}
	private bool formal(SemanticType type, int ordinal, SsaProgram source, LlvmStructRegistry layouts, CApi.TargetDataRef data) throws LlvmError {
		uint scalar = scalar_type (type);
		if (scalar != 0) {
			types += scalar;
			return true;
		}
		var receiver = type as ReceiverType;
		if (receiver != null) {
			type = receiver.instance_type;
		}
		if (!(type is ClassType) || pointer_ordinal != -2) {
			return false;
		}
		SsaClass? owner = null;
		foreach (var candidate in source.classes) {
			if (candidate.semantic_type == type) {
				owner = candidate;
			}
		}
		if (owner == null || owner.polymorphic || owner.parent_class != null || owner.concurrency_policy != null || owner.allocation_policy != null) {
			return false;
		}
		foreach (var property in owner.properties) {
			if (property.is_lazy) {
				return false;
			}
		}
		var layout = layouts.lookup (owner);
		foreach (var field in owner.fields) {
			uint field_type = scalar_type (field.semantic_type);
			if (field_type == 0 || field.owned_cleanup != null || field.slots_cleanup != null) {
				return false;
			}
			uint64 offset = CApi.offset_of_element (data, layout, layouts.field_index (field));
			if (offset > uint.MAX) {
				return false;
			}
			offsets += (uint) offset;
			sizes += field_type == 16 ? 4 : field_type == 17 ? 8 : field_type;
		}
		pointer_ordinal = ordinal;
		pointer_identity = type.logical_identity;
		types += 32;
		return true;
	}
	internal NativeOptimizerSpec (SsaFunction function, SsaProgram source, NativeSignature signature, LlvmStructRegistry layouts, CApi.TargetDataRef data) throws LlvmError {
		parameter_count = function.parameters.length;
		if (function.async_body != null || function.throws_type != null || signature.exception_plan != null || function.struct_parameters.length != 0 || function.buffer_parameters.length != 0 || function.struct_result != null) {
			return;
		}
		result_type = function.return_type.kind == Astra.Semantic.TypeKind.VOID ? 0 : scalar_type (function.return_type);
		if (function.return_type.kind != Astra.Semantic.TypeKind.VOID && result_type == 0) {
			return;
		}
		if (function.implicit_receiver != null && !formal (function.implicit_receiver.semantic_type, -1, source, layouts, data)) {
			return;
		}
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			if (scalar_type (parameter.semantic_type) == 0 && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				return;
			}
			if (!formal (parameter.semantic_type, p, source, layouts, data)) {
				return;
			}
		}
		supported = true;
	}
	internal OptimizerSummary propose(FunctionEffectFacts? facts) throws OptimizerSummaryError {
		var summary = new OptimizerSummary (supported && facts != null && (facts.flags & FunctionEffectFacts.NO_EXTERNAL_MEMORY) != 0);
		if (!supported || facts == null || pointer_ordinal == -2) {
			return summary;
		}
		uint effects = pointer_ordinal == -1 ? facts.flags & 3 : facts.parameter (pointer_ordinal);
		if (effects != 0) {
			summary.add (pointer_ordinal, effects);
		}
		return summary;
	}
	internal string? call_contract(OptimizerSummary summary, bool local, NativeOptimizerSpec caller) {
		if (!supported || summary.count > 1 || summary.count != 0 && summary.parameter (0).ordinal != pointer_ordinal || pointer_identity != null && caller.pointer_identity != pointer_identity) {
			return null;
		}
		uint flags = (summary.memory_none ? 4U : 0U) | (local ? 16U : 32U);
		if (summary.count == 1) {
			flags |= summary.parameter (0).facts;
		}
		var text = new StringBuilder ("%u,%u".printf (flags, result_type));
		foreach (uint type in types) {
			text.append_printf (",%u", type);
		}
		return text.str;
	}
	internal bool accepts(OptimizerSummary summary, uint8[] object_bytes, string symbol, string[] callee_symbols, string[] callee_contracts) {
		if (!summary.memory_none && summary.count == 0) {
			return true;
		}
		if (!supported || summary.count > 1 || summary.count != 0 && summary.parameter (0).ordinal != pointer_ordinal) {
			return false;
		}
		uint proved = leaf_proof (object_bytes, symbol, types, result_type, offsets, sizes, callee_symbols, callee_contracts);
		if ((proved & 8) == 0 || summary.memory_none && (proved & 4) == 0) {
			return false;
		}
		return summary.count == 0 || (summary.parameter (0).facts & ~(proved & 3U)) == 0;
	}
	internal FunctionEffectFacts facts(OptimizerSummary summary) {
		uint flags = summary.memory_none ? FunctionEffectFacts.NO_EXTERNAL_MEMORY : 0;
		var parameters = new uint[parameter_count];
		for (uint p = 0; p < summary.count; p++) {
			var row = summary.parameter (p);
			if (row.ordinal == -1) {
				flags |= row.facts;
			} else {
				parameters[row.ordinal] = row.facts;
			}
		}
		return new FunctionEffectFacts (flags, parameters);
	}
}
}
