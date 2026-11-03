// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
// Rebind only to this stage's actual member objects and signatures.
public class CfgForeignApi : Object {
	public static bool signal_prologue(CfgFunction function) {
		int position = 0;
		foreach (var group in function.struct_parameters) {
			if (group.shape.mode != StructValueMode.COPY_VALUE) {
				return false;
			}
			CfgLocalPlace? local = null;
			foreach (var candidate in function.locals) {
				if (candidate.struct_parameter == group) {
					if (local != null) {
						return false;
					}
					local = candidate;
				}
			}
			if (local == null) {
				return false;
			}
			for (int leaf = 0; leaf < group.shape.leaves.length; leaf++) {
				if (position >= function.entry.instructions.length) {
					return false;
				}
				var initialization = function.entry.instructions[position++] as CfgInitialize;
				var value = initialization == null ? null : initialization.value as CfgParameterValue;
				if (value == null || value.parameter != function.parameters[group.first_leaf + leaf]) {
					return false;
				}
				CfgPlace place = initialization.target;
				var path = group.shape.leaves[leaf];
				for (int depth = path.depth - 1; depth >= 0; depth--) {
					var field = place as CfgFieldPlace;
					if (field == null || field.field.ordinal != path.field_ordinal (depth)) {
						return false;
					}
					place = field.aggregate;
				}
				if (place != local) {
					return false;
				}
			}
		}
		return position == function.entry.instructions.length;
	}

	public static CfgFunction? target(CfgClass owner, ForeignMemberContract member) {
		if (member.native_member_ordinal < 0) {
			return null;
		}
		if (member.kind == ForeignMemberKind.CONSTRUCTOR) {
			return owner.constructor != null && owner.constructor.member_ordinal == member.native_member_ordinal ? owner.constructor : null;
		}
		if (member.kind == ForeignMemberKind.METHOD || member.kind == ForeignMemberKind.SIGNAL) {
			foreach (var method in owner.methods) {
				if (method.member_ordinal == member.native_member_ordinal && method.declaring_type == owner) {
					return method;
				}
			}
		}
		foreach (var property in owner.properties) {
			if (property.member_ordinal != member.native_member_ordinal || property.declaring_type != owner) {
				continue;
			}
			if (member.kind == ForeignMemberKind.GETTER) {
				return property.getter;
			}
			if (member.kind == ForeignMemberKind.SETTER) {
				return property.setter;
			}
		}
		return null;
	}

	public static ForeignValueType? record(CfgProgram? program,SemanticType type) {
		if (program == null) {
			return null;
		}
		var names = new GenericArray<string> ();
		var fields = new GenericArray<SemanticType> ();
		foreach (var structure in program.structs) {
			if (structure.semantic_type != type) {
				continue;
			}
			if (structure.representation != null && structure.representation.is_union) {
				return null;
			}
			foreach (var field in structure.fields) {
				if (field.is_private) {
					return null;
				}
				names.add (field.name);
				fields.add (field.semantic_type);
			}
			break;
		}
		return ForeignApiTypes.record (type,names,fields);
	}

	public static bool valid(CfgClass owner,CfgProgram? program = null) {
		var policy = owner.foreign_export;
		var api = policy == null ? null : policy.declared_api;
		if (api == null || !policy.valid () || api.native_origin != owner.name || owner.parent_class != null || owner.polymorphic || owner.exception_root || owner.generic_instance != null || owner.allocation_policy != null || (api.lifetime == ForeignLifetime.UNIQUE) != (owner.concurrency_policy == null)) {
			return false;
		}
		if (policy.com_count != 0 || policy.gobject != null) {
			var root_policies = new GenericArray<ForeignClassPolicy> ();
			var protocols = new GenericArray<ForeignComInterface> ();
			if (program != null) {
				foreach (var root in program.classes) {
					if (root.foreign_export != null) {
						root_policies.add (root.foreign_export);
					}
				}
				foreach (var handle in program.handles) {
					if (handle.c_import != null && handle.c_import.com != null) {
						protocols.add (handle.c_import.com);
					}
				}
			}
			if (!ForeignClassPolicy.com_roots_valid (policy,root_policies,protocols)) {
				return false;
			}
		}

		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			var function = target (owner,member);
			if (function == null || function.implicit_receiver == null || function.implicit_receiver.contract.instance_type != owner.semantic_type) {
				return false;
			}
			if (member.kind == ForeignMemberKind.SIGNAL && (owner.concurrency_policy == null || owner.concurrency_policy.identity != 1 || !function.span.file.native_interface && (!(function.entry.terminator is CfgForeignSignalReturn)))) {
				return false;
			}
			var parameters = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			bool[] heap = null,nonnull = null;
			foreach (var parameter in function.parameters) {
				parameters.add (parameter.semantic_type);
				contracts.add (parameter.pointer_contract);
				heap += parameter.heap_object;
				nonnull += parameter.requires_nonnull;
			}
			GenericArray<SemanticType> logical;
			GenericArray<PointerParameterContract> logical_contracts;
			if (!ForeignApiTypes.projected_parameters (member,parameters,contracts,function.struct_parameters,out logical,out logical_contracts)) {
				return false;
			}
			bool[] logical_heap,logical_nonnull;
			if (!ForeignApiTypes.projected_facts (member,heap,nonnull,out logical_heap,out logical_nonnull)) {
				return false;
			}
			parameters = logical;
			contracts = logical_contracts;
			heap = logical_heap;
			nonnull = logical_nonnull;
			var records = new ForeignRecordCatalog ();
			records.add (function.return_type,record (program,function.return_type));
			foreach (var type in parameters) {
				records.add (type,record (program,type));
			}
			var roots = new ForeignRootCatalog ();
			if (program != null) {
				foreach (var root in program.classes) {
					roots.add (root.semantic_type,root.foreign_export);
				}
			}
			if (program != null) {
				foreach (var handle in program.handles) {
					roots.add_imported (handle.semantic_type,handle.c_import);
				}
			}
			if (!ForeignApiTypes.callable (api,member,function.return_type,parameters,contracts,function.throws_type,function.async_body != null,function.result_contract,records.lookup,roots.lookup,heap,nonnull,function.heap_result,function.nonnull_result,roots.lookup_class,roots.lookup_imported)) {
				return false;
			}
		}
		return true;
	}

}
}
