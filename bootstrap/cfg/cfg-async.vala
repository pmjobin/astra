// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Cfg {
public class CfgSuspensionLoan : Object {
	public SuspensionLoanIdentity identity { get; private set; }
	public int parameter_ordinal { get; private set; }
	public CfgLocalPlace storage { get; private set; }
	public CfgValue view { get; private set; }
	internal CfgSuspensionLoan (SuspensionLoanIdentity identity, int parameter_ordinal, CfgLocalPlace storage, CfgValue view) {
		this.identity = identity;
		this.parameter_ordinal = parameter_ordinal;
		this.storage = storage;
		this.view = view;
	}

}

public class CfgTaskCreate : CfgCallInstruction {
	public bool checked_admission { get; private set; }
	public CfgValue? allocation_context { get; private set; }
	public GenericArray<CfgSuspensionLoan> loans { get; private set; default = new GenericArray<CfgSuspensionLoan> (); }
	private GenericArray<CfgValue> captures = new GenericArray<CfgValue> ();
	internal bool matches_captures() {
		if (arguments.length != captures.length) {
			return false;
		}
		for (int i = 0; i < captures.length; i++) {
			if (arguments[i] != captures[i]) {
				return false;
			}
		}
		return true;
	}

	internal int direct_wait_position(CfgBlock block, int position) {
		for (int i = position + 1; i < block.instructions.length; i++) {
			var wait = block.instructions[i] as CfgTaskWait;
			if (wait != null) {
				return wait.child == result ? i : -1;
			}
			var cleanup = block.instructions[i] as CfgCleanupInstruction;
			var loaded = cleanup == null ? null : cleanup.value as CfgLoadValue;
			bool captured = false;
			if (loaded != null) {
				foreach (var argument in arguments) {
					var transfer = argument as CfgPendingOwnedArgument;
					if (transfer != null && transfer.consumer == this && transfer.fresh_staged && transfer.source == loaded.source && transfer.cleanup == cleanup.cleanup) {
						captured = true;
					}
				}
			}
			if (!captured) {
				return -1;
			}
		}
		return -1;
	}

	internal CfgTaskCreate (SourceSpan span, CfgFunction target, GenericArray<CfgValue> arguments, CfgCallResultValue result, CfgValue? allocation_context = null, bool checked_admission = false) {
		base (span, target, arguments, result);
		this.checked_admission = checked_admission;
		this.allocation_context = allocation_context;
		foreach (var argument in arguments) {
			captures.add (argument);
		}
	}

}
public class CfgTaskMove : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	public CfgEvaluatedValue result { get; private set; }
	internal CfgTaskMove (SourceSpan span, CfgLocalPlace source) {
		base (span);
		this.source = source;
		result = new CfgEvaluatedValue (span, source.semantic_type);
	}

}
public class CfgTaskEnd : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	internal CfgTaskEnd (SourceSpan span, CfgLocalPlace source) {
		base (span);
		this.source = source;
	}

}
public class CfgAsyncDelay : CfgInstruction {
	public bool payload { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public CfgValue ticks { get; private set; }
	public CfgEvaluatedValue exception { get; private set; }
	internal CfgAsyncDelay (SourceSpan span, AsyncBodyContract body, CfgValue ticks, ClassType error_root, bool payload = false) {
		base (span);
		this.body = body;
		this.ticks = ticks;
		this.payload = payload;
		exception = new CfgEvaluatedValue (span, error_root);
	}

}
public class CfgTaskWait : CfgInstruction {
	public CfgValue? bridge_executor { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public CfgValue child { get; private set; }
	public bool discard { get; private set; }
	public CfgEvaluatedValue exception { get; private set; }
	private WeakRef continuation = WeakRef (null);
	public CfgTaskSuccess? success { owned get { return (CfgTaskSuccess?) continuation.get (); } internal set { continuation.set (value); } }
	internal CfgTaskWait (SourceSpan span, AsyncBodyContract body, CfgValue child, ClassType error_root, bool discard, CfgValue? bridge_executor = null) {
		base (span);
		this.bridge_executor = bridge_executor;
		this.body = body;
		this.child = child;
		this.discard = discard;
		exception = new CfgEvaluatedValue (span, error_root);
	}

}
public class CfgTaskSuccess : CfgInstruction {
	public CfgCleanupContract? buffer_cleanup { get; private set; }
	public CfgTaskWait operation { get; private set; }
	public CfgValue? result { get; private set; }
	public SemanticType success_type { get; private set; }
	public CfgStructCallResults? struct_result { get; private set; }
	public CfgEnumSlot? enum_result { get; private set; }
	internal CfgTaskSuccess (SourceSpan span, CfgTaskWait operation, SemanticType result, CfgCleanupContract? buffer_cleanup = null) {
		base (span);
		this.operation = operation;
		this.success_type = result;
		this.buffer_cleanup = buffer_cleanup;
		this.result = buffer_cleanup == null ? (CfgValue) new CfgEvaluatedValue (span, result) : new CfgCallResultValue (span, result);
	}

