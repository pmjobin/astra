// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Core {
public class CoreSuspensionLoan : Object {
	public SuspensionLoanIdentity identity { get; private set; }
	public int parameter_ordinal { get; private set; }
	public CoreLocalPlace storage { get; private set; }
	public CoreSliceFromArrayValue view { get; private set; }
	internal CoreSuspensionLoan (SuspensionLoanIdentity identity, int parameter_ordinal, CoreLocalPlace storage, CoreSliceFromArrayValue view) {
		this.identity = identity;
		this.parameter_ordinal = parameter_ordinal;
		this.storage = storage;
		this.view = view;
	}
}

public class CoreTaskCreate : CoreCallValue {
	public bool checked_admission { get; private set; }
	public CoreValue? allocation_context { get; private set; }
	public GenericArray<CoreSuspensionLoan> loans { get; private set; default = new GenericArray<CoreSuspensionLoan> (); }
	private GenericArray<CoreValue> captures = new GenericArray<CoreValue> ();
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
	internal CoreTaskCreate (SourceSpan span, TaskType type, CoreFunction target, GenericArray<CoreValue> arguments, CoreValue? allocation_context = null, bool checked_admission = false) {
		base (span, type, target, arguments);
		this.checked_admission = checked_admission;
		this.allocation_context = allocation_context;
		foreach (var argument in arguments) {
			captures.add (argument);
		}
	}
}
public class CoreStructAwait : CoreStructProducer {
	public CoreTaskAwait operation { get; private set; }
	internal CoreStructAwait (CoreTaskAwait operation, StructValueMode mode = StructValueMode.COPY_VALUE) {
		base (operation.span, operation.semantic_type, mode);
		this.operation = operation;
	}
}
public class CoreEnumAwait : CoreEnumProducer {
	public CoreTaskAwait operation { get; private set; }
	internal CoreEnumAwait (EnumDefinition definition, CoreTaskAwait operation, EnumInstanceIdentity instance) {
		base (operation.span, definition, instance);
		this.operation = operation;
	}
}
public class CoreTaskMove : CoreValue {
	public CoreLocalPlace source { get; private set; }
	internal CoreTaskMove (SourceSpan span, CoreLocalPlace source) {
		base (span, source.semantic_type);
		this.source = source;
	}
}
public class CoreAsyncDelay : CoreStatement {
	public bool payload { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public CoreValue ticks { get; private set; }
	internal CoreAsyncDelay (SourceSpan span, AsyncBodyContract body, CoreValue ticks, bool payload = false) {
		base (span);
		this.body = body;
		this.ticks = ticks;
		this.payload = payload;
	}
}
public class CoreTaskAwait : CoreValue {
	public CoreValue? bridge_executor { get; private set; }
	public CoreCleanupContract? buffer_cleanup { get; private set; }
	public AsyncBodyContract body { get; private set; }
	public CoreValue child { get; private set; }
	public bool discard { get; private set; }
	internal CoreTaskAwait (SourceSpan span, SemanticType result, AsyncBodyContract body, CoreValue child, bool discard, CoreCleanupContract? buffer_cleanup = null, CoreValue? bridge_executor = null) {
		base (span, result);
		this.bridge_executor = bridge_executor;
		this.body = body;
		this.child = child;
		this.discard = discard;
		this.buffer_cleanup = buffer_cleanup;
	}
}
public class CoreTaskAwaitStatement : CoreStatement {
	public CoreTaskAwait operation { get; private set; }
	internal CoreTaskAwaitStatement (SourceSpan span, CoreTaskAwait operation) {
		base (span);
		this.operation = operation;
	}
}

public class CoreTaskBorrow : CoreValue {
	public CoreLocalPlace source { get; private set; }
	internal CoreTaskBorrow (SourceSpan span, CoreLocalPlace source) {
		base (span, source.semantic_type);
		this.source = source;
	}
}
public class CoreExecutorBorrow : CoreValue {
	public CoreLocalPlace source { get; private set; }
	internal CoreExecutorBorrow (SourceSpan span, CoreLocalPlace source) {
		base (span, source.semantic_type);
		this.source = source;
	}
}
public class CoreAsyncOperation : CoreValue {
	public AsyncOperationContract contract { get; private set; }
	public CoreValue? executor { get; private set; }
	public CoreValue? task { get; private set; }
	public CoreValue? argument { get; private set; }
	internal CoreAsyncOperation (SourceSpan span, AsyncOperationContract contract, CoreValue? executor, CoreValue? task, CoreValue? argument) {
		base (span, contract.result);
		this.contract = contract;
		this.executor = executor;
		this.task = task;
		this.argument = argument;
	}
}
public class CoreAsyncOperationStatement : CoreStatement {
	public CoreAsyncOperation operation { get; private set; }
	internal CoreAsyncOperationStatement (SourceSpan span, CoreAsyncOperation operation) {
		base (span);
		this.operation = operation;
	}
}
public class CoreAsyncRun : CoreEnumProducer {
	public CoreAsyncOperation operation { get; private set; }
	internal CoreAsyncRun (SourceSpan span, EnumDefinition definition, CoreAsyncOperation operation, EnumInstanceIdentity instance) {
		base (span, definition, instance);
		this.operation = operation;
	}
}

}
