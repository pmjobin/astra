// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
// Declaration-only facts may outlive every compiler stage. No symbol, body,
// field graph or predecessor IR object is retained here.
public class NativeDeclarationIdentity : Object {
	private string module_identifier;
	private string callable_key;
	private string external_identifier;
	private string expected_shape;
	private string receiver_record_field;
	public bool scoped_readonly { get; private set; }
	private string lifetime_text;
	private int declared_task_inventory;
	public int task_inventory { get { return declared_task_inventory; } }
	public string lifetime_contract { get { return lifetime_text; } }
	private string readonly_input_text;
	private string callback_input_text;
	public string readonly_inputs { get { return readonly_input_text; } }
	public string callback_inputs { get { return callback_input_text; } }
	public string module_identity { get { return module_identifier; } }
	public string key { get { return callable_key; } }
	public string symbol { get { return external_identifier; } }
	public string signature_shape { get { return expected_shape; } }
	public string record_field { get { return receiver_record_field; } }

	internal NativeDeclarationIdentity (string module_identity, string key, string symbol, string signature_shape, string record_field = "", bool scoped_readonly = false, string readonly_inputs = "", string callback_inputs = "", string lifetime_contract = "", int task_inventory = -1) {
		module_identifier = module_identity;
		callable_key = key;
		external_identifier = symbol;
		expected_shape = signature_shape;
		receiver_record_field = record_field;
		this.scoped_readonly = scoped_readonly;
		readonly_input_text = readonly_inputs;
		callback_input_text = callback_inputs;
		lifetime_text = lifetime_contract;
		declared_task_inventory = task_inventory;
	}

}

public class NativeLifetimeLayout : Object {
	public static Astra.Source.RuntimeLifetimeLayout build(int parameters, GenericArray<StructBoundaryGroup> records, GenericArray<int>? buffer_positions = null, GenericArray<int>? buffer_ordinals = null) throws Astra.Source.RuntimeLifetimeError {
		var logical = new GenericArray<int> ();
		var paths = new GenericArray<string> ();
		var lengths = new GenericArray<bool> ();
		int physical = 0;
		int count = 0;
		while (physical < parameters) {
			StructBoundaryGroup? record = null;
			foreach (var candidate in records) {
				if (candidate.first_leaf == physical) {
					if (record != null) {
						throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout repeats a record parameter");
					}
					record = candidate;
				}
			}
			if (record != null) {
				if (record.source_ordinal != count || record.shape.leaves.length == 0 || physical + record.shape.leaves.length > parameters) {
					throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout lost its exact logical record parameter");
				}
				foreach (var leaf in record.shape.leaves) {
					var text = new StringBuilder ();
					for (int d = 0; d < leaf.depth; d++) {
						if (d != 0) {
							text.append_c ('.');
						}
						text.append_printf ("f%d", leaf.field_ordinal (d));
					}
					var buffer = leaf as StructBufferLeafPath;
					logical.add (count);
					paths.add (text.str);
					lengths.add (buffer != null && buffer.component == 1);
					physical++;
				}
			} else {
				bool buffer = false;
				if (buffer_positions != null && buffer_ordinals != null) {
					if (buffer_positions.length != buffer_ordinals.length) {
						throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout lost its buffer group inventory");
					}
					for (int b = 0; b < buffer_positions.length; b++) {
						if (buffer_positions[b] != physical) {
							continue;
						}
						if (buffer || buffer_ordinals[b] != count || physical + 1 >= parameters) {
							throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native lifetime layout lost its exact logical buffer parameter");
						}
						buffer = true;
					}
				}
				logical.add (count);
				paths.add ("");
				lengths.add (false);
				physical++;
				if (buffer) {
					logical.add (count);
					paths.add ("");
					lengths.add (true);
					physical++;
				}
			} count++;
		}
		return new Astra.Source.RuntimeLifetimeLayout (logical, paths, lengths, count);
	}

}

public class NativeDeclarationSignature : Object {
	public NativeDeclarationIdentity identity { get; private set; }
	private SemanticType result_type;
	private ResultOwnershipContract result_contract;
	private bool heap_result;
	private bool nonnull_result;
	private SemanticType? receiver_type;
	private ClassType? error_type;
	private GenericArray<SemanticType> parameters = new GenericArray<SemanticType> ();
	private GenericArray<PointerParameterContract> contracts = new GenericArray<PointerParameterContract> ();
	private bool[] heap_parameters;
	private bool[] nonnull_parameters;
	private int[] record_modes;
	private int result_record_mode;
	private NativeDeclarationSignature? logical_signature;
	private bool async_callable;
	private Astra.Source.AsyncProviderKind async_provider;
	private ClassType? runtime_error;

