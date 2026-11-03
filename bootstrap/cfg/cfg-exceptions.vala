// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Cfg {
// Conditional retirement recipes for the private initialized-field stack.
// Neither a user destructor call nor a read of an uninitialized field.
public class CfgConstructorUnwindField : Object {
	public CfgStructField field { get; private set; }
	public CfgCleanupContract? cleanup { get; private set; }
	public StructValueShape? shape { get; private set; }
	internal CfgConstructorUnwindField (CfgStructField field, CfgCleanupContract? cleanup, StructValueShape? shape = null) {
		this.field = field;
		this.cleanup = cleanup;
		this.shape = shape;
	}

}
public class CfgConstructorAbort : CfgInstruction {
	public CfgReceiverValue receiver { get; private set; }
	public GenericArray<CfgConstructorUnwindField> fields { get; private set; default = new GenericArray<CfgConstructorUnwindField> (); }
	public GenericArray<CfgProperty> lazy_properties { get; private set; default = new GenericArray<CfgProperty> (); }
	internal CfgConstructorAbort (SourceSpan span, CfgReceiverValue receiver) {
		base (span);
		this.receiver = receiver;
	}

}
public class CfgExceptionHandler : Object {
	private WeakRef dispatch_identity;
	private WeakRef matched_identity;
	private WeakRef next_identity;
	public CfgBlock? dispatch { owned get { return (CfgBlock?) dispatch_identity.get (); } }
	public CfgBlock? matched { owned get { return (CfgBlock?) matched_identity.get (); } }
	public CfgBlock? next { owned get { return (CfgBlock?) next_identity.get (); } }
	public CfgExceptionMatch selection { get; private set; }
	public CfgCatchBorrow borrow { get; private set; }
	internal CfgExceptionHandler (CfgBlock dispatch, CfgBlock matched, CfgBlock next, CfgExceptionMatch selection, CfgCatchBorrow borrow) {
		dispatch_identity = WeakRef (dispatch);
		matched_identity = WeakRef (matched);
		next_identity = WeakRef (next);
		this.selection = selection;
		this.borrow = borrow;
	}

}
public class CfgOwnedArgumentAbort : CfgInstruction {
	public CfgPendingOwnedArgument transfer { get; private set; }
	internal CfgOwnedArgumentAbort (SourceSpan span, CfgPendingOwnedArgument transfer) {
		base (span);
		this.transfer = transfer;
	}

}
public class CfgExceptionStorage : CfgTemporaryPlace {
	internal CfgExceptionStorage (SourceSpan span, ClassType root_type, int ordinal) {
		base (span, root_type, ordinal);
	}

}

public class CfgExceptionTake : CfgEvaluateInstruction {
	public CfgLocalPlace owner { get; private set; }
	internal CfgExceptionTake (SourceSpan span, CfgLocalPlace owner) {
		base (span, new CfgLoadValue (span, owner), new CfgEvaluatedValue (span, owner.semantic_type));
		this.owner = owner;
	}

}
public class CfgExceptionStamp : CfgInstruction {
	public CfgValue exception { get; private set; }
	internal CfgExceptionStamp (SourceSpan span, CfgValue exception) {
		base (span);
		this.exception = exception;
	}

}
public class CfgExceptionMatch : CfgValue {
	public CfgValue exception { get; private set; }
	public ClassType match_type { get; private set; }
	internal CfgExceptionMatch (SourceSpan span, SemanticType bool_type, CfgValue exception, ClassType match_type) {
		base (span, bool_type);
		this.exception = exception;
		this.match_type = match_type;
	}

}
public class CfgCatchBorrow : CfgValue {
	public CfgValue exception { get; private set; }
	internal CfgCatchBorrow (SourceSpan span, CfgValue exception, ClassType caught_type) {
		base (span, caught_type);
		this.exception = exception;
	}

}
public class CfgExceptionUnreachable : CfgTerminator {
	public CfgValue exception { get; private set; }
	internal CfgExceptionUnreachable (SourceSpan span, CfgValue exception) {
		base (span);
		this.exception = exception;
	}

	public override GenericArray<CfgBlock> successors() {
		return new GenericArray<CfgBlock> ();
	}

}
public class CfgExceptionReturn : CfgReturn {
	internal CfgExceptionReturn (SourceSpan span, CfgValue exception) {
		base (span, exception);
	}

}
public class CfgGroupCallSuccess : CfgInstruction {
	private WeakRef invocation;
	public CfgCallInstruction? call { owned get { return (CfgCallInstruction?) invocation.get (); } }
	internal CfgGroupCallSuccess (SourceSpan span, CfgCallInstruction call) {
		base (span);
		invocation = WeakRef (call);
	}

}
public class CfgCallSuccess : CfgEvaluateInstruction {
	private WeakRef invocation;
	public CfgCallInstruction? call { owned get { return (CfgCallInstruction?) invocation.get (); } }
	internal CfgCallSuccess (SourceSpan span, CfgCallInstruction call) {
		base (span, call.result, new CfgEvaluatedValue (span, call.result.semantic_type));
		this.invocation = WeakRef (call);
	}

}
public class CfgForeignReturn : CfgFunctionEnd {
	public ForeignImportBinding binding { get; internal set; }
	public CfgFunction factory { get; internal set; }
	public GenericArray<CfgLocalPlace> consumed { get; private set; default = new GenericArray<CfgLocalPlace> (); }
	internal CfgForeignReturn (SourceSpan span, ForeignImportBinding binding, CfgFunction factory, GenericArray<CfgLocalPlace>? consumed = null) {
		base (span);
		this.binding = binding;
		this.factory = factory;
		if (consumed != null) {
			foreach (var owner in consumed) {
				this.consumed.add (owner);
			}
		}
	}

}
public class CfgForeignSignalReturn : CfgFunctionEnd {
	public ForeignSignalBinding binding { get; internal set; }
	internal CfgForeignSignalReturn (SourceSpan span, ForeignSignalBinding binding) {
		base (span);
		this.binding = binding;
	}

}

}
