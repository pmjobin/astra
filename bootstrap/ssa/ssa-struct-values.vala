// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Ssa {
public class SsaStructBorrowResultArgument : StructBoundaryGroup {
	public SsaStructCallResults results { get; private set; }
	internal SsaStructBorrowResultArgument (int source_ordinal, int first_leaf, StructValueShape shape, SsaStructCallResults results) {
		base (source_ordinal, first_leaf, shape);
		this.results = results;
	}

}

public class SsaStructBorrowArgument : StructBoundaryGroup {
	public SsaStruct record_type { get; private set; }
	public int source_local_ordinal { get; private set; }
	public StructBoundaryGroup? incoming { get; private set; }
	public GenericArray<SsaHeapOwner> owners { get; private set; default = new GenericArray<SsaHeapOwner> (); }
	public GenericArray<SsaBufferBorrowInstruction> buffers { get; private set; default = new GenericArray<SsaBufferBorrowInstruction> (); }
	private GenericArray<int> owner_leaves = new GenericArray<int> ();
	public int owner_leaf(int index) {
		return owner_leaves[index];
	}

	internal void add_owner(SsaHeapOwner owner, int leaf) {
		owners.add (owner);
		owner_leaves.add (leaf);
	}

	internal SsaStructBorrowArgument (int source_ordinal, int first_leaf, StructValueShape shape, SsaStruct record_type, int source_local_ordinal, StructBoundaryGroup? incoming) {
		base (source_ordinal, first_leaf, shape);
		this.record_type = record_type;
		this.source_local_ordinal = source_local_ordinal;
		this.incoming = incoming;
	}

}

public class SsaStructParameterBorrow : SsaInstruction {
	public StructBoundaryGroup parameter { get; private set; }
	public GenericArray<SsaValue> leaves { get; private set; }
	public GenericArray<SsaBufferPair> buffers { get; private set; default = new GenericArray<SsaBufferPair> (); }
	internal SsaStructParameterBorrow (SourceSpan span, StructBoundaryGroup parameter, GenericArray<SsaValue> leaves) {
		base (span, null, -1);
		this.parameter = parameter;
		this.leaves = leaves;
	}

}

