// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// An exact bounded source for copying/forwarding, deliberately not CoreValue.
public abstract class CoreStructProducer : CoreNode {
	public StructValueContract contract { get; private set; }
	public SemanticType semantic_type { get { return contract.semantic_type; } }
	protected CoreStructProducer (SourceSpan span, SemanticType type, StructValueMode mode = StructValueMode.COPY_VALUE) {
		base (span);
		this.contract = new StructValueContract (type, mode);
	}

}

public class CoreStructMoveProducer : CoreStructProducer {
	public CoreOwnedLocal source { get; private set; }
	internal CoreStructMoveProducer (SourceSpan span, CoreOwnedLocal source) {
		base (span, source.place.semantic_type, StructValueMode.MOVE_VALUE);
		this.source = source;
	}

}

public class CoreStructSnapshot : CoreStructProducer {
	public CorePlace source { get; private set; }
	internal CoreStructSnapshot (SourceSpan span, CorePlace source) {
		base (span, source.semantic_type);
		this.source = source;
	}

}

// Borrowing observes exact storage without acquiring its owner leaves.
// The verifier reconstructs the bounded source and consumer relationship.
public class CoreStructBorrowSnapshot : CoreStructProducer {
	public CorePlace source { get; private set; }
	internal CoreStructBorrowSnapshot (SourceSpan span, CorePlace source) {
		base (span, source.semantic_type, StructValueMode.BORROW_VALUE);
		this.source = source;
	}

}

public class CoreStructProjectionValue : CoreValue {
	public CoreStructProducer source { get; private set; }
	public StructLeafPath path { get; private set; }
	internal CoreStructProjectionValue (SourceSpan span, CoreStructProducer source, StructLeafPath path) {
		base (span, path.semantic_type);
		this.source = source;
		this.path = path;
	}

}

public class CoreStructProjectionProducer : CoreStructProducer {
	public CoreStructProducer source { get; private set; }
	public StructLeafPath path { get; private set; }
	internal CoreStructProjectionProducer (SourceSpan span, CoreStructProducer source, StructLeafPath path) {
		base (span, path.semantic_type);
		this.source = source;
		this.path = path;
	}

}

public class CoreCStructCallResult : CoreStructProducer {
	private WeakRef callee;
	public CoreCFunction? target { owned get { return (CoreCFunction?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }
	internal CoreCStructCallResult (SourceSpan span, CoreCFunction target, GenericArray<CoreValue> arguments) {
		base (span, target.return_type);
		this.callee = WeakRef (target);
		this.arguments = arguments;
	}

}

public class CoreStructInvocationResult : CoreStructProducer {
	public CoreValue invocation { get; private set; }
	internal CoreStructInvocationResult (CoreValue invocation, StructValueMode mode) {
		base (invocation.span, invocation.semantic_type, mode);
		this.invocation = invocation;
	}

}

public class CoreStructCallResult : CoreStructProducer {
	private WeakRef callee;
	public CoreFunction? target { owned get { return (CoreFunction?) callee.get (); } }
	public GenericArray<CoreValue> arguments { get; private set; }
	public CoreValue? receiver { get; private set; }
	public GenericArray<SemanticType>? type_arguments { get; private set; }
	internal CoreStructCallResult (SourceSpan span, SemanticType type, CoreFunction target, GenericArray<CoreValue> arguments, CoreValue? receiver = null, GenericArray<SemanticType>? type_arguments = null) {
		base (span, type, target.struct_result_contract == null ? StructValueMode.COPY_VALUE : target.struct_result_contract.mode);
		this.callee = WeakRef (target);
		this.arguments = arguments;
		this.receiver = receiver;
		this.type_arguments = type_arguments;
	}

}

// Only verify_call accepts this adapter; verify_value rejects it everywhere else.
public class CoreStructArgument : CoreValue {
	public CoreParameter? parameter { get; private set; }
	public CoreStructProducer producer { get; private set; }
	internal CoreStructArgument (SourceSpan span, CoreParameter? parameter, CoreStructProducer producer) {
		base (span, producer.semantic_type);
		this.parameter = parameter;
		this.producer = producer;
	}

}

public class CoreStructResultStore : CoreStatement {
	public CorePlace destination { get; private set; }
	public CoreStructProducer producer { get; private set; }
	public bool initializes_destination { get; private set; }
	internal CoreStructResultStore (SourceSpan span, CorePlace destination, CoreStructProducer producer, bool initializes_destination) {
		base (span);
		this.destination = destination;
		this.producer = producer;
		this.initializes_destination = initializes_destination;
	}

}

public class CoreStructReturn : CoreStatement {
	public CoreStructProducer producer { get; private set; }
	internal CoreStructReturn (SourceSpan span, CoreStructProducer producer) {
		base (span);
		this.producer = producer;
	}

}

public class CoreAcquireStructParameter : CoreStatement {
	public CoreLocalPlace destination { get; private set; }
	public CoreParameter parameter { get; private set; }
	internal CoreAcquireStructParameter (SourceSpan span, CoreLocalPlace destination, CoreParameter parameter) {
		base (span);
		this.destination = destination;
		this.parameter = parameter;
	}

}
}
