// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
public class SsaEnumReadRecord : SsaInstruction {
	public SsaEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public EnumBindingIdentity binding { get; private set; }
	public SsaStructCallResults results { get; private set; }
	internal SsaEnumReadRecord (SourceSpan span, SsaEnumSlot source, EnumField field, EnumBindingIdentity binding, SsaStructCallResults results) {
		base (span, null, -1);
		this.source = source;
		this.field = field;
		this.binding = binding;
		this.results = results;
	}

}
public class SsaEnumScalarCapture : SsaInstruction {
	public SsaHeapOwner owner { get; private set; }
	public SsaValue pointer { get; private set; }
	internal SsaEnumScalarCapture (SourceSpan span, SsaHeapOwner owner, SsaValue pointer) {
		base (span, null, -1);
		this.owner = owner;
		this.pointer = pointer;
	}

}
public class SsaEnumScalarAbort : SsaInstruction {
	public SsaEnumScalarCapture capture { get; private set; }
	internal SsaEnumScalarAbort (SourceSpan span, SsaEnumScalarCapture capture) {
		base (span, null, -1);
		this.capture = capture;
	}

}
public class SsaEnumScalarCommit : SsaInstruction {
	public SsaEnumScalarCapture capture { get; private set; }
	public EnumField field { get; private set; }
	private WeakRef target;
	public SsaEnumConstruct? consumer { owned get { return (SsaEnumConstruct?) target.get (); } }
	internal SsaEnumScalarCommit (SourceSpan span, SsaEnumScalarCapture capture, EnumField field, SsaEnumConstruct consumer) {
		base (span, null, -1);
		this.capture = capture;
		this.field = field;
		this.target = WeakRef (consumer);
	}

}
public class SsaEnumReadScalar : SsaInstruction {
	public SsaEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public EnumBindingIdentity binding { get; private set; }
	public SsaHeapOwner owner { get; private set; }
	internal SsaEnumReadScalar (SourceSpan span, SsaEnumSlot source, EnumField field, EnumBindingIdentity binding, SsaHeapOwner owner, int ordinal) {
		base (span, field.semantic_type, ordinal);
		this.source = source;
		this.field = field;
		this.binding = binding;
		this.owner = owner;
	}

}
public class SsaEnumBufferCapture : SsaInstruction {
	public SsaBufferPair pair { get; private set; }
	public SsaBufferPlace place { get; private set; }
	public bool fresh { get; private set; }
	internal SsaEnumBufferCapture (SourceSpan span, SsaBufferPair pair, SsaBufferPlace place, bool fresh) {
		base (span, null, -1);
		this.pair = pair;
		this.place = place;
		this.fresh = fresh;
	}

}
public class SsaEnumBufferAbort : SsaInstruction {
	public SsaEnumBufferCapture capture { get; private set; }
	internal SsaEnumBufferAbort (SourceSpan span, SsaEnumBufferCapture capture) {
		base (span, null, -1);
		this.capture = capture;
	}

}
internal class SsaEnumProjectionContract : Object {
	internal SsaEnumRead instruction;
	private SsaEnumSlot source;
	private EnumField field;
	private EnumBindingIdentity binding;
	private SsaInstructionResult result;
	private string path;
	internal SsaEnumProjectionContract (SsaEnumRead instruction) {
		this.instruction = instruction;
		source = instruction.source;
		field = instruction.field;
		binding = instruction.binding;
		result = instruction.result;
		path = instruction.record_path == null ? "" : instruction.record_path.spelling ();
	}

	internal bool matches() {
		return instruction.source == source && instruction.field == field && instruction.binding == binding && instruction.result == result && (instruction.record_path == null ? "" : instruction.record_path.spelling ()) == path;
	}

}
public class SsaEnumSlot : SsaNode {
	public SsaEnumSlot? reservation_source { get; internal set; }
	public SsaEnumSlot? inspection_root { get; internal set; }
	public int parameter_ordinal { get; private set; }
	public EnumInstanceIdentity instance { get; private set; }
	public EnumDefinition definition { get; private set; }
	public int ordinal { get; private set; }
	public int source_ordinal { get; private set; }
	internal SsaEnumSlot (SourceSpan span, EnumDefinition definition, int ordinal, int source_ordinal = -1, EnumInstanceIdentity? instance = null, int parameter_ordinal = -1) {
		base (span);
		this.instance = instance ?? new EnumInstanceIdentity ();
		this.definition = definition;
		this.ordinal = ordinal;
		this.source_ordinal = source_ordinal;
		this.parameter_ordinal = parameter_ordinal;
	}

}

