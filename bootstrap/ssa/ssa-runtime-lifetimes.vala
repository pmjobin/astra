// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Text;

namespace Astra.Ssa {
private class SsaRuntimeStorage : Object {
	internal int binding;
	internal int destination;
	internal string path;
	internal bool private_exception;
	internal SsaRuntimeStorage (int binding, int destination, string path = "") {
		this.binding = binding;
		this.destination = destination;
		this.path = path;
	}

}
private class SsaRuntimeBound : Object {
	internal int value;
	internal int destination;
	internal SsaRuntimeBound (int value, int destination) {
		this.value = value;
		this.destination = destination;
	}

}
private class SsaRuntimeContextEnd : Object {
	internal int context;
	internal GenericArray<int> values = new GenericArray<int> ();
	internal GenericArray<int> bindings = new GenericArray<int> ();
	internal SsaRuntimeContextEnd (int context, int binding, RuntimeLifetimeState state) {
		this.context = context;
		foreach (int key in state.bindings.get_keys ()) {
			if (key != binding) {
				values.add (state.bindings.lookup (key));
				bindings.add (key);
			}
		}
	}

}
// Reconstruct from definitions, physical edges, ordered memory effects and
// exact owner events. No Source, Core or CFG summaries enter this authority.
public class SsaRuntimeLifetimes : Object {
	private SsaProgram program;
	private HashTable<SsaFunction, RuntimeLifetimeSummary> summaries = new HashTable<SsaFunction, RuntimeLifetimeSummary> (direct_hash, direct_equal);
	private HashTable<SsaFunction, bool> visiting = new HashTable<SsaFunction, bool> (direct_hash, direct_equal);
	public static HashTable<SsaFunction, RuntimeLifetimeSummary> analyze(SsaProgram program) throws SsaError {
		var analysis = new SsaRuntimeLifetimes ();
		analysis.program = program;
		foreach (var function in program.functions) {
			analysis.summary (function);
		}
		return analysis.summaries;
	}

	public static void verify(SsaProgram program, GenericArray<SsaFunction>? required = null) throws SsaError {
		var summaries = analyze (program);
		if (required != null) {
			foreach (var function in required) {
				var result = summaries.lookup (function);
				if (result == null || !result.complete) {
					throw new SsaError.INVALID_SSA ("SSA scoped construction requires its complete actual function lifetime proof");
				}
			}
		}
	}

	private static void physical_roles(SsaFunction function, out bool[] owners, out bool[] contexts, out bool[] mutable_owners) {
		owners = new bool[function.parameters.length];
		contexts = new bool[function.parameters.length];
		mutable_owners = new bool[function.parameters.length];
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			var type = parameter.semantic_type;
			bool graph = !(type is HandleType && ((HandleType) type).context_mode != "") && (type is ClassType || type is ReceiverType || type is HandleType || type.is_struct_storage () || type is TaskType);
			bool owns = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER;
			foreach (var group in function.struct_parameters) {
				if (p >= group.first_leaf && p < group.first_leaf + group.shape.leaves.length && group.shape.mode == StructValueMode.MOVE_VALUE) {
					var buffer = group.shape.leaves[p - group.first_leaf] as StructBufferLeafPath;
					owns = owns || graph || buffer != null && buffer.component == 0;
				}
			}
			foreach (var group in function.buffer_parameters) {
				if (p == group.first_leaf) {
					owns = true;
				}
			}
			contexts[p] = type.is_scoped_allocator ();
			owners[p] = owns || graph;
			mutable_owners[p] = !owns && graph && !contexts[p];
		}
	}

	internal static RuntimeLifetimeSummary import_summary(SsaFunction function, RuntimeLifetimeSummary archived) throws RuntimeLifetimeError {
		if (!archived.logical_coordinates) {
			return archived;
		}
		var positions = new GenericArray<int> ();
		var ordinals = new GenericArray<int> ();
		foreach (var group in function.buffer_parameters) {
			positions.add (group.first_leaf);
			ordinals.add (group.source_ordinal);
		}
		var layout = NativeLifetimeLayout.build ((int) function.parameters.length, function.struct_parameters, positions, ordinals);
		bool[] owners;
		bool[] contexts;
		bool[] mutable_owners;
		physical_roles (function, out owners, out contexts, out mutable_owners);
		return layout.to_physical (archived, function.implicit_receiver != null, owners, contexts, mutable_owners);
	}

	public static string export_summary(SsaFunction function, string descriptor) throws RuntimeLifetimeError {
		var positions = new GenericArray<int> ();
		var ordinals = new GenericArray<int> ();
		foreach (var group in function.buffer_parameters) {
			positions.add (group.first_leaf);
			ordinals.add (group.source_ordinal);
		}
		var layout = NativeLifetimeLayout.build ((int) function.parameters.length, function.struct_parameters, positions, ordinals);
		bool[] owners;
		bool[] contexts;
		bool[] mutable_owners;
		physical_roles (function, out owners, out contexts, out mutable_owners);
		var summary = RuntimeLifetimeSummary.decode (descriptor);
		summary.validate_formals (function.implicit_receiver != null, owners, contexts, mutable_owners);
		return layout.to_logical (summary, function.implicit_receiver != null, owners, contexts, mutable_owners).encode ();
	}

	internal RuntimeLifetimeSummary? summary(SsaFunction? function) throws SsaError {
		if (function == null || visiting.contains (function) || !program.functions.find (function)) {
			return null;
		}
		var existing = summaries.lookup (function);
		if (existing != null) {
			return existing;
		}
		if (function.native_declaration != null) {
			try {
				var imported = function.native_declaration.runtime_lifetime_summary ();
				if (imported != null) {
					imported = import_summary (function, imported);
					summaries.insert (function, imported);
				}
				return imported;
			} catch (RuntimeLifetimeError failure) {
				throw new SsaError.INVALID_SSA ("SSA native lifetime contract: %s", failure.message);
			}
		}
		visiting.insert (function, true);
		var body = new SsaRuntimeLifetimeBody (this, program, function);
		RuntimeLifetimeSummary result;
		try {
			result = body.analyze ();
		} catch (RuntimeLifetimeError failure) {
			if (failure is RuntimeLifetimeError.LOCAL_ESCAPE) {
				throw new SsaError.INVALID_SSA ("SSA runtime lifetime: %s", failure.message);
			}
			result = body.incomplete (failure.message);
		}
		if (body.requires_scope && !result.complete) {
			throw new SsaError.INVALID_SSA ("SSA scoped lifetime proof is incomplete: %s", result.limitation);
		}
		visiting.remove (function);
		summaries.insert (function, result);
		return result;
	}

}
private class SsaRuntimeLifetimeBody : Object {
	private SsaRuntimeLifetimes analysis;
	private SsaProgram program;
	private SsaFunction function;
	private RuntimeLifetimeEquations graph = new RuntimeLifetimeEquations ();
	private RuntimeLifetimeRegions regions = new RuntimeLifetimeRegions ();
	private HashTable<TextLoanExtent, int> region_ids = new HashTable<TextLoanExtent, int> (direct_hash, direct_equal);
	private HashTable<int, TextLoanExtent> extents = new HashTable<int, TextLoanExtent> (direct_hash, direct_equal);
	private HashTable<SsaBlock, RuntimeLifetimeState> entries = new HashTable<SsaBlock, RuntimeLifetimeState> (direct_hash, direct_equal);
	private HashTable<SsaBlock, RuntimeLifetimeState> outputs = new HashTable<SsaBlock, RuntimeLifetimeState> (direct_hash, direct_equal);
	private HashTable<SsaValue, int> values = new HashTable<SsaValue, int> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaInstruction> definitions = new HashTable<SsaValue, SsaInstruction> (direct_hash, direct_equal);
	private HashTable<SsaValue, GenericArray<SsaValue>> incoming_edges = new HashTable<SsaValue, GenericArray<SsaValue>> (direct_hash, direct_equal);
	private HashTable<SsaValue, GenericArray<SsaHeapOwner>> acquisitions = new HashTable<SsaValue, GenericArray<SsaHeapOwner>> (direct_hash, direct_equal);
	private HashTable<SsaFrameInputRestore, int> frame_inputs = new HashTable<SsaFrameInputRestore, int> (direct_hash, direct_equal);
	private HashTable<int, int> tasks = new HashTable<int, int> (direct_hash, direct_equal);
	private HashTable<SsaObjectStorage, int> objects = new HashTable<SsaObjectStorage, int> (direct_hash, direct_equal);
	private HashTable<SsaAddressableLocal, int> memory = new HashTable<SsaAddressableLocal, int> (direct_hash, direct_equal);
	private HashTable<SsaBufferStorage, int> buffers = new HashTable<SsaBufferStorage, int> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, SsaBufferPlace> buffer_reads = new HashTable<SsaBufferPair, SsaBufferPlace> (direct_hash, direct_equal);
	private HashTable<int, bool> buffer_inputs = new HashTable<int, bool> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, bool> buffer_pairs = new HashTable<SsaBufferPair, bool> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, int> buffer_versions = new HashTable<SsaBufferPair, int> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, SsaNode> buffer_consumptions = new HashTable<SsaBufferPair, SsaNode> (direct_hash, direct_equal);
	private HashTable<SsaValue, int> pending = new HashTable<SsaValue, int> (direct_hash, direct_equal);
	private HashTable<SsaValue, int> private_errors = new HashTable<SsaValue, int> (direct_hash, direct_equal);
	private HashTable<int, GenericArray<SsaNode>> private_uses = new HashTable<int, GenericArray<SsaNode>> (direct_hash, direct_equal);
	private HashTable<SsaValue, int> recent_moves = new HashTable<SsaValue, int> (direct_hash, direct_equal);
	private HashTable<SsaHeapOwnerEvent, bool> record_events = new HashTable<SsaHeapOwnerEvent, bool> (direct_hash, direct_equal);
	private HashTable<SsaStructCallResults, SsaTaskSuccess> task_records = new HashTable<SsaStructCallResults, SsaTaskSuccess> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaBlock> task_record_blocks = new HashTable<SsaValue, SsaBlock> (direct_hash, direct_equal);
	private HashTable<SsaStructCallResults, SsaCallInstruction> record_calls = new HashTable<SsaStructCallResults, SsaCallInstruction> (direct_hash, direct_equal);
	private HashTable<SsaStructCallResults, SsaStructResultConsume> record_consumptions = new HashTable<SsaStructCallResults, SsaStructResultConsume> (direct_hash, direct_equal);
	private HashTable<SsaStructCallResults, SsaRecordAdmissionRestore> record_restores = new HashTable<SsaStructCallResults, SsaRecordAdmissionRestore> (direct_hash, direct_equal);
	private HashTable<SsaCallInstruction, SsaGroupCallSuccess> record_successes = new HashTable<SsaCallInstruction, SsaGroupCallSuccess> (direct_hash, direct_equal);
	private HashTable<SsaCallInstruction, SsaBlock> record_success_blocks = new HashTable<SsaCallInstruction, SsaBlock> (direct_hash, direct_equal);
	private HashTable<SsaCallInstruction, int> record_pending = new HashTable<SsaCallInstruction, int> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaCallInstruction> checked_record_leaves = new HashTable<SsaValue, SsaCallInstruction> (direct_hash, direct_equal);
	private HashTable<SsaHeapOwner, SsaScopedAllocator> contexts = new HashTable<SsaHeapOwner, SsaScopedAllocator> (direct_hash, direct_equal);
	private HashTable<int, int> initial_inputs = new HashTable<int, int> (direct_hash, direct_equal);
	private HashTable<int, int> exits = new HashTable<int, int> (direct_hash, direct_equal);
	private GenericArray<int> slots = new GenericArray<int> ();
	private GenericArray<SsaRuntimeBound> bounds = new GenericArray<SsaRuntimeBound> ();
	private GenericArray<RuntimeLifetimeStore> stores = new GenericArray<RuntimeLifetimeStore> ();
	private GenericArray<SsaRuntimeContextEnd> context_ends = new GenericArray<SsaRuntimeContextEnd> ();
	private RuntimeLifetimeState state = new RuntimeLifetimeState ();
	private SsaLifetimeFacts? lifetimes;
	private SsaInstruction current_instruction;
	private SsaBlock current_block;
	private int returned;
	private int exceptional_result;
	private int normal_exits;
	private int next_slot;
	private int exit_count;
	private string unsupported = "";
	private bool scoped_allocation;
	internal bool requires_scope { get { return scoped_allocation || graph.has_scope_roots; } }
	internal SsaRuntimeLifetimeBody (SsaRuntimeLifetimes analysis, SsaProgram program, SsaFunction function) {
		this.analysis = analysis;
		this.program = program;
		this.function = function;
		scoped_allocation |= scoped_type (function.return_type) || function.implicit_receiver != null && scoped_type (function.implicit_receiver.contract) || function.throws_type != null && scoped_type (function.throws_type);
		foreach (var parameter in function.parameters) {
			scoped_allocation |= scoped_type (parameter.semantic_type);
		}
		foreach (var local in function.storage) {
			scoped_allocation |= scoped_type (local.semantic_type);
		}
		foreach (var local in function.object_storage) {
			scoped_allocation |= scoped_type (local.semantic_type);
		}
	}

	private void unsupported_node(string reason) {
		if (unsupported == "") {
			unsupported = reason;
		}
	}

	private static int parameter_binding(int parameter) {
		return -parameter - 2;
	}

	private int parameter_index(SsaFunctionParameter parameter) {
		for (int i = 0; i < function.parameters.length; i++) {
			if (function.parameters[i] == parameter) {
				return i;
			}
		}
		unsupported_node ("SSA parameter is outside its actual signature");
		return -2;
	}

	private static bool graph_input(SemanticType type) {
		return !(type is HandleType && ((HandleType) type).context_mode != "") && (type is ClassType || type is ReceiverType || type is HandleType || type.is_struct_storage () || type is TaskType);
	}

	private int slot() {
		int result = next_slot++;
		slots.add (result);
		return result;
	}

	private int region_id(TextLoanExtent? extent) throws RuntimeLifetimeError {
		if (extent == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA lifetime requires actual lexical cleanup extents");
		}
		if (!region_ids.contains (extent)) {
			int parent = extent.parent == null ? -1 : region_id (extent.parent);
			region_ids.insert (extent, regions.add_region (parent));
		}
		return region_ids.lookup (extent);
	}

