// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.NativeAbi {
public class NativeForeignApi : Object {
	public static bool callback(NativeAbiType type, ForeignValueType declaration) {
		var signature = type as NativeCallbackType;
		if (signature == null || declaration.kind != ForeignValueKind.CALLBACK || !declaration.valid () || !signature.call_scoped || signature.carrier_fields != 2 || declaration.callback_result == null || signature.parameter_types.length != declaration.callback_parameter_count || signature.void_result != (declaration.callback_result.kind == ForeignValueKind.VOID) || signature.record_result != null || signature.owned_result != null || signature.owned_parameters.length != 0 || signature.borrowed_parameters.length != 0 || signature.record_parameters.length != 0) {
			return false;
		}
		if (!signature.void_result && (!declaration.callback_result.scalar () || signature.result_scalar () != scalar (declaration.callback_result.kind))) {
			return false;
		}
		for (uint p = 0; p < declaration.callback_parameter_count; p++) {
			var parameter = signature.parameter_types[p] as NativeScalarAbiType;
			if (parameter == null || parameter.get_type () != typeof (NativeScalarAbiType) || !declaration.callback_parameter (p).scalar () || parameter.scalar_type != scalar (declaration.callback_parameter (p).kind)) {
				return false;
			}
		}
		return true;
	}
	public static NativeScalarType scalar(ForeignValueKind kind) {
		switch (kind) {
		case ForeignValueKind.I32:
			return NativeScalarType.I32;
		case ForeignValueKind.U32:
			return NativeScalarType.U32;
		case ForeignValueKind.I64:
			return NativeScalarType.I64;
		case ForeignValueKind.U64:
			return NativeScalarType.U64;
		case ForeignValueKind.F32:
			return NativeScalarType.F32;
		case ForeignValueKind.F64:
			return NativeScalarType.F64;
		case ForeignValueKind.BOOL:
			return NativeScalarType.B1;
		default:
			return (NativeScalarType) (-1);
		}
	}
	private static NativeCallableKind kind(ForeignMemberKind kind) {
		switch (kind) {
		case ForeignMemberKind.CONSTRUCTOR:
			return NativeCallableKind.CONSTRUCTOR;
		case ForeignMemberKind.METHOD:
		case ForeignMemberKind.SIGNAL:
			return NativeCallableKind.METHOD;
		case ForeignMemberKind.GETTER:
			return NativeCallableKind.PROPERTY_GETTER;
		case ForeignMemberKind.SETTER:
			return NativeCallableKind.PROPERTY_SETTER;
		default:
			return (NativeCallableKind) (-1);
		}
	}
	public static bool record(NativeAbiProgram program,NativeStructValuePlan? plan,ForeignValueType type) {
		if (plan == null || !program.struct_values.find (plan) || plan.foreign_record == null || !plan.foreign_record.equal (type) || !type.valid () || type.kind != ForeignValueKind.RECORD || plan.mode != NativeStructValueMode.COPY_VALUE || plan.ownership.length != 0 || plan.leaves.length != type.field_count) {
			return false;
		}
		string nominal = plan.struct_name;
		foreach (var application in program.record_applications) {
			if (application.record == plan) {
				nominal = application.nominal_name;
			}
		}
		if (nominal != type.nominal_origin) {
			return false;
		}
		for (uint f = 0; f < type.field_count; f++) {
			var leaf = plan.leaves[f];
			var scalar_type = leaf.abi_type as NativeScalarAbiType;
			if (leaf.field_path != f.to_string () || leaf.storage_path != leaf.field_path || leaf.buffer_component != -1 || scalar_type == null || scalar_type.scalar_type != scalar (type.field (f).kind)) {
				return false;
			}
		}
		return true;
	}
	public static ForeignApiContract? object_api(NativeAbiProgram program,int ordinal,ForeignChannel channel) {
		if (ordinal < 0 || ordinal >= program.classes.length || channel.value_type.kind != ForeignValueKind.NATIVE_OBJECT || !channel.valid ()) {
			return null;
		}
		var root = program.classes[ordinal];
		var api = root.foreign_export == null ? null : root.foreign_export.declared_api;
		if (api == null || !root.foreign_export_valid () || api.native_origin != channel.value_type.nominal_origin || channel.transfer == ForeignTransfer.OWN && channel.release_symbol != api.prefix + (api.lifetime == ForeignLifetime.UNIQUE ? "_destroy" : "_release")) {
			return null;
		}
		return api;
	}
	private static int named_class(NativeAbiProgram program,string name) {
		for (int c = 0; c < program.classes.length; c++) {
			if (program.classes[c].name == name) {
				return c;
			}
		}
		return -1;
	}
	private static bool subtype(NativeAbiProgram program,int child,int parent) {
		for (int depth = 0; depth <= program.classes.length && child >= 0 && child < program.classes.length; depth++) {
			if (child == parent) {
				return true;
			}
			child = program.classes[child].parent_ordinal;
		}
		return false;
	}
	public static bool errors(NativeAbiProgram program,ForeignMemberContract member,NativeExceptionPlan? plan) {
		if (plan == null) {
			return member.error_origin == "" && member.error_map == null;
		}
		var map = member.error_map;
		if (map == null || !map.valid (member.error_origin) || plan.bound_name != member.error_origin || named_class (program,member.error_origin) != plan.bound_ordinal || plan.root_ordinal < 0 || plan.root_ordinal >= program.classes.length || !program.classes[plan.root_ordinal].exception_root || program.classes[plan.root_ordinal].name != plan.root_name || !subtype (program,plan.bound_ordinal,plan.root_ordinal)) {
			return false;
		}
		for (uint c = 0; c < map.case_count; c++) {
			int type = named_class (program,map.at (c).native_origin);
			if (type < 0 || !subtype (program,type,plan.bound_ordinal)) {
				return false;
			}
			for (uint p = 0; p < c; p++) {
				if (subtype (program,type,named_class (program,map.at (p).native_origin))) {
					return false;
				}
			}
		}
		return true;
	}
	public static bool valid(NativeAbiProgram program,NativeClassPlan owner) {
		var policy = owner.foreign_export;
		var api = policy == null ? null : policy.declared_api;
		if (api == null || !owner.foreign_export_valid () || owner.parent_ordinal != -1 || owner.polymorphic || owner.exception_root || owner.is_interface || owner.generic_instance != null || owner.allocation_policy != null || (api.lifetime == ForeignLifetime.UNIQUE) != (owner.concurrency_policy == null) || owner.foreign_targets ().length != api.member_count) {
			return false;
		}
		if (policy.com_count != 0 || policy.gobject != null) {
			var root_policies = new GenericArray<ForeignClassPolicy> ();
			var protocols = new GenericArray<ForeignComInterface> ();
			foreach (var root in program.classes) {
				if (root.foreign_export != null) {
					root_policies.add (root.foreign_export);
				}
			}
			foreach (var root in program.class_imports) {
				if (root.com != null) {
					protocols.add (root.com);
				}
			}
			if (!ForeignClassPolicy.com_roots_valid (policy,root_policies,protocols)) {
				return false;
			}
		}

		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			int ordinal = owner.foreign_member (m);
			if (ordinal < 0 || ordinal >= program.functions.length) {
				return false;
			}
			var target = program.functions[ordinal];
			var signature = target.signature;
			if (member.kind == ForeignMemberKind.SIGNAL && (owner.concurrency_policy == null || owner.concurrency_policy.identity != 1 || (target.span.file.native_interface ? target.foreign_signal != null : target.foreign_signal == null || !target.foreign_signal.valid (program,target)))) {
				return false;
			}
			if (target.owner != program || target.ordinal != ordinal || !target.declaring_type_is_class || target.declaring_type_ordinal != owner.ordinal || target.kind != kind (member.kind) || signature.receiver == null || signature.receiver.scalar_type != NativeScalarType.PTR || !errors (program,member,signature.exception_plan) || signature.object_result != null || signature.sum_result != null) {
				return false;
			}
			bool buffer = member.result.value_type.kind == ForeignValueKind.BYTES;
			bool text_result = member.result.value_type.kind == ForeignValueKind.TEXT;
			bool record_result = member.result.value_type.kind == ForeignValueKind.RECORD;
			bool object_result = member.kind != ForeignMemberKind.CONSTRUCTOR && member.result.value_type.object_handle ();
			bool resource_result = object_result && signature.resource_result != null;
			if ((object_result && !resource_result) != (signature.heap_result != null)) {
				return false;
			}
			if (resource_result) {
				var result = signature.result == null ? null : signature.result.abi_type as NativeScalarAbiType;
				if (result == null || result.scalar_type != NativeScalarType.PTR || !NativeForeignImportPlan.object_channel (program,member.result,signature.resource_result,true,true,signature.nonnull_result)) {
					return false;
				}
			}
			if (object_result && !resource_result) {
				var result = signature.result == null ? null : signature.result.abi_type as NativeScalarAbiType;
				var origin = signature.heap_result;
				if (member.result.transfer != ForeignTransfer.OWN || !origin.heap || result == null || result.scalar_type != NativeScalarType.PTR || object_api (program,origin.class_ordinal,member.result) == null || origin.class_name != member.result.value_type.nominal_origin || member.result.native_nonnull != signature.nonnull_result) {
					return false;
				}
			}
			if (record_result != (signature.struct_result != null) || record_result && (!record (program,signature.struct_result,member.result.value_type) || signature.struct_result_mode != NativeStructValueMode.COPY_VALUE)) {
				return false;
			}
			if (buffer != (signature.buffer_result != null)) {
				return false;
			}
			if (buffer) {
				var value = signature.buffer_result;
				var element = value.element_type as NativeScalarAbiType;
				if (!member.result.valid () || member.result.transfer != ForeignTransfer.OWN || !member.result.intrinsic_length || member.result.release_symbol != api.prefix + "_bytes_release" || signature.result != null || !value.transfers_ownership || value.record_element != null || element == null || element.scalar_type != NativeScalarType.U8 || value.base_type != NativeScalarType.PTR || value.length_type != NativeScalarType.I32) {
					return false;
				}
			}
			if (text_result) {
				var text = signature.result == null ? null : signature.result.abi_type as NativeTextType;
				if (!member.result.valid () || member.result.transfer != ForeignTransfer.OWN || member.result.intrinsic_length != (member.result.encoding == ForeignTextEncoding.UTF8_COUNTED) || member.result.release_symbol != api.prefix + "_text_release" || text == null || text.contract != NativeTextContract.STATIC_TEXT && text.contract != NativeTextContract.RECEIVER_TEXT || text.base_type != NativeScalarType.PTR || text.length_type != NativeScalarType.I32) {
					return false;
				}
			}
			uint cursor = 0,groups = 0;
			for (uint p = 0; p < member.parameter_count; p++) {
				var channel = member.parameter (p);
				if (channel.value_type.kind == ForeignValueKind.RECORD) {
					if (channel.direction != ForeignDirection.IN || channel.transfer != ForeignTransfer.COPY) {
						return false;
					}
					NativeStructParameterPlan? selected = null;
					foreach (var group in signature.struct_parameters) {
						if (group.source_ordinal == p) {
							if (selected != null) {
								return false;
							}
							selected = group;
						}
					}
					if (selected == null || selected.first_leaf != cursor || selected.mode != NativeStructValueMode.COPY_VALUE || !record (program,selected.value_plan,channel.value_type) || cursor + channel.value_type.field_count > signature.parameters.length) {
						return false;
					}
					for (uint f = 0; f < channel.value_type.field_count; f++) {
						if (!signature.parameters[cursor + f].abi_type.same_type (selected.value_plan.leaves[f].abi_type)) {
							return false;
						}
					}
					cursor += channel.value_type.field_count;
					groups++;
					continue;
				}
				if (cursor >= signature.parameters.length) {
					return false;
				}
				var actual = signature.parameters[cursor++];
				if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
					if (!channel.valid () || !channel.intrinsic_context || !callback (actual.abi_type,channel.value_type) || actual.scalar_pointee != null || actual.resource != null || actual.object_origin != null) {
						return false;
					}
					continue;
				}
				if (channel.by_reference) {
					var pointer = actual.abi_type as NativeScalarAbiType;
					if (pointer == null || pointer.scalar_type != NativeScalarType.PTR || actual.scalar_pointee == null || actual.scalar_pointee.scalar_type != scalar (channel.value_type.kind)) {
						return false;
					}
					continue;
				}
				if (channel.value_type.object_handle ()) {
					var scalar_type = actual.abi_type as NativeScalarAbiType;
					if (actual.resource != null) {
						if (scalar_type == null || scalar_type.scalar_type != NativeScalarType.PTR || actual.object_origin != null || actual.scalar_pointee != null || actual.owns_resource != (channel.transfer == ForeignTransfer.OWN) || !NativeForeignImportPlan.object_channel (program,channel,actual.resource,actual.owns_resource,false,actual.requires_nonnull)) {
							return false;
						}
						continue;
					}
					int root = channel.transfer == ForeignTransfer.BORROW ? actual.borrowed_class_ordinal : actual.object_origin == null ? -1 : actual.object_origin.class_ordinal;
					if (channel.direction != ForeignDirection.IN || scalar_type == null || scalar_type.scalar_type != NativeScalarType.PTR || actual.scalar_pointee != null || actual.requires_nonnull != channel.native_nonnull || object_api (program,root,channel) == null || channel.transfer == ForeignTransfer.BORROW && (!channel.call_scoped || actual.object_origin != null) || channel.transfer == ForeignTransfer.OWN && (actual.object_origin == null || !actual.object_origin.heap)) {
						return false;
					}
					continue;
				}
				if (channel.value_type.kind == ForeignValueKind.TEXT) {
					var text = actual.abi_type as NativeTextType;
					if (!channel.valid () || channel.direction != ForeignDirection.IN || channel.transfer != ForeignTransfer.BORROW || !channel.call_scoped || text == null || text.contract != NativeTextContract.BORROWED_NOESCAPE || text.base_type != NativeScalarType.PTR || text.length_type != NativeScalarType.I32) {
						return false;
					}
					continue;
				}
				if (channel.value_type.kind == ForeignValueKind.BYTES) {
					var slice = actual.abi_type as NativeSliceType;
					if (!channel.valid () || channel.transfer != ForeignTransfer.BORROW || !channel.call_scoped || slice == null || slice is NativeRecordSliceType || slice is NativeTextSliceType || slice.borrowed_element == null || slice.borrowed_element.scalar_type != NativeScalarType.U8 || slice.base_type != NativeScalarType.PTR || slice.length_type != NativeScalarType.I32) {
						return false;
					}
					continue;
				}
				var parameter = actual.abi_type as NativeScalarAbiType;
				if (channel.direction != ForeignDirection.IN || channel.transfer != ForeignTransfer.COPY || parameter == null || actual.scalar_pointee != null || !member.parameter (p).value_type.scalar () || parameter.scalar_type != scalar (member.parameter (p).value_type.kind)) {
					return false;
				}
			}
			if (cursor != signature.parameters.length || groups != signature.struct_parameters.length) {
				return false;
			}
			if (record_result || buffer || member.kind == ForeignMemberKind.CONSTRUCTOR || member.result.value_type.kind == ForeignValueKind.VOID) {
				if (signature.result != null) {
					return false;
				}
			} else if (!text_result && !object_result) {
				var result = signature.result == null ? null : signature.result.abi_type as NativeScalarAbiType;
				if (result == null || !member.result.value_type.scalar () || result.scalar_type != scalar (member.result.value_type.kind)) {
					return false;
				}
			}
		}
		return true;
	}
}
public class NativeForeignSignalPlan: Object {
	public ForeignSignalBinding binding { get; private set; }
	public NativeForeignSignalPlan (ForeignSignalBinding binding) {
		this.binding = binding;
	}
	public bool valid(NativeAbiProgram program,NativeFunction function) {
		if (!binding.valid () || function.span.file.native_interface || function.kind != NativeCallableKind.METHOD || !function.declaring_type_is_class || function.declaring_type_ordinal < 0 || function.declaring_type_ordinal >= program.classes.length || function.signature.exception_plan != null || function.signature.result != null) {
			return false;
		}
		var owner = program.classes[function.declaring_type_ordinal];
		return owner.foreign_export != null && owner.foreign_export.identity () == binding.root.identity () && binding.member_index < owner.foreign_targets ().length && owner.foreign_member (binding.member_index) == function.ordinal;
	}
}
public class NativeForeignImportPlan: Object {
	internal static bool object_channel(NativeAbiProgram program,ForeignChannel channel,NativeScalarOwner? resource,bool owns,bool result = false,bool nonnull = false) {
		if (resource == null || resource.class_ordinal != -1 || !channel.value_type.object_handle () || !channel.valid () || channel.native_nonnull != nonnull || channel.transfer != (owns ? ForeignTransfer.OWN : ForeignTransfer.BORROW) || channel.direction != (result ? ForeignDirection.OUT : ForeignDirection.IN) || channel.call_scoped != !owns) {
			return false;
		}
		foreach (var root in program.class_imports) {
			if (channel.value_type.kind == root.object_kind && root.api.native_origin == resource.type_name && root.api.native_origin == channel.value_type.nominal_origin && resource.cleanup_symbol == root.cleanup_symbol () && root.valid () && (!owns || channel.release_symbol == root.api.prefix + (root.api.lifetime == ForeignLifetime.SHARED ? "_release" : "_destroy"))) {
				return true;
			}
		}
		return false;
	}
	public ForeignImportBinding binding { get; private set; }
	public int error_factory { get; private set; }
	public NativeForeignImportPlan (ForeignImportBinding binding,int error_factory) {
		this.binding = binding;
		this.error_factory = error_factory;
	}
	public bool valid(NativeAbiProgram program,NativeFunction function) {
		if (!binding.valid () || function.name != binding.root.api.native_origin + "." + binding.root.native_name (binding.member_index) || !NativeForeignApi.errors (program,binding.member,function.signature.exception_plan) || function.kind != NativeCallableKind.FUNCTION || function.signature.receiver != null || function.signature.exception_plan == null || function.signature.exception_plan.bound_name != binding.member.error_origin || error_factory < 0 || error_factory >= program.functions.length) {
			return false;
		}
		bool root = false;
		foreach (var candidate in program.class_imports) {
			if (candidate.api.equal (binding.root.api) && candidate.identity () == binding.root.identity ()) {
				root = true;
			}
		}
		if (!root) {
			return false;
		}
		var factory = program.functions[error_factory];
		var signature = factory.signature;
		if (factory.name != binding.root.factory (binding.member_index) || factory.kind != NativeCallableKind.FUNCTION || signature.exception_plan != null || signature.heap_result == null || !signature.heap_result.heap || signature.heap_result.class_name != binding.member.error_origin || signature.parameters.length != 2 || signature.receiver != null) {
			return false;
		}
		foreach (var parameter in signature.parameters) {
			var type = parameter.abi_type as NativeScalarAbiType;
			if (type == null || type.scalar_type != NativeScalarType.I32 || parameter.resource != null || parameter.object_origin != null) {
				return false;
			}
		}
		var member = binding.member;
		uint prefix = member.kind == ForeignMemberKind.CONSTRUCTOR ? 0 : 1;
		if (function.signature.parameters.length < prefix || function.signature.object_result != null) {
			return false;
		}
		if (prefix == 1) {
			var self = function.signature.parameters[0];
			var type = self.abi_type as NativeScalarAbiType;
			if (type == null || type.scalar_type != NativeScalarType.PTR || self.resource == null || self.owns_resource || self.resource.type_name != binding.root.api.native_origin || self.resource.cleanup_symbol != binding.root.cleanup_symbol ()) {
				return false;
			}
		}
		uint cursor = prefix,groups = 0;
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.value_type.kind == ForeignValueKind.RECORD) {
				NativeStructParameterPlan? selected = null;
				foreach (var group in function.signature.struct_parameters) {
					if (group.source_ordinal == p + prefix) {
						if (selected != null) {
							return false;
						}
						selected = group;
					}
				}
				if (selected == null || selected.first_leaf != cursor || selected.mode != NativeStructValueMode.COPY_VALUE || !NativeForeignApi.record (program,selected.value_plan,channel.value_type) || cursor + channel.value_type.field_count > function.signature.parameters.length) {
					return false;
				}
				for (uint f = 0; f < channel.value_type.field_count; f++) {
					var leaf = function.signature.parameters[cursor++];
					var scalar = leaf.abi_type as NativeScalarAbiType;
					if (scalar == null || scalar.scalar_type != NativeForeignApi.scalar (channel.value_type.field (f).kind) || leaf.resource != null || leaf.object_origin != null || leaf.scalar_pointee != null) {
						return false;
					}
				}
				groups++;
				continue;
			}
			if (cursor >= function.signature.parameters.length) {
				return false;
			}
			var parameter = function.signature.parameters[cursor++];
			var scalar = parameter.abi_type as NativeScalarAbiType;
			if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				if (!channel.valid () || !channel.intrinsic_context || !NativeForeignApi.callback (parameter.abi_type,channel.value_type) || parameter.scalar_pointee != null || parameter.resource != null || parameter.object_origin != null) {
					return false;
				}
				continue;
			}
			if (binding.root.com != null && member.kind == ForeignMemberKind.CONSTRUCTOR && p == 0) {
				if (scalar == null || scalar.get_type () != typeof (NativeScalarAbiType) || scalar.scalar_type != NativeScalarType.PTR || parameter.resource != null || parameter.scalar_pointee != null || parameter.object_origin != null || parameter.com_unknown_borrow == null || parameter.com_unknown_borrow.identity () != binding.root.com.identity ()) {
					return false;
				}
				continue;
			}
			if (parameter.com_unknown_borrow != null) {
				return false;
			}
			if (channel.value_type.object_handle ()) {
				if (scalar == null || scalar.scalar_type != NativeScalarType.PTR || parameter.owns_resource != (channel.transfer == ForeignTransfer.OWN) || parameter.scalar_pointee != null || parameter.object_origin != null || !object_channel (program,channel,parameter.resource,channel.transfer == ForeignTransfer.OWN)) {
					return false;
				}
				continue;
			}
			if (channel.by_reference) {
				if (scalar == null || scalar.scalar_type != NativeScalarType.PTR || parameter.scalar_pointee == null || parameter.scalar_pointee.scalar_type != NativeForeignApi.scalar (channel.value_type.kind) || parameter.resource != null || parameter.object_origin != null) {
					return false;
				}
				continue;
			}
			if (channel.value_type.kind == ForeignValueKind.BYTES) {
				var slice = parameter.abi_type as NativeSliceType;
				if (slice == null || slice is NativeRecordSliceType || slice is NativeTextSliceType || slice.borrowed_element == null || slice.borrowed_element.scalar_type != NativeScalarType.U8 || slice.base_type != NativeScalarType.PTR || slice.length_type != NativeScalarType.I32 || !channel.call_scoped || channel.transfer != ForeignTransfer.BORROW) {
					return false;
				}
				continue;
			}
			if (channel.value_type.kind == ForeignValueKind.TEXT) {
				var text = parameter.abi_type as NativeTextType;
				if (text == null || text.contract != NativeTextContract.BORROWED_NOESCAPE || text.base_type != NativeScalarType.PTR || text.length_type != NativeScalarType.I32 || channel.direction != ForeignDirection.IN || !channel.call_scoped || channel.transfer != ForeignTransfer.BORROW) {
					return false;
				}
				continue;
			}

			if (scalar == null || scalar.scalar_type != NativeForeignApi.scalar (channel.value_type.kind) || parameter.resource != null || parameter.object_origin != null || parameter.scalar_pointee != null) {
				return false;
			}
		}
		if (cursor != function.signature.parameters.length || groups != function.signature.struct_parameters.length) {
			return false;
		}
		var result = function.signature.result == null ? null : function.signature.result.abi_type as NativeScalarAbiType;
		if (member.result.value_type.object_handle ()) {
			return result != null && result.scalar_type == NativeScalarType.PTR && function.signature.struct_result == null && function.signature.buffer_result == null && function.signature.heap_result == null && object_channel (program,member.result,function.signature.resource_result,true,true) && (prefix != 0 || function.signature.resource_result.type_name == binding.root.api.native_origin);
		}
		bool record_result = member.result.value_type.kind == ForeignValueKind.RECORD;
		if (record_result != (function.signature.struct_result != null)) {
			return false;
		}
		if (record_result) {
			return prefix == 1 && function.signature.result == null && function.signature.resource_result == null && function.signature.buffer_result == null && function.signature.struct_result_mode == NativeStructValueMode.COPY_VALUE && NativeForeignApi.record (program,function.signature.struct_result,member.result.value_type);
		}
		bool buffer = member.result.value_type.kind == ForeignValueKind.BYTES || member.result.value_type.kind == ForeignValueKind.TEXT;
		if (buffer != (function.signature.buffer_result != null)) {
			return false;
		}
		if (buffer) {
			var value = function.signature.buffer_result;
			var element = value.element_type as NativeScalarAbiType;
			return prefix == 1 && function.signature.result == null && function.signature.resource_result == null && value.transfers_ownership && value.record_element == null && element != null && element.scalar_type == NativeScalarType.U8 && value.base_type == NativeScalarType.PTR && value.length_type == NativeScalarType.I32 && member.result.valid () && member.result.transfer == ForeignTransfer.OWN && member.result.intrinsic_length == (member.result.encoding != ForeignTextEncoding.UTF8_NUL) && member.result.release_symbol == binding.root.api.prefix + (member.result.value_type.kind == ForeignValueKind.BYTES ? "_bytes_release" : "_text_release");
		}
		if (prefix == 0) {
			return false;
		}
		return function.signature.resource_result == null && (member.result.value_type.kind == ForeignValueKind.VOID ? result == null : result != null && result.scalar_type == NativeForeignApi.scalar (member.result.value_type.kind));
	}
}

}
