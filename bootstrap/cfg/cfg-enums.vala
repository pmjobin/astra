// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
public class CfgEnumExtractRecord : CfgInstruction {
	public CfgEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public CfgLocalPlace destination { get; private set; }
	public EnumBindingIdentity binding { get; private set; }
	public CfgStructCallResults results { get; private set; }
	internal CfgEnumExtractRecord (SourceSpan span, CfgEnumSlot source, EnumField field, CfgLocalPlace destination, EnumBindingIdentity binding, StructValueShape shape) {
		base (span);
		this.source = source;
		this.field = field;
		this.destination = destination;
		this.binding = binding;
		results = new CfgStructCallResults (span, shape);
	}
}
public class CfgEnumScalarCapture : CfgEvaluateInstruction {
	public CfgLocalPlace source { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }
	internal CfgEnumScalarCapture (SourceSpan span, CfgLocalPlace source, CfgCleanupContract cleanup, CfgEvaluatedValue result) {
		base (span, new CfgLoadValue (span, source), result);
		this.source = source;
		this.cleanup = cleanup;
	}
}
public class CfgEnumScalarAbort : CfgInstruction {
	public CfgEnumScalarCapture capture { get; private set; }
	internal CfgEnumScalarAbort (SourceSpan span, CfgEnumScalarCapture capture) {
		base (span);
		this.capture = capture;
	}
}
public class CfgEnumBufferCapture : CfgInstruction {
	public bool fresh_staged { get; private set; }
	public CfgLocalPlace? source { get; private set; }
	public CfgValue? producer { get; private set; }
	public CfgCleanupContract cleanup { get; private set; }
	internal CfgEnumBufferCapture (SourceSpan span, CfgCleanupContract cleanup, CfgLocalPlace? source, CfgValue? producer, bool fresh_staged = false) {
		base (span);
		this.cleanup = cleanup;
		this.source = source;
		this.producer = producer;
		this.fresh_staged = fresh_staged;
	}
}
public class CfgEnumBufferAbort : CfgInstruction {
	public CfgEnumBufferCapture capture { get; private set; }
	internal CfgEnumBufferAbort (SourceSpan span, CfgEnumBufferCapture capture) {
		base (span);
		this.capture = capture;
	}
}
public class CfgEnumSlot : CfgNode {
	public CfgEnumSlot? reservation_source { get; internal set; }
	public CfgEnumSlot? inspection_root { get; internal set; }
	public EnumInstanceIdentity instance { get; private set; }
	public EnumDefinition definition { get; private set; }
	public int ordinal { get; private set; }
	public CfgLocalPlace? local { get; private set; }
	internal CfgEnumSlot (SourceSpan span, EnumDefinition definition, int ordinal, CfgLocalPlace? local = null, EnumInstanceIdentity? instance = null) {
		base (span);
		this.instance = instance ?? new EnumInstanceIdentity ();
		this.definition = definition;
		this.ordinal = ordinal;
		this.local = local;
	}
}

public class CfgEnumFieldInput : CfgNode {
	public CfgStructBoundaryMove? record_move { get; private set; }
	public CfgEnumScalarCapture? scalar_owner { get; private set; }
	public CfgEnumBufferCapture? buffer { get; private set; }
	public EnumField field { get; private set; }
	public GenericArray<CfgValue> leaves { get; private set; }
	public CfgEnumSlot? sum { get; private set; }
	internal CfgEnumFieldInput (SourceSpan span, EnumField field, GenericArray<CfgValue> leaves, CfgEnumSlot? sum = null, CfgEnumBufferCapture? buffer = null, CfgEnumScalarCapture? scalar_owner = null, CfgStructBoundaryMove? record_move = null) {
		base (span);
		this.record_move = record_move;
		this.field = field;
		this.leaves = leaves;
		this.sum = sum;
		this.buffer = buffer;
		this.scalar_owner = scalar_owner;
	}
}

