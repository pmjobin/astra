// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
// Only snapshot and call producers exist, consumed by the four nodes below.
// Producers are deliberately not CheckedExpressions.
public abstract class CheckedStructProducer : CheckedNode {
	public StructValueContract contract { get; private set; }
	public SemanticType semantic_type { get { return contract.semantic_type; } }
	public Copyability copyability { get; private set; }
	protected CheckedStructProducer (SourceSpan span, SemanticType type, Copyability copyability, StructValueMode mode = StructValueMode.COPY_VALUE) {
		base (span);
		this.contract = new StructValueContract (type, mode);
		this.copyability = copyability;
	}

}

public class CheckedStructMoveProducer : CheckedStructProducer {
	public LocalSymbol source { get; private set; }
	internal CheckedStructMoveProducer (SourceSpan span, LocalSymbol source) {
		base (span, source.semantic_type, Copyability.NOT_COPYABLE, StructValueMode.MOVE_VALUE);
		this.source = source;
	}

}

public class CheckedStructSnapshot : CheckedStructProducer {
	public CheckedPlace source { get; private set; }
	internal CheckedStructSnapshot (SourceSpan span, CheckedPlace source, Copyability copyability) {
		base (span, source.semantic_type, copyability);
		this.source = source;
	}

}

// A read-only observation keeps the complete nominal storage graph while
// transferring none of its recursive cleanup obligations. Consumers must
// retain the source loan; it is never an ordinary copied record snapshot.
public class CheckedStructBorrowSnapshot : CheckedStructProducer {
	public CheckedPlace source { get; private set; }
	internal CheckedStructBorrowSnapshot (SourceSpan span, CheckedPlace source) {
		base (span, source.semantic_type, Copyability.NOT_COPYABLE, StructValueMode.BORROW_VALUE);
		this.source = source;
	}

}

// Observe a copied producer exactly once before selecting a field. A copied
// subrecord remains a bounded producer; it never becomes an aggregate value.
public class CheckedStructProjectionValue : CheckedExpression {
	public LexicalRegion? borrow_region { get; internal set; }
	public CheckedStructProducer source { get; private set; }
	public StructLeafPath path { get; private set; }
	internal CheckedStructProjectionValue (SourceSpan span, CheckedStructProducer source, StructLeafPath path) {
		base (span, path.semantic_type);
		this.source = source;
		this.path = path;
	}

}

public class CheckedStructProjectionProducer : CheckedStructProducer {
	public CheckedStructProducer source { get; private set; }
	public StructLeafPath path { get; private set; }
	internal CheckedStructProjectionProducer (SourceSpan span, CheckedStructProducer source, StructLeafPath path) {
		base (span, path.semantic_type, Copyability.COPYABLE);
		this.source = source;
		this.path = path;
	}

}

public class CheckedCStructCallResult : CheckedStructProducer {
	private WeakRef callee;
	public CFunctionSymbol? target { owned get { return (CFunctionSymbol?) callee.get (); } }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	internal CheckedCStructCallResult (SourceSpan span, CFunctionSymbol target, GenericArray<CheckedExpression> arguments) {
		base (span, target.return_type, Copyability.COPYABLE);
		this.callee = WeakRef (target);
		this.arguments = arguments;
	}

}

public class CheckedStructInvocationResult : CheckedStructProducer {
	public CheckedExpression invocation { get; private set; }
	internal CheckedStructInvocationResult (CheckedExpression invocation, StructValueMode mode) {
		base (invocation.span, invocation.semantic_type, mode == StructValueMode.COPY_VALUE ? Copyability.COPYABLE : Copyability.NOT_COPYABLE, mode);
		this.invocation = invocation;
	}

}

public class CheckedStructCallResult : CheckedStructProducer {
	private WeakRef callee;
	public FunctionSymbol? target { owned get { return (FunctionSymbol?) callee.get (); } }
	public GenericArray<CheckedExpression> arguments { get; private set; }
	public CheckedExpression? receiver { get; private set; }
	public GenericArray<SemanticType>? type_arguments { get; private set; }
	internal CheckedStructCallResult (SourceSpan span, FunctionSymbol target, GenericArray<CheckedExpression> arguments, CheckedExpression? receiver, Copyability copyability, SemanticType? result = null, GenericArray<SemanticType>? type_arguments = null) {
		base (span, result ?? target.return_type, copyability, target.struct_result_contract == null ? StructValueMode.COPY_VALUE : target.struct_result_contract.mode);
		this.callee = WeakRef (target);
		this.arguments = arguments;
		this.receiver = receiver;
		this.type_arguments = type_arguments;
	}

}

// This adapter is legal only at an exact COPY_VALUE argument position.
public class CheckedStructArgument : CheckedExpression {
	public CheckedStructProducer producer { get; private set; }
	public ParameterSymbol? parameter { get; private set; }
	internal CheckedStructArgument (SourceSpan span, ParameterSymbol? parameter, CheckedStructProducer producer) {
		base (span, producer.semantic_type);
		this.parameter = parameter;
		this.producer = producer;
	}

}

public class CheckedStructResultStore : CheckedStatement {
	public CheckedPlace destination { get; private set; }
	public CheckedStructProducer producer { get; private set; }
	public bool initializes_destination { get; private set; }
	internal CheckedStructResultStore (SourceSpan span, CheckedPlace destination, CheckedStructProducer producer, bool initializes_destination) {
		base (span);
		this.destination = destination;
		this.producer = producer;
		this.initializes_destination = initializes_destination;
	}

}

public class CheckedStructReturn : CheckedStatement {
	public CheckedStructProducer producer { get; private set; }
	internal CheckedStructReturn (SourceSpan span, CheckedStructProducer producer) {
		base (span);
		this.producer = producer;
	}

}
}
