// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public class CheckedScopedAllocator : CheckedExpression {
	public ScopedBackingLoan loan { get; private set; }
	public LocalSymbol backing { get; private set; }
	public CheckedExpression kind { get; private set; }
	public CheckedExpression slots { get; private set; }
	public Astra.Foreign.CForeignCleanupContract cleanup { get; private set; }
	internal CheckedScopedAllocator (SourceSpan span, HandleType type, ScopedBackingLoan loan, LocalSymbol backing, CheckedExpression kind, CheckedExpression slots, Astra.Foreign.CForeignCleanupContract cleanup) {
		base (span, type);
		this.loan = loan;
		this.backing = backing;
		this.kind = kind;
		this.slots = slots;
		this.cleanup = cleanup;
	}

}
public class CheckedSlotsRecordTransfer : CheckedStatement {
	public CheckedPlace store { get; private set; }
	public CheckedExpression? index { get; private set; }
	public CheckedStructProducer value { get; private set; }
	internal CheckedSlotsRecordTransfer (SourceSpan span, CheckedPlace store, CheckedExpression? index, CheckedStructProducer value) {
		base (span);
		this.store = store;
		this.index = index;
		this.value = value;
	}

}
public class CheckedSlotsRecordRead : CheckedStructProducer {
	public CheckedPlace store { get; private set; }
	public CheckedExpression index { get; private set; }
	public bool remove { get; private set; }
	internal CheckedSlotsRecordRead (SourceSpan span, CheckedPlace store, CheckedExpression index, bool remove, StructValueMode mode = StructValueMode.COPY_VALUE) {
		base (span, ((OwnerSlotsType) store.semantic_type).element, mode == StructValueMode.COPY_VALUE ? Copyability.COPYABLE : Copyability.NOT_COPYABLE, mode);
		this.store = store;
		this.index = index;
		this.remove = remove;
	}

}
// Storage responsibility, never a slice view or a transferable value.
public class CheckedBufferOwnerSlot : CheckedNode {
	public CheckedPlace place { get; private set; }
	public LocalSymbol? owner { get; private set; }
	public StructFieldSymbol? field { get; private set; }
	internal CheckedBufferOwnerSlot (SourceSpan span, CheckedPlace place, LocalSymbol? owner, StructFieldSymbol? field) {
		base (span);
		this.place = place;
		this.owner = owner;
		this.field = field;
	}

}

public class CheckedOwnedBufferExchange : CheckedStatement {
	public CheckedBufferOwnerSlot left { get; private set; }
	public CheckedBufferOwnerSlot right { get; private set; }
	internal CheckedOwnedBufferExchange (SourceSpan span, CheckedBufferOwnerSlot left, CheckedBufferOwnerSlot right) {
		base (span);
		this.left = left;
		this.right = right;
	}

}

// Owning producer over the canonical SliceType; never a persistent view.
public class CheckedOwnedBufferAllocate : CheckedExpression {
	public CheckedExpression? allocation_context { get; private set; }
	public CheckedExpression count { get; private set; }
	public CheckedCallStatement? failure_call { get; private set; }
	public bool zero_initializes { get { return true; } }
	internal CheckedOwnedBufferAllocate (SourceSpan span, SliceType type, CheckedExpression count, CheckedCallStatement? failure_call = null, CheckedExpression? allocation_context = null) {
		base (span, type);
		this.count = count;
		this.failure_call = failure_call;
		this.allocation_context = allocation_context;
	}

}

public class CheckedOwnedBufferBorrow : CheckedExpression {
	public LocalSymbol source { get; private set; }
	public ParameterSymbol? parameter { get; private set; }
	internal CheckedOwnedBufferBorrow (SourceSpan span, LocalSymbol source, ParameterSymbol? parameter) {
		base (span, ContextBytesType.borrowed_type (source.semantic_type, parameter == null ? null : parameter.semantic_type));
		this.source = source;
		this.parameter = parameter;
	}

}

public class CheckedOwnedBufferReplace : CheckedStatement {
	public LocalSymbol owner { get; private set; }
	public CheckedExpression incoming { get; private set; }
	internal CheckedOwnedBufferReplace (SourceSpan span, LocalSymbol owner, CheckedExpression incoming) {
		base (span);
		this.owner = owner;
		this.incoming = incoming;
	}

}
}

namespace Astra.Semantic {
public class CheckedSlotsTake : CheckedExpression {
	public CheckedPlace store { get; private set; }
	public CheckedExpression index { get; private set; }
	public ClassSymbol? element { get; private set; }
	public Astra.Foreign.CForeignCleanupContract? resource_cleanup { get; private set; }
	internal CheckedSlotsTake (SourceSpan span, CheckedPlace store, CheckedExpression index, SemanticType type, ClassSymbol? element, Astra.Foreign.CForeignCleanupContract? resource_cleanup = null) {
		base (span, type);
		this.store = store;
		this.index = index;
		this.element = element;
		this.resource_cleanup = resource_cleanup;
	}

}
public class CheckedSlotsInitialize : CheckedStatement {
	public CheckedPlace store { get; private set; }
	internal CheckedSlotsInitialize (SourceSpan span, CheckedPlace store) {
		base (span);
		this.store = store;
	}

}
public class CheckedSlotsReplace : CheckedStatement {
	public CheckedPlace store { get; private set; }
	public CheckedExpression index { get; private set; }
	public CheckedOwnershipMove incoming { get; private set; }
	internal CheckedSlotsReplace (SourceSpan span, CheckedPlace store, CheckedExpression index, CheckedOwnershipMove incoming) {
		base (span);
		this.store = store;
		this.index = index;
		this.incoming = incoming;
	}

}
public class CheckedSlotsAppend : CheckedStatement {
	public CheckedPlace store { get; private set; }
	public CheckedOwnershipMove incoming { get; private set; }
	internal CheckedSlotsAppend (SourceSpan span, CheckedPlace store, CheckedOwnershipMove incoming) {
		base (span);
		this.store = store;
		this.incoming = incoming;
	}

}
public class CheckedSlotsValue : CheckedExpression {
	public bool has_iteration { get; private set; }
	public CheckedIterationContract? iteration { get; internal set; }
	public CheckedPlace store { get; private set; }
	public OwnerSlotsAction action { get; private set; }
	public CheckedExpression? operand { get; private set; }
	public ParameterSymbol? borrower { get; private set; }
	internal CheckedSlotsValue (SourceSpan span, SemanticType type, CheckedPlace store, OwnerSlotsAction action, CheckedExpression? operand = null, ParameterSymbol? borrower = null, CheckedIterationContract? iteration = null) {
		base (span, type);
		this.store = store;
		this.action = action;
		this.operand = operand;
		this.borrower = borrower;
		this.iteration = iteration;
		this.has_iteration = iteration != null;
	}

	public StructFieldSymbol field { get { return (store is CheckedReceiverFieldPlace) ? ((CheckedReceiverFieldPlace) store).field : ((CheckedObjectFieldPlace) store).field; } }
}
}