public class CfgEnumConstruct : CfgInstruction {
	private GenericArray<CfgEnumFieldInput> input_contract = new GenericArray<CfgEnumFieldInput> ();
	public CfgEnumSlot destination { get; private set; }
	public EnumVariant variant { get; private set; }
	public GenericArray<CfgEnumFieldInput> fields { get; private set; }
	internal CfgEnumConstruct (SourceSpan span, CfgEnumSlot destination, EnumVariant variant, GenericArray<CfgEnumFieldInput> fields) {
		base (span);
		this.destination = destination;
		this.variant = variant;
		this.fields = fields;
		foreach (var input in fields) {
			var leaves = new GenericArray<CfgValue> ();
			foreach (var leaf in input.leaves) {
				leaves.add (leaf);
			}
			input_contract.add (new CfgEnumFieldInput (input.span, input.field, leaves, input.sum, input.buffer, input.scalar_owner, input.record_move));
		}
	}
	internal bool matches_inputs() {
		if (fields.length != input_contract.length) {
			return false;
		}
		for (int i = 0; i < fields.length; i++) {
			var actual = fields[i];
			var expected = input_contract[i];
			if (actual.field != expected.field || actual.sum != expected.sum || actual.buffer != expected.buffer || actual.scalar_owner != expected.scalar_owner || actual.record_move != expected.record_move || actual.leaves.length != expected.leaves.length) {
				return false;
			}
			for (int l = 0; l < actual.leaves.length; l++) {
				if (actual.leaves[l] != expected.leaves[l]) {
					return false;
				}
			}
		}
		return true;
	}
}

public class CfgEnumCopy : CfgInstruction {
	public EnumUse mode { get; private set; }
	public CfgEnumSlot destination { get; private set; }
	public CfgEnumSlot source { get; private set; }
	public bool initializes_destination { get; private set; }
	internal CfgEnumCopy (SourceSpan span, CfgEnumSlot destination, CfgEnumSlot source, bool initializes_destination = true, EnumUse mode = EnumUse.COPY) {
		base (span);
		this.destination = destination;
		this.source = source;
		this.initializes_destination = initializes_destination;
		this.mode = mode;
	}
}
public class CfgEnumEndInspection : CfgInstruction {
	public CfgEnumSlot source { get; private set; }
	internal CfgEnumEndInspection (SourceSpan span, CfgEnumSlot source) {
		base (span);
		this.source = source;
	}
}

public class CfgEnumCommit : CfgInstruction {
	public CfgEnumSlot captured { get; private set; }
	internal CfgEnumCommit (SourceSpan span, CfgEnumSlot captured) {
		base (span);
		this.captured = captured;
	}
}
public class CfgEnumDrop : CfgInstruction {
	public CfgEnumSlot source { get; private set; }
	internal CfgEnumDrop (SourceSpan span, CfgEnumSlot source) {
		base (span);
		this.source = source;
	}
}
public class CfgEnumExtractBuffer : CfgInstruction {
	public CfgEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public CfgLocalPlace destination { get; private set; }
	public EnumBindingIdentity binding { get; private set; }
	internal CfgEnumExtractBuffer (SourceSpan span, CfgEnumSlot source, EnumField field, CfgLocalPlace destination, EnumBindingIdentity binding) {
		base (span);
		this.source = source;
		this.field = field;
		this.destination = destination;
		this.binding = binding;
	}
}
public class CfgEnumExtractScalar : CfgInstruction {
	public CfgEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public CfgLocalPlace destination { get; private set; }
	public EnumBindingIdentity binding { get; private set; }
	internal CfgEnumExtractScalar (SourceSpan span, CfgEnumSlot source, EnumField field, CfgLocalPlace destination, EnumBindingIdentity binding) {
		base (span);
		this.source = source;
		this.field = field;
		this.destination = destination;
		this.binding = binding;
	}
}
public class CfgEnumFinishArm : CfgInstruction {
	public CfgEnumSlot source { get; private set; }
	public EnumVariant? variant { get; private set; }
	private GenericArray<EnumField> retained = new GenericArray<EnumField> ();
	public uint retained_count { get { return retained.length; } }
	public EnumField field(uint ordinal) {
		return retained[ordinal];
	}
	internal CfgEnumFinishArm (SourceSpan span, CfgEnumSlot source, EnumVariant? variant, GenericArray<EnumField> fields) {
		base (span);
		this.source = source;
		this.variant = variant;
		foreach (var field in fields) {
			retained.add (field);
		}
	}
}