public class SsaEnumFieldInput : SsaNode {
	public SsaStructBoundaryMove? record_move { get; private set; }
	public SsaEnumScalarCapture? scalar_owner { get; private set; }
	public SsaBufferPair? buffer { get; private set; }
	public EnumField field { get; private set; }
	public GenericArray<SsaValue> leaves { get; private set; }
	public SsaEnumSlot? sum { get; private set; }
	internal SsaEnumFieldInput (SourceSpan span, EnumField field, GenericArray<SsaValue> leaves, SsaEnumSlot? sum = null, SsaBufferPair? buffer = null, SsaEnumScalarCapture? scalar_owner = null, SsaStructBoundaryMove? record_move = null) {
		base (span);
		this.record_move = record_move;
		this.field = field;
		this.leaves = leaves;
		this.sum = sum;
		this.buffer = buffer;
		this.scalar_owner = scalar_owner;
	}

}

public class SsaEnumConstruct : SsaInstruction {
	private GenericArray<SsaEnumFieldInput> input_contract = new GenericArray<SsaEnumFieldInput> ();
	public SsaEnumSlot destination { get; private set; }
	public EnumVariant variant { get; private set; }
	public GenericArray<SsaEnumFieldInput> fields { get; private set; }
	internal SsaEnumConstruct (SourceSpan span, SsaEnumSlot destination, EnumVariant variant, GenericArray<SsaEnumFieldInput> fields) {
		base (span, null, -1);
		this.destination = destination;
		this.variant = variant;
		this.fields = fields;
		foreach (var input in fields) {
			var leaves = new GenericArray<SsaValue> ();
			foreach (var leaf in input.leaves) {
				leaves.add (leaf);
			}
			input_contract.add (new SsaEnumFieldInput (input.span, input.field, leaves, input.sum, input.buffer, input.scalar_owner, input.record_move));
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

public class SsaEnumCopy : SsaInstruction {
	public EnumUse mode { get; private set; }
	public SsaEnumSlot destination { get; private set; }
	public SsaEnumSlot source { get; private set; }
	public bool initializes_destination { get; private set; }
	internal SsaEnumCopy (SourceSpan span, SsaEnumSlot destination, SsaEnumSlot source, bool initializes_destination = true, EnumUse mode = EnumUse.COPY) {
		base (span, null, -1);
		this.destination = destination;
		this.source = source;
		this.initializes_destination = initializes_destination;
		this.mode = mode;
	}

}
public class SsaEnumEndInspection : SsaInstruction {
	public SsaEnumSlot source { get; private set; }
	internal SsaEnumEndInspection (SourceSpan span, SsaEnumSlot source) {
		base (span, null, -1);
		this.source = source;
	}

}

public class SsaEnumCommit : SsaInstruction {
	public SsaEnumSlot captured { get; private set; }
	internal SsaEnumCommit (SourceSpan span, SsaEnumSlot captured) {
		base (span, null, -1);
		this.captured = captured;
	}

}
public class SsaEnumDrop : SsaInstruction {
	public SsaEnumSlot source { get; private set; }
	internal SsaEnumDrop (SourceSpan span, SsaEnumSlot source) {
		base (span, null, -1);
		this.source = source;
	}

}
public class SsaEnumReadBuffer : SsaInstruction {
	public SsaEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public EnumBindingIdentity binding { get; private set; }
	public SsaBufferPair pair { get; private set; }
	internal SsaEnumReadBuffer (SourceSpan span, SsaEnumSlot source, EnumField field, EnumBindingIdentity binding, BufferValueShape shape, int first_ordinal) {
		base (span, null, -1);
		this.source = source;
		this.field = field;
		this.binding = binding;
		pair = new SsaBufferPair.results (span, shape, first_ordinal);
	}

}
public class SsaEnumFinishArm : SsaInstruction {
	public SsaEnumSlot source { get; private set; }
	public EnumVariant? variant { get; private set; }
	private GenericArray<EnumField> retained = new GenericArray<EnumField> ();
	public uint retained_count { get { return retained.length; } }
	public EnumField field(uint ordinal) {
		return retained[ordinal];
	}

	internal SsaEnumFinishArm (SourceSpan span, SsaEnumSlot source, EnumVariant? variant, GenericArray<EnumField> fields) {
		base (span, null, -1);
		this.source = source;
		this.variant = variant;
		foreach (var field in fields) {
			retained.add (field);
		}
	}

}

public class SsaEnumAcquire : SsaInstruction {
	public SsaEnumSlot destination { get; private set; }
	public SsaFunctionParameter parameter { get; private set; }
	internal SsaEnumAcquire (SourceSpan span, SsaEnumSlot destination, SsaFunctionParameter parameter) {
		base (span, null, -1);
		this.destination = destination;
		this.parameter = parameter;
	}

}

public class SsaEnumArgument : SsaValue {
	public SsaEnumSlot source { get; private set; }
	internal SsaEnumArgument (SourceSpan span, SsaEnumSlot source) {
		base (span, source.definition.semantic_type);
		this.source = source;
	}

}

public class SsaEnumTagInstruction : SsaInstruction {
	public SsaEnumSlot source { get; private set; }
	internal SsaEnumTagInstruction (SourceSpan span, SemanticType integer, SsaEnumSlot source, int ordinal) {
		base (span, integer, ordinal);
		this.source = source;
	}

}

public class SsaEnumRead : SsaInstruction {
	public EnumBindingIdentity binding { get; private set; }
	public SsaEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public StructLeafPath? record_path { get; private set; }
	internal SsaEnumRead (SourceSpan span, SsaEnumSlot source, EnumField field, int ordinal, EnumBindingIdentity binding, StructLeafPath? record_path = null) {
		base (span, record_path == null ? field.semantic_type : record_path.semantic_type, ordinal);
		this.binding = binding;
		this.source = source;
		this.field = field;
		this.record_path = record_path;
	}

}

public class SsaEnumExtractSum : SsaInstruction {
	public EnumBindingIdentity binding { get; private set; }
	public SsaEnumSlot source { get; private set; }
	public EnumField field { get; private set; }
	public SsaEnumSlot destination { get; private set; }
	internal SsaEnumExtractSum (SourceSpan span, SsaEnumSlot source, EnumField field, SsaEnumSlot destination, EnumBindingIdentity binding) {
		base (span, null, -1);
		this.binding = binding;
		this.source = source;
		this.field = field;
		this.destination = destination;
	}

}

public class SsaEnumReturn : SsaReturn {
	public SsaEnumSlot source { get; private set; }
	internal SsaEnumReturn (SourceSpan span, SsaEnumSlot source) {
		base (span, null);
		this.source = source;
	}

}

public class SsaEnumCase : Object {
	public EnumVariant variant { get; private set; }
	public SsaEdge edge { get; private set; }
	internal SsaEnumCase (EnumVariant variant, SsaEdge edge) {
		this.variant = variant;
		this.edge = edge;
	}

}

public class SsaEnumDispatch : SsaTerminator {
	public SsaEnumSlot source { get; private set; }
	public GenericArray<SsaEnumCase> cases { get; private set; }
	public SsaEdge invalid_edge { get; private set; }
	internal SsaEnumDispatch (SourceSpan span, SsaEnumSlot source, GenericArray<SsaEnumCase> cases, SsaEdge invalid_edge) {
		base (span);
		this.source = source;
		this.cases = cases;
		this.invalid_edge = invalid_edge;
	}

}

public class SsaEnumInvalidTag : SsaTerminator {
	internal SsaEnumInvalidTag (SourceSpan span) {
		base (span);
	}

}
}
