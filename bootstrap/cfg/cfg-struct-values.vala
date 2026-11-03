// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
public class CfgStructBorrowResultArgument : StructBoundaryGroup {
	public CfgStructCallResults results { get; private set; }
	internal CfgStructBorrowResultArgument (int source_ordinal, int first_leaf, StructValueShape shape, CfgStructCallResults results) {
		base (source_ordinal, first_leaf, shape);
		this.results = results;
	}

}

public class CfgStructBorrowArgument : StructBoundaryGroup {
	public CfgLocalPlace source { get; private set; }
	internal CfgStructBorrowArgument (int source_ordinal, int first_leaf, StructValueShape shape, CfgLocalPlace source) {
		base (source_ordinal, first_leaf, shape);
		this.source = source;
	}

}

// Bind an incoming complete tuple as an observation. Unlike an acquisition,
// this event grants no cleanup or storage mutation authority.
public class CfgStructParameterBorrow : CfgInstruction {
	public CfgLocalPlace destination { get; private set; }
	public StructBoundaryGroup parameter { get; private set; }
	public GenericArray<CfgValue> leaves { get; private set; }
	internal CfgStructParameterBorrow (SourceSpan span, CfgLocalPlace destination, StructBoundaryGroup parameter, GenericArray<CfgValue> leaves) {
		base (span);
		this.destination = destination;
		this.parameter = parameter;
		this.leaves = leaves;
	}

}

