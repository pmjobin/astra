// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;

namespace Astra.NativeAbi {
public class NativeEntryBuilder : Object {
	public static NativeProgramEntryPlan build(SsaProgram source, NativeAbiProgram native, SsaFunction selected) throws NativeAbiError {
		int ordinal = -1;
		for (int i = 0; i < source.functions.length; i++) {
			if (source.functions[i] == selected) {
				ordinal = i;
			}
		}
		var kind = selected.parameters.length == 0 ? NativeEntryKind.ZERO_ARGUMENTS : NativeEntryKind.TEXT_ARGUMENTS;
		var plan = new NativeProgramEntryPlan (ordinal, selected.name_span, kind, kind == NativeEntryKind.TEXT_ARGUMENTS ? new NativeTextSliceType () : null);
		validate (plan, source, native, selected);
		return plan;
	}

	public static void validate(NativeProgramEntryPlan plan, SsaProgram source, NativeAbiProgram native, SsaFunction selected) throws NativeAbiError {
		plan.verify ();
		int ordinal = plan.function_ordinal;
		if (ordinal >= source.functions.length || ordinal >= native.functions.length || source.functions[ordinal] != selected || plan.symbol_span.file != selected.name_span.file || plan.symbol_span.start != selected.name_span.start || plan.symbol_span.end != selected.name_span.end || selected is SsaMethod || selected.return_type.kind != TypeKind.INT || selected.result_contract != ResultOwnershipContract.UNMANAGED) {
			throw new NativeAbiError.INVALID_ABI ("entry error: selected identity must correspond to the exact free source function and int result");
		}
		var function = native.functions[ordinal];
		var signature = function.signature;
		if (function.owner != native || function.kind != NativeCallableKind.FUNCTION || signature.exception_plan != null || signature.receiver != null || signature.object_result != null || signature.struct_result != null || signature.buffer_result != null || signature.struct_parameters.length != 0 || signature.buffer_parameters.length != 0 || signature.result == null || !(signature.result.abi_type is NativeScalarAbiType) || signature.result.scalar_type != NativeScalarType.I32 || signature.parameters.length != selected.parameters.length) {
			throw new NativeAbiError.INVALID_ABI ("entry plan requires corresponding plain native I32 result and exact parameter group");
		}
		if (plan.kind == NativeEntryKind.ZERO_ARGUMENTS) {
			if (selected.parameters.length != 0) {
				throw new NativeAbiError.INVALID_ABI ("zero-argument entry plan does not match selected signature");
			}
		} else if (selected.parameters.length != 1 || !selected.parameters[0].semantic_type.is_text_slice () || selected.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || signature.abi_version != NativeAbiVersion.TEXT_SLICE_V10 || !plan.text_slice.same_type (signature.parameters[0].abi_type)) {
			throw new NativeAbiError.INVALID_ABI ("text entry plan requires exact deep borrowed string[] and text-slice-v10 correspondence");
		}
	}

}
}
