// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.Semantic {
public delegate ForeignValueType? ForeignRecordLookup(SemanticType type);
public delegate ForeignApiContract? ForeignObjectLookup(SemanticType type);
public delegate ClassType? ForeignClassLookup(string name);
public delegate ForeignImportContract? ForeignImportLookup(SemanticType type);
public class ForeignRootCatalog : Object {
	private HashTable<SemanticType, ForeignApiContract> roots = new HashTable<SemanticType, ForeignApiContract> (direct_hash, direct_equal);
	private HashTable<string, ClassType> classes = new HashTable<string, ClassType> (str_hash, str_equal);
	private HashTable<SemanticType, ForeignImportContract> imported = new HashTable<SemanticType, ForeignImportContract> (direct_hash, direct_equal);
	public void add(SemanticType type, ForeignClassPolicy? policy) {
		if (type is ClassType) {
			classes.insert (type.nominal_name (), (ClassType) type);
		}
		if (policy != null && policy.declared_api != null) {
			roots.insert (type, policy.declared_api);
		}
	}
	public void add_imported(SemanticType type, ForeignImportContract? contract) {
		if (contract != null) {
			imported.insert (type, contract);
		}
	}
	public ForeignImportContract? lookup_imported(SemanticType type) {
		return imported.lookup (type);
	}
	public ForeignApiContract? lookup(SemanticType type) {
		return roots.lookup (type);
	}
	public ClassType? lookup_class(string name) {
		return classes.lookup (name);
	}
}
// Verification-local catalog reconstructed from the owning stage's fields.
// Never stored in a foreign artifact or used as a source admission cache.
public class ForeignRecordCatalog : Object {
	private GenericArray<SemanticType> types = new GenericArray<SemanticType> ();
	private GenericArray<ForeignValueType> values = new GenericArray<ForeignValueType> ();
	public void add(SemanticType type, ForeignValueType? value) {
		if (value != null) {
			types.add (type);
			values.add (value);
		}
	}
	public ForeignValueType? lookup(SemanticType type) {
		for (uint t = 0; t < types.length; t++) {
			if (types[t] == type) {
				return values[t];
			}
		}
		return null;
	}
}
public class ForeignApiTypes : Object {
	public static ForeignValueType? record(SemanticType type, GenericArray<string> names, GenericArray<SemanticType> types) {
		if (!type.is_struct_storage () || type.is_parameterized () || names.length != types.length) {
			return null;
		}
		var fields = new GenericArray<ForeignRecordField> ();
		for (uint f = 0; f < types.length; f++) {
			var value = copied (types[f]);
			if (value == null || !value.scalar ()) {
				return null;
			}
			fields.add (new ForeignRecordField (names[f], value.kind));
		}
		var result = new ForeignValueType (ForeignValueKind.RECORD, type.nominal_name (), fields);
		return result.valid () ? result : null;
	}
	public static bool uses_bool(ForeignValueType type) {
		if (type.kind == ForeignValueKind.BOOL) {
			return true;
		}
		if (type.kind == ForeignValueKind.CALLBACK) {
			if (type.callback_result != null && uses_bool (type.callback_result)) {
				return true;
			}
			for (uint p = 0; p < type.callback_parameter_count; p++) {
				if (uses_bool (type.callback_parameter (p))) {
					return true;
				}
			}
		}
		for (uint f = 0; f < type.field_count; f++) {
			if (type.field (f).kind == ForeignValueKind.BOOL) {
				return true;
			}
		}
		return false;
	}
	// Reconstruct logical copied record parameters from this stage's exact
	// leaf groups. Width-compatible tuples without an actual group refuse.
	public static bool projected_parameters(ForeignMemberContract member, GenericArray<SemanticType> actual,
		GenericArray<PointerParameterContract> actual_contracts, GenericArray<StructBoundaryGroup> groups,
		out GenericArray<SemanticType> logical, out GenericArray<PointerParameterContract> contracts, uint prefix = 0) {
		logical = new GenericArray<SemanticType> ();
		contracts = new GenericArray<PointerParameterContract> ();
		if (actual.length != actual_contracts.length) {
			return false;
		}
		if (prefix > actual.length) {
			return false;
		}
		for (uint p = 0; p < prefix; p++) {
			logical.add (actual[p]);
			contracts.add (actual_contracts[p]);
		}
		uint cursor = prefix, used = 0;
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.value_type.kind != ForeignValueKind.RECORD) {
				if (cursor >= actual.length) {
					return false;
				}
				logical.add (actual[cursor]);
				contracts.add (actual_contracts[cursor]);
				cursor++;
				continue;
			}
			StructBoundaryGroup? selected = null;
			foreach (var group in groups) {
				if (group.source_ordinal == p + prefix) {
					if (selected != null) {
						return false;
					}
					selected = group;
				}
			}
			if (selected == null || selected.first_leaf != cursor || selected.shape.mode != StructValueMode.COPY_VALUE || selected.shape.leaves.length != channel.value_type.field_count || cursor + selected.shape.leaves.length > actual.length) {
				return false;
			}
			for (uint f = 0; f < selected.shape.leaves.length; f++) {
				var leaf = selected.shape.leaves[f];
				var scalar = copied (actual[cursor + f]);
				if (leaf.depth != 1 || leaf.field_ordinal (0) != f || leaf.semantic_type != actual[cursor + f] || scalar == null || scalar.kind != channel.value_type.field (f).kind || actual_contracts[cursor + f] != PointerParameterContract.UNMANAGED) {
					return false;
				}
			}
			logical.add (selected.shape.semantic_type);
			contracts.add (PointerParameterContract.UNMANAGED);
			cursor += selected.shape.leaves.length;
			used++;
		}
		return cursor == actual.length && used == groups.length;
	}
	public static bool projected_facts(ForeignMemberContract member, bool[] actual_heap, bool[] actual_nonnull, out bool[] heap, out bool[] nonnull) {
		heap = new bool[member.parameter_count];
		nonnull = new bool[member.parameter_count];
		uint cursor = 0;
		for (uint p = 0; p < member.parameter_count; p++) {
			if (cursor >= actual_heap.length || cursor >= actual_nonnull.length) {
				return false;
			}
			heap[p] = actual_heap[cursor];
			nonnull[p] = actual_nonnull[cursor];
			cursor += member.parameter (p).value_type.kind == ForeignValueKind.RECORD ? member.parameter (p).value_type.field_count : 1;
		}
		return cursor == actual_heap.length && cursor == actual_nonnull.length;
	}
	public static ForeignValueType? copied(SemanticType type, ForeignRecordLookup? records = null) {
		ForeignValueKind kind;
		switch (type.kind) {
		case TypeKind.VOID: kind = ForeignValueKind.VOID;
			break;
		case TypeKind.INT: kind = ForeignValueKind.I32;
			break;
		case TypeKind.U32: kind = ForeignValueKind.U32;
			break;
		case TypeKind.I64: kind = ForeignValueKind.I64;
			break;
		case TypeKind.U64: kind = ForeignValueKind.U64;
			break;
		case TypeKind.F32: kind = ForeignValueKind.F32;
			break;
		case TypeKind.F64: kind = ForeignValueKind.F64;
			break;
		case TypeKind.BOOL: kind = ForeignValueKind.BOOL;
			break;
			default: return records == null ? null : records (type);
		}
		return new ForeignValueType (kind);
	}
	public static string member_key(string owner, ForeignMemberKind kind, int ordinal) {
		return "%d:%s:%u:%d".printf (owner.length, owner, (uint) kind, ordinal);
	}
	public static bool checked_constructor(ForeignClassPolicy? policy, int ordinal, ClassType? error) {
		var api = policy == null ? null : policy.declared_api;
		if (api == null || error == null) {
			return false;
		}
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			if (member.kind == ForeignMemberKind.CONSTRUCTOR && member.native_member_ordinal == ordinal && member.error_origin == error.nominal_name () && member.error_map != null && member.error_map.valid (member.error_origin)) {
				return true;
			}
		}
		return false;
	}
	public static bool copied_channel(ForeignChannel channel, SemanticType type, ForeignDirection direction, ForeignRecordLookup? records = null) {
		var actual = copied (type, records);
		return actual != null && channel.valid () && !channel.by_reference && channel.direction == direction && channel.transfer == ForeignTransfer.COPY && channel.value_type.equal (actual);
	}
	public static bool byte_view(SemanticType type) {
		return type is SliceType && ((SliceType) type).element_type.kind == TypeKind.U8 && !((SliceType) type).deep_borrow;
	}
	public static ForeignValueType? callback(SemanticType type) {
		var signature = type as CallbackType;
		if (signature == null || !signature.supported () || signature.is_parameterized ()) {
			return null;
		}
		var result = copied (signature.result_type);
		if (result == null) {
			return null;
		}
		var parameters = new GenericArray<ForeignValueType> ();
		foreach (var parameter in signature.parameter_types) {
			var value = copied (parameter);
			if (value == null || !value.scalar ()) {
				return null;
			}
			parameters.add (value);
		}
		return new ForeignValueType (ForeignValueKind.CALLBACK, "", null, parameters, result);
	}
	public static ForeignValueType? scalar_pointee(SemanticType type) {
		var pointer = type as TypedPointerType;
		var value = pointer == null ? null : copied (pointer.pointee);
		return value != null && value.scalar () ? value : null;
	}
	public static bool parameter(ForeignChannel channel, SemanticType type, PointerParameterContract contract, ForeignRecordLookup? records = null, ForeignObjectLookup? objects = null, bool heap = false, bool nonnull = false, ForeignImportLookup? imported = null) {
		if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
			var value = callback (type);
			return value != null && value.equal (channel.value_type) && contract == PointerParameterContract.BORROWED_NOESCAPE && channel.valid () && channel.intrinsic_context && channel.direction == ForeignDirection.IN && channel.transfer == ForeignTransfer.BORROW && channel.call_scoped;
		}
		if (channel.by_reference) {
			var pointee = scalar_pointee (type);
			return pointee != null && channel.valid () && channel.value_type.equal (pointee) && contract == PointerParameterContract.BORROWED_NOESCAPE;
		}
		if (channel.value_type.object_handle ()) {
			if (type is HandleType) {
				return contract == (channel.transfer == ForeignTransfer.OWN ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE) && ForeignImportTypes.handle (channel, type, imported, channel.transfer == ForeignTransfer.OWN, "", false, nonnull);
			}
			var root = objects == null ? null : objects (type);
			if (!(type is ClassType) || root == null || !channel.valid () || root.native_origin != channel.value_type.nominal_origin || type.nominal_name () != channel.value_type.nominal_origin || channel.direction != ForeignDirection.IN || channel.native_nonnull != nonnull) {
				return false;
			}
			if (channel.transfer == ForeignTransfer.BORROW) {
				return contract == PointerParameterContract.BORROWED_NOESCAPE && channel.call_scoped;
			}
			return channel.transfer == ForeignTransfer.OWN && contract == PointerParameterContract.OWNED_TRANSFER && heap && channel.release_symbol == root.prefix + (root.lifetime == ForeignLifetime.UNIQUE ? "_destroy" : "_release");
		}
		if (channel.value_type.kind == ForeignValueKind.TEXT) {
			return channel.valid () && type is StringType && contract == PointerParameterContract.BORROWED_NOESCAPE && channel.transfer == ForeignTransfer.BORROW && channel.call_scoped && channel.direction == ForeignDirection.IN && (channel.encoding == ForeignTextEncoding.UTF8_COUNTED || channel.encoding == ForeignTextEncoding.UTF8_NUL);
		}
		if (channel.value_type.kind == ForeignValueKind.BYTES) {
			return channel.valid () && byte_view (type) && contract == PointerParameterContract.BORROWED_NOESCAPE && channel.transfer == ForeignTransfer.BORROW && channel.call_scoped && channel.encoding == ForeignTextEncoding.BYTES;
		}
		return contract == PointerParameterContract.UNMANAGED && copied_channel (channel, type, ForeignDirection.IN, records);
	}
	public static bool errors(ForeignMemberContract member, ClassType? bound, ForeignClassLookup? classes) {
		if (bound == null) {
			return member.error_origin == "" && member.error_map == null;
		}
		var map = member.error_map;
		if (map == null || classes == null || member.error_origin != bound.nominal_name () || !map.valid (member.error_origin) || classes (member.error_origin) != bound) {
			return false;
		}
		for (uint c = 0; c < map.case_count; c++) {
			var type = classes (map.at (c).native_origin);
			if (type == null || !type.derives_from (bound)) {
				return false;
			}
			for (uint p = 0; p < c; p++) {
				var previous = classes (map.at (p).native_origin);
				if (previous == null || type.derives_from (previous)) {
					return false;
				}
			}
		}
		return true;
	}
	public static bool owned_property(ForeignClassPolicy? policy, int ordinal) {
		if (policy == null || policy.declared_api == null) {
			return false;
		}
		var api = policy.declared_api;
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			if (member.kind == ForeignMemberKind.GETTER && member.native_member_ordinal == ordinal && member.parameter_count == 0 && member.error_origin == "" && member.result.value_type.kind == ForeignValueKind.NATIVE_OBJECT && member.result.transfer == ForeignTransfer.OWN) {
				return true;
			}
		}
		return false;
	}
	public static bool callable(ForeignApiContract api, ForeignMemberContract member,
		SemanticType result, GenericArray<SemanticType> parameters, GenericArray<PointerParameterContract> contracts,
		ClassType? error, bool asynchronous, ResultOwnershipContract result_contract, ForeignRecordLookup? records = null, ForeignObjectLookup? objects = null,
		bool[]? heap_parameters = null, bool[]? nonnull_parameters = null, bool heap_result = false, bool nonnull_result = false, ForeignClassLookup? classes = null, ForeignImportLookup? imported = null) {
		if (!member.valid () || member.native_member_ordinal < 0 || member.native_key != member_key (api.native_origin, member.kind, member.native_member_ordinal) || parameters.length != member.parameter_count || contracts.length != parameters.length || !errors (member, error, classes) || asynchronous) {
			return false;
		}
		for (uint p = 0; p < parameters.length; p++) {
			if (!parameter (member.parameter (p), parameters[p], contracts[p], records, objects, heap_parameters != null && p < heap_parameters.length && heap_parameters[p], nonnull_parameters != null && p < nonnull_parameters.length && nonnull_parameters[p], imported)) {
				return false;
			}
		}
		if (member.kind != ForeignMemberKind.CONSTRUCTOR && member.result.value_type.object_handle ()) {
			if (result is HandleType) {
				var root = imported == null ? null : imported (result);
				return root != null && result_contract == ResultOwnershipContract.OWNED_TRANSFER && !heap_result && ForeignImportTypes.handle (member.result, result, imported, true, root.cleanup_symbol (), true, nonnull_result);
			}
			var root = objects == null ? null : objects (result);
			return result is ClassType && root != null && root.native_origin == member.result.value_type.nominal_origin && result.nominal_name () == member.result.value_type.nominal_origin && result_contract == ResultOwnershipContract.OWNED_TRANSFER && heap_result && member.result.valid () && member.result.transfer == ForeignTransfer.OWN && member.result.native_nonnull == nonnull_result && member.result.release_symbol == root.prefix + (root.lifetime == ForeignLifetime.UNIQUE ? "_destroy" : "_release");
		}
		if (member.kind == ForeignMemberKind.CONSTRUCTOR) {
			return result.kind == TypeKind.VOID && member.result.value_type.kind == ForeignValueKind.NATIVE_OBJECT && member.result.value_type.nominal_origin == api.native_origin && member.result.transfer == ForeignTransfer.OWN && !member.result.nullable && member.result.release_symbol == api.prefix + (api.lifetime == ForeignLifetime.UNIQUE ? "_destroy" : "_release");
		}
		if (member.result.value_type.kind == ForeignValueKind.BYTES) {
			return byte_view (result) && result_contract == ResultOwnershipContract.OWNED_TRANSFER && member.result.valid () && member.result.transfer == ForeignTransfer.OWN && member.result.intrinsic_length && member.result.release_symbol == api.prefix + "_bytes_release";
		}
		if (member.result.value_type.kind == ForeignValueKind.TEXT) {
			return result is StringType && (result_contract == ResultOwnershipContract.STATIC_TEXT || result_contract == ResultOwnershipContract.RECEIVER_TEXT) && member.result.valid () && member.result.transfer == ForeignTransfer.OWN && member.result.intrinsic_length == (member.result.encoding == ForeignTextEncoding.UTF8_COUNTED) && member.result.release_symbol == api.prefix + "_text_release";
		}
		return result_contract == ResultOwnershipContract.UNMANAGED && copied_channel (member.result, result, ForeignDirection.OUT, records);
	}
}
public class ForeignImportTypes : Object {
	public static bool handle(ForeignChannel channel, SemanticType type, ForeignImportLookup? roots, bool owns, string cleanup = "", bool result = false, bool nonnull = false) {
		var handle = type as HandleType;
		var root = roots == null ? null : roots (type);
		return handle != null && root != null && root.valid () && handle.foreign_policy_identity == root.identity () && handle.name == root.api.native_origin && channel.valid () && channel.value_type.kind == root.object_kind && channel.value_type.nominal_origin == root.api.native_origin && channel.native_nonnull == nonnull && channel.transfer == (owns ? ForeignTransfer.OWN : ForeignTransfer.BORROW) && channel.call_scoped == !owns && channel.direction == (result ? ForeignDirection.OUT : ForeignDirection.IN) && (owns ? (!result || cleanup == root.cleanup_symbol ()) && channel.release_symbol == root.api.prefix + (root.api.lifetime == ForeignLifetime.SHARED ? "_release" : "_destroy") : channel.release_symbol == "");
	}
	public static bool signature(ForeignImportBinding binding, string name, SemanticType result, ResultOwnershipContract ownership, string cleanup, ClassType? error, GenericArray<SemanticType> supplied_parameters, GenericArray<PointerParameterContract> supplied_contracts, ForeignRecordLookup? records = null, GenericArray<StructBoundaryGroup>? groups = null, ForeignImportLookup? roots = null) {
		var parameters = supplied_parameters;
		var contracts = supplied_contracts;
		if (!binding.valid () || name != binding.root.api.native_origin + "." + binding.root.native_name (binding.member_index) || error == null || error.nominal_name () != binding.member.error_origin || contracts.length != parameters.length) {
			return false;
		}
		var member = binding.member;
		uint prefix = member.kind == ForeignMemberKind.CONSTRUCTOR ? 0 : 1;
		if (groups != null) {
			GenericArray<SemanticType> logical;
			GenericArray<PointerParameterContract> logical_contracts;
			if (!ForeignApiTypes.projected_parameters (member, parameters, contracts, groups, out logical, out logical_contracts, prefix)) {
				return false;
			}
			parameters = logical;
			contracts = logical_contracts;
		}
		if (parameters.length != member.parameter_count + prefix) {
			return false;
		}
		var declared_root = roots == null ? null : roots (prefix == 0 ? result : parameters[0]);
		if (declared_root == null || !declared_root.equal (binding.root)) {
			return false;
		}
		if (prefix != 0) {
			var handle = parameters[0] as HandleType;
			if (handle == null || handle.name != binding.root.api.native_origin || handle.foreign_policy_identity != binding.root.identity () || contracts[0] != PointerParameterContract.BORROWED_NOESCAPE) {
				return false;
			}
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (binding.root.com != null && member.kind == ForeignMemberKind.CONSTRUCTOR && p == 0) {
				if (!parameters[0].is_void_pointer () || contracts[0] != PointerParameterContract.BORROWED_NOESCAPE) {
					return false;
				}
				continue;
			}
			if (channel.value_type.object_handle ()) {
				if (contracts[p + prefix] != (channel.transfer == ForeignTransfer.OWN ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE) || !handle (channel, parameters[p + prefix], roots, channel.transfer == ForeignTransfer.OWN)) {
					return false;
				}
			} else if (!ForeignApiTypes.parameter (channel, parameters[p + prefix], contracts[p + prefix], records)) {
				return false;
			}
		}
		if (member.result.value_type.object_handle ()) {
			return ownership == ResultOwnershipContract.OWNED_TRANSFER && handle (member.result, result, roots, true, cleanup, true) && (prefix != 0 || result.nominal_name () == binding.root.api.native_origin);
		}
		if (member.result.value_type.kind == ForeignValueKind.BYTES || member.result.value_type.kind == ForeignValueKind.TEXT) {
			return ForeignApiTypes.byte_view (result) && ownership == ResultOwnershipContract.OWNED_TRANSFER && cleanup == "" && member.result.valid () && member.result.transfer == ForeignTransfer.OWN && member.result.direction == ForeignDirection.OUT && member.result.release_symbol == binding.root.api.prefix + (member.result.value_type.kind == ForeignValueKind.BYTES ? "_bytes_release" : "_text_release") && member.result.intrinsic_length == (member.result.encoding != ForeignTextEncoding.UTF8_NUL);
		}
		return ownership == ResultOwnershipContract.UNMANAGED && cleanup == "" && ForeignApiTypes.copied_channel (member.result, result, ForeignDirection.OUT, records);
	}
	public static bool factory(ForeignImportBinding binding, string name, SemanticType result, ClassType? error, bool owns, bool heap, ClassType? factory_error, GenericArray<SemanticType> parameters, GenericArray<PointerParameterContract> contracts) {
		return binding.valid () && name == binding.root.factory (binding.member_index) && result == error && owns && heap && factory_error == null && parameters.length == 2 && contracts.length == 2 && parameters[0].kind == TypeKind.INT && parameters[1].kind == TypeKind.INT && contracts[0] == PointerParameterContract.UNMANAGED && contracts[1] == PointerParameterContract.UNMANAGED;
	}
}

}