// A complete inline record field changes responsibility as one language
// effect. Inputs are captured before replacement retires the old payload.
public class CfgRecordFieldCommit : CfgInstruction {
	public CfgIndirectFieldPlace destination { get; private set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<CfgValue> leaves { get; private set; }
	public bool initializes { get; private set; }
	public CfgStructBoundaryMove? record_move { get; internal set; }
	public CfgStructCallResults? results { get; private set; }
	internal CfgRecordFieldCommit (SourceSpan span, CfgIndirectFieldPlace destination, StructValueShape shape,
	                               GenericArray<CfgValue> leaves, bool initializes, CfgStructCallResults? results) {
		base (span);
		this.destination = destination;
		this.shape = shape;
		this.leaves = leaves;
		this.initializes = initializes;
		this.results = results;
	}

}

public class CfgRecordFieldDrop : CfgInstruction {
	public CfgIndirectFieldPlace source { get; private set; }
	public StructValueShape shape { get; private set; }
	internal CfgRecordFieldDrop (SourceSpan span, CfgIndirectFieldPlace source, StructValueShape shape) {
		base (span);
		this.source = source;
		this.shape = shape;
	}

}

public class CfgRecordBufferCapture : CfgEvaluateInstruction {
	public CfgFieldPlace field { get; private set; }
	internal CfgRecordBufferCapture (SourceSpan span, CfgFieldPlace field, CfgEvaluatedValue result) {
		base (span, new CfgLoadValue (span, field), result);
		this.field = field;
	}

}
// A complete record boundary acquires every declaration leaf atomically.
// Parameter and result identities are checked independently in CFG.
public class CfgStructBoundaryAcquire : CfgInstruction {
	public CfgLocalPlace destination { get; private set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<CfgValue> leaves { get; private set; }
	public StructBoundaryGroup? parameter { get; private set; }
	public CfgStructCallResults? results { get; private set; }
	public CfgFieldPlace? projection { get; private set; }
	public CfgPlace target { get { return projection == null ? (CfgPlace) destination : projection; } }
	public CfgStructBoundaryMove? record_move { get; internal set; }
	public bool contains(CfgFieldPlace field) {
		CfgPlace ancestor = field;
		while (ancestor is CfgFieldPlace && ancestor != target) {
			ancestor = ((CfgFieldPlace) ancestor).aggregate;
		}
		return ancestor == target;
	}

	internal CfgStructBoundaryAcquire (SourceSpan span, CfgLocalPlace destination, StructValueShape shape, GenericArray<CfgValue> leaves, StructBoundaryGroup? parameter = null, CfgStructCallResults? results = null, CfgFieldPlace? projection = null) {
		base (span);
		this.destination = destination;
		this.shape = shape;
		this.leaves = leaves;
		this.parameter = parameter;
		this.results = results;
		this.projection = projection;
	}

}

public class CfgStructBoundaryMove : CfgInstruction {
	public CfgLocalPlace source { get; private set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<CfgValue> leaves { get; private set; }
	public StructResultUseKind use_kind { get; private set; }
	private WeakRef target;
	public CfgNode? consumer { owned get { return (CfgNode?) target.get (); } internal set { target = WeakRef (value); } }
	internal CfgStructBoundaryMove (SourceSpan span, CfgLocalPlace source, StructValueShape shape, GenericArray<CfgValue> leaves, StructResultUseKind use_kind) {
		base (span);
		this.source = source;
		this.shape = shape;
		this.leaves = leaves;
		this.use_kind = use_kind;
	}

}
// One call owns N ordinary leaf definitions. This group is never a CfgValue.
public class CfgStructInvoke : CfgInstruction {
	public CfgValue call { get; private set; }
	public CfgStructCallResults results { get; private set; }
	public CfgCheckedClosureInvoke? checked_call { get; private set; }
	internal CfgStructInvoke (SourceSpan span, CfgValue call, CfgStructCallResults results, CfgCheckedClosureInvoke? checked_call = null) {
		base (span);
		this.call = call;
		this.results = results;
		this.checked_call = checked_call;
	}

}

public class CfgStructCallResults : CfgNode {
	public StructValueShape shape { get; private set; }
	public GenericArray<CfgCallResultValue> leaves { get; private set; default = new GenericArray<CfgCallResultValue> (); }
	internal CfgStructCallResults (SourceSpan span, StructValueShape shape) {
		base (span);
		this.shape = shape;
		foreach (var leaf in shape.leaves) {
			leaves.add (new CfgCallResultValue (span, leaf.semantic_type));
		}
	}

}
// A nonowning Slice descriptor selected from one complete borrowed record.
public class CfgRecordBufferView : CfgValue {
	public CfgStructCallResults group { get; private set; }
	public CfgCallResultValue source { get; private set; }
	internal CfgRecordBufferView (SourceSpan span, CfgStructCallResults group, CfgCallResultValue source) {
		base (span, source.semantic_type);
		this.group = group;
		this.source = source;
	}

}
public class CfgRecordParameterBufferView : CfgValue {
	public CfgFieldPlace field { get; private set; }
	public CfgEvaluatedValue source { get; private set; }
	public StructBoundaryGroup parameter { get; private set; }
	internal CfgRecordParameterBufferView (SourceSpan span, CfgFieldPlace field, CfgEvaluatedValue source, StructBoundaryGroup parameter) {
		base (span, field.semantic_type);
		this.field = field;
		this.source = source;
		this.parameter = parameter;
	}

}

// Complete bounded consumption, including copies that later promote away.
// It has no result and performs no memory access itself.
public class CfgStructResultConsume : CfgInstruction {
	public CfgStructCallResults results { get; private set; }
	public StructResultUseKind use_kind { get; private set; }
	public CfgPlace? destination { get; private set; }
	internal CfgStructResultConsume (SourceSpan span, CfgStructCallResults results, StructResultUseKind use_kind, CfgPlace? destination = null) {
		base (span);
		this.results = results;
		this.use_kind = use_kind;
		this.destination = destination;
	}

}

public class CfgStructReturn : CfgReturn {
	public CfgStructBoundaryMove? record_move { get; internal set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<CfgValue> leaves { get; private set; }
	internal CfgStructReturn (SourceSpan span, StructValueShape shape, GenericArray<CfgValue> leaves) {
		base (span, null);
		this.shape = shape;
		this.leaves = leaves;
	}

}
}
