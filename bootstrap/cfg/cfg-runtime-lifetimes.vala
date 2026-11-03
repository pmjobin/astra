// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Text;

namespace Astra.Cfg {
private class CfgRuntimeStorage : Object {
	internal int binding;
	internal int destination;
	internal string path;
	internal CfgRuntimeStorage (int binding, int destination, string path = "") {
		this.binding = binding;
		this.destination = destination;
		this.path = path;
	}

}
private class CfgRuntimeBound : Object {
	internal int value;
	internal int destination;
	internal CfgRuntimeBound (int value, int destination) {
		this.value = value;
		this.destination = destination;
	}

}
private class CfgRuntimeContextUse : Object {
	internal CfgInstruction instruction;
	internal CfgLocalPlace context;
	internal CfgRuntimeContextUse (CfgInstruction instruction, CfgLocalPlace context) {
		this.instruction = instruction;
		this.context = context;
	}

}
private class CfgRuntimeContextEnd : Object {
	internal int context;
	internal GenericArray<int> values = new GenericArray<int> ();
	internal GenericArray<int> bindings = new GenericArray<int> ();
	internal CfgRuntimeContextEnd (int context, RuntimeLifetimeState state) {
		this.context = context;
		foreach (int binding in state.bindings.get_keys ()) {
			if (binding != context) {
				bindings.add (binding);
				values.add (state.bindings.lookup (binding));
			}
		}
	}

}
private class CfgRuntimeCatchAlias : Object {
	internal int owner;
	internal CfgInstruction initialized;
	internal CfgValue captured;
	internal GenericArray<Object> uses = new GenericArray<Object> ();
	internal CfgRuntimeCatchAlias (int owner, CfgInstruction initialized, CfgValue captured) {
		this.owner = owner;
		this.initialized = initialized;
		this.captured = captured;
	}

}
public class CfgRuntimeLifetimes : Object {
	private CfgProgram program;
	private HashTable<CfgFunction, RuntimeLifetimeSummary> summaries = new HashTable<CfgFunction, RuntimeLifetimeSummary> (direct_hash, direct_equal);
	private HashTable<CfgFunction, bool> visiting = new HashTable<CfgFunction, bool> (direct_hash, direct_equal);
	public static HashTable<CfgFunction, RuntimeLifetimeSummary> analyze(CfgProgram program) throws CfgError {
		var analysis = new CfgRuntimeLifetimes ();
		analysis.program = program;
		foreach (var function in program.functions) {
			analysis.summary (function);
		}
		return analysis.summaries;
	}

	public static void verify(CfgProgram program, GenericArray<CfgFunction>? required = null) throws CfgError {
		var summaries = analyze (program);
		if (required != null) {
			foreach (var function in required) {
				var result = summaries.lookup (function);
				if (result == null || !result.complete) {
					throw new CfgError.INVALID_CFG ("CFG scoped construction requires its complete actual function lifetime proof");
				}
			}
		}
	}

	internal static RuntimeLifetimeSummary import_summary(CfgFunction function, RuntimeLifetimeSummary archived) throws RuntimeLifetimeError {
		if (!archived.logical_coordinates) {
			return archived;
		}
		var positions = new GenericArray<int> ();
		var ordinals = new GenericArray<int> ();
		var layout = NativeLifetimeLayout.build ((int) function.parameters.length, function.struct_parameters, positions, ordinals);
		bool[] owners = new bool[function.parameters.length];
		bool[] contexts = new bool[function.parameters.length];
		bool[] mutable_owners = new bool[function.parameters.length];
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
			contexts[p] = type.is_scoped_allocator ();
			owners[p] = owns || graph;
			mutable_owners[p] = !owns && graph && !contexts[p];
		}
		return layout.to_physical (archived, function.implicit_receiver != null, owners, contexts, mutable_owners);
	}