	private void owner_extent(int ordinal, TextLoanExtent? extent) throws RuntimeLifetimeError {
		if (ordinal < 0 || extent == null) {
			unsupported_node ("SSA owner lacks its actual cleanup extent");
			return;
		}
		if (extents.contains (ordinal)) {
			if (extents.lookup (ordinal) != extent) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA owner cleanup extent changed");
			}
			return;
		}
		extents.insert (ordinal, extent);
		regions.owner (ordinal, region_id (extent));
	}

	private SsaInstruction? definition(SsaValue? value) {
		return value == null ? null : definitions.lookup (value);
	}

	private SsaNativeInstance? instance(SemanticType type) {
		if (type is ReceiverType) {
			type = ((ReceiverType) type).instance_type;
		}
		foreach (var owner in program.native_instances ()) {
			if (owner.semantic_type == type) {
				return owner;
			}
		}
		return null;
	}

	private bool scoped_type(SemanticType type) {
		return RuntimeScopeTypes.contains (type, expand_scoped_type);
	}

	private bool expand_scoped_type(SemanticType type, GenericArray<SemanticType> following) {
		var owner = instance (type);
		if (owner != null) {
			var object_class = owner as SsaClass;
			if (object_class != null) {
				var policy = object_class.allocation_policy;
				if (policy != null && policy.kind == AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") {
					return true;
				}
				if (object_class.parent_class != null) {
					following.add (object_class.parent_class.semantic_type);
				}
			}
			foreach (var field in owner.fields) {
				if (field.owned_cleanup != null || field.slots_cleanup != null || field.semantic_type.is_struct_storage ()) {
					following.add (field.semantic_type);
				}
			}
		}
		foreach (var definition in program.enums) {
			if (definition.semantic_type == type) {
				foreach (var field in definition.value_fields ()) {
					following.add (field);
				}
			}
		}
		return false;
	}

	private int product(SemanticType type, RuntimeScopeOrigin? anchor = null) throws RuntimeLifetimeError {
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		if (anchor != null) {
			roots.add (anchor);
		}
		var fields = new HashTable<string, int> (str_hash, str_equal);
		var owner = instance (type);
		if (owner != null) {
			if (owner is SsaClass && ((SsaClass) owner).parent_class != null) {
				unsupported_node ("SSA inherited fields require nominal paths");
			}
			foreach (var field in owner.fields) {
				fields.insert ("f%d".printf (field.ordinal), graph.absent ());
			}
		}
		return graph.product (roots, fields);
	}

	private SsaRuntimeStorage object_storage(SsaObjectStorage storage) {
		return new SsaRuntimeStorage (objects.lookup (storage), storage.cleanup_rank);
	}

	private SsaRuntimeStorage? field(SsaRuntimeStorage? storage, int ordinal) {
		if (storage != null) {
			storage.path += (storage.path == "" ? "" : ".") + "f%d".printf (ordinal);
		}
		return storage;
	}

	private SsaRuntimeStorage? reference(SsaValue? value, HashTable<SsaValue, bool>? seen = null) {
		if (value == null) {
			return null;
		}
		if (private_errors.contains (value)) {
			private_use (value, current_instruction);
			var result = new SsaRuntimeStorage (private_errors.lookup (value), -1);
			result.private_exception = true;
			return result;
		}
		var visited = seen ?? new HashTable<SsaValue, bool> (direct_hash, direct_equal);
		if (visited.contains (value)) {
			return null;
		}
		visited.insert (value, true);
		var acquired = acquisitions.lookup (value);
		if (acquired != null && current_instruction != null && lifetimes != null) {
			var facts = lifetimes.before.lookup (current_instruction);
			SsaHeapOwner? found = null;
			if (facts != null) {
				foreach (var owner in acquired) {
					if (facts.state (owner.ordinal) == 2) {
						if (found != null) {
							unsupported_node ("SSA pointer aliases competing live owners");
							return null;
						}
						found = owner;
					}
				}
			}
			if (found != null) {
				return new SsaRuntimeStorage (found.ordinal, found.source_ordinal);
			}
		}
		if (value is SsaFunctionParameter) {
			int binding = parameter_binding (parameter_index ((SsaFunctionParameter) value));
			return new SsaRuntimeStorage (binding, binding);
		}
		if (value is SsaReceiver) {
			return new SsaRuntimeStorage (-1, -1);
		}
		var producer = definition (value);
		if (producer is SsaObjectReferenceInstruction) {
			return object_storage (((SsaObjectReferenceInstruction) producer).storage);
		}
		if (producer is SsaStorageReceiverInstruction) {
			return object_storage (((SsaStorageReceiverInstruction) producer).storage);
		}
		if (producer is SsaObjectValidateInstruction) {
			return reference (((SsaObjectValidateInstruction) producer).reference, visited);
		}
		if (producer is SsaClassUpcast) {
			return reference (((SsaClassUpcast) producer).reference, visited);
		}
		if (producer is SsaLoadInstruction) {
			return place (((SsaLoadInstruction) producer).source);
		}
		var edges = incoming_edges.lookup (value);
		if (edges != null) {
			SsaRuntimeStorage? result = null;
			foreach (var incoming in edges) {
				if (incoming == value) {
					continue;
				}
				var branch = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
				foreach (var prior in visited.get_keys ()) {
					branch.insert (prior, true);
				}
				var candidate = reference (incoming, branch);
				if (candidate == null || result != null && (result.binding != candidate.binding || result.path != candidate.path)) {
					return null;
				}
				result = candidate;
			}
			return result;
		}
		return null;
	}

	private SsaRuntimeStorage? place(SsaMemoryPlace source) {
		if (source is SsaLocalMemoryPlace) {
			var storage = ((SsaLocalMemoryPlace) source).storage;
			return new SsaRuntimeStorage (memory.lookup (storage), storage.source_local_ordinal);
		}
		if (source is SsaObjectFieldPlace) {
			return field (object_storage (((SsaObjectFieldPlace) source).storage), ((SsaObjectFieldPlace) source).field.ordinal);
		}
		if (source is SsaIndirectFieldPlace) {
			return field (reference (((SsaIndirectFieldPlace) source).pointer), ((SsaIndirectFieldPlace) source).field.ordinal);
		}
		if (source is SsaDirectFieldPlace) {
			var direct = (SsaDirectFieldPlace) source;
			return field (new SsaRuntimeStorage (memory.lookup (direct.storage), direct.storage.source_local_ordinal), direct.field.ordinal);
		}
		if (source is SsaFieldPlace && ((SsaFieldPlace) source).aggregate != null) {
			return field (place (((SsaFieldPlace) source).aggregate), ((SsaFieldPlace) source).field.ordinal);
		}
		unsupported_node ("SSA memory effect requires its exact ownership projection");
		return null;
	}

	private int read(SsaRuntimeStorage? storage) throws RuntimeLifetimeError {
		if (storage == null || !state.bindings.contains (storage.binding)) {
			unsupported_node ("SSA pointer requires exact live storage");
			return graph.absent ();
		}
		int value = state.bindings.lookup (storage.binding);
		return storage.path == "" ? value : graph.project (value, storage.path);
	}

	private int replace_path(int root, string path, int incoming) throws RuntimeLifetimeError {
		int dot = path.index_of_char ('.');
		if (dot < 0) {
			return graph.replace (root, path, incoming);
		}
		string head = path.substring (0, dot);
		return graph.replace (root, head, replace_path (graph.project (root, head), path.substring (dot + 1), incoming));
	}

	private void write(SsaRuntimeStorage? storage, int incoming, bool effect = true) throws RuntimeLifetimeError {
		if (storage == null) {
			unsupported_node ("SSA store requires its exact destination in " + function.name + " at " + (current_instruction == null ? "missing instruction" : current_instruction.get_type ().name ()));
			return;
		}
		int updated = storage.path == "" ? incoming : replace_path (state.bindings.lookup (storage.binding), storage.path, incoming);
		state.bindings.insert (storage.binding, updated);
		if (storage.private_exception) {
			return;
		}
		if (storage.destination >= 0) {
			if (extents.contains (storage.destination)) {
				bounds.add (new SsaRuntimeBound (updated, storage.destination));
			} else {
				unsupported_node ("SSA store lacks a checked destination cleanup extent");
			}
		} else if (effect) {
			stores.add (new RuntimeLifetimeStore (storage.destination == -1 ? -1 : -storage.destination - 2, incoming));
		}
	}

	private GenericArray<SemanticType>? record_fields(SemanticType type) {
		var record = instance (type) as SsaStruct;
		if (record == null) {
			return null;
		}
		var result = new GenericArray<SemanticType> ();
		foreach (var field in record.fields) {
			result.add (field.semantic_type);
		}
		return result;
	}

	private void record_shape(StructValueShape shape) throws RuntimeLifetimeError {
		try {
			shape.verify (record_fields);
		} catch (StructLeafError failure) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime shape: %s", failure.message);
		}
	}

	private SsaStructField? record_field(SsaStruct record, StructLeafPath path) {
		SsaStructField? field = null;
		SemanticType type = record.semantic_type;
		for (int depth = 0; depth < path.depth; depth++) {
			var current = instance (type) as SsaStruct;
			int ordinal = path.field_ordinal (depth);
			if (current == null || ordinal < 0 || ordinal >= current.fields.length) {
				return null;
			}
			field = current.fields[ordinal];
			type = field.semantic_type;
		}
		return type == path.semantic_type ? field : null;
	}

	private void buffer_parameters() throws RuntimeLifetimeError, SsaError {
		if (function.buffer_parameters.length == 0) {
			return;
		}
		if (function.struct_parameters.length != 0) {
			unsupported_node ("SSA mixed buffer/record parameters need exact combined groups");
			return;
		}
		int physical = 0;
		int logical = 0;
		int index = 0;
		while (physical < function.parameters.length) {
			var group = index < function.buffer_parameters.length ? function.buffer_parameters[index] : null;
			if (group == null || group.first_leaf > physical) {
				physical++;
				logical++;
				continue;
			}
			var shape = group.cleanup.buffer_shape;
			if (group.first_leaf != physical || group.source_ordinal != logical || physical + 1 >= function.parameters.length || !program.cleanups.find (group.cleanup) || !group.cleanup.is_buffer || shape == null || !shape.is_valid (record_fields) || scoped_type (shape.slice_type.element_type) || shape.slice_type is ContextBytesType || group.pair.shape != shape || group.pair.base_value != function.parameters[physical] || group.pair.length_value != function.parameters[physical + 1] || function.parameters[physical].semantic_type != shape.base_type || function.parameters[physical + 1].semantic_type != shape.length_type || function.parameters[physical].pointer_contract != PointerParameterContract.UNMANAGED || function.parameters[physical + 1].pointer_contract != PointerParameterContract.UNMANAGED) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer lifetime requires exact ordered original PTR/I32 parameters and scope-free owned cleanup");
			}
			int acquisitions = 0;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var write = instruction as SsaBufferWriteInstruction;
					if (write == null || write.pair != group.pair) {
						continue;
					}
					if (block != function.entry || !write.initializes || write.place.storage == null || !function.buffer_storage.find (write.place.storage) || write.place.cleanup != group.cleanup || write.place.storage.cleanup != group.cleanup || write.place.storage.text_extent == null) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer input requires its complete original entry acquisition and cleanup extent");
					}
					acquisitions++;
				}
			}
			if (acquisitions != 1) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer input requires one complete original entry acquisition");
			}
			buffer_inputs.insert (physical, true);
			buffer_pairs.insert (group.pair, true);
			physical += 2;
			logical++;
			index++;
		}
		if (index != function.buffer_parameters.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer lifetime group exceeds its actual signature");
		}
		SsaBufferMemoryFlow.verify (function);
	}

	private SsaRuntimeStorage? buffer_place(SsaBufferPlace source) {
		if (source.storage != null && buffers.contains (source.storage)) {
			return new SsaRuntimeStorage (buffers.lookup (source.storage), source.storage.owner_ordinal);
		}
		if (source.field != null) {
			return place (source.field);
		}
		unsupported_node ("SSA buffer lifetime requires an exact local or receiver field pair");
		return null;
	}

	private void buffer_pair(SsaBufferPair pair, SsaInstruction source) throws RuntimeLifetimeError {
		if (values.contains (pair.base_value) || values.contains (pair.length_value)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer lifetime repeats a physical pair definition");
		}
		buffer_pairs.insert (pair, true);
		values.insert (pair.base_value, graph.join ());
		values.insert (pair.length_value, graph.join ());
		definitions.insert (pair.base_value, source);
		definitions.insert (pair.length_value, source);
	}

	private int buffer_value(SsaBufferPair pair) throws RuntimeLifetimeError {
		if (pair.is_empty) {
			return graph.absent ();
		}
		if (!buffer_pairs.contains (pair) || !values.contains (pair.base_value) || !values.contains (pair.length_value)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer lifetime lost its complete original pointer/length pair");
		}
		return value (pair.base_value);
	}

	private void consume_buffer(SsaBufferPair pair, SsaCleanupContract cleanup, SsaNode site) throws RuntimeLifetimeError {
		if (cleanup.buffer_shape != pair.shape || !cleanup.is_buffer || pair.base_value.semantic_type != pair.shape.base_type || pair.length_value.semantic_type != pair.shape.length_type) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer lifetime changed its exact complete pair type or cleanup");
		}
		buffer_value (pair);
		if (pair.is_empty) {
			return;
		}
		if (buffer_consumptions.contains (pair)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer lifetime duplicates one complete owner pair");
		}
		buffer_consumptions.insert (pair, site);
	}

	private void buffer_arguments(SsaCallInstruction call) throws RuntimeLifetimeError {
		if (call.target == null || call.buffer_arguments.length != call.target.buffer_parameters.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer call lost its complete original argument groups");
		}
		for (int b = 0; b < call.buffer_arguments.length; b++) {
			var argument = call.buffer_arguments[b];
			if (argument.parameter != call.target.buffer_parameters[b] || argument.parameter.first_leaf + 1 >= call.arguments.length || call.arguments[argument.parameter.first_leaf] != argument.pair.base_value || call.arguments[argument.parameter.first_leaf + 1] != argument.pair.length_value) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer call changed an original parameter or complete pair");
			}
			consume_buffer (argument.pair, argument.parameter.cleanup, call);
		}
	}

	private void buffer_restore(SsaFallibleBufferRestore restored) throws RuntimeLifetimeError, SsaError {
		var call = restored.call;
		var argument = restored.argument;
		uint position = 0, called = 0;
		if (call == null || !call.constructs || !call.storage.fallible || !call.storage.heap_allocated || !call.buffer_restores.find (restored) || !call.buffer_arguments.find (argument) || argument.disarm.place.storage == null || argument.disarm.place.storage.record_type != null || restored.pair.shape != argument.pair.shape || restored.result != null || !current_block.instructions.find (restored, out position) || !current_block.instructions.find (call, out called) || called <= position + 1) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer restoration lost its exact fallible constructor and original caller pair");
		}
		var write = current_block.instructions[position + 1] as SsaBufferWriteInstruction;
		if (write == null || write.initializes || write.place != argument.disarm.place || write.pair != restored.pair) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer restoration requires immediate complete original caller publication");
		}
		for (uint i = position + 2; i < called; i++) {
			var effect = current_block.instructions[i];
			var other = effect as SsaFallibleBufferRestore;
			var stored = effect as SsaBufferWriteInstruction;
			bool allowed = other != null && other.call == call && call.buffer_restores.find (other);
			if (stored != null) {
				foreach (var candidate in call.buffer_restores) {
					if (stored.pair == candidate.pair && stored.place == candidate.argument.disarm.place) {
						allowed = true;
					}
				}
			}
			if (!allowed) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer restoration crosses an unrelated effect before admission");
			}
		}
		SsaBufferMemoryFlow.verify (function);
		int incoming = graph.join ();
		graph.alternative (incoming, graph.absent ());
		graph.alternative (incoming, buffer_value (argument.pair));
		publish_buffer (restored.pair, incoming);
	}

	private void frame_buffer_restore(SsaFrameBufferRestore restored) throws RuntimeLifetimeError, SsaError {
		var call = restored.creation;
		var argument = restored.argument;
		uint position = 0, called = 0;
		if (call == null || !call.checked_admission || call.exception_result == null || !call.buffer_restores.find (restored) || !call.buffer_arguments.find (argument) || argument.disarm.place.storage == null || argument.disarm.place.storage.record_type != null || restored.pair.shape != argument.pair.shape || restored.result != null || !current_block.instructions.find (restored, out position) || !current_block.instructions.find (call, out called) || called >= position || position + 1 >= current_block.instructions.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame buffer restoration lost its exact original admission and caller pair");
		}
		int registrations = 0;
		foreach (var candidate in call.buffer_restores) {
			if (candidate == restored) {
				registrations++;
			}
		}
		if (registrations != 1) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame buffer restoration requires one original pair publication");
		}
		var write = current_block.instructions[position + 1] as SsaBufferWriteInstruction;
		if (write == null || write.initializes || write.place != argument.disarm.place || write.pair != restored.pair) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame buffer restoration requires immediate complete original caller publication");
		}
		for (uint i = called + 1; i < position; i++) {
			if (!frame_restore_effect (current_block.instructions[i], call)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame buffer restoration crosses another effect after admission");
			}
		}
		SsaBufferMemoryFlow.verify (function);
		int incoming = graph.join ();
		graph.alternative (incoming, graph.absent ());
		graph.alternative (incoming, buffer_value (argument.pair));
		publish_buffer (restored.pair, incoming);
	}

	private void publish_buffer(SsaBufferPair pair, int incoming) throws RuntimeLifetimeError {
		publish (pair.base_value, incoming);
		publish (pair.length_value, graph.absent ());
	}

	private bool record_parameter_owned(int ordinal) {
		foreach (var group in function.struct_parameters) {
			if (group.shape.mode == StructValueMode.MOVE_VALUE && ordinal >= group.first_leaf && ordinal < group.first_leaf + group.shape.leaves.length) {
				var buffer = group.shape.leaves[ordinal - group.first_leaf] as StructBufferLeafPath;
				return buffer != null ? buffer.component == 0 : graph_input (function.parameters[ordinal].semantic_type);
			}
		}
		return false;
	}

	private bool parameter_prefix(SsaInstruction instruction) {
		if (instruction is SsaStructBoundaryAcquire) {
			var acquired = (SsaStructBoundaryAcquire) instruction;
			return acquired.parameter != null && function.struct_parameters.find (acquired.parameter);
		}
		if (instruction is SsaStructParameterBorrow) {
			return function.struct_parameters.find (((SsaStructParameterBorrow) instruction).parameter);
		}
		var buffer_write = instruction as SsaBufferWriteInstruction;
		if (buffer_write != null) {
			return buffer_write.initializes && buffer_write.record_boundary is SsaStructBoundaryAcquire && ((SsaStructBoundaryAcquire) buffer_write.record_boundary).parameter != null;
		}
		var event = instruction as SsaHeapOwnerEvent;
		if (event != null) {
			return event.action == SsaHeapOwnerAction.ACQUIRE && event.value is SsaFunctionParameter && function.parameters.find ((SsaFunctionParameter) event.value);
		}
		var initialized = instruction as SsaInitializeInstruction;
		return initialized != null && initialized.value is SsaFunctionParameter && function.parameters.find ((SsaFunctionParameter) initialized.value);
	}

	private void record_parameters() throws RuntimeLifetimeError {
		var occupied = new HashTable<int, bool> (direct_hash, direct_equal);
		foreach (var group in function.struct_parameters) {
			record_shape (group.shape);
			if (group.first_leaf < 0 || group.first_leaf > function.parameters.length || group.shape.leaves.length > function.parameters.length - group.first_leaf) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime group exceeds its exact parameter range");
			}
			for (int i = 0; i < group.shape.leaves.length; i++) {
				int ordinal = group.first_leaf + i;
				if (occupied.contains (ordinal) || function.parameters[ordinal].semantic_type != group.shape.leaves[i].semantic_type) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime lost its physical leaf correspondence");
				}
				occupied.insert (ordinal, true);
			}
			if (group.shape.mode == StructValueMode.COPY_VALUE) {
				continue;
			}
			int bindings = 0;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var acquired = instruction as SsaStructBoundaryAcquire;
					var borrowed = instruction as SsaStructParameterBorrow;
					if (!(acquired != null && acquired.parameter == group || borrowed != null && borrowed.parameter == group)) {
						continue;
					}
					bindings++;
					var leaves = acquired == null ? borrowed.leaves : acquired.leaves;
					if (block != function.entry || leaves.length != group.shape.leaves.length || (group.shape.mode == StructValueMode.MOVE_VALUE) != (acquired != null) || acquired != null && (acquired.shape != group.shape || acquired.record_type.semantic_type != group.shape.semantic_type || acquired.projection != null || acquired.results != null || acquired.record_move != null || acquired.admission_restore != null)) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime requires its exact complete entry acquisition or borrow");
					}
					for (int i = 0; i < leaves.length; i++) {
						if (leaves[i] != function.parameters[group.first_leaf + i]) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime binding changed its original parameter leaf");
						}
					}
					foreach (var prior in function.entry.instructions) {
						if (prior == instruction) {
							break;
						}
						if (!parameter_prefix (prior)) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime entry binding must precede body operations");
						}
					}
				}
			}
			if (bindings != 1) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime requires one original entry binding");
			}
		}
	}

	private void record_boundary(SsaStructBoundary boundary) throws RuntimeLifetimeError, SsaError {
		record_shape (boundary.shape);
		if (boundary.projection != null) {
			unsupported_node ("SSA projected or buffered record boundary needs exact field/pair correspondence");
			return;
		}
		if (boundary.shape.mode != StructValueMode.MOVE_VALUE || boundary.record_type.semantic_type != boundary.shape.semantic_type || instance (boundary.record_type.semantic_type) != boundary.record_type || boundary.leaves.length != boundary.shape.leaves.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record boundary lost its exact nominal field group");
		}
		var block = (SsaBlock?) null;
		int position = -1;
		foreach (var candidate in function.blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				if (candidate.instructions[i] == boundary) {
					if (block != null) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record boundary has competing instruction sites");
					}
					block = candidate;
					position = i;
				}
			}
		}
		if (block == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record boundary lost its actual instruction site");
		}
		record_buffer_boundary (boundary, block, position);
		int owning = 0;
		for (int l = 0; l < boundary.leaves.length; l++) {
			var leaf = boundary.shape.leaves[l];
			var field = record_field (boundary.record_type, leaf.storage_path ());
			if (field == null || boundary.leaves[l].semantic_type != leaf.semantic_type) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record boundary changed its declared leaf path or type");
			}
			if (field.owned_cleanup != null && !field.owned_cleanup.is_buffer) {
				owning++;
			}
		}
		if (owning != boundary.owners.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record boundary lost a declared owner obligation");
		}
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (int i = 0; i < boundary.owners.length; i++) {
			var owner = boundary.owners[i];
			var path = boundary.owner_path (i);
			var field = record_field (boundary.record_type, path);
			SsaValue? incoming = null;
			for (int l = 0; l < boundary.shape.leaves.length; l++) {
				if (boundary.shape.leaves[l].same_path (path)) {
					incoming = boundary.leaves[l];
				}
			}
			if (!function.heap_owners.find (owner) || owner.record_type != boundary.record_type || owner.source_ordinal != boundary.source_ordinal || owner.record_path == null || !path.same_path (owner.record_path) || owner.record_rank != boundary.owner_rank (i) || field == null || owner.record_field != field || owner.cleanup != field.owned_cleanup || incoming == null || seen.contains (path.spelling ()) || owner.text_extent == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record boundary lost its exact field owner identity or extent");
			}
			seen.insert (path.spelling (), true);
			var event = position + i + 1 >= block.instructions.length ? null : block.instructions[position + i + 1] as SsaHeapOwnerEvent;
			if (event == null || event.effect != boundary || event.owner != owner || event.value != incoming || event.action != ((boundary is SsaStructBoundaryAcquire) ? SsaHeapOwnerAction.ACQUIRE : SsaHeapOwnerAction.MOVE)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record boundary lost its immediate exact owner event");
			}
			record_events.insert (event, true);
		}
	}

	private void record_pairs(StructValueShape shape, GenericArray<SsaValue> leaves, GenericArray<SsaBufferPair> pairs) throws RuntimeLifetimeError {
		record_shape (shape);
		if (leaves.length != shape.leaves.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record lost its complete original leaf group");
		}
		int index = 0;
		for (int l = 0; l < shape.leaves.length; l++) {
			var path = shape.leaves[l] as StructBufferLeafPath;
			if (path == null || path.component != 0) {
				continue;
			}
			if (index >= pairs.length || l + 1 >= leaves.length) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record lost a complete original field pair");
			}
			var pair = pairs[index++];
			if (pair.shape != path.buffer_shape || pair.base_value != leaves[l] || pair.length_value != leaves[l + 1] || !pair.shape.is_valid (record_fields) ) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record changed its original ordered pair or scope-free element contract");
			}
			if (scoped_type (pair.shape.slice_type.element_type) || pair.shape.slice_type is ContextBytesType) {
				unsupported_node ("SSA buffered record needs its exact selected-context or element lifetime contract");
			}
			buffer_pairs.insert (pair, true);
		}
		if (index != pairs.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record repeats or invents a field pair");
		}
	}

	private void record_buffer_boundary(SsaStructBoundary boundary, SsaBlock block, int position) throws RuntimeLifetimeError, SsaError {
		record_pairs (boundary.shape, boundary.leaves, boundary.buffer_pairs);
		if (boundary.buffers.length != boundary.buffer_pairs.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record boundary lost its complete field storage group");
		}
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (int b = 0; b < boundary.buffers.length; b++) {
			var storage = boundary.buffers[b];
			var pair = boundary.buffer_pairs[b];
			var path = boundary.buffer_path (b);
			var field = record_field (boundary.record_type, path);
			if (!function.buffer_storage.find (storage) || storage.record_type != boundary.record_type || storage.record_source_ordinal != boundary.source_ordinal || storage.record_path == null || !storage.record_path.same_path (path) || storage.record_rank != boundary.buffer_rank (b) || field == null || storage.cleanup != field.owned_cleanup || storage.cleanup.buffer_shape != pair.shape || storage.text_extent == null || seen.contains (path.spelling ())) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record boundary lost its exact declared field storage or extent");
			}
			seen.insert (path.spelling (), true);
			int after = position + (int) boundary.owners.length + 1 + b;
			var write = after >= block.instructions.length ? null : block.instructions[after] as SsaBufferWriteInstruction;
			bool acquire = boundary is SsaStructBoundaryAcquire;
			if (write == null || write.record_boundary != boundary || write.place.storage != storage || write.initializes != acquire || (acquire ? write.pair != pair : !write.pair.is_empty || write.pair.shape != pair.shape)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record boundary lost its immediate complete acquisition or source disarm");
			}
		}
		if (boundary.buffers.length != 0) {
			SsaBufferMemoryFlow.verify (function);
		}
	}

	private void record_restored_buffers(SsaRecordAdmissionRestore restored) throws RuntimeLifetimeError {
		var moved = restored.original;
		var acquired = restored.acquisition;
		record_pairs (restored.results.shape, restored.results.leaves, restored.results.buffers);
		if (acquired == null || restored.results.buffers.length != moved.buffers.length || acquired.buffers.length != moved.buffers.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record restoration lost its complete original field group");
		}
		for (int b = 0; b < moved.buffers.length; b++) {
			if (acquired.buffers[b] != moved.buffers[b] || acquired.buffer_pairs[b] != restored.results.buffers[b]) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffered record restoration changed its original caller field or result pair");
			}
		}
	}

	private int record_value(StructValueShape shape, GenericArray<SsaValue> leaves) throws RuntimeLifetimeError {
		record_shape (shape);
		if (shape.leaves.length != leaves.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime lost its complete leaf group");
		}
		int result = product (shape.semantic_type);
		for (int i = 0; i < leaves.length; i++) {
			var leaf = shape.leaves[i];
			var component = leaf as StructBufferLeafPath;
			if (component != null && component.component == 1) {
				continue;
			}
			if (leaf.semantic_type != leaves[i].semantic_type) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record lifetime changed a leaf type");
			}
			var path = new StringBuilder ();
			for (int depth = 0; depth < leaf.depth; depth++) {
				if (path.len != 0) {
					path.append_c ('.');
				}
				path.append_printf ("f%d", leaf.field_ordinal (depth));
			}
			int incoming = recent_moves.contains (leaves[i]) ? state.bindings.lookup (recent_moves.lookup (leaves[i])) : value (leaves[i]);
			result = replace_path (result, path.str, incoming);
		}
		return result;
	}

	private int record_result(SsaStructReturn result, SsaBlock block) throws RuntimeLifetimeError {
		if (result.shape != function.struct_result || result.shape.semantic_type != function.return_type || result.shape.leaves.length != result.leaves.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result lost its exact declared shape or leaf group");
		}
		record_shape (result.shape);
		if (result.shape.mode == StructValueMode.MOVE_VALUE) {
			var moved = result.record_move;
			if (moved == null || moved.consumer != result || moved.use_kind != StructResultUseKind.RETURN || moved.shape != result.shape || moved.leaves.length != result.leaves.length) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result lost its exact complete move publication");
			}
			int sites = 0;
			foreach (var instruction in block.instructions) {
				if (instruction == moved) {
					sites++;
				}
			}
			if (sites != 1) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result requires one original same-block move publication");
			}
			for (int i = 0; i < result.leaves.length; i++) {
				if (result.leaves[i] != moved.leaves[i]) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result changed an original physical field value");
				}
			}
		} else if (result.shape.mode == StructValueMode.COPY_VALUE) {
			if (result.record_move != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA copied record result cannot consume an owner group");
			}
			foreach (var leaf in result.shape.leaves) {
				var type = leaf.semantic_type;
				if (!(type is IntegerType) && !(type is FloatingType) && !(type is VectorType) && type.kind != TypeKind.BOOL) {
					unsupported_node ("SSA copied record result requires its exact nonowning field correspondence");
				}
			}
		} else {
			unsupported_node ("SSA borrowed record result requires its exact output loan");
		}
		int value = record_value (result.shape, result.leaves);
		foreach (var leaf in result.leaves) {
			consume (leaf);
		}
		return value;
	}

	private int record_component(int incoming, StructLeafPath leaf) throws RuntimeLifetimeError {
		var component = leaf as StructBufferLeafPath;
		return component != null && component.component == 1 ? graph.absent () : graph.project (incoming, record_path (leaf));
	}

	private string record_path(StructLeafPath leaf) {
		var path = new StringBuilder ();
		for (int depth = 0; depth < leaf.depth; depth++) {
			if (path.len != 0) {
				path.append_c ('.');
			}
			path.append_printf ("f%d", leaf.field_ordinal (depth));
		}
		return path.str;
	}

	private void record_call(SsaCallInstruction call, SsaBlock block) throws RuntimeLifetimeError {
		var group = call.struct_result;
		if (group == null) {
			return;
		}
		record_shape (group.shape);
		if (call.target.struct_result != group.shape || group.shape.semantic_type != call.target.return_type || group.leaves.length != group.shape.leaves.length || record_calls.contains (group)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record call lost its unique exact declared result group");
		}
		if (call.target.throws_type != null) {
			var branch = block.terminator as SsaConditionalBranch;
			var condition = block.instructions.length < 2 ? null : block.instructions[block.instructions.length - 1] as SsaBinaryInstruction;
			if (call.exception_result == null || branch == null || condition == null || condition.result != branch.condition || condition.operator_kind != BinaryOperator.EQUAL || condition.left != call.exception_result || !(condition.right is SsaNullPointerConstant) || branch.true_edge.target == branch.false_edge.target || block.instructions[block.instructions.length - 2] != call) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked record call requires its exact original success/error test");
			}
			var publication = branch.true_edge.target;
			SsaGroupCallSuccess? success = null;
			foreach (var candidate in function.blocks) {
				foreach (var instruction in candidate.instructions) {
					var marker = instruction as SsaGroupCallSuccess;
					if (marker != null && marker.call == call) {
						if (success != null || candidate != publication || candidate.instructions[0] != marker) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked record requires one original guarded success publication");
						}
						success = marker;
					}
				}
				foreach (var next in candidate.terminator.successors ()) {
					if (next == publication && candidate != block) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked record success gained an unguarded predecessor");
					}
				}
			}
			if (success == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked record lost its original success publication");
			}
			record_successes.insert (call, success);
			record_success_blocks.insert (call, publication);
			record_pending.insert (call, graph.join ());
		}
		record_calls.insert (group, call);
		for (int i = 0; i < group.leaves.length; i++) {
			var leaf = group.leaves[i];
			if (leaf.semantic_type != group.shape.leaves[i].semantic_type || values.contains (leaf) || definitions.contains (leaf)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record call changed or repeated an original result leaf");
			}
			values.insert (leaf, graph.join ());
			definitions.insert (leaf, call);
			if (group.shape.mode == StructValueMode.MOVE_VALUE && graph_input (leaf.semantic_type) && !pending.contains (leaf)) {
				pending.insert (leaf, slot ());
			}
			if (call.target.throws_type != null) {
				checked_record_leaves.insert (leaf, call);
			}
		}
	}

	private SsaBlock? record_site(SsaInstruction source, out int position) throws RuntimeLifetimeError {
		SsaBlock? site = null;
		position = -1;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] == source) {
					if (site != null) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record effect has competing instruction sites");
					}
					site = block;
					position = i;
				}
			}
		}
		return site;
	}

	private bool admission_effect(SsaInstruction instruction, SsaLifecycleCallInstruction call) {
		if (instruction is SsaFallibleInputRestore) {
			return call.input_restores.find ((SsaFallibleInputRestore) instruction);
		}
		if (instruction is SsaFallibleBufferRestore) {
			return call.buffer_restores.find ((SsaFallibleBufferRestore) instruction);
		}
		if (instruction is SsaFallibleRecordRestore) {
			return call.record_restores.find ((SsaFallibleRecordRestore) instruction);
		}
		var event = instruction as SsaHeapOwnerEvent;
		if (event != null && event.action == SsaHeapOwnerAction.ACQUIRE && event.effect is SsaFallibleInputRestore) {
			return call.input_restores.find ((SsaFallibleInputRestore) event.effect);
		}
		var write = instruction as SsaBufferWriteInstruction;
		if (write != null) {
			foreach (var restore in call.buffer_restores) {
				if (write.pair == restore.pair && write.place == restore.argument.disarm.place) {
					return true;
				}
			}
		}
		foreach (var restore in call.record_restores) {
			var consumed = instruction as SsaStructResultConsume;
			if (consumed != null && consumed.results == restore.results || instruction == restore.acquisition || event != null && event.action == SsaHeapOwnerAction.ACQUIRE && event.effect == restore.acquisition) {
				return true;
			}
		}
		return false;
	}

	private bool frame_restore_effect(SsaInstruction instruction, SsaTaskCreate creation) {
		if (instruction is SsaFrameInputRestore) {
			return creation.input_restores.find ((SsaFrameInputRestore) instruction);
		}
		if (instruction is SsaFrameBufferRestore) {
			return creation.buffer_restores.find ((SsaFrameBufferRestore) instruction);
		}
		if (instruction is SsaFrameRecordRestore) {
			return creation.record_restores.find ((SsaFrameRecordRestore) instruction);
		}
		var event = instruction as SsaHeapOwnerEvent;
		if (event != null && event.action == SsaHeapOwnerAction.ACQUIRE && event.effect is SsaFrameInputRestore) {
			return creation.input_restores.find ((SsaFrameInputRestore) event.effect);
		}
		var write = instruction as SsaBufferWriteInstruction;
		if (write != null) {
			foreach (var restored in creation.buffer_restores) {
				if (write.pair == restored.pair && write.place == restored.argument.disarm.place) {
					return true;
				}
			}
		}
		foreach (var restored in creation.record_restores) {
			var consumed = instruction as SsaStructResultConsume;
			if (consumed != null && consumed.results == restored.results || instruction == restored.acquisition || event != null && event.action == SsaHeapOwnerAction.ACQUIRE && event.effect == restored.acquisition || write != null && write.record_boundary == restored.acquisition) {
				return true;
			}
		}
		return false;
	}

	private void frame_record_restore(SsaFrameRecordRestore restored) throws RuntimeLifetimeError {
		var call = restored.creation;
		var moved = restored.original;
		var group = restored.results;
		var acquired = restored.acquisition;
		int position, called = -1, committed;
		var site = record_site (restored, out position);
		var call_site = call == null ? null : record_site (call, out called);
		var move_site = record_site (moved, out committed);
		if (call == null || call.target == null || !call.checked_admission || call.exception_result == null || !call.record_restores.find (restored) || !call.record_moves.find (moved) || moved.consumer != call || moved.use_kind != StructResultUseKind.ARGUMENT || site != current_block || call_site != site || move_site != site || committed >= called || called >= position || restored.admission_value () != call.result || group.shape != moved.shape || group.shape.mode != StructValueMode.MOVE_VALUE || group.leaves.length != moved.leaves.length || record_restores.lookup (group) != restored || acquired == null || acquired.admission_restore != restored || acquired.results != group || acquired.record_type != moved.record_type || acquired.source_ordinal != moved.source_ordinal || acquired.owners.length != moved.owners.length || group.buffers.length != moved.buffers.length || acquired.buffers.length != moved.buffers.length || position + 2 >= site.instructions.length || site.instructions[position + 2] != acquired) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration lost its exact original capture, admission or caller acquisition");
		}
		record_shape (group.shape);
		record_restored_buffers (restored);
		int registrations = 0, moves = 0;
		foreach (var candidate in call.record_restores) {
			if (candidate == restored) {
				registrations++;
			}
		}
		foreach (var candidate in call.record_moves) {
			if (candidate == moved) {
				moves++;
			}
		}
		if (registrations != 1 || moves != 1 || call.struct_arguments.length != call.target.struct_parameters.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration requires one original move and restoration");
		}
		int matches = 0;
		for (int g = 0; g < call.struct_arguments.length; g++) {
			var argument = call.struct_arguments[g];
			var parameter = call.target.struct_parameters[g];
			if (argument.first_leaf != parameter.first_leaf || argument.source_ordinal != parameter.source_ordinal || argument.shape.semantic_type != parameter.shape.semantic_type || argument.shape.mode != parameter.shape.mode || argument.first_leaf < 0 || argument.first_leaf + argument.shape.leaves.length > call.arguments.length) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration changed its original parameter group");
			}
			if (argument.shape == moved.shape && argument.shape.leaves.length == moved.leaves.length) {
				bool exact = true;
				for (int l = 0; l < moved.leaves.length; l++) {
					exact = exact && call.arguments[argument.first_leaf + l] == moved.leaves[l];
				}
				if (exact) {
					matches++;
				}
			}
		}
		if (matches != 1) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration requires its complete original argument");
		}
		for (int i = 0; i < moved.owners.length; i++) {
			if (acquired.owners[i] != moved.owners[i]) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration changed an original caller field owner");
			}
		}
		var consumed = site.instructions[position + 1] as SsaStructResultConsume;
		if (consumed == null || consumed.results != group || consumed.use_kind != StructResultUseKind.INITIALIZE) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration requires immediate complete caller consumption");
		}
		for (int i = called + 1; i < position; i++) {
			if (!frame_restore_effect (site.instructions[i], call)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration crosses another effect after admission");
			}
		}
		for (int l = 0; l < group.leaves.length; l++) {
			if (group.leaves[l].semantic_type != moved.shape.leaves[l].semantic_type) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration changed a physical leaf type");
			}
			int incoming = value (moved.leaves[l]);
			if (restored.owning_leaf (l)) {
				int optional = graph.join ();
				graph.alternative (optional, graph.absent ());
				graph.alternative (optional, incoming);
				incoming = optional;
			}
			publish (group.leaves[l], incoming);
		}
	}

	private void record_restore(SsaFallibleRecordRestore restored) throws RuntimeLifetimeError {
		var call = restored.call;
		var moved = restored.original;
		var group = restored.results;
		var acquired = restored.acquisition;
		int position, called = -1, committed;
		var site = record_site (restored, out position);
		var call_site = call == null ? null : record_site (call, out called);
		var move_site = record_site (moved, out committed);
		if (call == null || call.target == null || !call.constructs || !call.storage.fallible || !call.storage.heap_allocated || !call.record_restores.find (restored) || !call.record_moves.find (moved) || moved.consumer != call || moved.use_kind != StructResultUseKind.ARGUMENT || site != current_block || call_site != site || move_site != site || committed >= position || position + 2 >= called || restored.admission_value () != call.receiver || group.shape != moved.shape || group.shape.mode != StructValueMode.MOVE_VALUE || group.leaves.length != moved.leaves.length || record_restores.lookup (group) != restored || acquired == null || acquired.admission_restore != restored || acquired.results != group || acquired.record_type != moved.record_type || acquired.source_ordinal != moved.source_ordinal || acquired.owners.length != moved.owners.length || group.buffers.length != moved.buffers.length || acquired.buffers.length != moved.buffers.length || site.instructions[position + 2] != acquired) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration lost its exact captured group, constructor or caller acquisition");
		}
		record_shape (group.shape);
		record_restored_buffers (restored);
		int registrations = 0, moves = 0;
		foreach (var candidate in call.record_restores) {
			if (candidate == restored) {
				registrations++;
			}
		}
		foreach (var candidate in call.record_moves) {
			if (candidate == moved) {
				moves++;
			}
		}
		if (registrations != 1 || moves != 1 || call.struct_arguments.length != call.target.struct_parameters.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration requires one original move, restore and exact argument groups");
		}
		for (int g = 0; g < call.struct_arguments.length; g++) {
			var argument = call.struct_arguments[g];
			var parameter = call.target.struct_parameters[g];
			if (argument.first_leaf != parameter.first_leaf || argument.source_ordinal != parameter.source_ordinal || argument.shape.semantic_type != parameter.shape.semantic_type || argument.shape.mode != parameter.shape.mode) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration changed its exact original parameter group");
			}
		}
		int matches = 0;
		foreach (var argument in call.struct_arguments) {
			if (argument.shape != moved.shape || argument.first_leaf < 0 || argument.first_leaf + moved.leaves.length > call.arguments.length) {
				continue;
			}
			bool exact = true;
			for (int l = 0; l < moved.leaves.length; l++) {
				exact = exact && call.arguments[argument.first_leaf + l] == moved.leaves[l];
			}
			if (exact) {
				matches++;
			}
		}
		if (matches != 1) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration lost its original complete call argument");
		}
		for (int i = 0; i < moved.owners.length; i++) {
			if (acquired.owners[i] != moved.owners[i]) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration changed an original caller field owner");
			}
		}
		var consumed = site.instructions[position + 1] as SsaStructResultConsume;
		if (consumed == null || consumed.results != group || consumed.use_kind != StructResultUseKind.INITIALIZE) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration requires immediate complete caller consumption");
		}
		for (int i = position + 3 + (int) moved.owners.length + (int) moved.buffers.length; i < called; i++) {
			if (!admission_effect (site.instructions[i], call)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration crosses another effect before admission");
			}
		}
		for (int l = 0; l < group.leaves.length; l++) {
			if (group.leaves[l].semantic_type != moved.shape.leaves[l].semantic_type) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration changed a physical leaf type");
			}
			int incoming = pending.contains (moved.leaves[l]) ? state.bindings.lookup (pending.lookup (moved.leaves[l])) : value (moved.leaves[l]);
			if (restored.owning_leaf (l)) {
				int optional = graph.join ();
				graph.alternative (optional, graph.absent ());
				graph.alternative (optional, incoming);
				incoming = optional;
			}
			publish (group.leaves[l], incoming);
		}
	}

	private void task_record(SsaTaskSuccess success, SsaBlock publication) throws RuntimeLifetimeError {
		var group = success.struct_result;
		var wait = success.operation;
		var task = wait.child.semantic_type as TaskType;
		if (group == null || task == null || wait.success != success || wait.discard || success.result != null || success.enum_result != null || success.buffer_result != null || success.success_type != group.shape.semantic_type || task.success_type.logical_identity != success.success_type.logical_identity || task_records.contains (group) || record_calls.contains (group) || group.leaves.length != group.shape.leaves.length || publication.instructions[0] != success) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task record lost its complete original success group");
		}
		record_shape (group.shape);
		int position;
		var waited = record_site (wait, out position);
		var branch = waited == null ? null : waited.terminator as SsaConditionalBranch;
		var condition = waited == null || waited.instructions.length < 2 ? null : waited.instructions[waited.instructions.length - 1] as SsaBinaryInstruction;
		if (waited == null || position != waited.instructions.length - 2 || condition == null || branch == null || condition.result != branch.condition || condition.operator_kind != BinaryOperator.EQUAL || condition.left != wait.result || !(condition.right is SsaNullPointerConstant) || branch.true_edge.target != publication || branch.false_edge.target == publication) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task record requires its exact original success/error test");
		}
		foreach (var block in function.blocks) {
			foreach (var next in block.terminator.successors ()) {
				if (next == publication && block != waited) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task record success gained an unguarded predecessor");
				}
			}
		}
		task_records.insert (group, success);
		for (int i = 0; i < group.leaves.length; i++) {
			var leaf = group.leaves[i];
			if (leaf.semantic_type != group.shape.leaves[i].semantic_type || values.contains (leaf) || definitions.contains (leaf)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task record changed an original physical result leaf");
			}
			values.insert (leaf, graph.join ());
			definitions.insert (leaf, success);
			task_record_blocks.insert (leaf, publication);
			if (group.shape.mode == StructValueMode.MOVE_VALUE && graph_input (leaf.semantic_type)) {
				pending.insert (leaf, slot ());
			}
		}
	}

	private void record_consumption(SsaStructResultConsume consumed) throws RuntimeLifetimeError {
		if (record_restores.contains (consumed.results)) {
			var restored = record_restores.lookup (consumed.results);
			int position;
			var site = record_site (consumed, out position);
			if (site == null || position == 0 || site.instructions[position - 1] != restored || consumed.use_kind != StructResultUseKind.INITIALIZE || record_consumptions.contains (consumed.results)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration lost its unique immediate result consumption");
			}
			record_consumptions.insert (consumed.results, consumed);
			return;
		}
		var call = record_calls.lookup (consumed.results);
		var task = task_records.lookup (consumed.results);
		if (call == null && task == null || consumed.use_kind != StructResultUseKind.INITIALIZE) {
			unsupported_node ("SSA record result consumption requires its exact direct producer and local acquisition");
			return;
		}
		int position;
		var block = record_site (consumed, out position);
		if (block == null || record_consumptions.contains (consumed.results)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result consumption lost its unique original site");
		}
		var acquired = position + 1 < block.instructions.length ? block.instructions[position + 1] as SsaStructBoundaryAcquire : null;
		if (consumed.results.shape.mode == StructValueMode.MOVE_VALUE && (acquired == null || acquired.results != consumed.results)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result consumption lost its immediate original owner acquisition");
		}
		bool producer = false;
		for (int i = 0; i < position; i++) {
			if (block.instructions[i] == task || block.instructions[i] == call || record_successes.lookup (call) == block.instructions[i] && record_success_blocks.lookup (call) == block) {
				producer = true;
			}
		}
		if (!producer) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result consumption must follow its original call or guarded success publication");
		}
		record_consumptions.insert (consumed.results, consumed);
	}

	private void record_acquisition(SsaStructBoundaryAcquire acquired) throws RuntimeLifetimeError {
		if (acquired.parameter != null) {
			if (!function.struct_parameters.find (acquired.parameter) || acquired.results != null || acquired.record_move != null || acquired.projection != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its exclusive parameter correspondence");
			}
			return;
		}
		var consumed = acquired.results == null ? null : record_consumptions.lookup (acquired.results);
		if (consumed == null) {
			unsupported_node ("SSA record acquisition requires its exact producer correspondence");
			return;
		}
		if (acquired.projection != null || acquired.record_move != null || acquired.admission_restore != null && record_restores.lookup (acquired.results) != acquired.admission_restore || acquired.shape.mode != StructValueMode.MOVE_VALUE || acquired.results.shape != acquired.shape || acquired.leaves.length != acquired.results.leaves.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result acquisition lost its exact complete original group");
		}
		int position;
		var block = record_site (acquired, out position);
		if (block == null || position == 0 || block.instructions[position - 1] != consumed) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result acquisition requires its immediate original consumption");
		}
		for (int i = 0; i < acquired.leaves.length; i++) {
			if (acquired.leaves[i] != acquired.results.leaves[i]) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result acquisition changed an original producer field");
			}
		}
	}

	private SsaStruct record_owner(SsaHeapOwner owner, StructLeafPath? path, int rank, SsaValue pointer, GenericArray<SsaValue> fields) throws RuntimeLifetimeError {
		var record = owner.record_type;
		if (!function.heap_owners.find (owner) || record == null || instance (record.semantic_type) != record || path == null || owner.record_path == null || !path.same_path (owner.record_path) || rank != owner.record_rank || owner.text_extent == null || owner.record_field != record_field (record, path) || owner.record_field == null || owner.record_field.owned_cleanup != owner.cleanup || fields.length != 1 || fields[0] != pointer || pointer.semantic_type != path.semantic_type) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its exact field owner, pointer or extent");
		}
		return record;
	}

	private void record_acquire(SsaRecordAcquire acquired) throws RuntimeLifetimeError {
		var owner = acquired.owner;
		var path = acquired.path;
		var record = record_owner (owner, path, acquired.rank, acquired.pointer, acquired.fields);
		SsaBlock? site = null;
		int position = -1;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] == acquired) {
					if (site != null) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition has competing instruction sites");
					}
					site = block;
					position = i;
				}
			}
		}
		if (site == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its actual instruction site");
		}
		var event = position + 1 < site.instructions.length ? site.instructions[position + 1] as SsaHeapOwnerEvent : null;
		if (event == null || event.action != SsaHeapOwnerAction.ACQUIRE || event.owner != owner || event.value != acquired.pointer || event.effect != acquired) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its immediate exact owner event");
		}
		// Promoted fields are represented by the exact field owner and its
		// value event. Addressable records additionally require the actual store.
		bool addressable = false;
		foreach (var storage in function.storage) {
			if (storage.source_local_ordinal == owner.source_ordinal) {
				if (storage.semantic_type != record.semantic_type || storage.structure != record) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its exact addressable declaration");
				}
				addressable = true;
			}
		}
		if (addressable) {
			var initialized = position + 2 < site.instructions.length ? site.instructions[position + 2] as SsaInitializeInstruction : null;
			var target = initialized == null ? null : place (initialized.target);
			var expected = new StringBuilder ();
			for (int depth = 0; depth < path.depth; depth++) {
				if (expected.len != 0) {
					expected.append_c ('.');
				}
				expected.append_printf ("f%d", path.field_ordinal (depth));
			}
			if (initialized == null || initialized.value != acquired.pointer || target == null || target.destination != owner.source_ordinal || target.path != expected.str) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its exact physical field initialization");
			}
		}
		record_events.insert (event, true);
		if (acquired.source_owner != null) {
			var source = acquired.source_owner;
			var prior = position > 0 ? site.instructions[position - 1] as SsaHeapOwnerEvent : null;
			if (!function.heap_owners.find (source) || source.record_type != null || source.cleanup != owner.cleanup || prior == null || prior.action != SsaHeapOwnerAction.MOVE || prior.owner != source || prior.value != acquired.pointer || !recent_moves.contains (acquired.pointer)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its exact incoming owner move");
			}
		} else {
			var call = definition (acquired.pointer) as SsaCallInstruction;
			if (call == null || call.target.throws_type != null) {
				unsupported_node ("SSA record acquisition requires its exact owned producer correspondence");
			} else if (call.result != acquired.pointer || call.target.owned_cleanup != owner.cleanup) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record acquisition lost its exact direct owned call result");
			}
		}
	}

	private void record_move(SsaRecordMove moved) throws RuntimeLifetimeError {
		var source = moved.source;
		var target = moved.destination;
		var record = record_owner (source, moved.path, moved.rank, moved.pointer, moved.fields);
		record_owner (target, moved.path, moved.rank, moved.pointer, moved.fields);
		if (source == target || source.source_ordinal == target.source_ordinal || target.record_type != record || target.record_field != source.record_field || target.cleanup != source.cleanup) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move lost its exact distinct source and destination fields");
		}
		foreach (var storage in function.storage) {
			if (storage.source_local_ordinal == source.source_ordinal || storage.source_local_ordinal == target.source_ordinal) {
				unsupported_node ("SSA addressable record move requires its exact physical field stores");
			}
		}
		foreach (var storage in function.buffer_storage) {
			if (storage.record_type == record && (storage.record_source_ordinal == source.source_ordinal || storage.record_source_ordinal == target.source_ordinal)) {
				unsupported_node ("SSA record move requires its exact buffer field correspondence");
			}
		}
		SsaBlock? site = null;
		int position = -1;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] == moved) {
					if (site != null) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move has competing instruction sites");
					}
					site = block;
					position = i;
				}
			}
		}
		if (site == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move lost its actual instruction site");
		}
		var released = position + 1 < site.instructions.length ? site.instructions[position + 1] as SsaHeapOwnerEvent : null;
		var acquired = position + 2 < site.instructions.length ? site.instructions[position + 2] as SsaHeapOwnerEvent : null;
		if (released == null || released.action != SsaHeapOwnerAction.MOVE || released.owner != source || released.value != moved.pointer || released.effect != moved || acquired == null || acquired.action != SsaHeapOwnerAction.ACQUIRE || acquired.owner != target || acquired.value != moved.pointer) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move lost its immediate exact source and destination events");
		}
		var declared = new HashTable<string, bool> (str_hash, str_equal);
		try {
			foreach (var path in StructLeafOrder.enumerate_storage (record.semantic_type, record_fields)) {
				var field = record_field (record, path);
				if (field != null && field.owned_cleanup != null) {
					if (field.owned_cleanup.is_buffer) {
						unsupported_node ("SSA record move requires its exact buffer field correspondence");
					} else {
						declared.insert (path.spelling (), true);
					}
				}
			}
		} catch (StructLeafError failure) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move lost its declared field order: %s", failure.message);
		}
		var expected = new HashTable<string, bool> (str_hash, str_equal);
		var destinations = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var owner in function.heap_owners) {
			if (owner.record_type != record || owner.source_ordinal != source.source_ordinal && owner.source_ordinal != target.source_ordinal) {
				continue;
			}
			if (owner.record_path == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move lost a declared field path");
			}
			var paths = owner.source_ordinal == source.source_ordinal ? expected : destinations;
			if (paths.contains (owner.record_path.spelling ())) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move repeats a declared field obligation");
			}
			paths.insert (owner.record_path.spelling (), true);
		}
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var instruction in site.instructions) {
			var field = instruction as SsaRecordMove;
			if (field == null || field.source.source_ordinal != source.source_ordinal || field.destination.source_ordinal != target.source_ordinal || field.source.record_type != record) {
				continue;
			}
			if (field.path == null || seen.contains (field.path.spelling ()) || !expected.contains (field.path.spelling ()) || !destinations.contains (field.path.spelling ())) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move lost its unique complete field group");
			}
			seen.insert (field.path.spelling (), true);
		}
		if (seen.size () != expected.size () || seen.size () != destinations.size () || seen.size () != declared.size ()) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move omitted a declared source or destination field");
		}
		foreach (var path in seen.get_keys ()) {
			if (!declared.contains (path)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record move invented a field outside its original declaration");
			}
		}
		record_events.insert (released, true);
		record_events.insert (acquired, true);
	}

	private int value(SsaValue? source) throws RuntimeLifetimeError {
		if (source != null && graph_input (source.semantic_type) && task_record_blocks.contains (source) && task_record_blocks.lookup (source) != current_block) {
			var acquired = reference (source);
			if (acquired == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task record leaf escaped its exact success publication or live acquired owner");
			}
			return read (acquired);
		}
		if (source != null && graph_input (source.semantic_type) && checked_record_leaves.contains (source) && record_success_blocks.lookup (checked_record_leaves.lookup (source)) != current_block) {
			var acquired = reference (source);
			if (acquired == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked record leaf escaped its exact success publication or live acquired owner");
			}
			return read (acquired);
		}
		if (source == null || source is SsaNullPointerConstant || source is SsaTaskAbsent) {
			return graph.absent ();
		}
		if (values.contains (source)) {
			return values.lookup (source);
		}
		if (graph_input (source.semantic_type)) {
			unsupported_node ("SSA owner value lacks its actual definition");
		}
		return graph.absent ();
	}

	private void publish(SsaValue? result, int incoming) throws RuntimeLifetimeError {
		if (result != null) {
			if (!values.contains (result)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA definition is absent from the lifetime inventory");
			}
			graph.alternative (values.lookup (result), incoming);
		}
	}

	private RuntimeScopeOrigin? context_origin(SsaValue? value, SsaHeapOwner? exact_owner = null) throws RuntimeLifetimeError {
		if (value == null || !value.semantic_type.is_scoped_allocator ()) {
			return null;
		}
		if (value is SsaFunctionParameter) {
			var parameter = (SsaFunctionParameter) value;
			if (exact_owner != null || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA scoped context parameter lost its borrowed signature");
			}
			return new RuntimeScopeOrigin.context_input (parameter_index (parameter));
		}
		SsaHeapOwner? owner = exact_owner;
		if (owner == null) {
			var candidates = acquisitions.lookup (value);
			if (candidates != null && candidates.length == 1) {
				owner = candidates[0];
			}
		}
		var factory = owner == null ? null : contexts.lookup (owner);
		if (factory == null || owner.text_extent == null || factory.result != value || factory.loan.context_ordinal != owner.source_ordinal || factory.loan.region_ordinal != owner.text_extent.ordinal) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA scoped allocation lost its exact context owner and definition");
		}
		var facts = lifetimes == null ? null : lifetimes.before.lookup (current_instruction);
		if (facts == null || facts.state (owner.ordinal) != 2) {
			throw new RuntimeLifetimeError.LOCAL_ESCAPE ("SSA scoped allocation uses a context outside its actual live obligation (function=%s, owner=%d, source=%d, state=%u, instruction=%s)", function.name, owner.ordinal, owner.source_ordinal, facts == null ? 0U : facts.state (owner.ordinal), current_instruction == null ? "none" : current_instruction.get_type ().name ());
		}
		return new RuntimeScopeOrigin.local (owner.source_ordinal, region_id (owner.text_extent));
	}

	private void task_error(SsaValue result, int incoming) throws RuntimeLifetimeError {
		publish (result, incoming);
		if (!private_errors.contains (result)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task error lost its exact private channel");
		}
		state.bindings.insert (private_errors.lookup (result), incoming);
	}

	private int task_create(SsaTaskCreate call) throws RuntimeLifetimeError, SsaError {
		buffer_arguments (call);
		if (call.checked_admission) {
			if (call.record_restores.length != call.record_moves.length || call.buffer_restores.length != call.buffer_arguments.length) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame restoration lost its complete original capture groups");
			}
			foreach (var moved in call.record_moves) {
				int matches = 0;
				foreach (var restored in call.record_restores) {
					if (restored.creation == call && restored.original == moved && current_block.instructions.find (restored)) {
						matches++;
					}
				}
				if (matches != 1) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame record restoration requires one original captured group and instruction");
				}
			}
			foreach (var argument in call.buffer_arguments) {
				int matches = 0;
				foreach (var restored in call.buffer_restores) {
					if (restored.creation == call && restored.argument == argument && current_block.instructions.find (restored)) {
						matches++;
					}
				}
				if (matches != 1) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame buffer restoration requires one original captured pair and instruction");
				}
			}
		}
		if (call.target == null || call.target.async_body == null || !call.matches_captures () || call.result == null || call.result.semantic_type != call.target.async_body.task_type || call.checked_admission != (call.exception_result != null)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA cold task lost its exact factory/capture/admission contract");
		}
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		for (int i = 0; i < call.arguments.length; i++) {
			var argument = call.arguments[i];
			inputs.insert (i, pending.contains (argument) ? state.bindings.lookup (pending.lookup (argument)) : value (argument));
			var anchor = context_origin (argument);
			if (anchor != null) {
				anchors.insert (i, anchor);
			}
		}
		var summary = analysis.summary (call.target);
		if (summary == null || !summary.complete || summary.has_exception || summary.store_count != 0 || summary.updated_inputs ().length != 0) {
			unsupported_node ("SSA cold task requires a complete deferred body lifetime contract");
			return graph.absent ();
		}
		int task = summary.equations.instantiate (summary.result, graph, inputs, anchors);
		var context = context_origin (call.allocation_context, call.context_owner);
		if (context != null) {
			var roots = new GenericArray<RuntimeScopeOrigin> ();
			roots.add (context);
			var fields = new HashTable<string, int> (str_hash, str_equal);
			foreach (string edge in new string[] { "f0", "f1", "f2" }) {
				fields.insert (edge, graph.project (task, edge));
			}
			task = graph.product (roots, fields);
		}
		if (call.exception_result != null) {
			task_error (call.exception_result, graph.absent ());
			foreach (var restored in call.input_restores) {
				if (restored.creation != call || !call.owned_arguments.find (restored.argument) || !function.heap_owners.find (restored.owner) || restored.owner.source_ordinal != restored.argument.source_ordinal || !pending.contains (restored.argument.value)) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame refusal lost its exact captured caller input");
				}
				int optional = graph.join ();
				graph.alternative (optional, graph.absent ());
				graph.alternative (optional, state.bindings.lookup (pending.lookup (restored.argument.value)));
				frame_inputs.insert (restored, optional);
			}
		}
		return task;
	}

	private void empty_enum(SsaEnumSlot slot) {
		if (slot.definition.value_fields ().length != 0) {
			unsupported_node ("SSA enum lifetime requires its exact payload operation");
		}
	}

	private int invoke(SsaFunction? target, GenericArray<SsaValue> arguments, SsaValue? receiver, GenericArray<SsaOwnedArgument>? owned_arguments = null, int constructed = -1, SsaValue? exception_result = null) throws RuntimeLifetimeError, SsaError {
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		var destinations = new HashTable<int, SsaRuntimeStorage> (direct_hash, direct_equal);
		if (constructed >= 0) {
			inputs.insert (-1, constructed);
		} else if (receiver != null) {
			var destination = reference (receiver);
			inputs.insert (-1, destination == null ? value (receiver) : read (destination));
			if (destination != null) {
				destinations.insert (-1, destination);
			}
		}
		for (int i = 0; i < arguments.length; i++) {
			var argument = arguments[i];
			var destination = reference (argument);
			bool owned_input = false;
			if (owned_arguments != null) {
				foreach (var transfer in owned_arguments) {
					if (target != null && transfer.parameter == target.parameters[i]) {
						owned_input = true;
					}
				}
			}
			int incoming = owned_input && pending.contains (argument) ? state.bindings.lookup (pending.lookup (argument)) : destination != null && target != null && target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE ? read (destination) : value (argument);
			inputs.insert (i, incoming);
			var anchor = context_origin (argument);
			if (anchor != null) {
				anchors.insert (i, anchor);
			}
			if (destination != null) {
				destinations.insert (i, destination);
			}
		}
		var summary = analysis.summary (target);
		if (summary == null || !summary.complete || target.dispatch_kind != ClassDispatchKind.DIRECT) {
			unsupported_node ("SSA call requires a complete direct lifetime summary: " + (target == null ? "missing target" : target.name) + (summary == null ? " (unavailable)" : " (" + summary.limitation + ")"));
			return constructed >= 0 ? constructed : graph.absent ();
		}
		for (uint i = 0; i < summary.store_count; i++) {
			var stored = summary.store (i);
			int incoming = summary.equations.instantiate (stored.value, graph, inputs, anchors);
			var destination = destinations.lookup (stored.parameter);
			if (destination == null) {
				if (!(constructed >= 0 && stored.parameter == -1)) {
					unsupported_node ("SSA call store lacks its exact cleanup extent");
				}
			} else if (destination.private_exception) { /* The private owner remains in state until its exact disposition. */
			} else if (destination.destination >= 0) {
				bounds.add (new SsaRuntimeBound (incoming, destination.destination));
			} else {
				stores.add (new RuntimeLifetimeStore (destination.destination == -1 ? -1 : -destination.destination - 2, incoming));
			}
		}
		int result = constructed >= 0 ? constructed : summary.equations.instantiate (summary.result, graph, inputs, anchors);
		var updates = summary.updated_inputs ();
		for (int u = 0; u < updates.length; u++) {
			int parameter = updates[u];
			int incoming = summary.equations.instantiate (summary.update (parameter), graph, inputs, anchors);
			if (constructed >= 0 && parameter == -1) {
				result = incoming;
			} else {
				write (destinations.lookup (parameter), incoming, false);
			}
		}
		if (target.throws_type != null) {
			if (!summary.has_exception || exception_result == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA throwing call lost its exceptional lifetime channel");
			}
			int failure = summary.equations.instantiate (summary.exception, graph, inputs, anchors);
			publish (exception_result, failure);
			if (!private_errors.contains (exception_result)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA exception result lost its private owner binding");
			}
			state.bindings.insert (private_errors.lookup (exception_result), failure);
		} else if (summary.has_exception || exception_result != null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA nonthrowing call gained an exceptional lifetime channel");
		}
		return result;
	}

	private void consume(SsaValue value) {
		if (pending.contains (value)) {
			state.bindings.insert (pending.lookup (value), graph.absent ());
			recent_moves.remove (value);
		}
	}

	private void ordinary_buffer(SsaCleanupContract cleanup) {
		if (cleanup.buffer_type is ContextBytesType || cleanup.buffer_shape == null || scoped_type (cleanup.buffer_type.element_type)) {
			unsupported_node ("SSA context buffer needs its complete backing obligation graph");
		}
	}

	private void conditional_state(RuntimeLifetimeState refused) throws RuntimeLifetimeError {
		foreach (int key in refused.bindings.get_keys ()) {
			if (!state.bindings.contains (key)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("conditional construction lost an owner binding");
			}
			int prior = refused.bindings.lookup (key), admitted = state.bindings.lookup (key);
			if (prior != admitted) {
				int joined = graph.join ();
				graph.alternative (joined, prior);
				graph.alternative (joined, admitted);
				state.bindings.insert (key, joined);
			}
		}
	}

	private void instruction(SsaInstruction source) throws RuntimeLifetimeError, SsaError {
		current_instruction = source;
		if (source is SsaTaskCreate) {
			var call = (SsaTaskCreate) source;
			int task = task_create (call);
			publish (call.result, task);
			state.bindings.insert (pending.lookup (call.result), task);
			foreach (var argument in call.arguments) {
				consume (argument);
			}
		} else if (source is SsaFrameBufferRestore) {
			frame_buffer_restore ((SsaFrameBufferRestore) source);
		} else if (source is SsaFrameInputRestore) {
			var restored = (SsaFrameInputRestore) source;
			if (!frame_inputs.contains (restored) || restored.creation == null || !restored.creation.input_restores.find (restored)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA frame restoration lost its original capture/admission channel");
			}
			publish (restored.result, frame_inputs.lookup (restored));
		} else if (source is SsaTaskAcquire) {
			var acquired = (SsaTaskAcquire) source;
			if (!tasks.contains (acquired.owner_ordinal)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task acquisition lacks its actual owner slot");
			}
			write (new SsaRuntimeStorage (tasks.lookup (acquired.owner_ordinal), acquired.owner_ordinal), value (acquired.source), false);
			consume (acquired.source);
		} else if (source is SsaTaskMove) {
			var moved = (SsaTaskMove) source;
			int incoming = state.bindings.lookup (tasks.lookup (moved.owner_ordinal));
			publish (moved.result, incoming);
			state.bindings.insert (pending.lookup (moved.result), incoming);
			state.bindings.insert (tasks.lookup (moved.owner_ordinal), graph.absent ());
		} else if (source is SsaTaskBorrow) {
			var borrowed = (SsaTaskBorrow) source;
			publish (borrowed.result, state.bindings.lookup (tasks.lookup (borrowed.owner_ordinal)));
		} else if (source is SsaTaskEnd) {
			state.bindings.insert (tasks.lookup (((SsaTaskEnd) source).owner_ordinal), graph.absent ());
		} else if (source is SsaExecutorEnd || source is SsaTaskStarted) {
		} else if (source is SsaAsyncDelay) {
			value (((SsaAsyncDelay) source).ticks);
			task_error (source.result, graph.absent ());
		} else if (source is SsaTaskWait) {
			var wait = (SsaTaskWait) source;
			value (wait.bridge_executor);
			task_error (wait.result, wait.discard ? graph.absent () : graph.project (value (wait.child), "f1"));
			consume (wait.child);
		} else if (source is SsaTaskSuccess) {
			var success = (SsaTaskSuccess) source;
			if (success.operation.success != success || success.operation.discard) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task result lost its exact successful observation");
			}
			if (success.result != null) {
				int incoming = graph.project (value (success.operation.child), "f0");
				publish (success.result, incoming);
				if (pending.contains (success.result)) {
					state.bindings.insert (pending.lookup (success.result), incoming);
				}
			} else if (success.struct_result != null) {
				if (task_records.lookup (success.struct_result) != success) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task record lost its original result correspondence");
				}
				int incoming = graph.project (value (success.operation.child), "f0");
				for (int i = 0; i < success.struct_result.leaves.length; i++) {
					var leaf = success.struct_result.leaves[i];
					int result = record_component (incoming, success.struct_result.shape.leaves[i]);
					publish (leaf, result);
					if (pending.contains (leaf)) {
						state.bindings.insert (pending.lookup (leaf), result);
					}
				}
			} else {
				unsupported_node ("SSA task grouped result needs its exact publication correspondence");
			}
		} else if (source is SsaAsyncOperation) {
			var operation = (SsaAsyncOperation) source;
			value (operation.executor);
			value (operation.argument);
			int task = value (operation.task);
			publish (operation.result, graph.absent ());
			if (operation.exception != null) {
				task_error (operation.exception, operation.contract.kind == AsyncOperationKind.RUN ? graph.project (task, "f1") : graph.absent ());
			}
			if (operation.contract.kind == AsyncOperationKind.RUN) {
				consume (operation.task);
			}
		} else if (source is SsaAsyncRunStatus) {
			empty_enum (((SsaAsyncRunStatus) source).destination);
		} else if (source is SsaEnumCopy) {
			empty_enum (((SsaEnumCopy) source).source);
			empty_enum (((SsaEnumCopy) source).destination);
		} else if (source is SsaEnumDrop) {
			empty_enum (((SsaEnumDrop) source).source);
		} else if (source is SsaEnumEndInspection) {
			empty_enum (((SsaEnumEndInspection) source).source);
		} else if (source is SsaEnumFinishArm) {
			empty_enum (((SsaEnumFinishArm) source).source);
		} else if (source is SsaStructBoundary) {
			var boundary = (SsaStructBoundary) source;
			record_boundary (boundary);
			var acquired = source as SsaStructBoundaryAcquire;
			if (acquired != null) {
				record_acquisition (acquired);
			}
		} else if (source is SsaGroupCallSuccess) {
			var success = (SsaGroupCallSuccess) source;
			var call = success.call;
			if (call == null || call.struct_result == null) {
				unsupported_node ("SSA grouped success requires its exact record result correspondence");
			} else {
				if (record_successes.lookup (call) != success || record_success_blocks.lookup (call) != current_block || !record_pending.contains (call)) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked record changed its original success publication");
				}
				for (int i = 0; i < call.struct_result.leaves.length; i++) {
					var leaf = call.struct_result.leaves[i];
					int incoming = record_component (record_pending.lookup (call), call.struct_result.shape.leaves[i]);
					publish (leaf, incoming);
					if (pending.contains (leaf)) {
						state.bindings.insert (pending.lookup (leaf), incoming);
					}
				}
			}
		} else if (source is SsaFrameRecordRestore) {
			frame_record_restore ((SsaFrameRecordRestore) source);
		} else if (source is SsaFallibleRecordRestore) {
			record_restore ((SsaFallibleRecordRestore) source);
		} else if (source is SsaStructResultConsume) {
			record_consumption ((SsaStructResultConsume) source);
		} else if (source is SsaStructParameterBorrow) {
			if (!function.struct_parameters.find (((SsaStructParameterBorrow) source).parameter)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record borrow lost its declared parameter group");
			}
		} else if (source is SsaRecordAcquire) {
			record_acquire ((SsaRecordAcquire) source);
		} else if (source is SsaRecordMove) {
			record_move ((SsaRecordMove) source);
		} else if (source is SsaRecordFieldCommit) {
			var committed = (SsaRecordFieldCommit) source;
			if (committed.destination.semantic_type != committed.shape.semantic_type || committed.shape.mode != StructValueMode.MOVE_VALUE) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record field commit lost its exact owning type");
			}
			write (place (committed.destination), record_value (committed.shape, committed.leaves));
			foreach (var leaf in committed.leaves) {
				consume (leaf);
			}
		} else if (source is SsaRecordFieldDrop) {
			var dropped = (SsaRecordFieldDrop) source;
			record_shape (dropped.shape);
			if (dropped.source.semantic_type != dropped.shape.semantic_type || dropped.shape.mode != StructValueMode.MOVE_VALUE) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record field retirement lost its exact owning type");
			}
			write (place (dropped.source), graph.absent (), false);
		} else if (source is SsaStorageReceiverInstruction) {
			var selection = (SsaStorageReceiverInstruction) source;
			var policy = selection.storage.object_class.allocation_policy;
			if (selection.storage.text_extent == null) {
				unsupported_node ("SSA allocation lacks its actual ObjectStorage cleanup extent");
			}
			var handle = selection.allocation_context == null ? null : selection.allocation_context.semantic_type as HandleType;
			if (policy != null && policy.kind == AllocationKind.CONTEXT ? !policy.valid () || handle == null || handle.context_mode != policy.context_mode : selection.allocation_context != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA allocation lost exact selected context mode");
			}
			int root = product (selection.storage.semantic_type, context_origin (selection.allocation_context, selection.context_owner));
			write (object_storage (selection.storage), root);
			publish (source.result, root);
		} else if (source is SsaLifecycleCallInstruction && ((SsaLifecycleCallInstruction) source).constructs) {
			var call = (SsaLifecycleCallInstruction) source;
			var storage = object_storage (call.storage);
			RuntimeLifetimeState? refused = call.storage.fallible ? state.snapshot () : null;
			buffer_arguments (call);
			write (storage, invoke (call.target, call.arguments, call.receiver, call.owned_arguments, read (storage), call.exception_result));
			if (refused != null) {
				conditional_state (refused);
			}
			foreach (var argument in call.arguments) {
				consume (argument);
			}
		} else if (source is SsaFallibleBufferRestore) {
			buffer_restore ((SsaFallibleBufferRestore) source);
		} else if (source is SsaFallibleInputRestore) {
			var restored = (SsaFallibleInputRestore) source;
			var call = restored.call;
			if (call == null || !call.constructs || !call.storage.fallible || !call.input_restores.find (restored) || !call.owned_arguments.find (restored.argument) || restored.owner.source_ordinal != restored.argument.source_ordinal || !pending.contains (restored.argument.value)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA fallible input lost its exact captured owner/constructor channel");
			}
			publish (restored.result, state.bindings.lookup (pending.lookup (restored.argument.value)));
		} else if (source is SsaCallInstruction) {
			var call = (SsaCallInstruction) source;
			if (call.target != null) {
				buffer_arguments (call);
			}
			int result = invoke (call.target, call.arguments, call.receiver, call.owned_arguments, -1, call.exception_result);
			publish (call.result, result);
			if (call.buffer_result != null) {
				ordinary_buffer (call.target.owned_cleanup);
				publish_buffer (call.buffer_result, result);
			}
			if (call.struct_result != null) {
				if (record_pending.contains (call)) {
					graph.alternative (record_pending.lookup (call), result);
				} else {
					for (int i = 0; i < call.struct_result.leaves.length; i++) {
						var leaf = call.struct_result.leaves[i];
						int incoming = record_component (result, call.struct_result.shape.leaves[i]);
						publish (leaf, incoming);
						if (pending.contains (leaf)) {
							state.bindings.insert (pending.lookup (leaf), incoming);
						}
					}
				}
			}
			foreach (var argument in call.arguments) {
				consume (argument);
			}
			if (call is SsaLifecycleCallInstruction) {
				write (object_storage (((SsaLifecycleCallInstruction) call).storage), graph.absent (), false);
			}
		} else if (source is SsaExceptionTransfer) {
			var transfer = (SsaExceptionTransfer) source;
			var storage = reference (transfer.source);
			publish (transfer.result, storage == null ? value (transfer.source) : read (storage));
		} else if (source is SsaExceptionStamp) {
			private_use (((SsaExceptionStamp) source).exception, source);
			value (((SsaExceptionStamp) source).exception);
		} else if (source is SsaExceptionMatch) {
			private_use (((SsaExceptionMatch) source).exception, source);
			value (((SsaExceptionMatch) source).exception);
			publish (source.result, graph.absent ());
		}
		// The frame catch event mirrors the existing private exception owner.
		// It retains that exact channel across suspension; it creates no new
		// source-level owner or lifetime origin.
		else if (source is SsaFrameCatchEvent) {
			var event = (SsaFrameCatchEvent) source;
			if (!function.frame_catch_owners.find (event.owner) || !event.owner.matches_event (event) || event.source.semantic_type != event.owner.semantic_type || !(event.source is SsaNullPointerConstant) && !private_errors.contains (event.source)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA suspended catch event lost its exact private exception owner");
			}
			try {
				event.owner.verify_events (function);
			} catch (SsaError failure) {
				throw new RuntimeLifetimeError.INVALID_GRAPH (failure.message);
			}
			private_use (event.source, event);
			value (event.source);
		} else if (source is SsaCatchBorrow) {
			var caught = (SsaCatchBorrow) source;
			bool registered = false;
			foreach (var handler in function.handlers) {
				if (handler.borrow == caught && handler.selection.exception == caught.exception && handler.selection.match_type == caught.result.semantic_type) {
					registered = true;
				}
			}
			if (!registered) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA catch borrow lost its actual protected exception channel");
			}
			var storage = reference (caught.exception);
			if (storage == null || !storage.private_exception) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA catch borrow lost its private owner binding");
			}
			publish (source.result, read (storage));
		} else if (source is SsaCallSuccess) {
			var success = (SsaCallSuccess) source;
			if (success.call.exception_result == null || success.call.target.throws_type == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA success result lost its actual throwing call");
			}
			publish (source.result, value (success.call.result));
		} else if (source is SsaTextSnapshotDestroy) {
			write (place (((SsaTextSnapshotDestroy) source).field), graph.absent (), false);
		} else if (source is SsaConstructorAbort) {
			var abort = (SsaConstructorAbort) source;
			if (abort.lazy_properties.length != 0) {
				unsupported_node ("SSA lazy constructor unwind needs exact cache effects");
			}
			int receiver = state.bindings.lookup (-1);
			foreach (var field in abort.fields) {
				receiver = graph.replace (receiver, "f%d".printf (field.field.ordinal), graph.absent ());
			}
			state.bindings.insert (-1, receiver);
		} else if (source is SsaOwnedArgumentReservation) {
			var reservation = (SsaOwnedArgumentReservation) source;
			if (reservation.value == null || reservation.pair != null) {
				unsupported_node ("SSA aggregate reservation needs exact owner groups");
			} else {
				value (reservation.value);
			}
		} else if (source is SsaOwnedArgumentAbort) {
			var reservation = ((SsaOwnedArgumentAbort) source).reservation;
			var call = reservation.consumer as SsaCallInstruction;
			if (call == null || !call.reservations.find (reservation) || reservation.value == null || reservation.pair != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA abort lost its exact pending owner/call reservation");
			}
			value (reservation.value);
		} else if (source is SsaHeapOwnerEvent) {
			var event = (SsaHeapOwnerEvent) source;
			if (event.owner == null) {
				if (!(event.action == SsaHeapOwnerAction.END && event.effect is SsaCleanupInstruction) && event.action != SsaHeapOwnerAction.RETURN) {
					unsupported_node ("SSA detached owner event needs exact storage");
				}
				return;
			}
			if (event.owner.record_type != null && (event.action == SsaHeapOwnerAction.ACQUIRE || event.action == SsaHeapOwnerAction.MOVE) && !record_events.contains (event)) {
				unsupported_node ("SSA record owner event lacks its actual field acquisition or boundary");
			}
			int binding = event.owner.ordinal;
			if (event.action == SsaHeapOwnerAction.ACQUIRE) {
				int incoming = recent_moves.contains (event.value) ? state.bindings.lookup (recent_moves.lookup (event.value)) : value (event.value);
				var producer = definition (event.value);
				if (producer is SsaObjectReferenceInstruction && !recent_moves.contains (event.value)) {
					incoming = read (object_storage (((SsaObjectReferenceInstruction) producer).storage));
					if (objects.lookup (((SsaObjectReferenceInstruction) producer).storage) != binding) {
						state.bindings.insert (objects.lookup (((SsaObjectReferenceInstruction) producer).storage), graph.absent ());
					}
				}
				write (new SsaRuntimeStorage (binding, event.owner.source_ordinal), incoming, false);
				consume (event.value);
			} else if (event.action == SsaHeapOwnerAction.MOVE || event.action == SsaHeapOwnerAction.RETURN) {
				int incoming = state.bindings.lookup (binding);
				if (pending.contains (event.value)) {
					state.bindings.insert (pending.lookup (event.value), incoming);
					recent_moves.insert (event.value, pending.lookup (event.value));
				} else {
					unsupported_node ("SSA moved value lacks its pending obligation");
				} state.bindings.insert (binding, graph.absent ());
			} else if (event.action == SsaHeapOwnerAction.END || event.action == SsaHeapOwnerAction.RELEASE) {
				if (contexts.contains (event.owner)) {
					context_ends.add (new SsaRuntimeContextEnd (event.owner.source_ordinal, binding, state));
				}
				state.bindings.insert (binding, graph.absent ());
			}
		} else if (source is SsaCleanupInstruction) {
			var cleanup = (SsaCleanupInstruction) source;
			var storage = reference (cleanup.value);
			if (!(cleanup.value is SsaNullPointerConstant) && cleanup.cleanup.is_object && cleanup.cleanup.destructor != null) {
				invoke (cleanup.cleanup.destructor, new GenericArray<SsaValue> (), null, null, storage == null ? value (cleanup.value) : read (storage));
			}
			if (storage != null && !cleanup.value.semantic_type.is_scoped_allocator ()) {
				write (storage, graph.absent (), false);
			}
			consume (cleanup.value);
		} else if (source is SsaObjectReferenceInstruction) {
			publish (source.result, read (object_storage (((SsaObjectReferenceInstruction) source).storage)));
		} else if (source is SsaObjectValidateInstruction) {
			var guarded = (SsaObjectValidateInstruction) source;
			var storage = reference (guarded.reference);
			publish (source.result, storage == null ? value (guarded.reference) : read (storage));
		} else if (source is SsaClassUpcast) {
			publish (source.result, value (((SsaClassUpcast) source).reference));
		} else if (source is SsaLoadInstruction) {
			var loaded = (SsaLoadInstruction) source;
			publish (source.result, graph_input (loaded.source.semantic_type) ? read (place (loaded.source)) : graph.absent ());
		} else if (source is SsaInitializeInstruction) {
			var initialized = (SsaInitializeInstruction) source;
			if (graph_input (initialized.target.semantic_type)) {
				write (place (initialized.target), recent_moves.contains (initialized.value) ? state.bindings.lookup (recent_moves.lookup (initialized.value)) : value (initialized.value));
				consume (initialized.value);
			}
		} else if (source is SsaStoreInstruction) {
			var stored = (SsaStoreInstruction) source;
			if (graph_input (stored.target.semantic_type)) {
				write (place (stored.target), recent_moves.contains (stored.value) ? state.bindings.lookup (recent_moves.lookup (stored.value)) : value (stored.value));
				consume (stored.value);
			}
		} else if (source is SsaScopedAllocator) {
			publish (source.result, graph.absent ());
		} else if (source is SsaSliceLengthInstruction) {
			value (((SsaSliceLengthInstruction) source).slice);
			publish (source.result, graph.absent ());
		} else if (source is SsaBufferAllocateInstruction) {
			var allocation = (SsaBufferAllocateInstruction) source;
			ordinary_buffer (allocation.cleanup);
			if (allocation.allocation_context != null || allocation.failure != null) {
				unsupported_node ("SSA buffer needs selected-context and exceptional effects");
			}
			publish_buffer (allocation.pair, graph.absent ());
		} else if (source is SsaBufferReadInstruction) {
			var loaded = (SsaBufferReadInstruction) source;
			ordinary_buffer (loaded.place.cleanup);
			var storage = buffer_place (loaded.place);
			if (storage != null) {
				buffer_versions.insert (loaded.pair, state.bindings.lookup (storage.binding));
			}
			publish_buffer (loaded.pair, read (storage));
		} else if (source is SsaBufferWriteInstruction) {
			var stored = (SsaBufferWriteInstruction) source;
			ordinary_buffer (stored.place.cleanup);
			consume_buffer (stored.pair, stored.place.cleanup, stored);
			write (buffer_place (stored.place), buffer_value (stored.pair));
		} else if (source is SsaBufferDeallocateInstruction) {
			var retired = (SsaBufferDeallocateInstruction) source;
			ordinary_buffer (retired.cleanup);
			consume_buffer (retired.pair, retired.cleanup, retired);
			if (buffer_reads.contains (retired.pair)) {
				var storage = buffer_place (buffer_reads.lookup (retired.pair));
				if (storage != null && buffer_versions.contains (retired.pair) && state.bindings.lookup (storage.binding) == buffer_versions.lookup (retired.pair)) {
					write (storage, graph.absent (), false);
				}
			}
		} else if (source is SsaBufferBorrowInstruction) {
			if (((SsaBufferBorrowInstruction) source).pair.shape.slice_type is ContextBytesType) {
				unsupported_node ("SSA context buffer view needs an exact owner loan");
			}
			publish (source.result, buffer_value (((SsaBufferBorrowInstruction) source).pair));
		} else if (source is SsaCCallInstruction) {
			var call = (SsaCCallInstruction) source;
			var target = call.target;
			bool admitted = target != null && call.arguments.length == target.parameters.length && RuntimeForeignLifetimes.result (target.return_type, target.owned_cleanup == null ? null : target.owned_cleanup.external_symbol);
			if (target != null) {
				foreach (var parameter in target.parameters) {
					admitted = admitted && RuntimeForeignLifetimes.input (parameter.semantic_type, parameter.pointer_contract, target.owned_cleanup != null);
				}
			}
			if (!admitted) {
				unsupported_node ("SSA foreign call requires an exact owner/pointer/callback lifetime effect");
			}
			foreach (var argument in call.arguments) {
				value (argument);
				context_origin (argument);
				consume (argument);
			}
			publish (source.result, graph.absent ());
		} else if (source is SsaBinaryInstruction || source is SsaPrefixInstruction || source is SsaNonNullUse || source is SsaValidatePlaceInstruction) {
			publish (source.result, graph.absent ());
		} else {
			unsupported_node ("SSA instruction requires its exact lifetime operation: " + source.get_type ().name ());
			publish (source.result, graph.absent ());
		}
	}

	private GenericArray<SsaEdge> edges(SsaTerminator source) {
		var result = new GenericArray<SsaEdge> ();
		if (source is SsaBranch) {
			result.add (((SsaBranch) source).edge);
		} else if (source is SsaConditionalBranch) {
			result.add (((SsaConditionalBranch) source).true_edge);
			result.add (((SsaConditionalBranch) source).false_edge);
		} else if (source is SsaBufferAllocationBranch) {
			result.add (((SsaBufferAllocationBranch) source).success_edge);
			result.add (((SsaBufferAllocationBranch) source).failure_edge);
		} else if (source is SsaEnumDispatch) {
			var dispatch = (SsaEnumDispatch) source;
			foreach (var branch in dispatch.cases) {
				result.add (branch.edge);
			}
			result.add (dispatch.invalid_edge);
		}
		return result;
	}

	private GenericArray<SsaBlock> blocks() {
		var result = new GenericArray<SsaBlock> ();
		result.add (function.entry);
		for (int i = 0; i < result.length; i++) {
			foreach (var next in result[i].terminator.successors ()) {
				if (!result.find (next)) {
					result.add (next);
				}
			}
		}
		return result;
	}

	private void inventory(GenericArray<SsaBlock> reachable) throws RuntimeLifetimeError {
		foreach (var owner in function.heap_owners) {
			if (slot () != owner.ordinal) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA owner ordinals lost their actual inventory");
			}
			owner_extent (owner.source_ordinal, owner.text_extent);
		}
		foreach (var owner in function.task_owners) {
			if (tasks.contains (owner.source_ordinal)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA task owner has competing lifetime slots");
			}
			tasks.insert (owner.source_ordinal, slot ());
			owner_extent (owner.source_ordinal, owner.text_extent);
		}
		foreach (var storage in function.object_storage) {
			objects.insert (storage, slot ());
			if (storage.text_extent != null) {
				if (storage.region_ordinal != storage.text_extent.ordinal) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA ObjectStorage region differs from its actual cleanup extent");
				}
				owner_extent (storage.cleanup_rank, storage.text_extent);
			}
		}
		foreach (var storage in function.storage) {
			memory.insert (storage, slot ());
		}
		foreach (var storage in function.buffer_storage) {
			buffers.insert (storage, slot ());
			owner_extent (storage.owner_ordinal, storage.text_extent);
		}
		foreach (var block in reachable) {
			foreach (var parameter in block.parameters) {
				values.insert (parameter, graph.join ());
			}
			foreach (var source in block.instructions) {
				if (source.result != null) {
					values.insert (source.result, graph.join ());
					definitions.insert (source.result, source);
				}
				var call = source as SsaCallInstruction;
				if (call != null) {
					record_call (call, block);
					if (call.buffer_result != null) {
						if (call.target == null || call.target.owned_cleanup == null || !call.target.owned_cleanup.is_buffer || call.buffer_result.shape != call.target.owned_cleanup.buffer_shape) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer result lost its exact declared owned pair shape");
						}
						if (call.target.throws_type != null) {
							unsupported_node ("SSA checked buffer result needs its exact success publication");
						}
						buffer_pair (call.buffer_result, call);
					}
				}
				if (call != null && call.exception_result != null) {
					values.insert (call.exception_result, graph.join ());
					definitions.insert (call.exception_result, call);
					private_errors.insert (call.exception_result, slot ());
				}
				var boundary = source as SsaStructBoundary;
				if (boundary != null) {
					record_pairs (boundary.shape, boundary.leaves, boundary.buffer_pairs);
				}
				var restored_group = source as SsaRecordAdmissionRestore;
				if (restored_group != null) {
					record_pairs (restored_group.results.shape, restored_group.results.leaves, restored_group.results.buffers);
				}
				var borrowed_group = source as SsaStructParameterBorrow;
				if (borrowed_group != null) {
					record_pairs (borrowed_group.parameter.shape, borrowed_group.leaves, borrowed_group.buffers);
				}
				if (call != null && call.struct_result != null) {
					record_pairs (call.struct_result.shape, call.struct_result.leaves, call.struct_result.buffers);
				}
				var task_group = source as SsaTaskSuccess;
				if (task_group != null && task_group.struct_result != null) {
					record_pairs (task_group.struct_result.shape, task_group.struct_result.leaves, task_group.struct_result.buffers);
				}
				if (source is SsaTaskSuccess && ((SsaTaskSuccess) source).struct_result != null) {
					task_record ((SsaTaskSuccess) source, block);
				}
				if (source is SsaRecordAdmissionRestore) {
					var restored = (SsaRecordAdmissionRestore) source;
					if (record_restores.contains (restored.results)) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration repeats one physical result group");
					}
					record_restores.insert (restored.results, restored);
					foreach (var leaf in restored.results.leaves) {
						if (values.contains (leaf)) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record restoration duplicates a physical leaf definition");
						}
						values.insert (leaf, graph.join ());
						definitions.insert (leaf, restored);
					}
				}
				if (source is SsaTaskCreate || source is SsaTaskMove || source is SsaTaskSuccess && source.result != null && graph_input (source.result.semantic_type)) {
					if (!pending.contains (source.result)) {
						pending.insert (source.result, slot ());
					}
				}
				SsaValue? task_exception = null;
				if (source is SsaTaskWait || source is SsaAsyncDelay) {
					task_exception = source.result;
				} else if (source is SsaAsyncOperation) {
					task_exception = ((SsaAsyncOperation) source).exception;
				}
				if (task_exception != null) {
					if (!values.contains (task_exception)) {
						values.insert (task_exception, graph.join ());
						definitions.insert (task_exception, source);
					}
					private_errors.insert (task_exception, slot ());
				}
				if (source is SsaBufferReadInstruction) {
					var read = (SsaBufferReadInstruction) source;
					buffer_pair (read.pair, source);
					buffer_reads.insert (read.pair, read.place);
				} else if (source is SsaFallibleBufferRestore) {
					buffer_pair (((SsaFallibleBufferRestore) source).pair, source);
				} else if (source is SsaFrameBufferRestore) {
					buffer_pair (((SsaFrameBufferRestore) source).pair, source);
				} else if (source is SsaBufferAllocateInstruction) {
					buffer_pair (((SsaBufferAllocateInstruction) source).pair, source);
				}
				var event = source as SsaHeapOwnerEvent;
				if (event != null && event.owner != null) {
					if (event.action == SsaHeapOwnerAction.ACQUIRE) {
						var owners = acquisitions.lookup (event.value);
						if (owners == null) {
							owners = new GenericArray<SsaHeapOwner> ();
							acquisitions.insert (event.value, owners);
						}
						if (!owners.find (event.owner)) {
							owners.add (event.owner);
						}
					} else if (event.action == SsaHeapOwnerAction.MOVE || event.action == SsaHeapOwnerAction.RETURN) {
						if (!pending.contains (event.value)) {
							pending.insert (event.value, slot ());
						}
						var transfer = event.effect as SsaExceptionTransfer;
						if (transfer != null) {
							if (event.action != SsaHeapOwnerAction.MOVE || transfer.source != event.value || transfer.owner_ordinal != event.owner.source_ordinal || !block.instructions.find (transfer)) {
								throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA exception transfer lost its exact owner event");
							}
							pending.insert (transfer.result, pending.lookup (event.value));
							private_errors.insert (transfer.result, pending.lookup (event.value));
						}
					}
				}
				var factory = source as SsaScopedAllocator;
				if (factory != null) {
					if (contexts.contains (factory.owner)) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA context acquired competing backing loans");
					}
					contexts.insert (factory.owner, factory);
					regions.context (factory.owner.source_ordinal, region_id (factory.owner.text_extent));
				}
				var selection = source as SsaStorageReceiverInstruction;
				if (selection != null && selection.storage.object_class.allocation_policy != null && selection.storage.object_class.allocation_policy.context_mode == "scoped-affine") {
					scoped_allocation = true;
				}
			}
		}
		foreach (var block in reachable) {
			foreach (var edge in edges (block.terminator)) {
				if (edge.target == null || !reachable.find (edge.target) || edge.arguments.length != edge.target.parameters.length) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA lifetime edge lost its exact block arguments");
				}
				for (int i = 0; i < edge.arguments.length; i++) {
					var parameter = edge.target.parameters[i];
					var incoming = incoming_edges.lookup (parameter);
					if (incoming == null) {
						incoming = new GenericArray<SsaValue> ();
						incoming_edges.insert (parameter, incoming);
					}
					incoming.add (edge.arguments[i]);
				}
			}
		}
		// Private channels can remain SSA values or cross physical block arguments.
		// Reconstruct their aliases here; no Source/CFG storage identity is used.
		bool changed = false;
		do {
			changed = false;
			foreach (var block in reachable) {
				foreach (var source in block.instructions) {
					SsaValue? input = null;
					if (source is SsaClassUpcast) {
						input = ((SsaClassUpcast) source).reference;
					} else if (source is SsaCatchBorrow) {
						input = ((SsaCatchBorrow) source).exception;
					}
					if (input != null && private_errors.contains (input) && !private_errors.contains (source.result)) {
						private_errors.insert (source.result, private_errors.lookup (input));
						changed = true;
					}
				}
				foreach (var parameter in block.parameters) {
					if (private_errors.contains (parameter)) {
						continue;
					}
					var incoming = incoming_edges.lookup (parameter);
					if (incoming == null) {
						continue;
					}
					foreach (var value in incoming) {
						if (private_errors.contains (value)) {
							private_errors.insert (parameter, slot ());
							changed = true;
							break;
						}
					}
				}
			}
		} while (changed);
		foreach (var parameter in incoming_edges.get_keys ()) {
			if (!private_errors.contains (parameter)) {
				continue;
			}
			foreach (var incoming in incoming_edges.lookup (parameter)) {
				if (!(incoming is SsaNullPointerConstant) && !private_errors.contains (incoming)) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA private exception edge gained an unrelated owner");
				}
			}
		}
	}

	private void private_use(SsaValue value, SsaNode? use) {
		if (use == null || !private_errors.contains (value)) {
			return;
		}
		int binding = private_errors.lookup (value);
		var uses = private_uses.lookup (binding);
		if (uses == null) {
			uses = new GenericArray<SsaNode> ();
			private_uses.insert (binding, uses);
		}
		if (!uses.find (use)) {
			uses.add (use);
		}
	}

	private bool invalidated_private_use(SsaBlock start, int after, int binding, SsaNode use) {
		var pending = new GenericArray<SsaBlock> ();
		var seen = new HashTable<SsaBlock, bool> (direct_hash, direct_equal);
		pending.add (start);
		for (int n = 0; n < pending.length; n++) {
			var block = pending[n];
			int first = n == 0 ? after : 0;
			if (n != 0) {
				if (seen.contains (block)) {
					continue;
				}
				seen.insert (block, true);
				bool fresh = false;
				foreach (var parameter in block.parameters) {
					if (private_errors.contains (parameter) && private_errors.lookup (parameter) == binding) {
						fresh = true;
					}
				}
				if (fresh) {
					continue;
				}
			}
			bool fresh = false;
			for (int i = first; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				if (instruction == use) {
					return true;
				}
				SsaValue? created = null;
				if (instruction is SsaExceptionTransfer) {
					created = instruction.result;
				} else if (instruction is SsaCallInstruction) {
					created = ((SsaCallInstruction) instruction).exception_result;
				}
				if (created != null && private_errors.contains (created) && private_errors.lookup (created) == binding) {
					fresh = true;
					break;
				}
			}
			if (fresh) {
				continue;
			}
			if (block.terminator == use) {
				return true;
			}
			foreach (var next in block.terminator.successors ()) {
				pending.add (next);
			}
		}
		return false;
	}

	private void verify_private_uses(GenericArray<SsaBlock> blocks) throws RuntimeLifetimeError {
		foreach (var block in blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				if (cleanup == null || !private_errors.contains (cleanup.value)) {
					continue;
				}
				int binding = private_errors.lookup (cleanup.value);
				var uses = private_uses.lookup (binding);
				if (uses == null) {
					continue;
				}
				foreach (var use in uses) {
					if (invalidated_private_use (block, i + 1, binding, use)) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA borrow outlives its exact private exception owner");
					}
				}
			}
		}
	}

	private RuntimeLifetimeState edge_state(SsaBlock block, SsaEdge edge) throws RuntimeLifetimeError {
		var result = outputs.lookup (block).snapshot ();
		var branch = block.terminator as SsaConditionalBranch;
		var binary = branch == null ? null : definition (branch.condition) as SsaBinaryInstruction;
		// Reconstruct the checked constructor rollback from SSA's own call,
		// receiver, physical exception result and final branch instruction.
		bool checked = false;
		foreach (var instruction in block.instructions) {
			var call = instruction as SsaLifecycleCallInstruction;
			if (call == null || !call.constructs || call.target.throws_type == null) {
				continue;
			}
			var policy = call.storage.object_class.allocation_policy;
			if (policy == null || !policy.checked_initialization ()) {
				continue;
			}
			if (checked) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked constructor rollback requires one exact invocation before its exception test");
			}
			checked = true;
			var receiver = definition (call.receiver) as SsaStorageReceiverInstruction;
			if (call.exception_result == null || branch == null || binary == null || binary.result != branch.condition || binary.operator_kind != BinaryOperator.EQUAL || binary.left != call.exception_result || !(binary.right is SsaNullPointerConstant) || branch.true_edge.target == branch.false_edge.target || block.instructions.length < 2 || block.instructions[block.instructions.length - 1] != binary || block.instructions[block.instructions.length - 2] != call || receiver == null || receiver.storage != call.storage || !function.object_storage.find (call.storage) || call.storage.object_class.constructor != call.target) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA checked constructor rollback requires its exact candidate and original success/error test");
			}
			if (edge == branch.false_edge) {
				result.bindings.insert (objects.lookup (call.storage), graph.absent ());
			}
		}
		if (binary != null && (binary.operator_kind == BinaryOperator.EQUAL || binary.operator_kind == BinaryOperator.NOT_EQUAL)) {
			SsaValue? tested = (binary.left is SsaNullPointerConstant) ? binary.right : (binary.right is SsaNullPointerConstant) ? binary.left : null;
			bool truth = edge == branch.true_edge;
			if (tested != null && private_errors.contains (tested) && truth == (binary.operator_kind == BinaryOperator.EQUAL)) {
				result.bindings.insert (private_errors.lookup (tested), graph.absent ());
			}
		}
		var incoming = new HashTable<int, int> (direct_hash, direct_equal);
		for (int i = 0; i < edge.arguments.length; i++) {
			var parameter = edge.target.parameters[i];
			if (!private_errors.contains (parameter)) {
				continue;
			}
			int target = private_errors.lookup (parameter);
			var value = edge.arguments[i];
			incoming.insert (target, (value is SsaNullPointerConstant) ? graph.absent () : result.bindings.lookup (private_errors.lookup (value)));
		}
		for (int i = 0; i < edge.arguments.length; i++) {
			if (private_errors.contains (edge.target.parameters[i]) && private_errors.contains (edge.arguments[i])) {
				result.bindings.insert (private_errors.lookup (edge.arguments[i]), graph.absent ());
			}
		}
		foreach (int key in incoming.get_keys ()) {
			result.bindings.insert (key, incoming.lookup (key));
		}
		return result;
	}

	private void exit() throws RuntimeLifetimeError {
		exit_count++;
		foreach (int binding in exits.get_keys ()) {
			graph.alternative (exits.lookup (binding), state.bindings.lookup (binding));
		}
	}

	internal RuntimeLifetimeSummary incomplete(string reason) {
		graph.seal ();
		return new RuntimeLifetimeSummary (graph, graph.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), reason);
	}

	internal RuntimeLifetimeSummary analyze() throws RuntimeLifetimeError, SsaError {
		record_parameters ();
		buffer_parameters ();
		function.verify_exception_dispositions ();
		var reachable = blocks ();
		inventory (reachable);
		returned = graph.join ();
		exceptional_result = graph.join ();
		graph.alternative (exceptional_result, graph.absent ());
		var initial = new RuntimeLifetimeState ();
		for (int s = 0; s < slots.length; s++) {
			int binding = slots[s];
			initial.bindings.insert (binding, graph.absent ());
		}
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			bool allocator = parameter.semantic_type.is_scoped_allocator ();
			bool owning = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || record_parameter_owned (p) || buffer_inputs.contains (p);
			if (allocator || owning || graph_input (parameter.semantic_type)) {
				regions.input (p, allocator);
			}
			int incoming = allocator || !owning && !graph_input (parameter.semantic_type) ? graph.absent () : graph.input (p);
			values.insert (parameter, incoming);
			int binding = parameter_binding (p);
			slots.add (binding);
			initial.bindings.insert (binding, owning ? graph.absent () : incoming);
			if (!owning && graph_input (parameter.semantic_type)) {
				initial_inputs.insert (binding, incoming);
				exits.insert (binding, graph.join ());
			}
		}
		if (function.implicit_receiver != null) {
			regions.input (-1);
			slots.add (-1);
			int incoming = graph.input (-1);
			values.insert (function.implicit_receiver, incoming);
			initial.bindings.insert (-1, incoming);
			initial_inputs.insert (-1, incoming);
			exits.insert (-1, graph.join ());
		}
		regions.seal ();
		if (function.heap_owners.length != 0) {
			lifetimes = SsaHeapOwnerFlow.verify (function, true);
		}
		if (contexts.size () != 0) {
			var buffer_lifetimes = SsaBufferMemoryFlow.verify (function);
			SsaScopedBackingFlow.verify (function, lifetimes, buffer_lifetimes);
		}
		if (function.struct_result != null) {
			record_shape (function.struct_result);
			if (function.struct_result.semantic_type != function.return_type) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result differs from its declared return type");
			}
		}
		foreach (var block in reachable) {
			var entry = new RuntimeLifetimeState ();
			for (int s = 0; s < slots.length; s++) {
				int binding = slots[s];
				entry.bindings.insert (binding, graph.join ());
			}
			entries.insert (block, entry);
		}
		var first = entries.lookup (function.entry);
		for (int s = 0; s < slots.length; s++) {
			int binding = slots[s];
			graph.alternative (first.bindings.lookup (binding), initial.bindings.lookup (binding));
		}
		foreach (var block in reachable) {
			current_block = block;
			state = entries.lookup (block).snapshot ();
			recent_moves = new HashTable<SsaValue, int> (direct_hash, direct_equal);
			foreach (var source in block.instructions) {
				instruction (source);
			}
			var result = block.terminator as SsaReturn;
			if (block.terminator is SsaExceptionReturn) {
				if (function.throws_type == null && function.async_body == null) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA exceptional result escapes a nonthrowing signature");
				}
				var failure = ((SsaExceptionReturn) block.terminator).value;
				private_use (failure, block.terminator);
				graph.alternative (exceptional_result, private_errors.contains (failure) ? state.bindings.lookup (private_errors.lookup (failure)) : value (failure));
				exit ();
			} else if (result is SsaBufferReturn) {
				var returned_buffer = (SsaBufferReturn) result;
				ordinary_buffer (returned_buffer.cleanup);
				if (function.owned_cleanup != returned_buffer.cleanup || function.return_type != returned_buffer.pair.shape.slice_type || returned_buffer.cleanup.buffer_shape != returned_buffer.pair.shape) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA buffer result lost its complete declared ownership publication");
				}
				consume_buffer (returned_buffer.pair, returned_buffer.cleanup, returned_buffer);
				normal_exits++;
				graph.alternative (returned, buffer_value (returned_buffer.pair));
				exit ();
			} else if (result is SsaStructReturn) {
				normal_exits++;
				graph.alternative (returned, record_result ((SsaStructReturn) result, block));
				exit ();
			} else if (result != null) {
				if (function.struct_result != null) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("SSA record result lost its complete return publication");
				}
				normal_exits++;
				int incoming = result.value != null && recent_moves.contains (result.value) ? state.bindings.lookup (recent_moves.lookup (result.value)) : value (result.value);
				graph.alternative (returned, graph_input (function.return_type) || function.owned_cleanup != null ? incoming : graph.absent ());
				exit ();
			} else if (block.terminator is SsaFunctionEnd) {
				normal_exits++;
				graph.alternative (returned, graph.absent ());
				exit ();
			} else if (block.terminator is SsaExceptionUnreachable) {
				value (((SsaExceptionUnreachable) block.terminator).exception);
			} else if (block.terminator is SsaEnumDispatch) {
				empty_enum (((SsaEnumDispatch) block.terminator).source);
			} else if (!(block.terminator is SsaBranch) && !(block.terminator is SsaConditionalBranch) && !(block.terminator is SsaEnumInvalidTag)) {
				unsupported_node ("SSA terminator requires exact lifetime effects");
			}
			outputs.insert (block, state);
		}
		foreach (var block in reachable) {
			foreach (var edge in edges (block.terminator)) {
				var target = entries.lookup (edge.target);
				var source = edge_state (block, edge);
				for (int s = 0; s < slots.length; s++) {
					int binding = slots[s];
					graph.alternative (target.bindings.lookup (binding), source.bindings.lookup (binding));
				}
				for (int i = 0; i < edge.arguments.length; i++) {
					graph.alternative (values.lookup (edge.target.parameters[i]), value (edge.arguments[i]));
				}
			}
		}
		verify_private_uses (reachable);
		if (normal_exits == 0) {
			graph.alternative (returned, graph.absent ());
		}
		if (exit_count == 0) {
			foreach (int binding in exits.get_keys ()) {
				graph.alternative (exits.lookup (binding), initial_inputs.lookup (binding));
			}
		}
		int factory_result = -1;
		if (function.async_body != null) {
			var captures = new HashTable<string, int> (str_hash, str_equal);
			for (int p = 0; p < function.parameters.length; p++) {
				var parameter = function.parameters[p];
				bool owning = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || record_parameter_owned (p) || buffer_inputs.contains (p);
				captures.insert ("f%d".printf (p), graph_input (parameter.semantic_type) || owning ? graph.input (p) : graph.absent ());
			}
			var fields = new HashTable<string, int> (str_hash, str_equal);
			fields.insert ("f0", returned);
			fields.insert ("f1", exceptional_result);
			fields.insert ("f2", graph.product (new GenericArray<RuntimeScopeOrigin> (), captures));
			factory_result = graph.product (new GenericArray<RuntimeScopeOrigin> (), fields);
		}
		graph.seal ();
		if (unsupported != "") {
			return new RuntimeLifetimeSummary (graph, returned, new HashTable<int, int> (direct_hash, direct_equal), stores, unsupported);
		}
		foreach (var bound in bounds) {
			regions.validate (graph, bound.value, bound.destination);
		}
		foreach (var origin in graph.requirements (returned)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("SSA result retains a scoped local allocation");
			}
		}
		foreach (var origin in graph.requirements (exceptional_result)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("SSA exception retains a scoped local allocation");
			}
		}
		foreach (var ended in context_ends) {
			for (int v = 0; v < ended.values.length; v++) {
				foreach (var origin in graph.requirements (ended.values[v])) {
					if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT && origin.ordinal == ended.context) {
						throw new RuntimeLifetimeError.LOCAL_ESCAPE ("SSA context retires before a derived owner or pending handoff in %s binding #%d".printf (function.name, ended.bindings[v]));
					}
				}
			}
		}
		var updates = new HashTable<int, int> (direct_hash, direct_equal);
		int borrowed = 0;
		foreach (int binding in exits.get_keys ()) {
			borrowed++;
			var original = graph.requirements (initial_inputs.lookup (binding));
			int updated = exits.lookup (binding);
			var output = graph.requirements (updated);
			bool changed = original.length != output.length;
			if (!changed) {
				for (int i = 0; i < original.length; i++) {
					if (original[i].identity () != output[i].identity ()) {
						changed = true;
					}
				}
			}
			if (changed || stores.length != 0) {
				updates.insert (binding == -1 ? -1 : -binding - 2, updated);
			}
			foreach (var origin in output) {
				if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
					throw new RuntimeLifetimeError.LOCAL_ESCAPE ("SSA input storage retains a scoped local allocation");
				}
			}
		}
		if (borrowed > 1 && stores.length != 0) {
			unsupported_node ("SSA mutable borrowed aliases require exact effects");
		}
		if (function.async_body != null) {
			if (updates.size () != 0 || stores.length != 0) {
				unsupported_node ("SSA async factory needs deferred borrowed-storage effects");
			}
			return new RuntimeLifetimeSummary (graph, factory_result, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), unsupported);
		}
		return new RuntimeLifetimeSummary (graph, returned, updates, stores, unsupported, function.throws_type == null ? -1 : exceptional_result);
	}

}
}