	internal NativeDeclarationSignature (NativeDeclarationIdentity identity, SemanticType result,
	                                     ResultOwnershipContract result_contract, bool heap_result, bool nonnull_result,
	                                     SemanticType? receiver, ClassType? error, GenericArray<SemanticType> parameters,
	                                     GenericArray<PointerParameterContract> contracts, bool[] heap_parameters, bool[] nonnull_parameters,
	                                     int[]? record_modes = null, int result_record_mode = -1, NativeDeclarationSignature? logical_signature = null,
	                                     AsyncBodyContract? async_body = null) {
		this.identity = identity;
		result_type = result;
		this.result_contract = result_contract;
		this.heap_result = heap_result;
		this.nonnull_result = nonnull_result;
		receiver_type = receiver;
		error_type = error;
		foreach (var parameter in parameters) {
			this.parameters.add (parameter);
		}
		for (int p = 0; p < contracts.length; p++) {
			this.contracts.add (contracts[p]);
		}
		this.heap_parameters = heap_parameters.copy ();
		this.nonnull_parameters = nonnull_parameters.copy ();
		this.record_modes = record_modes == null ? new int[parameters.length] : record_modes.copy ();
		if (record_modes == null) {
			for (int p = 0; p < parameters.length; p++) {
				this.record_modes[p] = -1;
			}
		}
		this.result_record_mode = result_record_mode;
		this.logical_signature = logical_signature;
		async_callable = async_body != null;
		if (async_body != null) {
			async_provider = async_body.runtime.provider;
			runtime_error = async_body.runtime.error_type;
		}
	}

	public bool matches_async(AsyncBodyContract? body) {
		var original = logical_signature ?? this;
		return original.async_callable == (body != null) && (body == null ||
			original.async_provider == body.runtime.provider && same_type (original.runtime_error, body.runtime.error_type) &&
			same_type (original.result_type, body.success_type) && original.result_contract == body.success_mode &&
			same_type (original.error_type, body.exception_bound));
	}

	public Astra.Source.RuntimeLifetimeSummary? runtime_lifetime_summary () throws Astra.Source.RuntimeLifetimeError {
		var logical = logical_signature ?? this;
		if (identity.task_inventory >= 0 && identity.task_inventory != (logical.async_callable ? 1 : 0)) {
			throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native task declaration/metadata inventory mismatch");
		}
		if (identity.lifetime_contract == "") {
			return null;
		}
		var summary = Astra.Source.RuntimeLifetimeSummary.decode (identity.lifetime_contract);
		if (logical.parameters.length != logical.contracts.length) {
			throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native lifetime contract lost its exact formal inventory");
		}
		bool[] owners = new bool[logical.parameters.length];
		bool[] contexts = new bool[logical.parameters.length];
		bool[] mutable_owners = new bool[logical.parameters.length];
		for (int i = 0; i < logical.parameters.length; i++) {
			var type = logical.parameters[i];
			var contract = logical.contracts[i];
			bool owning = contract == PointerParameterContract.OWNED_TRANSFER;
			bool graph = !(type is HandleType && ((HandleType) type).context_mode != "") && (type is ClassType || type is ReceiverType || type is HandleType || type.is_struct_storage () || type is TaskType);
			contexts[i] = type.is_scoped_allocator ();
			owners[i] = !contexts[i] && (owning || graph);
			mutable_owners[i] = !contexts[i] && !owning && graph;
			if (contexts[i] && contract != PointerParameterContract.BORROWED_NOESCAPE) {
				throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native scoped context requires its exact borrowed formal");
			}
		}
		if (summary.complete && !summary.logical_coordinates) {
			for (int p = 0; p < logical.parameters.length; p++) {
				if (logical.record_modes[p] >= 0 || logical.parameters[p] is SliceType && logical.contracts[p] == PointerParameterContract.OWNED_TRANSFER) {
					throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native composite lifetime coordinates require rebuild with runtime-lifetime-logical/1");
				}
			}
		}
		summary.validate_formals (logical.receiver_type != null, owners, contexts, mutable_owners);
		if (!summary.matches_exception (!logical.async_callable && logical.error_type != null)) {
			throw new Astra.Source.RuntimeLifetimeError.INVALID_GRAPH ("native lifetime exception channel differs from its exact throws signature");
		}
		return summary;
	}

