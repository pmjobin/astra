// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.NativeAbi {
// Declaration-only task facts survive without a producer body or frame graph.
public class NativeAsyncCallablePlan : Object {
	public bool composable { get; private set; }
	public Astra.Source.AsyncProviderKind provider { get; private set; }
	private string runtime_error_identifier;
	private string success_identifier;
	public string runtime_error { get { return runtime_error_identifier; } }
	public string success_name { get { return success_identifier; } }
	public bool imported { get; private set; }
	public int success_mode { get; private set; }
	private string signature_origin;
	internal NativeAsyncCallablePlan (Astra.Source.AsyncProviderKind provider, string runtime_error,
	                                  string success_name, int success_mode, NativeSignature signature, bool imported = false, bool composable = false) {
		this.composable = composable;
		this.imported = imported;
		this.provider = provider;
		runtime_error_identifier = runtime_error;
		success_identifier = success_name;
		this.success_mode = success_mode;
		signature_origin = channels (signature);
	}
	private static string channels(NativeSignature signature) {
		var text = new StringBuilder ();
		text.append_printf ("receiver=%s;result=%s;", signature.receiver == null ? "none" : signature.receiver.spelling (),
			signature.result == null ? "void" : signature.result.abi_type.spelling ());
		if (signature.exception_plan != null) {
			text.append ("bound=" + signature.exception_plan.bound_name + ";root=" + signature.exception_plan.root_name + ";");
		}
		foreach (var parameter in signature.parameters) {
			text.append_printf ("parameter=%d:%s;borrowed-class=%d;", parameter.ordinal,
				parameter.abi_type.spelling (), parameter.borrowed_class_ordinal);
			if (parameter.object_origin != null) {
				text.append_printf ("Class=%s:%d;", parameter.object_origin.class_name, parameter.object_origin.heap ? 1 : 0);
			}
			if (parameter.resource != null) {
				text.append_printf ("Resource=%s:%s:%d;", parameter.resource.type_name,
					parameter.resource.cleanup_symbol, parameter.owns_resource ? 1 : 0);
			}
		}
		foreach (var group in signature.struct_parameters) {
			text.append_printf ("record=%d:%d:%s:%d;", group.source_ordinal, group.first_leaf,
				group.value_plan.struct_name, (int) group.mode);
			foreach (var leaf in group.value_plan.leaves) {
				text.append (leaf.field_path + ":" + leaf.abi_type.spelling () + ";");
			}
		}
		if (signature.struct_result != null) {
			text.append_printf ("record-result=%s:%d;", signature.struct_result.struct_name, (int) signature.struct_result_mode);
			foreach (var leaf in signature.struct_result.leaves) {
				text.append (leaf.field_path + ":" + leaf.abi_type.spelling () + ";");
			}
		}
		if (signature.buffer_result != null) {
			text.append ("buffer-result=" + signature.buffer_result.element_spelling () + ";");
		}
		foreach (var buffer in signature.buffer_parameters) {
			if (buffer.value_plan.context_origin != null) {
				text.append_printf ("context-buffer=%d:%d:%s;", buffer.source_ordinal, buffer.first_leaf, buffer.value_plan.element_spelling ());
			}
		}
		if (signature.sum_result != null) {
			text.append ("sum-result=" + signature.sum_result.spelling () + ";");
		}
		return text.str;
	}
	public string contract() {
		return "native-tasks-v17;task-abi=17;provider=%d;runtime-error=%s;success=%s;mode=%d;cold-factory=fastcc:parent,frame-descriptor,frame-context;checked-factory=nullable-unpublished/1;provider-admission=exact;resume=ccc:void(ptr);destroy=ccc:void(ptr,i32);complete=5;error=6;cancelled=7;retire=descendants-and-provider-users;".printf ((int) provider, runtime_error, success_name, success_mode) + (composable ? "bridge=worker-submit-observe/1;" : "");
	}
	public bool matches(NativeSignature signature) {
		foreach (var parameter in signature.parameters) {
			if (parameter.abi_type is NativeSharedHandleType) {
				return false;
			}
			var closure = parameter.abi_type as NativeClosureHandleType;
			if (closure != null && (provider == Astra.Source.AsyncProviderKind.POSIX_THREADED || closure.actor || closure.threaded)) {
				return false;
			}
		}
		return provider >= Astra.Source.AsyncProviderKind.VIRTUAL && provider <= Astra.Source.AsyncProviderKind.POSIX_THREADED &&
		       runtime_error != "" && success_name != "" && signature.receiver == null && signature_origin == channels (signature);
	}
}
public class NativeTaskHandleType : NativeAbiType {
	public Astra.Source.TaskContractIdentity identity { get; private set; }
	public NativeAbiType? success { get; private set; }
	public bool owns_success { get; private set; }
	internal NativeTaskHandleType (Astra.Source.TaskContractIdentity identity, NativeAbiType? success, bool owns_success) {
		this.identity = identity;
		this.success = success;
		this.owns_success = owns_success;
	}
	public override string spelling() {
		return "UNIQUE_TASK(%s%s)".printf (owns_success ? "owned " : "", success == null ? "void" : success.spelling ());
	}
	public override bool same_type(NativeAbiType other) {
		return other is NativeTaskHandleType && ((NativeTaskHandleType) other).identity == identity && ((NativeTaskHandleType) other).owns_success == owns_success && ((((NativeTaskHandleType) other).success == null) == (success == null)) && (success == null || success.same_type (((NativeTaskHandleType) other).success));
	}
}
// Logical record success identity. Its concrete leaf carrier belongs to the
// frame/result plan, never to an ordinary scalar parameter ABI.
public class NativeTaskRecordSuccessType : NativeAbiType {
	public Astra.Source.TaskContractIdentity identity { get; private set; }
	private string identifier;
	internal NativeTaskRecordSuccessType (Astra.Source.TaskContractIdentity identity, string name) {
		this.identity = identity;
		identifier = name;
	}
	public override string spelling() {
		return "TASK_RECORD(" + identifier + ")";
	}
	public override bool same_type(NativeAbiType other) {
		var record = other as NativeTaskRecordSuccessType;
		return record != null && record.identity == identity && record.identifier == identifier;
	}
}
public enum NativeTaskCapability {
	NATIVE_TASKS_V15
}
// One detached observation right binds its producer, continuation and full
// success group. The source contract remains independent of emitted operands.
public class NativeAsyncWait : Object {
	public int bridge_definition { get; private set; }
	public int bridge_owner { get; private set; }
	public Astra.Source.AsyncProviderKind target_provider { get; private set; }
	public bool composed { get; private set; }
	public int block { get; private set; }
	public int position { get; private set; }
	public int child_definition { get; private set; }
	public int exception_definition { get; private set; }
	public bool discard { get; private set; }
	public Astra.Source.TaskContractIdentity identity { get; private set; }
	public int enum_ordinal { get; private set; }
	public Astra.Source.EnumInstanceIdentity? enum_instance { get; private set; }
	private int[] leaves;
	public uint leaf_count { get { return leaves.length; } }
	public int leaf(uint ordinal) {
		return leaves[ordinal];
	}
	internal NativeAsyncWait (int block, int position, int child_definition, int exception_definition, bool discard, Astra.Source.TaskContractIdentity identity, GenericArray<int> leaves, int enum_ordinal = -1, Astra.Source.EnumInstanceIdentity? enum_instance = null, int bridge_definition = -1, int bridge_owner = -1, Astra.Source.AsyncProviderKind target_provider = Astra.Source.AsyncProviderKind.VIRTUAL, bool composed = false) {
		this.bridge_definition = bridge_definition;
		this.bridge_owner = bridge_owner;
		this.target_provider = target_provider;
		this.composed = composed;
		this.block = block;
		this.position = position;
		this.child_definition = child_definition;
		this.exception_definition = exception_definition;
		this.discard = discard;
		this.identity = identity;
		this.enum_ordinal = enum_ordinal;
		this.enum_instance = enum_instance;
		this.leaves = new int[leaves.length];
		for (int l = 0; l < leaves.length; l++) {
			this.leaves[l] = leaves[l];
		}
	}
}
public class NativeAsyncLoan : Object {
	public Astra.Source.SuspensionLoanIdentity identity { get; private set; }
	public int block { get; private set; }
	public int creation_position { get; private set; }
	public int wait_position { get; private set; }
	public int child_definition { get; private set; }
	public int child_body { get; private set; }
	public int parameter_ordinal { get; private set; }
	public int view_definition { get; private set; }
	public int storage_ordinal { get; private set; }
	internal NativeAsyncLoan (Astra.Source.SuspensionLoanIdentity identity, int block, int creation_position, int wait_position, int child_definition, int child_body, int parameter_ordinal, int view_definition, int storage_ordinal) {
		this.identity = identity;
		this.block = block;
		this.creation_position = creation_position;
		this.wait_position = wait_position;
		this.child_definition = child_definition;
		this.child_body = child_body;
		this.parameter_ordinal = parameter_ordinal;
		this.view_definition = view_definition;
		this.storage_ordinal = storage_ordinal;
	}
}
public class NativeAsyncEnumStorage : Object {
	public int cleanup_position { get; private set; }
	public int ordinal { get; private set; }
	public int source_ordinal { get; private set; }
	public int capture_first_leaf { get; private set; }
	public int inspection_root { get; private set; }
	public int reservation_source { get; private set; }
	public Astra.Source.EnumIdentity identity { get; private set; }
	public Astra.Source.EnumInstanceIdentity instance { get; private set; }
	public bool owning { get; private set; }
	internal NativeAsyncEnumStorage (int ordinal, int source_ordinal, int capture_first_leaf, int inspection_root, int reservation_source, Astra.Source.EnumIdentity identity, Astra.Source.EnumInstanceIdentity instance, bool owning, int cleanup_position = -1) {
		this.cleanup_position = cleanup_position;
		this.ordinal = ordinal;
		this.source_ordinal = source_ordinal;
		this.capture_first_leaf = capture_first_leaf;
		this.inspection_root = inspection_root;
		this.reservation_source = reservation_source;
		this.identity = identity;
		this.instance = instance;
		this.owning = owning;
	}
}
public class NativeAsyncStorage : Object {
	public int ordinal { get; private set; }
	public int source_ordinal { get; private set; }
	public int array_count { get; private set; }
	public NativeAbiType? leaf { get; private set; }
	public NativeRecordElement? record { get; private set; }
	internal NativeAsyncStorage (int ordinal, int source_ordinal, int array_count, NativeAbiType? leaf, NativeRecordElement? record = null) {
		this.ordinal = ordinal;
		this.source_ordinal = source_ordinal;
		this.array_count = array_count;
		this.leaf = leaf;
		this.record = record;
	}
}
public class NativeAsyncOwner : Object {
	public int record_rank { get; private set; }
	public NativeContextHandleType? context { get; private set; }
	public NativeClosureHandleType? closure { get; internal set; }
	private NativeClosureHandleType? original_closure;
	internal bool closure_valid() {
		return closure == original_closure;
	}
	public int cleanup_position { get; private set; }
	public int ordinal { get; private set; }
	public int source_ordinal { get; private set; }
	public int class_ordinal { get; private set; }
	public bool catch_owner { get; private set; }
	private string cleanup_identifier;
	public string cleanup_symbol { get { return cleanup_identifier; } }
	public int capture_first_leaf { get; private set; default = -1; }
	internal NativeAsyncOwner (int ordinal, int source_ordinal, int class_ordinal, bool catch_owner, string cleanup_symbol = "", int capture_first_leaf = -1, int cleanup_position = -1, NativeClosureHandleType? closure = null, NativeContextHandleType? context = null, int record_rank = -1) {
		this.record_rank = record_rank;
		this.context = context;
		this.closure = closure;
		original_closure = closure;
		this.cleanup_position = cleanup_position;
		this.ordinal = ordinal;
		this.source_ordinal = source_ordinal;
		this.class_ordinal = class_ordinal;
		this.catch_owner = catch_owner;
		this.cleanup_identifier = cleanup_symbol;
		this.capture_first_leaf = capture_first_leaf;
	}
}
public class NativeAsyncBuffer : Object {
	public int record_rank { get; private set; }
	public NativeContextSliceType? context_origin { get; private set; }
	public int cleanup_position { get; private set; }
	public int ordinal { get; private set; }
	public int owner_ordinal { get; private set; }
	public NativeAbiType? element { get; private set; }
	public NativeRecordElement? record_element { get; private set; }
	public int capture_first_leaf { get; private set; default = -1; }
	internal NativeAsyncBuffer (int ordinal, int owner_ordinal, NativeAbiType element, int capture_first_leaf = -1, int cleanup_position = -1, NativeContextSliceType? context_origin = null, int record_rank = -1) {
		this.record_rank = record_rank;
		this.cleanup_position = cleanup_position;
		this.ordinal = ordinal;
		this.owner_ordinal = owner_ordinal;
		this.element = element;
		this.capture_first_leaf = capture_first_leaf;
		this.context_origin = context_origin;
	}
	internal NativeAsyncBuffer.for_record (int ordinal, int owner_ordinal, NativeRecordElement element, int capture_first_leaf = -1, int cleanup_position = -1, int record_rank = -1) {
		this.record_rank = record_rank;
		this.cleanup_position = cleanup_position;
		this.ordinal = ordinal;
		this.owner_ordinal = owner_ordinal;
		this.record_element = element;
		this.capture_first_leaf = capture_first_leaf;
	}
}
public class NativeAsyncField : Object {
	public int definition { get; private set; }
	public int block { get; private set; }
	public int position { get; private set; }
	public NativeAbiType abi_type { get; private set; }
	internal NativeAsyncField (int definition, int block, int position, NativeAbiType type) {
		this.definition = definition;
		this.block = block;
		this.position = position;
		this.abi_type = type;
	}
}
public class NativeAsyncState : Object {
	public int payload_definition { get; private set; }
	public int payload_owner { get; private set; }
	public int pc { get; private set; }
	public int block { get; private set; }
	public int position { get; private set; }
	private int[] initialized;
	public uint initialized_count { get { return initialized.length; } }
	public int initialized_field(uint ordinal) {
		return initialized[ordinal];
	}
	internal NativeAsyncState (int pc, int block, int position, GenericArray<int> initialized, int payload_definition = -1, int payload_owner = -1) {
		this.payload_definition = payload_definition;
		this.payload_owner = payload_owner;
		this.pc = pc;
		this.block = block;
		this.position = position;
		this.initialized = new int[initialized.length];
		for (int i = 0; i < initialized.length; i++) {
			this.initialized[i] = initialized[i];
		}
	}
}
// Detached concrete code/storage plan. No SSA or semantic function survives.
public class NativeAsyncFramePlan : Object {
	private string record_origin;
	internal static string record_identity(NativeStructValuePlan? record) {
		if (record == null) {
			return "none";
		}
		var text = new StringBuilder ("%d/%d:%s/%d/%d".printf (record.struct_ordinal, record.struct_name.length, record.struct_name, (int) record.mode, (int) record.result_carrier));
		foreach (var leaf in record.leaves) {
			text.append_printf ("/leaf=%s/%s/%d/%s", leaf.field_path, leaf.storage_path, leaf.buffer_component, leaf.abi_type.spelling ());
		}
		foreach (var owner in record.ownership) {
			text.append_printf ("/owner=%s/%d:%s/%d:%s/%d/%d/%s", owner.field_path, owner.type_name.length, owner.type_name, owner.cleanup_symbol.length, owner.cleanup_symbol, owner.cleanup_class_ordinal, owner.acquisition_rank, owner.buffer_cleanup == null ? "none" : owner.buffer_cleanup.element_spelling ());
		}
		return text.str;
	}
	public const string CAPABILITY = "native-tasks-v17";
	public const string LINUX_CAPABILITY = "linux-uring-timers-v1";
	public Astra.Source.AsyncProviderKind provider { get; private set; }
	private int[] cleanup_domains;
	private int[] cleanup_ordinals;
	public uint cleanup_count { get { return cleanup_domains.length; } }
	public int cleanup_domain(uint ordinal) {
		return cleanup_domains[ordinal];
	}
	public int cleanup_ordinal(uint ordinal) {
		return cleanup_ordinals[ordinal];
	}
	private void order_cleanups() {
		int count = (int) (owner_count + buffer_count + enum_count);
		cleanup_domains = new int[count];
		cleanup_ordinals = new int[count];
		int[] positions = new int[count];
		int[] ranks = new int[count];
		int n = 0;
		for (int domain = 0; domain < 3; domain++) {
			int length = (int) (domain == 0 ? owner_count : domain == 1 ? buffer_count : enum_count);
			for (int ordinal = 0; ordinal < length; ordinal++) {
				int position = domain == 0 ? owners[ordinal].cleanup_position : domain == 1 ? buffers[ordinal].cleanup_position : enums[ordinal].cleanup_position;
				int rank = domain == 0 ? owners[ordinal].record_rank : domain == 1 ? buffers[ordinal].record_rank : -1;
				int at = n;
				while (at > 0 && (positions[at - 1] > position || positions[at - 1] == position && ranks[at - 1] > rank)) {
					positions[at] = positions[at - 1];
					ranks[at] = ranks[at - 1];
					cleanup_domains[at] = cleanup_domains[at - 1];
					cleanup_ordinals[at] = cleanup_ordinals[at - 1];
					at--;
				}
				positions[at] = position;
				ranks[at] = rank;
				cleanup_domains[at] = domain;
				cleanup_ordinals[at] = ordinal;
				n++;
			}
		}
	}
	public int function_ordinal { get; private set; }
	public Astra.Source.SourceSpan declaration { get; private set; }
	public NativeAbiType? result { get; private set; }
	public NativeStructValuePlan? record_result { get; private set; }
	public uint object_count { get; private set; }
	public uint owner_count { get; private set; }
	private GenericArray<NativeAsyncField> fields;
	private GenericArray<NativeAsyncState> states;
	private GenericArray<NativeAsyncBuffer> buffers;
	private GenericArray<NativeAsyncOwner> owners;
	private GenericArray<NativeAsyncWait> waits = new GenericArray<NativeAsyncWait> ();
	public uint wait_count { get { return waits.length; } }
	public NativeAsyncWait wait(uint ordinal) {
		return waits[ordinal];
	}
	private GenericArray<NativeAsyncLoan> loans = new GenericArray<NativeAsyncLoan> ();
	public uint loan_count { get { return loans.length; } }
	public NativeAsyncLoan loan(uint ordinal) {
		return loans[ordinal];
	}
	private GenericArray<NativeAsyncStorage> storage = new GenericArray<NativeAsyncStorage> ();
	private GenericArray<NativeAsyncEnumStorage> enums = new GenericArray<NativeAsyncEnumStorage> ();
	public uint enum_count { get { return enums.length; } }
	public NativeAsyncEnumStorage enum_slot(uint ordinal) {
		return enums[ordinal];
	}
	public uint storage_count { get { return storage.length; } }
	public NativeAsyncStorage storage_slot(uint ordinal) {
		return storage[ordinal];
	}
	public NativeAsyncOwner owner(uint ordinal) {
		return owners[ordinal];
	}
	public uint buffer_count { get { return buffers.length; } }
	public NativeAsyncBuffer buffer(uint ordinal) {
		return buffers[ordinal];
	}
	public uint field_count { get { return fields.length; } }
	public uint state_count { get { return states.length; } }
	public NativeAsyncField field(uint ordinal) {
		return fields[ordinal];
	}
	public NativeAsyncState state(uint ordinal) {
		return states[ordinal];
	}
	internal NativeAsyncFramePlan (int function_ordinal, Astra.Source.SourceSpan declaration, NativeAbiType? result, GenericArray<NativeAsyncField> fields, GenericArray<NativeAsyncState> states, uint object_count = 0, uint owner_count = 0, GenericArray<NativeAsyncBuffer>? buffers = null, GenericArray<NativeAsyncOwner>? owners = null, GenericArray<NativeAsyncStorage>? storage = null, GenericArray<NativeAsyncEnumStorage>? enums = null, NativeStructValuePlan? record_result = null, GenericArray<NativeAsyncLoan>? loans = null, GenericArray<NativeAsyncWait>? waits = null, Astra.Source.AsyncProviderKind provider = Astra.Source.AsyncProviderKind.VIRTUAL) {
		this.provider = provider;
		if (waits != null) {
			foreach (var wait in waits) {
				this.waits.add (wait);
			}
		}
		if (loans != null) {
			foreach (var loan in loans) {
				this.loans.add (loan);
			}
		}
		this.record_result = record_result;
		record_origin = record_identity (record_result);
		if (enums != null) {
			foreach (var slot in enums) {
				this.enums.add (slot);
			}
		}
		if (storage != null) {
			foreach (var slot in storage) {
				this.storage.add (slot);
			}
		}
		this.owners = new GenericArray<NativeAsyncOwner> ();
		if (owners != null) {
			foreach (var owner in owners) {
				this.owners.add (owner);
			}
		}
		this.buffers = new GenericArray<NativeAsyncBuffer> ();
		if (buffers != null) {
			foreach (var buffer in buffers) {
				this.buffers.add (buffer);
			}
		}
		this.object_count = object_count;
		this.owner_count = owner_count;
		this.function_ordinal = function_ordinal;
		this.declaration = declaration;
		this.result = result;
		this.fields = new GenericArray<NativeAsyncField> ();
		foreach (var field in fields) {
			this.fields.add (field);
		}
		this.states = new GenericArray<NativeAsyncState> ();
		foreach (var state in states) {
			this.states.add (state);
		}
		order_cleanups ();
	}
	public void verify() throws NativeAbiError {
		if (record_origin != record_identity (record_result)) {
			throw new NativeAbiError.INVALID_ABI ("async record result lost its original complete carrier and cleanup authority");
		}
		if (provider != Astra.Source.AsyncProviderKind.VIRTUAL && provider != Astra.Source.AsyncProviderKind.LINUX_IO_URING && provider != Astra.Source.AsyncProviderKind.POSIX_THREADED) {
			throw new NativeAbiError.INVALID_ABI ("unknown native completion provider");
		}
		if (record_result != null && (result != null || record_result.struct_ordinal < 0 || record_result.leaves.length == 0)) {
			throw new NativeAbiError.INVALID_ABI ("async record result requires its complete bounded leaf carrier");
		}
		if (function_ordinal < 0 || states.length == 0 || states[0].pc != 0 || states[0].position != -1) {
			throw new NativeAbiError.INVALID_ABI ("async frame requires exact body ordinal and cold initial state");
		}
		foreach (var wait in waits) {
			bool state = false;
			foreach (var resume in states) {
				if (resume.block == wait.block && resume.position == wait.position) {
					state = true;
				}
			}
			if (!state || wait.child_definition < 0 || wait.exception_definition < 0 || (wait.enum_ordinal < 0) != (wait.enum_instance == null) || (wait.enum_ordinal >= 0 && (uint) wait.enum_ordinal >= enum_count) || (wait.discard && (wait.leaf_count != 0 || wait.enum_ordinal >= 0))) {
				throw new NativeAbiError.INVALID_ABI ("pending task observation lost exact right/state/result group authority");
			}
		}
		foreach (var wait in waits) {
			if (wait.bridge_definition < 0) {
				if (wait.bridge_owner != -1 || wait.composed) {
					throw new NativeAbiError.INVALID_ABI ("bridge metadata has no target pool definition");
				}
				continue;
			}
			if (!wait.composed || provider == Astra.Source.AsyncProviderKind.POSIX_THREADED || wait.target_provider != Astra.Source.AsyncProviderKind.POSIX_THREADED || wait.bridge_owner < 0 || wait.bridge_owner >= owners.length || owners[wait.bridge_owner].cleanup_symbol != "astra_async_worker_pool_close" || owners[wait.bridge_owner].class_ordinal >= 0) {
				throw new NativeAbiError.INVALID_ABI ("bridge lost exact provider direction and joined pool close authority");
			}
			bool initialized = false;
			foreach (var state in states) {
				if (state.block != wait.block || state.position != wait.position) {
					continue;
				}
				for (uint i = 0; i < state.initialized_count; i++) {
					int ordinal = state.initialized_field (i);
					if (ordinal < 0 || ordinal >= fields.length) {
						continue;
					}
					var field = fields[ordinal];
					if (field.definition == wait.bridge_definition && field.abi_type.get_type () == typeof (NativeScalarAbiType) && ((NativeScalarAbiType) field.abi_type).scalar_type == NativeScalarType.PTR) {
						initialized = true;
					}
				}
			}
			if (!initialized) {
				throw new NativeAbiError.INVALID_ABI ("bridge lacks its exact initialized persistent pool field");
			}
		}
		var loan_ids = new HashTable<Astra.Source.SuspensionLoanIdentity, bool> (direct_hash, direct_equal);
		foreach (var loan in loans) {
			if (loan_ids.contains (loan.identity) || loan.block < 0 || loan.creation_position < 0 || loan.wait_position <= loan.creation_position || loan.child_definition < 0 || loan.child_body < 0 || loan.parameter_ordinal < 0 || loan.view_definition < 0 || loan.storage_ordinal < 0 || loan.storage_ordinal >= storage.length || storage[loan.storage_ordinal].array_count < 1) {
				throw new NativeAbiError.INVALID_ABI ("suspension loan lost exact capture-through-join/view/frame storage authority");
			}
			loan_ids.insert (loan.identity, true);
		}
		var definitions = new HashTable<int, bool> (direct_hash, direct_equal);
		if (owners.length != owner_count) {
			throw new NativeAbiError.INVALID_ABI ("async frame requires complete owner descriptors");
		}
		for (uint o = 0; o < owners.length; o++) {
			if (owners[o].ordinal != o || owners[o].source_ordinal < 0 || ((owners[o].class_ordinal < 0) == (owners[o].cleanup_symbol == "")) || (owners[o].catch_owner && owners[o].cleanup_symbol != "")) {
				throw new NativeAbiError.INVALID_ABI ("async frame owner lost its exact declaration/domain association");
			}
		}
		foreach (var owner in owners) {
			if (owner.context != null && (!owner.context.valid () || owner.class_ordinal >= 0 || owner.catch_owner || owner.closure != null || owner.cleanup_symbol != owner.context.cleanup)) {
				throw new NativeAbiError.INVALID_ABI ("async allocator context owner lost exact lifetime/thread/release authority");
			}
			if (!owner.closure_valid ()) {
				throw new NativeAbiError.INVALID_ABI ("async closure owner lost its original callable cleanup contract");
			}
			if (owner.closure != null && (owner.class_ordinal >= 0 || owner.catch_owner || owner.closure.actor || owner.closure.threaded ||
			                              provider == Astra.Source.AsyncProviderKind.POSIX_THREADED)) {
				throw new NativeAbiError.INVALID_ABI ("async closure owner requires its exact single-threaded cleanup domain");
			}
		}
		for (uint b = 0; b < buffers.length; b++) {
			var buffer = buffers[b];
			if (buffer.ordinal != b || buffer.owner_ordinal < 0 || (buffer.element == null) == (buffer.record_element == null) || buffer.context_origin != null && (!buffer.context_origin.valid () || provider == Astra.Source.AsyncProviderKind.POSIX_THREADED && buffer.context_origin.allocator.mode != "owned-concurrent" || buffer.element == null || !buffer.element.same_type (new NativeScalarAbiType (NativeScalarType.U8)))) {
				throw new NativeAbiError.INVALID_ABI ("async buffer lost exact complete owner/storage/context identity");
			}
		}
		for (uint e = 0; e < enums.length; e++) {
			var slot = enums[e];
			if (slot.ordinal != e || slot.capture_first_leaf < -1 || slot.inspection_root >= enums.length || slot.reservation_source >= enums.length || slot.inspection_root == e || slot.reservation_source == e) {
				throw new NativeAbiError.INVALID_ABI ("async enum storage lost exact carrier/instance/inspection authority");
			}
		}
		for (uint s = 0; s < storage.length; s++) {
			var slot = storage[s];
			if (slot.ordinal != s || slot.source_ordinal < 0 || slot.array_count == 0 || slot.array_count < -1 || (slot.leaf == null) == (slot.record == null)) {
				throw new NativeAbiError.INVALID_ABI ("async storage lost exact declared type/local/extent identity");
			}
			if (slot.record != null) {
				NativeRecordLayout.x86_64 (slot.record);
			}
		}
		foreach (var field in fields) {
			if (field.definition < 0 || definitions.contains (field.definition)) {
				throw new NativeAbiError.INVALID_ABI ("async field requires one exact complete definition identity");
			}
			definitions.insert (field.definition, true);
		}
		for (uint s = 0; s < states.length; s++) {
			var state = states[s];
			if (state.pc != s || state.block < 0 || (s != 0 && state.position < 0)) {
				throw new NativeAbiError.INVALID_ABI ("async resume state lost exact dispatcher/source position");
			}
			if ((state.payload_definition < 0) != (state.payload_owner < 0)) {
				throw new NativeAbiError.INVALID_ABI ("payload suspension requires paired buffer definition and owner authority");
			}
			if (state.payload_owner >= 0) {
				if (s == 0 || provider != Astra.Source.AsyncProviderKind.LINUX_IO_URING || state.payload_owner >= owners.length || owners[state.payload_owner].cleanup_symbol != "astra_linux_payload_close") {
					throw new NativeAbiError.INVALID_ABI ("payload suspension lost exact Linux fd/buffer owner cleanup");
				}
				bool found = false;
				for (uint f = 0; f < state.initialized_count; f++) {
					int ordinal = state.initialized_field (f);
					if (ordinal >= 0 && ordinal < fields.length && fields[ordinal].definition == state.payload_definition && fields[ordinal].abi_type is NativeScalarAbiType && ((NativeScalarAbiType) fields[ordinal].abi_type).scalar_type == NativeScalarType.PTR) {
						found = true;
					}
				}
				if (!found) {
					throw new NativeAbiError.INVALID_ABI ("payload suspension lacks its initialized stable buffer owner pointer");
				}
			}
			var seen = new HashTable<int, bool> (direct_hash, direct_equal);
			for (uint i = 0; i < state.initialized_count; i++) {
				int field = state.initialized_field (i);
				if (field < 0 || field >= fields.length || seen.contains (field)) {
					throw new NativeAbiError.INVALID_ABI ("async state initialization requires exact unique frame field");
				}
				seen.insert (field, true);
			}
		}
	}
}
public class NativeExecutorHandleType : NativeAbiType {
	public Astra.Source.TaskContractIdentity identity { get; private set; }
	internal NativeExecutorHandleType (Astra.Source.TaskContractIdentity identity) {
		this.identity = identity;
	}
	public override string spelling() {
		return "UNIQUE_VIRTUAL_EXECUTOR";
	}
	public override bool same_type(NativeAbiType other) {
		return other is NativeExecutorHandleType && ((NativeExecutorHandleType) other).identity == identity;
	}
}

}
