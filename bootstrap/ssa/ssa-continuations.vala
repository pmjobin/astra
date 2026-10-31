// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;
using Astra.Continuations;

namespace Astra.Ssa {
public class SsaContinuationEnvironment : Object {
	public ContinuationIdentity identity { get; private set; default = new ContinuationIdentity (); }
	public SemanticType state_type { get; private set; }
	public StructValueShape? record_shape { get; private set; }
	public SsaCleanupContract? buffer_cleanup { get; private set; }
	public bool stable { get; private set; }
	public int leaf_count { get { return record_shape == null ? 1 : (int) record_shape.leaves.length; } }
	public SemanticType leaf_type(int index) {
		return record_shape == null ? state_type : record_shape.leaves[index].semantic_type;
	}
	internal SsaContinuationEnvironment (SemanticType state_type, StructValueShape? record_shape = null, SsaCleanupContract? buffer_cleanup = null, bool stable = true) {
		this.state_type = state_type;
		this.record_shape = record_shape;
		this.buffer_cleanup = buffer_cleanup;
		this.stable = stable;
	}
}

public class SsaContinuationEntry : Object {
	public ContinuationIdentity identity { get; private set; default = new ContinuationIdentity (); }
	public ContinuationRole role { get; private set; }
	public SsaContinuationEnvironment? environment { get; private set; }
	private WeakRef body;
	public SsaFunction? target { owned get { return (SsaFunction?) body.get (); } }
	internal SsaContinuationEntry (ContinuationRole role, SsaContinuationEnvironment? environment, SsaFunction? target = null) {
		this.role = role;
		this.environment = environment;
		this.body = WeakRef (target);
	}
}

public class SsaContinuationFamily : Object {
	public ContinuationIdentity identity { get; private set; default = new ContinuationIdentity (); }
	public SsaContinuationEnvironment? environment { get; private set; }
	public GenericArray<SsaContinuationEntry> entries { get; private set; default = new GenericArray<SsaContinuationEntry> (); }
	public SsaContinuationEntry? destroy { get; private set; }
	public bool repeat_step { get; private set; }
	internal SsaContinuationFamily (SsaContinuationEnvironment? environment, SsaContinuationEntry? destroy, bool repeat_step = true) {
		this.environment = environment;
		this.destroy = destroy;
		this.repeat_step = repeat_step;
	}
}

// Internal typed executable region, not a source SemanticType or erased value.
public class SsaContinuationRegion : SsaInstruction {
	public ContinuationIdentity identity { get; private set; default = new ContinuationIdentity (); }
	public GenericArray<SsaContinuationFamily> families { get; private set; default = new GenericArray<SsaContinuationFamily> (); }
	public GenericArray<SsaValue> operands { get; private set; default = new GenericArray<SsaValue> (); }
	public GenericArray<ContinuationAction> actions { get; private set; default = new GenericArray<ContinuationAction> (); }
	internal SsaContinuationRegion (SourceSpan span, SemanticType result_type, int ordinal) {
		base (span, result_type, ordinal);
	}
}

private class ContinuationOwnerState : Object {
	internal SsaContinuationFamily family;
	internal int instance;
	internal bool initialized;
	internal bool published;
	internal bool live = true;
	internal int retained;
	internal int active = -1;
	internal bool called;
	internal int calls;
	internal ContinuationOwnerState (SsaContinuationFamily family, int instance) {
		this.family = family;
		this.instance = instance;
		this.initialized = family.environment == null;
	}
}

private class ContinuationFields : Object {
	private GenericArray<SsaStruct> structs;
	internal ContinuationFields (GenericArray<SsaStruct> structs) {
		this.structs = structs;
	}
	internal GenericArray<SemanticType>? fields(SemanticType type) {
		foreach (var structure in structs) {
			if (structure.semantic_type == type) {
				var result = new GenericArray<SemanticType> ();
				foreach (var field in structure.fields) {
					result.add (field.semantic_type);
				}
				return result;
			}
		}
		return null;
	}
}

public class SsaContinuationVerifier : Object {
	private static void require(bool condition, string reason) throws SsaError {
		if (!condition) {
			throw new SsaError.INVALID_SSA ("internal continuation verification: %s", reason);
		}
	}
	public static void verify(SsaContinuationRegion region, GenericArray<SsaFunction> functions, GenericArray<SsaStruct> structs, GenericArray<SsaCleanupContract> cleanups) throws SsaError {
		require (region.result != null && region.result.semantic_type.kind == TypeKind.INT, "region result must be exact int");
		var seen = new HashTable<ContinuationIdentity, bool> (direct_hash, direct_equal);
		foreach (var family in region.families) {
			require (!seen.contains (family.identity), "duplicate operation family");
			seen.insert (family.identity, true);
			var environment = family.environment;
			require (family.destroy != null && family.destroy.role == ContinuationRole.DESTROY && family.destroy.target == null && family.destroy.environment == environment, "missing exact destruction authority");
			require (!seen.contains (family.destroy.identity), "duplicate destruction authority");
			seen.insert (family.destroy.identity, true);
			if (environment != null) {
				require (environment.stable && environment.leaf_count > 0 && environment.leaf_type (0).kind == TypeKind.INT, "stable exact state with leading int required");
				if (environment.record_shape != null) {
					require (environment.state_type == environment.record_shape.semantic_type, "wrong state record association");
					try {
						environment.record_shape.verify (new ContinuationFields (structs).fields);
					} catch (StructLeafError error) {
						throw new SsaError.INVALID_SSA ("continuation state shape: %s", error.message);
					}
				} else {
					require (environment.state_type.kind == TypeKind.INT, "scalar state must be exact int");
				}
				if (environment.buffer_cleanup != null) {
					require (cleanups.find (environment.buffer_cleanup) && environment.buffer_cleanup.is_buffer && environment.buffer_cleanup.buffer_type.element_type.kind == TypeKind.INT, "missing concrete int buffer cleanup authority");
				}
			}
			bool step = false;
			bool cancel = false;
			foreach (var entry in family.entries) {
				require (!seen.contains (entry.identity), "duplicate generated entry identity");
				seen.insert (entry.identity, true);
				require (entry.environment == environment && entry.role != ContinuationRole.DESTROY, "wrong operation environment or role");
				var target = entry.target;
				require (target != null && functions.find (target), "stale generated code membership");
				require (target.async_body == null && target.kind == CallableKind.FUNCTION && target.implicit_receiver == null && target.owned_cleanup == null && target.buffer_parameters.length == 0, "generated body requires an ordinary exact value boundary");
				int leaves = environment == null ? 0 : environment.leaf_count;
				bool buffer = environment != null && environment.buffer_cleanup != null;
				require (target.parameters.length == leaves + 1 + (buffer ? 1 : 0), "generated body signature mismatch");
				for (int i = 0; i < leaves; i++) {
					require (target.parameters[i].semantic_type == environment.leaf_type (i) && target.parameters[i].pointer_contract == PointerParameterContract.UNMANAGED, "state snapshot signature mismatch");
				}
				require (target.parameters[leaves].semantic_type.kind == TypeKind.INT, "invocation argument signature mismatch");
				if (buffer) {
					require (target.parameters[leaves + 1].semantic_type == environment.buffer_cleanup.buffer_type && target.parameters[leaves + 1].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE, "buffer invocation requires exact bounded slice");
				}
				require (target.return_type == (environment == null ? target.parameters[0].semantic_type : environment.state_type), "generated body result signature mismatch");
				if (environment != null && environment.record_shape != null) {
					require (target.struct_result != null && target.struct_result.semantic_type == environment.state_type && target.struct_parameters.length == 1 && target.struct_parameters[0].first_leaf == 0 && target.struct_parameters[0].shape.semantic_type == environment.state_type, "complete record snapshot boundary required");
				}
				// A body receives snapshots and a bounded buffer view, never the
				// descriptor/environment address or its destruction permission.
				foreach (var block in target.blocks) {
					foreach (var instruction in block.instructions) {
						require (!(instruction is SsaContinuationRegion), "nested continuation body is outside this bounded entry contract");
					}
				}
				step |= entry.role == ContinuationRole.STEP;
				cancel |= entry.role == ContinuationRole.CANCEL_DRAIN;
			}
			require (step && cancel, "family requires distinct step and cancel-drain roles");
		}
		var owners = new HashTable<int, ContinuationOwnerState> (direct_hash, direct_equal);
		var instances = new HashTable<int, bool> (direct_hash, direct_equal);
		var witnesses = new HashTable<int, ContinuationOwnerState> (direct_hash, direct_equal);
		var used_witnesses = new HashTable<int, bool> (direct_hash, direct_equal);
		bool result = false;
		foreach (var action in region.actions) {
			if (action.kind == ContinuationActionKind.CREATE) {
				require (action.owner >= 0 && !owners.contains (action.owner), "duplicate owning descriptor");
				require (action.family >= 0 && action.family < region.families.length, "wrong operation family");
				require (action.instance >= 0 && !instances.contains (action.instance), "duplicate environment instance authority");
				instances.insert (action.instance, true);
				owners.insert (action.owner, new ContinuationOwnerState (region.families[action.family], action.instance));
				continue;
			}
			var owner = owners.lookup (action.owner);
			require (owner != null && owner.live, "use after move or destruction");
			var environment = owner.family.environment;
			switch (action.kind) {
			case ContinuationActionKind.INITIALIZE:
				require (!owner.initialized && !owner.published && environment != null && action.capture_count == environment.leaf_count, "missing or duplicate environment initialization");
				for (int i = 0; i < action.capture_count; i++) {
					int operand = action.capture (i);
					require (operand >= 0 && operand < region.operands.length && region.operands[operand].semantic_type == environment.leaf_type (i), "capture type mismatch");
				}
				if (environment.buffer_cleanup != null) {
					require (action.operand >= 0 && action.operand < region.operands.length && region.operands[action.operand].semantic_type.kind == TypeKind.INT, "buffer initialization count mismatch");
				}
				owner.initialized = true;
				break;
			case ContinuationActionKind.PUBLISH:
				require (owner.initialized && !owner.published, "publication requires initialized environment");
				require (action.first_entry >= 0 && action.second_entry >= 0 && action.first_entry < owner.family.entries.length && action.second_entry < owner.family.entries.length && owner.family.entries[action.first_entry].role == ContinuationRole.STEP && owner.family.entries[action.second_entry].role == ContinuationRole.STEP, "selection requires exact step family");
				require (action.operand >= 0 && action.operand < region.operands.length && region.operands[action.operand].semantic_type.kind == TypeKind.BOOL, "runtime selection requires bool");
				owner.published = true;
				break;
			case ContinuationActionKind.MOVE:
				require (owner.published && owner.active < 0 && owner.retained == 0, "move overlaps bounded use");
				require (action.destination >= 0 && !owners.contains (action.destination), "duplicate owning descriptor destination");
				var moved = new ContinuationOwnerState (owner.family, owner.instance);
				moved.initialized = true;
				moved.published = true;
				moved.calls = owner.calls;
				owner.live = false;
				owners.insert (action.destination, moved);
				break;
			case ContinuationActionKind.RETAIN: case ContinuationActionKind.BEGIN:
				require (owner.published && action.witness >= 0 && !used_witnesses.contains (action.witness), "invalid bounded witness");
				if (action.kind == ContinuationActionKind.BEGIN) {
					require (owner.active < 0, "reentrant invocation");
					owner.active = action.witness;
					owner.called = false;
				} else {
					owner.retained++;
				}
				witnesses.insert (action.witness, owner);
				used_witnesses.insert (action.witness, true);
				break;
			case ContinuationActionKind.RELEASE: case ContinuationActionKind.END:
				require (witnesses.lookup (action.witness) == owner, "wrong environment retention association");
				if (action.kind == ContinuationActionKind.END) {
					require (owner.active == action.witness && owner.called, "invocation must complete before end");
					owner.active = -1;
				} else {
					require (owner.active != action.witness && owner.retained > 0, "wrong retention witness role");
					owner.retained--;
				}
				witnesses.remove (action.witness);
				break;
			case ContinuationActionKind.CALL:
				require (owner.published && owner.active == action.witness && !owner.called && witnesses.lookup (action.witness) == owner, "invocation requires exact active witness");
				require (action.role == ContinuationRole.STEP || action.role == ContinuationRole.CANCEL_DRAIN, "wrong invocation operation role");
				require (action.operand >= 0 && action.operand < region.operands.length && region.operands[action.operand].semantic_type.kind == TypeKind.INT, "invocation signature mismatch");
				require (owner.calls == 0 || owner.family.repeat_step || action.role != ContinuationRole.STEP, "step repeat permission missing");
				owner.called = true;
				if (action.role == ContinuationRole.STEP) {
					owner.calls++;
				}
				result = true;
				break;
			case ContinuationActionKind.DESTROY:
				require (owner.published && owner.active < 0 && owner.retained == 0, "destruction requires complete invocation and retention retirement");
				owner.live = false;
				break;
			default:
				require (false, "invalid continuation action");
				break;
			}
		}
		foreach (var owner in owners.get_values ()) {
			require (!owner.live, "missing unique owner destruction");
		}
		require (witnesses.size () == 0 && result, "region requires retired uses and a produced result");
	}
}
}