	private static bool same_type(SemanticType? left, SemanticType? right) {
		return left == null ? right == null : right != null && left.logical_identity == right.logical_identity;
	}

	public bool same_signature(NativeDeclarationSignature other) {
		var left = logical_signature ?? this;
		var right = other.logical_signature ?? other;
		bool same_async = left.async_callable == right.async_callable && (!left.async_callable ||
			left.async_provider == right.async_provider && same_type (left.runtime_error, right.runtime_error));
		return same_async && identity == other.identity && matches_logical_records (other.record_modes, other.result_record_mode) && matches (other.result_type, other.result_contract,
			other.heap_result, other.nonnull_result, other.receiver_type, other.error_type,
			other.parameters, other.contracts, other.heap_parameters, other.nonnull_parameters);
	}

	public bool matches_logical_records(int[] modes, int result_mode) {
		if (record_modes.length != modes.length || result_record_mode != result_mode) {
			return false;
		}
		for (int p = 0; p < modes.length; p++) {
			if (record_modes[p] != modes[p]) {
				return false;
			}
		}
		return true;
	}

	public NativeDeclarationSignature lowered(SemanticType result, ResultOwnershipContract result_contract,
		bool heap_result, bool nonnull_result, SemanticType? receiver, ClassType? error,
		GenericArray<SemanticType> parameters, GenericArray<PointerParameterContract> contracts,
		bool[] heap_parameters, bool[] nonnull_parameters) {
		return new NativeDeclarationSignature (identity, result, result_contract, heap_result, nonnull_result,
			receiver, error, parameters, contracts, heap_parameters, nonnull_parameters, null, -1, logical_signature ?? this);
	}

	public bool matches_records(GenericArray<StructBoundaryGroup> groups, StructValueShape? result) {
		var logical = logical_signature ?? this;
		if (logical.record_modes.length != logical.parameters.length) {
			return false;
		}
		int next = 0;
		for (int p = 0; p < logical.parameters.length; p++) {
			if (logical.record_modes[p] < 0) {
				continue;
			}
			if (next >= groups.length) {
				return false;
			}
			var group = groups[next++];
			if (group.source_ordinal != p || !same_type (group.shape.semantic_type, logical.parameters[p]) || (int) group.shape.mode != logical.record_modes[p]) {
				return false;
			}
		}
		if (next != groups.length) {
			return false;
		}
		return logical.result_record_mode < 0 ? result == null : result != null && same_type (result.semantic_type, logical.result_type) && (int) result.mode == logical.result_record_mode;
	}

	public bool matches_buffers(GenericArray<int> ordinals, GenericArray<SemanticType> types) {
		var logical = logical_signature ?? this;
		if (ordinals.length != types.length) {
			return false;
		}
		int next = 0;
		for (int p = 0; p < logical.parameters.length; p++) {
			if (!(logical.parameters[p] is SliceType) || logical.contracts[p] != PointerParameterContract.OWNED_TRANSFER) {
				continue;
			}
			if (next >= ordinals.length || ordinals[next] != p || !same_type (types[next], logical.parameters[p])) {
				return false;
			}
			next++;
		}
		return next == ordinals.length;
	}

	public bool matches(SemanticType result, ResultOwnershipContract result_contract,
		bool heap_result, bool nonnull_result, SemanticType? receiver, ClassType? error,
		GenericArray<SemanticType> parameters, GenericArray<PointerParameterContract> contracts,
		bool[] heap_parameters, bool[] nonnull_parameters) {
		if (!same_type (result_type, result) || this.result_contract != result_contract ||
		    this.heap_result != heap_result || this.nonnull_result != nonnull_result ||
		    !same_type (receiver_type, receiver) || !same_type (error_type, error) ||
		    this.parameters.length != parameters.length || this.contracts.length != parameters.length ||
		    contracts.length != parameters.length || this.heap_parameters.length != parameters.length ||
		    heap_parameters.length != parameters.length || this.nonnull_parameters.length != parameters.length ||
		    nonnull_parameters.length != parameters.length) {
			return false;
		}
		for (int p = 0; p < parameters.length; p++) {
			if (!same_type (this.parameters[p], parameters[p]) || this.contracts[p] != contracts[p] ||
			    this.heap_parameters[p] != heap_parameters[p] || this.nonnull_parameters[p] != nonnull_parameters[p]) {
				return false;
			}
		}
		return true;
	}

}
}