public class SsaRecordFieldCommit : SsaInstruction {
	public SsaIndirectFieldPlace destination { get; private set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<SsaValue> leaves { get; private set; }
	public bool initializes { get; private set; }
	public SsaStructBoundaryMove? record_move { get; internal set; }
	public SsaStructCallResults? results { get; private set; }
	internal SsaRecordFieldCommit (SourceSpan span, SsaIndirectFieldPlace destination, StructValueShape shape,
	                               GenericArray<SsaValue> leaves, bool initializes, SsaStructCallResults? results) {
		base (span, null, -1);
		this.destination = destination;
		this.shape = shape;
		this.leaves = leaves;
		this.initializes = initializes;
		this.results = results;
	}

}

public class SsaRecordFieldDrop : SsaInstruction {
	public SsaIndirectFieldPlace source { get; private set; }
	public StructValueShape shape { get; private set; }
	internal SsaRecordFieldDrop (SourceSpan span, SsaIndirectFieldPlace source, StructValueShape shape) {
		base (span, null, -1);
		this.source = source;
		this.shape = shape;
	}

}

public abstract class SsaStructBoundary : SsaInstruction {
	public SsaStruct record_type { get; private set; }
	public int source_ordinal { get; private set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<SsaValue> leaves { get; private set; }
	public GenericArray<SsaHeapOwner> owners { get; private set; }
	public StructLeafPath? projection { get; private set; }
	public StructLeafPath root_path(StructLeafPath leaf) {
		if (projection == null) {
			return leaf;
		}
		int[] path = new int[projection.depth + leaf.depth];
		for (int i = 0; i < projection.depth; i++) {
			path[i] = projection.field_ordinal (i);
		}
		for (int i = 0; i < leaf.depth; i++) {
			path[projection.depth + i] = leaf.field_ordinal (i);
		}
		return new StructLeafPath (path, leaf.semantic_type);
	}

	public GenericArray<SsaBufferStorage> buffers { get; private set; default = new GenericArray<SsaBufferStorage> (); }
	public GenericArray<SsaBufferPair> buffer_pairs { get; private set; default = new GenericArray<SsaBufferPair> (); }
	private GenericArray<StructLeafPath> buffer_paths = new GenericArray<StructLeafPath> ();
	private GenericArray<int> buffer_ranks = new GenericArray<int> ();
	public StructLeafPath buffer_path(int index) {
		return buffer_paths[index];
	}

	public int buffer_rank(int index) {
		return buffer_ranks[index];
	}

	internal void add_buffer(SsaBufferStorage storage, SsaBufferPair pair) {
		buffers.add (storage);
		buffer_pairs.add (pair);
		buffer_paths.add (storage.record_path);
		buffer_ranks.add (storage.record_rank);
	}

	private GenericArray<StructLeafPath> paths = new GenericArray<StructLeafPath> ();
	private int[] ranks;
	public StructLeafPath owner_path(int index) {
		return paths[index];
	}

	public int owner_rank(int index) {
		return ranks[index];
	}

	internal bool owns_value(SsaHeapOwner owner, SsaValue value) {
		for (int i = 0; i < owners.length; i++) {
			if (owners[i] != owner) {
				continue;
			}
			for (int l = 0; l < shape.leaves.length; l++) {
				if (root_path (shape.leaves[l]).same_path (paths[i]) && leaves[l] == value) {
					return true;
				}
			}
		}
		return false;
	}

	protected SsaStructBoundary (SourceSpan span, SsaStruct record_type, int source_ordinal, StructValueShape shape, GenericArray<SsaValue> leaves, GenericArray<SsaHeapOwner> owners, StructLeafPath? projection = null) {
		base (span, null, -1);
		this.record_type = record_type;
		this.source_ordinal = source_ordinal;
		this.shape = shape;
		this.leaves = leaves;
		this.owners = owners;
		this.projection = projection;
		ranks = new int[owners.length];
		for (int i = 0; i < owners.length; i++) {
			paths.add (owners[i].record_path);
			ranks[i] = owners[i].record_rank;
		}
	}

}

public class SsaStructBoundaryAcquire : SsaStructBoundary {
	public SsaRecordAdmissionRestore? admission_restore { get; internal set; }
	public StructBoundaryGroup? parameter { get; private set; }
	public SsaStructCallResults? results { get; private set; }
	public SsaStructBoundaryMove? record_move { get; internal set; }
	internal SsaStructBoundaryAcquire (SourceSpan span, SsaStruct record_type, int source_ordinal, StructValueShape shape, GenericArray<SsaValue> leaves, GenericArray<SsaHeapOwner> owners, StructBoundaryGroup? parameter, SsaStructCallResults? results, StructLeafPath? projection = null) {
		base (span, record_type, source_ordinal, shape, leaves, owners, projection);
		this.parameter = parameter;
		this.results = results;
	}

}

public class SsaStructBoundaryMove : SsaStructBoundary {
	public StructResultUseKind use_kind { get; private set; }
	private WeakRef target;
	public SsaNode? consumer { owned get { return (SsaNode?) target.get (); } internal set { target = WeakRef (value); } }
	internal SsaStructBoundaryMove (SourceSpan span, SsaStruct record_type, int source_ordinal, StructValueShape shape, GenericArray<SsaValue> leaves, GenericArray<SsaHeapOwner> owners, StructResultUseKind use_kind) {
		base (span, record_type, source_ordinal, shape, leaves, owners);
		this.use_kind = use_kind;
	}

}
// Bounded physical call identity over ordinary SSA definitions; not SsaValue.
public class SsaStructCallResults : SsaNode {
	public StructValueShape shape { get; private set; }
	public GenericArray<SsaInstructionResult> leaves { get; private set; }
	public GenericArray<SsaBufferPair> buffers { get; private set; default = new GenericArray<SsaBufferPair> (); }
	internal SsaStructCallResults (SourceSpan span, StructValueShape shape, GenericArray<SsaInstructionResult> leaves) {
		base (span);
		this.shape = shape;
		this.leaves = leaves;
	}

}

// Retains exact complete consumption when destination field definitions promote.
// Backend transport needs no instruction for this semantic verification event.
public class SsaStructResultConsume : SsaInstruction {
	public SsaStructCallResults results { get; private set; }
	public StructResultUseKind use_kind { get; private set; }
	internal SsaStructResultConsume (SourceSpan span, SsaStructCallResults results, StructResultUseKind use_kind) {
		base (span, null, -1);
		this.results = results;
		this.use_kind = use_kind;
	}

}

public class SsaStructReturn : SsaReturn {
	public SsaStructBoundaryMove? record_move { get; internal set; }
	public StructValueShape shape { get; private set; }
	public GenericArray<SsaValue> leaves { get; private set; }
	internal SsaStructReturn (SourceSpan span, StructValueShape shape, GenericArray<SsaValue> leaves) {
		base (span, null);
		this.shape = shape;
		this.leaves = leaves;
	}

}
}
