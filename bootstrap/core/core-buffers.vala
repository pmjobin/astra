// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
public class CoreScopedAllocator : CoreValue {
	public ScopedBackingLoan loan { get; private set; }
	public CoreLocalPlace backing { get; private set; }
	public CoreValue kind { get; private set; }
	public CoreValue slots { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	internal CoreScopedAllocator (SourceSpan span, HandleType type, ScopedBackingLoan loan, CoreLocalPlace backing, CoreValue kind, CoreValue slots, CoreCleanupContract cleanup) {
		base (span, type);
		this.loan = loan;
		this.backing = backing;
		this.kind = kind;
		this.slots = slots;
		this.cleanup = cleanup;
	}
}
public class CoreSlotsRecordTransfer : CoreStatement {
	public CoreIndirectFieldPlace store { get; private set; }
	public CoreValue? index { get; private set; }
	public CoreStructProducer value { get; private set; }
	internal CoreSlotsRecordTransfer (SourceSpan span, CoreIndirectFieldPlace store, CoreValue? index, CoreStructProducer value) {
		base (span);
		this.store = store;
		this.index = index;
		this.value = value;
	}
}
public class CoreSlotsRecordRead : CoreStructProducer {
	public CoreIndirectFieldPlace store { get; private set; }
	public CoreValue index { get; private set; }
	public bool remove { get; private set; }
	internal CoreSlotsRecordRead (SourceSpan span, CoreIndirectFieldPlace store, CoreValue index, bool remove, StructValueMode mode = StructValueMode.COPY_VALUE) {
		base (span, ((OwnerSlotsType) store.semantic_type).element, mode);
		this.store = store;
		this.index = index;
		this.remove = remove;
	}
}
// A bounded owner slot proof; not a mutable reference or an owned value.
public class CoreBufferOwnerSlot : CoreNode {
	public CorePlace place { get; private set; }
	public CoreOwnedLocal? owner { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	internal CoreBufferOwnerSlot (SourceSpan span, CorePlace place, CoreOwnedLocal? owner, CoreCleanupContract cleanup) {
		base (span);
		this.place = place;
		this.owner = owner;
		this.cleanup = cleanup;
	}
}

public class CoreOwnedBufferExchange : CoreStatement {
	public CoreBufferOwnerSlot left { get; private set; }
	public CoreBufferOwnerSlot right { get; private set; }
	internal CoreOwnedBufferExchange (SourceSpan span, CoreBufferOwnerSlot left, CoreBufferOwnerSlot right) {
		base (span);
		this.left = left;
		this.right = right;
	}
}

public class CoreOwnedBufferAllocate : CoreValue {
	public CoreValue? allocation_context { get; private set; }
	public CoreValue count { get; private set; }
	public CoreCleanupContract cleanup { get; private set; }
	public CoreStatement? failure_call { get; private set; }
	public bool zero_initializes { get { return true; } }
	internal CoreOwnedBufferAllocate (SourceSpan span, SliceType type, CoreValue count, CoreCleanupContract cleanup, CoreStatement? failure_call = null, CoreValue? allocation_context = null) {
		base (span, type);
		this.count = count;
		this.cleanup = cleanup;
		this.failure_call = failure_call;
		this.allocation_context = allocation_context;
	}
}

public class CoreOwnedBufferBorrow : CoreValue {
	public CoreOwnedLocal source { get; private set; }
	public CoreParameter? parameter { get; private set; }
	internal CoreOwnedBufferBorrow (SourceSpan span, CoreOwnedLocal source, CoreParameter? parameter) {
		base (span, ContextBytesType.borrowed_type (source.place.semantic_type, parameter == null ? null : parameter.semantic_type));
		this.source = source;
		this.parameter = parameter;
	}
}
}

namespace Astra.Core {
public class CoreSlotsInitialize : CoreStatement {
	public CoreIndirectFieldPlace store { get; private set; }
	internal CoreSlotsInitialize (SourceSpan span, CoreIndirectFieldPlace store) {
		base (span);
		this.store = store;
	}
}
public class CoreSlotsTake : CoreValue {
	public CoreIndirectFieldPlace store { get; private set; }
	public CoreValue index { get; private set; }
	internal CoreSlotsTake (SourceSpan span, CoreIndirectFieldPlace store, CoreValue index) {
		base (span, ((OwnerSlotsType) store.semantic_type).element);
		this.store = store;
		this.index = index;
	}
}
public class CoreSlotsReplace : CoreStatement {
	public CoreIndirectFieldPlace store { get; private set; }
	public CoreValue index { get; private set; }
	public CoreOwnedLocal incoming { get; private set; }
	internal CoreSlotsReplace (SourceSpan span, CoreIndirectFieldPlace store, CoreValue index, CoreOwnedLocal incoming) {
		base (span);
		this.store = store;
		this.index = index;
		this.incoming = incoming;
	}
}
public class CoreSlotsAppend : CoreStatement {
	public CoreIndirectFieldPlace store { get; private set; }
	public CoreOwnedLocal incoming { get; private set; }
	internal CoreSlotsAppend (SourceSpan span, CoreIndirectFieldPlace store, CoreOwnedLocal incoming) {
		base (span);
		this.store = store;
		this.incoming = incoming;
	}
}
public class CoreSlotsValue : CoreValue {
	public bool has_iteration { get; private set; }
	public CoreIterationContract? iteration { get; internal set; }
	public CoreIndirectFieldPlace store { get; private set; }
	public OwnerSlotsAction action { get; private set; }
	public CoreValue? operand { get; private set; }
	public CoreParameter? borrower { get; private set; }
	internal CoreSlotsValue (SourceSpan span, SemanticType type, CoreIndirectFieldPlace store, OwnerSlotsAction action, CoreValue? operand = null, CoreParameter? borrower = null, CoreIterationContract? iteration = null) {
		base (span, type);
		this.store = store;
		this.action = action;
		this.operand = operand;
		this.borrower = borrower;
		this.iteration = iteration;
		this.has_iteration = iteration != null;
	}
}
}
