// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
public enum NativeEntryKind {
	ZERO_ARGUMENTS, TEXT_ARGUMENTS
}
public enum NativeEntryStep {
	INITIALIZE_NULL, PREPARE, GUARD_SUCCESS, INVOKE_NATIVE, DISPOSE, RETURN
}
// Independent selection/protocol authority. Source spans are immutable leaves;
// no syntax, checked/SSA function, ABI program or source-name lookup survives.
public class NativeProgramEntryPlan : Object {
	public int function_ordinal { get; private set; }
	public Source.SourceSpan symbol_span { get; private set; }
	public NativeEntryKind kind { get; private set; }
	public NativeTextSliceType? text_slice { get; private set; }
	private NativeEntryStep[] operations;
	public int step_count { get { return operations.length; } }
	public NativeEntryStep step(int index) {
		return operations[index];
	}
	public const string PREPARE_SYMBOL = "astra_host_args_prepare_v0";
	public const string DISPOSE_SYMBOL = "astra_host_args_dispose_v0";
	internal NativeProgramEntryPlan (int function_ordinal, Source.SourceSpan symbol_span, NativeEntryKind kind, NativeTextSliceType? text_slice = null, NativeEntryStep[]? operations = null) {
		this.function_ordinal = function_ordinal;
		this.symbol_span = symbol_span;
		this.kind = kind;
		this.text_slice = text_slice;
		this.operations = operations ?? (kind == NativeEntryKind.TEXT_ARGUMENTS ? new NativeEntryStep[] { NativeEntryStep.INITIALIZE_NULL, NativeEntryStep.PREPARE, NativeEntryStep.GUARD_SUCCESS, NativeEntryStep.INVOKE_NATIVE, NativeEntryStep.DISPOSE, NativeEntryStep.RETURN } : new NativeEntryStep[] { NativeEntryStep.INVOKE_NATIVE, NativeEntryStep.RETURN });
	}
	public void verify() throws NativeAbiError {
		if (function_ordinal < 0 || (kind != NativeEntryKind.ZERO_ARGUMENTS && kind != NativeEntryKind.TEXT_ARGUMENTS) || (kind == NativeEntryKind.TEXT_ARGUMENTS ? text_slice == null || !text_slice.valid () : text_slice != null)) {
			throw new NativeAbiError.INVALID_ABI ("entry requires an exact selected identity, entry kind and text-slice contract");
		}
		NativeEntryStep[] expected = kind == NativeEntryKind.TEXT_ARGUMENTS ? new NativeEntryStep[] {
			NativeEntryStep.INITIALIZE_NULL, NativeEntryStep.PREPARE, NativeEntryStep.GUARD_SUCCESS, NativeEntryStep.INVOKE_NATIVE, NativeEntryStep.DISPOSE, NativeEntryStep.RETURN
		} : new NativeEntryStep[] {
			NativeEntryStep.INVOKE_NATIVE, NativeEntryStep.RETURN
		};
		if (operations.length != expected.length) {
			throw new NativeAbiError.INVALID_ABI ("entry protocol has incomplete preparation/cleanup sequence");
		}
		for (int i = 0; i < expected.length; i++) {
			if (operations[i] != expected[i]) {
				throw new NativeAbiError.INVALID_ABI ("entry publication/call must follow success guard and disposal must follow native return");
			}
		}
	}
}
}