	internal CfgTaskSuccess.for_record (SourceSpan span, CfgTaskWait operation, StructValueShape shape) {
		base (span);
		this.operation = operation;
		success_type = shape.semantic_type;
		struct_result = new CfgStructCallResults (span, shape);
	}
	internal CfgTaskSuccess.for_enum (SourceSpan span, CfgTaskWait operation, CfgEnumSlot destination) {
		base (span);
		this.operation = operation;
		success_type = destination.definition.semantic_type;
		enum_result = destination;
	}
}

public class CfgTaskBorrow : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	public CfgEvaluatedValue result { get; private set; }
	internal CfgTaskBorrow (SourceSpan span, CfgLocalPlace source) {
		base (span);
		this.source = source;
		result = new CfgEvaluatedValue (span, source.semantic_type);
	}

}
public class CfgAsyncOperation : CfgInstruction {
	public AsyncOperationContract contract { get; private set; }
	public CfgValue? executor { get; private set; }
	public CfgValue? task { get; private set; }
	public CfgValue? argument { get; private set; }
	public int task_owner { get; private set; }
	public int executor_owner { get; private set; }
	public CfgEvaluatedValue? result { get; private set; }
	public CfgEvaluatedValue? exception { get; private set; }
	internal CfgAsyncOperation (SourceSpan span, AsyncOperationContract contract, CfgValue? executor, CfgValue? task, CfgValue? argument, ClassType? error_root, int task_owner, int executor_owner) {
		base (span);
		this.contract = contract;
		this.executor = executor;
		this.task = task;
		this.argument = argument;
		this.task_owner = task_owner;
		this.executor_owner = executor_owner;
		if (contract.result.kind != TypeKind.VOID) {
			result = new CfgEvaluatedValue (span, contract.result);
		}
		if (contract.raises) {
			exception = new CfgEvaluatedValue (span, error_root);
		}
	}

}
public class CfgTaskStarted : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	public CfgAsyncOperation operation { get; private set; }
	internal CfgTaskStarted (SourceSpan span, CfgLocalPlace source, CfgAsyncOperation operation) {
		base (span);
		this.source = source;
		this.operation = operation;
	}

}

public class CfgExecutorEnd : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	internal CfgExecutorEnd (SourceSpan span, CfgLocalPlace source) {
		base (span);
		this.source = source;
	}

}

public class CfgAsyncRunStatus : CfgInstruction {
	public CfgAsyncOperation operation { get; private set; }
	public CfgEnumSlot destination { get; private set; }
	internal CfgAsyncRunStatus (SourceSpan span, CfgAsyncOperation operation, CfgEnumSlot destination) {
		base (span);
		this.operation = operation;
		this.destination = destination;
	}

}

}