public class CfgEnumAcquire : CfgInstruction {
	public CfgEnumSlot destination { get; private set; }
	public CfgParameter parameter { get; private set; }
	internal CfgEnumAcquire (SourceSpan span, CfgEnumSlot destination, CfgParameter parameter) {
		base (span);
		this.destination = destination;
		this.parameter = parameter;
	}
}

public class CfgEnumArgument : CfgValue {
	public CfgEnumSlot source { get; private set; }
	internal CfgEnumArgument (SourceSpan span, CfgEnumSlot source) {
		base (span, source.definition.semantic_type);
		this.source = source;
	}
}

public class CfgEnumTag : CfgValue {
	public CfgEnumSlot source { get; private set; }
	internal CfgEnumTag (SourceSpan span, SemanticType integer, CfgEnumSlot source) {
		base (span, integer);
		this.source = source;
	}
}

public class CfgEnumPayloadValue : CfgValue {
	public EnumBindingIdentity binding { get; private set; }
	public CfgEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public StructLeafPath? record_path { get; private set; }
	internal CfgEnumPayloadValue (SourceSpan span, CfgEnumSlot source, EnumField field, EnumBindingIdentity binding, StructLeafPath? record_path = null) {
		base (span, record_path == null ? field.semantic_type : record_path.semantic_type);
		this.binding = binding;
		this.source = source;
		this.field = field;
		this.record_path = record_path;
	}
}

public class CfgEnumExtractSum : CfgInstruction {
	public EnumBindingIdentity binding { get; private set; }
	public CfgEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public CfgEnumSlot destination { get; private set; }
	internal CfgEnumExtractSum (SourceSpan span, CfgEnumSlot source, EnumField field, CfgEnumSlot destination, EnumBindingIdentity binding) {
		base (span);
		this.binding = binding;
		this.source = source;
		this.field = field;
		this.destination = destination;
	}
}

public class CfgEnumReturn : CfgReturn {
	public CfgEnumSlot source { get; private set; }
	internal CfgEnumReturn (SourceSpan span, CfgEnumSlot source) {
		base (span, null);
		this.source = source;
	}
}

public class CfgEnumCase : Object {
	public EnumVariant variant { get; private set; }
	private WeakRef successor;
	public CfgBlock? target { owned get { return (CfgBlock?) successor.get (); } }
	internal CfgEnumCase (EnumVariant variant, CfgBlock target) {
		this.variant = variant;
		successor = WeakRef (target);
	}
}

public class CfgEnumDispatch : CfgTerminator {
	public CfgEnumSlot source { get; private set; }
	public GenericArray<CfgEnumCase> cases { get; private set; }
	private WeakRef failure;
	public CfgBlock? invalid_target { owned get { return (CfgBlock?) failure.get (); } }
	internal CfgEnumDispatch (SourceSpan span, CfgEnumSlot source, GenericArray<CfgEnumCase> cases, CfgBlock invalid_target) {
		base (span);
		this.source = source;
		this.cases = cases;
		failure = WeakRef (invalid_target);
	}
	public override GenericArray<CfgBlock> successors() {
		var result = new GenericArray<CfgBlock> ();
		foreach (var branch in cases) {
			if (branch.target != null) {
				result.add (branch.target);
			}
		}
		if (invalid_target != null) {
			result.add (invalid_target);
		}
		return result;
	}
}

public class CfgEnumInvalidTag : CfgTerminator {
	internal CfgEnumInvalidTag (SourceSpan span) {
		base (span);
	}
	public override GenericArray<CfgBlock> successors() {
		return new GenericArray<CfgBlock> ();
	}
}
}
