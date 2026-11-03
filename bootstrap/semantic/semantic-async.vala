// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
namespace Astra.Semantic {
public class CheckedSuspensionLoan : Object {
	public SuspensionLoanIdentity identity { get; private set; }
	public int parameter_ordinal { get; private set; }
	public LocalSymbol storage { get; private set; }
	public CheckedSliceFromArrayExpression view { get; private set; }
	internal CheckedSuspensionLoan (SuspensionLoanIdentity identity, int parameter_ordinal, LocalSymbol storage, CheckedSliceFromArrayExpression view) {
		this.identity = identity;
		this.parameter_ordinal = parameter_ordinal;
		this.storage = storage;
		this.view = view;
	}

}

public class CheckedTaskCreate : CheckedExpression {
	public bool checked_admission { get; private set; }
	public CheckedExpression? allocation_context { get; private set; }
	public GenericArray<CheckedSuspensionLoan> loans { get; private set; default = new GenericArray<CheckedSuspensionLoan> (); }
	private WeakRef callee;
	public FunctionSymbol? target { owned get { return (FunctionSymbol?) callee.get (); } }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	internal CheckedTaskCreate (SourceSpan span, FunctionSymbol target, GenericArray<CheckedExpression> arguments, CheckedExpression? allocation_context = null, bool checked_admission = false) {
		base (span, target.async_body.task_type);
		this.checked_admission = checked_admission;
		this.allocation_context = allocation_context;
		callee = WeakRef (target);
		this.arguments = arguments;
	}

}
public class CheckedStructAwait : CheckedStructProducer {
	public CheckedTaskAwait operation { get; private set; }
	internal CheckedStructAwait (CheckedTaskAwait operation, StructValueMode mode = StructValueMode.COPY_VALUE) {
		base (operation.span, operation.semantic_type, mode == StructValueMode.COPY_VALUE ? Copyability.COPYABLE : Copyability.NOT_COPYABLE, mode);
		this.operation = operation;
	}

}
public class CheckedEnumAwait : CheckedEnumProducer {
	public CheckedTaskAwait operation { get; private set; }
	internal CheckedEnumAwait (EnumDefinition definition, CheckedTaskAwait operation) {
		base (operation.span, definition);
		this.operation = operation;
	}

}
public class CheckedTaskMove : CheckedExpression {
	public LocalSymbol source { get; private set; }
	internal CheckedTaskMove (SourceSpan span, LocalSymbol source) {
		base (span, source.semantic_type);
		this.source = source;
	}

}
public class CheckedAsyncDelay : CheckedStatement {
	public bool payload { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public CheckedExpression ticks { get; private set; }
	internal CheckedAsyncDelay (SourceSpan span, AsyncBodyContract body, CheckedExpression ticks, bool payload = false) {
		base (span);
		this.body = body;
		this.ticks = ticks;
		this.payload = payload;
	}

}
public class CheckedTaskAwait : CheckedExpression {
	public CheckedExpression? bridge_executor { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public CheckedExpression child { get; private set; }
	public bool discard { get; private set; }
	internal CheckedTaskAwait (SourceSpan span, SemanticType result, AsyncBodyContract body, CheckedExpression child, bool discard, CheckedExpression? bridge_executor = null) {
		base (span, result);
		this.bridge_executor = bridge_executor;
		this.body = body;
		this.child = child;
		this.discard = discard;
	}

}
public class CheckedTaskAwaitStatement : CheckedStatement {
	public CheckedTaskAwait operation { get; private set; }
	internal CheckedTaskAwaitStatement (SourceSpan span, CheckedTaskAwait operation) {
		base (span);
		this.operation = operation;
	}

}

public class CheckedTaskBorrow : CheckedExpression {
	public LocalSymbol source { get; private set; }
	internal CheckedTaskBorrow (SourceSpan span, LocalSymbol source) {
		base (span, source.semantic_type);
		this.source = source;
	}

}
public class CheckedExecutorBorrow : CheckedExpression {
	public LocalSymbol source { get; private set; }
	internal CheckedExecutorBorrow (SourceSpan span, LocalSymbol source) {
		base (span, source.semantic_type);
		this.source = source;
	}

}
public class CheckedAsyncOperation : CheckedExpression {
	public AsyncOperationContract contract { get; private set; }
	public CheckedExpression? executor { get; private set; }
	public CheckedExpression? task { get; private set; }
	public CheckedExpression? argument { get; private set; }
	internal CheckedAsyncOperation (SourceSpan span, AsyncOperationContract contract, CheckedExpression? executor, CheckedExpression? task, CheckedExpression? argument) {
		base (span, contract.result);
		this.contract = contract;
		this.executor = executor;
		this.task = task;
		this.argument = argument;
	}

}
public class CheckedAsyncOperationStatement : CheckedStatement {
	public CheckedAsyncOperation operation { get; private set; }
	internal CheckedAsyncOperationStatement (SourceSpan span, CheckedAsyncOperation operation) {
		base (span);
		this.operation = operation;
	}

}
public class CheckedAsyncRun : CheckedEnumProducer {
	public CheckedAsyncOperation operation { get; private set; }
	internal CheckedAsyncRun (SourceSpan span, EnumDefinition definition, CheckedAsyncOperation operation) {
		base (span, definition);
		this.operation = operation;
	}

}

}