	internal RuntimeLifetimeSummary? summary(CfgFunction? function) throws CfgError {
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
				throw new CfgError.INVALID_CFG ("CFG native lifetime contract: %s", failure.message);
			}
		}
		visiting.insert (function, true);
		var body = new CfgRuntimeLifetimeBody (this, program, function);
		RuntimeLifetimeSummary result;
		try {
			result = body.analyze ();
		} catch (RuntimeLifetimeError failure) {
			if (failure is RuntimeLifetimeError.LOCAL_ESCAPE) {
				throw new CfgError.INVALID_CFG ("CFG runtime lifetime: %s", failure.message);
			}
			result = body.incomplete (failure.message);
		}
		if (body.requires_scope && !result.complete) {
			throw new CfgError.INVALID_CFG ("CFG scoped lifetime proof is incomplete: %s", result.limitation);
		}
		visiting.remove (function);
		summaries.insert (function, result);
		return result;
	}

}
// One equation per block-entry slot. Instructions run once; successor joins
// receive exact output versions after all blocks have been reconstructed.
// Evaluated values capture their definition's version, not a later slot read.
private class CfgRuntimeLifetimeBody : Object {
	private CfgRuntimeLifetimes analysis;
	private CfgProgram program;
	private CfgFunction function;
	private RuntimeLifetimeEquations graph = new RuntimeLifetimeEquations ();
	private RuntimeLifetimeRegions regions = new RuntimeLifetimeRegions ();
	private HashTable<TextLoanExtent, int> region_ids = new HashTable<TextLoanExtent, int> (direct_hash, direct_equal);
	private HashTable<CfgBlock, RuntimeLifetimeState> entries = new HashTable<CfgBlock, RuntimeLifetimeState> (direct_hash, direct_equal);
	private HashTable<CfgBlock, RuntimeLifetimeState> outputs = new HashTable<CfgBlock, RuntimeLifetimeState> (direct_hash, direct_equal);
	private HashTable<CfgValue, int> values = new HashTable<CfgValue, int> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgValue> definitions = new HashTable<CfgValue, CfgValue> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgBlock> value_blocks = new HashTable<CfgValue, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgValue, int> captured_versions = new HashTable<CfgValue, int> (direct_hash, direct_equal);
	private HashTable<CfgValue, int> captures = new HashTable<CfgValue, int> (direct_hash, direct_equal);
	private HashTable<CfgStructCallResults, CfgTaskSuccess> task_records = new HashTable<CfgStructCallResults, CfgTaskSuccess> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgBlock> task_record_blocks = new HashTable<CfgValue, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgStructCallResults, CfgCallInstruction> record_calls = new HashTable<CfgStructCallResults, CfgCallInstruction> (direct_hash, direct_equal);
	private HashTable<CfgStructCallResults, CfgStructResultConsume> record_consumptions = new HashTable<CfgStructCallResults, CfgStructResultConsume> (direct_hash, direct_equal);
	private HashTable<CfgCallInstruction, CfgGroupCallSuccess> record_successes = new HashTable<CfgCallInstruction, CfgGroupCallSuccess> (direct_hash, direct_equal);
	private HashTable<CfgCallInstruction, CfgBlock> record_success_blocks = new HashTable<CfgCallInstruction, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgCallInstruction, int> record_pending = new HashTable<CfgCallInstruction, int> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgStructBoundaryMove> record_argument_moves = new HashTable<CfgValue, CfgStructBoundaryMove> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgCallInstruction> checked_record_leaves = new HashTable<CfgValue, CfgCallInstruction> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, int> object_slots = new HashTable<CfgObjectStorage, int> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, CfgLocalPlace> object_targets = new HashTable<CfgObjectStorage, CfgLocalPlace> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, CfgScopedAllocator> contexts = new HashTable<CfgLocalPlace, CfgScopedAllocator> (direct_hash, direct_equal);
	private HashTable<int, int> initial_inputs = new HashTable<int, int> (direct_hash, direct_equal);
	private HashTable<int, int> exits = new HashTable<int, int> (direct_hash, direct_equal);
	private GenericArray<int> slots = new GenericArray<int> ();
	private GenericArray<CfgRuntimeBound> bounds = new GenericArray<CfgRuntimeBound> ();
	private GenericArray<RuntimeLifetimeStore> stores = new GenericArray<RuntimeLifetimeStore> ();
	private GenericArray<CfgRuntimeContextUse> context_uses = new GenericArray<CfgRuntimeContextUse> ();
	private GenericArray<CfgRuntimeContextEnd> context_ends = new GenericArray<CfgRuntimeContextEnd> ();
	private RuntimeLifetimeState state = new RuntimeLifetimeState ();
	private CfgBlock current_block;
	private CfgInstruction current_instruction;
	private Object current_site;
	private HashTable<CfgLocalPlace, CfgRuntimeCatchAlias> catch_aliases = new HashTable<CfgLocalPlace, CfgRuntimeCatchAlias> (direct_hash, direct_equal);
	private int returned;
	private int exceptional_result;
	private int normal_exits;
	private int next_slot;
	private int exit_count;
	private string unsupported = "";
	private bool scoped_allocation;
	internal bool requires_scope { get { return scoped_allocation || graph.has_scope_roots; } }
	internal CfgRuntimeLifetimeBody (CfgRuntimeLifetimes analysis, CfgProgram program, CfgFunction function) {
		this.analysis = analysis;
		this.program = program;
		this.function = function;
		current_block = function.entry;
		current_site = function.entry;
		scoped_allocation |= scoped_type (function.return_type) || function.implicit_receiver != null && scoped_type (function.implicit_receiver.contract) || function.throws_type != null && scoped_type (function.throws_type);
		foreach (var parameter in function.parameters) {
			scoped_allocation |= scoped_type (parameter.semantic_type);
		}
		foreach (var local in function.locals) {
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

	private static bool graph_input(SemanticType type) {
		return !(type is HandleType && ((HandleType) type).context_mode != "") && (type is ClassType || type is ReceiverType || type is HandleType || type.is_struct_storage () || type is TaskType);
	}

	private int region_id(TextLoanExtent? extent) throws RuntimeLifetimeError {
		if (extent == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG lifetime requires actual lexical cleanup extents");
		}
		if (!region_ids.contains (extent)) {
			int parent = extent.parent == null ? -1 : region_id (extent.parent);
			region_ids.insert (extent, regions.add_region (parent));
		}
		return region_ids.lookup (extent);
	}

	private int slot() {
		int result = next_slot++;
		slots.add (result);
		return result;
	}

	private void define_value(CfgValue value, CfgBlock block, CfgValue? source = null, bool owning = false) throws RuntimeLifetimeError {
		if (!values.contains (value)) {
			values.insert (value, graph.join ());
			value_blocks.insert (value, block);
			if (source != null) {
				definitions.insert (value, source);
			}
			if (owning) {
				captures.insert (value, slot ());
			}
		}
	}

	private CfgValue origin(CfgValue value) {
		var seen = new HashTable<CfgValue, bool> (direct_hash, direct_equal);
		while (definitions.contains (value) && !seen.contains (value)) {
			seen.insert (value, true);
			value = definitions.lookup (value);
		}
		return value;
	}

	private CfgNativeInstance? instance(SemanticType type) {
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
			var object_class = owner as CfgClass;
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

	private int product(SemanticType type, CfgValue? context = null) throws RuntimeLifetimeError {
		var roots = new GenericArray<RuntimeScopeOrigin> ();
		var anchor = context_origin (context);
		if (anchor != null) {
			roots.add (anchor);
		}
		var fields = new HashTable<string, int> (str_hash, str_equal);
		var owner = instance (type);
		if (owner != null) {
			if (owner is CfgClass && ((CfgClass) owner).parent_class != null) {
				unsupported_node ("CFG inherited fields require nominal paths");
			}
			foreach (var field in owner.fields) {
				fields.insert ("f%d".printf (field.ordinal), graph.absent ());
			}
		}
		return graph.product (roots, fields);
	}

	private RuntimeScopeOrigin? context_origin(CfgValue? argument) throws RuntimeLifetimeError {
		CfgValue? value = argument;
		if (value == null || !value.semantic_type.is_scoped_allocator ()) {
			return null;
		}
		value = origin (value);
		if (value is CfgParameterValue) {
			return new RuntimeScopeOrigin.context_input (((CfgParameterValue) value).parameter.ordinal);
		}
		CfgLocalPlace? local = null;
		if (value is CfgLoadValue) {
			local = ((CfgLoadValue) value).source as CfgLocalPlace;
		} else if (value is CfgOwnedBorrowValue) {
			local = ((CfgOwnedBorrowValue) value).source;
		}
		var factory = local == null ? null : contexts.lookup (local);
		if (factory == null || !function.locals.find (local) || local.text_extent == null || factory.loan.context_ordinal != local.ordinal || factory.loan.region_ordinal != local.text_extent.ordinal) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG scoped allocation requires its exact context declaration");
		}
		context_uses.add (new CfgRuntimeContextUse (current_instruction, local));
		return new RuntimeScopeOrigin.local (local.ordinal, region_id (local.text_extent));
	}

	private CfgRuntimeStorage? object_storage(CfgObjectStorage storage) {
		var target = object_targets.lookup (storage);
		if (target == null || !object_slots.contains (storage)) {
			unsupported_node ("CFG ObjectStorage lacks its actual destination owner");
			return null;
		}
		return new CfgRuntimeStorage (object_slots.lookup (storage), target.ordinal);
	}

	private CfgRuntimeStorage? field(CfgRuntimeStorage? storage, int ordinal) {
		if (storage != null) {
			storage.path += (storage.path == "" ? "" : ".") + "f%d".printf (ordinal);
		}
		return storage;
	}

	private CfgRuntimeStorage? reference(CfgValue? argument) {
		CfgValue? value = argument;
		if (value == null) {
			return null;
		}
		value = origin (value);
		if (value is CfgLoadValue) {
			var local = ((CfgLoadValue) value).source as CfgLocalPlace;
			var alias = local == null ? null : catch_aliases.lookup (local);
			if (alias != null) {
				if (!alias.uses.find (current_site)) {
					alias.uses.add (current_site);
				}
				return new CfgRuntimeStorage (alias.owner, local.ordinal);
			}
			return place (((CfgLoadValue) value).source);
		}
		if (value is CfgParameterValue) {
			int binding = parameter_binding (((CfgParameterValue) value).parameter.ordinal);
			return new CfgRuntimeStorage (binding, binding);
		}
		if (value is CfgReceiverValue) {
			return new CfgRuntimeStorage (-1, -1);
		}
		if (value is CfgOwnedBorrowValue) {
			var local = ((CfgOwnedBorrowValue) value).source;
			return new CfgRuntimeStorage (local.ordinal, local.ordinal);
		}
		if (value is CfgObjectReferenceValue) {
			return object_storage (((CfgObjectReferenceValue) value).storage);
		}
		if (value is CfgStorageReceiverValue) {
			return object_storage (((CfgStorageReceiverValue) value).storage);
		}
		if (value is CfgClassUpcast) {
			return reference (((CfgClassUpcast) value).reference);
		}
		if (value is CfgObjectValidateValue) {
			return reference (((CfgObjectValidateValue) value).reference);
		}
		return null;
	}

	private CfgRuntimeStorage? place(CfgPlace? source) {
		if (source is CfgLocalPlace) {
			int binding = ((CfgLocalPlace) source).ordinal;
			return new CfgRuntimeStorage (binding, binding);
		}
		if (source is CfgTemporaryPlace) {
			int binding = (int) function.locals.length + ((CfgTemporaryPlace) source).ordinal;
			return new CfgRuntimeStorage (binding, binding);
		}
		if (source is CfgFieldPlace) {
			return field (place (((CfgFieldPlace) source).aggregate), ((CfgFieldPlace) source).field.ordinal);
		}
		if (source is CfgIndirectFieldPlace) {
			return field (reference (((CfgIndirectFieldPlace) source).pointer), ((CfgIndirectFieldPlace) source).field.ordinal);
		}
		if (source is CfgObjectFieldPlace) {
			return field (object_storage (((CfgObjectFieldPlace) source).storage), ((CfgObjectFieldPlace) source).field.ordinal);
		}
		unsupported_node ("CFG storage requires its exact owning path");
		return null;
	}

	private int read(CfgRuntimeStorage? storage) throws RuntimeLifetimeError {
		if (storage == null || !state.bindings.contains (storage.binding)) {
			unsupported_node ("CFG read requires a declared graph slot");
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

	private GenericArray<SemanticType>? record_fields(SemanticType type) {
		var owner = instance (type) as CfgStruct;
		if (owner == null) {
			return null;
		}
		var result = new GenericArray<SemanticType> ();
		foreach (var field in owner.fields) {
			result.add (field.semantic_type);
		}
		return result;
	}

	private void record_shape(StructValueShape shape) throws RuntimeLifetimeError {
		try {
			shape.verify (record_fields);
		} catch (StructLeafError failure) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime shape: %s", failure.message);
		}
		if (shape.physical_buffers) {
			unsupported_node ("CFG record buffer lifetimes require exact physical pair correspondence");
		}
	}

	private bool record_parameter_owned(int ordinal) {
		foreach (var group in function.struct_parameters) {
			if (group.shape.mode == StructValueMode.MOVE_VALUE && ordinal >= group.first_leaf && ordinal < group.first_leaf + group.shape.leaves.length) {
				return graph_input (function.parameters[ordinal].semantic_type);
			}
		}
		return false;
	}

	private bool parameter_prefix(CfgInstruction instruction) {
		if (instruction is CfgStructBoundaryAcquire) {
			var acquired = (CfgStructBoundaryAcquire) instruction;
			return acquired.parameter != null && function.struct_parameters.find (acquired.parameter);
		}
		if (instruction is CfgStructParameterBorrow) {
			return function.struct_parameters.find (((CfgStructParameterBorrow) instruction).parameter);
		}
		var initialized = instruction as CfgInitialize;
		var incoming = initialized == null ? null : initialized.value as CfgParameterValue;
		if (incoming == null) {
			return false;
		}
		var local = initialized.target as CfgLocalPlace;
		if (local != null) {
			return function.locals.find (local) && local.incoming_parameter == incoming.parameter;
		}
		var field = initialized.target as CfgFieldPlace;
		local = field == null ? null : field.root_local ();
		return local != null && local.struct_parameter != null && function.struct_parameters.find (local.struct_parameter) && local.struct_parameter.shape.mode == StructValueMode.COPY_VALUE;
	}

	private void record_parameters() throws RuntimeLifetimeError {
		var occupied = new HashTable<int, bool> (direct_hash, direct_equal);
		foreach (var group in function.struct_parameters) {
			record_shape (group.shape);
			if (group.first_leaf < 0 || group.first_leaf > function.parameters.length || group.shape.leaves.length > function.parameters.length - group.first_leaf) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime group exceeds its exact parameter range");
			}
			for (int i = 0; i < group.shape.leaves.length; i++) {
				int ordinal = group.first_leaf + i;
				if (occupied.contains (ordinal) || function.parameters[ordinal].ordinal != ordinal || function.parameters[ordinal].semantic_type != group.shape.leaves[i].semantic_type) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime group lost its exact physical leaf correspondence");
				}
				occupied.insert (ordinal, true);
			}
			if (group.shape.mode == StructValueMode.COPY_VALUE) {
				continue;
			}
			int bindings = 0;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var acquired = instruction as CfgStructBoundaryAcquire;
					var borrowed = instruction as CfgStructParameterBorrow;
					if (!(acquired != null && acquired.parameter == group || borrowed != null && borrowed.parameter == group)) {
						continue;
					}
					var destination = acquired == null ? borrowed.destination : acquired.destination;
					var leaves = acquired == null ? borrowed.leaves : acquired.leaves;
					bindings++;
					if (block != function.entry || !function.locals.find (destination) || destination.struct_parameter != group || destination.semantic_type != group.shape.semantic_type || destination.address_taken || leaves.length != group.shape.leaves.length || (group.shape.mode == StructValueMode.MOVE_VALUE) != (acquired != null) || (acquired != null && (acquired.shape != group.shape || acquired.results != null || acquired.record_move != null || acquired.projection != null || destination.cleanup == null || destination.cleanup.record_type == null || destination.cleanup.record_type.semantic_type != destination.semantic_type)) || borrowed != null && destination.cleanup != null) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime requires its exact complete entry acquisition or borrow");
					}
					for (int i = 0; i < leaves.length; i++) {
						var incoming = leaves[i] as CfgParameterValue;
						if (incoming == null || incoming.parameter != function.parameters[group.first_leaf + i]) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime acquisition changed its original parameter leaf");
						}
					}
					foreach (var prior in function.entry.instructions) {
						if (prior == instruction) {
							break;
						}
						if (!parameter_prefix (prior)) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime entry binding must precede body operations");
						}
					}
				}
			}
			if (bindings != 1) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime requires one original entry binding");
			}
		}
	}

	private int record_value(StructValueShape shape, GenericArray<CfgValue> leaves) throws RuntimeLifetimeError {
		record_shape (shape);
		if (shape.leaves.length != leaves.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime lost a complete leaf group");
		}
		int result = product (shape.semantic_type);
		for (int i = 0; i < leaves.length; i++) {
			var leaf = shape.leaves[i];
			if (leaf.semantic_type != leaves[i].semantic_type) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record lifetime changed a leaf type");
			}
			var path = new StringBuilder ();
			for (int depth = 0; depth < leaf.depth; depth++) {
				if (path.len != 0) {
					path.append_c ('.');
				}
				path.append_printf ("f%d", leaf.field_ordinal (depth));
			}
			result = replace_path (result, path.str, value (leaves[i]));
		}
		return result;
	}

	private int record_return(CfgStructReturn result) throws RuntimeLifetimeError {
		if (function.struct_result != result.shape || result.shape.semantic_type != function.return_type) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result lost its exact declared shape");
		}
		record_shape (result.shape);
		if (result.shape.mode == StructValueMode.MOVE_VALUE) {
			var moved = result.record_move;
			if (moved == null || moved.consumer != result || moved.use_kind != StructResultUseKind.RETURN || moved.shape != result.shape || moved.leaves != result.leaves || !current_block.instructions.find (moved) || !function.locals.find (moved.source) || moved.source.semantic_type != result.shape.semantic_type || result.leaves.length != result.shape.leaves.length) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result lost its exact complete local move publication");
			}
			int sites = 0;
			foreach (var instruction in current_block.instructions) {
				if (instruction == moved) {
					sites++;
				}
			}
			if (sites != 1) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result requires one original move publication");
			}
			for (int i = 0; i < result.leaves.length; i++) {
				var captured = result.leaves[i];
				var loaded = definitions.lookup (captured) as CfgLoadValue;
				var field = loaded == null ? null : loaded.source as CfgFieldPlace;
				if (field == null || field.root_local () != moved.source || !field.storage_path ().same_path (result.shape.leaves[i]) || value_blocks.lookup (captured) != current_block) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result changed an original captured field path");
				}
				bool capture = false;
				foreach (var instruction in current_block.instructions) {
					if (instruction == moved) {
						break;
					}
					var evaluated = instruction as CfgEvaluateInstruction;
					if (evaluated != null && evaluated.result == captured && evaluated.value == loaded) {
						capture = true;
					}
				}
				if (!capture) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result requires its field capture before the move commit");
				}
			}
		} else if (result.shape.mode == StructValueMode.COPY_VALUE) {
			if (result.record_move != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG copied record result cannot consume an owner group");
			}
			foreach (var leaf in result.shape.leaves) {
				var type = leaf.semantic_type;
				if (!(type is IntegerType) && !(type is FloatingType) && !(type is VectorType) && type.kind != TypeKind.BOOL) {
					unsupported_node ("CFG copied record result requires its exact nonowning field correspondence");
				}
			}
		} else {
			unsupported_node ("CFG borrowed record result requires its exact output loan");
		}
		int value = record_value (result.shape, result.leaves);
		foreach (var leaf in result.leaves) {
			consume (leaf);
		}
		return value;
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

	private void record_call(CfgCallInstruction call, CfgBlock block) throws RuntimeLifetimeError {
		var group = call.struct_result;
		if (group == null) {
			return;
		}
		record_shape (group.shape);
		if (call.target == null || call.target.struct_result != group.shape || group.shape.semantic_type != call.target.return_type || group.leaves.length != group.shape.leaves.length || record_calls.contains (group)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record call lost its unique exact declared result group");
		}
		CfgBlock publication = block;
		if (call.target.throws_type != null) {
			var branch = block.terminator as CfgConditionalBranch;
			var condition = branch == null ? null : branch.condition as CfgBinaryValue;
			if (call.exception_result == null || condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != call.exception_result || !(condition.right is CfgNullPointerValue) || branch.true_target == branch.false_target || block.instructions[block.instructions.length - 1] != call) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked record call requires its exact original success/error test");
			}
			publication = branch.true_target;
			CfgGroupCallSuccess? success = null;
			foreach (var candidate in function.blocks) {
				foreach (var instruction in candidate.instructions) {
					var marker = instruction as CfgGroupCallSuccess;
					if (marker != null && marker.call == call) {
						if (success != null || candidate != publication || candidate.instructions[0] != marker) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked record requires one original guarded success publication");
						}
						success = marker;
					}
				}
				foreach (var next in candidate.terminator.successors ()) {
					if (next == publication && candidate != block) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked record success gained an unguarded predecessor");
					}
				}
			}
			if (success == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked record lost its original success publication");
			}
			record_successes.insert (call, success);
			record_success_blocks.insert (call, publication);
			record_pending.insert (call, graph.join ());
		}
		record_calls.insert (group, call);
		for (int i = 0; i < group.leaves.length; i++) {
			if (group.leaves[i].semantic_type != group.shape.leaves[i].semantic_type || values.contains (group.leaves[i])) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record call changed or repeated an original result leaf");
			}
			define_value (group.leaves[i], publication, null, group.shape.mode == StructValueMode.MOVE_VALUE && graph_input (group.leaves[i].semantic_type));
			if (call.target.throws_type != null) {
				checked_record_leaves.insert (group.leaves[i], call);
			}
		}
	}

	private void task_record(CfgTaskSuccess success, CfgBlock publication) throws RuntimeLifetimeError {
		var group = success.struct_result;
		var wait = success.operation;
		var task = wait.child.semantic_type as TaskType;
		if (group == null || task == null || wait.success != success || wait.discard || success.result != null || success.enum_result != null || success.buffer_cleanup != null || success.success_type != group.shape.semantic_type || task.success_type.logical_identity != success.success_type.logical_identity || task_records.contains (group) || record_calls.contains (group) || group.leaves.length != group.shape.leaves.length || publication.instructions[0] != success) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG task record lost its complete original success group");
		}
		record_shape (group.shape);
		CfgBlock? waited = null;
		int sites = 0;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction == wait) {
					waited = block;
					sites++;
				}
			}
		}
		var branch = waited == null ? null : waited.terminator as CfgConditionalBranch;
		var condition = branch == null ? null : branch.condition as CfgBinaryValue;
		if (sites != 1 || waited.instructions[waited.instructions.length - 1] != wait || condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != wait.exception || !(condition.right is CfgNullPointerValue) || branch.true_target != publication || branch.false_target == publication) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG task record requires its exact original success/error test");
		}
		foreach (var block in function.blocks) {
			foreach (var next in block.terminator.successors ()) {
				if (next == publication && block != waited) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG task record success gained an unguarded predecessor");
				}
			}
		}
		task_records.insert (group, success);
		for (int i = 0; i < group.leaves.length; i++) {
			var leaf = group.leaves[i];
			if (leaf.semantic_type != group.shape.leaves[i].semantic_type || values.contains (leaf)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG task record changed an original physical result leaf");
			}
			define_value (leaf, publication, null, group.shape.mode == StructValueMode.MOVE_VALUE && graph_input (leaf.semantic_type));
			task_record_blocks.insert (leaf, publication);
		}
	}

	private void record_consumption(CfgStructResultConsume consumed) throws RuntimeLifetimeError {
		var call = record_calls.lookup (consumed.results);
		var task = task_records.lookup (consumed.results);
		var destination = consumed.destination as CfgLocalPlace;
		if (call == null && task == null || consumed.use_kind != StructResultUseKind.INITIALIZE || destination == null) {
			unsupported_node ("CFG record result consumption requires its exact direct producer and local acquisition");
			return;
		}
		if (record_consumptions.contains (consumed.results) || !function.locals.find (destination) || destination.semantic_type != consumed.results.shape.semantic_type) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result consumption lost its unique original destination");
		}
		int position = 0;
		while (position < current_block.instructions.length && current_block.instructions[position] != consumed) {
			position++;
		}
		var acquired = position + 1 < current_block.instructions.length ? current_block.instructions[position + 1] as CfgStructBoundaryAcquire : null;
		if (consumed.results.shape.mode == StructValueMode.MOVE_VALUE && (acquired == null || acquired.results != consumed.results || acquired.destination != destination)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result consumption lost its immediate original owner acquisition");
		}
		bool producer = false;
		foreach (var instruction in current_block.instructions) {
			if (instruction == consumed) {
				break;
			}
			if (instruction == task || instruction == call || record_successes.lookup (call) == instruction && record_success_blocks.lookup (call) == current_block) {
				producer = true;
			}
		}
		if (!producer) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result consumption must follow its original call or guarded success publication");
		}
		record_consumptions.insert (consumed.results, consumed);
	}

	private void record_acquisition(CfgStructBoundaryAcquire acquired) throws RuntimeLifetimeError {
		if (acquired.parameter != null) {
			if (!function.struct_parameters.find (acquired.parameter) || acquired.results != null || acquired.record_move != null || acquired.projection != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record acquisition lost its exclusive parameter correspondence");
			}
			return;
		}
		var consumed = acquired.results == null ? null : record_consumptions.lookup (acquired.results);
		if (consumed == null) {
			unsupported_node ("CFG record acquisition requires its exact parameter or producer correspondence");
			return;
		}
		if (acquired.projection != null || acquired.record_move != null || acquired.shape.mode != StructValueMode.MOVE_VALUE || acquired.results.shape != acquired.shape || consumed.destination != acquired.destination || !function.locals.find (acquired.destination) || acquired.destination.semantic_type != acquired.shape.semantic_type || acquired.destination.cleanup == null || acquired.destination.cleanup.record_type == null || acquired.destination.cleanup.record_type.semantic_type != acquired.destination.semantic_type || acquired.leaves.length != acquired.results.leaves.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result acquisition lost its exact complete owning local");
		}
		int position = 0;
		while (position < current_block.instructions.length && current_block.instructions[position] != acquired) {
			position++;
		}
		if (position == 0 || position == current_block.instructions.length || current_block.instructions[position - 1] != consumed) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result acquisition requires its immediate original consumption");
		}
		for (int i = 0; i < acquired.leaves.length; i++) {
			if (acquired.leaves[i] != acquired.results.leaves[i]) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result acquisition changed an original producer field");
			}
		}
	}

	private void write(CfgRuntimeStorage? storage, int incoming, bool effect = true) throws RuntimeLifetimeError {
		if (storage == null) {
			unsupported_node ("CFG write requires its actual destination");
			return;
		}
		int value = storage.path == "" ? incoming : replace_path (state.bindings.lookup (storage.binding), storage.path, incoming);
		state.bindings.insert (storage.binding, value);
		if (storage.destination >= 0 && storage.destination < function.locals.length) {
			bounds.add (new CfgRuntimeBound (value, storage.destination));
		} else if (storage.destination < 0 && effect) {
			stores.add (new RuntimeLifetimeStore (storage.destination == -1 ? -1 : -storage.destination - 2, incoming));
		}
	}

	private void publish_value(CfgValue result, int incoming) throws RuntimeLifetimeError {
		if (!values.contains (result)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG value definition is outside the exact inventory");
		}
		graph.alternative (values.lookup (result), incoming);
		if (captures.contains (result)) {
			state.bindings.insert (captures.lookup (result), incoming);
		}
	}

	private void consume(CfgValue? value) {
		if (value != null && captures.contains (value)) {
			state.bindings.insert (captures.lookup (value), graph.absent ());
		}
	}

	private void drop(CfgValue pointer, CfgCleanupContract cleanup) throws RuntimeLifetimeError, CfgError {
		var storage = reference (pointer);
		if (storage == null) {
			unsupported_node ("CFG cleanup lacks its exact owner storage");
			return;
		}
		if (pointer.semantic_type.is_scoped_allocator ()) {
			context_ends.add (new CfgRuntimeContextEnd (storage.binding, state));
		}
		if (cleanup.is_object && cleanup.object_class.destructor != null && read (storage) != graph.absent ()) {
			var invocation = new CfgCallInstruction (pointer.span, cleanup.object_class.destructor, new GenericArray<CfgValue> (), null, pointer);
			invoke (invocation);
		}
		write (storage, graph.absent (), false);
	}

	private int value(CfgValue? source) throws RuntimeLifetimeError {
		if (source != null && task_record_blocks.contains (source) && task_record_blocks.lookup (source) != current_block) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG task record leaf escaped its exact success publication block");
		}
		if (source != null && checked_record_leaves.contains (source) && record_success_blocks.lookup (checked_record_leaves.lookup (source)) != current_block) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked record leaf escaped its exact success publication block");
		}
		if (source == null) {
			return graph.absent ();
		}
		if (values.contains (source)) {
			return values.lookup (source);
		}
		if (source is CfgLoadValue || source is CfgParameterValue || source is CfgReceiverValue || source is CfgOwnedBorrowValue || source is CfgObjectReferenceValue || source is CfgStorageReceiverValue || source is CfgClassUpcast || source is CfgObjectValidateValue) {
			int loaded = read (reference (source));
			return (source.semantic_type.kind == TypeKind.BOOL || source.semantic_type is IntegerType || source.semantic_type is FloatingType || source.semantic_type is VectorType) ? graph.absent () : loaded;
		}
		if (source is CfgCatchBorrow) {
			var caught = (CfgCatchBorrow) source;
			bool registered = false;
			foreach (var handler in function.handlers) {
				if (handler.borrow == caught && handler.selection.exception == caught.exception && handler.selection.match_type == caught.semantic_type) {
					registered = true;
				}
			}
			if (!registered) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG catch borrow lost its actual protected exception channel");
			}
			return value (caught.exception);
		}
		if (source is CfgExceptionMatch) {
			value (((CfgExceptionMatch) source).exception);
			return graph.absent ();
		}
		if (source is CfgBinaryValue) {
			value (((CfgBinaryValue) source).left);
			value (((CfgBinaryValue) source).right);
			return graph.absent ();
		}
		if (source is CfgPrefixValue) {
			value (((CfgPrefixValue) source).operand);
			return graph.absent ();
		}
		if (source is CfgIntegerValue || source is CfgBooleanValue || source is CfgFloatValue || source is CfgTextValue || source is CfgNullPointerValue) {
			return graph.absent ();
		}
		if (source is CfgScopedAllocator) {
			value (((CfgScopedAllocator) source).kind);
			value (((CfgScopedAllocator) source).slots);
			return graph.absent ();
		}
		if (source is CfgSliceLengthValue) {
			value (((CfgSliceLengthValue) source).slice);
			return graph.absent ();
		}
		unsupported_node ("CFG value requires its exact lifetime operation: " + source.get_type ().name ());
		return graph.absent ();
	}

	private void record_argument_move(CfgStructBoundaryMove moved) throws RuntimeLifetimeError {
		if (moved.leaves.length != moved.shape.leaves.length || moved.consumer == null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record argument lost its complete original move consumer");
		}
		for (int i = 0; i < moved.leaves.length; i++) {
			var captured = moved.leaves[i];
			var loaded = definitions.lookup (captured) as CfgLoadValue;
			var field = loaded == null ? null : loaded.source as CfgFieldPlace;
			if (field == null || field.root_local () != moved.source || !field.storage_path ().same_path (moved.shape.leaves[i]) || captured.semantic_type != moved.shape.leaves[i].semantic_type || value_blocks.lookup (captured) != current_block || !captured_versions.contains (captured) || captured_versions.lookup (captured) != state.bindings.lookup (moved.source.ordinal) || record_argument_moves.contains (captured)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record argument requires its unchanged original captured field and one move");
			}
			bool before = false;
			foreach (var instruction in current_block.instructions) {
				if (instruction == moved) {
					break;
				}
				var evaluation = instruction as CfgEvaluateInstruction;
				if (evaluation != null && evaluation.result == captured && evaluation.value == loaded) {
					before = true;
				}
			}
			if (!before) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record argument must capture its field before the move");
			}
			record_argument_moves.insert (captured, moved);
		}
	}

	private HashTable<int, bool> record_arguments(CfgCallInstruction call) throws RuntimeLifetimeError {
		var moved_positions = new HashTable<int, bool> (direct_hash, direct_equal);
		var target = call.target;
		if (target == null || call.struct_arguments.length != target.struct_parameters.length) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record call lost its complete original parameter groups");
		}
		for (int g = 0; g < call.struct_arguments.length; g++) {
			var argument = call.struct_arguments[g];
			var parameter = target.struct_parameters[g];
			record_shape (argument.shape);
			if (argument.first_leaf != parameter.first_leaf || argument.source_ordinal != parameter.source_ordinal || argument.shape.semantic_type != parameter.shape.semantic_type || argument.shape.mode != parameter.shape.mode || argument.first_leaf < 0 || argument.first_leaf + argument.shape.leaves.length > call.arguments.length) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record argument lost its exact declared group and ordered channels");
			}
			if (argument.shape.mode != StructValueMode.MOVE_VALUE) {
				continue;
			}
			int matches = 0;
			foreach (var moved in call.record_moves) {
				if (moved.consumer != call || moved.use_kind != StructResultUseKind.ARGUMENT || moved.shape != argument.shape || !current_block.instructions.find (moved) || moved.leaves.length != argument.shape.leaves.length) {
					continue;
				}
				bool exact = true;
				for (int i = 0; i < moved.leaves.length; i++) {
					var leaf = call.arguments[argument.first_leaf + i];
					exact = exact && leaf == moved.leaves[i] && record_argument_moves.lookup (leaf) == moved;
				}
				if (exact) {
					matches++;
				}
			}
			if (matches != 1) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record argument requires one exact committed original leaf group");
			}
			for (int i = 0; i < argument.shape.leaves.length; i++) {
				if (moved_positions.contains (argument.first_leaf + i)) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record argument repeats one physical channel");
				}
				moved_positions.insert (argument.first_leaf + i, true);
			}
		}
		return moved_positions;
	}

	private int task_create(CfgTaskCreate call) throws RuntimeLifetimeError, CfgError {
		if (call.target == null || call.target.async_body == null || !call.matches_captures () || call.result == null || call.result.semantic_type != call.target.async_body.task_type || call.checked_admission != (call.exception_result != null)) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG cold task lost its exact factory/capture/admission contract");
		}
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		for (int i = 0; i < call.arguments.length; i++) {
			inputs.insert (i, value (call.arguments[i]));
			var anchor = context_origin (call.arguments[i]);
			if (anchor != null) {
				anchors.insert (i, anchor);
			}
		}
		record_arguments (call);
		var summary = analysis.summary (call.target);
		if (summary == null || !summary.complete || summary.has_exception || summary.store_count != 0 || summary.updated_inputs ().length != 0) {
			unsupported_node ("CFG cold task requires a complete deferred body lifetime contract");
			return graph.absent ();
		}
		int task = summary.equations.instantiate (summary.result, graph, inputs, anchors);
		var context = context_origin (call.allocation_context);
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
			publish_value (call.exception_result, graph.absent ());
			foreach (var argument in call.arguments) {
				var captured = argument as CfgPendingOwnedArgument;
				if (captured == null || captured.source == null) {
					continue;
				}
				if (captured.consumer != call || captured.parameter.ordinal < 0 || captured.parameter.ordinal >= call.target.parameters.length || call.target.parameters[captured.parameter.ordinal] != captured.parameter) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG frame refusal lost its exact captured caller input");
				}
				int restored = graph.join ();
				graph.alternative (restored, state.bindings.lookup (captured.source.ordinal));
				graph.alternative (restored, value (captured));
				write (place (captured.source), restored, false);
			}
		}
		if (call.checked_admission) {
			foreach (var moved in call.record_moves) {
				int restored = graph.join ();
				graph.alternative (restored, state.bindings.lookup (moved.source.ordinal));
				graph.alternative (restored, record_value (moved.shape, moved.leaves));
				write (place (moved.source), restored, false);
			}
		}
		return task;
	}

	private void empty_enum(CfgEnumSlot slot) {
		if (slot.definition.value_fields ().length != 0) {
			unsupported_node ("CFG enum lifetime requires its exact payload operation");
		}
	}

	private int invoke(CfgCallInstruction call, int constructed = -1) throws RuntimeLifetimeError, CfgError {
		var target = call.target;
		var inputs = new HashTable<int, int> (direct_hash, direct_equal);
		var anchors = new HashTable<int, RuntimeScopeOrigin> (direct_hash, direct_equal);
		var destinations = new HashTable<int, CfgRuntimeStorage> (direct_hash, direct_equal);
		if (constructed >= 0) {
			inputs.insert (-1, constructed);
		} else if (call.receiver != null) {
			inputs.insert (-1, value (call.receiver));
			var destination = reference (call.receiver);
			if (destination != null) {
				destinations.insert (-1, destination);
			}
		}
		for (int i = 0; i < call.arguments.length; i++) {
			var argument = call.arguments[i];
			inputs.insert (i, value (argument));
			var anchor = context_origin (argument);
			if (anchor != null) {
				anchors.insert (i, anchor);
			}
			var destination = reference (argument);
			if (destination != null) {
				destinations.insert (i, destination);
			}
		}
		var summary = analysis.summary (target);
		if (summary == null || !summary.complete || target.dispatch_kind != ClassDispatchKind.DIRECT) {
			unsupported_node ("CFG call requires a complete direct lifetime summary: " + (target == null ? "missing target" : target.name) + (summary == null ? "" : ": " + summary.limitation));
			return constructed >= 0 ? constructed : graph.absent ();
		}
		var moved_arguments = record_arguments (call);
		var updates = summary.updated_inputs ();
		if (updates.length != 0) {
			for (int p = 0; p < call.arguments.length; p++) {
				if (!moved_arguments.contains (p)) {
					check_pending (call.arguments[p]);
				}
			}
			if (call.receiver != null) {
				check_pending (call.receiver);
			}
		}
		for (uint i = 0; i < summary.store_count; i++) {
			var stored = summary.store (i);
			int incoming = summary.equations.instantiate (stored.value, graph, inputs, anchors);
			var destination = destinations.lookup (stored.parameter);
			if (destination == null) {
				if (!(constructed >= 0 && stored.parameter == -1)) {
					unsupported_node ("CFG call store lacks its actual cleanup extent");
				}
			} else if (destination.destination >= 0 && destination.destination < function.locals.length) {
				bounds.add (new CfgRuntimeBound (incoming, destination.destination));
			} else if (destination.destination < 0) {
				stores.add (new RuntimeLifetimeStore (destination.destination == -1 ? -1 : -destination.destination - 2, incoming));
			}
		}
		int result = constructed >= 0 ? constructed : summary.equations.instantiate (summary.result, graph, inputs, anchors);
		for (int i = 0; i < updates.length; i++) {
			int parameter = updates[i];
			int incoming = summary.equations.instantiate (summary.update (parameter), graph, inputs, anchors);
			if (constructed >= 0 && parameter == -1) {
				result = incoming;
			} else {
				write (destinations.lookup (parameter), incoming, false);
			}
		}
		if (target.throws_type != null) {
			if (!summary.has_exception || call.exception_result == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG throwing call lost its exceptional lifetime channel");
			}
			publish_value (call.exception_result, summary.equations.instantiate (summary.exception, graph, inputs, anchors));
		} else if (summary.has_exception || call.exception_result != null) {
			throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG nonthrowing call gained an exceptional lifetime channel");
		}
		return result;
	}

	private void check_pending(CfgValue value) {
		if (!value_blocks.contains (value) || !graph_input (value.semantic_type)) {
			return;
		}
		var destination = reference (value);
		if (destination == null) {
			return;
		}
		if (value_blocks.lookup (value) != current_block || !captured_versions.contains (value) || state.bindings.lookup (destination.binding) != captured_versions.lookup (value)) {
			unsupported_node ("CFG mutating call requires unchanged exact pending borrowed storage");
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

	private void instruction(CfgInstruction source) throws RuntimeLifetimeError, CfgError {
		current_instruction = source;
		current_site = source;
		if (source is CfgTaskCreate) {
			var call = (CfgTaskCreate) source;
			publish_value (call.result, task_create (call));
			foreach (var argument in call.arguments) {
				consume (argument);
			}
		} else if (source is CfgTaskMove) {
			var moved = (CfgTaskMove) source;
			publish_value (moved.result, read (place (moved.source)));
			write (place (moved.source), graph.absent (), false);
		} else if (source is CfgTaskBorrow) {
			var borrowed = (CfgTaskBorrow) source;
			publish_value (borrowed.result, read (place (borrowed.source)));
		} else if (source is CfgTaskEnd) {
			write (place (((CfgTaskEnd) source).source), graph.absent (), false);
		} else if (source is CfgExecutorEnd) {
			write (place (((CfgExecutorEnd) source).source), graph.absent (), false);
		} else if (source is CfgTaskStarted) {
			value (((CfgTaskStarted) source).operation.task);
		} else if (source is CfgAsyncDelay) {
			var delay = (CfgAsyncDelay) source;
			value (delay.ticks);
			publish_value (delay.exception, graph.absent ());
		} else if (source is CfgTaskWait) {
			var wait = (CfgTaskWait) source;
			value (wait.bridge_executor);
			int task = value (wait.child);
			publish_value (wait.exception, wait.discard ? graph.absent () : graph.project (task, "f1"));
			consume (wait.child);
		} else if (source is CfgTaskSuccess) {
			var success = (CfgTaskSuccess) source;
			if (success.operation.success != success || success.operation.discard) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG task result lost its exact successful observation");
			}
			int result = graph.project (value (success.operation.child), "f0");
			if (success.result != null) {
				publish_value (success.result, result);
			} else if (success.struct_result != null) {
				if (task_records.lookup (success.struct_result) != success) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG task record lost its original result correspondence");
				}
				for (int i = 0; i < success.struct_result.leaves.length; i++) {
					publish_value (success.struct_result.leaves[i], graph.project (result, record_path (success.struct_result.shape.leaves[i])));
				}
			} else {
				unsupported_node ("CFG task grouped result needs its exact publication correspondence");
			}
		} else if (source is CfgAsyncOperation) {
			var operation = (CfgAsyncOperation) source;
			value (operation.executor);
			value (operation.argument);
			int task = value (operation.task);
			if (operation.result != null) {
				publish_value (operation.result, graph.absent ());
			}
			if (operation.exception != null) {
				publish_value (operation.exception, operation.contract.kind == AsyncOperationKind.RUN ? graph.project (task, "f1") : graph.absent ());
			}
			if (operation.contract.kind == AsyncOperationKind.RUN) {
				consume (operation.task);
			}
		} else if (source is CfgAsyncRunStatus) {
			empty_enum (((CfgAsyncRunStatus) source).destination);
		} else if (source is CfgEnumCopy) {
			empty_enum (((CfgEnumCopy) source).source);
			empty_enum (((CfgEnumCopy) source).destination);
		} else if (source is CfgEnumDrop) {
			empty_enum (((CfgEnumDrop) source).source);
		} else if (source is CfgEnumEndInspection) {
			empty_enum (((CfgEnumEndInspection) source).source);
		} else if (source is CfgEnumFinishArm) {
			empty_enum (((CfgEnumFinishArm) source).source);
		} else if (source is CfgStructBoundaryAcquire) {
			var acquired = (CfgStructBoundaryAcquire) source;
			record_acquisition (acquired);
			write (place (acquired.target), record_value (acquired.shape, acquired.leaves));
			foreach (var leaf in acquired.leaves) {
				consume (leaf);
			}
		} else if (source is CfgGroupCallSuccess) {
			var success = (CfgGroupCallSuccess) source;
			var call = success.call;
			if (call == null || call.struct_result == null) {
				unsupported_node ("CFG grouped success requires its exact record result correspondence");
			} else {
				if (record_successes.lookup (call) != success || record_success_blocks.lookup (call) != current_block || !record_pending.contains (call)) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked record changed its original success publication");
				}
				for (int i = 0; i < call.struct_result.leaves.length; i++) {
					publish_value (call.struct_result.leaves[i], graph.project (record_pending.lookup (call), record_path (call.struct_result.shape.leaves[i])));
				}
			}
		} else if (source is CfgStructResultConsume) {
			record_consumption ((CfgStructResultConsume) source);
		} else if (source is CfgStructParameterBorrow) {
			var borrowed = (CfgStructParameterBorrow) source;
			if (!function.struct_parameters.find (borrowed.parameter)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record borrow lost its declared parameter group");
			}
			write (place (borrowed.destination), record_value (borrowed.parameter.shape, borrowed.leaves), false);
		} else if (source is CfgStructBoundaryMove) {
			var moved = (CfgStructBoundaryMove) source;
			record_shape (moved.shape);
			if (moved.shape.mode != StructValueMode.MOVE_VALUE || !function.locals.find (moved.source) || moved.source.semantic_type != moved.shape.semantic_type || moved.source.cleanup == null || moved.source.cleanup.record_type == null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record move lost its exact owning local");
			}
			if (moved.use_kind == StructResultUseKind.ARGUMENT) {
				record_argument_move (moved);
			}
			foreach (var leaf in moved.leaves) {
				value (leaf);
				if (moved.use_kind == StructResultUseKind.RETURN && (!captured_versions.contains (leaf) || captured_versions.lookup (leaf) != state.bindings.lookup (moved.source.ordinal))) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result requires unchanged exact captured field storage");
				}
			}
			write (place (moved.source), graph.absent (), false);
		} else if (source is CfgRecordFieldCommit) {
			var committed = (CfgRecordFieldCommit) source;
			if (committed.destination.semantic_type != committed.shape.semantic_type || committed.shape.mode != StructValueMode.MOVE_VALUE) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record field commit lost its exact owning type");
			}
			write (place (committed.destination), record_value (committed.shape, committed.leaves));
		} else if (source is CfgRecordFieldDrop) {
			var dropped = (CfgRecordFieldDrop) source;
			record_shape (dropped.shape);
			if (dropped.source.semantic_type != dropped.shape.semantic_type || dropped.shape.mode != StructValueMode.MOVE_VALUE) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record field retirement lost its exact owning type");
			}
			write (place (dropped.source), graph.absent (), false);
		} else if (source is CfgLifecycleCallInstruction && ((CfgLifecycleCallInstruction) source).constructs) {
			var call = (CfgLifecycleCallInstruction) source;
			var receiver = (CfgStorageReceiverValue) call.receiver;
			var storage = call.storage;
			var policy = storage.object_class.allocation_policy;
			var context = receiver.allocation_context;
			var handle = context == null ? null : context.semantic_type as HandleType;
			if (policy != null && policy.kind == AllocationKind.CONTEXT ? !policy.valid () || handle == null || handle.context_mode != policy.context_mode : context != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG allocation lost exact context mode");
			}
			RuntimeLifetimeState? refused = storage.fallible ? state.snapshot () : null;
			write (object_storage (storage), invoke (call, product (storage.semantic_type, context)));
			if (refused != null) {
				conditional_state (refused);
				foreach (var argument in call.arguments) {
					var captured = argument as CfgPendingOwnedArgument;
					if (captured == null || captured.source == null) {
						continue;
					}
					if (captured.consumer != call || captured.parameter.ordinal < 0 || captured.parameter.ordinal >= call.target.parameters.length || call.target.parameters[captured.parameter.ordinal] != captured.parameter) {
						throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG fallible input lost its exact capture/constructor channel");
					}
					int restored = graph.join ();
					graph.alternative (restored, state.bindings.lookup (captured.source.ordinal));
					graph.alternative (restored, value (captured));
					write (new CfgRuntimeStorage (captured.source.ordinal, captured.source.ordinal), restored, false);
				}
			}
			foreach (var argument in call.arguments) {
				consume (argument);
			}
		} else if (source is CfgCallInstruction) {
			var call = (CfgCallInstruction) source;
			int result = invoke (call);
			if (call.result != null) {
				publish_value (call.result, result);
			}
			if (call.struct_result != null) {
				if (record_pending.contains (call)) {
					graph.alternative (record_pending.lookup (call), result);
				} else {
					for (int i = 0; i < call.struct_result.leaves.length; i++) {
						publish_value (call.struct_result.leaves[i], graph.project (result, record_path (call.struct_result.shape.leaves[i])));
					}
				}
			}
			foreach (var argument in call.arguments) {
				consume (argument);
			}
			if (call is CfgLifecycleCallInstruction && !((CfgLifecycleCallInstruction) call).constructs) {
				write (object_storage (((CfgLifecycleCallInstruction) call).storage), graph.absent (), false);
			}
		} else if (source is CfgCCallInstruction) {
			var call = (CfgCCallInstruction) source;
			var target = call.target;
			bool admitted = target != null && call.arguments.length == target.parameters.length && RuntimeForeignLifetimes.result (target.return_type, target.owned_cleanup == null ? null : target.owned_cleanup.external_symbol);
			if (target != null) {
				foreach (var parameter in target.parameters) {
					admitted = admitted && RuntimeForeignLifetimes.input (parameter.semantic_type, parameter.pointer_contract, target.owned_cleanup != null);
				}
			}
			if (!admitted) {
				unsupported_node ("CFG foreign call requires an exact owner/pointer/callback lifetime effect");
			}
			foreach (var argument in call.arguments) {
				value (argument);
				context_origin (argument);
				consume (argument);
			}
			if (call.result != null) {
				publish_value (call.result, graph.absent ());
			}
		} else if (source is CfgOwnedArgumentCapture) {
			var capture = ((CfgOwnedArgumentCapture) source).transfer;
			if (capture.source == null && capture.fresh_staged) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG fresh capture lost its staging owner");
			}
			int incoming = capture.source == null ? graph.absent() : state.bindings.lookup (capture.source.ordinal);
			publish_value (capture, incoming);
			if (capture.source != null) {
				state.bindings.insert (capture.source.ordinal, graph.absent ());
			}
		} else if (source is CfgExceptionTake) {
			var take = (CfgExceptionTake) source;
			publish_value (take.result, state.bindings.lookup (take.owner.ordinal));
			state.bindings.insert (take.owner.ordinal, graph.absent ());
		} else if (source is CfgTextSnapshotDestroy) {
			write (place (((CfgTextSnapshotDestroy) source).field), graph.absent (), false);
		} else if (source is CfgExceptionStamp) {
			value (((CfgExceptionStamp) source).exception);
		} else if (source is CfgOwnedArgumentAbort) {
			var transfer = ((CfgOwnedArgumentAbort) source).transfer;
			var call = transfer.consumer as CfgCallInstruction;
			if (!transfer.exceptional_abort || call == null || !call.arguments.find (transfer)) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG exception abort lost its exact pending input/consumer");
			}
			if (transfer.source != null) {
				state.bindings.insert (transfer.source.ordinal, value (transfer));
			}
			consume (transfer);
		} else if (source is CfgConstructorAbort) {
			var abort = (CfgConstructorAbort) source;
			if (abort.lazy_properties.length != 0) {
				unsupported_node ("CFG lazy constructor unwind needs exact cache lifetime effects");
			}
			int receiver = state.bindings.lookup (-1);
			foreach (var field in abort.fields) {
				receiver = graph.replace (receiver, "f%d".printf (field.field.ordinal), graph.absent ());
			}
			state.bindings.insert (-1, receiver);
		} else if (source is CfgEvaluateInstruction) {
			var evaluation = (CfgEvaluateInstruction) source;
			var captured = source as CfgResourceCapture;
			int incoming = value (evaluation.value);
			var storage = reference (evaluation.value);
			if (storage != null) {
				captured_versions.insert (evaluation.result, state.bindings.lookup (storage.binding));
			}
			publish_value (evaluation.result, incoming);
			if (captured != null && captured.source != null) {
				state.bindings.insert (captured.source.ordinal, graph.absent ());
			}
		} else if (source is CfgOwnedBorrowInstruction) {
			var borrowed = ((CfgOwnedBorrowInstruction) source).result;
			publish_value (borrowed, state.bindings.lookup (borrowed.source.ordinal));
			captured_versions.insert (borrowed, state.bindings.lookup (borrowed.source.ordinal));
		} else if (source is CfgOwnedCallTransferCommit || source is CfgValidatePlace || source is CfgBufferSlotCapture) {
		} else if (source is CfgOwnershipTransferInstruction) {
			var transfer = (CfgOwnershipTransferInstruction) source;
			int incoming = state.bindings.lookup (transfer.source.ordinal);
			state.bindings.insert (transfer.source.ordinal, graph.absent ());
			write (place (transfer.destination), incoming);
		} else if (source is CfgOwnershipRearmInstruction) {
			var rearm = (CfgOwnershipRearmInstruction) source;
			int incoming = rearm.source == null ? value(rearm.value) : state.bindings.lookup (rearm.source.ordinal);
			if (rearm.source != null) {
				state.bindings.insert (rearm.source.ordinal, graph.absent ());
			}
			write (place (rearm.owner), incoming);
			consume (rearm.value);
		} else if (source is CfgOwnershipReleaseInstruction) {
			var released = (CfgOwnershipReleaseInstruction) source;
			drop (new CfgLoadValue (released.span, released.owner), released.cleanup);
		} else if (source is CfgInitialize) {
			var initialized = (CfgInitialize) source;
			var alias_local = initialized.target as CfgLocalPlace;
			if (alias_local != null && catch_aliases.contains (alias_local)) {
				int borrowed = value (initialized.value);
				bounds.add (new CfgRuntimeBound (borrowed, alias_local.ordinal));
				state.bindings.insert (alias_local.ordinal, graph.absent ());
			} else {
				write (place (initialized.target), value (initialized.value));
			} consume (initialized.value);
			var local = initialized.target as CfgLocalPlace;
			var root = origin (initialized.value) as CfgObjectReferenceValue;
			if (local != null && root != null && root.storage.transferable) {
				state.bindings.insert (object_slots.lookup (root.storage), graph.absent ());
			}
			if (local != null && local.cleanup == null && local.semantic_type is ClassType && root == null && !(initialized.value is CfgCatchBorrow)) {
				unsupported_node ("CFG persistent borrowed Class aliases need storage effects");
			}
		} else if (source is CfgStore) {
			var stored = (CfgStore) source;
			write (place (stored.target), value (stored.value));
			consume (stored.value);
		} else if (source is CfgOwnershipReturnInstruction) {
			var returned = ((CfgOwnershipReturnInstruction) source).result;
			int incoming = returned.source == null ? value(returned.producer) : state.bindings.lookup (returned.source.ordinal);
			publish_value (returned, incoming);
			if (returned.source != null) {
				state.bindings.insert (returned.source.ordinal, graph.absent ());
			}
			consume (returned.producer);
		} else if (source is CfgCleanupInstruction) {
			var cleanup = (CfgCleanupInstruction) source;
			drop (cleanup.value, cleanup.cleanup);
		} else if (source is CfgBufferAllocate) {
			var allocation = (CfgBufferAllocate) source;
			if (allocation.failure != null) {
				unsupported_node ("CFG buffer failure requires exceptional effects");
			}
			value (allocation.count);
			int result = product (allocation.cleanup.buffer_type, allocation.allocation_context);
			publish_value (allocation.results.owner, result);
			publish_value (allocation.results.base_value, result);
			publish_value (allocation.results.length_value, graph.absent ());
		} else if (source is CfgBufferExchange) {
			var exchange = (CfgBufferExchange) source;
			var left = place (exchange.left);
			var right = place (exchange.right);
			int old_left = read (left);
			int old_right = read (right);
			write (left, old_right);
			write (right, old_left);
		} else {
			unsupported_node ("CFG instruction requires its exact lifetime operation: " + source.get_type ().name ());
		}
	}

	private void inventory(GenericArray<CfgBlock> blocks) throws RuntimeLifetimeError {
		for (int i = 0; i < function.locals.length + function.temporaries.length; i++) {
			slots.add (i);
		}
		next_slot = (int) (function.locals.length + function.temporaries.length);
		foreach (var block in blocks) {
			foreach (var source in block.instructions) {
				if (source is CfgEvaluateInstruction) {
					var evaluation = (CfgEvaluateInstruction) source;
					define_value (evaluation.result, block, evaluation.value, source is CfgResourceCapture || source is CfgExceptionTake);
					var factory = evaluation.value as CfgScopedAllocator;
					if (factory != null) {
						if (factory.loan.context_ordinal < 0 || factory.loan.context_ordinal >= function.locals.length) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG scoped context ordinal is absent");
						}
						var local = function.locals[factory.loan.context_ordinal];
						contexts.insert (local, factory);
						regions.context (local.ordinal, region_id (local.text_extent));
					}
				} else if (source is CfgTaskMove) {
					define_value (((CfgTaskMove) source).result, block, null, true);
				} else if (source is CfgTaskBorrow) {
					define_value (((CfgTaskBorrow) source).result, block);
				} else if (source is CfgTaskWait) {
					define_value (((CfgTaskWait) source).exception, block);
				} else if (source is CfgAsyncDelay) {
					define_value (((CfgAsyncDelay) source).exception, block);
				} else if (source is CfgAsyncOperation) {
					var operation = (CfgAsyncOperation) source;
					if (operation.result != null) {
						define_value (operation.result, block);
					}
					if (operation.exception != null) {
						define_value (operation.exception, block);
					}
				} else if (source is CfgTaskSuccess) {
					var success = (CfgTaskSuccess) source;
					if (success.result != null) {
						define_value (success.result, block, null, graph_input (success.success_type));
					} else if (success.struct_result != null) {
						task_record (success, block);
					}
				} else if (source is CfgCallInstruction) {
					var call = (CfgCallInstruction) source;
					record_call (call, block);
					if (call.result != null) {
						define_value (call.result, block, null, call is CfgTaskCreate);
					}
					if (call.exception_result != null) {
						define_value (call.exception_result, block);
					}
				} else if (source is CfgCCallInstruction && ((CfgCCallInstruction) source).result != null) {
					define_value (((CfgCCallInstruction) source).result, block);
				} else if (source is CfgOwnedArgumentCapture) {
					define_value (((CfgOwnedArgumentCapture) source).transfer, block, null, true);
				} else if (source is CfgOwnershipReturnInstruction) {
					define_value (((CfgOwnershipReturnInstruction) source).result, block, null, true);
				} else if (source is CfgOwnedBorrowInstruction) {
					define_value (((CfgOwnedBorrowInstruction) source).result, block);
				} else if (source is CfgStructBoundaryMove && ((CfgStructBoundaryMove) source).use_kind == StructResultUseKind.ARGUMENT) {
					foreach (var leaf in ((CfgStructBoundaryMove) source).leaves) {
						if (graph_input (leaf.semantic_type) && !captures.contains (leaf)) {
							captures.insert (leaf, slot ());
						}
					}
				} else if (source is CfgBufferAllocate) {
					var results = ((CfgBufferAllocate) source).results;
					define_value (results.owner, block, null, true);
					define_value (results.base_value, block);
					define_value (results.length_value, block);
				}
				var construction = source as CfgLifecycleCallInstruction;
				if (construction != null && construction.constructs && construction.storage.object_class.allocation_policy != null && construction.storage.object_class.allocation_policy.context_mode == "scoped-affine") {
					scoped_allocation = true;
				}
			}
		}
		foreach (var block in blocks) {
			foreach (var source in block.instructions) {
				var initialized = source as CfgInitialize;
				var caught = initialized == null ? null : initialized.value as CfgCatchBorrow;
				var local = initialized == null ? null : initialized.target as CfgLocalPlace;
				if (caught == null) {
					continue;
				}
				var loaded = origin (caught.exception) as CfgLoadValue;
				var owner = loaded == null ? null : loaded.source as CfgExceptionStorage;
				if (local == null || owner == null || catch_aliases.contains (local)) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG catch alias requires one exact private exception owner");
				}
				catch_aliases.insert (local, new CfgRuntimeCatchAlias ((int) function.locals.length + owner.ordinal, source, caught.exception));
			}
		}
		foreach (var block in blocks) {
			foreach (var source in block.instructions) {
				var initialized = source as CfgInitialize;
				var local = initialized == null ? null : initialized.target as CfgLocalPlace;
				var reference = initialized == null ? null : origin (initialized.value) as CfgObjectReferenceValue;
				if (local != null && reference != null) {
					object_targets.insert (reference.storage, local);
				}
			}
		}
		foreach (var storage in function.object_storage) {
			var target = object_targets.lookup (storage);
			if (target == null) {
				object_slots.insert (storage, slot ());
			} else {
				if (target.text_extent == null || target.text_extent.ordinal != storage.region_ordinal || storage.heap_allocated && storage.cleanup_rank != target.ordinal) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG object lifetime differs from actual cleanup scope/rank");
				}
				object_slots.insert (storage, storage.transferable ? slot () : target.ordinal);
			}
		}
	}

	// Catch locals borrow the private error slot. They do not create another
	// owner; physical cleanup/store paths must not invalidate a live borrow.
	private bool invalidated_borrow(CfgBlock start, int after, Object use, CfgRuntimeCatchAlias alias) {
		var pending = new GenericArray<CfgBlock> ();
		var seen = new HashTable<CfgBlock, bool> (direct_hash, direct_equal);
		pending.add (start);
		for (int n = 0; n < pending.length; n++) {
			var block = pending[n];
			int first = n == 0 ? after : 0;
			if (n != 0) {
				if (seen.contains (block)) {
					continue;
				}
				seen.insert (block, true);
			}
			bool fresh = false;
			for (int i = first; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				if (instruction == use) {
					return true;
				}
				var captured = instruction as CfgEvaluateInstruction;
				if (captured != null && captured.result == alias.captured) {
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

	private void verify_catch_aliases(GenericArray<CfgBlock> blocks) throws RuntimeLifetimeError {
		foreach (var alias in catch_aliases.get_values ()) {
			alias.uses.add (alias.initialized);
			foreach (var block in blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					CfgPlace? target = null;
					if (instruction is CfgCleanupInstruction) {
						var loaded = origin (((CfgCleanupInstruction) instruction).value) as CfgLoadValue;
						if (loaded != null) {
							target = loaded.source;
						}
					} else if (instruction is CfgStore) {
						target = ((CfgStore) instruction).target;
					} else if (instruction is CfgInitialize) {
						target = ((CfgInitialize) instruction).target;
					}
					var owner = target as CfgExceptionStorage;
					if (owner == null || (int) function.locals.length + owner.ordinal != alias.owner) {
						continue;
					}
					foreach (var use in alias.uses) {
						if (invalidated_borrow (block, i + 1, use, alias)) {
							throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG catch borrow outlives its exact private exception owner");
						}
					}
				}
			}
		}
	}

	private void exit() throws RuntimeLifetimeError {
		exit_count++;
		foreach (int binding in exits.get_keys ()) {
			graph.alternative (exits.lookup (binding), state.bindings.lookup (binding));
		}
	}

	// The checked constructor ABI unwinds initialized fields and retires its
	// unpublished backing before exposing the error. Only that exact error
	// edge loses the candidate; the success edge still has to publish it.
	private RuntimeLifetimeState edge_state(CfgBlock block, CfgBlock next) throws RuntimeLifetimeError {
		var result = outputs.lookup (block).snapshot ();
		bool checked = false;
		foreach (var instruction in block.instructions) {
			var call = instruction as CfgLifecycleCallInstruction;
			if (call == null || !call.constructs || call.target.throws_type == null) {
				continue;
			}
			var policy = call.storage.object_class.allocation_policy;
			if (policy == null || !policy.checked_initialization ()) {
				continue;
			}
			if (checked) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked constructor rollback requires one exact invocation before its exception test");
			}
			checked = true;
			var branch = block.terminator as CfgConditionalBranch;
			var condition = branch == null ? null : branch.condition as CfgBinaryValue;
			var receiver = call.receiver as CfgStorageReceiverValue;
			if (call.exception_result == null || condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != call.exception_result || !(condition.right is CfgNullPointerValue) || branch.true_target == branch.false_target || block.instructions[block.instructions.length - 1] != call || receiver == null || receiver.storage != call.storage || !function.object_storage.find (call.storage) || call.storage.object_class.constructor != call.target) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG checked constructor rollback requires its exact candidate and original success/error test");
			}
			if (next == branch.false_target) {
				result.bindings.insert (object_slots.lookup (call.storage), graph.absent ());
			}
		}
		return result;
	}

	internal RuntimeLifetimeSummary incomplete(string reason) {
		graph.seal ();
		return new RuntimeLifetimeSummary (graph, graph.absent (), new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), reason);
	}

	internal RuntimeLifetimeSummary analyze() throws RuntimeLifetimeError, CfgError {
		record_parameters ();
		var predecessors = CfgPredecessors.analyze (function);
		var blocks = predecessors.blocks ();
		inventory (blocks);
		returned = graph.join ();
		exceptional_result = graph.join ();
		graph.alternative (exceptional_result, graph.absent ());
		var initial = new RuntimeLifetimeState ();
		foreach (var parameter in function.parameters) {
			bool allocator = parameter.semantic_type.is_scoped_allocator ();
			bool owning = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || record_parameter_owned (parameter.ordinal);
			if (allocator || owning || graph_input (parameter.semantic_type)) {
				regions.input (parameter.ordinal, allocator);
			}
			int incoming = allocator || !owning && !graph_input (parameter.semantic_type) ? graph.absent () : graph.input (parameter.ordinal);
			int binding = parameter_binding (parameter.ordinal);
			slots.add (binding);
			initial.bindings.insert (binding, incoming);
			if (!owning && graph_input (parameter.semantic_type)) {
				initial_inputs.insert (binding, incoming);
				exits.insert (binding, graph.join ());
			}
		}
		if (function.implicit_receiver != null) {
			regions.input (-1);
			slots.add (-1);
			int incoming = graph.input (-1);
			initial.bindings.insert (-1, incoming);
			initial_inputs.insert (-1, incoming);
			exits.insert (-1, graph.join ());
		}
		foreach (var local in function.locals) {
			if (graph_input (local.semantic_type) || local.semantic_type is SliceType || local.semantic_type.is_scoped_allocator ()) {
				regions.owner (local.ordinal, region_id (local.text_extent));
			}
			initial.bindings.insert (local.ordinal, local.semantic_type.is_struct_storage () ? product (local.semantic_type) : graph.absent ());
		}
		for (int i = (int) function.locals.length; i < next_slot; i++) {
			initial.bindings.insert (i, graph.absent ());
		}
		regions.seal ();
		if (function.struct_result != null) {
			record_shape (function.struct_result);
			if (function.struct_result.semantic_type != function.return_type) {
				throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result differs from its declared return type");
			}
		}
		foreach (var block in blocks) {
			var entry = new RuntimeLifetimeState ();
			for (int i = 0; i < slots.length; i++) {
				entry.bindings.insert (slots[i], graph.join ());
			}
			entries.insert (block, entry);
		}
		var first = entries.lookup (function.entry);
		for (int i = 0; i < slots.length; i++) {
			graph.alternative (first.bindings.lookup (slots[i]), initial.bindings.lookup (slots[i]));
		}
		foreach (var block in blocks) {
			current_block = block;
			state = entries.lookup (block).snapshot ();
			foreach (var source in block.instructions) {
				instruction (source);
			}
			current_site = block.terminator;
			if (block.terminator is CfgExceptionReturn) {
				if (function.throws_type == null && function.async_body == null) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG exceptional result escapes a nonthrowing signature");
				}
				graph.alternative (exceptional_result, value (((CfgExceptionReturn) block.terminator).value));
				exit ();
			} else if (block.terminator is CfgStructReturn) {
				normal_exits++;
				graph.alternative (returned, record_return ((CfgStructReturn) block.terminator));
				exit ();
			} else if (block.terminator is CfgReturn) {
				if (function.struct_result != null) {
					throw new RuntimeLifetimeError.INVALID_GRAPH ("CFG record result lost its complete return publication");
				}
				normal_exits++;
				int result = value (((CfgReturn) block.terminator).value);
				graph.alternative (returned, graph_input (function.return_type) || function.owned_cleanup != null ? result : graph.absent ());
				exit ();
			} else if (block.terminator is CfgFunctionEnd) {
				normal_exits++;
				graph.alternative (returned, graph.absent ());
				exit ();
			} else if (block.terminator is CfgConditionalBranch) {
				value (((CfgConditionalBranch) block.terminator).condition);
			} else if (block.terminator is CfgExceptionUnreachable) {
				value (((CfgExceptionUnreachable) block.terminator).exception);
			} else if (block.terminator is CfgEnumDispatch) {
				empty_enum (((CfgEnumDispatch) block.terminator).source);
			} else if (!(block.terminator is CfgBranch) && !(block.terminator is CfgEnumInvalidTag)) {
				unsupported_node ("CFG terminator requires exact lifetime effects");
			}
			outputs.insert (block, state);
		}
		foreach (var block in blocks) {
			foreach (var next in block.terminator.successors ()) {
				var target = entries.lookup (next);
				var source = edge_state (block, next);
				for (int i = 0; i < slots.length; i++) {
					graph.alternative (target.bindings.lookup (slots[i]), source.bindings.lookup (slots[i]));
				}
			}
		}
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
			foreach (var parameter in function.parameters) {
				bool owning = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || record_parameter_owned (parameter.ordinal);
				captures.insert ("f%d".printf (parameter.ordinal), graph_input (parameter.semantic_type) || owning ? graph.input (parameter.ordinal) : graph.absent ());
			}
			var fields = new HashTable<string, int> (str_hash, str_equal);
			fields.insert ("f0", returned);
			fields.insert ("f1", exceptional_result);
			fields.insert ("f2", graph.product (new GenericArray<RuntimeScopeOrigin> (), captures));
			factory_result = graph.product (new GenericArray<RuntimeScopeOrigin> (), fields);
		}
		graph.seal ();
		verify_catch_aliases (blocks);
		if (unsupported != "") {
			return new RuntimeLifetimeSummary (graph, returned, new HashTable<int, int> (direct_hash, direct_equal), stores, unsupported);
		}
		foreach (var bound in bounds) {
			if (graph.requirements (bound.value).length != 0) {
				regions.validate (graph, bound.value, bound.destination);
			}
		}
		foreach (var origin in graph.requirements (returned)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("CFG result retains a scoped local allocation");
			}
		}
		foreach (var origin in graph.requirements (exceptional_result)) {
			if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT) {
				throw new RuntimeLifetimeError.LOCAL_ESCAPE ("CFG exception retains a scoped local allocation");
			}
		}
		if (contexts.size () != 0) {
			var flow = OwnershipFlow.analyze (function);
			if (flow.diagnostic != null) {
				throw new RuntimeLifetimeError.INVALID_GRAPH (flow.diagnostic.message);
			}
			foreach (var use in context_uses) {
				var live = flow.scoped_state_before (use.instruction, use.context);
				if (live == null || !live.definitely_owned ()) {
					throw new RuntimeLifetimeError.LOCAL_ESCAPE ("CFG scoped allocation uses a context outside its actual live obligation");
				}
			}
		}
		foreach (var ended in context_ends) {
			for (int i = 0; i < ended.values.length; i++) {
				foreach (var origin in graph.requirements (ended.values[i])) {
					if (origin.kind == RuntimeScopeOriginKind.LOCAL_CONTEXT && origin.ordinal == ended.context) {
						throw new RuntimeLifetimeError.LOCAL_ESCAPE ("CFG context retires before a derived owner or pending handoff at binding %d in %s", ended.bindings[i], function.name);
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
					throw new RuntimeLifetimeError.LOCAL_ESCAPE ("CFG input storage retains a scoped local allocation");
				}
			}
		}
		if (borrowed > 1 && stores.length != 0) {
			unsupported_node ("CFG mutable borrowed aliases require exact effects");
		}
		if (function.async_body != null) {
			if (updates.size () != 0 || stores.length != 0) {
				unsupported_node ("CFG async factory needs deferred borrowed-storage effects");
			}
			return new RuntimeLifetimeSummary (graph, factory_result, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), unsupported);
		}
		return new RuntimeLifetimeSummary (graph, returned, updates, stores, unsupported, function.throws_type == null ? -1 : exceptional_result);
	}

}
}
