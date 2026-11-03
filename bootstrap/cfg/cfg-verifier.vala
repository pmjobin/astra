// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;
using Astra.Code;

namespace Astra.Cfg {
internal class CfgDeclaredClassAuthority : Object {
	private static void require(bool valid) throws CfgError {
		if (!valid) {
			throw new CfgError.INVALID_CFG ("declared generic Class lost substituted type/field/member/lifetime authority");
		}
	}

	private static bool exact_heap_class_argument(CfgProgram program, SemanticType type) {
		foreach (var owner in program.classes) {
			if (owner.semantic_type == type) {
				return owner.generic_instance == null && !owner.polymorphic && owner.parent_class == null && !((ClassType) type).is_interface;
			}
		}
		return false;
	}

	private static void callable(CfgProgram program, CfgFunction function, GenericMemberPattern member, ExactClassGenericInstance key, CopyabilityFields field_graph, TypeArgumentVector? method_arguments = null) throws CfgError {
		var types = new GenericArray<SemanticType> ();
		var contracts = new GenericArray<PointerParameterContract> ();
		for (int p = 0; p < function.parameters.length;) {
			StructBoundaryGroup? group = null;
			foreach (var candidate in function.struct_parameters) {
				if (candidate.first_leaf == p) {
					group = candidate;
				}
			}
			if (group != null) {
				types.add (group.shape.semantic_type);
				contracts.add (group.shape.mode == StructValueMode.BORROW_VALUE ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED);
				p += group.shape.leaves.length;
			} else {
				types.add (function.parameters[p].semantic_type);
				contracts.add (function.parameters[p].pointer_contract);
				p++;
			}
		}
		ExactHeapClassArgument exact_class = (type) => exact_heap_class_argument (program, type);
		require (GenericClassDeclaredShape.signature (member, key, function.return_type, types, contracts, function.throws_type, function.async_body != null, field_graph, method_arguments, exact_class));
		require ((int) function.dispatch_kind == member.dispatch);
		bool owner_result = GenericClassDeclaredShape.owns_value (member.result_mode, function.return_type);
		require (owner_result ? function.owned_cleanup != null : function.owned_cleanup == null);
		if (member.result_mode == GenericValueMode.BORROWED && (function.return_type is ClassType || function.return_type is HandleType)) {
			require (function.result_contract == ResultOwnershipContract.RECEIVER_BORROW);
		}
	}

	internal static void verify(CfgProgram program, CfgClass owner, ExactClassGenericInstance key) throws CfgError {
		CopyabilityFields field_graph = (type) => {
			foreach (var record in program.structs) {
				if (record.semantic_type != type) {
					continue;
				}
				var result = new GenericArray<SemanticType> ();
				foreach (var field in record.fields) {
					result.add (field.semantic_type);
				}
				return result;
			}
			return null;
		};
		var structure = key.definition.structure;
		require (structure != null && key.valid (owner.semantic_type) && owner.name == key.instance_type.name);
		for (int c = 0; c < structure.constraint_count; c++) {
			require (GenericClassDeclaredShape.constraint (structure.constraint (c), key.arguments, null, (type) => exact_heap_class_argument (program, type)));
		}
		require (owner.fields.length == structure.field_count && owner.properties.length == structure.property_count);
		foreach (var other in program.classes) {
			var prior = other.generic_instance;
			if (other != owner && prior != null) {
				require (prior.definition != key.definition || !prior.arguments.matches (key.arguments));
			}
		}
		for (int f = 0; f < structure.field_count; f++) {
			var declared = structure.field (f);
			var field = owner.fields[f];
			require (field.ordinal == f && field.name == declared.name && field.is_private == declared.private_field && field.text_snapshot == declared.readonly_field);
			require (GenericClassDeclaredShape.type (declared.value_type, field.semantic_type, key, null, field_graph));
			bool owned_field = GenericClassDeclaredShape.owns_field (declared.owned_field, field.semantic_type, field_graph);
			require (owned_field == (field.owned_cleanup != null || field.semantic_type is OwnerSlotsType));
		}
		int expected_methods = 0;
		for (int m = 0; m < structure.member_count; m++) {
			var member = structure.member (m);
			if (member.type_parameter_count != 0) {
				continue;
			}
			CfgFunction? function = null;
			if (member.kind == GenericMemberPatternKind.CONSTRUCTOR) {
				function = owner.constructor;
			} else if (member.kind == GenericMemberPatternKind.DESTRUCTOR) {
				function = owner.destructor;
			} else {
				expected_methods++;
				foreach (var method in owner.methods) {
					if (method.name == member.name && method.generic_method_instance == null) {
						require (function == null);
						function = method;
					}
				}
			}
			require (function != null && program.functions.find (function));
			callable (program, function, member, key, field_graph);
		}
		foreach (var method in owner.methods) {
			var request = method.generic_method_instance;
			if (request == null) {
				continue;
			}
			expected_methods++;
			require (request.valid (key) && method.name == request.name && program.functions.find (method));
			var member = structure.find_member (key.definition.generic_method_name (request.member));
			require (member != null);
			callable (program, method, member, key, field_graph, request.arguments);
			foreach (var other in owner.methods) {
				var prior = other.generic_method_instance;
				if (other != method && prior != null) {
					require (prior.member != request.member || !prior.arguments.matches (request.arguments));
				}
			}
		}
		require (owner.methods.length == expected_methods);
		for (int p = 0; p < structure.property_count; p++) {
			var declared = structure.property (p);
			var property = owner.properties[p];
			require (property.name == declared.name && property.ordinal == p && property.is_lazy == declared.lazy_property);
			require (property.getter != null && program.functions.find (property.getter) && (property.setter != null) == (declared.setter != null));
			callable (program, property.getter, declared.getter, key, field_graph);
			if (property.setter != null) {
				require (program.functions.find (property.setter));
				callable (program, property.setter, declared.setter, key, field_graph);
			}
		}
	}

}

public class CfgVerifier : Object {
	private CfgCallerResultOrigins caller_result_origins;
	private void verify_native_declaration(CfgFunction function, string path) throws CfgError {
		if (!function.native_declaration_valid ()) {
			fail (path, "native declaration lost its original signature facts");
		}
		var declaration = function.native_declaration;
		if (declaration == null) {
			if (function.name_span.file.native_interface) {
				fail (path, "native declaration lost its original signature facts");
			}
			return;
		}
		if (!function.name_span.file.native_interface) {
			fail (path, "native declaration requires its exact imported source origin");
		}
		if (!declaration.matches_async (function.async_body)) {
			fail (path, "native declaration differs from its original async result/runtime contract");
		}
		var types = new GenericArray<SemanticType> ();
		var contracts = new GenericArray<PointerParameterContract> ();
		var heaps = new bool[function.parameters.length];
		var nonnull = new bool[function.parameters.length];
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			types.add (parameter.semantic_type);
			contracts.add (parameter.pointer_contract);
			heaps[p] = parameter.heap_object;
			nonnull[p] = parameter.requires_nonnull;
		}
		var receiver = function.implicit_receiver;
		string member = function.name_span.text ();
		if (function is CfgConstructor) {
			member = "init";
		} else if (function is CfgDestructor) {
			member = "deinit";
		} else if (function is CfgPropertyGetter) {
			member = "get:" + ((CfgPropertyGetter) function).property_member.name;
		} else if (function is CfgPropertySetter) {
			member = "set:" + ((CfgPropertySetter) function).property_member.name;
		}
		var method = function as CfgMethod;
		if (method != null && method.generic_method_instance != null) {
			member += method.generic_method_instance.arguments.display_suffix (true);
		}
		string key = receiver == null ? "F:" + function.name : "C:" + receiver.contract.instance_type.display_name () + "::" + member;
		if (key != declaration.identity.key || !declaration.matches_records (function.struct_parameters, function.struct_result) ||
		    !declaration.matches (function.return_type, function.result_contract, function.heap_result, function.nonnull_result,
				receiver == null ? null : receiver.contract.instance_type, function.throws_type, types, contracts, heaps, nonnull)) {
			fail (path, "native declaration differs from its original exact signature");
		}
	}

	private bool thread_capture_type(SemanticType type, HashTable<SemanticType, bool> seen, bool mailbox_graph = false, bool affinity_only = false) {
		if (type is ClassType && ((ClassType) type).thread_bound) {
			return false;
		}
		if (affinity_only && type is ClosureHandleType) {
			if (seen.contains (type)) {
				return true;
			}
			seen.insert (type, true);
			return thread_capture_type (((ClosureHandleType) type).environment_type, seen, mailbox_graph, true);
		}
		var shared = type as SharedHandleType;
		if (shared != null && affinity_only) {
			return thread_capture_type (shared.payload_type, seen, mailbox_graph, true);
		}
		if (shared != null) {
			var payload = structs.lookup (shared.payload_type) as CfgClass;
			return payload != null && shared.payload_type.monitored && !shared.payload_type.thread_bound && (payload.allocation_policy == null || payload.allocation_policy.kind == AllocationKind.CONTEXT && payload.allocation_policy.context_mode == "owned-concurrent") && thread_capture_type (shared.payload_type, seen, mailbox_graph, affinity_only);
		}

		if (type is ClosureHandleType && ((ClosureHandleType) type).actor) {
			return !mailbox_graph && ((ClosureHandleType) type).supported ();
		}
		if (type is HandleType) {
			var context = ((HandleType) type).context_mode;
			return context != "" ? context == "owned-concurrent" : affinity_only;
		}
		if (type is RawPointerType || type is TypedPointerType) {
			return false;
		}
		if (type is StringType || FunctionValueType.scalar (type) || type is VectorType) {
			return true;
		}
		if (seen.contains (type)) {
			return true;
		}
		seen.insert (type, true);
		if (type is ContextBytesType && ((ContextBytesType) type).context_mode != "owned-concurrent") {
			return false;
		}
		if (type is SliceType) {
			return thread_capture_type (((SliceType) type).element_type, seen, mailbox_graph, affinity_only);
		}
		if (type is OwnerSlotsType) {
			return thread_capture_type (((OwnerSlotsType) type).element, seen, mailbox_graph, affinity_only);
		}
		var owner = structs.lookup (type);
		if (owner == null) {
			return false;
		}
		var object_class = owner as CfgClass;
		if (object_class != null && object_class.allocation_policy != null) {
			var policy = object_class.allocation_policy;
			if (policy.kind == AllocationKind.CONTEXT ? policy.context_mode != "owned-concurrent" : !affinity_only) {
				return false;
			}
		}
		if (!affinity_only && object_class != null && ((ClassType) type).intrinsically_shared && !((ClassType) type).monitored) {
			return false;
		}
		if (object_class != null && object_class.polymorphic) {
			foreach (var instance in structs.get_values ()) {
				var derived = instance as CfgClass;
				if (derived == null || derived == object_class) {
					continue;
				}
				for (var parent = derived.parent_class; parent != null; parent = parent.parent_class) {
					if (parent == object_class) {
						if (!thread_capture_type (derived.semantic_type, seen, mailbox_graph, affinity_only)) {
							return false;
						}
						break;
					}
				}
			}
		}
		foreach (var field in owner.fields) {
			if (!thread_capture_type (field.semantic_type, seen, mailbox_graph, affinity_only)) {
				return false;
			}
		}
		return object_class == null || object_class.parent_class == null || thread_capture_type (object_class.parent_class.semantic_type, seen, mailbox_graph, affinity_only);
	}

	private void verify_exact_class(CfgClass owner, CfgProgram program) throws CfgError {
		foreach (var field in owner.fields) {
			if (field.semantic_type is ExactGenericClassType && (!GenericClassTypes.general (field.semantic_type) || field.owned_cleanup == null || !field.owned_cleanup.is_heap_object)) {
				fail ("generic Class", "child fields require an owned closed general Class application");
			}
		}
		var key = owner.generic_instance;
		if ((key != null) != (owner.semantic_type is ExactGenericClassType)) {
			fail ("generic Class", "missing or forged exact specialization identity");
		}
		if (key == null) {
			foreach (var method in owner.methods) {
				if (method.generic_method_instance != null) {
					fail ("generic method", "requires its exact generic Class owner");
				}
			}
			return;
		}
		if (key.definition.structure != null) {
			CfgDeclaredClassAuthority.verify (program, owner, key);
			return;
		}
		int generic_count = 0;
		foreach (var method in owner.methods) {
			if (method.generic_method_instance != null) {
				generic_count++;
			}
		}
		if (!key.valid (owner.semantic_type) || owner.name != key.instance_type.name || owner.fields.length != 1 || owner.methods.length != key.definition.member_count - 1 + generic_count || owner.constructor == null || owner.destructor == null || owner.properties.length != key.definition.property_count || owner.polymorphic || owner.parent_class != null || owner.exception_root || !ExactClassGenericShape.field (key, owner.fields[0].semantic_type, owner.fields[0].name)) {
			fail ("generic Class", "exact definition/argument/field shape mismatch");
		}
		for (int p = 0; p < owner.properties.length; p++) {
			var property = owner.properties[p];
			var getter = property.getter;
			if (!ExactClassGenericShape.property (key, p, property.name, property.semantic_type) || property.ordinal != p || property.is_lazy || property.is_owned_lazy || property.is_borrowed || property.setter != null || property.factory != null) {
				fail ("generic property", "lost its exact computed declaration schema");
			}
			if (getter == null || getter.property_member != property || !program.functions.find (getter) || getter.return_type != property.semantic_type || getter.parameters.length != 0 || getter.result_contract != ResultOwnershipContract.UNMANAGED || getter.owned_cleanup != null || getter.heap_result || getter.async_body != null || getter.throws_type != null || getter.dispatch_kind != ClassDispatchKind.DIRECT) {
				fail ("generic property", "lost its direct copied getter signature");
			}
		}
		foreach (var other in program.classes) {
			var prior = other.generic_instance;
			if (other != owner && prior != null && prior.definition == key.definition && prior.argument == key.argument) {
				fail ("generic Class", "duplicate canonical specialization");
			}
		}
		for (int i = 0; i < key.definition.member_count; i++) {
			var operation = key.definition.operation (i);
			CfgFunction? function = operation == Astra.Source.ExactClassOperation.INITIALIZE ? (CfgFunction) owner.constructor : null;
			if (function == null) {
				foreach (var method in owner.methods) {
					if (method.name == key.definition.member_name (i)) {
						function = method;
					}
				}
			}
			if (function == null || !program.functions.find (function)) {
				fail ("generic Class", "missing exact specialized member");
			}
			var types = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			for (int p = 0; p < function.parameters.length;) {
				StructBoundaryGroup? record = null;
				foreach (var group in function.struct_parameters) {
					if (group.first_leaf == p) {
						record = group;
					}
				}
				if (record != null) {
					types.add (record.shape.semantic_type);
					contracts.add (PointerParameterContract.UNMANAGED);
					p += record.shape.leaves.length;
				} else {
					types.add (function.parameters[p].semantic_type);
					contracts.add (function.parameters[p].pointer_contract);
					p++;
				}
			}
			bool owned_result = key.definition.general_bodies && (key.argument is StructType) ? false : key.definition.general_bodies ? key.definition.signature (i).owned_result : operation == Astra.Source.ExactClassOperation.TAKE;
			if (function.async_body != null || function.throws_type != null || (owned_result ? function.owned_cleanup != owner.fields[0].slots_cleanup || function.heap_result != (key.argument is ClassType) : function.owned_cleanup != null) || function.dispatch_kind != ClassDispatchKind.DIRECT || !ExactClassGenericShape.signature (key, operation, function.return_type, types, contracts, function.parameters.length > 0 && function.parameters[function.parameters.length - 1].heap_object, i)) {
				fail ("generic Class", "specialized member signature mismatch");
			}
			if (key.definition.general_bodies) {
				continue;
			}
			if (function.blocks.length != 1) {
				fail ("generic Class", "finite member requires one direct operation block");
			}
			if (operation == Astra.Source.ExactClassOperation.RESERVE || operation == Astra.Source.ExactClassOperation.COUNT || operation == Astra.Source.ExactClassOperation.CAPACITY) {
				bool reserve = operation == Astra.Source.ExactClassOperation.RESERVE;
				if (function.entry.instructions.length != (reserve ? 2 : 1)) {
					fail ("generic Class", "query operation recipe mismatch");
				}
				var evaluation = function.entry.instructions[reserve ? 1 : 0] as CfgEvaluateInstruction;
				var query = evaluation == null ? null : evaluation.value as CfgSlotsValue;
				var returned = function.entry.terminator as CfgReturn;
				var receiver = query == null ? null : query.store.pointer as CfgReceiverValue;
				if (query == null || query.store.field != owner.fields[0] || receiver == null || receiver.receiver != function.implicit_receiver || returned == null || returned.value != evaluation.result || query.action != (reserve ? OwnerSlotsAction.RESERVE : operation == Astra.Source.ExactClassOperation.COUNT ? OwnerSlotsAction.LENGTH : OwnerSlotsAction.CAPACITY)) {
					fail ("generic Class", "query lost exact field/receiver/result operation");
				}
				if (reserve) {
					var argument = function.entry.instructions[0] as CfgEvaluateInstruction;
					var value = argument == null ? null : argument.value as CfgParameterValue;
					if (value == null || value.parameter != function.parameters[0] || query.operand != argument.result) {
						fail ("generic Class", "reserve lost exact requested parameter");
					}
				}
			} else {
				int count = 0;
				foreach (var instruction in function.entry.instructions) {
					CfgIndirectFieldPlace? place = null;
					if (operation == Astra.Source.ExactClassOperation.INITIALIZE && instruction is CfgSlotsInitialize) {
						place = ((CfgSlotsInitialize) instruction).store;
					}
					if (operation == Astra.Source.ExactClassOperation.APPEND && instruction is CfgSlotsAppend) {
						place = ((CfgSlotsAppend) instruction).store;
					}
					if (operation == Astra.Source.ExactClassOperation.REPLACE && instruction is CfgSlotsReplace) {
						place = ((CfgSlotsReplace) instruction).store;
					}
					if (operation == Astra.Source.ExactClassOperation.TAKE && instruction is CfgInitialize) {
						var take = ((CfgInitialize) instruction).value as CfgSlotsValue;
						if (take != null && take.action == OwnerSlotsAction.TAKE) {
							place = take.store;
						}
					}
					if (place != null) {
						var receiver = place.pointer as CfgReceiverValue;
						if (++count != 1 || place.field != owner.fields[0] || receiver == null || receiver.receiver != function.implicit_receiver) {
							fail ("generic Class", "effect lost exact specialized field/receiver");
						}
					}
				}
				if (count != 1) {
					fail ("generic Class", "missing exact specialized operation");
				}
			}
		}
		foreach (var method in owner.methods) {
			var request = method.generic_method_instance;
			if (request == null) {
				continue;
			}
			if (!key.definition.general_bodies || !request.valid (key) || method.name != request.name || !program.functions.find (method) || method.async_body != null || method.throws_type != null || method.dispatch_kind != ClassDispatchKind.DIRECT) {
				fail ("generic method", "lost exact declaration, Class instance or concrete direct body");
			}
			CopyabilityFields fields = (type) => {
				foreach (var enumeration in program.enums) {
					if (enumeration.semantic_type == type) {
						return enumeration.value_fields ();
					}
				}
				foreach (var record in program.structs) {
					if (record.semantic_type == type) {
						var result = new GenericArray<SemanticType> ();
						foreach (var field in record.fields) {
							result.add (field.semantic_type);
						}
						return result;
					}
				}
				return null;
			};
			if (!GenericArgumentTypes.plain_copy (request.argument, fields)) {
				fail ("generic method", "argument lost its exact recursive copy capability");
			}
			foreach (var prior in owner.methods) {
				var other = prior.generic_method_instance;
				if (prior != method && other != null && other.member == request.member && other.argument == request.argument) {
					fail ("generic method", "duplicate canonical method specialization");
				}
			}
			var types = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			for (int p = 0; p < method.parameters.length;) {
				StructBoundaryGroup? record = null;
				foreach (var group in method.struct_parameters) {
					if (group.first_leaf == p) {
						record = group;
					}
				}
				if (record != null) {
					types.add (record.shape.semantic_type);
					contracts.add (PointerParameterContract.UNMANAGED);
					p += record.shape.leaves.length;
				} else {
					types.add (method.parameters[p].semantic_type);
					contracts.add (method.parameters[p].pointer_contract);
					p++;
				}
			}
			var signature = key.definition.generic_method_signature (request.member);
			bool owned_result = signature.owned_result && !(key.argument is StructType);
			if ((owned_result ? method.owned_cleanup != owner.fields[0].slots_cleanup || method.heap_result != (key.argument is ClassType) : method.owned_cleanup != null) || !ExactClassGenericShape.signature (key, Astra.Source.ExactClassOperation.BODY, method.return_type, types, contracts, false, -1, request)) {
				fail ("generic method", "concrete parameter/result ownership or type differs from its declaration");
			}
		}
	}

	private HashTable<CfgUtf8FactoryValue, CfgFunction> utf8_values;
	private void verify_text_exits(CfgFunction function) throws CfgError {
		foreach (var block in function.blocks) {
			foreach (var authority in block.text_exits) {
				var actual = new GenericArray<Object> ();
				foreach (var instruction in block.instructions) {
					var end = instruction as CfgTextLoanEnd;
					if (end != null && end.exit_authority == authority) {
						if (actual.find (end.local)) {
							fail ("text loan exit authority", "duplicate end of the exact exited extent");
						}
						actual.add (end.local);
					}
				}
				if (!authority.matches (actual)) {
					fail ("text loan exit authority", "missing end or end of a surviving outer extent");
				}
			}
		}
	}

	private static bool heap_transfer(SemanticType source, CfgCleanupContract from, SemanticType target, CfgCleanupContract to) {
		return from.is_heap_object && to.is_heap_object && source is ClassType && target is ClassType && ((ClassType) source).derives_from ((ClassType) target) && (source == target || to.object_class.polymorphic);
	}

	private void verify_class_hierarchy(CfgProgram program) throws CfgError {
		var classes = new HashTable<CfgClass, bool> (direct_hash, direct_equal);
		foreach (var owner in program.classes) {
			classes.insert (owner, true);
		}
		CfgClass? nominated = null;
		foreach (var owner in program.structs) {
			var policy = owner.representation;
			var type = (StructType) owner.semantic_type;
			string[] names = {};
			string[] types = {};
			foreach (var field in owner.fields) {
				names += field.name;
				types += field.semantic_type.display_name ();
			}
			if (policy == null ? type.representation_identity != "" : !policy.matches (type.representation_identity, owner.name, names, types) || owner.methods.length != 0 || owner.properties.length != 0) {
				fail ("POD representation", "record lost its admitted natural C field order, scalar types or alignment");
			}
		}
		var allocation_domains = new Astra.Source.AllocationDomains ();
		foreach (var owner in program.classes) {
			if (!allocation_domains.admit (owner.allocation_policy)) {
				fail ("allocation domain", "conflicting or altered named policy");
			}
			verify_exact_class (owner, program);
			if (!Astra.Source.ForeignClassPolicy.matches (owner.foreign_export, ((ClassType) owner.semantic_type).foreign_policy_identity, owner.name) || (owner.parent_class != null && owner.parent_class.foreign_export != null)) {
				fail ("foreign Class policy", "lost its admitted native root or independent declaration");
			}
			if (owner.foreign_export != null) {
				var policy = owner.foreign_export;
				if (policy.declared_api != null) {
					if (!CfgForeignApi.valid (owner, program)) {
						fail ("foreign declared API", "lost exact native member binding, type, ownership or effect authority");
					}
				} else {
					if (owner.parent_class != null || owner.polymorphic || owner.exception_root || owner.generic_instance != null || owner.allocation_policy != null || owner.concurrency_policy == null || (owner.concurrency_policy.identity != 1 && owner.concurrency_policy.identity != 3) || owner.constructor == null || owner.constructor.throws_type != null || owner.constructor.parameters.length != 1 || owner.constructor.parameters[0].semantic_type.kind != TypeKind.INT || policy.property_ordinal >= owner.properties.length) {
						fail ("foreign Class policy", "requires its selected Shared heap root and exact int constructor");
					}
					var property = owner.properties[policy.property_ordinal];
					if (property.name != policy.property_name || property.ordinal != policy.property_ordinal || property.semantic_type.kind != TypeKind.INT || property.is_lazy || property.is_borrowed || property.getter == null || property.setter == null || property.getter.throws_type != null || property.setter.throws_type != null) {
						fail ("foreign Class policy", "lost its selected nonthrowing read/write int property");
					}
					foreach (var field in owner.fields) {
						if (field.semantic_type.kind != TypeKind.INT) {
							fail ("foreign Class policy", "requires copied int payload fields");
						}
					}
				}
			}
			if (owner.exception_root && owner.concurrency_policy != null) {
				fail ("exception policy", "native exception roots retain their unique lifetime contract");
			}
			if (owner.parent_class != null && ((ClassType) owner.parent_class.semantic_type).concurrency_policy_identity != ((ClassType) owner.semantic_type).concurrency_policy_identity) {
				fail ("Class concurrency policy", "inheritance lost one root policy authority");
			}
			if (owner.concurrency_policy != null && (owner.concurrency_policy.monitor || owner.concurrency_policy.thread_bound || owner.concurrency_policy.actor)) {
				foreach (var field in owner.fields) {
					if (!field.is_private) {
						fail ("protected state", "Monitor/ThreadBound fields require private compiler-mediated access");
					}
				}
			}
			if (owner.concurrency_policy != null && owner.concurrency_policy.actor && (owner.concurrency_policy.identity != 16 || owner.parent_class != null || owner.polymorphic || owner.allocation_policy != null)) {
				fail ("Actor policy", "requires an exact hosted receiver with transferable state and no sender cycles");
			}
			if (owner.concurrency_policy != null && owner.concurrency_policy.monitor) {
				foreach (var method in owner.methods) {
					if (method.async_body != null || !(FunctionValueType.scalar (method.return_type) || method.return_type.kind == TypeKind.VOID || method.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) {
						fail ("Monitor signature", "requires synchronous copied scalar/void or an owning snapshot");
					}
				}
				foreach (var property in owner.properties) {
					if (property.is_borrowed || !FunctionValueType.scalar (property.semantic_type)) {
						fail ("Monitor signature", "protected property borrow cannot escape its guard");
					}
				}
			}
			if (owner.concurrency_policy != null && owner.concurrency_policy.singleton) {
				if (owner.concurrency_policy.identity != 7 || owner.constructor == null || owner.parent_class != null || owner.polymorphic || owner.allocation_policy != null) {
					fail ("Singleton policy", "requires an exact hosted Shared Monitor root with an explicit constructor");
				}
				foreach (var field in owner.fields) {
					if (!(field.semantic_type is IntegerType || field.semantic_type is FloatingType || field.semantic_type.kind == TypeKind.BOOL)) {
						fail ("Singleton fields", "bounded initialization requires copied numeric state");
					}
				}
				foreach (var parameter in owner.constructor.parameters) {
					if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(parameter.semantic_type is IntegerType || parameter.semantic_type is FloatingType || parameter.semantic_type.kind == TypeKind.BOOL)) {
						fail ("Singleton constructor", "requires copied numeric inputs");
					}
				}
			}
			if (owner.constructor != null && owner.constructor.throws_type != null && !ConstructorContracts.admitted (owner.foreign_export, owner.allocation_policy, owner.constructor.member_ordinal, owner.constructor.throws_type) && (owner.concurrency_policy == null || !owner.concurrency_policy.singleton)) {
				fail ("checked constructor", "requires the bounded Singleton failure and retry protocol");
			}
			if (!Astra.Source.ConcurrencyPolicy.matches (owner.concurrency_policy, ((ClassType) owner.semantic_type).concurrency_policy_identity)) {
				fail ("Class concurrency policy", "lost its exact admitted declaration identity");
			}
			if (!Astra.Source.AllocationPolicy.matches (owner.allocation_policy, ((ClassType) owner.semantic_type).allocation_policy_identity) || owner.allocation_policy != null && (owner.polymorphic || owner.parent_class != null || owner.exception_root || ((ClassType) owner.semantic_type).is_interface)) {
				fail ("Class allocation policy", "requires its exact admitted nonpolymorphic declaration");
			}
			if (((ClassType) owner.semantic_type).is_interface && (owner.parent_class != null || owner.fields.length != 0 || owner.properties.length != 0 || owner.destructor != null || owner.methods.length == 0 || !owner.polymorphic)) {
				fail ("interface contract", "requires an exact fieldless abstract root");
			}
			if (((ClassType) owner.semantic_type).parent_type != (owner.parent_class == null ? null : owner.parent_class.semantic_type)) {
				fail ("class parent", "requires the exact nominal parent identity");
			}
			if (owner.exception_root) {
				if (nominated != null || owner.parent_class != null) {
					fail ("ExceptionRoot", "requires one unique root class");
				}
				nominated = owner;
			}
			var seen = new HashTable<CfgClass, bool> (direct_hash, direct_equal);
			int depth = 0;
			for (CfgClass? current = owner; current != null; current = current.parent_class) {
				if (!classes.contains (current) || seen.contains (current) || ++depth > 256) {
					fail ("class parent", "requires a bounded acyclic exact program-owned chain");
				}
				seen.insert (current, true);
			}
		}
		var complete = new HashTable<CfgClass, bool> (direct_hash, direct_equal);
		while (complete.size () != classes.size ()) {
			foreach (var owner in program.classes) {
				if (complete.contains (owner) || (owner.parent_class != null && !complete.contains (owner.parent_class))) {
					continue;
				}
				var expected = new GenericArray<CfgFunction> ();
				if (owner.parent_class != null) {
					foreach (var entry in owner.parent_class.virtual_entries) {
						expected.add (entry);
					}
				}
				var members = new GenericArray<CfgFunction> ();
				foreach (var member in owner.methods) {
					members.add (member);
				}
				foreach (var property in owner.properties) {
					members.add (property.getter);
				}
				foreach (var member in members) {
					var getter = member as CfgPropertyGetter;
					string name = getter == null ? member.name : getter.property_member.name;
					CfgFunction? prior = null;
					bool inherited_name = false;
					for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
						foreach (var field in ancestor.fields) {
							if (field.name == name) {
								inherited_name = true;
							}
						}
						foreach (var candidate in ancestor.methods) {
							if (candidate.name == name && !inherited_name) {
								prior = candidate;
								inherited_name = true;
							}
						}
						foreach (var property in ancestor.properties) {
							if (property.name == name && !inherited_name) {
								prior = property.getter;
								inherited_name = true;
							}
						}
					}
					if (member.dispatch_kind == ClassDispatchKind.DIRECT) {
						if (member.virtual_slot != -1 || inherited_name) {
							fail ("virtual slot", "direct member cannot carry a virtual slot or shadow an inherited member");
						}
						continue;
					}
					if (!owner.polymorphic || member.owned_cleanup != null || member.return_type is EnumType || member.return_type.is_struct_storage () || (getter != null && getter.property_member.setter != null)) {
						fail ("virtual slot", "bounded virtual member requires nonowning result and get-only property");
					}
					foreach (var parameter in member.parameters) {
						if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER || parameter.semantic_type is EnumType || parameter.semantic_type.is_struct_storage ()) {
							fail ("virtual slot", "bounded virtual parameter requires a nonowning plain value or borrow");
						}
					}
					if (member.dispatch_kind == ClassDispatchKind.VIRTUAL) {
						if (inherited_name || member.virtual_slot != expected.length) {
							fail ("virtual slot", "new virtual slot must have its exact declaration rank");
						}
						expected.add (member);
					} else if (member.dispatch_kind == ClassDispatchKind.OVERRIDE) {
						if (prior == null || prior.dispatch_kind == ClassDispatchKind.DIRECT || (getter == null) != (prior is CfgMethod) || prior.return_type != member.return_type || prior.result_contract != member.result_contract || member.parameters.length != prior.parameters.length || member.virtual_slot != prior.virtual_slot) {
							fail ("virtual override", "requires exact inherited slot kind, result and parameter grouping");
						}
						for (int p = 0; p < member.parameters.length; p++) {
							if (member.parameters[p].semantic_type != prior.parameters[p].semantic_type || member.parameters[p].pointer_contract != prior.parameters[p].pointer_contract) {
								fail ("virtual override", "requires exact parameter type and borrow contract");
							}
						}
						if (member.throws_type != null && (prior.throws_type == null || !member.throws_type.derives_from (prior.throws_type))) {
							fail ("virtual override", "cannot broaden the inherited checked bound");
						}
						expected.set (member.virtual_slot, member);
					} else {
						fail ("virtual slot", "invalid dispatch kind");
					}
				}
				foreach (var field in owner.fields) {
					for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
						foreach (var prior in ancestor.fields) {
							if (prior.name == field.name) {
								fail ("class field", "derived field cannot shadow an inherited field");
							}
						}
						foreach (var prior in ancestor.methods) {
							if (prior.name == field.name) {
								fail ("class field", "derived field cannot shadow an inherited method");
							}
						}
						foreach (var prior in ancestor.properties) {
							if (prior.name == field.name) {
								fail ("class field", "derived field cannot shadow an inherited property");
							}
						}
					}
				}
				if (owner.virtual_entries.length != expected.length) {
					fail ("virtual slots", "requires one complete exact inherited slot table");
				}
				for (int v = 0; v < expected.length; v++) {
					if (owner.virtual_entries[v] != expected[v]) {
						fail ("virtual slots", "slot must select the exact overriding implementation");
					}
				}
				if (!((ClassType) owner.semantic_type).is_interface) {
					foreach (var entry in owner.virtual_entries) {
						var requirement = entry as CfgMethod;
						if (requirement != null && requirement.declaring_type.semantic_type is ClassType && ((ClassType) requirement.declaring_type.semantic_type).is_interface) {
							fail ("interface dispatch", "concrete Class must replace every abstract operation");
						}
					}
				}
				foreach (var method in owner.methods) {
					bool readonly_contract = false;
					for (var ancestor = owner.parent_class; ancestor != null; ancestor = ancestor.parent_class) {
						if (((ClassType) ancestor.semantic_type).is_interface && method.virtual_slot >= 0 && method.virtual_slot < ancestor.virtual_entries.length) {
							readonly_contract = true;
						}
					}
					if (readonly_contract) {
						verify_interface_readonly (method);
					}
				}
				bool required = owner.parent_class != null || expected.length != 0;
				foreach (var child in program.classes) {
					if (child.parent_class == owner) {
						required = true;
					}
				}
				if (required != owner.polymorphic) {
					fail ("class header", "pay-for-use header must correspond to this participating hierarchy");
				}
				complete.insert (owner, true);
			}
		}
		if (nominated != null) {
			CfgProperty? message = null;
			foreach (var property in nominated.properties) {
				if (property.name == "message") {
					message = property;
				}
			}
			if (message == null || !(message.semantic_type is StringType) || message.setter != null || message.getter.dispatch_kind != ClassDispatchKind.VIRTUAL) {
				fail ("ExceptionRoot", "requires the exact virtual get-only receiver text message slot");
			}
		}
		foreach (var function in program.functions) {
			if (function.throws_type == null) {
				continue;
			}
			bool bound = false;
			foreach (var owner in program.classes) {
				if (owner.semantic_type == function.throws_type && nominated != null && function.throws_type.derives_from ((ClassType) nominated.semantic_type)) {
					bound = true;
				}
			}
			if (!bound || (function is CfgLifecycle && (!(function is CfgConstructor) || !ConstructorContracts.admitted (((CfgConstructor) function).declaring_class.foreign_export, ((CfgConstructor) function).declaring_class.allocation_policy, ((CfgConstructor) function).member_ordinal, function.throws_type) && (((CfgConstructor) function).declaring_class.concurrency_policy == null || !((CfgConstructor) function).declaring_class.concurrency_policy.singleton))) || (function is CfgPropertyAccessor && (!(function is CfgPropertyGetter) || !(((CfgPropertyAccessor) function).property_member.declaring_type is CfgClass) || ((CfgPropertyAccessor) function).property_member.setter != null || function.dispatch_kind != ClassDispatchKind.DIRECT || (!((CfgPropertyAccessor) function).property_member.is_owned_lazy && !PropertyValueTypes.supports_cache (function.return_type))))) {
				fail ("throws declaration", "requires an exact program-owned nominated exception subtype and native callable");
			}
			foreach (var exported in program.c_exports) {
				if (exported.target == function) {
					fail ("throws declaration", "private exception channel cannot cross a C export");
				}
			}
		}
	}

	private void verify_interface_readonly(CfgMethod method) throws CfgError {
		if (method.native_declaration != null) {
			verify_native_declaration (method, "native interface implementation");
			return;
		}
		foreach (var block in method.blocks) {
			foreach (var instruction in block.instructions) {
				// Short-circuit conditions join through a compiler temporary. This
				// stores a copied value without changing the receiver or an alias.
				var stored = instruction as CfgStore;
				if (stored != null && stored.target is CfgTemporaryPlace && FunctionValueType.scalar (stored.target.semantic_type)) {
					continue;
				}
				var initialized = instruction as CfgInitialize;
				if (initialized != null && initialized.target is CfgTemporaryPlace && initialized.acquisition == null &&
				    FunctionValueType.scalar (initialized.target.semantic_type)) {
					continue;
				}
				var evaluation = instruction as CfgEvaluateInstruction;
				if (evaluation == null) {
					fail ("interface read-only implementation", "calls, stores and ownership effects are excluded (%s)".printf (instruction.get_type ().name ()));
				}
				var value = evaluation.value;
				if (!(value is CfgIntegerValue || value is CfgBooleanValue || value is CfgParameterValue || value is CfgLoadValue || value is CfgPrefixValue || value is CfgBinaryValue || value is CfgIntegerShiftValue || value is CfgClassUpcast || value is CfgReceiverValue || value is CfgEvaluatedValue)) {
					fail ("interface read-only implementation", "requires copied scalar arithmetic and receiver field reads");
				}
			}
		}
	}

	private void verify_borrowed_getter(CfgPropertyAccessor accessor) throws CfgError {
		if (accessor.native_declaration != null) {
			verify_native_declaration (accessor, "borrowed native getter");
			if (!accessor.declaration_only ()) {
				fail ("borrowed native getter", "requires its sealed declaration block");
			}
			return;
		}
		if (accessor.blocks.length != 1 || accessor.locals.length != 0 || accessor.result_contract != ResultOwnershipContract.RECEIVER_BORROW || accessor.dispatch_kind != ClassDispatchKind.DIRECT) {
			fail ("borrowed getter", "requires one pure receiver projection block");
		}
		if (accessor.struct_result != null) {
			var block = accessor.blocks[0];
			var returned = block.terminator as CfgStructReturn;
			var validation = block.instructions.length == 0 ? null : block.instructions[0] as CfgValidatePlace;
			var root = validation == null ? null : validation.place as CfgIndirectFieldPlace;
			var receiver = root == null ? null : root.pointer as CfgReceiverValue;
			var shape = accessor.struct_result;
			if (shape.mode != StructValueMode.BORROW_VALUE || returned == null || returned.record_move != null || returned.shape != shape || returned.leaves.length != shape.leaves.length || block.instructions.length != shape.leaves.length + 1 || root == null || receiver == null || receiver.receiver != accessor.receiver || root.field.containing_type != accessor.property_member.declaring_type || root.semantic_type != accessor.return_type) {
				fail ("borrowed record getter", "requires one exact complete receiver field observation without ownership acquisition");
			}
			if (root.field.owned_cleanup == null || root.field.owned_cleanup.record_type == null || root.field.owned_cleanup.record_type.semantic_type != root.semantic_type || !cleanups.contains (root.field.owned_cleanup) || CopyabilityAuthority.of (root.semantic_type, struct_fields) == Copyability.COPYABLE) {
				fail ("borrowed record getter", "requires its exact receiver-owned record cleanup graph");
			}
			for (int i = 0; i < shape.leaves.length; i++) {
				var evaluation = block.instructions[i + 1] as CfgEvaluateInstruction;
				var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
				if (load == null || evaluation.result != returned.leaves[i] || !matches_struct_leaf (load.source, root, shape.leaves[i])) {
					fail ("borrowed record getter", "requires every exact ordered receiver-field leaf once");
				}
			}
			return;
		}
		var block = accessor.blocks[0];
		var returned = block.terminator as CfgReturn;
		var evaluation = block.instructions.length == 1 ? block.instructions[0] as CfgEvaluateInstruction : null;
		var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
		var place = load == null ? null : load.source as CfgIndirectFieldPlace;
		var receiver = place == null ? null : place.pointer as CfgReceiverValue;
		if (returned == null || evaluation == null || returned.value != evaluation.result || place == null || receiver == null || receiver.receiver != accessor.receiver || place.field.containing_type != accessor.property_member.declaring_type || !(place.semantic_type is ClassType || place.semantic_type is HandleType) || place.semantic_type != accessor.return_type) {
			fail ("borrowed getter", "requires one exact owned receiver-field projection without effects or result ownership");
		}
	}

	private void verify_text_getter(CfgPropertyAccessor accessor) throws CfgError {
		if (accessor.native_declaration != null) {
			verify_native_declaration (accessor, "native text getter");
			return;
		}
		if (accessor.blocks.length != 1 || accessor.locals.length != 0) {
			fail ("text getter", "requires one pure receiver snapshot or literal return block");
		}
		var block = accessor.blocks[0];
		var returned = block.terminator as CfgReturn;
		CfgValue? value = returned == null ? null : returned.value;
		uint remaining = block.instructions.length;
		if (remaining != 0) {
			var evaluation = block.instructions[remaining - 1] as CfgEvaluateInstruction;
			if (evaluation != null && evaluation.result == value) {
				value = evaluation.value;
				remaining--;
			}
		}
		var load = value as CfgLoadValue;
		var place = load == null ? null : load.source as CfgIndirectFieldPlace;
		var parent = remaining == 1 ? block.instructions[0] as CfgEvaluateInstruction : null;
		var cast = parent == null ? null : parent.value as CfgClassUpcast;
		var receiver = place == null ? null : (cast == null ? place.pointer : cast.reference) as CfgReceiverValue;
		bool backing = place != null && (cast == null ? remaining == 0 && place.field.containing_type == accessor.property_member.declaring_type : parent.result == place.pointer && cast.source_class == accessor.property_member.declaring_type && cast.target_class == place.field.containing_type);
		if (!(remaining == 0 && value is CfgTextValue || (receiver != null && receiver.receiver == accessor.receiver && place.field.text_snapshot && backing))) {
			fail ("text getter", "requires literal or exact readonly receiver snapshot backing without effects");
		}
	}

	private HashTable<EnumType, EnumDefinition> enum_definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private SemanticType? string_type;
	private HashTable<Astra.Text.TextBytes, bool> text_literals = new HashTable<Astra.Text.TextBytes, bool> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgNumericGuard> numeric_guards = new HashTable<CfgValue, CfgNumericGuard> (direct_hash, direct_equal);
	private HashTable<CfgBufferOwnerGroup, CfgLocalPlace> buffer_groups = new HashTable<CfgBufferOwnerGroup, CfgLocalPlace> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgIndirectFieldPlace> buffer_field_views = new HashTable<CfgEvaluatedValue, CfgIndirectFieldPlace> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgInstruction> resource_consumers = new HashTable<CfgEvaluatedValue, CfgInstruction> (direct_hash, direct_equal);
	private HashTable<CfgInstruction, CfgResourceCapture> resource_stores = new HashTable<CfgInstruction, CfgResourceCapture> (direct_hash, direct_equal);
	private HashTable<CfgCleanupInstruction, CfgCleanupInstruction> field_epilogues = new HashTable<CfgCleanupInstruction, CfgCleanupInstruction> (direct_hash, direct_equal);
	private CfgInstruction? current_instruction;
	private HashTable<CfgCleanupInstruction, CfgCleanupInstruction> resource_replacements = new HashTable<CfgCleanupInstruction, CfgCleanupInstruction> (direct_hash, direct_equal);

	private HashTable<Astra.Source.SuspensionLoanIdentity, bool> suspension_loan_ids = new HashTable<Astra.Source.SuspensionLoanIdentity, bool> (direct_hash, direct_equal);
	private HashTable<CfgStructCallResults, CfgInstruction> struct_results = new HashTable<CfgStructCallResults, CfgInstruction> (direct_hash, direct_equal);
	private HashTable<CfgCallResultValue, CfgStructCallResults> struct_result_leaves = new HashTable<CfgCallResultValue, CfgStructCallResults> (direct_hash, direct_equal);
	private HashTable<CfgStructCallResults, CfgStructResultConsume> consumed_struct_results = new HashTable<CfgStructCallResults, CfgStructResultConsume> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, CfgCallInstruction> result_candidates = new HashTable<CfgObjectStorage, CfgCallInstruction> (direct_hash, direct_equal);
	private HashTable<CfgResultObjectStorage, CfgFunction> result_inputs = new HashTable<CfgResultObjectStorage, CfgFunction> (direct_hash, direct_equal);
	private FieldInitializationState? field_state;
	private HashTable<CfgObjectStorage, CfgFunction> object_owners = new HashTable<CfgObjectStorage, CfgFunction> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, HashTable<CfgStructField, CfgObjectFieldPlace>> object_fields = new HashTable<CfgObjectStorage, HashTable<CfgStructField, CfgObjectFieldPlace>> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, CfgBlock> constructor_sites = new HashTable<CfgObjectStorage, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, CfgObjectStorage> available_constructors = new HashTable<CfgObjectStorage, CfgObjectStorage> (direct_hash, direct_equal);
	private HashTable<CfgObjectFieldPlace, CfgBlock> object_initializations = new HashTable<CfgObjectFieldPlace, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgObjectStorage, CfgObjectStorage> object_constructions = new HashTable<CfgObjectStorage, CfgObjectStorage> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgExceptionTake> exception_takes = new HashTable<CfgEvaluatedValue, CfgExceptionTake> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgCallSuccess> property_successes = new HashTable<CfgEvaluatedValue, CfgCallSuccess> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgValue> evaluated_sources = new HashTable<CfgEvaluatedValue, CfgValue> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgObjectValidateValue> object_validations = new HashTable<CfgEvaluatedValue, CfgObjectValidateValue> (direct_hash, direct_equal);
	private HashTable<SemanticType, ReceiverType> initializing_types = new HashTable<SemanticType, ReceiverType> (direct_hash, direct_equal);
	private HashTable<SemanticType, ReceiverType> receiver_types = new HashTable<SemanticType, ReceiverType> (direct_hash, direct_equal);
	private HashTable<CfgReceiver, CfgFunction> receiver_owners = new HashTable<CfgReceiver, CfgFunction> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgValue> slice_bounds_views = new HashTable<CfgValue, CfgValue> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgLocalPlace> bounds_storage = new HashTable<CfgValue, CfgLocalPlace> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, CfgBlock> array_initializations = new HashTable<CfgLocalPlace, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, CfgLocalPlace> available_arrays = new HashTable<CfgLocalPlace, CfgLocalPlace> (direct_hash, direct_equal);
	private HashTable<SemanticType, SliceType> slices = new HashTable<SemanticType, SliceType> (direct_hash, direct_equal);
	private GenericArray<ArrayType> arrays = new GenericArray<ArrayType> ();
	private CfgOwnedCallTransferCommit? pending_commit;
	private HashTable<CfgPendingOwnedArgument, CfgOwnedCallTransferCommit> committed_transfers = new HashTable<CfgPendingOwnedArgument, CfgOwnedCallTransferCommit> (direct_hash, direct_equal);
	private HashTable<CfgPendingOwnedArgument, CfgPendingOwnedArgument> used_transfers = new HashTable<CfgPendingOwnedArgument, CfgPendingOwnedArgument> (direct_hash, direct_equal);
	private HashTable<CfgOwnedReturnValue, CfgOwnedReturnValue> used_returns = new HashTable<CfgOwnedReturnValue, CfgOwnedReturnValue> (direct_hash, direct_equal);
	private HashTable<SemanticType, CfgHandle> handles = new HashTable<SemanticType, CfgHandle> (direct_hash, direct_equal);
	private HashTable<CfgOwnershipRearmInstruction, CfgOwnershipRearmInstruction> rearms = new HashTable<CfgOwnershipRearmInstruction, CfgOwnershipRearmInstruction> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgCleanupContract> owned_results = new HashTable<CfgValue, CfgCleanupContract> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgValue> consumed_results = new HashTable<CfgValue, CfgValue> (direct_hash, direct_equal);
	private CfgValue? pending_acquisition;
	private HashTable<CfgOwnershipReleaseInstruction, CfgOwnershipReleaseInstruction> releases = new HashTable<CfgOwnershipReleaseInstruction, CfgOwnershipReleaseInstruction> (direct_hash, direct_equal);
	private HashTable<CfgParameter, CfgParameter> contract_parameters = new HashTable<CfgParameter, CfgParameter> (direct_hash, direct_equal);
	private HashTable<CfgCleanupInstruction, CfgCleanupInstruction> cleanup_instructions = new HashTable<CfgCleanupInstruction, CfgCleanupInstruction> (direct_hash, direct_equal);
	private HashTable<CfgCleanupContract, CfgCleanupContract> cleanups = new HashTable<CfgCleanupContract, CfgCleanupContract> (direct_hash, direct_equal);
	private HashTable<CfgCFunction, CfgCFunction> c_functions = new HashTable<CfgCFunction, CfgCFunction> (direct_hash, direct_equal);
	private HashTable<CfgFunction, CfgFunction> functions = new HashTable<CfgFunction, CfgFunction> (direct_hash, direct_equal);
	private HashTable<CfgInstruction, CfgInstruction> calls = new HashTable<CfgInstruction, CfgInstruction> (direct_hash, direct_equal);
	private HashTable<CfgRecordFieldDrop, bool> record_field_epilogues = new HashTable<CfgRecordFieldDrop, bool> (direct_hash, direct_equal);
	private HashTable<CfgCallResultValue, CfgInstruction> results = new HashTable<CfgCallResultValue, CfgInstruction> (direct_hash, direct_equal);
	private HashTable<CfgCallResultValue, CfgCallResultValue> available_results = new HashTable<CfgCallResultValue, CfgCallResultValue> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgClassUpcast> class_upcasts = new HashTable<CfgEvaluatedValue, CfgClassUpcast> (direct_hash, direct_equal);
	private HashTable<CfgEvaluateInstruction, CfgEvaluateInstruction> evaluations = new HashTable<CfgEvaluateInstruction, CfgEvaluateInstruction> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgEvaluatedValue> evaluated_results = new HashTable<CfgEvaluatedValue, CfgEvaluatedValue> (direct_hash, direct_equal);
	private HashTable<CfgEvaluatedValue, CfgEvaluatedValue> available_evaluations = new HashTable<CfgEvaluatedValue, CfgEvaluatedValue> (direct_hash, direct_equal);
	private HashTable<CfgParameter, CfgFunction> owners = new HashTable<CfgParameter, CfgFunction> (direct_hash, direct_equal);
	private HashTable<CfgPlace, CfgFunction> place_owners = new HashTable<CfgPlace, CfgFunction> (direct_hash, direct_equal);
	private HashTable<CfgPlace, CfgPlace> initialized = new HashTable<CfgPlace, CfgPlace> (direct_hash, direct_equal);
	private HashTable<CfgBlock, CfgFunction> block_owners = new HashTable<CfgBlock, CfgFunction> (direct_hash, direct_equal);
	private HashTable<CfgValue, CfgBlock> definition_blocks = new HashTable<CfgValue, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgOwnedBorrowValue, CfgOwnedBorrowValue> borrow_definitions = new HashTable<CfgOwnedBorrowValue, CfgOwnedBorrowValue> (direct_hash, direct_equal);
	private HashTable<CfgOwnedBorrowValue, CfgOwnedBorrowValue> available_borrows = new HashTable<CfgOwnedBorrowValue, CfgOwnedBorrowValue> (direct_hash, direct_equal);
	private HashTable<CfgOwnedBorrowValue, CfgOwnedBorrowValue> used_borrows = new HashTable<CfgOwnedBorrowValue, CfgOwnedBorrowValue> (direct_hash, direct_equal);
	private CfgBlock current_block;
	private HashTable<int, SemanticType> integer_types = new HashTable<int, SemanticType> (direct_hash, direct_equal);
	private SemanticType? f32_type;
	private SemanticType? f64_type;
	private SemanticType? bool_type;
	private SemanticType? void_type;
	private HashTable<SemanticType, SemanticType> pointer_types = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);

	private HashTable<SemanticType, CfgNativeInstance> structs = new HashTable<SemanticType, CfgNativeInstance> (direct_hash, direct_equal);
	private GenericArray<SemanticType>? child_edges(SemanticType type) {
		var result = new GenericArray<SemanticType> ();
		var record = structs.lookup (type) as CfgStruct;
		if (record != null) {
			foreach (var field in record.fields) {
				if (field.semantic_type is ClassType || field.semantic_type is StructType) {
					result.add (field.semantic_type);
				}
			}
			return result;
		}
		for (var owner = structs.lookup (type) as CfgClass; owner != null; owner = owner.parent_class) {
			foreach (var property in owner.properties) {
				if (property.is_owned_lazy) {
					result.add (property.semantic_type);
				}
			}
			foreach (var field in owner.fields) {
				if (field.semantic_type is ClassType || field.semantic_type is StructType) {
					result.add (field.semantic_type);
				} else if (field.semantic_type is OwnerSlotsType) {
					result.add (((OwnerSlotsType) field.semantic_type).element);
				}
			}
		}
		return result;
	}

	private GenericArray<VectorType> vectors = new GenericArray<VectorType> ();

	private GenericArray<CfgFunction> scoped_constructions = new GenericArray<CfgFunction> ();
	private CfgVerifier () {
	}

	public static void verify(CfgProgram program) throws CfgError {
		foreach (var function in program.functions) {
			function.verify_vector_memory ();
		}
		foreach (var function in program.functions) {
			if (!function.floating_policy_valid ()) {
				throw new CfgError.INVALID_CFG ("floating policy differs from its admitted declaration");
			}
		}
		var verifier = new CfgVerifier ();
		verifier.caller_result_origins = new CfgCallerResultOrigins (program);
		verifier.utf8_values = CfgUtf8FactoryAuthority.authorize (program);
		foreach (var function in program.functions) {
			verifier.verify_native_declaration (function, "native declaration");
		}
		verifier.verify_program (program);
		verify_callback_effects (program);
		verifier.verify_class_type_arguments (program);
		CfgNonNull.verify (program);
		CfgTextOrigins.verify (program);
		foreach (var function in program.functions) {
			verifier.verify_text_exits (function);
		}
		foreach (var function in program.functions) {
			if (function.declaration_only ()) {
				continue;
			}
			CfgObjectLifecycleFlow.verify (function);
			CfgRecordObligations.verify (function);
			// Record boundaries also require ordering against adjacent scalar
			// owners. Other ownership diagnostics remain in CfgFlowChecker.
			bool record_owner = false;
			foreach (var local in function.locals) {
				if (local.cleanup != null && (local.cleanup.record_type != null || local.semantic_type.is_scoped_allocator ())) {
					record_owner = true;
					break;
				}
			}
			if (record_owner) {
				OwnershipFlow.analyze (function);
			}
		}
		CfgRuntimeLifetimes.verify (program, verifier.scoped_constructions);
	}

	private void verify_class_type_arguments(CfgProgram program) throws CfgError {
		int next = 0;
		foreach (var owner in program.classes) {
			var key = owner.generic_instance;
			if (key == null) {
				continue;
			}
			for (int a = 0; a < key.arguments.length; a++) {
				if (next >= program.class_type_arguments.length) {
					fail ("Class type arguments", "missing original nominal argument fact");
				}
				var argument = program.class_type_arguments[next++];
				if (!argument.matches (key, (ClassType) owner.semantic_type, a)) {
					fail ("Class type arguments", "nominal argument differs from its original exact Class key");
				}
				var type = argument.semantic_type;
				if (type is StructType || type is ClassType) {
					var declaration = structs.lookup (type);
					bool record = type is StructType && declaration is CfgStruct;
					bool object = type is ClassType && declaration is CfgClass;
					if (!record && !object) {
						fail ("Class type arguments", "nominal argument lost its exact stage-owned declaration");
					}
				} else {
					verify_type (type, true, "Class type argument");
				}
			}
		}
		if (next != program.class_type_arguments.length) {
			fail ("Class type arguments", "unexpected nominal argument fact");
		}
	}

	private void fail(string path, string message) throws CfgError {
		throw new CfgError.INVALID_CFG ("internal CFG verification error at %s: %s", path, message);
	}

	private GenericArray<CfgStruct> element_structs;
	private CfgArrayElementPlace? initializing_array_entry;
	private HashTable<CfgLocalPlace, GenericArray<CfgArrayInitialize>> record_initializations = new HashTable<CfgLocalPlace, GenericArray<CfgArrayInitialize>> (direct_hash, direct_equal);
	private HashTable<CfgArrayInitialize, CfgBlock> record_initialization_blocks = new HashTable<CfgArrayInitialize, CfgBlock> (direct_hash, direct_equal);
	private HashTable<CfgArrayInitialize, bool> verified_record_initializations = new HashTable<CfgArrayInitialize, bool> (direct_hash, direct_equal);
	private GenericArray<SemanticType>? element_fields(SemanticType type) {
		foreach (var structure in element_structs) {
			if (structure.semantic_type != type) {
				continue;
			}
			var result = new GenericArray<SemanticType> ();
			foreach (var field in structure.fields) {
				result.add (field.semantic_type);
			}
			return result;
		}
		return null;
	}

	private void verify_collection_element(SemanticType type, string path) throws CfgError {
		if (!type.is_struct_storage ()) {
			verify_type (type, true, path);
			return;
		}
		if (!BufferElementTypes.supports (type, element_fields)) {
			fail (path, "record collection element requires a complete copyable, zeroable, trivially destructible field graph; invalid path " + (BufferElementTypes.invalid_field (type, element_fields) ?? "<copy>"));
		}
	}

	private void verify_array_type(ArrayType array, string path) throws CfgError {
		if (!ArrayType.supports (array.element_type, array.length)) {
			fail (path, "unsupported array element or length; requires numeric storage and length 1..1024");
			return;
		}
		verify_collection_element (array.element_type, path + "/element");
		foreach (var prior in arrays) {
			if (prior.element_type == array.element_type && prior.length == array.length) {
				if (prior != array) {
					fail (path, "inconsistent array semantic type identity");
				}
				return;
			}
		}
		arrays.add (array);
	}

	private HashTable<CfgLazyDrop, bool> lazy_seen = new HashTable<CfgLazyDrop, bool> (direct_hash, direct_equal);
	private HashTable<CfgLazyDrop, bool> lazy_epilogues = new HashTable<CfgLazyDrop, bool> (direct_hash, direct_equal);
	private HashTable<CfgSlotsDrop, bool> slots_epilogues = new HashTable<CfgSlotsDrop, bool> (direct_hash, direct_equal);
	private void verify_slots_field(CfgStructField field, string path) throws CfgError {
		var type = field.semantic_type as OwnerSlotsType;
		var cleanup = field.slots_cleanup;
		if (type == null || !(field.containing_type is CfgClass) || ((CfgClass) field.containing_type).polymorphic || field.owned_cleanup != null || field.text_snapshot) {
			fail (path, "owner slots lost exact field authority");
		}
		if (field.ordinal < 0 || field.ordinal >= field.containing_type.fields.length || field.containing_type.fields[field.ordinal] != field) {
			fail (path, "owner-slot field requires its exact declared ordinal and identity");
		}
		if (type.element is StructType) {
			if (cleanup != null || struct_fields (type.element) == null) {
				fail (path, "record slots require an exact complete value layout without scalar cleanup");
			}
			try {
				StructLeafOrder.enumerate_storage (type.element, struct_fields);
			} catch (StructLeafError error) {
				fail (path, "record slots require a complete supported layout: " + error.message);
			}
			return;
		}
		if (cleanup == null || !cleanups.contains (cleanup)) {
			fail (path, "owner slots lost exact scalar cleanup authority");
		}
		if (type.element.get_type () == typeof (HandleType)) {
			if (cleanup.is_object || cleanup.is_buffer || cleanup.shared_type != null || cleanup.closure_type != null || !matches_cleanup (type.element, cleanup)) {
				fail (path, "owner slots lost the exact Resource declaration destructor");
			}
			return;
		}
		if (!cleanup.is_heap_object || cleanup.object_class == null || cleanup.object_class.semantic_type != type.element || structs.lookup (type.element) != cleanup.object_class || cleanup.object_class.polymorphic || cleanup.object_class.parent_class != null) {
			fail (path, "owner slots lost exact bounded heap Class cleanup");
		}
	}

	private void verify_slots_place(CfgIndirectFieldPlace store, CfgFunction function, bool read, string path) throws CfgError {
		if (function.async_body != null) {
			fail (path, "owner slots require synchronous code");
		}
		verify_place (store, function, path);
		verify_slots_field (store.field, path);
		var self = store.pointer as CfgReceiverValue;
		if (read && self != null && self.receiver.contract.mode == ReceiverMode.INITIALIZING && (field_state == null || !field_state.is_definite (store.field.ordinal))) {
			fail (path, "owner-slot read before initialization");
		}
	}

	private GenericArray<SemanticType>? slot_edges(SemanticType type) {
		var edges = child_edges (type);
		var parent = type as ClassType;
		if (parent != null) {
			foreach (var instance in structs.get_values ()) {
				var candidate = instance.semantic_type as ClassType;
				if (candidate != null && candidate != parent && candidate.derives_from (parent)) {
					foreach (var child in child_edges (candidate)) {
						edges.add (child);
					}
				}
			}
		}
		return edges;
	}

	private bool slot_alias(SemanticType candidate, SemanticType backing) {
		if (candidate is ReceiverType) {
			candidate = ((ReceiverType) candidate).instance_type;
		}
		return OwnedChildComposition.may_invalidate (candidate, backing, slot_edges);
	}

	private CfgProgram code_program;
	private CfgCodeOrigins? code_origins;
	private CodeEffectAnalysis? readonly_inference;
	private CfgFunction? readonly_scope;
	private CodeEffectSummary? readonly_result;
	public static CodeEffectAnalysis infer_effects(CfgProgram program) {
		var origins = new CfgCodeOrigins (program);
		var effects = create_effect_analysis (origins);
		foreach (var function in program.functions) {
			var parameters = new GenericArray<Object> ();
			var formals = new GenericArray<Object> ();
			for (int p = 0; p < function.parameters.length; p++) {
				var parameter = function.parameters[p];
				parameters.add (parameter);
				var signature = parameter.semantic_type as FunctionValueType;
				if (signature == null) {
					continue;
				}
				bool first_order = true;
				foreach (var type in signature.physical_parameters ()) {
					first_order &= !(type is FunctionValueType);
				}
				foreach (var group in function.struct_parameters) {
					first_order &= !(p >= group.first_leaf && p < group.first_leaf + group.shape.leaves.length);
				}
				if (first_order) {
					formals.add (parameter);
				}
			}
			var positions = new GenericArray<int> ();
			for (int p = 0; p < function.parameters.length; p++) {
				if (!(function.parameters[p].semantic_type is FunctionValueType)) {
					continue;
				}
				bool record_leaf = false;
				foreach (var group in function.struct_parameters) {
					record_leaf |= p >= group.first_leaf && p < group.first_leaf + group.shape.leaves.length;
				}
				if (!record_leaf) {
					positions.add (p);
				}
			}
			var declaration = function.native_declaration;
			effects.add_function (function, parameters, formals,
				declaration == null ? null : Astra.Code.CodeInputSet.decode (declaration.identity.scoped_readonly,
					declaration.identity.readonly_inputs, (int) parameters.length, positions),
				declaration == null ? null : Astra.Code.CodeInputSet.decode (true,
					declaration.identity.callback_inputs, (int) parameters.length, positions));
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as CfgCallInstruction;
					if (call == null || call.target == null) {
						continue;
					}
					bool protected_call = call.readonly_required;
					foreach (var argument in call.arguments) {
						protected_call |= argument is CfgSlotsLoan && (call.target.kind == CallableKind.METHOD || ((CfgSlotsLoan) argument).readonly_required);
					}
					effects.add_call (function, call.target, effect_arguments (call.arguments), protected_call);
				}
			}
		}
		var checker = new CfgVerifier ();
		foreach (var definition in program.functions) {
			checker.functions.insert (definition, definition);
		}
		foreach (var record in program.structs) {
			checker.structs.insert (record.semantic_type, record);
		}
		checker.readonly_inference = effects;
		effects.infer_readonly (checker.probe_readonly);
		effects.infer_requirements ();
		return effects;
	}

	private bool probe_readonly(Object function, CodeEffectSummary result) {
		scoped_inspectors.remove_all ();
		readonly_scope = (CfgFunction) function;
		readonly_result = result;
		try {
			scoped_inspector ((CfgFunction) function);
			return true;
		} catch (CfgError error) {
			return false;
		}
	}

	private static void verify_callback_effects(CfgProgram program) throws CfgError {
		bool needed = false;
		foreach (var function in program.functions) {
			var declaration = function.native_declaration;
			needed |= declaration != null && (declaration.identity.readonly_inputs != "" || declaration.identity.callback_inputs != "");
		}
		if (!needed) {
			return;
		}
		var effects = infer_effects (program);
		foreach (var function in program.functions) {
			var required = effects.required_summary (function);
			if (required == null || !required.eligible) {
				throw new CfgError.INVALID_CFG ("native callback inputs require independently proved readonly code");
			}
		}
	}

	// Vala shares closure storage within one method. Keep this long-lived
	// frontier separate from probes that capture the analysis or its owner.
	private static CodeEffectAnalysis create_effect_analysis(CfgCodeOrigins origins) {
		return new CodeEffectAnalysis ((value, formals) => origins.effect_frontier (value, formals));
	}

	private static GenericArray<Object> effect_arguments(GenericArray<CfgValue> values) {
		var result = new GenericArray<Object> ();
		foreach (var value in values) {
			result.add (value);
		}
		return result;
	}

	private void scoped_call(CfgFunction target, GenericArray<CfgValue> arguments) throws CfgError {
		if (readonly_inference == null) {
			scoped_inspector (target);
		} else if (!readonly_inference.call (target, effect_arguments (arguments), readonly_scope, readonly_result)) {
			fail ("readonly scoped inspector", "unproved conditional direct call effect");
		}
	}

	private HashTable<CfgFunction, bool> scoped_inspectors = new HashTable<CfgFunction, bool> (direct_hash, direct_equal);
	private bool scoped_copied(SemanticType type) {
		if (FunctionValueType.scalar (type) || type is FunctionValueType || type is StringType) {
			return true;
		}
		if (!(type is StructType)) {
			return false;
		}
		try {
			foreach (var leaf in StructLeafOrder.enumerate (type, struct_fields)) {
				if (!FunctionValueType.scalar (leaf.semantic_type)) {
					return false;
				}
			}
		} catch (StructLeafError error) {
			return false;
		}
		return true;
	}

	private bool scoped_local(CfgPlace place) {
		while (place is CfgFieldPlace) {
			place = ((CfgFieldPlace) place).aggregate;
		}
		return place is CfgLocalPlace || place is CfgTemporaryPlace;
	}

	private bool scoped_writable(CfgPlace place) {
		while (place is CfgFieldPlace) {
			place = ((CfgFieldPlace) place).aggregate;
		}
		var local = place as CfgLocalPlace;
		return local != null ? local.struct_parameter == null || local.struct_parameter.shape.mode != StructValueMode.BORROW_VALUE : place is CfgTemporaryPlace;
	}

	private void scoped_place(CfgPlace place) throws CfgError {
		if (scoped_local (place)) {
			return;
		}
		if (place is CfgSliceElementPlace) {
			var element = (CfgSliceElementPlace) place;
			scoped_value (element.slice);
			scoped_value (element.index);
			return;
		}
		if (place is CfgFieldPlace) {
			scoped_place (((CfgFieldPlace) place).aggregate);
			return;
		}
		if (place is CfgIndirectFieldPlace) {
			scoped_value (((CfgIndirectFieldPlace) place).pointer);
			return;
		}
		fail ("readonly scoped inspector", "cannot read unproved indirect storage");
	}

	private void scoped_value(CfgValue value) throws CfgError {
		if (value is CfgSliceLengthValue) {
			scoped_value (((CfgSliceLengthValue) value).slice);
			return;
		}
		if (value is CfgRecordBufferView) {
			scoped_value (((CfgRecordBufferView) value).source);
			return;
		}
		if (value is CfgRecordParameterBufferView) {
			scoped_value (((CfgRecordParameterBufferView) value).source);
			return;
		}
		if (value is CfgIntegerValue || value is CfgFloatValue || value is CfgBooleanValue || value is CfgTextValue || value is CfgNullPointerValue || value is CfgParameterValue || value is CfgReceiverValue || value is CfgEvaluatedValue || value is CfgCallResultValue || value is CfgSlotsLoan || value is CfgFunctionAddress) {
			return;
		}
		if (value is CfgLoadValue) {
			scoped_place (((CfgLoadValue) value).source);
			return;
		}
		if (value is CfgObjectValidateValue) {
			scoped_value (((CfgObjectValidateValue) value).reference);
			return;
		}
		if (value is CfgClassUpcast) {
			scoped_value (((CfgClassUpcast) value).reference);
			return;
		}
		if (value is CfgPrefixValue) {
			scoped_value (((CfgPrefixValue) value).operand);
			return;
		}
		if (value is CfgBinaryValue) {
			scoped_value (((CfgBinaryValue) value).left);
			scoped_value (((CfgBinaryValue) value).right);
			return;
		}
		if (value is CfgIntegerShiftValue) {
			scoped_value (((CfgIntegerShiftValue) value).operand);
			scoped_value (((CfgIntegerShiftValue) value).count);
			return;
		}
		if (value is CfgIntegerConversionValue) {
			scoped_value (((CfgIntegerConversionValue) value).operand);
			return;
		}
		if (value is CfgFloatConversionValue) {
			scoped_value (((CfgFloatConversionValue) value).operand);
			return;
		}
		if (value is CfgNumericConversionValue) {
			scoped_value (((CfgNumericConversionValue) value).operand);
			return;
		}
		if (value is CfgSlotsValue) {
			var query = (CfgSlotsValue) value;
			if (query.action != OwnerSlotsAction.LENGTH && query.action != OwnerSlotsAction.CAPACITY) {
				fail ("readonly scoped inspector", "cannot mutate collection storage");
			}
			scoped_place (query.store);
			return;
		}
		if (value is CfgFunctionValueCall) {
			var call = (CfgFunctionValueCall) value;
			var signature = (FunctionValueType) call.callee.semantic_type;
			bool requires_target = false;
			foreach (var parameter in signature.physical_parameters ()) {
				requires_target |= !FunctionValueType.scalar (parameter);
			}
			if (requires_target) {
				if (readonly_inference != null) {
					if (!readonly_inference.code (call.callee, readonly_scope, readonly_result, effect_arguments (call.arguments))) {
						fail ("readonly scoped inspector", "unproved declarative callback origin or invocation context");
					}
					scoped_value (call.callee);
					foreach (var argument in call.arguments) {
						scoped_value (argument);
					}
					return;
				}
				if (code_origins == null) {
					code_origins = new CfgCodeOrigins (code_program);
				}
				var targets = code_origins.targets (call.callee);
				if (targets == null) {
					fail ("readonly scoped inspector", "indirect call requires independently proved code targets");
				}
				foreach (var target in targets) {
					scoped_inspector (target);
				}
			}
			scoped_value (call.callee);
			foreach (var argument in call.arguments) {
				scoped_value (argument);
			}
			return;
		}
		fail ("readonly scoped inspector", "unproved value effect: " + value.get_type ().name ());
	}

	private void scoped_inspector(CfgFunction target) throws CfgError {
		if (!functions.contains (target) || target.async_body != null || target.throws_type != null || target.dispatch_kind != ClassDispatchKind.DIRECT || target.result_contract == ResultOwnershipContract.OWNED_TRANSFER || target is CfgLifecycle) {
			fail ("readonly scoped inspector", "requires a direct synchronous nonconsuming definition");
		}
		var getter = target as CfgPropertyGetter;
		if (getter != null && getter.property_member.is_lazy) {
			fail ("readonly scoped inspector", "lazy access may mutate receiver storage");
		}
		foreach (var parameter in target.parameters) {
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				fail ("readonly scoped inspector", "cannot consume an owner");
			}
		}
		if (target.struct_result != null && target.struct_result.mode == StructValueMode.MOVE_VALUE) {
			fail ("readonly scoped inspector", "cannot consume owning record channels");
		}
		foreach (var group in target.struct_parameters) {
			if (group.shape.mode == StructValueMode.MOVE_VALUE) {
				fail ("readonly scoped inspector", "cannot consume owning record channels");
			}
		}
		if (target.span.file.native_interface) {
			verify_native_declaration (target, "readonly native inspector");
			if (target.native_declaration == null || !target.native_declaration.identity.scoped_readonly) {
				fail ("readonly scoped inspector", "requires its original native readonly effect contract");
			}
			return;
		}
		if (scoped_inspectors.contains (target)) {
			return;
		}
		scoped_inspectors.insert (target, true);
		foreach (var block in target.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is CfgInitialize) {
					var initial = (CfgInitialize) instruction;
					if (initial.acquisition != null || !scoped_writable (initial.target) || !scoped_copied (initial.target.semantic_type)) {
						fail ("readonly scoped inspector", "initialization cannot mutate observed storage");
					}
					scoped_value (initial.value);
				} else if (instruction is CfgStore) {
					var store = (CfgStore) instruction;
					if (!scoped_writable (store.target) || !scoped_copied (store.target.semantic_type)) {
						fail ("readonly scoped inspector", "cannot write object fields or indirect storage");
					}
					scoped_value (store.value);
				} else if (instruction is CfgEvaluateInstruction) {
					scoped_value (((CfgEvaluateInstruction) instruction).value);
				} else if (instruction is CfgValidatePlace) {
					scoped_place (((CfgValidatePlace) instruction).place);
				} else if (instruction is CfgSliceBoundsCheck) {
					var bounds = (CfgSliceBoundsCheck) instruction;
					scoped_value (bounds.slice);
					scoped_value (bounds.value);
				} else if (instruction is CfgCallInstruction) {
					var call = (CfgCallInstruction) instruction;
					if (call.receiver != null) {
						scoped_value (call.receiver);
					}
					foreach (var argument in call.arguments) {
						scoped_value (argument);
					}
					scoped_call (call.target, call.arguments);
				} else if (instruction is CfgCCallInstruction) {
					var call = (CfgCCallInstruction) instruction;
					foreach (var argument in call.arguments) {
						if (!scoped_copied (argument.semantic_type) || argument.semantic_type is FunctionValueType) {
							fail ("readonly scoped inspector", "foreign arguments cannot expose mutable aliases");
						}
						scoped_value (argument);
					}
					if (call.target.return_type.kind != TypeKind.VOID && !scoped_copied (call.target.return_type)) {
						fail ("readonly scoped inspector", "foreign result cannot acquire a pointer or owner");
					}
				} else if (instruction is CfgStructInvoke) {
					var invoked = (CfgStructInvoke) instruction;
					if (invoked.checked_call != null || invoked.results.shape.mode != StructValueMode.COPY_VALUE) {
						fail ("readonly scoped inspector", "indirect observation requires an exact infallible copied result");
					}
					scoped_value (invoked.call);
				} else if (instruction is CfgStructResultConsume) {
					var consumption = (CfgStructResultConsume) instruction;
					if (consumption.results.shape.mode != StructValueMode.COPY_VALUE && !(consumption.results.shape.mode == StructValueMode.BORROW_VALUE && consumption.use_kind == StructResultUseKind.OBSERVE)) {
						fail ("readonly scoped inspector", "cannot consume owning record results");
					}
				} else if (instruction is CfgStructParameterBorrow) {
					var binding = (CfgStructParameterBorrow) instruction;
					if (binding.parameter.shape.mode != StructValueMode.BORROW_VALUE || binding.destination.cleanup != null) {
						fail ("readonly scoped inspector", "record parameter observation cannot acquire cleanup");
					}
					foreach (var leaf in binding.leaves) {
						scoped_value (leaf);
					}
				} else if (instruction is CfgStructBoundaryAcquire) {
					var acquire = (CfgStructBoundaryAcquire) instruction;
					if (acquire.shape.mode != StructValueMode.COPY_VALUE || !scoped_local (acquire.target)) {
						fail ("readonly scoped inspector", "record acquisition cannot change observed ownership");
					}
					foreach (var leaf in acquire.leaves) {
						scoped_value (leaf);
					}
				} else if (instruction is CfgSlotsBorrow) {
					scoped_place (((CfgSlotsBorrow) instruction).result.store);
				} else {
					fail ("readonly scoped inspector", "unproved instruction effect: " + instruction.get_type ().name ());
				}
			}
			if (block.terminator is CfgStructReturn) {
				foreach (var leaf in ((CfgStructReturn) block.terminator).leaves) {
					scoped_value (leaf);
				}
			} else if (block.terminator is CfgReturn) {
				var returned = ((CfgReturn) block.terminator).value;
				if (returned != null) {
					scoped_value (returned);
				}
			} else if (block.terminator is CfgConditionalBranch) {
				scoped_value (((CfgConditionalBranch) block.terminator).condition);
			} else if (!(block.terminator is CfgBranch || block.terminator is CfgFunctionEnd)) {
				fail ("readonly scoped inspector", "cannot suspend or expose a checked failure");
			}
		}
	}

	private bool slots_invalidates(CfgInstruction instruction, SemanticType backing, bool readonly_receiver = false) {
		CfgIndirectFieldPlace? store = (instruction is CfgSlotsReplace) ? ((CfgSlotsReplace) instruction).store : (instruction is CfgSlotsAppend) ? ((CfgSlotsAppend) instruction).store : (instruction is CfgSlotsDrop) ? ((CfgSlotsDrop) instruction).store : (instruction is CfgSlotsInitialize) ? ((CfgSlotsInitialize) instruction).store : (instruction is CfgStore) ? ((CfgStore) instruction).target as CfgIndirectFieldPlace : null;
		if (store != null && slot_alias (store.field.containing_type.semantic_type, backing)) {
			return true;
		}
		var acquisition = instruction as CfgInitialize;
		var take = acquisition == null ? null : acquisition.value as CfgSlotsValue;
		if (take != null && take.action == OwnerSlotsAction.TAKE && slot_alias (take.store.field.containing_type.semantic_type, backing)) {
			return true;
		}
		var eval = instruction as CfgEvaluateInstruction;
		var reserve = eval == null ? null : eval.value as CfgSlotsValue;
		if (reserve != null && reserve.action == OwnerSlotsAction.RESERVE && slot_alias (reserve.store.field.containing_type.semantic_type, backing)) {
			return true;
		}
		var cleanup = instruction as CfgCleanupInstruction;
		if (cleanup != null && slot_alias (cleanup.value.semantic_type, backing)) {
			return true;
		}
		var release = instruction as CfgOwnershipReleaseInstruction;
		if (release != null && slot_alias (release.owner.semantic_type, backing)) {
			return true;
		}
		var transfer = instruction as CfgOwnershipTransferInstruction;
		if (transfer != null && slot_alias (transfer.source.semantic_type, backing)) {
			return true;
		}
		var call = instruction as CfgCallInstruction;
		if (call != null) {
			if (!readonly_receiver && call.receiver != null && slot_alias (call.receiver.semantic_type, backing)) {
				return true;
			}
			foreach (var argument in call.arguments) {
				if (slot_alias (argument.semantic_type, backing)) {
					return true;
				}
			}
		}
		return false;
	}

	private bool slots_reaches(CfgBlock start, CfgBlock target) {
		var pending = new GenericArray<CfgBlock> ();
		var seen = new HashTable<CfgBlock, bool> (direct_hash, direct_equal);
		pending.add (start);
		for (int n = 0; n < pending.length; n++) {
			var block = pending[n];
			if (block == target) {
				return true;
			}
			if (seen.contains (block)) {
				continue;
			}
			seen.insert (block, true);
			foreach (var next in block.terminator.successors ()) {
				pending.add (next);
			}
		}
		return false;
	}

	private void verify_slots_loans(CfgFunction function) throws CfgError {
		foreach (var origin in function.blocks) {
			for (int i = 0; i < origin.instructions.length; i++) {
				var borrow = origin.instructions[i] as CfgSlotsBorrow;
				if (borrow == null) {
					continue;
				}
				var loan = borrow.result;
				CfgCallInstruction? consumer = null;
				CfgBlock? consumer_block = null;
				int consumers = 0;
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as CfgCallInstruction;
						if (call == null) {
							continue;
						}
						for (int a = 0; a < call.arguments.length; a++) {
							if (call.arguments[a] == loan) {
								consumers++;
								consumer = call;
								consumer_block = block;
								if (a >= call.target.parameters.length || call.target.parameters[a] != loan.borrower || (call.target.kind != CallableKind.FUNCTION && call.target.kind != CallableKind.METHOD) || call.target.async_body != null || call.target.throws_type != null || !(FunctionValueType.scalar (call.target.return_type) || call.target.return_type.kind == TypeKind.VOID || call.target.return_type.is_struct_storage () && scoped_copied (call.target.return_type))) {
									fail ("owner-slot loan", "lost exact concrete synchronous inspection call");
								}
							}
						}
					}
				}
				if (consumers != 1) {
					fail ("owner-slot loan", "requires one exact native call consumer");
				}
				if (!loan.readonly_context_valid ()) {
					fail ("owner-slot loan", "lost original readonly iteration context");
				}
				bool readonly_receiver = consumer.target.kind == CallableKind.METHOD || loan.readonly_required;
				if (readonly_receiver) {
					scoped_inspector (consumer.target);
				}
				var backing = loan.store.field.containing_type.semantic_type;
				if (slots_invalidates (consumer, backing, readonly_receiver)) {
					fail ("owner-slot loan", "inspection call carries an overlapping container alias");
				}
				var pending = new GenericArray<CfgBlock> ();
				var seen = new HashTable<CfgBlock, bool> (direct_hash, direct_equal);
				pending.add (origin);
				for (int n = 0; n < pending.length; n++) {
					var block = pending[n];
					if (seen.contains (block)) {
						continue;
					}
					seen.insert (block, true);
					if (!slots_reaches (block, consumer_block)) {
						continue;
					}
					bool finished = false;
					for (int j = block == origin ? i + 1 : 0; j < block.instructions.length; j++) {
						var instruction = block.instructions[j];
						if (instruction == consumer) {
							finished = true;
							break;
						}
						if (slots_invalidates (instruction, backing)) {
							fail ("owner-slot loan", "mutation or destruction crosses indexed loan capture and call");
						}
					}
					if (!finished) {
						foreach (var next in block.terminator.successors ()) {
							pending.add (next);
						}
					}
				}
			}
		}
	}

	private void verify_invocation_result(CfgInvocation call, CallableSignature? signature, string path) throws CfgError {
		var value = (CfgValue) call;
		var cleanup = call.result_cleanup ();
		if (signature == null || !FunctionValueType.supported_result (value.semantic_type, signature.result_contract)
		    || (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER
		            ? cleanup == null || !cleanups.contains (cleanup) || !matches_cleanup (value.semantic_type, cleanup) || value.semantic_type is ClassType && !cleanup.is_heap_object
		            : cleanup != null)) {
			fail (path, "indirect result lost its exact declared ownership and cleanup contract");
		}
		if (cleanup != null) {
			var evaluation = current_instruction as CfgEvaluateInstruction;
			if (evaluation == null || evaluation.value != value || (!(evaluation is CfgCheckedClosureInvoke) && owned_results.lookup (evaluation.result) != cleanup)) {
				fail (path, "indirect owned result requires one captured producer definition");
			}
		}
	}

	private void verify_type(SemanticType? semantic_type, bool requires_value, string path) throws CfgError {
		if (semantic_type is ClosureHandleType && !((ClosureHandleType) semantic_type).actor) {
			var signature = (ClosureHandleType) semantic_type;
			try {
				signature.verify_records (signature.record_parameters, struct_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
		}
		if (semantic_type is FunctionValueType) {
			var signature = (FunctionValueType) semantic_type;
			if ((signature is CallbackType) ? !((CallbackType) signature).supported () : !FunctionValueType.supported_result (signature.result_type, signature.result_contract) || signature.parameter_types.length > 4) {
				fail (path, "function value requires a bounded copied scalar signature");
			}
			try {
				signature.verify_records (signature.record_parameters, struct_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			return;
		}
		if (semantic_type is ExecutorType || semantic_type is TaskType) {
			return;
		}
		if (semantic_type == null) {
			fail (path, "missing semantic type");
			return;
		}
		if (semantic_type is EnumType) {
			if (!enum_definitions.contains ((EnumType) semantic_type)) {
				fail (path, "enum requires exact program-owned nominal definition");
			}
			return;
		}
		if (semantic_type.kind == TypeKind.STRING) {
			if (!(semantic_type is StringType) || (string_type != null && string_type != semantic_type)) {
				fail (path, "text requires canonical StringType identity");
			}
			string_type = semantic_type;
			return;
		}
		if (semantic_type.kind == TypeKind.RECEIVER) {
			var receiver = semantic_type as ReceiverType;
			if (receiver == null || (receiver.mode == ReceiverMode.INITIALIZING ? initializing_types : receiver_types).lookup (receiver.instance_type) != receiver) {
				fail (path, "receiver requires exact declared instance type and compiler-owned contract");
			}
			return;
		}
		if (semantic_type.kind == TypeKind.SLICE) {
			var slice = semantic_type as SliceType;
			if (slice == null || !SliceType.supports (slice.element_type)) {
				fail (path, "unsupported slice element; requires exact supported storage or text descriptor type");
				return;
			}
			verify_collection_element (slice.element_type, path + "/element");
			if (slice is ContextBytesType) {
				var bytes = (ContextBytesType) slice;
				if (!bytes.valid ()) {
					fail (path, "context byte pair lost its exact owned allocator contract");
				}
				verify_type (bytes.allocator_type, true, path + "/allocator");
			}
			var prior = slices.lookup (slice.canonical_key ());
			if (prior != null && prior != slice) {
				fail (path, "inconsistent slice semantic type identity");
			}
			slices.insert (slice.canonical_key (), slice);
			return;
		}
		if (semantic_type.kind == TypeKind.VECTOR) {
			var vector = semantic_type as VectorType;
			if (vector == null || !VectorType.supports (vector.element_type, vector.lane_count)) {
				fail (path, "unsupported vector element or lane shape");
				return;
			}
			verify_type (vector.element_type, true, path + "/element");
			foreach (var prior in vectors) {
				if (prior.element_type == vector.element_type && prior.lane_count == vector.lane_count) {
					if (prior != vector) {
						fail (path, "inconsistent vector semantic type identity");
					}
					return;
				}
			}
			vectors.add (vector);
			return;
		}
		switch (semantic_type.kind) {
		case TypeKind.INT:
		case TypeKind.I8:
		case TypeKind.U8:
		case TypeKind.I16:
		case TypeKind.U16:
		case TypeKind.U32:
		case TypeKind.I64:
		case TypeKind.U64:
		case TypeKind.ISIZE:
		case TypeKind.USIZE:
			var prior_integer = integer_types.lookup ((int) semantic_type.kind);
			if (prior_integer != null && prior_integer != semantic_type) {
				fail (path, "inconsistent '%s' semantic type identity".printf (semantic_type.display_name ()));
			}
			if (!(semantic_type is IntegerType)) {
				fail (path, "integer type requires immutable IntegerType authority");
			}
			integer_types.insert ((int) semantic_type.kind, semantic_type);
			break;
		case TypeKind.F32:
			if (!(semantic_type is F32Type)) {
				fail (path, "f32 type requires immutable F32Type authority");
			}
			if (f32_type != null && f32_type != semantic_type) {
				fail (path, "inconsistent 'f32' semantic type identity");
			}
			f32_type = semantic_type;
			break;
		case TypeKind.F64:
			if (!(semantic_type is F64Type)) {
				fail (path, "f64 type requires immutable F64Type authority");
			}
			if (f64_type != null && f64_type != semantic_type) {
				fail (path, "inconsistent 'f64' semantic type identity");
			}
			f64_type = semantic_type;
			break;
		case TypeKind.BOOL:
			if (bool_type != null && bool_type != semantic_type) {
				fail (path, "inconsistent 'bool' semantic type identity");
			}
			bool_type = semantic_type;
			break;
		case TypeKind.CLASS:
			if (!(semantic_type is ClassType) || !(structs.lookup (semantic_type) is CfgClass)) {
				fail (path, "class reference requires exact program-owned nominal identity");
			}
			break;
		case TypeKind.HANDLE:
			if (!(semantic_type is HandleType) || !handles.contains (semantic_type)) {
				fail (path, "handle value requires exact declared nominal type identity");
			}
			break;
		case TypeKind.TYPED_POINTER:
			var typed = semantic_type as TypedPointerType;
			if (typed == null || !typed.pointee.is_typed_data_pointee ()) {
				fail (path, "unsupported typed data pointer pointee");
				return;
			}
			if (typed.pointee is StructType) {
				if (!structs.contains (typed.pointee)) {
					fail (path, "typed pointer requires exact program-owned struct identity");
				}
				if (record_field (typed.pointee) != null) {
					fail (path, "owning record pointers are deferred");
				}
			} else {
				verify_type (typed.pointee, true, path + "/pointee");
			}
			var prior_pointer = pointer_types.lookup (typed.pointee);
			if (prior_pointer != null && prior_pointer != typed) {
				fail (path, "inconsistent typed pointer semantic type identity");
			}
			pointer_types.insert (typed.pointee, typed);
			break;
		case TypeKind.RAW_POINTER:
			var pointer = semantic_type as RawPointerType;
			if (pointer == null || pointer.pointee.kind != TypeKind.VOID) {
				fail (path, "raw pointer must point to void");
				return;
			}
			if (pointer.pointee.kind == TypeKind.VOID) {
				verify_type (pointer.pointee, false, path + "/pointee");
			}
			var previous = pointer_types.lookup (pointer.pointee);
			if (previous != null && previous != pointer) {
				fail (path, "inconsistent '%s' semantic type identity".printf (pointer.display_name ()));
			}
			pointer_types.insert (pointer.pointee, pointer);
			break;
		case TypeKind.VOID:
			if (requires_value) {
				fail (path, "value or parameter type must be 'int', 'bool' or 'void*', found 'void'");
			}
			if (void_type != null && void_type != semantic_type) {
				fail (path, "inconsistent 'void' semantic type identity");
			}
			void_type = semantic_type;
			break;
			default:
			fail (path, "unsupported semantic type");
			break;
		}
	}

	private void verify_buffer_results(CfgBufferResults results, CfgCleanupContract cleanup, string path) throws CfgError {
		if (!cleanups.contains (cleanup) || !cleanup.is_buffer || results.shape != cleanup.buffer_shape || !results.shape.is_valid (element_fields) || results.owner.semantic_type != cleanup.buffer_type || results.base_value.semantic_type != results.shape.base_type || results.length_value.semantic_type != results.shape.length_type || results.base_value == results.length_value || results.owner == results.base_value || results.owner == results.length_value) {
			fail (path, "buffer producer requires one complete exact PTR/I32 owner group and static cleanup");
		}
	}

	private CfgStructField? record_field(SemanticType type) {
		if (!(structs.lookup (type) is CfgStruct)) {
			return null;
		}
		CfgStructField? found = null;
		try {
			foreach (var path in StructLeafOrder.enumerate_storage (type, struct_fields)) {
				var field = record_leaf (type, path);
				if (field == null) {
					return null;
				}
				if (field.owned_cleanup != null) {
					if (!(field.semantic_type is HandleType) && !(field.semantic_type is ClassType) && !(field.semantic_type is SliceType)) {
						return null;
					}
					if (found == null) {
						found = field;
					}
				} else if (!NativeFieldTypes.supports (field.semantic_type, false)) {
					return null;
				}
			}
		} catch (StructLeafError error) {
			return null;
		}
		return found;
	}

	private CfgStructField? record_leaf(SemanticType type, StructLeafPath path) {
		CfgStructField? field = null;
		for (int d = 0; d < path.depth; d++) {
			var owner = structs.lookup (type) as CfgStruct;
			int ordinal = path.field_ordinal (d);
			if (owner == null || ordinal < 0 || ordinal >= owner.fields.length) {
				return null;
			}
			field = owner.fields[ordinal];
			type = field.semantic_type;
		}
		return field != null && field.semantic_type == path.semantic_type ? field : null;
	}

	private bool matches_cleanup(SemanticType type, CfgCleanupContract cleanup) {
		if (cleanup.record_type != null) {
			return type == cleanup.record_type.semantic_type && structs.lookup (type) == cleanup.record_type && record_field (type) != null;
		}
		if (cleanup.closure_type != null) {
			return type == cleanup.closure_type && cleanup.closure_environment != null && cleanup.closure_environment.semantic_type == cleanup.closure_type.environment_type && !cleanup.closure_environment.polymorphic;
		}
		if (cleanup.shared_type != null) {
			return type == cleanup.shared_type && cleanup.shared_payload != null && cleanup.shared_payload.semantic_type == cleanup.shared_type.payload_type;
		}
		if (cleanup.is_buffer) {
			return type == cleanup.buffer_type && cleanup.buffer_shape.is_valid (element_fields);
		}
		if (cleanup.is_object) {
			return type is ClassType && cleanup.object_class != null && structs.lookup (type) == cleanup.object_class;
		}
		var record = record_field (type);
		if (record != null) {
			var resource = handles.lookup (record.semantic_type);
			return resource != null && resource.cleanup == cleanup;
		}
		var handle = handles.lookup (type);
		return type.is_void_pointer () || (type is HandleType && handle != null && handle.cleanup == cleanup);
	}

	private void verify_parameter_contract(CfgParameter parameter, string path, bool record_class_leaf = false, bool record_buffer_leaf = false, StructBoundaryGroup? record_channel = null) throws CfgError {
		bool record_borrow = record_channel != null && record_channel.shape.semantic_type == parameter.semantic_type && record_channel.shape.mode == StructValueMode.BORROW_VALUE;
		if (record_borrow) {
			verify_struct_shape (record_channel.shape, parameter.semantic_type, path);
		}
		if (parameter.semantic_type is ReceiverType) {
			fail (path, "receiver is not an explicit parameter");
		}
		if (parameter.semantic_type is CallbackType && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			fail (path, "Callback requires exact borrowed-noescape parameter transport");
		}
		if (contract_parameters.contains (parameter) || !parameter.pointer_contract.is_valid () || (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && !(parameter.semantic_type is HandleType) && !(parameter.semantic_type is ClassType) && !(parameter.semantic_type is SliceType)) || (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is CallbackType) && !record_borrow && !parameter.semantic_type.is_ownable_handle_type () && !(parameter.semantic_type is TypedPointerType && (CPlainRecordTypes.pointer (parameter.semantic_type, struct_fields) || (CPlainRecordTypes.i32_pointer (parameter.semantic_type) || ForeignApiTypes.scalar_pointee (parameter.semantic_type) != null))) && !(parameter.semantic_type is StringType) && !(parameter.semantic_type is SliceType) && !(parameter.semantic_type is ClassType)) || ((parameter.semantic_type is SliceType && parameter.pointer_contract == PointerParameterContract.UNMANAGED && !record_buffer_leaf) || (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.UNMANAGED && !record_class_leaf))) {
			fail (path, "parameter requires unique identity and a valid ownership or borrowed-noescape contract");
		}
		if (parameter.semantic_type.is_text_slice () && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			fail (path, "text slice requires deep borrowed-noescape contract");
		}
		if (parameter.semantic_type is StringType && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			fail (path, "string parameter requires borrowed-noescape");
		}
		contract_parameters.insert (parameter, parameter);
	}

	private void verify_program(CfgProgram program) throws CfgError {
		foreach (var function in program.functions) {
			if (function.return_type.is_scoped_allocator ()) {
				fail ("scoped context", "cannot escape through a callable result");
			}
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type.is_scoped_allocator () && (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || function.async_body != null)) {
					fail ("scoped context", "requires a synchronous nonescaping borrowed parameter");
				}
			}
		}
		foreach (var function in program.c_functions) {
			if (function.return_type.is_scoped_allocator ()) {
				fail ("scoped context", "cannot be acquired from a foreign factory");
			}
		}
		foreach (var record in program.structs) {
			foreach (var field in record.fields) {
				if (field.semantic_type.is_scoped_allocator ()) {
					fail ("scoped context", "cannot be stored in a field");
				}
			}
		}
		foreach (var record in program.classes) {
			foreach (var field in record.fields) {
				if (field.semantic_type.is_scoped_allocator ()) {
					fail ("scoped context", "cannot be stored in a Class field");
				}
			}
		}
		code_program = program;
		// Accessor links are weak. Reject a retired/missing property before
		// any derived result contract or hierarchy check dereferences it.
		foreach (var function in program.functions) {
			var accessor = function as CfgPropertyAccessor;
			if (accessor != null && accessor.property_member == null) {
				fail ("property accessor", "requires its live exact property declaration");
			}
		}
		foreach (var function in program.functions) {
			if (GenericClassTypes.general (function.return_type)) {
				if (function.async_body != null) {
					fail ("generic Class", "Class results require a synchronous ownership or registered receiver observation contract");
				}
			} else if (function.return_type is ExactGenericClassType) {
				fail ("generic Class", "bag result composition is outside the finite scope");
			}
			foreach (var parameter in function.parameters) {
				bool record_leaf = false;
				foreach (var group in function.struct_parameters) {
					record_leaf |= parameter.ordinal >= group.first_leaf && parameter.ordinal < group.first_leaf + group.shape.leaves.length;
				}
				// Record transport owns its leaves through the complete boundary
				// group; leaf pointer flags do not describe standalone parameters.
				if (record_leaf) {
					continue;
				}
				if (GenericClassTypes.general (parameter.semantic_type)) {
					if (!(parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && function.async_body == null || parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (function.async_body == null || parameter.heap_object))) {
						fail ("generic Class", "parameter requires an exact synchronous ownership/borrow contract or independent async heap ownership");
					}
				} else if (parameter.semantic_type is ExactGenericClassType && (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || function.async_body != null || function.throws_type != null || (function.return_type.kind != TypeKind.VOID && !GenericBorrowTypes.scalar (function.return_type)))) {
					fail ("generic Class", "bag helper requires a synchronous nonthrowing borrowed scalar/void boundary");
				}
			}
		}
		verify_class_hierarchy (program);
		foreach (var definition in program.enums) {
			if (enum_definitions.contains (definition.semantic_type)) {
				fail ("enum", "duplicate enum definition");
			}
			enum_definitions.insert (definition.semantic_type, definition);
		}
		element_structs = program.structs;
		CfgEnumVerifier.verify (program, element_fields);
		element_structs = program.structs;
		foreach (var payload in program.text_literals) {
			if (!payload.valid ()) {
				fail ("text literal", "invalid UTF-8 payload or signed-I32 byte length");
			}
			text_literals.insert (payload, true);
		}
		var cleanup_symbols = new HashTable<string, string> (str_hash, str_equal);
		var buffer_cleanups = new HashTable<SliceType, bool> (direct_hash, direct_equal);
		var object_cleanups = new HashTable<CfgClass, CfgCleanupContract> (direct_hash, direct_equal);
		var heap_cleanups = new HashTable<CfgClass, CfgCleanupContract> (direct_hash, direct_equal);
		var record_cleanups = new HashTable<CfgStruct, bool> (direct_hash, direct_equal);
		for (int c = 0; c < program.cleanups.length; c++) {
			var cleanup = program.cleanups[c];
			if (cleanup.record_type != null) {
				var record = cleanup.record_type;
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || !program.structs.find (record) || record_cleanups.contains (record) || cleanup.is_object || cleanup.is_buffer || cleanup.closure_type != null || cleanup.shared_type != null || cleanup.external_symbol != "") {
					fail ("record responsibility", "requires one program-owned exact root record without scalar cleanup authority");
				}
				record_cleanups.insert (record, true);
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.closure_type != null) {
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || cleanup.is_object || cleanup.is_buffer || cleanup.shared_type != null || !cleanup.closure_type.supported () || cleanup.closure_environment == null || cleanup.closure_environment.semantic_type != cleanup.closure_type.environment_type || cleanup.closure_environment.polymorphic || !program.classes.find (cleanup.closure_environment)) {
					fail ("closure cleanup", "requires exact closure signature and nonpolymorphic program-owned environment destructor authority");
				}
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.shared_type != null) {
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || cleanup.is_object || cleanup.is_buffer || cleanup.shared_payload == null || cleanup.shared_payload.semantic_type != cleanup.shared_type.payload_type || !program.classes.find (cleanup.shared_payload) || cleanup.shared_type.payload_type.is_interface && !cleanup.shared_type.payload_type.intrinsically_shared || cleanup.shared_type.payload_type.intrinsically_shared && !cleanup.shared_type.is_weak) {
					fail ("shared cleanup", "requires exact strong/weak type and program-owned concrete payload destructor authority");
				}
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.is_buffer) {
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || buffer_cleanups.contains (cleanup.buffer_type) || cleanup.is_object || cleanup.external_symbol != "" || !cleanup.buffer_shape.is_valid (element_fields)) {
					fail ("buffer cleanup", "requires unique exact eligible shape and static deallocation authority");
				}
				verify_type (cleanup.buffer_shape.base_type, true, "buffer base");
				verify_type (cleanup.buffer_shape.length_type, true, "buffer length");
				buffer_cleanups.insert (cleanup.buffer_type, true);
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.is_object) {
				var object_class = cleanup.object_class;
				var authority = cleanup.is_heap_object ? heap_cleanups : object_cleanups;
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || object_class == null || object_class.ordinal < 0 || object_class.ordinal >= program.classes.length || program.classes[object_class.ordinal] != object_class || authority.contains (object_class) || cleanup.external_symbol != "") {
					fail ("cleanup", "object responsibility requires unique exact program-owned class and native destructor authority");
				}
				authority.insert (object_class, cleanup);
				cleanups.insert (cleanup, cleanup);
				continue;
			}
			if (cleanup.ordinal != c || cleanups.contains (cleanup) || cleanup.external_symbol == "" || cleanup_symbols.contains (cleanup.external_symbol)) {
				fail ("cleanup", "cleanup identity, symbol and ordinal must be unique, nonempty and in declaration order");
			}
			cleanups.insert (cleanup, cleanup);
			cleanup_symbols.insert (cleanup.external_symbol, cleanup.external_symbol);
		}
		var names = new HashTable<string, string> (str_hash, str_equal);
		var foreign_roots = new GenericArray<Astra.Source.ForeignImportContract> ();
		foreach (var handle in program.handles) {
			if (handle.c_import != null) {
				foreign_roots.add (handle.c_import);
			}
		}
		if (!Astra.Source.ForeignImportContract.distinct (foreign_roots)) {
			fail ("foreign imports", "requires distinct nominal roots, prefixes and COM IIDs with exact declared parents");
		}
		for (int h = 0; h < program.handles.length; h++) {
			var handle = program.handles[h];
			if (handle.context_mode != "" && handle.semantic_type.context_cleanup != handle.cleanup.external_symbol) {
				fail ("allocator context", "context handle lost its exact backing-release contract");
			}
			if (handle.context_mode != handle.semantic_type.context_mode || handle.context_mode != "" && !AllocationPolicy.valid_context_mode (handle.context_mode)) {
				fail ("allocator context", "nominal handle lost its independently retained context lifetime/thread contract");
			}
			if (handle.c_import != null) {
				var root = handle.c_import;
				for (uint m = 0; m < root.api.member_count; m++) {
					int matches = 0;
					foreach (var candidate in program.functions) {
						if (candidate.name != root.api.native_origin + "." + root.native_name (m)) {
							continue;
						}
						var imported = candidate.entry.terminator as CfgForeignReturn;
						if (imported == null || imported.binding.member_index != m || !imported.binding.root.equal (root)) {
							fail ("CImport", "declared member lost its exact typed adapter operation");
						}
						matches++;
					}
					if (matches != 1) {
						fail ("CImport", "requires exactly one adapter for each declared member");
					}
				}
			}

			if (!(handle.c_import == null ? Astra.Source.ComImportContract.matches (handle.com_import, handle.semantic_type.foreign_policy_identity, handle.name, handle.cleanup.external_symbol) : Astra.Source.ForeignImportContract.matches (handle.c_import, handle.semantic_type.foreign_policy_identity, handle.name, handle.cleanup.external_symbol))) {
				fail ("COMImport", "lost exact imported interface IID/lifetime/context identity");
			}
			if (handle.ordinal != h || handles.contains (handle.semantic_type) || names.contains (handle.name) || handle.name == "" || BuiltinTypes.is_builtin_name (handle.name) || !cleanups.contains (handle.cleanup)) {
				fail ("handle", "handle requires exact unique nominal identity, type name, declaration ordinal and program-owned cleanup");
			}
			handles.insert (handle.semantic_type, handle);
			names.insert (handle.name, handle.name);
		}
		var instances = program.native_instances ();
		foreach (var structure in instances) {
			string path = "native type " + structure.name;
			if (structure is CfgClass && (structure.ordinal < 0 || structure.ordinal >= program.classes.length || program.classes[structure.ordinal] != structure)) {
				fail (path, "class requires its exact declaration ordinal even without methods");
			}
			if ((structure is CfgStruct && !(structure.semantic_type is StructType)) || (structure is CfgClass && !(structure.semantic_type is ClassType))) {
				fail (path, "native declaration category must match its exact semantic type");
			}
			if (structs.contains (structure.semantic_type) || names.contains (structure.name) || structure.name == "" || structure.name != structure.semantic_type.display_name ()) {
				fail (path, "struct descriptor must have unique declared type identity and name");
			}
			if (BuiltinTypes.is_builtin_name (structure.name)) {
				fail (path, "struct descriptor conflicts with builtin type");
			}
			structs.insert (structure.semantic_type, structure);
			names.insert (structure.name, structure.name);
			if (structure is CfgStruct && structure.fields.length == 0) {
				fail (path, "struct must have at least one scalar field");
			}
			var field_names = new HashTable<string, string> (str_hash, str_equal);
			for (int f = 0; f < structure.fields.length; f++) {
				var field = structure.fields[f];
				if (field.semantic_type is CallbackType) {
					fail (path, "call-scoped Callback cannot be stored in a field");
				}
				if (field.is_private && (!(structure is CfgClass) || ((CfgClass) structure).generic_instance != null && ((CfgClass) structure).generic_instance.definition.structure == null)) {
					fail (path, "private fields require an ordinary nongeneric native Class");
				}
				if (field.containing_type != structure || field.ordinal != f || field.name == "" || field_names.contains (field.name)) {
					fail (path, "field must have exact struct owner, unique name and declaration ordinal");
				}
				field_names.insert (field.name, field.name);
				if (field.semantic_type is VectorType && structure is CfgClass) {
					fail (path, "vector struct fields are unsupported");
				}
				if (field.semantic_type.is_typed_pointer () || (field.semantic_type is HandleType && !(structure is CfgClass || structure is CfgStruct))) {
					fail (path, "typed-pointer struct fields are unsupported");
				}
				if (field.semantic_type is SliceType && (field.owned_cleanup == null || !field.owned_cleanup.is_buffer || !buffer_cleanups.contains ((SliceType) field.semantic_type))) {
					fail (path, "buffer fields require exact native class and static cleanup authority");
				}
				if (field.semantic_type is ReceiverType) {
					fail (path, "receiver cannot be a field");
				}
				if (field.text_snapshot && (!(structure is CfgClass) || !(field.semantic_type is StringType))) {
					fail (path, "snapshot requires an exact readonly text class field");
				}
				if (field.semantic_type.kind == TypeKind.VOID) {
					verify_type (field.semantic_type, true, path + "/field " + field.name);
				}
				if (!(field.semantic_type is OwnerSlotsType) && !field.text_snapshot && !NativeFieldTypes.supports (field.semantic_type, true) && !(structure is CfgStruct && field.owned_cleanup != null && (field.semantic_type is HandleType || field.semantic_type is ClassType || field.semantic_type is SliceType)) && !(structure is CfgClass && (field.semantic_type is HandleType || field.semantic_type is SliceType || field.semantic_type is ClassType))) {
					fail (path, "unsupported native field type");
				}
			}
		}
		// Callable fields may name record results declared later in the graph.
		foreach (var structure in instances) {
			var record_type = structure.semantic_type as StructType;
			var owning_record = record_type == null ? null : record_type.owning_application;
			if (owning_record != null) {
				if (!(structure is CfgStruct) || !owning_record.valid (record_type, ((CfgStruct) structure).owning_arguments, struct_fields) || structure.fields.length != owning_record.definition.field_count) {
					fail ("owning record", "lost exact closed declared storage and argument authority");
				}
				foreach (var field in structure.fields) {
					if (!owning_record.field (field.ordinal, field.name, field.semantic_type, field.owned_cleanup != null, field.is_private, struct_fields)) {
						fail ("owning record field", "lost declared type, ownership or visibility");
					}
				}
			} else if (structure is CfgStruct && ((CfgStruct) structure).owning_arguments.length != 0) {
				fail ("owning record", "argument demands require an exact owning declaration");
			}
			foreach (var field in structure.fields) {
				if (!(field.semantic_type is StructType) && !(field.semantic_type is ClassType) && !(field.semantic_type is OwnerSlotsType)) {
					verify_type (field.semantic_type, true, "native type " + structure.name + "/field " + field.name);
				}
			}
		}
		// Structural transfer checks require the complete registered type graph.
		foreach (var owner in program.classes) {
			if (owner.concurrency_policy != null && owner.concurrency_policy.actor && !thread_capture_type (owner.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true)) {
				fail ("Actor policy", "receiver state must be transferable and contain no sender cycles");
			}
		}
		foreach (var function in program.functions) {
			if (function.async_body != null) {
				foreach (var parameter in function.parameters) {
					bool record = false;
					foreach (var group in function.struct_parameters) {
						if (parameter.ordinal >= group.first_leaf && parameter.ordinal < group.first_leaf + group.shape.leaves.length) {
							if (group.shape.mode == StructValueMode.BORROW_VALUE) {
								fail ("async frame", "borrowed record cannot escape into a cold frame");
							}
							record = true;
						}
					}
					if (record) {
						continue;
					}
					if (!AsyncClosureCaptures.valid (parameter.semantic_type, parameter.pointer_contract, function.async_body.runtime.threaded)) {
						fail ("async frame", "Closure capture requires one owned non-actor handle and a single-threaded executor");
					}
					if (parameter.semantic_type is ClassType && (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !parameter.heap_object)) {
						fail ("async frame", "Class capture requires one exact independently heap-owned parameter");
					}
					if (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is SliceType)) {
						fail ("async frame", "borrowed captures require an exact sealed array suspension loan");
					}
				}
			}
			if (function.async_body != null && function.async_body.runtime.threaded) {
				foreach (var parameter in function.parameters) {
					bool record = false;
					foreach (var group in function.struct_parameters) {
						if (parameter.ordinal >= group.first_leaf && parameter.ordinal < group.first_leaf + group.shape.leaves.length) {
							if (group.shape.mode == StructValueMode.BORROW_VALUE || !thread_capture_type (group.shape.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
								fail ("threaded frame", "record capture lost complete structural Send authority");
							}
							record = true;
						}
					}
					if (record) {
						continue;
					}
					if ((parameter.semantic_type is ClassType && (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !parameter.heap_object)) || !thread_capture_type (parameter.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
						fail ("threaded frame", "parameter lost exact heap ownership or structural Send authority");
					}
				}
				if (function.return_type.kind != TypeKind.VOID && !thread_capture_type (function.return_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
					fail ("threaded frame", "result lost structural Send authority");
				}
			}
		}

		foreach (var record in program.structs) {
			foreach (var field in record.fields) {
				if (!(field.semantic_type is ClassType)) {
					continue;
				}
				var child = structs.lookup (field.semantic_type) as CfgClass;
				if (child == null || child.polymorphic || field.owned_cleanup == null || !field.owned_cleanup.is_heap_object || field.owned_cleanup.object_class != child) {
					fail ("record Class field", "requires exact nonpolymorphic heap cleanup authority");
				}
			}
		}
		foreach (var owner in program.structs) {
			foreach (var field in owner.fields) {
				if (field.semantic_type is HandleType) {
					var handle = handles.lookup (field.semantic_type);
					if (handle == null || field.owned_cleanup != handle.cleanup) {
						fail ("record ownership", "Resource field lost its exact declared cleanup contract");
					}
				}
			}
			if (record_field (owner.semantic_type) != null && (owner.methods.length != 0 || owner.properties.length != 0)) {
				fail ("record ownership", "owning record members require their own value ownership contract");
			}
		}
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				if (field.semantic_type is OwnerSlotsType || field.slots_cleanup != null) {
					verify_slots_field (field, "owner-slot field");
				}
			}
			// All nominal declarations exist before checking forward child references.
			foreach (var field in owner.fields) {
				if (field.semantic_type is ClassType) {
					verify_type (field.semantic_type, true, "owned child field");
					var child = structs.lookup (field.semantic_type) as CfgClass;
					if (child == null || child.polymorphic || !heap_cleanups.contains (child)) {
						fail ("owned child fields", "requires exact nonpolymorphic heap cleanup authority");
					}
				}
			}
			if (!OwnedChildComposition.acyclic (owner.semantic_type, child_edges)) {
				fail ("owned child fields", "cyclic owned child composition");
			}
		}
		var complete_layouts = new HashTable<CfgNativeInstance, CfgNativeInstance> (direct_hash, direct_equal);
		var active_layouts = new GenericArray<CfgNativeInstance> ();
		foreach (var structure in instances) {
			verify_layout (structure, complete_layouts, active_layouts);
		}
		for (int st = 0; st < instances.length; st++) {
			var structure = instances[st];
			var member_names = new HashTable<string, string> (str_hash, str_equal);
			foreach (var field in structure.fields) {
				member_names.insert (field.name, field.name);
			}
			int previous_member = -1;
			for (int m = 0; m < structure.methods.length; m++) {
				var method = structure.methods[m];
				bool present = false;
				foreach (var function in program.functions) {
					if (function == method) {
						present = true;
					}
				}
				if (!present || structure.ordinal != ((structure is CfgClass) ? st - (int) program.structs.length : st) || method.declaring_type != structure || method.method_ordinal != m || method.member_ordinal <= previous_member || method.member_ordinal >= structure.fields.length + structure.methods.length + structure.properties.length + ((structure is CfgClass) ? ((CfgClass) structure).lifecycle_count : 0) || method.name == "" || member_names.contains (method.name) || receiver_owners.contains (method.receiver) || method.receiver.contract.mode != ReceiverMode.LIVE || method.receiver.contract.instance_type != structure.semantic_type) {
					fail ("methods", "method requires exact declaring struct, unique member name/ordinal and one implicit receiver");
				}
				var prior = receiver_types.lookup (structure.semantic_type);
				if (prior != null && prior != method.receiver.contract) {
					fail ("methods", "methods of one struct require the same exact receiver type contract");
				}
				receiver_types.insert (structure.semantic_type, method.receiver.contract);
				receiver_owners.insert (method.receiver, method);
				member_names.insert (method.name, method.name);
				previous_member = method.member_ordinal;
			}
			int previous_property_member = -1;
			for (int p = 0; p < structure.properties.length; p++) {
				var property = structure.properties[p];
				if (property.declaring_type != structure || property.ordinal != p || property.name == "" || member_names.contains (property.name) || property.member_ordinal <= previous_property_member || property.member_ordinal >= structure.fields.length + structure.methods.length + structure.properties.length + ((structure is CfgClass) ? ((CfgClass) structure).lifecycle_count : 0) || !(property.is_borrowed ? structure is CfgClass && (property.semantic_type is ClassType || property.semantic_type is HandleType || property.semantic_type.is_struct_storage () && record_field (property.semantic_type) != null) && (!property.is_lazy || property.is_owned_lazy) : PropertyValueTypes.supports (property.semantic_type, struct_fields) || property.getter != null && property.getter.result_contract == ResultOwnershipContract.OWNED_TRANSFER && structure is CfgClass && ForeignApiTypes.owned_property (((CfgClass) structure).foreign_export, property.member_ordinal)) || property.getter == null) {
					fail ("properties", "property requires exact owner, legal value type, unique member name/ordinal and getter");
				}
				if (property.is_owned_lazy) {
					var factory = property.factory;
					var body = property.getter.blocks.length == 1 ? property.getter.blocks[0] : null;
					var returned = body == null ? null : body.terminator as CfgReturn;
					var observe = returned == null ? null : returned.value as CfgLazyObserve;
					if (body == null || body.instructions.length != 0 || observe == null || observe.property_member != property || property.getter.locals.length != 0) {
						fail ("owned lazy", "borrowed getter must preserve the exact receiver cache observation body");
					}
					if (!property.is_lazy || !property.is_borrowed || !(property.semantic_type is ClassType) || property.setter != null || factory == null || !program.functions.find (factory) || factory.declaring_type != structure || factory.return_type != property.semantic_type || factory.result_contract != ResultOwnershipContract.OWNED_TRANSFER || !factory.heap_result || factory.owned_cleanup == null || !factory.owned_cleanup.is_heap_object || factory.owned_cleanup.object_class.polymorphic || property.semantic_type is ExactGenericClassType && !GenericClassTypes.general (property.semantic_type) || factory.parameters.length != 0 || factory.throws_type != property.getter.throws_type || factory.dispatch_kind != ClassDispatchKind.DIRECT || property.getter.dispatch_kind != ClassDispatchKind.DIRECT) {
						fail ("owned lazy", "requires distinct exact owned factory and receiver-borrow observation channels");
					}
				} else if (property.factory != null) {
					fail ("owned lazy", "ordinary property cannot acquire an owned factory");
				}
				if (structure is CfgClass && (property.name == "init" || property.name == "deinit")) {
					fail ("properties", "class lifecycle names are reserved");
				}
				foreach (var method in structure.methods) {
					if (method.member_ordinal == property.member_ordinal) {
						fail ("properties", "property/member ordinals must be distinct");
					}
				}
				if (property.semantic_type is StructType) {
					if (!(structs.lookup (property.semantic_type) is CfgStruct)) {
						fail ("property/value-type", "copied record property lost exact declaration");
					}
				} else {
					verify_type (property.semantic_type, true, "property/value-type");
				}
				member_names.insert (property.name, property.name);
				previous_property_member = property.member_ordinal;
				if (property.semantic_type is StringType && (!(structure is CfgClass) || property.setter != null)) {
					fail ("property", "receiver text requires a get-only native class property");
				}
				if (property.is_lazy && (!(structure is CfgClass) || property.setter != null || property.getter.dispatch_kind != ClassDispatchKind.DIRECT || (!property.is_owned_lazy && !PropertyValueTypes.supports_cache (property.semantic_type)))) {
					fail ("lazy property", "requires an exact nonvirtual get-only copied-value class property");
				}
				var accessors = new GenericArray<CfgPropertyAccessor> ();
				accessors.add (property.getter);
				if (property.setter != null) {
					accessors.add (property.setter);
				}
				foreach (var accessor in accessors) {
					bool present = false;
					foreach (var function in program.functions) {
						if (function == accessor) {
							present = true;
						}
					}
					bool getter = accessor is CfgPropertyGetter;
					bool record_setter = !getter && property.semantic_type is StructType;
					int parameter_count = getter ? 0 : 1;
					if (record_setter) {
						if (accessor.struct_parameters.length != 1 || accessor.struct_parameters[0].source_ordinal != 0 || accessor.struct_parameters[0].first_leaf != 0 || accessor.struct_parameters[0].shape.semantic_type != property.semantic_type || accessor.struct_parameters[0].shape.mode != StructValueMode.COPY_VALUE) {
							fail ("accessors", "record setter requires one complete copied parameter group");
						}
						parameter_count = (int) accessor.struct_parameters[0].shape.leaves.length;
					}
					if (getter && accessor.return_type is StringType) {
						verify_text_getter (accessor);
					}
					if (getter && property.is_borrowed && !property.is_owned_lazy) {
						verify_borrowed_getter (accessor);
					}
					if ((accessor.result_contract == ResultOwnershipContract.RECEIVER_BORROW) != (getter && property.is_borrowed)) {
						fail ("borrowed property", "receiver-borrow result requires its exact declared projection getter");
					}
					if (!present || accessor.property_member != property || (getter ? property.getter != accessor : property.setter != accessor) || receiver_owners.contains (accessor.receiver) || accessor.receiver.contract.mode != ReceiverMode.LIVE || accessor.receiver.contract.instance_type != structure.semantic_type || (accessor.owned_cleanup != null && !(getter && structure is CfgClass && ForeignApiTypes.owned_property (((CfgClass) structure).foreign_export, property.member_ordinal) && accessor.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) || accessor.result_storage != null || accessor.parameters.length != parameter_count || (getter ? accessor.return_type != property.semantic_type : accessor.return_type.kind != TypeKind.VOID)) {
						fail ("accessors", "accessor requires exact property identity, live receiver and plain getter/setter signature");
					}
					if (!getter && !record_setter && (accessor.parameters[0].semantic_type != property.semantic_type || accessor.parameters[0].pointer_contract != (property.is_borrowed ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.UNMANAGED))) {
						fail ("accessors", "setter requires one exact plain property-value parameter");
					}
					var prior = receiver_types.lookup (structure.semantic_type);
					if (prior != null && prior != accessor.receiver.contract) {
						fail ("accessors", "accessor must share the exact native member receiver contract");
					}
					receiver_types.insert (structure.semantic_type, accessor.receiver.contract);
					receiver_owners.insert (accessor.receiver, accessor);
				}
			}
		}

		// Physical external-symbol uniqueness is validated by CABI.
		foreach (var owner in program.classes) {
			var lifecycle_members = new GenericArray<CfgLifecycle> ();
			if (owner.constructor != null) {
				lifecycle_members.add (owner.constructor);
			}
			if (owner.destructor != null) {
				lifecycle_members.add (owner.destructor);
			}
			foreach (var lifecycle in lifecycle_members) {
				bool present = false;
				foreach (var function in program.functions) {
					if (function == lifecycle) {
						present = true;
					}
				}
				bool initializing = lifecycle is CfgConstructor;
				if (!present || lifecycle.declaring_class != owner || lifecycle.receiver.contract.instance_type != owner.semantic_type || lifecycle.receiver.contract.mode != (initializing ? ReceiverMode.INITIALIZING : ReceiverMode.LIVE) || lifecycle.return_type.kind != TypeKind.VOID || lifecycle.owned_cleanup != null || (!initializing && lifecycle.parameters.length != 0) || lifecycle.name != (initializing ? "init" : "deinit") || lifecycle.member_ordinal < 0 || lifecycle.member_ordinal >= owner.fields.length + owner.methods.length + owner.properties.length + owner.lifecycle_count || receiver_owners.contains (lifecycle.receiver)) {
					fail ("lifecycle", "lifecycle requires exact class identity, receiver mode, member ordinal and void callable contract");
				}
				foreach (var method in owner.methods) {
					if (method.name == "init" || method.name == "deinit" || method.member_ordinal == lifecycle.member_ordinal) {
						fail ("lifecycle", "lifecycle names and member ordinals cannot collide with methods");
					}
				}
				foreach (var property in owner.properties) {
					if (property.member_ordinal == lifecycle.member_ordinal) {
						fail ("properties", "property and lifecycle member ordinals must be distinct");
					}
				}
				foreach (var field in owner.fields) {
					if (field.name == "init" || field.name == "deinit") {
						fail ("lifecycle", "lifecycle names cannot collide with fields");
					}
				}
				if (owner.constructor != null && owner.destructor != null && owner.constructor.member_ordinal == owner.destructor.member_ordinal) {
					fail ("lifecycle", "lifecycle member ordinals must be distinct");
				}
				var contracts = initializing ? initializing_types : receiver_types;
				var prior = contracts.lookup (owner.semantic_type);
				if (prior != null && prior != lifecycle.receiver.contract) {
					fail ("lifecycle", "receiver contract must have exact class and mode identity");
				}
				contracts.insert (owner.semantic_type, lifecycle.receiver.contract);
				receiver_owners.insert (lifecycle.receiver, lifecycle);
			}
		}
		for (int c = 0; c < program.c_functions.length; c++) {
			var imported = program.c_functions[c];
			string path = "C import #%d".printf (c);
			if (imported.return_type is ClosureHandleType || imported.return_type is SharedHandleType) {
				fail (path, "native lifetime carriers cannot be exposed as raw C results");
			}
			foreach (var carrier_type in imported.parameter_types) {
				if (carrier_type is ClosureHandleType || carrier_type is SharedHandleType) {
					fail (path, "native lifetime carriers cannot be exposed as raw C parameters");
				}
			}

			if (c_functions.contains (imported) || imported.ordinal != c) {
				fail (path, "C function identity/ordinal must be unique and in declaration order");
			}
			if (imported.abi != ForeignAbi.C || imported.external_symbol == "") {
				fail (path, "C import must have ABI C and a nonempty external symbol");
			}
			if (imported.metadata.owned_result != null || (imported.owned_cleanup != null && (!cleanups.contains (imported.owned_cleanup) || !imported.return_type.is_ownable_handle_type () || !matches_cleanup (imported.return_type, imported.owned_cleanup)))) {
				fail (path, "owned-result requires an exact program-owned cleanup and void* result; semantic ownership metadata must be normalized");
			}
			bool device_parameters = true;
			foreach (var type in imported.parameter_types) {
				device_parameters &= type.kind == TypeKind.INT;
			}
			if (!imported.metadata.device_signature (imported.return_type.kind == TypeKind.INT, imported.parameter_types.length, device_parameters)) {
				fail (path, "PC device policy lost its admitted operation or exact i32 signature");
			}
			if (!imported.metadata.text_abi.is_valid ()) {
				fail (path, "invalid C text ABI mode");
			}
			if (!imported.metadata.bool_policy_valid ()) {
				fail (path, "lost admitted C99 boolean policy");
			}
			if (!imported.metadata.import_policy_valid ()) {
				fail (path, "lost admitted foreign policy or GObject bridge/header identity");
			}
			if (!imported.metadata.record_abi.is_valid ()) {
				fail (path, "invalid C record ABI mode");
			}
			if (!imported.metadata.buffer_abi.is_valid ()) {
				fail (path, "invalid C buffer ABI mode");
			}
			if (imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE && imported.return_type.is_nullable_pointer_value ()) {
				fail (path, "C byte buffer imports cannot return pointer-like values");
			}
			if (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE && imported.return_type.is_nullable_pointer_value ()) {
				fail (path, "C record imports cannot return pointer-like values or derived owners");
			}
			bool has_text = false;
			bool has_buffer = false;
			bool has_record = false;
			bool has_pointer = false;
			SemanticType[] com_types = null;
			PointerParameterContract[] com_contracts = null;
			foreach (var parameter in imported.parameters) {
				com_types += parameter.semantic_type;
				com_contracts += parameter.pointer_contract;
			}
			if (!ComImportTypes.valid (imported.metadata, imported.return_type, com_types, com_contracts, imported.owned_cleanup == null ? "" : imported.owned_cleanup.external_symbol)) {
				fail (path, "COMImport lost its nominal IID, signature, ownership or context contract");
			}
			if (!imported.metadata.pointer_abi.is_valid () || imported.metadata.pointer_abi != Astra.Foreign.CPointerAbi.NONE && (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE || imported.metadata.text_abi != Astra.Foreign.CTextAbi.NONE || imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE || imported.metadata.callback != null || !imported.metadata.com_owner_result && (imported.owned_cleanup != null || imported.return_type.is_nullable_pointer_value ()))) {
				fail (path, "invalid i32-noescape C pointer transport");
			}
			bool value_record = imported.metadata.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64;
			if (value_record && (imported.parameters.length > 2 || imported.metadata.callback != null || imported.metadata.text_abi != Astra.Foreign.CTextAbi.NONE || imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE)) {
				fail (path, "value-lp64 requires at most two parameters and no alternate transport groups");
			}
			if (value_record && imported.return_type.is_struct_storage ()) {
				if (!CPlainRecordTypes.value (imported.return_type, struct_fields)) {
					fail (path, "unsupported C value record result");
				}
				has_record = true;
			}
			c_functions.insert (imported, imported);
			if (imported.return_type is StringType || imported.return_type is SliceType) {
				fail (path, "C slice results are unsupported");
			}
			if (!(value_record && imported.return_type.is_struct_storage ())) {
				verify_type (imported.return_type, false, path + "/result");
			}
			if (!(value_record && imported.return_type.is_struct_storage ()) && !(imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && imported.return_type.kind == TypeKind.BOOL) && imported.return_type.kind != TypeKind.INT && imported.return_type.kind != TypeKind.I64 && imported.return_type.kind != TypeKind.U64 && imported.return_type.kind != TypeKind.ISIZE && imported.return_type.kind != TypeKind.USIZE && !(imported.return_type is F64Type) && !(imported.return_type is F32Type) && imported.return_type.kind != TypeKind.VOID && !imported.return_type.is_ownable_handle_type ()) {
				fail (path, "C result must be int, void* or void; foreign bool is unsupported");
			}
			if (imported.parameters.length != imported.parameter_types.length) {
				fail (path, "C parameter metadata count must match semantic types");
			}
			for (int p = 0; p < imported.parameters.length; p++) {
				var parameter = imported.parameters[p];
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					fail (path, "C ownership parameter boundaries are unsupported");
				}
				verify_parameter_contract (parameter, path);
				if (value_record && parameter.semantic_type.is_struct_storage ()) {
					if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !CPlainRecordTypes.value (parameter.semantic_type, struct_fields)) {
						fail (path, "unsupported C value record parameter");
					}
					has_record = true;
				}
				if (CPlainRecordTypes.i32_pointer (parameter.semantic_type)) {
					if (imported.metadata.pointer_abi != Astra.Foreign.CPointerAbi.I32_NOESCAPE || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						fail (path, "C int pointer requires explicit i32-noescape borrowed int*");
					}
					has_pointer = true;
				} else if (parameter.semantic_type is TypedPointerType) {
					if (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NATURAL_LP64 || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || !(CPlainRecordTypes.pointer (parameter.semantic_type, struct_fields) || CPlainRecordTypes.i32_pointer (parameter.semantic_type))) {
						fail (path, "C record parameter requires explicit natural-lp64 borrowed scalar POD Struct*");
					}
					has_record = true;
				}
				if (parameter.semantic_type is SliceType) {
					var slice = (SliceType) parameter.semantic_type;
					if (!(slice.element_type is IntegerType) || slice.element_type.kind != TypeKind.U8 || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || imported.metadata.buffer_abi != Astra.Foreign.CBufferAbi.U8_I32) {
						fail (path, "C buffer parameter requires exact borrowed u8[] and explicit u8-i32 metadata");
					}
				}
				if (parameter.ordinal != p || parameter.semantic_type != imported.parameter_types[p]) {
					fail (path, "C parameter identity/order/type metadata mismatch");
				}
			}
			foreach (var parameter_type in imported.parameter_types) {
				if (parameter_type is StringType) {
					has_text = true;
					if (imported.metadata.text_abi != Astra.Foreign.CTextAbi.UTF8_I32) {
						fail (path, "C string parameter requires explicit utf8-i32 metadata");
					}
				} else if (parameter_type is SliceType) {
					has_buffer = true;
				}
				if (!(value_record && parameter_type.is_struct_storage ())) {
					verify_type (parameter_type, true, path + "/parameter");
				}
				if (!(value_record && parameter_type.is_struct_storage ()) && !(imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && parameter_type.kind == TypeKind.BOOL) && parameter_type.kind != TypeKind.INT && parameter_type.kind != TypeKind.I64 && parameter_type.kind != TypeKind.U64 && parameter_type.kind != TypeKind.ISIZE && parameter_type.kind != TypeKind.USIZE && !(parameter_type is F64Type) && !(parameter_type is F32Type) && !(parameter_type is StringType) && !(parameter_type is SliceType) && !parameter_type.is_ownable_handle_type () && !(parameter_type is TypedPointerType && (CPlainRecordTypes.pointer (parameter_type, struct_fields) || CPlainRecordTypes.i32_pointer (parameter_type)))) {
					fail (path, "C parameters must be int or void*; foreign bool is unsupported");
				}
			}
			bool has_bool = imported.return_type.kind == TypeKind.BOOL;
			foreach (var type in imported.parameter_types) {
				has_bool |= type.kind == TypeKind.BOOL;
			}
			if (!imported.metadata.bool_signature_valid (has_bool) || imported.metadata.bool_abi == Astra.Foreign.CBoolAbi.C99 && imported.owned_cleanup != null) {
				fail (path, "C99 boolean profile requires copied bool channels without alternate transports");
			}
			if (has_text != (imported.metadata.text_abi == Astra.Foreign.CTextAbi.UTF8_I32)) {
				fail (path, "C text ABI mode requires string parameters");
			}
			if (has_buffer != (imported.metadata.buffer_abi == Astra.Foreign.CBufferAbi.U8_I32)) {
				fail (path, "C buffer ABI mode requires borrowed u8[] parameters");
			}
			if (has_pointer != (imported.metadata.pointer_abi == Astra.Foreign.CPointerAbi.I32_NOESCAPE)) {
				fail (path, "C pointer ABI mode requires borrowed int* parameters");
			}
			if (has_record != (imported.metadata.record_abi != Astra.Foreign.CRecordAbi.NONE)) {
				fail (path, "C record ABI mode requires borrowed scalar POD Struct* parameters");
			}
			if (!imported.metadata.callback_abi.is_valid () || (imported.metadata.callback != null) != (imported.metadata.callback_abi == Astra.Foreign.CCallbackAbi.I32_CONTEXT_I32_SYNC)) {
				fail (path, "C callback requires exact synchronous nonretaining mode and target name");
			}
			if (imported.metadata.callback != null) {
				CfgFunction? callback = null;
				foreach (var candidate in program.functions) {
					if (candidate.name == imported.metadata.callback) {
						if (callback != null) {
							fail (path, "C callback target identity is ambiguous");
						}
						callback = candidate;
					}
				}
				if (!has_record || imported.parameters.length != 2 || imported.return_type.kind != TypeKind.INT || !imported.parameters[0].semantic_type.is_struct_pointer () || imported.parameters[1].semantic_type.kind != TypeKind.INT || imported.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED || callback == null || callback.implicit_receiver != null || callback.throws_type != null || callback.async_body != null || callback.return_type.kind != TypeKind.INT || callback.parameters.length != 2 || callback.parameters[0].semantic_type != imported.parameters[0].semantic_type || callback.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || callback.parameters[1].semantic_type.kind != TypeKind.INT || callback.parameters[1].pointer_contract != PointerParameterContract.UNMANAGED) {
					fail (path, "C callback requires exact nonthrowing native I32(borrowed POD*, I32) target");
				}
			}
		}
		// Establish all declaration and block owners before checking uses.
		for (int i = 0; i < program.functions.length; i++) {
			var function = program.functions[i];
			string path = "function #%d".printf (i);
			if (functions.contains (function)) {
				fail (path, "function identity occurs more than once");
			}
			functions.insert (function, function);
			if (function.implicit_receiver != null && receiver_owners.lookup (function.implicit_receiver) != function) {
				fail (path, "method is absent from its exact declaring struct member namespace");
			}
			if (function.heap_result) {
				if (!(function.return_type is ClassType) || function.owned_cleanup == null || !function.owned_cleanup.is_heap_object || function.result_storage != null) {
					fail (path, "heap-origin result requires exact heap cleanup and no lexical result storage");
				}
			} else if (function.return_type is ClassType && function.result_contract != ResultOwnershipContract.RECEIVER_BORROW) {
				var input = function.result_storage;
				if (function.owned_cleanup == null || input == null || input.semantic_type != function.return_type || input.object_class == null || structs.lookup (input.semantic_type) != input.object_class || result_inputs.contains (input)) {
					fail (path, "owned ClassType result requires exact unique caller-provided result storage and cleanup contract");
				}
				result_inputs.insert (input, function);
			} else if (function.result_storage != null) {
				fail (path, "only owned ClassType results have result storage");
			}
			if (function.result_contract == ResultOwnershipContract.RECEIVER_BORROW && (!(function is CfgPropertyGetter) || !((CfgPropertyGetter) function).property_member.is_borrowed || function.owned_cleanup != null || function.result_storage != null || function.heap_result)) {
				fail (path, "receiver borrow requires the exact nonowning property getter");
			}
			if (function.return_type is ReceiverType) {
				fail (path, "receiver cannot be a function result");
			}
			if (function.ordinal != i) {
				fail (path, "expected ordinal %d, found %d".printf (i, function.ordinal));
			}
			if (function.owned_cleanup != null && (!(function.return_type is HandleType || function.return_type is ClassType || function.return_type is SliceType) || !cleanups.contains (function.owned_cleanup) || !matches_cleanup (function.return_type, function.owned_cleanup))) {
				fail (path, "owned native result requires exact nominal handle type and its cleanup contract");
			}
			if (function.return_type is SliceType && (function.owned_cleanup == null || !function.owned_cleanup.is_buffer)) {
				fail (path, "native slice results require unsupported lifetime relationships");
			}
			if (function.return_type is CallbackType) {
				fail ("callback result", "call-scoped Callback cannot be returned");
			}
			if (function.return_type is StructType) {
				verify_struct_shape (function.struct_result, function.return_type, path + "/result");
				if ((function.struct_result.mode == StructValueMode.BORROW_VALUE) != (function.result_contract == ResultOwnershipContract.RECEIVER_BORROW)) {
					fail (path, "borrowed record result requires its exact receiver-bound getter contract");
				}
			} else {
				if (function.struct_result != null) {
					fail (path, "only a StructType result has a leaf grouping");
				}
				verify_type (function.return_type, false, path + "/return-type");
			}
			verify_struct_parameter_groups (function, path);
			if (function.return_type.is_typed_pointer ()) {
				fail (path, "typed-pointer function results are unsupported in TPTR-1");
			}
			for (int j = 0; j < function.parameters.length; j++) {
				var parameter = function.parameters[j];
				string parameter_path = path + "/parameter #%d".printf (j);
				if (owners.contains (parameter)) {
					fail (parameter_path, "parameter identity occurs in more than one declaration slot");
				}
				if (parameter.ordinal != j) {
					fail (parameter_path, "expected ordinal %d, found %d".printf (j, parameter.ordinal));
				}
				verify_type (parameter.semantic_type, true, parameter_path);
				bool record_class_leaf = false;
				bool record_buffer_leaf = false;
				foreach (var group in function.struct_parameters) {
					if (group.shape.mode != StructValueMode.MOVE_VALUE || j < group.first_leaf || j >= group.first_leaf + group.shape.leaves.length) {
						continue;
					}
					var leaf = group.shape.leaves[j - group.first_leaf];
					var field = record_leaf (group.shape.semantic_type, leaf);
					record_class_leaf = field != null && field.owned_cleanup != null && field.owned_cleanup.is_heap_object;
					record_buffer_leaf = field != null && field.owned_cleanup != null && field.owned_cleanup.is_buffer;
				}
				verify_parameter_contract (parameter, parameter_path, record_class_leaf, record_buffer_leaf);
				owners.insert (parameter, function);
			}
			for (int j = 0; j < function.locals.length; j++) {
				var local = function.locals[j];
				if (local.semantic_type is CallbackType) {
					fail ("callback storage", "call-scoped Callback cannot be stored in a local");
				}
				bool record_borrow = local.struct_parameter != null && local.struct_parameter.shape.mode == StructValueMode.BORROW_VALUE;
				if (record_field (local.semantic_type) != null && (record_borrow && function.async_body != null || local.incoming_parameter != null || (record_borrow ? local.cleanup != null : local.cleanup == null))) {
					fail (path, "record local requires ownership or an exact synchronous nonowning parameter binding");
				}
				if (local.semantic_type is ReceiverType) {
					fail (path, "receiver cannot be a mutable local");
				}
				string local_path = path + "/local #%d".printf (j);
				if (place_owners.contains (local)) {
					fail (local_path, "local identity occurs in more than one declaration slot");
				}
				if (local.ordinal != j) {
					fail (local_path, "expected ordinal %d, found %d".printf (j, local.ordinal));
				}
				if (local.cleanup != null && (!cleanups.contains (local.cleanup) || (!local.semantic_type.is_ownable_handle_type () && !(local.semantic_type is ClassType) && !(local.semantic_type is SliceType) && record_field (local.semantic_type) == null) || (!local.is_promotable () && !(record_field (local.semantic_type) != null && !local.address_taken)) || !matches_cleanup (local.semantic_type, local.cleanup))) {
					fail (local_path, "owned local requires scalar void* storage and an exact program cleanup contract");
				}
				if (local.cleanup != null && local.cleanup.is_buffer) {
					var group = local.buffer_group;
					if (group == null || group.shape != local.cleanup.buffer_shape || group.base_place.semantic_type != group.shape.base_type || group.length_place.semantic_type != group.shape.length_type || group.base_place.component != 0 || group.length_place.component != 1 || group.base_place == group.length_place) {
						fail (local_path, "buffer owner requires one complete exact PTR/I32 storage group");
					}
					if (buffer_groups.contains (group)) {
						fail (local_path, "buffer storage group cannot belong to multiple owners");
					}
					buffer_groups.insert (group, local);
				} else if (local.buffer_group != null) {
					fail (local_path, "nonbuffer local cannot carry owner group metadata");
				}
				if (local.address_taken && !local.semantic_type.is_typed_data_pointee ()) {
					fail (local_path, "only supported scalar or aggregate locals may be address-taken");
				}
				if (local.semantic_type.kind == TypeKind.STRUCT) {
					if (!structs.contains (local.semantic_type)) {
						fail (local_path, "aggregate local must have a program-owned struct descriptor");
					}
				} else {
					if (local.semantic_type is ArrayType) {
						verify_array_type ((ArrayType) local.semantic_type, local_path);
					} else {
						verify_type (local.semantic_type, true, local_path);
					}
				}
				place_owners.insert (local, function);
			}
			int projection_index = 0;
			foreach (var local in function.locals) {
				if (local.semantic_type.kind != TypeKind.STRUCT) {
					continue;
				}
				verify_projections (local, function, ref projection_index, path);
			}
			if (projection_index != function.field_places.length) {
				fail (path, "unexpected or duplicate field projection");
			}
			for (int j = 0; j < function.temporaries.length; j++) {
				var temporary = function.temporaries[j];
				string temporary_path = path + "/temporary #%d".printf (j);
				if (place_owners.contains (temporary) || temporary.ordinal != j) {
					fail (temporary_path, "temporary identity/ordinal must be unique and in construction order");
				}
				if (temporary.semantic_type is ReceiverType) {
					fail (temporary_path, "receiver cannot become mutable temporary storage");
				}
				verify_type (temporary.semantic_type, true, temporary_path);
				if (temporary is CfgExceptionStorage) {
					var owner = structs.lookup (temporary.semantic_type) as CfgClass;
					if (owner == null || !owner.exception_root) {
						fail (path, "private exception storage requires exact nominated native root");
					}
				} else if (temporary.semantic_type.kind != TypeKind.BOOL) {
					fail (temporary_path, "generated temporary must have type 'bool'");
				}
				place_owners.insert (temporary, function);
			}
			foreach (var storage in function.object_storage) {
				if (function.async_body != null && function.async_body.runtime.threaded && !thread_capture_type (storage.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
					fail ("threaded frame", "object storage lost its structural Send authority");
				}
				if (((ClassType) storage.semantic_type).intrinsically_shared && !storage.heap_allocated) {
					fail ("shared allocation", "intrinsic weak anchors require independently allocated retained backing");
				}
				if (object_owners.contains (storage) || storage.ordinal < 0 || storage.ordinal >= function.object_storage.length || function.object_storage[storage.ordinal] != storage || storage.region_ordinal < 0 || (!storage.result_candidate && storage.destructor != null && storage.cleanup_rank < 0) || storage.object_class == null || structs.lookup (storage.semantic_type) != storage.object_class) {
					fail (path, "object storage requires exact class and function-owned lexical identity");
				}
				int responsibility_count = 0;
				foreach (var local in function.locals) {
					if (local.object_storage != storage) {
						continue;
					}
					if (local.incoming_parameter != null || local.cleanup == null || !local.cleanup.is_object || local.cleanup.object_class != storage.object_class || local.semantic_type != storage.semantic_type) {
						fail (path, "transferable storage requires exact local owner and cleanup responsibility");
					}
					responsibility_count++;
				}
				if (responsibility_count > 1 || storage.transferable != (responsibility_count == 1)) {
					fail (path, "fixed/transferable ObjectStorage mode must match its unique ownership responsibility");
				}
				if (storage.fallible) {
					var owner = storage.object_class;
					if (!storage.heap_allocated || storage.result_candidate || owner.allocation_policy == null || owner.constructor == null || function.async_body != null) {
						fail (path, "fallible construction requires fresh synchronous policy-owned storage and exact constructor");
					}
					foreach (var parameter in owner.constructor.parameters) {
						bool scalar = (parameter.semantic_type is IntegerType || parameter.semantic_type is FloatingType || parameter.semantic_type.kind == TypeKind.BOOL) && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
						bool input = (parameter.semantic_type is ClassType || parameter.semantic_type is HandleType || parameter.semantic_type is SliceType) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER;
						bool record = false;
						foreach (var group in owner.constructor.struct_parameters) {
							if (parameter.ordinal >= group.first_leaf && parameter.ordinal < group.first_leaf + group.shape.leaves.length) {
								if (group.shape.mode == StructValueMode.BORROW_VALUE) {
									fail (path, "fallible record constructor requires owned or copied complete values");
								}
								record = true;
							}
						}
						if (!scalar && !input && !record) {
							fail (path, "fallible construction requires copied values or exact owning input contracts");
						}
					}
				}
				object_owners.insert (storage, function);
				object_fields.insert (storage, new HashTable<CfgStructField, CfgObjectFieldPlace> (direct_hash, direct_equal));
			}
			for (int j = 0; j < function.blocks.length; j++) {
				var block = function.blocks[j];
				string block_path = path + "/block #%d".printf (j);
				if (block_owners.contains (block)) {
					fail (block_path, "block identity occurs in more than one declaration slot");
				}
				if (block.ordinal != j) {
					fail (block_path, "expected ordinal %d, found %d".printf (j, block.ordinal));
				}
				if (!block.is_complete) {
					fail (block_path + "/terminator", "block has no terminator");
				}
				block_owners.insert (block, function);
				for (int k = 0; k < block.instructions.length; k++) {
					var lifecycle_call = block.instructions[k] as CfgLifecycleCallInstruction;
					if (lifecycle_call != null && lifecycle_call.constructs) {
						if (constructor_sites.contains (lifecycle_call.storage)) {
							fail (path, "object storage requires exactly one constructor call site");
						}
						constructor_sites.insert (lifecycle_call.storage, block);
					}
					var initialization = block.instructions[k] as CfgInitialize;
					var field = initialization == null ? null : initialization.target as CfgObjectFieldPlace;
					if (field != null) {
						var bindings = object_fields.lookup (field.storage);
						if (bindings == null || bindings.contains (field.field)) {
							fail (path, "object field must have one exact initialization site");
						}
						bindings.insert (field.field, field);
						object_initializations.insert (field, block);
					}
					var object_evaluation = block.instructions[k] as CfgEvaluateInstruction;
					if (object_evaluation != null && object_evaluation.value is CfgObjectValidateValue) {
						object_validations.insert (object_evaluation.result, (CfgObjectValidateValue) object_evaluation.value);
					}
					var array = block.instructions[k] as CfgArrayInitialize;
					if (array != null) {
						if (array.record_root != null) {
							var entries = record_initializations.lookup (array.storage);
							if (entries == null) {
								entries = new GenericArray<CfgArrayInitialize> ();
								record_initializations.insert (array.storage, entries);
							}
							if (array.record_ordinal != entries.length || array.record_ordinal >= array.record_root.array_type.length) {
								fail (path, "record initialization entries must occur once in positional order");
							}
							entries.add (array);
							record_initialization_blocks.insert (array, block);
						}
						if (!array.completes_array) {
							continue;
						}
						if (array_initializations.contains (array.storage)) {
							fail (path, "array local requires exactly one initialization");
						}
						array_initializations.insert (array.storage, block);
					}
					var slice_bounds = block.instructions[k] as CfgSliceBoundsCheck;
					if (slice_bounds != null) {
						slice_bounds_views.insert (slice_bounds.result, slice_bounds.slice);
					}
					var numeric_guard = block.instructions[k] as CfgNumericGuard;
					if (numeric_guard != null) {
						numeric_guards.insert (numeric_guard.result, numeric_guard);
					}
					var bounds = block.instructions[k] as CfgArrayBoundsCheck;
					if (bounds != null) {
						bounds_storage.insert (bounds.result, bounds.storage);
					}
					var call = block.instructions[k] as CfgCallInstruction;
					if (call != null && call.exception_result != null) {
						definition_blocks.insert (call.exception_result, block);
					}
					if (call != null && call.struct_result != null) {
						foreach (var leaf in call.struct_result.leaves) {
							definition_blocks.insert (leaf, block);
						}
					}
					if (block.instructions[k] is CfgStructInvoke) {
						foreach (var leaf in ((CfgStructInvoke) block.instructions[k]).results.leaves) {
							definition_blocks.insert (leaf, block);
						}
					}
					if (block.instructions[k] is CfgBufferAllocate) {
						var allocation = (CfgBufferAllocate) block.instructions[k];
						definition_blocks.insert (allocation.results.owner, block);
						owned_results.insert (allocation.results.owner, allocation.cleanup);
					}
					var c_call = block.instructions[k] as CfgCCallInstruction;
					if (c_call != null && c_call.struct_result != null) {
						foreach (var leaf in c_call.struct_result.leaves) {
							definition_blocks.insert (leaf, block);
						}
					}
					if (c_call != null && c_call.result != null) {
						definition_blocks.insert (c_call.result, block);
						if (c_call.target != null && c_call.target.owned_cleanup != null) {
							owned_results.insert (c_call.result, c_call.target.owned_cleanup);
						}
					}
					var capture = block.instructions[k] as CfgOwnedArgumentCapture;
					if (capture != null) {
						definition_blocks.insert (capture.transfer, block);
					}
					var owned_return = block.instructions[k] as CfgOwnershipReturnInstruction;
					if (owned_return != null) {
						definition_blocks.insert (owned_return.result, block);
					}
					var borrow = block.instructions[k] as CfgOwnedBorrowInstruction;
					if (borrow != null) {
						definition_blocks.insert (borrow.result, block);
					}
					if (block.instructions[k] is CfgSlotsBorrow) {
						definition_blocks.insert (((CfgSlotsBorrow) block.instructions[k]).result, block);
					}
					var evaluation = block.instructions[k] as CfgEvaluateInstruction;
					if (block.instructions[k] is CfgTaskBorrow) {
						definition_blocks.insert (((CfgTaskBorrow) block.instructions[k]).result, block);
					}
					if (block.instructions[k] is CfgAsyncOperation) {
						var operation = (CfgAsyncOperation) block.instructions[k];
						if (operation.result != null) {
							definition_blocks.insert (operation.result, block);
						}
						if (operation.exception != null) {
							definition_blocks.insert (operation.exception, block);
						}
					}
					if (block.instructions[k] is CfgTaskMove) {
						definition_blocks.insert (((CfgTaskMove) block.instructions[k]).result, block);
					}
					if (block.instructions[k] is CfgAsyncDelay) {
						definition_blocks.insert (((CfgAsyncDelay) block.instructions[k]).exception, block);
					}
					if (block.instructions[k] is CfgTaskWait) {
						definition_blocks.insert (((CfgTaskWait) block.instructions[k]).exception, block);
					}
					if (block.instructions[k] is CfgTaskSuccess) {
						var success = (CfgTaskSuccess) block.instructions[k];
						if (success.result != null) {
							definition_blocks.insert (success.result, block);
						}
						if (success.struct_result != null) {
							foreach (var leaf in success.struct_result.leaves) {
								definition_blocks.insert (leaf, block);
							}
						}
						if (success.buffer_cleanup != null) {
							owned_results.insert ((CfgCallResultValue) success.result, success.buffer_cleanup);
						}
					}
					if (evaluation != null) {
						var shared = evaluation.value as CfgSharedOperation;
						var closure = evaluation.value as CfgClosureBind;
						var invocation = evaluation.value as CfgInvocation;
						var scoped = evaluation.value as CfgScopedAllocator;
						var native_cleanup = scoped != null ? scoped.cleanup : closure != null ? closure.cleanup : invocation != null && !(evaluation is CfgCheckedClosureInvoke) ? invocation.result_cleanup () : shared == null ? null : shared.cleanup;
						if (native_cleanup != null) {
							owned_results.insert (evaluation.result, native_cleanup);
						}
					}
					var buffer_load = evaluation == null ? null : evaluation.value as CfgLoadValue;
					if (buffer_load != null && buffer_load.semantic_type is SliceType && buffer_load.source is CfgIndirectFieldPlace) {
						buffer_field_views.insert (evaluation.result, (CfgIndirectFieldPlace) buffer_load.source);
					}
					if (call != null && call.result != null) {
						if (!(call is CfgTaskCreate) && call.target != null && call.target.owned_cleanup != null) {
							owned_results.insert (call.result, call.target.owned_cleanup);
						}
						definition_blocks.insert (call.result, block);
					} else if (evaluation != null) {
						definition_blocks.insert (evaluation.result, block);
					}
				}
			}
		}
		for (int e = 0; e < program.c_exports.length; e++) {
			var exported = program.c_exports[e];
			string path = "C export #%d".printf (e);
			var target = exported.target;
			if (target != null && target.implicit_receiver != null) {
				fail (path, "methods are internal native members and cannot be C exports");
			}
			if (target == null || !functions.contains (target)) {
				fail (path, "C export target must be a live native function owned by this program");
			}
			if (exported.ordinal != e || exported.abi != ForeignAbi.C) {
				fail (path, "C export must have ABI C and an ordinal in declaration order");
			}
			if ((exported.record_abi != Astra.Foreign.CRecordAbi.NONE && exported.record_abi != Astra.Foreign.CRecordAbi.VALUE_LP64) || (exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64 && target.parameters.length - (int) target.struct_parameters.length > 4)) {
				fail (path, "invalid explicit C value record export authority");
			}
			bool has_bool = target.return_type.kind == TypeKind.BOOL;
			foreach (var parameter in target.parameters) {
				has_bool |= parameter.semantic_type.kind == TypeKind.BOOL;
			}
			if (!exported.bool_policy_valid () || has_bool != (exported.bool_abi == Astra.Foreign.CBoolAbi.C99) || exported.bool_abi == Astra.Foreign.CBoolAbi.C99 && exported.record_abi != Astra.Foreign.CRecordAbi.NONE) {
				fail (path, "C export lost its admitted C99 bool channels");
			}
			bool has_value_record = target.return_type.is_struct_storage () || target.struct_parameters.length != 0;
			if (has_value_record != (exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64)) {
				fail (path, "C export record groups require exact explicit value-lp64 authority");
			}
			if (exported.external_symbol == "") {
				fail (path, "external C symbols must be nonempty");
			}
			if (!(exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64 && CPlainRecordTypes.value (target.return_type, struct_fields)) && !(exported.bool_abi == Astra.Foreign.CBoolAbi.C99 && target.return_type.kind == TypeKind.BOOL) && target.return_type.kind != TypeKind.INT && target.return_type.kind != TypeKind.I64 && target.return_type.kind != TypeKind.U64 && target.return_type.kind != TypeKind.ISIZE && target.return_type.kind != TypeKind.USIZE && !(target.return_type is F64Type) && !(target.return_type is F32Type) && target.return_type.kind != TypeKind.VOID && !target.return_type.is_void_pointer ()) {
				fail (path, "C export result must be int, void* or void; foreign bool is unsupported");
			}
			foreach (var parameter in target.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.UNMANAGED) {
					fail (path, "C export borrowed parameters are unsupported");
				}
				if (!(exported.record_abi == Astra.Foreign.CRecordAbi.VALUE_LP64 && CPlainRecordTypes.value (parameter.semantic_type, struct_fields)) && !(exported.bool_abi == Astra.Foreign.CBoolAbi.C99 && parameter.semantic_type.kind == TypeKind.BOOL) && parameter.semantic_type.kind != TypeKind.INT && parameter.semantic_type.kind != TypeKind.I64 && parameter.semantic_type.kind != TypeKind.U64 && parameter.semantic_type.kind != TypeKind.ISIZE && parameter.semantic_type.kind != TypeKind.USIZE && !(parameter.semantic_type is F64Type) && !(parameter.semantic_type is F32Type) && !parameter.semantic_type.is_void_pointer ()) {
					fail (path, "C export parameters must be int or void*; foreign bool is unsupported");
				}
			}
		}
		for (int i = 0; i < program.functions.length; i++) {
			var function = program.functions[i];
			string path = "function #%d".printf (i);
			if (function.entry == null || block_owners.lookup (function.entry) != function) {
				fail (path + "/entry", "entry block is not owned by the containing function");
			}
			if (function.native_declaration != null) {
				verify_native_declaration (function, path);
				if (!function.declaration_only ()) {
					fail (path, "native declaration requires one empty declaration block without local storage");
				}
				continue;
			}
			foreach (var handler in function.handlers) {
				var branch = handler.dispatch == null ? null : handler.dispatch.terminator as CfgConditionalBranch;
				if (branch == null || branch.condition != handler.selection || branch.true_target != handler.matched || branch.false_target != handler.next || handler.borrow.exception != handler.selection.exception || handler.borrow.semantic_type != handler.selection.match_type) {
					fail (path, "protected group lost source-ordered subtype selection and exact handler target/owner");
				}
				bool bound = false;
				foreach (var instruction in handler.matched.instructions) {
					var initialization = instruction as CfgInitialize;
					if (initialization != null && initialization.value == handler.borrow) {
						bound = true;
					}
				}
				if (!bound) {
					fail (path, "handler target lost its exact guarded borrowed binding");
				}
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation is CfgClosureCallSuccess) {
						continue;
					}
					var structured = instruction as CfgStructInvoke;
					if (structured != null && structured.checked_call != null) {
						continue;
					}
					var value = evaluation != null ? evaluation.value : structured == null ? null : structured.call;
					var invocation = value as CfgFunctionValueCall;
					var closure = value as CfgClosureCall;
					if (invocation == null && closure == null) {
						continue;
					}
					var signature = (invocation == null ? closure.callee.semantic_type : invocation.callee.semantic_type) as CallableSignature;
					var channels = invocation == null ? closure.channel_parameters : invocation.channel_parameters;
					if (signature == null || channels.length != (signature.has_owner_channels () ? signature.parameter_types.length : 0)) {
						fail (path, "indirect call lost its complete call-owned channel declarations");
					}
					for (int p = 0; p < channels.length; p++) {
						var channel = channels[p];
						if (channel.ordinal != p || channel.semantic_type != signature.parameter_types[p] || channel.pointer_contract != signature.parameter_contract (p) || channel.heap_object != CallableRecordGroups.heap_parameter (signature, p) || channel.requires_nonnull) {
							fail (path, "indirect call channel differs from its signature");
						}
						StructBoundaryGroup? record_channel = null;
						foreach (var group in ((signature is FunctionValueType) ? ((FunctionValueType) signature).record_parameters : ((ClosureHandleType) signature).record_parameters)) {
							if (group.source_ordinal == p) {
								record_channel = group;
							}
						}
						verify_parameter_contract (channel, path + "/call-channel", false, false, record_channel);
					}
				}
			}
			verify_buffer_exchanges (function);
			verify_enum_owner_captures (function);
			int parameter_rank = 0;
			foreach (var parameter in function.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER) {
					continue;
				}
				if (parameter_rank >= function.entry.instructions.length) {
					fail (path, "missing owned parameter acquisition");
				}
				var acquisition = function.entry.instructions[parameter_rank++] as CfgAcquireParameter;
				if (acquisition == null || acquisition.acquisition == null || acquisition.acquisition.incoming_parameter != parameter) {
					fail (path, "owned parameters must acquire at entry in declaration order");
				}
			}
			verify_struct_parameter_acquisitions (function, parameter_rank, path);
			var constructor_flow = (function is CfgConstructor) ? new CfgConstructorInitialization ((CfgConstructor) function, struct_fields) : null;
			initialized.remove_all ();
			verify_resource_epilogues (function);
			verify_slots_loans (function);
			CfgAllocationFailureVerifier.verify (function);
			for (int j = 0; j < function.blocks.length; j++) {
				var block = function.blocks[j];
				string block_path = path + "/block #%d".printf (j);
				current_block = block;
				field_state = constructor_flow == null ? null : constructor_flow.at_entry (block);
				available_constructors.remove_all ();
				available_results.remove_all ();
				available_evaluations.remove_all ();
				available_arrays.remove_all ();
				available_borrows.remove_all ();
				for (int k = 0; k < block.instructions.length; k++) {
					verify_instruction (block.instructions[k], function, block_path + "/instruction #%d".printf (k));
				}
				if (pending_acquisition != null) {
					fail (block_path, "owned producer result must be consumed immediately by acquisition or rearm");
				}
				if (pending_commit != null) {
					fail (block_path, "transfer commit must immediately precede its native call");
				}
				current_instruction = null;
				verify_terminator (block.terminator, function, block_path + "/terminator");
			}
			for (int j = 0; j < function.temporaries.length; j++) {
				if (!initialized.contains (function.temporaries[j])) {
					fail (path + "/temporary #%d".printf (j), "temporary must have exactly one initialization");
				}
			}
			foreach (var place in function.field_places) {
				if (!(place.semantic_type is StructType) && !initialized.contains (place)) {
					fail ("field " + place.field.name, "field must have exactly one initialization");
				}
			}
			for (int j = 0; j < function.locals.length; j++) {
				if (function.locals[j].semantic_type.kind != TypeKind.STRUCT && !initialized.contains (function.locals[j])) {
					fail (path + "/local #%d".printf (j), "local must have exactly one initialization");
				}
			}
		}
		foreach (var group in struct_results.get_keys ()) {
			if (!consumed_struct_results.contains (group)) {
				fail ("struct-result", "every struct call result requires one bounded complete consumer");
			}
		}
		foreach (var value in evaluated_results.get_keys ()) {
			if (value is CfgPendingOwnedArgument && !used_transfers.contains ((CfgPendingOwnedArgument) value)) {
				fail ("owned-call", "pending ownership capture has no unique native call consumer");
			}
			if (value is CfgOwnedReturnValue && !used_returns.contains ((CfgOwnedReturnValue) value)) {
				fail ("owned-return", "owned return capture has no unique return consumer");
			}
		}
		if (borrow_definitions.size () != used_borrows.size ()) {
			fail ("borrow", "borrow event must supply exactly one borrowed call argument");
		}
	}

	private void reject_stored_owner(CfgValue value, string path) throws CfgError {
		if (value is CfgEvaluatedValue && exception_takes.contains ((CfgEvaluatedValue) value) && current_instruction is CfgStore && ((CfgStore) current_instruction).target is CfgExceptionStorage) {
			return;
		}
		if (value is CfgEvaluatedValue && resource_consumers.lookup ((CfgEvaluatedValue) value) == current_instruction) {
			return;
		}
		var seen = new HashTable<CfgValue, CfgValue> (direct_hash, direct_equal);
		while (value is CfgEvaluatedValue && evaluated_sources.contains ((CfgEvaluatedValue) value)) {
			if (seen.contains (value)) {
				fail (path, "cyclic evaluated owner value");
			}
			seen.insert (value, value);
			value = evaluated_sources.lookup ((CfgEvaluatedValue) value);
		}
		var load = value as CfgLoadValue;
		var owner = load == null ? null : load.source as CfgLocalPlace;
		if (value is CfgBufferBorrowValue || (owner != null && owner.buffer_group != null) || (load != null && load.source is CfgIndirectFieldPlace && load.semantic_type is SliceType) || (value is CfgParameterValue && value.semantic_type is SliceType && ((CfgParameterValue) value).parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER)) {
			fail (path, "borrowed buffer views cannot be stored as persistent aliases or copied owners");
		}
		if (owner != null && owner.cleanup != null && owner.semantic_type is ClassType) {
			fail (path, "persistent alias from transferable object owner is unsupported");
		}
	}

	private static bool invalidates_buffer_field(CfgInstruction instruction, CfgIndirectFieldPlace place) {
		var type = place.field.containing_type.semantic_type;
		var exchange = instruction as CfgBufferExchange;
		if (exchange != null) {
			foreach (var slot in new CfgPlace[] { exchange.left, exchange.right }) {
				var field = slot as CfgIndirectFieldPlace;
				if (field != null && field.field.containing_type.semantic_type == type) {
					return true;
				}
			}
		}
		var call = instruction as CfgCallInstruction;
		if (call != null) {
			var receiver = call.receiver == null ? null : call.receiver.semantic_type as ReceiverType;
			if (receiver != null && receiver.instance_type == type) {
				return true;
			}
			foreach (var argument in call.arguments) {
				if (argument.semantic_type == type) {
					return true;
				}
			}
		}
		var store = instruction as CfgStore;
		if (store != null && store.target is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) store.target).field.containing_type.semantic_type == type) {
			return true;
		}
		var cleanup = instruction as CfgCleanupInstruction;
		var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
		return load != null && load.source is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) load.source).field.containing_type.semantic_type == type;
	}

	private void verify_buffer_field_interval(CfgEvaluatedValue value, CfgFunction function, string path) throws CfgError {
		var place = buffer_field_views.lookup (value);
		if (place == null) {
			return;
		}
		var origin = definition_blocks.lookup (value);
		bool[] reaches = new bool[function.blocks.length];
		reaches[current_block.ordinal] = true;
		bool changed = false;
		do {
			changed = false;
			foreach (var block in function.blocks) {
				if (block == origin || reaches[block.ordinal]) {
					continue;
				}
				foreach (var next in block.terminator.successors ()) {
					if (reaches[next.ordinal]) {
						reaches[block.ordinal] = true;
						changed = true;
						break;
					}
				}
			}
		} while (changed);
		bool[] visited = new bool[function.blocks.length];
		var pending = new GenericArray<CfgBlock> ();
		pending.add (origin);
		for (int p = 0; p < pending.length; p++) {
			var block = pending[p];
			if (visited[block.ordinal]) {
				continue;
			}
			visited[block.ordinal] = true;
			bool started = block != origin;
			foreach (var instruction in block.instructions) {
				if (!started) {
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation != null && evaluation.result == value) {
						started = true;
					}
					continue;
				}
				if (block == current_block && instruction == current_instruction) {
					break;
				}
				if (invalidates_buffer_field (instruction, place)) {
					fail (path, "buffer field borrow outlives possible owner replacement or destruction");
				}
			}
			if (block == current_block) {
				continue;
			}
			foreach (var next in block.terminator.successors ()) {
				if (next != origin && reaches[next.ordinal]) {
					pending.add (next);
				}
			}
		}
		if (current_instruction is CfgCallInstruction && invalidates_buffer_field (current_instruction, place)) {
			fail (path, "buffer field borrow overlaps a possibly aliasing object call");
		}
	}

	private void verify_transfer_source(CfgLocalPlace source, SemanticType type, CfgCleanupContract cleanup, CfgFunction function, string path) throws CfgError {
		if (source.semantic_type.is_scoped_allocator ()) {
			fail (path, "scoped context cannot leave its exact lexical backing loan");
		}
		verify_place (source, function, path);
		if ((source.semantic_type != type || source.cleanup != cleanup) && !heap_transfer (source.semantic_type, source.cleanup, type, cleanup)) {
			fail (path, "ownership transfer source requires exact nominal type and cleanup contract");
		}
	}

	private void verify_buffer_slot(CfgPlace slot, CfgCleanupContract cleanup, CfgFunction function, string path) throws CfgError {
		if (!cleanups.contains (cleanup) || !cleanup.is_buffer) {
			fail (path, "buffer slot requires program-owned buffer cleanup");
		}
		verify_place (slot, function, path);
		var local = slot as CfgLocalPlace;
		var field = slot as CfgIndirectFieldPlace;
		if (slot.semantic_type != cleanup.buffer_type || (local == null ? field == null || !(field.field.containing_type is CfgClass) : local.cleanup != cleanup || local.buffer_group == null)) {
			fail (path, "buffer exchange requires exact local/field owner slots and cleanup");
		}
		if (field != null && field_state != null && field.pointer is CfgReceiverValue && !field_state.is_definite (field.field.ordinal)) {
			fail (path, "buffer slot capture requires a definitely initialized field");
		}
	}

	private CfgFunction? incoming_origin_function;
	private HashTable<CfgLocalPlace, CfgOwnershipTransferInstruction> incoming_transfers = new HashTable<CfgLocalPlace, CfgOwnershipTransferInstruction> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, bool> duplicate_incoming_transfers = new HashTable<CfgLocalPlace, bool> (direct_hash, direct_equal);
	private HashTable<CfgLocalPlace, bool> incoming_origin_cache = new HashTable<CfgLocalPlace, bool> (direct_hash, direct_equal);
	private bool incoming_local_owner(CfgFunction function, CfgLocalPlace owner) {
		if (caller_result_origins != null) {
			var equation = caller_result_origins.inputs (function, owner);
			if (equation.domains == 0 && equation.input_count != 0) {
				bool inputs_valid = true;
				for (int i = 0; i < equation.input_count; i++) {
					int ordinal = equation.input (i);
					if (ordinal < 0 || ordinal >= function.parameters.length) {
						inputs_valid = false;
						break;
					}
					var parameter = function.parameters[ordinal];
					inputs_valid &= parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER
					    && parameter.semantic_type == owner.semantic_type && !parameter.heap_object;
				}
				if (inputs_valid) {
					return true;
				}
			}
		}
		if (incoming_origin_function != function) {
			incoming_origin_function = function;
			incoming_transfers.remove_all ();
			duplicate_incoming_transfers.remove_all ();
			incoming_origin_cache.remove_all ();
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var transfer = instruction as CfgOwnershipTransferInstruction;
					if (transfer == null) {
						continue;
					}
					if (incoming_transfers.contains (transfer.destination)) {
						duplicate_incoming_transfers.insert (transfer.destination, true);
					}
					incoming_transfers.insert (transfer.destination, transfer);
				}
			}
		}
		if (incoming_origin_cache.contains (owner)) {
			return incoming_origin_cache.lookup (owner);
		}
		var seen = new HashTable<CfgLocalPlace, bool> (direct_hash, direct_equal);
		var root = owner;
		bool valid = false;
		while (true) {
			if (incoming_origin_cache.contains (root)) {
				valid = incoming_origin_cache.lookup (root);
				break;
			}
			if (seen.contains (root) || root.object_storage != null) {
				break;
			}
			seen.insert (root, true);
			if (root.incoming_parameter != null) {
				var parameter = root.incoming_parameter;
				if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || parameter.semantic_type != owner.semantic_type
				    || parameter.heap_object || root.cleanup != owner.cleanup || !function.parameters.find (parameter)) {
					break;
				}
				foreach (var instruction in function.entry.instructions) {
					var acquire = instruction as CfgAcquireParameter;
					var value = acquire == null ? null : acquire.value as CfgParameterValue;
					if (acquire != null && acquire.acquisition == root && value != null && value.parameter == parameter) {
						valid = true;
						break;
					}
				}
				break;
			}
			var transfer = incoming_transfers.lookup (root);
			if (transfer == null || duplicate_incoming_transfers.contains (root) || transfer.cleanup != owner.cleanup
			    || transfer.source.semantic_type != owner.semantic_type || transfer.source.cleanup != owner.cleanup) {
				break;
			}
			root = transfer.source;
		}
		foreach (var local in seen.get_keys ()) {
			incoming_origin_cache.insert (local, valid);
		}
		return valid;
	}

	private bool null_local_owner(CfgFunction function, CfgLocalPlace owner) {
		var equation = caller_result_origins.inputs (function, owner);
		return equation.domains == 0 && equation.input_count == 0;
	}

	private bool incoming_local_transfer(CfgFunction function, CfgOwnershipTransferInstruction transfer) {
		if (transfer.destination.incoming_parameter != null || transfer.destination.object_storage != null
		    || transfer.source.semantic_type != transfer.destination.semantic_type || transfer.source.cleanup != transfer.destination.cleanup) {
			return false;
		}
		if (incoming_local_owner (function, transfer.source) || null_local_owner (function, transfer.source)) {
			return true;
		}

		// A local caller-result allocation may move only into a destination
		// whose lexical extent is contained in the original backing extent.
		var root = transfer.source;
		var seen = new HashTable<CfgLocalPlace, bool> (direct_hash, direct_equal);
		while (incoming_transfers.contains (root)) {
			if (seen.contains (root) || duplicate_incoming_transfers.contains (root)) {
				return false;
			}
			seen.insert (root, true);
			root = incoming_transfers.lookup (root).source;
		}
		if (root.text_extent == null || transfer.destination.text_extent == null
		    || !root.text_extent.outlives (transfer.destination.text_extent)) {
			return false;
		}
		CfgInitialize? acquisition = null;
		CfgCallInstruction? producer = null;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var initialized = instruction as CfgInitialize;
				if (initialized != null && initialized.acquisition == root) {
					if (acquisition != null) {
						return false;
					}
					acquisition = initialized;
				}
			}
		}
		if (acquisition == null) {
			return false;
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as CfgCallInstruction;
				if (call != null && call.result == acquisition.value) {
					producer = call;
				}
			}
		}
		return producer != null && producer.candidate_storage != null && producer.candidate_storage.result_candidate
		       && producer.candidate_storage.semantic_type == root.semantic_type
		       && producer.candidate_storage.region_ordinal == root.text_extent.ordinal;
	}

	private static bool invalidates_buffer_slot(CfgInstruction instruction, CfgPlace slot) {
		var enumeration = instruction as CfgEnumConstruct;
		if (enumeration != null) {
			foreach (var input in enumeration.fields) {
				if ((input.buffer != null && input.buffer.source == slot) || (input.scalar_owner != null && input.scalar_owner.source == slot)) {
					return true;
				}
			}
		}
		var field = slot as CfgIndirectFieldPlace;
		if (field != null && invalidates_buffer_field (instruction, field)) {
			return true;
		}
		var exchange = instruction as CfgBufferExchange;
		if (exchange != null && (exchange.left == slot || exchange.right == slot)) {
			return true;
		}
		var store = instruction as CfgStore;
		if (store != null && store.target == slot) {
			return true;
		}
		var initialize = instruction as CfgInitialize;
		if (initialize != null && initialize.target == slot) {
			return true;
		}
		var resource = instruction as CfgResourceCapture;
		var argument = instruction as CfgOwnedArgumentCapture;
		var returned = instruction as CfgOwnershipReturnInstruction;
		var transfer = instruction as CfgOwnershipTransferInstruction;
		var rearm = instruction as CfgOwnershipRearmInstruction;
		var release = instruction as CfgOwnershipReleaseInstruction;
		var cleanup = instruction as CfgCleanupInstruction;
		CfgLocalPlace? source = resource != null ? resource.source : argument != null ? argument.transfer.source : returned != null ? returned.result.source : transfer != null ? transfer.source : rearm != null ? rearm.source : null;
		CfgLocalPlace? destination = transfer != null ? transfer.destination : rearm != null ? rearm.owner : release != null ? release.owner : null;
		var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
		if (source == slot || destination == slot || (load != null && load.source == slot)) {
			return true;
		}
		if (field == null) {
			return false;
		}
		var type = field.field.containing_type.semantic_type;
		return (source != null && source.semantic_type == type) || (destination != null && destination.semantic_type == type) || (cleanup != null && cleanup.value.semantic_type == type);
	}

	private void verify_enum_owner_captures(CfgFunction function) throws CfgError {
		var sites = new HashTable<CfgInstruction, CfgBlock> (direct_hash, direct_equal);
		var positions = new HashTable<CfgInstruction, int> (direct_hash, direct_equal);
		var consumed = new HashTable<CfgInstruction, bool> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				sites.insert (block.instructions[i], block);
				positions.insert (block.instructions[i], i);
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var construction = instruction as CfgEnumConstruct;
				if (construction == null) {
					continue;
				}
				foreach (var input in construction.fields) {
					CfgInstruction? capture = input.scalar_owner != null ? (CfgInstruction) input.scalar_owner : input.buffer;
					if (capture == null) {
						continue;
					}
					var source = input.scalar_owner != null ? input.scalar_owner.source : input.buffer.source;
					bool fresh = input.buffer != null && input.buffer.fresh_staged;
					bool invalid_source = input.scalar_owner != null ? source == null : (source == null) == (input.buffer.producer == null) || input.buffer.cleanup.buffer_type != input.field.semantic_type;
					if (!sites.contains (capture) || consumed.contains (capture) || invalid_source) {
						fail ("enum owner", "each exact owner capture requires one complete constructor consumer");
					}
					consumed.insert (capture, true);
					current_block = block;
					if (sites.lookup (capture) == block ? positions.lookup (capture) >= positions.lookup (construction) : !block_available_on_entry (sites.lookup (capture), function)) {
						fail ("enum owner", "capture must precede and dominate its exact constructor commit");
					}
					var pending = new GenericArray<CfgBlock> ();
					var states = new GenericArray<int> ();
					var visited = new HashTable<CfgBlock, int> (direct_hash, direct_equal);
					pending.add (sites.lookup (capture));
					states.add (0);
					for (int p = 0; p < pending.length; p++) {
						var candidate = pending[p];
						int state = states[p];
						int bit = 1 << state;
						if ((visited.lookup (candidate) & bit) != 0) {
							continue;
						}
						visited.insert (candidate, visited.lookup (candidate) | bit);
						int first = candidate == sites.lookup (capture) ? positions.lookup (capture) + 1 : 0;
						for (int j = first; j < candidate.instructions.length; j++) {
							var effect = candidate.instructions[j];
							var buffer_abort = effect as CfgEnumBufferAbort;
							var scalar_abort = effect as CfgEnumScalarAbort;
							bool aborts = (buffer_abort != null && buffer_abort.capture == capture) || (scalar_abort != null && scalar_abort.capture == capture);
							if (aborts || effect == construction) {
								if (state != 0) {
									fail ("enum owner", "reservation was already committed or aborted on this edge");
								}
								if (aborts && fresh) {
									var release = j + 1 < candidate.instructions.length ? candidate.instructions[j + 1] as CfgOwnershipReleaseInstruction : null;
									if (release == null || release.owner != source || release.cleanup != input.buffer.cleanup) {
										fail ("enum owner", "abandoned fresh capture requires its exact immediate owner release");
									}
								}
								state = aborts ? 1 : 2;
							} else if (state == 0 && (effect == capture || (source != null && invalidates_buffer_slot (effect, source)))) {
								fail ("enum owner", "reserved source was invalidated before its exact constructor commit");
							}
						}
						var successors = candidate.terminator.successors ();
						if (successors.length == 0 && state == 0 && !(candidate.terminator is CfgAllocationFailureTrap)) {
							fail ("enum owner", "capture reaches a normal exit without commit or abort");
						}
						foreach (var successor in successors) {
							if (successor == sites.lookup (capture)) {
								if (state == 0) {
									fail ("enum owner", "capture repeats before its disposition");
								}
							} else {
								pending.add (successor);
								states.add (state);
							}
						}
					}
				}
			}
		}
		foreach (var instruction in sites.get_keys ()) {
			if ((instruction is CfgEnumBufferCapture || instruction is CfgEnumScalarCapture) && !consumed.contains (instruction)) {
				fail ("enum owner", "orphan owning payload capture");
			}
		}
	}

	private void verify_buffer_exchanges(CfgFunction function) throws CfgError {
		bool present = false;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is CfgBufferSlotCapture || instruction is CfgBufferExchange) {
					present = true;
				}
			}
		}
		if (!present) {
			return;
		}
		var sites = new HashTable<CfgInstruction, CfgBlock> (direct_hash, direct_equal);
		var positions = new HashTable<CfgInstruction, int> (direct_hash, direct_equal);
		var consumed = new HashTable<CfgBufferSlotCapture, bool> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var instruction = block.instructions[i];
				if (sites.contains (instruction)) {
					fail ("buffer exchange", "repeated instruction identity");
				}
				sites.insert (instruction, block);
				positions.insert (instruction, i);
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var exchange = instruction as CfgBufferExchange;
				if (exchange == null) {
					continue;
				}
				CfgInstruction[] ordered = {
					exchange.left_capture, exchange.right_capture, exchange
				};
				for (int i = 0; i < 2; i++) {
					var capture = (CfgBufferSlotCapture) ordered[i];
					var next = ordered[i + 1];
					if (!sites.contains (capture) || !sites.contains (next) || consumed.contains (capture)) {
						fail ("buffer exchange", "each slot capture must belong to this function and one exchange operand");
					}
					consumed.insert (capture, true);
					current_block = sites.lookup (next);
					if (sites.lookup (capture) == current_block ? positions.lookup (capture) >= positions.lookup (next) : !block_available_on_entry (sites.lookup (capture), function)) {
						fail ("buffer exchange", "left capture must precede and dominate right capture, then exchange");
					}
					var pending = new GenericArray<CfgBlock> ();
					var visited = new HashTable<CfgBlock, bool> (direct_hash, direct_equal);
					pending.add (sites.lookup (capture));
					for (int p = 0; p < pending.length; p++) {
						var candidate = pending[p];
						if (visited.contains (candidate)) {
							continue;
						}
						visited.insert (candidate, true);
						int first = candidate == sites.lookup (capture) ? positions.lookup (capture) + 1 : 0;
						bool committed = false;
						for (int j = first; j < candidate.instructions.length; j++) {
							var effect = candidate.instructions[j];
							if (effect == exchange) {
								committed = true;
								break;
							}
							if (effect == capture || invalidates_buffer_slot (effect, capture.place)) {
								fail ("buffer exchange", "captured slot or containing object is invalidated before exchange");
							}
						}
						if (committed) {
							continue;
						}
						var successors = candidate.terminator.successors ();
						if (successors.length == 0 && !(candidate.terminator is CfgAllocationFailureTrap)) {
							fail ("buffer exchange", "slot capture reaches a normal exit without its exchange");
						}
						foreach (var successor in successors) {
							if (successor == sites.lookup (capture)) {
								fail ("buffer exchange", "slot capture can repeat before its exchange");
							}
							pending.add (successor);
						}
					}
				}
			}
		}
		foreach (var instruction in sites.get_keys ()) {
			if (instruction is CfgBufferSlotCapture && !consumed.contains ((CfgBufferSlotCapture) instruction)) {
				fail ("buffer exchange", "orphan slot capture");
			}
		}
	}

	// Walk every executable path after capture, stopping only at this commit.
	// This proof also covers later arguments containing short-circuit regions.
	private bool guarded_exception_success(CfgCallInstruction call, CfgFunction function) {
		return guarded_effect_success (call.exception_result, function);
	}

	private bool guarded_effect_success(CfgValue? exception, CfgFunction function) {
		if (exception == null) {
			return false;
		}
		var origin = definition_blocks.lookup (exception);
		var branch = origin == null ? null : origin.terminator as CfgConditionalBranch;
		var condition = branch == null ? null : branch.condition as CfgBinaryValue;
		return condition != null && condition.operator_kind == BinaryOperator.EQUAL && condition.left == exception && condition.right is CfgNullPointerValue && (current_block == branch.true_target || block_available_on_entry (branch.true_target, function)) && current_block != branch.false_target && !block_available_on_entry (branch.false_target, function);
	}

	private bool guarded_exception_catch(CfgCatchBorrow caught, CfgFunction function) {
		foreach (var block in function.blocks) {
			var branch = block.terminator as CfgConditionalBranch;
			var match = branch == null ? null : branch.condition as CfgExceptionMatch;
			if (match != null && match.exception == caught.exception && match.match_type == caught.semantic_type && (current_block == branch.true_target || block_available_on_entry (branch.true_target, function)) && current_block != branch.false_target && !block_available_on_entry (branch.false_target, function)) {
				return true;
			}
		}
		return false;
	}

	private void verify_pending_interval(CfgPendingOwnedArgument transfer, CfgOwnedCallTransferCommit commit, CfgFunction function, string path) throws CfgError {
		var start = definition_blocks.lookup (transfer);
		if (start == null) {
			fail (path, "pending transfer has no capture definition");
		}
		var pending = new GenericArray<CfgBlock> ();
		var visited = new HashTable<CfgBlock, CfgBlock> (direct_hash, direct_equal);
		pending.add (start);
		for (int b = 0; b < pending.length; b++) {
			var block = pending[b];
			if (!visited.insert (block, block)) {
				continue;
			}
			bool after_capture = block != start;
			bool committed = false;
			foreach (var instruction in block.instructions) {
				if (!after_capture) {
					var capture = instruction as CfgOwnedArgumentCapture;
					if (capture != null && capture.transfer == transfer) {
						after_capture = true;
					}
					continue;
				}
				if (instruction == commit) {
					committed = true;
					break;
				}
				if (instruction is CfgOwnedArgumentAbort && ((CfgOwnedArgumentAbort) instruction).transfer == transfer) {
					committed = true;
					break;
				}
				var cleanup = instruction as CfgCleanupInstruction;
				// Expressions cannot perform lexical cleanup, explicit release or
				// rearm. Callee-internal effects remain inside their native call.
				var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
				var release = instruction as CfgOwnershipReleaseInstruction;
				var rearm = instruction as CfgOwnershipRearmInstruction;
				if (transfer.source != null && ((load != null && load.source == transfer.source) || (release != null && release.owner == transfer.source) || (rearm != null && rearm.owner == transfer.source))) {
					fail (path, "pending source cannot be cleaned or rearmed between capture and commit");
				}
			}
			if (committed) {
				continue;
			}
			var successors = block.terminator.successors ();
			if (successors.length == 0) {
				fail (path, "pending capture reaches an exit before its native call commit");
			}
			foreach (var successor in successors) {
				pending.add (successor);
			}
		}
	}

	private GenericArray<SemanticType>? struct_fields(SemanticType type) {
		var structure = structs.lookup (type) as CfgStruct;
		if (structure == null) {
			return null;
		}
		var fields = new GenericArray<SemanticType> ();
		foreach (var field in structure.fields) {
			fields.add (field.semantic_type);
		}
		return fields;
	}

	private void verify_record_field(CfgIndirectFieldPlace place, CfgFunction function, string path) throws CfgError {
		verify_place (place, function, path);
		var cleanup = place.field.owned_cleanup;
		if (!(place.field.containing_type is CfgClass) || !(place.semantic_type is StructType) || cleanup == null || cleanup.record_type == null || cleanup.record_type.semantic_type != place.semantic_type || !cleanups.contains (cleanup) || !matches_cleanup (place.semantic_type, cleanup)) {
			fail (path, "inline record field lost exact Class storage and recursive cleanup authority");
		}
	}

	private void verify_struct_shape(StructValueShape? shape, SemanticType type, string path) throws CfgError {
		if (shape == null || !(type is StructType) || shape.semantic_type != type) {
			fail (path, "struct boundary requires exact concrete StructType shape");
			return;
		}
		try {
			shape.verify (struct_fields);
		} catch (StructLeafError error) {
			fail (path, error.message);
		}
		foreach (var leaf in shape.leaves) {
			verify_type (leaf.semantic_type, true, path + "/leaf");
		}
	}

	private void verify_struct_parameter_groups(CfgFunction function, string path) throws CfgError {
		int physical = 0;
		int logical = 0;
		int group_index = 0;
		while (physical < function.parameters.length) {
			var group = group_index < function.struct_parameters.length ? function.struct_parameters[group_index] : null;
			if (group != null && group.first_leaf <= physical) {
				if (group.first_leaf != physical || group.source_ordinal != logical || group.shape.leaves.length > function.parameters.length - physical) {
					fail (path, "struct parameter grouping must preserve complete ordered source positions");
				}
				verify_struct_shape (group.shape, group.shape.semantic_type, path + "/parameter");
				if (group.shape.mode == StructValueMode.BORROW_VALUE && function.async_body != null) {
					fail (path, "borrowed record parameter cannot enter an async frame");
				}
				foreach (var leaf in group.shape.leaves) {
					var parameter = function.parameters[physical++];
					var contract = group.shape.mode == StructValueMode.BORROW_VALUE && (leaf.semantic_type is ClassType || leaf.semantic_type is HandleType || leaf.semantic_type is SliceType) ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED;
					if (parameter.semantic_type != leaf.semantic_type || parameter.pointer_contract != contract) {
						fail (path, "struct parameter leaves require exact ordered copy, move or borrowed channels");
					}
				}
				group_index++;
			} else {
				physical++;
			}
			logical++;
		}
		if (group_index != function.struct_parameters.length) {
			fail (path, "struct parameter grouping exceeds leaf parameters");
		}
	}

	private bool matches_struct_leaf(CfgPlace place, CfgPlace root, StructLeafPath path) {
		for (int d = path.depth - 1; d >= 0; d--) {
			var field = place as CfgFieldPlace;
			if (field == null || field.field.ordinal != path.field_ordinal (d) || structs.lookup (field.aggregate.semantic_type) != field.field.containing_type) {
				return false;
			}
			place = field.aggregate;
		}
		return place == root;
	}

	private CfgFieldPlace boundary_leaf(CfgFunction function, CfgPlace root, StructLeafPath leaf, string path) throws CfgError {
		foreach (var field in function.field_places) {
			if (field.semantic_type == leaf.semantic_type && matches_struct_leaf (field, root, leaf)) {
				return field;
			}
		}
		fail (path, "record boundary requires every original declared projection");
		assert_not_reached ();
	}

	private void verify_boundary_acquire(CfgStructBoundaryAcquire acquire, CfgFunction function, string path) throws CfgError {
		var root = acquire.destination;
		var target = acquire.target;
		verify_struct_shape (acquire.shape, target.semantic_type, path);
		int sources = (acquire.parameter == null ? 0 : 1) + (acquire.results == null ? 0 : 1) + (acquire.record_move == null ? 0 : 1);
		if (acquire.shape.mode != StructValueMode.MOVE_VALUE || !function.locals.find (root) || root.cleanup == null || root.cleanup.record_type == null || root.cleanup.record_type.semantic_type != root.semantic_type || initialized.contains (target) || acquire.leaves.length != acquire.shape.leaves.length || sources != 1) {
			fail (path, "record boundary acquisition requires one fresh exact target and a complete original parameter, result or move group");
		}
		if (acquire.projection != null && (acquire.projection.root_local () != root || !function.field_places.find (acquire.projection) || acquire.parameter != null)) {
			fail (path, "record subobject requires its exact declared projection and lexical root");
		}
		if (acquire.parameter != null) {
			if (!function.struct_parameters.find (acquire.parameter) || root.struct_parameter != acquire.parameter || acquire.parameter.shape != acquire.shape || current_block != function.entry) {
				fail (path, "record parameter acquisition lost its exact entry group");
			}
		} else if (acquire.results != null) {
			var consumption = consumed_struct_results.lookup (acquire.results);
			if (consumption == null || consumption.destination != target || consumption.use_kind != StructResultUseKind.INITIALIZE || acquire.results.shape != acquire.shape) {
				fail (path, "record result acquisition requires its exact original complete result consumption");
			}
		} else {
			var move = acquire.record_move;
			if (move.consumer != acquire || move.shape != acquire.shape || move.leaves != acquire.leaves || move.source == root || move.use_kind != StructResultUseKind.INITIALIZE) {
				fail (path, "record subobject acquisition lost its original complete source move");
			}
		}
		for (int i = 0; i < acquire.leaves.length; i++) {
			var leaf = acquire.shape.leaves[i];
			var field = boundary_leaf (function, target, leaf, path);
			var value = acquire.leaves[i];
			if (initialized.contains (field) || value.semantic_type != field.semantic_type) {
				fail (path, "record boundary cannot repeat or retype a field acquisition");
			}
			if (acquire.parameter != null) {
				var incoming = value as CfgParameterValue;
				if (incoming == null || incoming.parameter != function.parameters[acquire.parameter.first_leaf + i]) {
					fail (path, "record parameter must acquire each original leaf once in declaration order");
				}
			} else if (acquire.results != null && value != acquire.results.leaves[i]) {
				fail (path, "record result acquisition changed an original leaf");
			}
			verify_value (value, function, path + "/leaf");
			initialized.insert (field, field);
		}
		initialized.insert (target, target);
		foreach (var field in function.field_places) {
			if (acquire.contains (field) && field.semantic_type is StructType) {
				initialized.insert (field, field);
			}
		}
	}

	private void verify_boundary_move(CfgStructBoundaryMove move, CfgFunction function, string path) throws CfgError {
		verify_struct_shape (move.shape, move.source.semantic_type, path);
		if (move.shape.mode != StructValueMode.MOVE_VALUE || !function.locals.find (move.source) || move.source.cleanup == null || move.source.cleanup.record_type == null || move.leaves.length != move.shape.leaves.length) {
			fail (path, "record MOVE_VALUE requires its exact root responsibility and complete captured leaves");
		}
		for (int i = 0; i < move.leaves.length; i++) {
			var captured = move.leaves[i] as CfgEvaluatedValue;
			var load = captured == null ? null : evaluated_sources.lookup (captured) as CfgLoadValue;
			if (load == null || load.source != boundary_leaf (function, move.source, move.shape.leaves[i], path)) {
				fail (path, "record MOVE_VALUE must capture every original source field before disarming");
			}
			if (load.semantic_type is SliceType) {
				int captures = 0;
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var capture = instruction as CfgRecordBufferCapture;
						if (capture != null && capture.result == captured && capture.field == load.source) {
							captures++;
						}
					}
				}
				if (captures != 1) {
					fail (path, "record buffer move requires its exact complete-pair field capture");
				}
			}
			verify_value (move.leaves[i], function, path + "/leaf");
		}
		var invocation = move.consumer as CfgInstruction;
		var call_moves = invocation == null ? null : CfgInvocationContracts.record_moves (invocation);
		var returned = move.consumer as CfgStructReturn;
		var enumeration = move.consumer as CfgEnumConstruct;
		var inserted = move.consumer as CfgSlotsRecordTransfer;
		var field_commit = move.consumer as CfgRecordFieldCommit;
		var subobject = move.consumer as CfgStructBoundaryAcquire;
		if (subobject != null) {
			int position = 0;
			while (position < current_block.instructions.length && current_block.instructions[position] != move) {
				position++;
			}
			if (move.use_kind != StructResultUseKind.INITIALIZE || subobject.record_move != move || subobject.shape != move.shape || subobject.leaves != move.leaves || position + 1 >= current_block.instructions.length || current_block.instructions[position + 1] != subobject) {
				fail (path, "record subobject move requires one exact immediate complete acquisition");
			}
			return;
		}
		if (field_commit != null) {
			var use_kind = field_commit.initializes ? StructResultUseKind.INITIALIZE : StructResultUseKind.ASSIGN;
			int position = 0;
			while (position < current_block.instructions.length && current_block.instructions[position] != move) {
				position++;
			}
			if (move.use_kind != use_kind || field_commit.record_move != move || field_commit.shape != move.shape || field_commit.leaves != move.leaves || position + 1 >= current_block.instructions.length || current_block.instructions[position + 1] != field_commit) {
				fail (path, "record field move requires one exact immediate complete commit");
			}
			return;
		}
		if (inserted != null) {
			if (move.use_kind != StructResultUseKind.CONTAINER_ELEMENT || inserted.record_move != move || inserted.shape != move.shape || inserted.leaves != move.leaves) {
				fail (path, "record slot insertion lost its exact complete move commit");
			}
			int position = 0;
			while (position < current_block.instructions.length && current_block.instructions[position] != move) {
				position++;
			}
			if (position + 1 >= current_block.instructions.length || current_block.instructions[position + 1] != inserted) {
				fail (path, "record slot move must immediately precede its original consumer");
			}
			return;
		}
		if (enumeration != null) {
			int uses = 0;
			foreach (var input in enumeration.fields) {
				if (input.record_move == move && input.field.owns_record && input.field.semantic_type == move.shape.semantic_type && input.leaves == move.leaves) {
					uses++;
				}
			}
			if (uses != 1 || move.use_kind != StructResultUseKind.ENUM_PAYLOAD || !current_block.instructions.find (enumeration)) {
				fail (path, "record enum payload requires one exact complete same-block constructor field commit");
			}
			bool found = false;
			foreach (var instruction in current_block.instructions) {
				if (instruction == move) {
					found = true;
					continue;
				}
				if (instruction == enumeration) {
					if (!found) {
						fail (path, "record enum commit must precede its original constructor");
					}
					break;
				}
				if (found && !(instruction is CfgStructBoundaryMove)) {
					fail (path, "record enum payload cannot commit before another payload effect");
				}
			}
		} else if (call_moves != null) {
			if (move.use_kind != StructResultUseKind.ARGUMENT || !call_moves.find (move) || !current_block.instructions.find (invocation)) {
				fail (path, "record argument move lost its exact same-block call commit");
			}
			bool found = false;
			foreach (var instruction in current_block.instructions) {
				if (instruction == move) {
					found = true;
					continue;
				}
				if (instruction == invocation) {
					if (!found) {
						fail (path, "record transfer must commit before its consumer");
					}
					break;
				}
				if (found && !(instruction is CfgStructBoundaryMove || instruction is CfgOwnedCallTransferCommit || instruction is CfgEnumCommit)) {
					fail (path, "record transfer cannot commit before another argument effect");
				}
			}
		} else if (returned == null || move.use_kind != StructResultUseKind.RETURN || returned.record_move != move || current_block.terminator != returned || returned.shape != move.shape || returned.leaves != move.leaves) {
			fail (path, "record return move lost its exact complete return consumer");
		}
	}

	private void verify_struct_parameter_acquisitions(CfgFunction function, int rank, string path) throws CfgError {
		foreach (var group in function.struct_parameters) {
			CfgLocalPlace? storage = null;
			foreach (var local in function.locals) {
				if (local.struct_parameter == group) {
					if (storage != null) {
						fail (path, "struct parameter has duplicate local storage");
					}
					storage = local;
				}
			}
			if (storage == null || storage.semantic_type != group.shape.semantic_type || storage.address_taken || storage.incoming_parameter != null) {
				fail (path, "struct parameter requires one independent local");
			}
			if (group.shape.mode == StructValueMode.BORROW_VALUE) {
				var binding = rank >= function.entry.instructions.length ? null : function.entry.instructions[rank++] as CfgStructParameterBorrow;
				if (binding == null || binding.destination != storage || binding.parameter != group || storage.cleanup != null) {
					fail (path, "borrowed record parameter requires one exact entry binding without cleanup");
				}
				continue;
			}
			if (group.shape.mode == StructValueMode.MOVE_VALUE) {
				var acquisition = rank >= function.entry.instructions.length ? null : function.entry.instructions[rank++] as CfgStructBoundaryAcquire;
				if (acquisition == null || acquisition.destination != storage || acquisition.parameter != group || storage.cleanup == null || storage.cleanup.record_type == null) {
					fail (path, "MOVE_VALUE parameter requires one complete entry acquisition and exact cleanup plan");
				}
				continue;
			}
			if (storage.cleanup != null) {
				fail (path, "copied struct parameter cannot acquire owner responsibility");
			}
			for (int i = 0; i < group.shape.leaves.length; i++) {
				if (rank >= function.entry.instructions.length) {
					fail (path, "missing struct parameter leaf acquisition");
				}
				var acquisition = function.entry.instructions[rank++] as CfgInitialize;
				var value = acquisition == null ? null : acquisition.value as CfgParameterValue;
				if (acquisition == null || value == null || value.parameter != function.parameters[group.first_leaf + i] || !matches_struct_leaf (acquisition.target, storage, group.shape.leaves[i])) {
					fail (path, "all struct parameter leaves must initialize in entry before body execution");
				}
			}
		}
		foreach (var local in function.locals) {
			if (local.struct_parameter != null) {
				bool found = false;
				foreach (var group in function.struct_parameters) {
					if (group == local.struct_parameter) {
						found = true;
					}
				}
				if (!found) {
					fail (path, "foreign struct parameter storage group");
				}
			}
		}
	}

	private void verify_struct_parameter_borrow(CfgStructParameterBorrow binding, CfgFunction function, string path) throws CfgError {
		var group = binding.parameter;
		var root = binding.destination;
		if (current_block != function.entry || !function.struct_parameters.find (group) || !function.locals.find (root) || root.struct_parameter != group || root.cleanup != null || root.address_taken || root.semantic_type != group.shape.semantic_type || group.shape.mode != StructValueMode.BORROW_VALUE || binding.leaves.length != group.shape.leaves.length || initialized.contains (root)) {
			fail (path, "record parameter borrow lost its exact complete fresh entry binding");
		}
		for (int i = 0; i < binding.leaves.length; i++) {
			var incoming = binding.leaves[i] as CfgParameterValue;
			var field = boundary_leaf (function, root, group.shape.leaves[i], path);
			if (incoming == null || incoming.parameter != function.parameters[group.first_leaf + i] || initialized.contains (field)) {
				fail (path, "record parameter borrow must bind each original ordered leaf exactly once");
			}
			initialized.insert (field, field);
		}
		initialized.insert (root, root);
		foreach (var field in function.field_places) {
			if (field.root_local () == root && field.semantic_type is StructType) {
				initialized.insert (field, field);
			}
		}
	}

	private void verify_record_argument_interval(CfgEvaluatedValue value, CfgLocalPlace root, CfgInstruction call, CfgFunction function, string path) throws CfgError {
		var start = definition_blocks.lookup (value);
		if (start == null) {
			fail (path, "record argument loan lost its exact captured field definition");
		}
		bool[] reaches = new bool[function.blocks.length];
		reaches[current_block.ordinal] = true;
		bool changed = false;
		do {
			changed = false;
			foreach (var block in function.blocks) {
				foreach (var next in block.terminator.successors ()) {
					if (reaches[next.ordinal] && !reaches[block.ordinal]) {
						reaches[block.ordinal] = true;
						changed = true;
					}
				}
			}
		} while (changed);
		if (!reaches[start.ordinal]) {
			fail (path, "record argument capture cannot reach its call");
		}
		var pending = new GenericArray<CfgBlock> ();
		bool[] seen = new bool[function.blocks.length];
		pending.add (start);
		seen[start.ordinal] = true;
		bool found = false;
		for (int b = 0; b < pending.length; b++) {
			var candidate = pending[b];
			bool active = candidate != start;
			foreach (var instruction in candidate.instructions) {
				var capture = instruction as CfgEvaluateInstruction;
				if (capture != null && capture.result == value) {
					active = true;
					continue;
				}
				if (!active) {
					continue;
				}
				if (instruction == call) {
					found = true;
					break;
				}
				var move = instruction as CfgStructBoundaryMove;
				var transfer = instruction as CfgOwnershipTransferInstruction;
				var take = instruction as CfgRecordTake;
				var replace = instruction as CfgRecordReplace;
				var cleanup = instruction as CfgCleanupInstruction;
				var release = instruction as CfgOwnershipReleaseInstruction;
				var store = instruction as CfgStore;
				var field = store == null ? null : store.target as CfgFieldPlace;
				if (move != null && move.source == root || transfer != null && transfer.source == root || take != null && take.source == root || replace != null && replace.owner == root || cleanup != null && cleanup.record_owner == root || release != null && release.owner == root || store != null && (store.target == root || field != null && field.root_local () == root)) {
					fail (path, "record argument loan overlaps source mutation or lifetime invalidation");
				}
			}
			if (!active) {
				fail (path, "record argument capture lost its original evaluation");
			}
			if (candidate == current_block) {
				continue;
			}
			foreach (var next in candidate.terminator.successors ()) {
				if (reaches[next.ordinal] && !seen[next.ordinal]) {
					seen[next.ordinal] = true;
					pending.add (next);
				}
			}
		}
		if (!found) {
			fail (path, "record argument loan lost its bounded consumer");
		}
	}

	private void verify_record_argument_loan(GenericArray<CfgValue> arguments, StructBoundaryGroup argument, CfgInstruction call, CfgFunction function, string path) throws CfgError {
		if (argument.shape.mode == StructValueMode.BORROW_VALUE) {
			var result_loan = argument as CfgStructBorrowResultArgument;
			if (result_loan != null) {
				var results = result_loan.results;
				var origin = struct_results.lookup (results) as CfgCallInstruction;
				var consumed = consumed_struct_results.lookup (results);
				if (origin == null || !(origin.target is CfgPropertyGetter) || origin.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW || results.shape.mode != StructValueMode.BORROW_VALUE || results.shape.semantic_type != argument.shape.semantic_type || results.leaves.length != argument.shape.leaves.length || consumed == null || consumed.use_kind != StructResultUseKind.OBSERVE) {
					fail (path, "record getter argument requires its exact complete observed noescape result");
				}
				for (int l = 0; l < results.leaves.length; l++) {
					if (arguments[argument.first_leaf + l] != results.leaves[l]) {
						fail (path, "record getter argument changed an original ordered result leaf");
					}
				}
				var property = ((CfgPropertyGetter) origin.target).property_member;
				verify_receiver_loan_interval (results.leaves[0], origin, property.declaring_type.semantic_type, true, function, path, "borrowed record argument");
			} else {
				var borrow = argument as CfgStructBorrowArgument;
				var root = borrow == null ? null : borrow.source;
				bool incoming = root != null && root.struct_parameter != null && root.struct_parameter.shape.mode == StructValueMode.BORROW_VALUE && function.struct_parameters.find (root.struct_parameter);
				if (root == null || !function.locals.find (root) || root.semantic_type != argument.shape.semantic_type || root.address_taken || (incoming ? root.cleanup != null : root.cleanup == null || root.cleanup.record_type == null)) {
					fail (path, "record argument loan requires its exact live owner or incoming borrowed binding");
				}
				for (int l = 0; l < argument.shape.leaves.length; l++) {
					var captured = arguments[argument.first_leaf + l] as CfgEvaluatedValue;
					var load = captured == null ? null : evaluated_sources.lookup (captured) as CfgLoadValue;
					if (load == null || load.source != boundary_leaf (function, root, argument.shape.leaves[l], path)) {
						fail (path, "record argument loan must capture every original declared source leaf");
					}
					verify_record_argument_interval (captured, root, call, function, path);
				}
			}
		} else if (argument is CfgStructBorrowArgument || argument is CfgStructBorrowResultArgument) {
			fail (path, "record loan cannot be relabeled as copied or owning transport");
		}
	}

	private void verify_struct_arguments(CfgCallInstruction call, CfgFunction function, string path) throws CfgError {
		if (call.struct_arguments.length != call.target.struct_parameters.length) {
			fail (path, "struct arguments require exact source parameter groups");
		}
		for (int i = 0; i < call.struct_arguments.length; i++) {
			var argument = call.struct_arguments[i];
			var parameter = call.target.struct_parameters[i];
			if (argument.first_leaf != parameter.first_leaf || argument.source_ordinal != parameter.source_ordinal || argument.shape.semantic_type != parameter.shape.semantic_type || argument.first_leaf < 0 || argument.shape.leaves.length > call.arguments.length - argument.first_leaf) {
				fail (path, "struct argument requires exact nominal type and ordered complete channels");
			}
			verify_struct_shape (argument.shape, parameter.shape.semantic_type, path);
			if (argument.shape.mode != parameter.shape.mode) {
				fail (path, "record argument cannot change its copy/move mode");
			}
			verify_record_argument_loan (call.arguments, argument, call, function, path);
			if (argument.shape.mode == StructValueMode.MOVE_VALUE) {
				int matches = 0;
				foreach (var move in call.record_moves) {
					if (!current_block.instructions.find (move) || move.consumer != call || move.shape != argument.shape || move.leaves.length != argument.shape.leaves.length) {
						continue;
					}
					bool exact = true;
					for (int l = 0; l < move.leaves.length; l++) {
						exact &= move.leaves[l] == call.arguments[argument.first_leaf + l];
					}
					if (exact) {
						matches++;
					}
				}
				if (matches != 1) {
					fail (path, "record argument requires one exact complete MOVE_VALUE commit");
				}
			}
			for (int l = 0; l < argument.shape.leaves.length; l++) {
				var leaf = call.arguments[argument.first_leaf + l];
				if (!(leaf is CfgEvaluatedValue || leaf is CfgCallResultValue)) {
					fail (path, "struct argument leaves must be snapshotted at argument evaluation");
				}
			}
		}
	}

	private void verify_struct_consumption(CfgStructResultConsume consumption, CfgFunction function, string path) throws CfgError {
		var group = consumption.results;
		if (!struct_results.contains (group) || consumed_struct_results.contains (group)) {
			fail (path, "struct result requires one complete bounded consumption after its call");
		}
		if (consumption.use_kind == StructResultUseKind.OBSERVE || group.shape.mode == StructValueMode.BORROW_VALUE) {
			var origin = struct_results.lookup (group) as CfgCallInstruction;
			if (consumption.use_kind != StructResultUseKind.OBSERVE || group.shape.mode != StructValueMode.BORROW_VALUE || consumption.destination != null || origin == null || origin.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW) {
				fail (path, "record observation requires one exact nonescaping borrowed getter result");
			}
			foreach (var leaf in group.leaves) {
				if (!available_results.contains (leaf)) {
					fail (path, "record observation requires the complete available borrowed result");
				}
			}
			consumed_struct_results.insert (group, consumption);
			return;
		}
		bool storage_use = consumption.use_kind == StructResultUseKind.INITIALIZE || consumption.use_kind == StructResultUseKind.ASSIGN;
		if (storage_use != (consumption.destination != null) || (!storage_use && consumption.use_kind != StructResultUseKind.ARGUMENT && consumption.use_kind != StructResultUseKind.RETURN && consumption.use_kind != StructResultUseKind.ENUM_PAYLOAD && consumption.use_kind != StructResultUseKind.CONTAINER_ELEMENT)) {
			fail (path, "invalid bounded struct result consumer");
		}
		foreach (var leaf in group.leaves) {
			if (!available_results.contains (leaf)) {
				fail (path, "struct result consumption requires all same-block call leaves");
			}
		}
		if (storage_use) {
			if (consumption.destination.semantic_type != group.shape.semantic_type) {
				fail (path, "struct result storage requires exact nominal type");
			}
			if (group.shape.mode == StructValueMode.MOVE_VALUE) {
				int position = 0;
				while (position < current_block.instructions.length && current_block.instructions[position] != consumption) {
					position++;
				}
				var acquire = position + 1 >= current_block.instructions.length ? null : current_block.instructions[position + 1] as CfgStructBoundaryAcquire;
				var field = position + 1 >= current_block.instructions.length ? null : current_block.instructions[position + 1] as CfgRecordFieldCommit;
				if (field != null) {
					if (field.results != group || field.destination != consumption.destination || field.shape != group.shape || field.record_move != null || consumption.use_kind != (field.initializes ? StructResultUseKind.INITIALIZE : StructResultUseKind.ASSIGN)) {
						fail (path, "record field result lost exact complete consumption");
					}
					consumed_struct_results.insert (group, consumption);
					return;
				}
				if (consumption.use_kind != StructResultUseKind.INITIALIZE || acquire == null || acquire.results != group || acquire.target != consumption.destination || acquire.shape != group.shape) {
					fail (path, "MOVE_VALUE result must initialize one exact complete owner before another effect");
				}
				consumed_struct_results.insert (group, consumption);
				return;
			}
			CfgPlace entry_root = consumption.destination;
			while (entry_root is CfgFieldPlace) {
				entry_root = ((CfgFieldPlace) entry_root).aggregate;
			}
			if (consumption.use_kind == StructResultUseKind.INITIALIZE && entry_root is CfgArrayElementPlace) {
				var root = (CfgArrayElementPlace) entry_root;
				initializing_array_entry = root;
				verify_place (consumption.destination, function, path + "/destination");
				initializing_array_entry = null;
				int next = 0;
				while (next < current_block.instructions.length && current_block.instructions[next] != consumption) {
					next++;
				}
				CfgArrayInitialize? entry = null;
				while (++next < current_block.instructions.length) {
					entry = current_block.instructions[next] as CfgArrayInitialize;
					if (entry != null || consumption.destination == root) {
						break;
					}
				}
				if (entry == null || entry.record_root != root || entry.elements.length != entry.record_fields.length) {
					fail (path, "struct result entry requires its complete same-block array initialization");
				}
				int first = -1;
				for (int i = 0; i < entry.elements.length; i++) {
					if (entry.elements[i] == group.leaves[0]) {
						if (first != -1) {
							fail (path, "duplicate struct result entry consumption");
						}
						first = i;
					}
				}
				if (first < 0 || first + group.leaves.length > entry.elements.length || (consumption.destination == root && entry.elements.length != group.leaves.length)) {
					fail (path, "struct result entry requires its complete exact leaf set");
				}
				for (int i = 0; i < group.leaves.length; i++) {
					if (entry.elements[first + i] != group.leaves[i] || !matches_struct_leaf (entry.record_fields[first + i], consumption.destination, group.shape.leaves[i])) {
						fail (path, "struct result entry must consume every exact ordered leaf");
					}
					for (int j = 0; j < entry.elements.length; j++) {
						if (j != first + i && entry.elements[j] == group.leaves[i]) {
							fail (path, "duplicate struct result field entry leaf");
						}
					}
				}
				consumed_struct_results.insert (group, consumption);
				return;
			}
			verify_place (consumption.destination, function, path + "/destination");
			int position = 0;
			while (position < current_block.instructions.length && current_block.instructions[position] != consumption) {
				position++;
			}
			for (int i = 0; i < group.leaves.length; i++) {
				if (++position >= current_block.instructions.length) {
					fail (path, "struct result storage requires every ordered leaf write");
				}
				var initialization = current_block.instructions[position] as CfgInitialize;
				var store = current_block.instructions[position] as CfgStore;
				var target = initialization != null ? initialization.target : store == null ? null : store.target;
				var value = initialization != null ? initialization.value : store == null ? null : store.value;
				if ((consumption.use_kind == StructResultUseKind.INITIALIZE) != (initialization != null) || target == null || value != group.leaves[i] || !matches_struct_leaf (target, consumption.destination, group.shape.leaves[i])) {
					fail (path, "struct result writes must consume the complete exact ordered leaf set");
				}
			}
		} else {
			int consumers = 0;
			foreach (var block in function.blocks) {
				if (consumption.use_kind == StructResultUseKind.CONTAINER_ELEMENT) {
					foreach (var instruction in block.instructions) {
						var transfer = instruction as CfgSlotsRecordTransfer;
						if (transfer == null || transfer.shape.semantic_type != group.shape.semantic_type || transfer.leaves.length != group.leaves.length) {
							continue;
						}
						bool exact = true;
						for (int l = 0; l < group.leaves.length; l++) {
							exact &= transfer.leaves[l] == group.leaves[l];
						}
						if (exact) {
							consumers++;
						}
					}
				} else if (consumption.use_kind == StructResultUseKind.ENUM_PAYLOAD) {
					foreach (var instruction in block.instructions) {
						var construction = instruction as CfgEnumConstruct;
						if (construction == null) {
							continue;
						}
						foreach (var field in construction.fields) {
							if (field.field.semantic_type != group.shape.semantic_type || field.leaves.length != group.leaves.length) {
								continue;
							}
							bool exact = true;
							for (int i = 0; i < group.leaves.length; i++) {
								if (field.leaves[i] != group.leaves[i]) {
									exact = false;
								}
							}
							if (exact) {
								consumers++;
							}
						}
					}
				} else if (consumption.use_kind == StructResultUseKind.RETURN) {
					var returned = block.terminator as CfgStructReturn;
					if (returned == null || returned.shape.semantic_type != group.shape.semantic_type || returned.leaves.length != group.leaves.length) {
						continue;
					}
					bool exact = true;
					for (int i = 0; i < group.leaves.length; i++) {
						if (returned.leaves[i] != group.leaves[i]) {
							exact = false;
						}
					}
					if (exact) {
						consumers++;
					}
				} else {
					foreach (var instruction in block.instructions) {
						var call = instruction as CfgCallInstruction;
						var foreign_call = instruction as CfgCCallInstruction;
						var evaluated = instruction as CfgEvaluateInstruction;
						var indirect = evaluated == null ? null : evaluated.value as CfgFunctionValueCall;
						var closure = (evaluated == null || instruction is CfgClosureCallSuccess) ? null : evaluated.value as CfgClosureCall;
						if (call == null && foreign_call == null && indirect == null && closure == null) {
							continue;
						}
						var arguments = closure != null ? closure.arguments : indirect != null ? indirect.arguments : call == null ? foreign_call.arguments : call.arguments;
						var groups = closure != null ? closure.struct_arguments : indirect != null ? indirect.struct_arguments : call == null ? foreign_call.struct_arguments : call.struct_arguments;
						foreach (var argument in groups) {
							if (argument.shape.semantic_type != group.shape.semantic_type || argument.first_leaf < 0 || group.leaves.length > arguments.length - argument.first_leaf) {
								continue;
							}
							bool exact = true;
							for (int i = 0; i < group.leaves.length; i++) {
								if (arguments[argument.first_leaf + i] != group.leaves[i]) {
									exact = false;
								}
							}
							if (exact) {
								consumers++;
							}
						}
					}
				}
			}
			if (consumers != 1) {
				fail (path, "forwarded struct result requires exactly one matching complete argument or return");
			}
		}
		consumed_struct_results.insert (group, consumption);
		foreach (var leaf in group.leaves) {
			verify_value (leaf, function, path + "/leaf");
		}
	}

	private void verify_resource_epilogues(CfgFunction function) throws CfgError {
		var destructor = function as CfgDestructor;
		if (destructor == null) {
			return;
		}
		foreach (var block in function.blocks) {
			if (!(block.terminator is CfgReturn || block.terminator is CfgFunctionEnd)) {
				continue;
			}
			int index = (int) block.instructions.length - 1;
			if (destructor.declaring_class.parent_class != null && destructor.declaring_class.parent_class.destructor != null) {
				var call = index < 0 ? null : block.instructions[index--] as CfgBaseLifecycleCall;
				var evaluation = index < 0 ? null : block.instructions[index--] as CfgEvaluateInstruction;
				var cast = evaluation == null ? null : evaluation.value as CfgClassUpcast;
				var self = cast == null ? null : cast.reference as CfgReceiverValue;
				if (call == null || cast == null || self == null || self.receiver != destructor.receiver || cast.source_class != destructor.declaring_class || cast.target_class != destructor.declaring_class.parent_class || call.receiver != evaluation.result || call.target != destructor.declaring_class.parent_class.destructor || call.arguments.length != 0) {
					fail ("base deinit", "normal destructor exit requires exact base teardown after declared field cleanup");
				}
			}
			// Reading backwards from the exit must encounter declaration order.
			foreach (var field in destructor.declaring_class.fields) {
				if (field.owned_cleanup != null && field.owned_cleanup.record_type != null) {
					var drop = index < 0 ? null : block.instructions[index--] as CfgRecordFieldDrop;
					var receiver = drop == null ? null : drop.source.pointer as CfgReceiverValue;
					if (receiver == null || receiver.receiver != destructor.receiver || drop.source.field != field) {
						fail ("record field cleanup", "destructor requires complete reverse declaration field retirement");
					}
					record_field_epilogues.insert (drop, true);
					continue;
				}
				if (field.semantic_type is OwnerSlotsType) {
					var drop = index < 0 ? null : block.instructions[index--] as CfgSlotsDrop;
					var self = drop == null ? null : drop.store.pointer as CfgReceiverValue;
					if (self == null || self.receiver != destructor.receiver || drop.store.field != field) {
						fail ("owner-slot cleanup", "destructor requires exact reverse-order slot cleanup");
					}
					slots_epilogues.insert (drop, true);
					continue;
				}
				if (field.text_snapshot) {
					var snapshot = index < 0 ? null : block.instructions[index--] as CfgTextSnapshotDestroy;
					var self = snapshot == null ? null : snapshot.field.pointer as CfgReceiverValue;
					if (self == null || self.receiver != destructor.receiver || snapshot.field.field != field) {
						fail ("snapshot cleanup", "normal destructor exit requires exact reverse declaration snapshot cleanup");
					}
					continue;
				}
				if (!(field.semantic_type is HandleType || field.semantic_type is SliceType || field.semantic_type is ClassType)) {
					continue;
				}
				var cleanup = index < 0 ? null : block.instructions[index--] as CfgCleanupInstruction;
				var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
				var place = load == null ? null : load.source as CfgIndirectFieldPlace;
				var receiver = place == null ? null : place.pointer as CfgReceiverValue;
				if (receiver == null || receiver.receiver != destructor.receiver || place.field != field || !matches_cleanup (field.semantic_type, cleanup.cleanup) || (field.semantic_type is ClassType && !cleanup.cleanup.is_heap_object)) {
					fail ("field cleanup", "normal destructor exit requires exact reverse declaration cleanup of current field contents");
				}
				field_epilogues.insert (cleanup, cleanup);
			}
			foreach (var property in destructor.declaring_class.properties) {
				if (!property.is_owned_lazy) {
					continue;
				}
				var drop = index < 0 ? null : block.instructions[index--] as CfgLazyDrop;
				if (drop == null || drop.property_member != property) {
					fail ("owned lazy", "destructor exit lost exact reverse-order cache owner retirement");
				}
				lazy_epilogues.insert (drop, true);
			}

		}
	}

	private void verify_resource_capture_order(CfgResourceCapture capture, string path) throws CfgError {
		int index = 0;
		while (index < current_block.instructions.length && current_block.instructions[index] != capture) {
			index++;
		}
		index++;
		var cleanup = index >= current_block.instructions.length ? null : current_block.instructions[index] as CfgCleanupInstruction;
		if (cleanup != null) {
			index++;
		}
		var consumer = index >= current_block.instructions.length ? null : current_block.instructions[index];
		var actor = consumer as CfgActorSend;
		if (actor != null) {
			var type = actor.sender.semantic_type as ClosureHandleType;
			if (cleanup != null || type == null || !type.actor || actor.action != Astra.Source.ActorAction.SEND || actor.message != capture.result || capture.source == null || !capture.cleanup.is_heap_object || capture.cleanup.object_class.polymorphic || capture.result.semantic_type != type.actor_message) {
				fail (path, "Actor admission must immediately consume the exact sole heap message before either outcome");
			}
			resource_consumers.insert (capture.result, consumer);
			resource_stores.insert (consumer, capture);
			return;
		}
		var shared_evaluation = consumer as CfgEvaluateInstruction;
		var closure = shared_evaluation == null ? null : shared_evaluation.value as CfgClosureBind;
		if (closure != null) {
			if (cleanup != null || closure.environment != capture.result || capture.source == null || !capture.cleanup.is_heap_object || closure.cleanup.closure_environment != capture.cleanup.object_class || capture.result.semantic_type != ((ClosureHandleType) closure.semantic_type).environment_type) {
				fail (path, "closure acquisition must immediately consume exact sole heap environment capture");
			}
			resource_consumers.insert (capture.result, consumer);
			resource_stores.insert (consumer, capture);
			return;
		}
		var shared = shared_evaluation == null ? null : shared_evaluation.value as CfgSharedOperation;
		if (shared != null && shared.action == SharedAction.ACQUIRE) {
			if (cleanup != null || shared.operand != capture.result || capture.source == null || !capture.cleanup.is_heap_object || !SharedContracts.matches (shared.action, capture.result.semantic_type, shared.semantic_type)) {
				fail (path, "shared acquisition must immediately consume exact sole heap payload capture");
			}
			resource_consumers.insert (capture.result, consumer);
			resource_stores.insert (consumer, capture);
			return;
		}
		var initialize = consumer as CfgInitialize;
		var store = consumer as CfgStore;
		var target = initialize != null ? initialize.target : store == null ? null : store.target;
		var record = target as CfgFieldPlace;
		if (record != null) {
			var root = record.root_local ();
			var field = record.field;
			if (initialize == null || cleanup != null || root == null || field == null || initialize.acquisition != root || !matches_cleanup (field.semantic_type, capture.cleanup) || field != record.field || initialize.value != capture.result) {
				fail (path, "record capture requires exact whole-record initialization and Resource authority");
			}
			resource_consumers.insert (capture.result, consumer);
			resource_stores.insert (consumer, capture);
			return;
		}
		var destination = target as CfgIndirectFieldPlace;
		var incoming = initialize != null ? initialize.value : store == null ? null : store.value;
		if (destination == null || !(destination.field.containing_type is CfgClass) || incoming != capture.result || destination.semantic_type != capture.result.semantic_type || (initialize == null ? cleanup == null : cleanup != null)) {
			fail (path, "Resource capture must feed one immediate field initialization or cleanup-then-store replacement");
		}
		if (cleanup != null) {
			var old = cleanup.value as CfgLoadValue;
			if (old == null || old.source != destination || cleanup.cleanup != capture.cleanup) {
				fail (path, "replacement must load and release the exact old destination after incoming capture and before store");
			}
		}
		if (cleanup != null) {
			resource_replacements.insert (cleanup, cleanup);
		}
		resource_consumers.insert (capture.result, consumer);
		resource_stores.insert (consumer, capture);
	}

	private void verify_call_arguments(CfgCallInstruction call, CfgFunction function, string path) throws CfgError {
		var target = call.target;
		if (target != null && functions.contains (target) && target.blocks.length != 0 && target.entry.is_complete && target.entry.terminator is CfgForeignReturn && ((CfgForeignReturn) target.entry.terminator).binding.root.api.active_personalities == 0) {
			fail (path, "call requires unselected foreign import");
		}
		if (target != null && functions.contains (target) && target.blocks.length != 0 && target.entry.is_complete && target.entry.terminator is CfgForeignSignalReturn) {
			var self = call.receiver as CfgReceiverValue;
			if (self == null || self.receiver != function.implicit_receiver || function.implicit_receiver == null || target.implicit_receiver.contract.instance_type != function.implicit_receiver.contract.instance_type) {
				fail (path, "signal emission requires the exact defining Class self receiver");
			}
		}
		var caller_policy = function.implicit_receiver == null ? null : function.implicit_receiver.contract.instance_type as ClassType;
		var callee_policy = target == null || target.implicit_receiver == null ? null : target.implicit_receiver.contract.instance_type as ClassType;
		if (caller_policy != null && caller_policy.monitored && !(function is CfgLifecycle) && callee_policy != null && callee_policy.monitored && !(target is CfgLifecycle)) {
			var self = call.receiver as CfgReceiverValue;
			if (self == null || self.receiver != function.implicit_receiver) {
				fail (path, "cross-object monitor nesting requires a qualified ordered-lock operation");
			}
		}

		var factory_method = target as CfgMethod;
		if (factory_method != null) {
			foreach (var property in factory_method.declaring_type.properties) {
				if (property.factory == factory_method) {
					fail (path, "owning lazy factory is reserved for its exact compiler cache gate");
				}
			}
		}
		if (pending_commit != null && pending_commit.call != call) {
			fail (path, "task creation requires its exact ownership commit");
		}
		verify_struct_arguments (call, function, path);
		if (call.arguments.length != target.parameters.length) {
			fail (path, "call argument count does not match target parameters");
		}
		for (int i = 0; i < call.arguments.length; i++) {
			var class_cast = (call.arguments[i] is CfgEvaluatedValue) ? class_upcasts.lookup ((CfgEvaluatedValue) call.arguments[i]) : null;
			var class_borrow = class_cast == null ? null : class_cast.reference as CfgOwnedBorrowValue;
			if (class_borrow != null && class_borrow.parameter != target.parameters[i]) {
				fail (path, "upcast borrow must reach its exact noescape consumer parameter");
			}
			string argument_path = path + "/argument #%d".printf (i);
			if (pending_commit != null && (call.arguments[i] is CfgSliceFromArrayValue || call.arguments[i] is CfgSliceLengthValue || call.arguments[i] is CfgLoadValue || call.arguments[i] is CfgBinaryValue || call.arguments[i] is CfgPrefixValue || call.arguments[i] is CfgVectorDotValue || call.arguments[i] is CfgDspValue || call.arguments[i] is CfgIntegerShiftValue || call.arguments[i] is CfgIntegerConversionValue || call.arguments[i] is CfgNumericConversionValue || call.arguments[i] is CfgFloatConversionValue || call.arguments[i] is CfgVectorSplatValue || call.arguments[i] is CfgVectorExtractValue || call.arguments[i] is CfgVectorInsertValue || call.arguments[i] is CfgVectorShuffleValue || call.arguments[i] is CfgVectorSelectValue || call.arguments[i] is CfgVectorConstructValue || call.arguments[i] is CfgVectorReductionValue || call.arguments[i] is CfgAddressOfValue)) {
				fail (argument_path, "all owned-call argument expressions must be evaluated before transfer commit");
			}
			if (target.parameters[i].semantic_type is EnumType) {
				var argument = call.arguments[i] as CfgEnumArgument;
				if (argument == null || argument.source.local != null || argument.semantic_type != target.parameters[i].semantic_type) {
					fail (argument_path, "enum argument requires exact independent by-value snapshot");
				}
			} else if (target.parameters[i].pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				var pending_transfer = call.arguments[i] as CfgPendingOwnedArgument;
				if (pending_transfer == null || pending_transfer.parameter != target.parameters[i] || pending_commit == null || committed_transfers.lookup (pending_transfer) != pending_commit || used_transfers.contains (pending_transfer)) {
					fail (argument_path, "owned call argument requires its exact parameter and one committed pending transfer");
				}
				used_transfers.insert (pending_transfer, pending_transfer);
			} else {
				verify_value (call.arguments[i], function, argument_path, target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE ? target.parameters[i] : null);
			}
			if (call.arguments[i].semantic_type != target.parameters[i].semantic_type) {
				fail (argument_path, "call argument type does not match target parameter");
			}
		}
		if (pending_commit != null) {
			foreach (var pending_transfer in pending_commit.transfers) {
				if (!used_transfers.contains (pending_transfer)) {
					fail (path, "commit contains a transfer absent from its call");
				}
			}
			pending_commit = null;
		}
	}

	private void verify_constructor_abort(CfgConstructorAbort abort, CfgFunction function, string path) throws CfgError {
		var constructor = function as CfgConstructor;
		var owner = constructor == null ? null : constructor.declaring_class;
		if (owner == null || abort.receiver.receiver != function.implicit_receiver || !ConstructorContracts.admitted (owner.foreign_export, owner.allocation_policy, constructor.member_ordinal, function.throws_type)) {
			fail (path, "constructor abort requires its exact admitted initializing receiver and checked effect");
		}
		int cursor = 0;
		for (int f = owner.fields.length - 1; f >= 0; f--) {
			var field = owner.fields[f];
			if (field.owned_cleanup == null && !field.text_snapshot && !(field.semantic_type is OwnerSlotsType)) {
				continue;
			}
			var cleanup = (field.semantic_type is OwnerSlotsType) ? field.slots_cleanup : field.owned_cleanup;
			if (cursor >= abort.fields.length || abort.fields[cursor].field != field || abort.fields[cursor].cleanup != cleanup) {
				fail (path, "constructor abort lost exact complete field retirement recipes");
			}
			var recipe = abort.fields[cursor++];
			if (cleanup != null && cleanup.record_type != null) {
				verify_struct_shape (recipe.shape, field.semantic_type, path);
			} else if (recipe.shape != null) {
				fail (path, "scalar constructor retirement cannot acquire record channels");
			}
		}
		if (cursor != abort.fields.length || cursor > 4096) {
			fail (path, "constructor abort changed its bounded field inventory");
		}
		cursor = 0;
		for (int p = owner.properties.length - 1; p >= 0; p--) {
			var property = owner.properties[p];
			if (!property.is_owned_lazy) {
				continue;
			}
			if (cursor >= abort.lazy_properties.length || abort.lazy_properties[cursor++] != property) {
				fail (path, "constructor abort lost exact lazy-cache retirement");
			}
		}
		if (cursor != abort.lazy_properties.length) {
			fail (path, "constructor abort changed lazy-cache inventory");
		}
	}

	private void verify_instruction(CfgInstruction instruction, CfgFunction function, string path) throws CfgError {
		if (instruction is CfgConstructorAbort) {
			verify_constructor_abort ((CfgConstructorAbort) instruction, function, path);
			if (!(current_block.terminator is CfgExceptionReturn) || current_block.instructions[current_block.instructions.length - 1] != instruction) {
				fail (path, "constructor abort belongs immediately before exceptional completion");
			}
			return;
		}
		current_instruction = instruction;
		if (instruction is CfgStructInvoke) {
			var invocation = (CfgStructInvoke) instruction;
			var code = invocation.call as CfgFunctionValueCall;
			var closure = invocation.call as CfgClosureCall;
			if (code == null && closure == null) {
				fail (path, "record invocation requires its exact typed code value");
			}
			var signature = (code == null ? closure.callee.semantic_type : code.callee.semantic_type) as CallableSignature;
			var group = invocation.results;
			if (signature == null || signature.record_result == null || group.shape.semantic_type != signature.record_result.semantic_type || group.shape.mode != signature.record_result.mode || group.leaves.length != group.shape.leaves.length || struct_results.contains (group)) {
				fail (path, "indirect record result requires its complete exact declared group");
			}
			verify_struct_shape (group.shape, invocation.call.semantic_type, path);
			if (invocation.checked_call != null) {
				if (closure == null || invocation.checked_call.call != closure || !guarded_effect_success (invocation.checked_call.result, function)) {
					fail (path, "checked record publication requires its exact null-error successor");
				}
			} else {
				verify_value (invocation.call, function, path + "/invocation");
			}
			struct_results.insert (group, invocation);
			for (int r = 0; r < group.leaves.length; r++) {
				var leaf = group.leaves[r];
				if (leaf.semantic_type != group.shape.leaves[r].semantic_type || results.contains (leaf)) {
					fail (path, "indirect record result lost unique ordered leaf definitions");
				}
				results.insert (leaf, invocation);
				available_results.insert (leaf, leaf);
				struct_result_leaves.insert (leaf, group);
			}
			return;
		}
		if (instruction is CfgRecordFieldCommit) {
			var commit = (CfgRecordFieldCommit) instruction;
			verify_record_field (commit.destination, function, path);
			verify_struct_shape (commit.shape, commit.destination.semantic_type, path);
			if (commit.shape.mode != StructValueMode.MOVE_VALUE || commit.leaves.length != commit.shape.leaves.length || (commit.record_move == null) == (commit.results == null)) {
				fail (path, "record field commit requires one complete moved or produced record");
			}
			if (commit.record_move != null && commit.record_move.consumer != commit) {
				fail (path, "record field move lost exact consumer");
			}
			if (commit.results != null && (!consumed_struct_results.contains (commit.results) || commit.results.shape != commit.shape)) {
				fail (path, "record field producer lacks complete original consumption");
			}
			for (int i = 0; i < commit.leaves.length; i++) {
				if (commit.leaves[i].semantic_type != commit.shape.leaves[i].semantic_type || (commit.results != null && commit.leaves[i] != commit.results.leaves[i])) {
					fail (path, "record field commit changed an original leaf");
				}
				verify_value (commit.leaves[i], function, path + "/leaf");
			}
			if (commit.initializes) {
				var receiver = commit.destination.pointer as CfgReceiverValue;
				if (!(function is CfgConstructor) || receiver == null || receiver.receiver != function.implicit_receiver || commit.destination.field.containing_type != ((CfgConstructor) function).declaring_class || field_state == null || field_state.is_possible (commit.destination.field.ordinal)) {
					fail (path, "record field requires one fresh exact constructor initialization");
				}
				field_state.initialize (commit.destination.field.ordinal);
			} else if (field_state != null) {
				fail (path, "constructor record field cannot be replaced before complete publication");
			}
			return;
		}
		if (instruction is CfgRecordFieldDrop) {
			var drop = (CfgRecordFieldDrop) instruction;
			verify_record_field (drop.source, function, path);
			verify_struct_shape (drop.shape, drop.source.semantic_type, path);
			if (drop.shape.mode != StructValueMode.MOVE_VALUE) {
				fail (path, "record field retirement requires complete ownership shape");
			}
			if (!record_field_epilogues.contains (drop)) {
				fail (path, "record field drop lacks exact destructor epilogue authority");
			}
			return;
		}
		if (instruction is CfgStructParameterBorrow) {
			verify_struct_parameter_borrow ((CfgStructParameterBorrow) instruction, function, path);
			return;
		}
		if (instruction is CfgStructBoundaryAcquire) {
			verify_boundary_acquire ((CfgStructBoundaryAcquire) instruction, function, path);
			return;
		}
		if (instruction is CfgStructBoundaryMove) {
			verify_boundary_move ((CfgStructBoundaryMove) instruction, function, path);
			return;
		}
		if (instruction is CfgLazyDrop) {
			var drop = (CfgLazyDrop) instruction;
			var destructor = function as CfgDestructor;
			if (destructor == null || !drop.property_member.is_owned_lazy || drop.property_member.declaring_type != destructor.declaring_class || !lazy_epilogues.contains (drop) || lazy_seen.contains (drop)) {
				fail (path, "cache retirement requires exact declaring destructor and owned lazy property");
			}
			lazy_seen.insert (drop, true);
			return;
		}
		if (instruction is CfgSlotsRecordTransfer) {
			var transfer = (CfgSlotsRecordTransfer) instruction;
			verify_slots_place (transfer.store, function, true, path);
			var element = ((OwnerSlotsType) transfer.store.semantic_type).element;
			verify_struct_shape (transfer.shape, element, path);
			if ((transfer.shape.mode == StructValueMode.MOVE_VALUE) != (transfer.record_move != null) || transfer.leaves.length != transfer.shape.leaves.length) {
				fail (path, "record slot copy requires a complete exact value group");
			}
			if (transfer.record_move != null && (transfer.record_move.consumer != transfer || !current_block.instructions.find (transfer.record_move))) {
				fail (path, "record slot move lacks its complete same-block ownership commit");
			}
			if (transfer.index != null) {
				verify_value (transfer.index, function, path);
				if (transfer.index.semantic_type.kind != TypeKind.INT) {
					fail (path, "record slot replacement requires I32 index");
				}
			}
			for (int l = 0; l < transfer.leaves.length; l++) {
				if (transfer.leaves[l].semantic_type != transfer.shape.leaves[l].semantic_type) {
					fail (path, "record slot copy changed an exact leaf type");
				}
				verify_value (transfer.leaves[l], function, path);
			}
			return;
		}
		if (instruction is CfgSlotsRecordRead) {
			var read = (CfgSlotsRecordRead) instruction;
			var group = read.results;
			verify_slots_place (read.store, function, true, path);
			verify_value (read.index, function, path);
			verify_struct_shape (group.shape, ((OwnerSlotsType) read.store.semantic_type).element, path);
			if (read.index.semantic_type.kind != TypeKind.INT || (group.shape.mode == StructValueMode.MOVE_VALUE && !read.remove) || group.leaves.length != group.shape.leaves.length || struct_results.contains (group)) {
				fail (path, "record slot read lost complete copied group or index authority");
			}
			struct_results.insert (group, read);
			for (int l = 0; l < group.leaves.length; l++) {
				var leaf = group.leaves[l];
				if (leaf.semantic_type != group.shape.leaves[l].semantic_type || results.contains (leaf)) {
					fail (path, "record slot read changed its exact ordered result leaves");
				}
				results.insert (leaf, read);
				available_results.insert (leaf, leaf);
				struct_result_leaves.insert (leaf, group);
			}
			return;
		}
		if (instruction is CfgSlotsInitialize) {
			var store = ((CfgSlotsInitialize) instruction).store;
			verify_slots_place (store, function, false, path);
			var self = store.pointer as CfgReceiverValue;
			if (field_state == null || !(function is CfgConstructor) || self == null || self.receiver != function.implicit_receiver || self.receiver.contract.mode != ReceiverMode.INITIALIZING || store.field.containing_type != ((CfgConstructor) function).declaring_class || field_state.is_possible (store.field.ordinal)) {
				fail (path, "owner-slot initialization requires the unique exact constructor field");
			}
			field_state.initialize (store.field.ordinal);
			return;
		}
		if (instruction is CfgSlotsReplace) {
			var replace = (CfgSlotsReplace) instruction;
			verify_slots_place (replace.store, function, true, path);
			verify_value (replace.index, function, path + "/index");
			if (replace.index.semantic_type.kind != TypeKind.INT) {
				fail (path, "owner-slot replace requires I32 index");
			}
			verify_transfer_source (replace.incoming, ((OwnerSlotsType) replace.store.semantic_type).element, replace.store.field.slots_cleanup, function, path);
			if (replace.incoming.cleanup != replace.store.field.slots_cleanup || !matches_cleanup (replace.incoming.semantic_type, replace.incoming.cleanup)) {
				fail (path, "owner-slot replace lost exact heap input");
			}
			return;
		}
		if (instruction is CfgSlotsAppend) {
			var append = (CfgSlotsAppend) instruction;
			verify_slots_place (append.store, function, true, path);
			verify_transfer_source (append.incoming, ((OwnerSlotsType) append.store.semantic_type).element, append.store.field.slots_cleanup, function, path);
			if (append.incoming.cleanup != append.store.field.slots_cleanup || !matches_cleanup (append.incoming.semantic_type, append.incoming.cleanup)) {
				fail (path, "owner-slot append requires exact unique heap owner and cleanup");
			}
			return;
		}
		if (instruction is CfgSlotsDrop) {
			var drop = (CfgSlotsDrop) instruction;
			verify_slots_place (drop.store, function, true, path);
			if (!slots_epilogues.contains (drop)) {
				fail (path, "owner-slot drop lacks exact destructor epilogue authority");
			}
			return;
		}
		if (instruction is CfgSlotsBorrow) {
			var loan = ((CfgSlotsBorrow) instruction).result;
			if (evaluated_results.contains (loan)) {
				fail (path, "owner-slot loan requires one unique capture definition");
			}
			evaluated_results.insert (loan, loan);
			verify_slots_place (loan.store, function, true, path);
			verify_value (loan.index, function, path);
			if (loan.index.semantic_type.kind != TypeKind.INT || loan.borrower.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || loan.borrower.semantic_type != loan.semantic_type || loan.semantic_type != ((OwnerSlotsType) loan.store.semantic_type).element) {
				fail (path, "owner-slot loan lost exact index/type/borrower");
			}
			available_evaluations.insert (loan, loan);
			return;
		}

		if (instruction is CfgAsyncRunStatus) {
			var run = (CfgAsyncRunStatus) instruction;
			verify_value (run.operation.result, function, path);
			if (run.operation.contract.kind != AsyncOperationKind.RUN || run.destination.definition.semantic_type != run.operation.contract.runtime.status_type || !guarded_effect_success (run.operation.exception, function)) {
				fail (path, "run status lost exact guarded consuming root association");
			}
			return;
		}
		if (instruction is CfgExecutorEnd) {
			var end = (CfgExecutorEnd) instruction;
			verify_place (end.source, function, path);
			if (!(end.source.semantic_type is ExecutorType)) {
				fail (path, "executor cleanup lost unique handle identity");
			}
			return;
		}
		if (instruction is CfgTaskBorrow) {
			var borrow = (CfgTaskBorrow) instruction;
			verify_place (borrow.source, function, path);
			if (!(borrow.source.semantic_type is TaskType)) {
				fail (path, "task borrow lost exact unique owner identity");
			}
			available_evaluations.insert (borrow.result, borrow.result);
			return;
		}
		if (instruction is CfgTaskStarted) {
			var started = (CfgTaskStarted) instruction;
			if (started.operation.contract.kind != AsyncOperationKind.START || started.operation.task_owner != started.source.ordinal || !guarded_effect_success (started.operation.exception, function)) {
				fail (path, "started obligation lost exact guarded successful enrollment association");
			}
			return;
		}
		if (instruction is CfgAsyncOperation) {
			var operation = (CfgAsyncOperation) instruction;
			if (!operation.contract.valid_shape (operation.executor == null ? null : operation.executor.semantic_type, operation.task == null ? null : operation.task.semantic_type, operation.argument == null ? null : operation.argument.semantic_type, function.async_body)) {
				fail (path, "virtual operation lost exact registered operand/result/effect/context contract");
			}
			if (operation.executor != null) {
				verify_value (operation.executor, function, path + "/executor");
				if (operation.executor.semantic_type != operation.contract.runtime.executor_type) {
					fail (path, "operation lost exact nominated executor");
				}
			}
			if (operation.task != null) {
				verify_value (operation.task, function, path + "/task");
			}
			if (operation.argument != null) {
				verify_value (operation.argument, function, path + "/argument");
			}
			if (operation.result != null) {
				available_evaluations.insert (operation.result, operation.result);
			}
			if (operation.exception != null) {
				available_evaluations.insert (operation.exception, operation.exception);
			}
			return;
		}
		if (instruction is CfgTaskWait) {
			var wait = (CfgTaskWait) instruction;
			verify_value (wait.child, function, path + "/child");
			var bridge = wait.bridge_executor;
			if (bridge != null) {
				var handle = bridge.semantic_type as HandleType;
				var load = bridge as CfgLoadValue;
				if (handle == null || !handles.contains (handle) || !AsyncBridgeTypes.matches (handle, handles.lookup (handle).cleanup.external_symbol) || load == null || !(load.source is CfgLocalPlace)) {
					fail (path, "worker bridge lost exact live pool owner and close contract");
				}
				verify_value (bridge, function, path + "/bridge");
			}
			var task = wait.child.semantic_type as TaskType;
			if (wait.body != function.async_body || task == null || (bridge == null ? !task.runtime.compatible (wait.body.runtime) : !AsyncBridgeTypes.compatible (wait.body.runtime, task.runtime))) {
				fail (path, "wait lost exact body/task/runtime identity");
			}
			available_evaluations.insert (wait.exception, wait.exception);
			return;
		}
		if (instruction is CfgTaskSuccess) {
			var success = (CfgTaskSuccess) instruction;
			if (success.operation.success != success || success.operation.discard || success.success_type.logical_identity != ((TaskType) success.operation.child.semantic_type).success_type.logical_identity || !guarded_effect_success (success.operation.exception, function)) {
				fail (path, "wait success lost exact original guarded result publication");
			}
			if (success.struct_result != null) {
				var group = success.struct_result;
				if (success.result != null || success.enum_result != null || success.buffer_cleanup != null || group.shape.semantic_type != success.success_type || struct_results.contains (group) || group.leaves.length != group.shape.leaves.length) {
					fail (path, "record await requires one exact complete success group");
				}
				verify_struct_shape (group.shape, success.success_type, path);
				struct_results.insert (group, success);
				for (int l = 0; l < group.leaves.length; l++) {
					var leaf = group.leaves[l];
					if (leaf.semantic_type != group.shape.leaves[l].semantic_type || results.contains (leaf)) {
						fail (path, "record await lost ordered exact leaf definitions");
					}
					results.insert (leaf, success);
					available_results.insert (leaf, leaf);
					struct_result_leaves.insert (leaf, group);
				}
				return;
			}
			if (success.enum_result != null) {
				if (success.result != null || success.buffer_cleanup != null || success.enum_result.definition.semantic_type != success.success_type || !function.enum_slots.find (success.enum_result)) {
					fail (path, "enum await requires one exact guarded result carrier");
				}
				return;
			}
			if (success.result == null || success.result.semantic_type != success.success_type) {
				fail (path, "await lost exact scalar success definition");
			}
			if (success.buffer_cleanup != null) {
				if (!success.buffer_cleanup.is_buffer || success.buffer_cleanup.buffer_type != success.result.semantic_type || !cleanups.contains (success.buffer_cleanup) || ((TaskType) success.operation.child.semantic_type).success_mode != ResultOwnershipContract.OWNED_TRANSFER) {
					fail (path, "await buffer lost exact complete ownership contract");
				}
				results.insert ((CfgCallResultValue) success.result, success);
				available_results.insert ((CfgCallResultValue) success.result, (CfgCallResultValue) success.result);
				pending_acquisition = (CfgCallResultValue) success.result;
			} else {
				available_evaluations.insert ((CfgEvaluatedValue) success.result, (CfgEvaluatedValue) success.result);
			} return;
		}
		if (instruction is CfgTaskMove) {
			var move = (CfgTaskMove) instruction;
			verify_place (move.source, function, path + "/source");
			if (!(move.source.semantic_type is TaskType) || move.result.semantic_type != move.source.semantic_type) {
				fail (path, "task move lost exact source/result contract");
			}
			available_evaluations.insert (move.result, move.result);
			return;
		}
		if (instruction is CfgTaskEnd) {
			var end = (CfgTaskEnd) instruction;
			verify_place (end.source, function, path + "/source");
			if (!(end.source.semantic_type is TaskType)) {
				fail (path, "task scope cleanup requires an exact Task owner");
			}
			return;
		}
		if (instruction is CfgTaskCreate) {
			var creation = (CfgTaskCreate) instruction;
			if (!creation.matches_captures () || creation.target == null || creation.target.async_body == null || creation.result == null || creation.result.semantic_type != creation.target.async_body.task_type || creation.arguments.length != creation.target.parameters.length || creation.checked_admission != (creation.exception_result != null) || creation.checked_admission && creation.allocation_context == null || creation.buffer_result != null || creation.enum_result != null || creation.struct_result != null) {
				fail (path, "task creation requires exact body/capture/logical-result channels");
			}
			var frame_context = creation.allocation_context;
			if (frame_context != null) {
				var type = frame_context.semantic_type as HandleType;
				var load = frame_context as CfgLoadValue;
				if (type == null || !handles.contains (type) || type.context_mode == "" || handles.lookup (type).context_mode != type.context_mode || creation.target.async_body.runtime.threaded && type.context_mode != "owned-concurrent" || creation.loans.length != 0 || load == null && !(frame_context is CfgParameterValue) || load != null && !(load.source is CfgLocalPlace)) {
					fail (path, "task frame lost exact named backing lifetime/thread contract");
				}
				// The exact owned-context mode above supplies a retained frame lease.
				verify_value (frame_context, function, path + "/frame-context", null, true);
			}
			int borrowed = 0;
			for (int p = 0; p < creation.target.parameters.length; p++) {
				var parameter = creation.target.parameters[p];
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					continue;
				}
				if (borrowed >= creation.loans.length) {
					fail (path, "borrowed task capture lacks a sealed suspension loan");
				}
				var loan = creation.loans[borrowed++];
				CfgValue view = loan.view;
				while (view is CfgEvaluatedValue && evaluated_sources.contains ((CfgEvaluatedValue) view)) {
					view = evaluated_sources.lookup ((CfgEvaluatedValue) view);
				}
				var array = view as CfgSliceFromArrayValue;
				int site = 0;
				while (site < current_block.instructions.length && current_block.instructions[site] != creation) {
					site++;
				}
				int wait_position = creation.direct_wait_position (current_block, site);
				var wait = wait_position < 0 ? null : current_block.instructions[wait_position] as CfgTaskWait;
				if (function.async_body == null || wait == null || wait.child != creation.result || loan.parameter_ordinal != p || loan.view != creation.arguments[p] || array == null || array.storage != loan.storage || loan.storage.incoming_parameter != null || !function.locals.find (loan.storage) || !(parameter.semantic_type is SliceType) || suspension_loan_ids.contains (loan.identity)) {
					fail (path, "suspension loan lost exact direct wait/capture/view/parent-array association");
				}
				suspension_loan_ids.insert (loan.identity, true);
			}
			if (borrowed != creation.loans.length) {
				fail (path, "task creation has an unrelated suspension loan");
			}
			verify_call_arguments (creation, function, path);
			if (creation.checked_admission) {
				foreach (var input in creation.arguments) {
					var captured = input as CfgPendingOwnedArgument;
					if (captured != null && (!(captured.semantic_type is ClassType || captured.semantic_type is HandleType || captured.semantic_type is SliceType) || captured.source != null && (captured.source.semantic_type != captured.semantic_type || captured.source.requires_nonnull || captured.source.incoming_parameter != null && captured.source.incoming_parameter.requires_nonnull))) {
						fail (path, "checked frame requires exact nullable caller inputs");
					}
				}
				available_evaluations.insert (creation.exception_result, creation.exception_result);
			}
			if (results.contains (creation.result)) {
				fail (path, "task factory result has duplicate definition responsibility");
			}
			results.insert (creation.result, creation);
			available_results.insert (creation.result, creation.result);
			return;
		}
		if (instruction is CfgAsyncDelay) {
			var delay = (CfgAsyncDelay) instruction;
			if (delay.body != function.async_body) {
				fail (path, "suspension lost exact async body identity");
			}
			if (delay.payload) {
				var load = delay.ticks as CfgLoadValue;
				var owner = load == null ? null : load.source as CfgLocalPlace;
				if (!delay.body.runtime.linux || owner == null || owner.cleanup == null || !AsyncPayloadTypes.matches (owner.semantic_type, owner.cleanup.external_symbol)) {
					fail (path, "payload suspension requires exact owned LinuxPayload and cleanup");
				}
				verify_value (delay.ticks, function, path + "/payload", null, true);
			} else {
				verify_value (delay.ticks, function, path + "/ticks");
				if (delay.ticks.semantic_type.kind != TypeKind.U32 && delay.ticks.semantic_type.kind != TypeKind.INT) {
					fail (path, "virtual suspension requires integral ticks");
				}
			}
			available_evaluations.insert (delay.exception, delay.exception);
			return;
		}
		if (instruction is CfgTextSnapshotDestroy) {
			var snapshot = (CfgTextSnapshotDestroy) instruction;
			var destructor = function as CfgDestructor;
			var receiver = snapshot.field.pointer as CfgReceiverValue;
			if (destructor == null || receiver == null || receiver.receiver != destructor.receiver || snapshot.field.field.containing_type != destructor.declaring_class || !snapshot.field.field.text_snapshot) {
				fail (path, "snapshot cleanup requires exact destructor receiver and owned snapshot field");
			}
			verify_place (snapshot.field, function, path + "/snapshot");
			return;
		}
		if (instruction is CfgActorSend) {
			var send = (CfgActorSend) instruction;
			var type = send.sender.semantic_type as ClosureHandleType;
			var error = structs.lookup (send.error_type) as CfgClass;
			if (type == null || !type.actor || !type.supported () || send.action < Astra.Source.ActorAction.SEND || send.action > Astra.Source.ActorAction.CANCEL || function.async_body != null || error == null || !error.exception_root || error.parent_class != null || error.constructor == null || error.constructor.throws_type != null || error.constructor.parameters.length != 1 || !(error.constructor.parameters[0].semantic_type is StringType) || send.result.semantic_type != send.error_type) {
				fail (path, "Actor operation lost exact sender, action or nominated Error channel");
			}
			var branch = current_block.terminator as CfgConditionalBranch;
			var condition = branch == null ? null : branch.condition as CfgBinaryValue;
			if (condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != send.result || !(condition.right is CfgNullPointerValue) || branch.true_target == branch.false_target || evaluations.contains (send) || evaluated_results.contains (send.result)) {
				fail (path, "Actor operation requires distinct checked success/error edges and sole result definition");
			}
			var load = send.sender as CfgLoadValue;
			var parameter = send.sender as CfgParameterValue;
			if (load == null ? parameter == null || parameter.parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE : !(load.source is CfgLocalPlace) || ((CfgLocalPlace) load.source).cleanup == null) {
				fail (path, "Actor operation requires exact live sender loan");
			}
			verify_value (send.sender, function, path + "/sender", null, true);
			if (send.action == Astra.Source.ActorAction.SEND) {
				if (send.message == null || send.message.semantic_type != type.actor_message) {
					fail (path, "Actor message differs from exact sender signature");
				}
				if (type.actor_message is ClassType) {
					var captured = send.message as CfgEvaluatedValue;
					if (captured == null || resource_consumers.lookup (captured) != send) {
						fail (path, "Actor message lost immediately consumed heap-owner capture");
					}
					verify_value (send.message, function, path + "/message", null, true);
				} else {
					verify_value (send.message, function, path + "/scalar");
				}
			} else if (send.message != null) {
				fail (path, "Actor lifecycle operation cannot carry a message");
			}
			evaluations.insert (send, send);
			evaluated_results.insert (send.result, send.result);
			available_evaluations.insert (send.result, send.result);
			return;
		}
		if (instruction is CfgCheckedClosureInvoke) {
			var invocation = (CfgCheckedClosureInvoke) instruction;
			var type = invocation.call.callee.semantic_type as ClosureHandleType;
			if (type == null || type.throws_type == null || invocation.value != invocation.call || !(invocation.result.semantic_type is ClassType) || ((ClassType) invocation.result.semantic_type).parent_type != null || !type.throws_type.derives_from ((ClassType) invocation.result.semantic_type)) {
				fail (path, "checked closure invocation lost exact rooted exception channel");
			}
			var branch = current_block.terminator as CfgConditionalBranch;
			var condition = branch == null ? null : branch.condition as CfgBinaryValue;
			if (condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != invocation.result || !(condition.right is CfgNullPointerValue) || branch.true_target == branch.false_target || evaluations.contains (invocation) || evaluated_results.contains (invocation.result)) {
				fail (path, "checked closure invocation requires distinct guarded success/error edges and sole channel definition");
			}
			evaluations.insert (invocation, invocation);
			evaluated_results.insert (invocation.result, invocation.result);
			verify_value (invocation.call, function, path + "/call");
			available_evaluations.insert (invocation.result, invocation.result);
			return;
		}
		if (instruction is CfgClosureCallSuccess) {
			var success = (CfgClosureCallSuccess) instruction;
			var type = success.invocation.call.callee.semantic_type as ClosureHandleType;
			if (type == null || type.throws_type == null || success.value != success.invocation.call || success.result.semantic_type != type.result_type || !guarded_effect_success (success.invocation.result, function)) {
				fail (path, "checked closure scalar publication requires its exact null-error successor");
			}
			if (evaluations.contains (success) || evaluated_results.contains (success.result)) {
				fail (path, "checked closure success requires sole scalar definition");
			}
			evaluations.insert (success, success);
			evaluated_results.insert (success.result, success.result);
			evaluated_sources.insert (success.result, success.value);
			if (owned_results.contains (success.result)) {
				pending_acquisition = success.result;
			}
			available_evaluations.insert (success.result, success.result);
			return;
		}

		if (instruction is CfgTextLoanEnd) {
			var local = ((CfgTextLoanEnd) instruction).local;
			if (!current_block.text_exits.find (((CfgTextLoanEnd) instruction).exit_authority) || !local.text_loan || !(local.semantic_type is StringType) || !function.locals.find (local) || local.text_extent == null) {
				fail (path, "text loan exit requires the exact function-owned local extent");
			}
			return;
		}
		if (instruction is CfgOwnedArgumentAbort) {
			var aborted = ((CfgOwnedArgumentAbort) instruction).transfer;
			var consumer = aborted.consumer;
			var arguments = consumer == null ? null : CfgInvocationContracts.arguments (consumer);
			var direct = consumer as CfgCallInstruction;
			bool associated = false;
			if (arguments != null) {
				foreach (var argument in arguments) {
					if (argument == aborted) {
						associated = true;
					}
				}
			}
			if (!aborted.exceptional_abort || consumer == null || !associated || (direct != null && !functions.contains (direct.target)) || (!available_evaluations.contains (aborted) && !available_on_entry (aborted, function))) {
				fail (path, "exception abort requires its exact pending consumer and dominating capture");
			}
			return;
		}
		if (instruction is CfgExceptionStamp) {
			var stamp = (CfgExceptionStamp) instruction;
			verify_value (stamp.exception, function, path);
			if (!(stamp.exception.semantic_type is ClassType)) {
				fail (path, "exception origin requires native class reference");
			}
			return;
		}
		if (instruction is CfgExceptionTake) {
			var take = (CfgExceptionTake) instruction;
			exception_takes.insert (take.result, take);
			if (take.owner.cleanup == null || !take.owner.cleanup.is_heap_object || take.owner.semantic_type != take.result.semantic_type) {
				fail (path, "exception take requires exact owned heap class binding");
			}
		}
		if (instruction is CfgGroupCallSuccess) {
			var success = (CfgGroupCallSuccess) instruction;
			if (success.call == null || success.call.exception_result == null || !guarded_exception_success (success.call, function) || (success.call.buffer_result == null && success.call.struct_result == null && success.call.enum_result == null)) {
				fail (path, "success group requires exact private call association");
			}
			if (success.call.struct_result != null) {
				foreach (var leaf in success.call.struct_result.leaves) {
					available_results.insert (leaf, leaf);
				}
			}
			if (success.call.result != null) {
				available_results.insert (success.call.result, success.call.result);
				if (success.call.target.owned_cleanup != null) {
					pending_acquisition = success.call.result;
				}
			}
			return;
		}
		if (instruction is CfgCallSuccess) {
			var success = (CfgCallSuccess) instruction;
			if (success.call == null || success.call.exception_result == null || !guarded_exception_success (success.call, function) || success.value != success.call.result || success.result != success.call.success_result) {
				fail (path, "success load requires exact private throwing call result");
			}
			if (success.call.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
				if (evaluated_results.contains (success.result)) {
					fail (path, "checked borrowed result requires sole guarded definition");
				}
				property_successes.insert (success.result, success);
				evaluations.insert (success, success);
				evaluated_results.insert (success.result, success.result);
				available_evaluations.insert (success.result, success.result);
				return;
			}
			if (success.call.target.owned_cleanup != null) {
				available_results.insert (success.call.result, success.call.result);
				pending_acquisition = success.call.result;
				return;
			}
		}


		if (pending_commit != null && pending_commit.call != instruction) {
			fail (path, "transfer commit must immediately precede its associated native call");
		}
		var rearm = instruction as CfgOwnershipRearmInstruction;
		if (rearm != null && rearm.owner.semantic_type.is_scoped_allocator ()) {
			fail (path, "scoped context cannot be rearmed");
		}
		if (pending_acquisition != null) {
			var acquisition = instruction as CfgInitialize;
			var discarded = instruction as CfgCleanupInstruction;
			var returned = instruction as CfgOwnershipReturnInstruction;
			if (!((discarded != null && discarded.value == pending_acquisition && discarded.cleanup == owned_results.lookup (pending_acquisition)) || (instruction is CfgEnumBufferCapture && ((CfgEnumBufferCapture) instruction).producer == pending_acquisition) || (instruction is CfgResourceCapture && ((CfgResourceCapture) instruction).value == pending_acquisition) || (instruction is CfgRecordReplace && ((CfgRecordReplace) instruction).incoming == pending_acquisition) || (returned != null && returned.result.producer == pending_acquisition) || (rearm != null && rearm.value == pending_acquisition) || (acquisition != null && acquisition.acquisition != null && acquisition.value == pending_acquisition))) {
				fail (path, "owned producer result must be consumed immediately by acquisition or rearm");
			}
			pending_acquisition = null;
		}
		if (instruction is CfgEnumExtractRecord) {
			var extraction = (CfgEnumExtractRecord) instruction;
			var group = extraction.results;
			if (!function.locals.find (extraction.destination) || initialized.contains (extraction.destination) || extraction.destination.cleanup == null || extraction.destination.cleanup.record_type == null || extraction.destination.semantic_type != extraction.field.semantic_type || group.shape.semantic_type != extraction.field.semantic_type || group.shape.mode != StructValueMode.MOVE_VALUE || struct_results.contains (group) || group.leaves.length != group.shape.leaves.length) {
				fail (path, "enum record extraction requires its exact selected field, fresh root and complete moving result group");
			}
			verify_struct_shape (group.shape, extraction.field.semantic_type, path);
			struct_results.insert (group, extraction);
			for (int ordinal = 0; ordinal < group.leaves.length; ordinal++) {
				var leaf = group.leaves[ordinal];
				if (leaf.semantic_type != group.shape.leaves[ordinal].semantic_type || results.contains (leaf)) {
					fail (path, "enum record extraction changed a unique declared leaf channel");
				}
				results.insert (leaf, extraction);
				available_results.insert (leaf, leaf);
				struct_result_leaves.insert (leaf, group);
			}
			return;
		}
		if (instruction is CfgEnumExtractBuffer) {
			var extraction = (CfgEnumExtractBuffer) instruction;
			verify_buffer_slot (extraction.destination, extraction.destination.cleanup, function, path);
			initialized.insert (extraction.destination, extraction.destination);
			return;
		}
		if (instruction is CfgEnumExtractScalar) {
			var extraction = (CfgEnumExtractScalar) instruction;
			var destination = extraction.destination;
			if (!function.locals.find (destination) || destination.cleanup == null || !matches_cleanup (destination.semantic_type, destination.cleanup) || destination.cleanup.is_heap_object != extraction.field.owns_child || (extraction.field.owned_cleanup != null && destination.cleanup.external_symbol != extraction.field.owned_cleanup.external_symbol) || initialized.contains (destination)) {
				fail (path, "enum scalar extraction requires one fresh exact Resource or heap Class owner");
			}
			initialized.insert (destination, destination);
			return;
		}
		if (instruction is CfgEnumScalarCapture) {
			var capture = (CfgEnumScalarCapture) instruction;
			if (!function.locals.find (capture.source) || capture.source.cleanup != capture.cleanup || capture.cleanup.is_buffer || capture.cleanup.record_type != null || !matches_cleanup (capture.source.semantic_type, capture.cleanup) || capture.result.semantic_type != capture.source.semantic_type || available_evaluations.contains (capture.result)) {
				fail (path, "enum scalar capture requires its original named owner, exact type and cleanup");
			}
			verify_value (capture.value, function, path);
			available_evaluations.insert (capture.result, capture.result);
			evaluated_sources.insert (capture.result, capture.value);
			return;
		}
		if (instruction is CfgEnumScalarAbort) {
			var capture = ((CfgEnumScalarAbort) instruction).capture;
			bool defined = false;
			foreach (var candidate in function.blocks) {
				if (candidate == current_block || block_available_on_entry (candidate, function)) {
					if (candidate.instructions.find (capture)) {
						defined = true;
					}
				}
			}
			if (!defined) {
				fail (path, "enum scalar abort requires its original dominating reservation");
			}
			return;
		}
		var enum_buffer = instruction as CfgEnumBufferCapture;
		if (enum_buffer != null) {
			if (enum_buffer.source != null) {
				verify_buffer_slot (enum_buffer.source, enum_buffer.cleanup, function, path);
			} else {
				verify_value (enum_buffer.producer, function, path, null, false, enum_buffer.cleanup);
			} return;
		}
		if (instruction is CfgEnumBufferAbort) {
			var aborted = ((CfgEnumBufferAbort) instruction).capture;
			bool defined = false;
			foreach (var candidate in function.blocks) {
				foreach (var effect in candidate.instructions) {
					if (effect == aborted && (candidate == current_block || block_available_on_entry (candidate, function))) {
						defined = true;
					}
				}
			}
			if (!defined) {
				fail (path, "enum buffer abort requires exact dominating reservation");
			}
			return;
		}

		if (instruction is CfgEnumEndInspection || instruction is CfgEnumFinishArm || instruction is CfgEnumDrop || instruction is CfgEnumCommit) {
			return;
		}
		var enum_construct = instruction as CfgEnumConstruct;
		if (enum_construct != null) {
			foreach (var field in enum_construct.fields) {
				foreach (var leaf in field.leaves) {
					verify_value (leaf, function, path + "/payload");
				}
			}
			return;
		}
		var enum_copy = instruction as CfgEnumCopy;
		if (enum_copy != null) {
			if (enum_copy.destination.local != null && enum_copy.initializes_destination) {
				if (initialized.contains (enum_copy.destination.local)) {
					fail (path, "enum local has duplicate initialization");
				}
				initialized.insert (enum_copy.destination.local, enum_copy.destination.local);
			}
			return;
		}
		var enum_acquire = instruction as CfgEnumAcquire;
		if (enum_acquire != null) {
			initialized.insert (enum_acquire.destination.local, enum_acquire.destination.local);
			return;
		}
		var enum_extract = instruction as CfgEnumExtractSum;
		if (enum_extract != null) {
			initialized.insert (enum_extract.destination.local, enum_extract.destination.local);
			return;
		}
		var slot_capture = instruction as CfgBufferSlotCapture;
		if (slot_capture != null) {
			verify_buffer_slot (slot_capture.place, slot_capture.cleanup, function, path);
			return;
		}
		var exchange = instruction as CfgBufferExchange;
		if (exchange != null) {
			if (exchange.cleanup != exchange.right_capture.cleanup) {
				fail (path, "buffer exchange requires identical concrete cleanup contracts");
			}
			verify_buffer_slot (exchange.left, exchange.cleanup, function, path + "/left");
			verify_buffer_slot (exchange.right, exchange.cleanup, function, path + "/right");
			return;
		}
		if (instruction is CfgBufferAllocate) {
			var allocation = (CfgBufferAllocate) instruction;
			var bytes = allocation.cleanup.buffer_type as ContextBytesType;
			var context = allocation.allocation_context;
			var load = context as CfgLoadValue;
			if ((bytes != null) != (context != null)) {
				fail (path, "byte allocation lost exact selected context authority");
			}
			if (context != null) {
				if (context.semantic_type != bytes.allocator_type || load == null && !(context is CfgParameterValue) || load != null && !(load.source is CfgLocalPlace)) {
					fail (path, "byte allocation requires an exact named context owner or borrowed parameter");
				}
				verify_value (context, function, path + "/context", null, true);
			}
			verify_buffer_results (allocation.results, allocation.cleanup, path);
			verify_value (allocation.count, function, path + "/count");
			if (allocation.count.semantic_type != allocation.cleanup.buffer_shape.length_type || (allocation.count is CfgIntegerValue && ((CfgIntegerValue) allocation.count).value.mathematical_value < 0)) {
				fail (path, "buffer count requires a non-negative int/i32 length");
			}
			available_results.insert (allocation.results.owner, allocation.results.owner);
			pending_acquisition = allocation.results.owner;
			return;
		}
		if (rearm != null) {
			verify_place (rearm.owner, function, path + "/owner");
			if ((!rearm.owner.semantic_type.is_ownable_handle_type () && !rearm.cleanup.is_buffer) || !cleanups.contains (rearm.cleanup) || rearm.owner.cleanup != rearm.cleanup) {
				fail (path, "ownership rearm requires exact owned void* local and its stable cleanup contract");
			}
			if (rearms.contains (rearm)) {
				fail (path, "rearm instruction identity occurs in more than one ordered instruction slot");
			}
			rearms.insert (rearm, rearm);
			if (rearm.source != null) {
				verify_transfer_source (rearm.source, rearm.owner.semantic_type, rearm.cleanup, function, path + "/source");
				if (rearm.source == rearm.owner || (!(rearm.source.semantic_type is HandleType) && !rearm.cleanup.is_buffer) || rearm.value != null) {
					fail (path, "replacement move requires distinct exact Resource owners and one incoming responsibility");
				}
				return;
			}
			verify_value (rearm.value, function, path + "/producer", null, false, rearm.cleanup);
			var producer = owned_results.lookup (rearm.value);
			if (producer == null || producer != rearm.cleanup || rearm.value.semantic_type != rearm.owner.semantic_type) {
				fail (path, "rearm requires the direct producer's exact cleanup contract");
			}
			return;
		}
		if (instruction is CfgStructResultConsume) {
			verify_struct_consumption ((CfgStructResultConsume) instruction, function, path);
			return;
		}
		var parameter_acquire = instruction as CfgAcquireParameter;
		if (parameter_acquire != null) {
			var owner = parameter_acquire.acquisition;
			var incoming = parameter_acquire.value as CfgParameterValue;
			if (owner == null || incoming == null || owner.cleanup.is_heap_object != incoming.parameter.heap_object || current_block != function.entry || parameter_acquire.target != owner || owner.incoming_parameter != incoming.parameter || owners.lookup (incoming.parameter) != function || incoming.parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || incoming.semantic_type != owner.semantic_type || owner.cleanup == null || initialized.contains (owner)) {
				fail (path, "parameter acquisition requires exact entry slot, owned native parameter and nominal cleanup");
			}
			verify_place (owner, function, path);
			initialized.insert (owner, owner);
			return;
		}
		var capture = instruction as CfgOwnedArgumentCapture;
		if (capture != null) {
			var value = capture.transfer;
			if (!contract_parameters.contains (value.parameter) || value.cleanup.is_heap_object != value.parameter.heap_object || value.parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || (!(value.semantic_type is HandleType) && !(value.semantic_type is ClassType) && !(value.semantic_type is SliceType)) || (value.cleanup.is_buffer && value.source == null) || value.semantic_type != value.parameter.semantic_type || !cleanups.contains (value.cleanup) || !matches_cleanup (value.semantic_type, value.cleanup) || evaluated_results.contains (value)) {
				fail (path, "pending owned argument requires unique capture and exact owned parameter contract");
			}

			if (value.source != null) {
				verify_transfer_source (value.source, value.semantic_type, value.cleanup, function, path);
			}
			evaluated_results.insert (value, value);
			available_evaluations.insert (value, value);
			return;
		}
		var owned_return = instruction as CfgOwnershipReturnInstruction;
		if (owned_return != null) {
			var value = owned_return.result;
			bool after_capture = false;
			foreach (var next in current_block.instructions) {
				if (next == owned_return) {
					after_capture = true;
					continue;
				}
				if (after_capture && !(next is CfgTextLoanEnd) && !(next is CfgEnumDrop) && !(next is CfgEnumEndInspection) && !(next is CfgTaskEnd) && !(next is CfgCleanupInstruction) && !(next is CfgLifecycleCallInstruction && !((CfgLifecycleCallInstruction) next).constructs)) {
					fail (path, "owned return capture must be followed only by lexical cleanups and its return");
				}
			}
			var terminator = current_block.terminator as CfgOwnershipReturn;
			if (terminator == null || terminator.value != value) {
				fail (path, "owned return capture requires its associated return after cleanups");
			}
			if (function.owned_cleanup == null || value.cleanup != function.owned_cleanup || value.semantic_type != function.return_type || evaluated_results.contains (value)) {
				fail (path, "owned return capture requires exact function result contract and unique result");
			}
			if (function.return_type is ClassType) {
				var captured = value.producer as CfgEvaluatedValue;
				var indirect = captured == null ? null : evaluated_sources.lookup (captured) as CfgInvocation;
				var expected = value.source != null ? (value.source.cleanup.is_heap_object ? ObjectResultProvenance.HEAP_OBJECT : null_local_owner (function, value.source) ? ObjectResultProvenance.NULL : incoming_local_owner (function, value.source) ? ObjectResultProvenance.OWNED_PARAMETER_STORAGE : ObjectResultProvenance.CALLEE_LOCAL_STORAGE) : (value.producer is CfgResultObjectStorage) ? ObjectResultProvenance.RESULT_STORAGE : (value.producer is CfgCallResultValue || indirect != null) ? ObjectResultProvenance.FORWARDED_OWNED_RESULT : ObjectResultProvenance.NULL;
				if ((value.source != null && value.source.cleanup.is_heap_object != function.heap_result) || !expected.is_returnable () || value.provenance != expected || (value.source != null && value.producer != null)) {
					fail (path, "owned return has illegal storage provenance");
				}
				if (value.producer is CfgResultObjectStorage) {
					int constructions = 0;
					foreach (var prior in current_block.instructions) {
						if (prior == instruction) {
							break;
						}
						var construction = prior as CfgResultConstructionInstruction;
						if (construction != null && construction.storage == value.producer) {
							constructions++;
						}
					}
					if (value.producer != function.result_storage || constructions != 1) {
						fail (path, "fresh return requires one successful direct result construction before capture");
					}
				} else if (indirect != null) {
					if (!function.heap_result || function.result_storage != null || indirect.result_cleanup () != value.cleanup || owned_results.lookup (captured) != value.cleanup) {
						fail (path, "indirect Class forwarding requires its exact captured heap result and cleanup");
					}
					verify_value (value.producer, function, path + "/producer", null, false, value.cleanup);
				} else if (value.producer != null) {
					verify_value (value.producer, function, path + "/producer", null, false, value.cleanup);
					CfgCallInstruction? producer = null;
					foreach (var candidate in function.blocks) {
						foreach (var prior in candidate.instructions) {
							var call = prior as CfgCallInstruction;
							if (call != null && call.result == value.producer && (candidate == current_block || (function.heap_result && call.exception_result != null && guarded_exception_success (call, function)))) {
								producer = call;
							}
						}
					}
					if (producer == null || producer.target.heap_result != function.heap_result || producer.result_storage != function.result_storage) {
						fail (path, "forwarded result requires exact storage/origin and same-block or guarded successful producer");
					}
					foreach (var argument in producer.arguments) {
						var transfer = argument as CfgPendingOwnedArgument;
						if (transfer != null && transfer.semantic_type == function.return_type && transfer.source != null && transfer.source.incoming_parameter == null && !transfer.source.cleanup.is_heap_object) {
							fail (path, "callee-local ObjectStorage cannot escape through forwarded result");
						}
					}
				}
			} else {
				if (value.provenance != ObjectResultProvenance.NONE || (value.source != null && value.producer != null)) {
					fail (path, "Resource result must retain exact source or direct producer authority");
				}
				if (value.producer != null) {
					var captured = value.producer as CfgEvaluatedValue;
					var invocation = captured == null ? null : evaluated_sources.lookup (captured) as CfgInvocation;
					if (!(value.producer is CfgCallResultValue || (invocation != null && invocation.result_cleanup () == value.cleanup && owned_results.lookup (captured) == value.cleanup)) || value.producer.semantic_type != function.return_type) {
						fail (path, "Resource forwarding requires exact invocation result type");
					}
					verify_value (value.producer, function, path + "/producer", null, false, value.cleanup);
				}
			}
			if (value.source != null) {
				verify_transfer_source (value.source, value.semantic_type, value.cleanup, function, path);
			}
			evaluated_results.insert (value, value);
			available_evaluations.insert (value, value);
			return;
		}
		var commit = instruction as CfgOwnedCallTransferCommit;
		if (commit != null) {
			if (pending_commit != null || commit.call == null || CfgInvocationContracts.arguments (commit.call) == null || commit.transfers.length == 0) {
				fail (path, "owned call commit requires a live associated invocation and transfers");
			}
			var sources = new HashTable<CfgLocalPlace, CfgLocalPlace> (direct_hash, direct_equal);
			foreach (var transfer in commit.transfers) {
				if (transfer.source != null && !sources.insert (transfer.source, transfer.source)) {
					fail (path, "owned call commit cannot transfer the same source twice");
				}
				if (committed_transfers.contains (transfer) || (!available_evaluations.contains (transfer) && !available_on_entry (transfer, function))) {
					fail (path, "owned call commit requires exactly one preceding capture per transfer");
				}
				committed_transfers.insert (transfer, commit);
				verify_pending_interval (transfer, commit, function, path);
			}
			pending_commit = commit;
			return;
		}
		var release = instruction as CfgOwnershipReleaseInstruction;
		if (release != null) {
			if (release.owner.semantic_type.is_scoped_allocator ()) {
				fail (path, "scoped context retires at its lexical scope exit");
			}
			verify_place (release.owner, function, path + "/owner");
			if ((!release.owner.semantic_type.is_ownable_handle_type () && !release.cleanup.is_buffer && !release.cleanup.is_heap_object) || !cleanups.contains (release.cleanup) || release.owner.cleanup != release.cleanup) {
				fail (path, "ownership release requires exact owned void* local and its cleanup contract");
			}
			if (releases.contains (release)) {
				fail (path, "release instruction identity occurs in more than one ordered instruction slot");
			}
			releases.insert (release, release);
			return;
		}
		var borrow = instruction as CfgOwnedBorrowInstruction;
		if (borrow != null) {
			var value = borrow.result;
			bool projected_callback = value.semantic_type is CallbackType && ((CallbackType) value.semantic_type).matches_closure (value.source.semantic_type);
			bool projected_buffer = value is CfgBufferBorrowValue && value.parameter != null && ContextBytesType.permits_view (value.source.semantic_type, value.semantic_type);
			verify_place (value.source, function, path + "/owner");
			if (value.source.cleanup == null || (!value.semantic_type.is_ownable_handle_type () && !(value.semantic_type is ClassType) && !(value is CfgBufferBorrowValue) && !projected_callback) || value.semantic_type != value.source.semantic_type && !projected_callback && !projected_buffer || (value.parameter == null ? !(value is CfgBufferBorrowValue) || !value.source.cleanup.is_buffer : !contract_parameters.contains (value.parameter) || value.parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || (value.parameter.semantic_type != value.semantic_type && !(value.semantic_type is ClassType && value.parameter.semantic_type is ClassType && ((ClassType) value.semantic_type).derives_from ((ClassType) value.parameter.semantic_type)))) || borrow_definitions.contains (value)) {
				fail (path, "borrow event requires exact owned void* local, borrowed parameter and unique result");
			}
			borrow_definitions.insert (value, value);
			available_borrows.insert (value, value);
			return;
		}
		var transfer = instruction as CfgOwnershipTransferInstruction;
		if (transfer != null) {
			verify_place (transfer.source, function, path + "/source");
			verify_place (transfer.destination, function, path + "/destination");
			if (transfer.source == transfer.destination || !cleanups.contains (transfer.cleanup) || transfer.source.cleanup != transfer.cleanup || transfer.destination.cleanup != transfer.cleanup || (!transfer.source.semantic_type.is_ownable_handle_type () && !transfer.cleanup.is_buffer && !transfer.cleanup.is_heap_object && record_field (transfer.source.semantic_type) == null && !(transfer.source.semantic_type is ClassType && incoming_local_transfer (function, transfer))) || transfer.source.semantic_type != transfer.destination.semantic_type || initialized.contains (transfer.destination)) {
				fail (path, "ownership transfer requires distinct exact void* owners, identical cleanup contracts and one fresh destination initialization");
			}
			if (record_field (transfer.source.semantic_type) != null) {
				foreach (var field in function.field_places) {
					if (field.root_local () == transfer.destination) {
						initialized.insert (field, field);
					}
				}
			}
			initialized.insert (transfer.destination, transfer.destination);
			return;
		}
		var array = instruction as CfgArrayInitialize;
		if (array != null) {
			verify_array_storage (array.storage, function, false, path);
			var type = (ArrayType) array.storage.semantic_type;
			if (array.record_root != null) {
				verify_record_array_entry (array, function, path);
				return;
			}
			if (type.element_type is StructType || array.record_fields.length != 0 || record_initializations.contains (array.storage)) {
				fail (path, "record arrays require complete ordered typed entry initialization");
			}
			if (initialized.contains (array.storage) || array.elements.length != type.length) {
				fail (path, "array initialization requires exactly N elements and one site");
			}
			foreach (var element in array.elements) {
				verify_value (element, function, path + "/element");
				if (element.semantic_type != type.element_type) {
					fail (path, "array initializer element requires exact type");
				}
			}
			initialized.insert (array.storage, array.storage);
			available_arrays.insert (array.storage, array.storage);
			return;
		}
		var numeric_guard = instruction as CfgNumericGuard;
		if (numeric_guard != null) {
			verify_type (numeric_guard.destination_type, true, path + "/destination");
			if (!(numeric_guard.value.semantic_type is FloatingType) || !(numeric_guard.destination_type is IntegerType) || numeric_guard.policy != NumericConversionPolicy.TRUNCATE_TRAP) {
				fail (path, "numeric guard requires floating source, exact integer destination and truncation/trap policy");
			}
		}
		var slice_bounds = instruction as CfgSliceBoundsCheck;
		if (slice_bounds != null) {
			verify_value (slice_bounds.slice, function, path + "/slice", null, false, null, false, true);
			if (!(slice_bounds.slice is CfgEvaluatedValue) || !(slice_bounds.slice.semantic_type is SliceType) || !(slice_bounds.value.semantic_type is IntegerType)) {
				fail (path, "slice bounds require a captured SliceType and integer index");
			}
		}
		var bounds = instruction as CfgArrayBoundsCheck;
		if (bounds != null) {
			verify_array_storage (bounds.storage, function, true, path);
			if (!(bounds.value.semantic_type is IntegerType)) {
				fail (path, "array bounds check requires integer index");
			}
		}
		var validation = instruction as CfgValidatePlace;
		if (validation != null) {
			CfgPlace root = validation.place;
			while (root is CfgFieldPlace) {
				root = ((CfgFieldPlace) root).aggregate;
			}
			if (root is CfgTemporaryPlace || (root is CfgLocalPlace && !((CfgLocalPlace) root).address_taken)) {
				fail (path, "Place validation requires memory-backed storage");
			}
			verify_place (validation.place, function, path + "/place");
			return;
		}
		var resource_capture = instruction as CfgResourceCapture;
		if (instruction is CfgRecordTake) {
			var take = (CfgRecordTake) instruction;
			if (take.source.cleanup == null || take.source.cleanup.record_type == null || take.field.root_local () != take.source || take.field.field.owned_cleanup == null || take.destination.cleanup != take.field.field.owned_cleanup || take.destination.semantic_type != take.field.semantic_type || initialized.contains (take.destination)) {
				fail (path, "record field take requires exact source owner/path and one fresh typed destination");
			}
			verify_place (take.field, function, path + "/field");
			verify_place (take.destination, function, path + "/destination");
			initialized.insert (take.destination, take.destination);
			return;
		}
		if (instruction is CfgRecordReplace) {
			var replace = (CfgRecordReplace) instruction;
			var field = replace.field;
			if (replace.owner.cleanup == null || replace.owner.cleanup.record_type == null || field.root_local () != replace.owner || field.field.owned_cleanup == null || replace.incoming.semantic_type != field.semantic_type) {
				fail (path, "record replacement requires exact original root/path and typed incoming ownership");
			}
			verify_place (field, function, path + "/field");
			if (replace.source != null) {
				verify_transfer_source (replace.source, field.semantic_type, field.field.owned_cleanup, function, path);
				var load = replace.incoming as CfgLoadValue;
				if (load == null || load.source != replace.source) {
					fail (path, "record replacement must capture its exact original incoming named owner");
				}
			} else {
				if (owned_results.lookup (replace.incoming) != field.field.owned_cleanup) {
					fail (path, "record replacement requires one exact direct owned producer");
				}
				verify_value (replace.incoming, function, path + "/incoming", null, false, field.field.owned_cleanup);
			}
			return;
		}
		if (resource_capture != null) {
			if ((!(resource_capture.value.semantic_type is HandleType) && !resource_capture.cleanup.is_buffer && !resource_capture.cleanup.is_heap_object) || !cleanups.contains (resource_capture.cleanup) || !matches_cleanup (resource_capture.value.semantic_type, resource_capture.cleanup)) {
				fail (path, "Resource capture requires exact concrete handle and release identity");
			}
			if (resource_capture.value.semantic_type is ClassType && !resource_capture.cleanup.is_heap_object) {
				fail (path, "child field capture requires exact heap ownership");
			}
			verify_resource_capture_order (resource_capture, path);
			if (resource_capture.source != null) {
				verify_transfer_source (resource_capture.source, resource_capture.value.semantic_type, resource_capture.cleanup, function, path);
				var load = resource_capture.value as CfgLoadValue;
				if (load == null || load.source != resource_capture.source) {
					fail (path, "Resource capture must read its exact incoming owner");
				}
			} else if (!(resource_capture.value is CfgCallResultValue || resource_capture.value is CfgEvaluatedValue) || owned_results.lookup (resource_capture.value) != resource_capture.cleanup) {
				fail (path, "Resource capture requires an exact direct owned producer");
			}
		}
		var evaluation = instruction as CfgEvaluateInstruction;
		if (evaluation != null) {
			evaluated_sources.insert (evaluation.result, evaluation.value);
		}
		if (evaluation != null) {
			if (evaluations.contains (evaluation)) {
				fail (path, "evaluation instruction identity occurs in more than one instruction slot");
			}
			evaluations.insert (evaluation, evaluation);
			if (evaluation.value is CfgClassUpcast) {
				class_upcasts.insert (evaluation.result, (CfgClassUpcast) evaluation.value);
			}
			verify_value (evaluation.value, function, path + "/value", null, resource_capture != null, resource_capture == null ? null : resource_capture.cleanup, evaluation.result.semantic_type is ReceiverType, evaluation.value is CfgBufferBorrowValue || evaluation.value is CfgRecordBufferView || evaluation.value is CfgRecordParameterBufferView);
			verify_type (evaluation.result.semantic_type, evaluation.result.semantic_type.kind != TypeKind.VOID, path + "/result");
			if (evaluation.result.semantic_type != evaluation.value.semantic_type) {
				fail (path, "evaluation result type must match its value type");
			}
			if (evaluated_results.contains (evaluation.result)) {
				fail (path, "evaluation result identity occurs in more than one definition slot");
			}
			evaluated_results.insert (evaluation.result, evaluation.result);
			if (owned_results.contains (evaluation.result)) {
				pending_acquisition = evaluation.result;
			}
			available_evaluations.insert (evaluation.result, evaluation.result);
			return;
		}
		var cleanup = instruction as CfgCleanupInstruction;
		if (cleanup != null) {
			if (!cleanups.contains (cleanup.cleanup) || (!cleanup.value.semantic_type.is_ownable_handle_type () && !(cleanup.value.semantic_type is ClassType) && !cleanup.cleanup.is_buffer) || !matches_cleanup (cleanup.value.semantic_type, cleanup.cleanup)) {
				fail (path, "cleanup requires exact program-owned void (void*) contract, void* argument and no result");
			}
			if (cleanup_instructions.contains (cleanup)) {
				fail (path, "cleanup instruction identity occurs in more than one ordered instruction slot");
			}
			if (cleanup.record_owner != null) {
				var root = cleanup.record_owner;
				var loaded = cleanup.value as CfgLoadValue;
				var place = loaded == null ? null : loaded.source as CfgFieldPlace;
				if (place == null || place.root_local () != root || place.field.owned_cleanup != cleanup.cleanup || !matches_cleanup (place.semantic_type, cleanup.cleanup) || place_owners.lookup (root) != function) {
					fail (path, "record retirement requires exact original owner and Resource leaf");
				}
			}
			cleanup_instructions.insert (cleanup, cleanup);
			var load = cleanup.value as CfgLoadValue;
			if (load != null && load.source is CfgIndirectFieldPlace && (load.semantic_type is HandleType || load.semantic_type is SliceType || load.semantic_type is ClassType) && !field_epilogues.contains (cleanup)) {
				if (!resource_replacements.contains (cleanup)) {
					fail (path, "field release requires an exact replacement or automatic destructor epilogue");
				}
			}
			var owner = load == null ? null : load.source as CfgLocalPlace;
			if (owner != null && owner.cleanup != null && owner.cleanup != cleanup.cleanup) {
				fail (path, "lexical cleanup must retain the owner's exact contract");
			}
			verify_value (cleanup.value, function, path + "/value", null, false, (cleanup.value is CfgCallResultValue) ? cleanup.cleanup : null);
			return;
		}
		var c_call = instruction as CfgCCallInstruction;
		if (c_call != null) {
			if (calls.contains (c_call)) {
				fail (path, "call instruction identity occurs in more than one instruction slot");
			}
			calls.insert (c_call, c_call);
			var target = c_call.target;
			if (target == null || !c_functions.contains (target)) {
				fail (path, "call target is not owned by the containing program");
				return;
			}
			int leaf = 0;
			int group_index = 0;
			for (int p = 0; p < target.parameter_types.length; p++) {
				var type = target.parameter_types[p];
				if (type.is_struct_storage ()) {
					if (group_index >= c_call.struct_arguments.length) {
						fail (path, "C record argument lost its source grouping");
					}
					var group = c_call.struct_arguments[group_index++];
					if (group.source_ordinal != p || group.first_leaf != leaf || group.shape.semantic_type != type) {
						fail (path, "C record argument lost exact source ordinal/type/leaf range");
					}
					verify_struct_shape (group.shape, type, path);
					foreach (var field in group.shape.leaves) {
						if (leaf >= c_call.arguments.length || c_call.arguments[leaf].semantic_type != field.semantic_type) {
							fail (path, "C record argument lost exact ordered fields");
						}
						var value = c_call.arguments[leaf++];
						verify_value (value, function, path, target.parameters[p].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE ? target.parameters[p] : null);
					}
				} else {
					if (leaf >= c_call.arguments.length || c_call.arguments[leaf].semantic_type != type) {
						fail (path, "C call scalar argument lost exact type");
					}
					var value = c_call.arguments[leaf++];
					verify_value (value, function, path, target.parameters[p].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE ? target.parameters[p] : null);
				}
			}
			if (leaf != c_call.arguments.length || group_index != c_call.struct_arguments.length) {
				fail (path, "C call has extra argument fields/groups");
			}

			if (target.return_type.is_struct_storage ()) {
				var group = c_call.struct_result;
				if (c_call.result != null || group == null || group.shape.semantic_type != target.return_type || group.leaves.length != group.shape.leaves.length) {
					fail (path, "C value record result requires exact complete field definitions");
				}
				verify_struct_shape (group.shape, target.return_type, path);
				if (struct_results.contains (group)) {
					fail (path, "C record group has duplicate producer");
				}
				struct_results.insert (group, c_call);
				for (int r = 0; r < group.leaves.length; r++) {
					var field = group.leaves[r];
					if (field.semantic_type != group.shape.leaves[r].semantic_type || results.contains (field)) {
						fail (path, "C record result lost unique typed fields");
					}
					results.insert (field, c_call);
					available_results.insert (field, field);
					struct_result_leaves.insert (field, group);
				}
			} else if (c_call.struct_result != null) {
				fail (path, "C scalar result cannot carry record fields");
			} else if (target.return_type.kind == TypeKind.VOID) {
				if (c_call.result != null) {
					fail (path, "void call must not define a result");
				}
			} else {
				if (c_call.result == null || c_call.result.semantic_type != target.return_type) {
					fail (path, "non-void call must define a result matching the target return type");
					return;
				}
				verify_type (c_call.result.semantic_type, true, path + "/result");
				if (results.contains (c_call.result)) {
					fail (path, "call result identity occurs in more than one definition slot");
				}
				results.insert (c_call.result, c_call);
				available_results.insert (c_call.result, c_call.result);
				if (target.owned_cleanup != null) {
					pending_acquisition = c_call.result;
				}
			}
			return;
		}
		var call = instruction as CfgCallInstruction;
		if (call != null) {
			if (!call.readonly_context_valid ()) {
				fail (path, "call lost original readonly scope context");
			}
			if (calls.contains (call)) {
				fail (path, "call instruction identity occurs in more than one instruction slot");
			}
			calls.insert (call, call);
			var target = call.target;
			if (target != null && functions.contains (target) && target.blocks.length != 0 && target.entry.is_complete && target.entry.terminator is CfgForeignReturn && ((CfgForeignReturn) target.entry.terminator).binding.root.api.active_personalities == 0) {
				fail (path, "call requires unselected foreign import");
			}
			if (target == null || !functions.contains (target)) {
				fail (path, "call target is not owned by the containing program");
				return;
			}
			var receiver_contract = target.implicit_receiver;
			if ((receiver_contract == null) != (call.receiver == null)) {
				fail (path, "method call requires exactly one implicit receiver; free calls have none");
			}
			if (call.receiver != null) {
				if (call.receiver.semantic_type != receiver_contract.contract || !(call.receiver is CfgReceiverValue || call.receiver is CfgEvaluatedValue || (call is CfgLifecycleCallInstruction && call.receiver is CfgStorageReceiverValue) || (call is CfgResultConstructionInstruction && call.receiver is CfgResultStorageReceiverValue))) {
					fail (path, "method receiver must be exact and evaluated before arguments and transfer commit");
				}
				verify_value (call.receiver, function, path + "/receiver", null, false, null, true);
			}
			var construction = call as CfgResultConstructionInstruction;
			if (construction != null) {
				var returned = current_block.terminator as CfgOwnershipReturn;
				var captured = returned == null ? null : returned.value as CfgOwnedReturnValue;
				if (captured == null || captured.producer != construction.storage || captured.provenance != ObjectResultProvenance.RESULT_STORAGE) {
					fail (path, "constructed result must transfer through this block's owned return");
				}
				if (construction.storage != function.result_storage || construction.storage == null || !(target is CfgConstructor) || construction.storage.object_class.constructor != target || !(call.receiver is CfgResultStorageReceiverValue) || ((CfgResultStorageReceiverValue) call.receiver).storage != construction.storage) {
					fail (path, "fresh result requires exact constructor and supplied result storage");
				}
			}
			if (target.result_storage != null) {
				if ((call.candidate_storage == null) == (call.result_storage == null)) {
					fail (path, "owned result call requires exactly one storage destination");
				}
				if (call.result_storage != null && (call.result_storage != function.result_storage || call.result_storage.semantic_type != target.return_type)) {
					fail (path, "forwarded result requires same exact result storage");
				}
				if (call.candidate_storage != null && (!call.candidate_storage.result_candidate || call.candidate_storage.transferable || object_owners.lookup (call.candidate_storage) != function || call.candidate_storage.semantic_type != target.return_type || result_candidates.contains (call.candidate_storage))) {
					fail (path, "call candidate requires exact caller storage unique to this acquisition");
				}
				if (call.candidate_storage != null) {
					result_candidates.insert (call.candidate_storage, call);
				}
			} else if (call.result_storage != null || call.candidate_storage != null) {
				fail (path, "call has no result storage contract");
			}
			if (call is CfgBaseLifecycleCall) {
				var lifecycle = function as CfgLifecycle;
				var cast = class_upcasts.lookup ((CfgEvaluatedValue) call.receiver);
				var self = cast == null ? null : cast.reference as CfgReceiverValue;
				if (lifecycle == null || lifecycle.declaring_class.parent_class == null || cast == null || self == null || self.receiver != lifecycle.receiver || cast.source_class != lifecycle.declaring_class || cast.target_class != lifecycle.declaring_class.parent_class) {
					fail (path, "base lifecycle requires an exact child lifecycle receiver");
				}
				if (lifecycle is CfgConstructor) {
					if (target != lifecycle.declaring_class.parent_class.constructor || field_state == null || field_state.is_possible ((int) lifecycle.declaring_class.fields.length)) {
						fail (path, "base init requires one exact direct-parent constructor call");
					}
					field_state.initialize ((int) lifecycle.declaring_class.fields.length);
				} else if (!(lifecycle is CfgDestructor) || target != lifecycle.declaring_class.parent_class.destructor || call.arguments.length != 0) {
					fail (path, "base deinit requires exact direct-parent teardown and no arguments");
				}
			}
			var lifecycle_call = call as CfgLifecycleCallInstruction;
			if ((target is CfgLifecycle) != (lifecycle_call != null || call is CfgResultConstructionInstruction || call is CfgBaseLifecycleCall)) {
				fail (path, "lifecycle invocation requires explicit construction or object cleanup authority");
			}
			if (lifecycle_call != null) {
				var storage = lifecycle_call.storage;
				var lifecycle = (CfgLifecycle) target;
				var address = call.receiver as CfgStorageReceiverValue;
				if (address == null || address.storage != storage) {
					fail (path, "lifecycle receiver must be the original storage address, never a reference binding");
				}
				if (lifecycle_call.constructs && storage.fallible) {
					foreach (var input in call.arguments) {
						var captured = input as CfgPendingOwnedArgument;
						if (captured != null && captured.source != null && (captured.source.semantic_type != captured.semantic_type || captured.source.requires_nonnull || captured.source.incoming_parameter != null && captured.source.incoming_parameter.requires_nonnull)) {
							fail (path, "fallible input requires an exact nullable caller slot");
						}
					}
				}
				if (lifecycle_call.constructs) {
					available_constructors.insert (storage, storage);
				}
				if (storage.result_candidate || (!lifecycle_call.constructs && storage.transferable) || object_owners.lookup (storage) != function || storage.object_class != lifecycle.declaring_class || (lifecycle_call.constructs ? storage.object_class.constructor != lifecycle : storage.destructor != lifecycle)) {
					fail (path, "lifecycle cleanup/construction requires exact original ObjectStorage and matching class member");
				}
			}
			if ((target.throws_type == null) != (call.exception_result == null)) {
				fail (path, "throwing call requires one explicit private exception result");
			}
			if (call.exception_result != null) {
				available_evaluations.insert (call.exception_result, call.exception_result);
			}
			verify_call_arguments (call, function, path);
			if (target.struct_result != null) {
				var group = call.struct_result;
				if (call.result != null || group == null || group.shape.semantic_type != target.return_type || struct_results.contains (group)) {
					fail (path, "struct call requires one exact leaf result group and no aggregate Value");
				}
				verify_struct_shape (group.shape, target.return_type, path + "/result");
				if (group.shape.mode != target.struct_result.mode) {
					fail (path, "record call result changed its declared copy, move or bounded borrow operation");
				}
				if (group.leaves.length != group.shape.leaves.length) {
					fail (path, "struct call result leaf count mismatch");
				}
				struct_results.insert (group, call);
				for (int r = 0; r < group.leaves.length; r++) {
					var leaf = group.leaves[r];
					if (leaf.semantic_type != group.shape.leaves[r].semantic_type || results.contains (leaf)) {
						fail (path, "struct call result requires unique ordered exact leaf definitions");
					}
					results.insert (leaf, call);
					available_results.insert (leaf, leaf);
					struct_result_leaves.insert (leaf, group);
				}
			} else if (call.struct_result != null) {
				fail (path, "scalar call cannot carry struct result grouping");
			} else if (target.return_type is EnumType) {
				if (call.result != null || call.enum_result == null) {
					fail (path, "enum call requires caller storage");
				}
			} else if (target.return_type.kind == TypeKind.VOID) {
				if (call.result != null) {
					fail (path, "void call must not define a result");
				}
			} else {
				if (call.result == null || call.result.semantic_type != target.return_type) {
					fail (path, "non-void call must define a result matching the target return type");
					return;
				}
				verify_type (call.result.semantic_type, true, path + "/result");
				if (results.contains (call.result)) {
					fail (path, "call result identity occurs in more than one definition slot");
				}
				results.insert (call.result, call);
				if (target.owned_cleanup != null && target.owned_cleanup.is_buffer) {
					if (call.buffer_result == null || call.buffer_result.owner != call.result) {
						fail (path, "buffer call requires complete exact result pair");
					}
					verify_buffer_results (call.buffer_result, target.owned_cleanup, path);
				} else if (call.buffer_result != null) {
					fail (path, "non-buffer call cannot carry buffer owner results");
				}
				if (target.owned_cleanup != null && call.exception_result == null) {
					pending_acquisition = call.result;
				}
				available_results.insert (call.result, call.result);
			}
			return;
		}
		var initialization = instruction as CfgInitialize;
		var field_store = instruction as CfgStore;
		var field_destination = (initialization != null ? initialization.target : field_store == null ? null : field_store.target) as CfgIndirectFieldPlace;
		if (field_destination != null && field_destination.semantic_type is HandleType && !resource_stores.contains (instruction)) {
			fail (path, "Resource field writes require exact incoming ownership capture");
		}
		var record_destination = (initialization != null ? initialization.target : field_store == null ? null : field_store.target) as CfgFieldPlace;
		if (record_destination != null && record_destination.semantic_type is HandleType && !resource_stores.contains (instruction)) {
			fail (path, "record Resource writes require exact whole-record acquisition");
		}
		if (initialization != null) {
			if ((initialization.target is CfgIndirectFieldPlace && !(function is CfgConstructor && ((CfgIndirectFieldPlace) initialization.target).pointer is CfgReceiverValue)) || initialization.target is CfgDereferencePlace || initialization.target is CfgArrayElementPlace || initialization.target is CfgSliceElementPlace) {
				fail (path, "indirect storage cannot be initialized; use Store");
			}
			string record_part;
			var record_root = CfgConstructorInitialization.record_root (initialization.target, out record_part);
			var record_receiver = record_root == null ? null : record_root.pointer as CfgReceiverValue;
			bool constructor_record = function is CfgConstructor && record_receiver != null && record_receiver.receiver == function.implicit_receiver && record_root.field.containing_type == ((CfgConstructor) function).declaring_class;
			if (initialization.target is CfgFieldPlace && ((CfgFieldPlace) initialization.target).root_local () == null && !constructor_record) {
				fail (path, "indirect storage cannot be initialized; use Store");
			}
			if (constructor_record) {
				if (field_state == null || field_state.is_part_possible (record_root.field.ordinal, record_part)) {
					fail (path, "constructor record leaf possibly initialized twice");
				}
				try {
					if (!field_state.initialize_record_part (record_root.field.ordinal, record_part, StructLeafOrder.path_names (record_root.semantic_type, struct_fields))) {
						fail (path, "constructor record initialization lost exact leaf path");
					}
				} catch (StructLeafError error) {
					fail (path, error.message);
				}
			}
			verify_type (initialization.target.semantic_type, true, path + "/target");
			verify_place (initialization.target, function, path + "/target");
			if (initialized.contains (initialization.target)) {
				fail (path, (initialization.target is CfgTemporaryPlace) ? "temporary must have exactly one initialization" : "local must have exactly one initialization");
			}
			reject_stored_owner (initialization.value, path);
			var local = initialization.target as CfgLocalPlace;
			var record = initialization.target as CfgFieldPlace;
			var owner = record != null && resource_stores.contains (instruction) ? initialization.acquisition : local == null || local.cleanup == null ? null : local;
			if (initialization.target.semantic_type.is_scoped_allocator ()) {
				var evaluated = initialization.value as CfgEvaluatedValue;
				if (owner == null || evaluated == null || !(evaluated_sources.lookup (evaluated) is CfgScopedAllocator)) {
					fail (path, "scoped context requires one exact lexical intrinsic acquisition");
				}
			}
			verify_value (initialization.value, function, path + "/value", null, false, owner == null ? null : owner.cleanup);
			if (initialization.acquisition != owner) {
				fail (path, "owned initialization requires its exact acquisition marker");
			}
			if (owner != null && owner.cleanup.is_object && owner.object_storage != null) {
				var evaluated = initialization.value as CfgEvaluatedValue;
				var reference = evaluated == null ? null : evaluated_sources.lookup (evaluated) as CfgObjectReferenceValue;
				if (reference == null || owner.cleanup.is_heap_object != owner.object_storage.heap_allocated || reference.storage != owner.object_storage || !reference.storage.transferable || reference.storage.semantic_type != owner.semantic_type) {
					fail (path, "object owner acquisition requires its exact fresh published ObjectStorage");
				}
			} else if (owner != null && record == null) {
				var slots_take = initialization.value as CfgSlotsValue;
				var producer = slots_take != null && slots_take.action == OwnerSlotsAction.TAKE ? slots_take.store.field.slots_cleanup : owned_results.lookup (initialization.value);
				if (producer == null || producer != owner.cleanup) {
					fail (path, "acquisition requires the direct producer's exact cleanup contract");
				}
			}
			if (initialization.value.semantic_type != initialization.target.semantic_type) {
				fail (path, "initializer value type does not match target place type");
			}
			if (initialization.target is CfgIndirectFieldPlace) {
				var field = ((CfgIndirectFieldPlace) initialization.target).field;
				if (field_state == null || field_state.is_possible (field.ordinal)) {
					fail (path, "constructor field possibly initialized twice: " + field.name);
				}
				field_state.initialize (field.ordinal);
			}
			initialized.insert (initialization.target, initialization.target);
			return;
		}
		var store = instruction as CfgStore;
		if (store != null && (!VolatileAccessContract.valid (store.volatile_access, store.volatile_enabled, store.target.semantic_type) || (store.volatile_enabled && !(store.target is CfgDereferencePlace || store.target is CfgArrayElementPlace || store.target is CfgSliceElementPlace)))) {
			fail (path, "volatile store requires its exact typed memory provenance and flag");
		}
		if (store != null && store.target is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) store.target).field.text_snapshot) {
			fail (path, "readonly snapshot cannot be rebound");
		}
		if (store != null && store.target is CfgSliceElementPlace && ((CfgSliceElementPlace) store.target).slice_type.element_access != SliceElementAccess.READ_WRITE) {
			fail (path, "text slice descriptor elements are read-only");
		}
		if (store != null && field_state != null && store.target is CfgIndirectFieldPlace && ((CfgIndirectFieldPlace) store.target).pointer is CfgReceiverValue) {
			fail (path, "constructor field writes must be Initialize");
		}
		if (store != null && field_state != null) {
			string part;
			var root = CfgConstructorInitialization.record_root (store.target, out part);
			if (root != null && root.pointer is CfgReceiverValue) {
				fail (path, "constructor record leaf writes must be Initialize");
			}
		}
		if (store != null) {
			var parameter_root = (store.target as CfgLocalPlace) ?? ((store.target is CfgFieldPlace) ? ((CfgFieldPlace) store.target).root_local () : null);
			if (parameter_root != null && parameter_root.struct_parameter != null) {
				fail (path, "by-value struct parameter storage is read-only");
			}
			if (store.target is CfgObjectFieldPlace) {
				fail (path, "object storage is initialized directly and accessed through references afterward");
			}
			var local = store.target as CfgLocalPlace;
			if (local != null && local.cleanup != null) {
				fail (path, "owned storage cannot be reassigned or rearmed");
			}
			verify_type (store.target.semantic_type, true, path + "/target");
			verify_place (store.target, function, path + "/target");
			reject_stored_owner (store.value, path);
			verify_value (store.value, function, path + "/value");
			if (store.value.semantic_type != store.target.semantic_type) {
				fail (path, "stored value type does not match target place type");
			}
			return;
		}
		fail (path, "unsupported CFG instruction");
	}

	private void verify_record_array_entry(CfgArrayInitialize entry, CfgFunction function, string path) throws CfgError {
		var root = entry.record_root;
		var type = entry.storage.semantic_type as ArrayType;
		var entries = record_initializations.lookup (entry.storage);
		if (type == null || !(type.element_type is StructType) || root.storage != entry.storage || root.array_type != type || entry.elements.length != entry.record_fields.length || entries == null || entries.length != type.length) {
			fail (path, "record array requires N complete exact typed entry initializations");
		}
		if (entry.record_ordinal > 0) {
			var prior = entries[entry.record_ordinal - 1];
			var site = record_initialization_blocks.lookup (prior);
			if (site == current_block ? !verified_record_initializations.contains (prior) : !block_available_on_entry (site, function)) {
				fail (path, "each record entry must finish before the next entry is initialized");
			}
		}
		GenericArray<StructLeafPath> expected;
		try {
			expected = StructLeafOrder.enumerate (type.element_type, element_fields);
		} catch (StructLeafError error) {
			fail (path, error.message);
			return;
		}
		if (expected.length != entry.elements.length) {
			fail (path, "record entry must initialize every semantic leaf");
		}
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (int i = 0; i < entry.elements.length; i++) {
			var field = entry.record_fields[i];
			initializing_array_entry = root;
			verify_place (field, function, path);
			initializing_array_entry = null;
			string key = "";
			CfgPlace base_place = field;
			while (base_place is CfgFieldPlace) {
				var projection = (CfgFieldPlace) base_place;
				key = projection.field.ordinal.to_string () + (key == "" ? "" : "." + key);
				base_place = projection.aggregate;
			}
			bool found = false;
			foreach (var leaf in expected) {
				if (leaf.spelling () == key && leaf.semantic_type == field.semantic_type) {
					found = true;
				}
			}
			if (base_place != root || !found || seen.contains (key)) {
				fail (path, "record entry requires distinct exact leaf projections from its indexed root");
			}
			seen.insert (key, true);
			verify_value (entry.elements[i], function, path);
			if (entry.elements[i].semantic_type != field.semantic_type) {
				fail (path, "record field initializer requires exact scalar/vector leaf type");
			}
		}
		verified_record_initializations.insert (entry, true);
		if (entry.completes_array) {
			initialized.insert (entry.storage, entry.storage);
			available_arrays.insert (entry.storage, entry.storage);
		}
	}

	private void verify_array_storage(CfgLocalPlace storage, CfgFunction function, bool initialized, string path) throws CfgError {
		var type = storage.semantic_type as ArrayType;
		if (type == null || place_owners.lookup (storage) != function || storage.is_promotable ()) {
			fail (path, "array requires exact local storage");
			return;
		}
		verify_array_type (type, path);
		if (initialized && !available_arrays.contains (storage) && !block_available_on_entry (array_initializations.lookup (storage), function)) {
			fail (path, "complete array initialization must precede and dominate storage use");
		}
	}

	private void verify_layout(CfgNativeInstance structure, HashTable<CfgNativeInstance, CfgNativeInstance> complete, GenericArray<CfgNativeInstance> active) throws CfgError {
		if (complete.contains (structure)) {
			return;
		}
		for (int i = 0; i < active.length; i++) {
			if (active[i] != structure) {
				continue;
			}
			var path = new StringBuilder ();
			for (int j = i; j < active.length; j++) {
				path.append (active[j].name + " → ");
			}
			fail ("struct layout", "recursive by-value struct layout: " + path.str + structure.name);
		}
		active.add (structure);
		foreach (var field in structure.fields) {
			if (!(field.semantic_type is StructType)) {
				continue;
			}
			var dependency = structs.lookup (field.semantic_type);
			if (!(dependency is CfgStruct)) {
				fail ("struct layout", "embedded struct requires its exact program-owned descriptor");
			}
			verify_layout (dependency, complete, active);
		}
		active.remove_index (active.length - 1);
		complete.insert (structure, structure);
	}

	private void verify_projections(CfgPlace aggregate, CfgFunction function, ref int index, string path) throws CfgError {
		foreach (var field in structs.lookup (aggregate.semantic_type).fields) {
			if (index >= function.field_places.length) {
				fail (path, "missing canonical field projection");
			}
			var place = function.field_places[index++];
			if (place.aggregate != aggregate || place.field != field || place.semantic_type != field.semantic_type || place_owners.contains (place)) {
				fail (path, "field projection must be canonical, function-owned and match its exact aggregate base and declared field");
			}
			place_owners.insert (place, function);
			if (field.semantic_type is StructType) {
				verify_projections (place, function, ref index, path);
			}
		}
	}

	private void verify_field_visibility(CfgStructField field, CfgFunction function, string path) throws CfgError {
		if (!field.is_private) {
			return;
		}
		var owner = field.containing_type as CfgClass;
		var receiver = function.implicit_receiver;
		if (owner == null || receiver == null || receiver.contract.instance_type != owner.semantic_type) {
			fail (path, "private field access requires its exact lexical declaring Class");
		}
	}

	private void verify_place(CfgPlace place, CfgFunction function, string path) throws CfgError {
		if (place.semantic_type is CallbackType) {
			fail (path, "call-scoped Callback cannot occupy storage");
		}
		var object_field = place as CfgObjectFieldPlace;
		if (object_field != null) {
			var storage = object_field.storage;
			var field = object_field.field;
			verify_field_visibility (field, function, path);
			if (storage.result_candidate || object_owners.lookup (storage) != function || field.containing_type != storage.object_class || field.ordinal < 0 || field.ordinal >= storage.object_class.fields.length || storage.object_class.fields[field.ordinal] != field || place.semantic_type != field.semantic_type || object_fields.lookup (storage).lookup (field) != object_field) {
				fail (path, "object field requires exact storage/class/field identity");
			}
			return;
		}
		var slice = place as CfgSliceElementPlace;
		if (slice != null) {
			verify_value (slice.slice, function, path + "/operand", null, false, null, false, true);
			verify_value (slice.index, function, path + "/operand");
			if (slice.provenance.deep_text != slice.slice_type.deep_borrow) {
				fail (path, "text slice element requires the complete table and payload backing-origin contract");
			}
			if (slice.slice.semantic_type != slice.slice_type || place.semantic_type != slice.slice_type.element_type || !(slice.index.semantic_type is IntegerType) || !slice.provenance.is_valid () || slice.provenance.origin == DataPointerOrigin.NULL) {
				fail (path, "slice element requires exact SliceType, integer index and non-null lexical provenance");
			}
			if (slice_bounds_views.lookup (slice.index) != slice.slice) {
				fail (path, "slice element requires a dominating bounds result for this exact captured view");
			}
			return;
		}
		var array = place as CfgArrayElementPlace;
		if (array != null) {
			verify_array_storage (array.storage, function, array != initializing_array_entry, path);
			verify_value (array.index, function, path + "/index");
			if (array.storage.semantic_type != array.array_type || place.semantic_type != array.array_type.element_type || !(array.index.semantic_type is IntegerType) || !array.provenance.is_valid () || array.provenance.origin != DataPointerOrigin.LOCAL || array.provenance.origin_ordinal != array.storage.ordinal) {
				fail (path, "array element requires exact type, integer index and storage provenance");
			}
			var constant = array.index as CfgIntegerValue;
			if (constant != null) {
				if (!constant.value.fits_nonnegative ((uint64) array.array_type.length - 1)) {
					fail (path, "constant array index outside bounds");
				}
			} else if (bounds_storage.lookup (array.index) != array.storage) {
				fail (path, "array element requires validated index for exact storage");
			}
			return;
		}
		var dereference = place as CfgDereferencePlace;
		if (dereference != null) {
			verify_value (dereference.pointer, function, path + "/pointer", null, false, null, true);
			if (!(place.semantic_type is StructType)) {
				verify_type (place.semantic_type, true, path);
			}
			var pointer = dereference.pointer.semantic_type as TypedPointerType;
			if (pointer == null || !pointer.pointee.is_typed_data_pointee () || pointer.pointee != place.semantic_type || !dereference.provenance.is_valid ()) {
				fail (path, "dereference place requires the exact directly dereferenceable pointee and lexical provenance");
			}
			return;
		}
		var indirect = place as CfgIndirectFieldPlace;
		if (indirect != null) {
			verify_field_visibility (indirect.field, function, path);
			var structure = indirect.field.containing_type;
			if (indirect.pointer.semantic_type is ClassType && object_validations.lookup (indirect.pointer as CfgEvaluatedValue) == null) {
				fail (path, "object field requires a captured null-validated reference");
			}
			if (indirect.pointer.semantic_type is ReceiverType && !(indirect.pointer is CfgReceiverValue) && !class_upcasts.contains (indirect.pointer as CfgEvaluatedValue)) {
				fail (path, "receiver field access requires this identity or its exact verified ancestor upcast");
			}
			verify_value (indirect.pointer, function, path + "/pointer", null, false, null, true);
			if (structure == null || structs.lookup (structure.semantic_type) != structure || indirect.field.ordinal < 0 || indirect.field.ordinal >= structure.fields.length || structure.fields[indirect.field.ordinal] != indirect.field) {
				fail (path, "indirect field must have exact program-owned struct/field identity");
			}
			if (((indirect.pointer.semantic_type is ReceiverType) ? ((ReceiverType) indirect.pointer.semantic_type).instance_type != structure.semantic_type : (indirect.pointer.semantic_type is ClassType) ? indirect.pointer.semantic_type != structure.semantic_type : (!indirect.pointer.semantic_type.is_struct_pointer () || ((TypedPointerType) indirect.pointer.semantic_type).pointee != structure.semantic_type)) || place.semantic_type != indirect.field.semantic_type) {
				fail (path, "indirect field pointer pointee and scalar type must match the exact field");
			}
			return;
		}
		var recursive = place as CfgFieldPlace;
		if (recursive != null) {
			var owner = recursive.field.containing_struct;
			if (owner == null || structs.lookup (recursive.aggregate.semantic_type) != owner || recursive.field.ordinal < 0 || recursive.field.ordinal >= owner.fields.length || owner.fields[recursive.field.ordinal] != recursive.field || place.semantic_type != recursive.field.semantic_type) {
				fail (path, "field projection requires exact StructType base, field owner and result type");
			}
			verify_place (recursive.aggregate, function, path + "/base");
			if (recursive.root_local () == null) {
				return;
			}
		}
		if (!(place is CfgLocalPlace) && !(place is CfgTemporaryPlace) && !(place is CfgFieldPlace)) {
			fail (path, "unsupported CFG place");
			return;
		}
		if (place_owners.lookup (place) != function) {
			fail (path, (place is CfgTemporaryPlace) ? "temporary place is not owned by the containing function" : "local place is not owned by the containing function");
		}
		if (!(place.semantic_type is StructType)) {
			verify_type (place.semantic_type, true, path);
		}
	}

	private void verify_terminator(CfgTerminator? terminator, CfgFunction function, string path) throws CfgError {
		if (terminator is CfgForeignSignalReturn) {
			var binding = ((CfgForeignSignalReturn) terminator).binding;
			var method = function as CfgMethod;
			var owner = method == null ? null : method.declaring_type as CfgClass;
			if (!binding.valid () || owner == null || owner.foreign_export == null || owner.foreign_export.identity () != binding.root.identity () || CfgForeignApi.target (owner, binding.member) != function || !CfgForeignApi.valid (owner, code_program) || function.blocks.length != 1 || function.entry.terminator != terminator) {
				fail (path, "native signal lost its exact shared receiver, signature, member or intrinsic body authority");
			}
			if (!CfgForeignApi.signal_prologue (function)) {
				fail (path, "native signal has an executable operation outside its copied parameter prologue");
			}
			return;
		}
		if (terminator is CfgForeignReturn) {
			var imported = (CfgForeignReturn) terminator;
			var types = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			if (function.return_type.is_struct_storage () && (function.struct_result == null || function.struct_result.mode != StructValueMode.COPY_VALUE)) {
				fail (path, "CImport POD requires an exact copied native result");
			}
			foreach (var p in function.parameters) {
				types.add (p.semantic_type);
				contracts.add (p.pointer_contract);
			}
			if (!ForeignImportTypes.signature (imported.binding, function.name, function.return_type, function.result_contract, function.owned_cleanup == null ? "" : function.owned_cleanup.external_symbol, function.throws_type, types, contracts, (type) => CfgForeignApi.record (code_program, type), function.struct_parameters, (type) => { var handle = handles.lookup (type); return handle == null ? null : handle.c_import; }) || !ForeignApiTypes.errors (imported.binding.member, function.throws_type, (name) => { foreach (var type in structs.get_keys ()) {
																																																																																																																																	 if (type is ClassType && type.nominal_name () == name) {
																																																																																																																																		 return (ClassType) type;
																																																																																																																																	 }
																																																																																																																																 }
				                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 return null; })) {
				fail (path, "CImport lost its exact nominal member/signature/ownership/throws authority");
			}
			types.remove_range (0, types.length);
			contracts.remove_range (0, contracts.length);
			var factory = imported.factory;
			foreach (var p in factory.parameters) {
				types.add (p.semantic_type);
				contracts.add (p.pointer_contract);
			}
			if (!functions.contains (factory) || !ForeignImportTypes.factory (imported.binding, factory.name, factory.return_type, function.throws_type, factory.result_contract == ResultOwnershipContract.OWNED_TRANSFER, factory.heap_result, factory.throws_type, types, contracts)) {
				fail (path, "CImport lost its exact owned heap exception factory");
			}
			uint prologue = 0, transfers = 0;
			foreach (var group in function.struct_parameters) {
				prologue += group.shape.leaves.length;
			}
			foreach (var parameter in function.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER) {
					continue;
				}
				prologue++;
				if (transfers >= imported.consumed.length || imported.consumed[transfers].incoming_parameter != parameter || !function.locals.find (imported.consumed[transfers]) || imported.consumed[transfers].cleanup == null) {
					fail (path, "CImport lost exact ordered owned-parameter consumption");
				}
				transfers++;
			}
			if (transfers != imported.consumed.length) {
				fail (path, "CImport consumed inventory differs from owned parameters");
			}
			if (function.blocks.length != 1 || function.entry.terminator != terminator || function.entry.instructions.length != prologue) {
				fail (path, "CImport adapter requires exact copied-parameter acquisitions followed by one typed return");
			}
			return;
		}

		if (terminator is CfgExceptionReturn && function is CfgConstructor && ConstructorContracts.admitted (((CfgConstructor) function).declaring_class.foreign_export, ((CfgConstructor) function).declaring_class.allocation_policy, ((CfgConstructor) function).member_ordinal, function.throws_type)) {
			if (current_block.instructions.length == 0 || !(current_block.instructions[current_block.instructions.length - 1] is CfgConstructorAbort)) {
				fail (path, "checked constructor exceptional exit lacks partial-field retirement");
			}
		}
		if (terminator is CfgNativeDeclaration) {
			if (!function.declaration_only ()) {
				fail (path, "native declaration terminator lost its exact imported signature");
			}
			return;
		}
		if (terminator is CfgExceptionUnreachable) {
			verify_value (((CfgExceptionUnreachable) terminator).exception, function, path);
			return;
		}
		if (terminator is CfgExceptionReturn) {
			if (function.throws_type == null || !(((CfgExceptionReturn) terminator).value.semantic_type is ClassType)) {
				fail (path, "exception propagation requires a checked throws declaration");
			}
			verify_value (((CfgExceptionReturn) terminator).value, function, path);
			return;
		}
		// Completion is write-once; every published block must be complete.
		if (function is CfgConstructor && terminator is CfgReturn) {
			fail (path, "constructor explicit return is unsupported");
		}
		if (field_state != null && terminator is CfgFunctionEnd) {
			if (((CfgConstructor) function).declaring_class.parent_class != null && !field_state.is_definite ((int) ((CfgConstructor) function).declaring_class.fields.length)) {
				fail (path, "constructor completion requires exact completed base initialization");
			}
			foreach (var field in ((CfgConstructor) function).declaring_class.fields) {
				if (!field_state.is_definite (field.ordinal)) {
					fail (path, "constructor field not initialized on successful completion: " + field.name);
				}
			}
		}

		if (terminator == null) {
			fail (path, "block has no terminator");
			return;
		}
		var successors = terminator.successors ();
		for (int i = 0; i < successors.length; i++) {
			if (block_owners.lookup (successors[i]) != function) {
				fail (path + "/successor #%d".printf (i), "successor block is not owned by the containing function");
			}
		}
		if (terminator is CfgEnumDispatch || terminator is CfgEnumInvalidTag) {
			return;
		}
		if (terminator is CfgEnumReturn) {
			if (((CfgEnumReturn) terminator).source.definition.semantic_type != function.return_type) {
				fail (path, "enum return nominal mismatch");
			}
			return;
		}
		var branch = terminator as CfgBranch;
		if (branch != null) {
			if (successors.length != 1 || successors[0] != branch.target) {
				fail (path, "branch successors must match its target");
			}
			return;
		}
		var request = terminator as CfgBufferAllocationBranch;
		if (request != null) {
			verify_value (request.allocation.count, function, path + "/count");
			if (successors.length != 2 || !(request.allocation.count is CfgEvaluatedValue || request.allocation.count is CfgCallResultValue)) {
				fail (path, "allocation branch requires exactly two edges and a once-evaluated count");
			}
			return;
		}
		if (terminator is CfgAllocationFailureTrap) {
			var receiver = ((CfgAllocationFailureTrap) terminator).failure.captured_receiver;
			if (receiver != null) {
				verify_value (receiver, function, path + "/captured-receiver", null, false, null, true);
			}
			return;
		}
		var conditional = terminator as CfgConditionalBranch;
		if (conditional != null) {
			if (successors.length != 2 || successors[0] != conditional.true_target || successors[1] != conditional.false_target) {
				fail (path, "conditional successors must match true and false targets");
			}
			verify_value (conditional.condition, function, path + "/condition");
			if (conditional.condition.semantic_type.kind != TypeKind.BOOL) {
				fail (path + "/condition", "conditional branch condition must have type 'bool'");
			}
			return;
		}
		if (!(terminator is CfgReturn) && !(terminator is CfgFunctionEnd)) {
			fail (path, "unsupported CFG terminator");
			return;
		}
		if (successors.length != 0) {
			fail (path, "return and function-end must have no successors");
		}
		if (terminator is CfgFunctionEnd) {
			// No value field by construction. Reachable non-void completion is
			// structurally valid; the flow checker diagnoses the source.
			return;
		}
		if (function.owned_cleanup != null) {
			var owned_return = terminator as CfgOwnershipReturn;
			var value = owned_return == null ? null : owned_return.value as CfgOwnedReturnValue;
			if (value == null || value.cleanup != function.owned_cleanup || value.semantic_type != function.return_type || used_returns.contains (value) || !available_evaluations.contains (value)) {
				fail (path, "owned return requires its unique same-block capture before lexical cleanups");
			}
			used_returns.insert (value, value);
			return;
		}
		if (terminator is CfgOwnershipReturn) {
			fail (path, "unmanaged function cannot return ownership");
		}
		if (terminator is CfgStructReturn) {
			var returned = (CfgStructReturn) terminator;
			verify_struct_shape (returned.shape, function.return_type, path);
			if (function.struct_result == null || returned.value != null || returned.leaves.length != returned.shape.leaves.length) {
				fail (path, "struct return requires its exact complete leaf result set");
			}
			if (returned.shape.mode != function.struct_result.mode || (returned.shape.mode == StructValueMode.BORROW_VALUE && (function.result_contract != ResultOwnershipContract.RECEIVER_BORROW || returned.record_move != null))) {
				fail (path, "record return cannot change the declared copy, move or bounded borrow mode");
			}
			if (returned.shape.mode == StructValueMode.MOVE_VALUE) {
				if (returned.record_move != null) {
					if (!current_block.instructions.find (returned.record_move) || returned.record_move.consumer != returned) {
						fail (path, "MOVE_VALUE return lost its exact prior ownership commit");
					}
				} else {
					int forwarded = 0;
					foreach (var group in consumed_struct_results.get_keys ()) {
						var consumed = consumed_struct_results.lookup (group);
						if (consumed.use_kind != StructResultUseKind.RETURN || group.shape != returned.shape || group.leaves.length != returned.leaves.length) {
							continue;
						}
						bool exact = true;
						for (int i = 0; i < group.leaves.length; i++) {
							exact &= group.leaves[i] == returned.leaves[i];
						}
						if (exact) {
							forwarded++;
						}
					}
					if (forwarded != 1) {
						fail (path, "MOVE_VALUE return requires an exact root transfer or complete owned result forwarding");
					}
				}
			}
			for (int i = 0; i < returned.leaves.length; i++) {
				verify_value (returned.leaves[i], function, path + "/leaf");
				if (returned.leaves[i].semantic_type != returned.shape.leaves[i].semantic_type) {
					fail (path, "struct return leaf type or order mismatch");
				}
			}
			return;
		}
		var returned = (CfgReturn) terminator;
		if (function.return_type.kind == TypeKind.VOID) {
			if (returned.value != null) {
				fail (path, "void function return must not carry a value");
			}
			return;
		}
		if (returned.value == null) {
			fail (path, "non-void function return must carry a value");
			return;
		}
		verify_value (returned.value, function, path + "/value");
		if (returned.value.semantic_type != function.return_type) {
			fail (path, "return value type does not match function return type");
		}
	}

	// Check instruction-result availability without adding CFG merge values
	// or coupling the standalone model to SSA's dominance/frontier analysis.
	private bool reaches(CfgFunction function, CfgBlock start, CfgBlock target, CfgBlock? excluded = null) {
		var pending = new GenericArray<CfgBlock> ();
		var visited = new HashTable<CfgBlock, CfgBlock> (direct_hash, direct_equal);
		if (start != excluded) {
			pending.add (start);
			visited.insert (start, start);
		}
		for (int i = 0; i < pending.length; i++) {
			if (pending[i] == target) {
				return true;
			}
			var successors = pending[i].terminator.successors ();
			for (int j = 0; j < successors.length; j++) {
				var next = successors[j];
				if (next != excluded && block_owners.lookup (next) == function && visited.insert (next, next)) {
					pending.add (next);
				}
			}
		}
		return false;
	}

	private bool available_on_entry(CfgValue value, CfgFunction function) {
		return block_available_on_entry (definition_blocks.lookup (value), function);
	}

	private bool block_available_on_entry(CfgBlock? definition, CfgFunction function) {
		if (definition == null || definition == current_block || block_owners.lookup (definition) != function || !reaches (function, definition, current_block)) {
			return false;
		}
		// Disconnected source tails also have entry roots. Closed, rootless
		// components cannot establish a first instruction definition.
		var incoming = new bool[function.blocks.length];
		for (int i = 0; i < function.blocks.length; i++) {
			var successors = function.blocks[i].terminator.successors ();
			for (int j = 0; j < successors.length; j++) {
				if (block_owners.lookup (successors[j]) == function) {
					incoming[successors[j].ordinal] = true;
				}
			}
		}
		bool rooted = false;
		for (int i = 0; i < function.blocks.length; i++) {
			var root = function.blocks[i];
			if (root == function.entry || !incoming[i]) {
				if (reaches (function, root, current_block, definition)) {
					return false;
				}
				rooted = rooted || reaches (function, root, definition);
			}
		}
		return rooted;
	}

	private bool invalidates_property_loan(CfgInstruction instruction, SemanticType owner) {
		if (instruction is CfgRecordFieldCommit) {
			return OwnedChildComposition.may_invalidate (((CfgRecordFieldCommit) instruction).destination.field.containing_type.semantic_type, owner, slot_edges);
		}
		if (instruction is CfgRecordFieldDrop) {
			return OwnedChildComposition.may_invalidate (((CfgRecordFieldDrop) instruction).source.field.containing_type.semantic_type, owner, slot_edges);
		}
		var transfer = instruction as CfgOwnershipTransferInstruction;
		if (transfer != null && OwnedChildComposition.may_invalidate (transfer.source.semantic_type, owner, slot_edges)) {
			return true;
		}
		var capture = instruction as CfgResourceCapture;
		if (capture != null && capture.source != null && OwnedChildComposition.may_invalidate (capture.source.semantic_type, owner, slot_edges)) {
			return true;
		}

		var call = instruction as CfgCallInstruction;
		if (call != null && call.target is CfgPropertyGetter && (((CfgPropertyGetter) call.target).property_member.is_owned_lazy || call.target.struct_result != null && call.target.struct_result.mode == StructValueMode.BORROW_VALUE)) {
			return false;
		}
		if (call != null) {
			var receiver = call.receiver == null ? null : call.receiver.semantic_type as ReceiverType;
			if (receiver != null && OwnedChildComposition.may_invalidate (receiver.instance_type, owner, slot_edges)) {
				return true;
			}
			foreach (var argument in call.arguments) {
				if (OwnedChildComposition.may_invalidate (argument.semantic_type, owner, slot_edges)) {
					return true;
				}
			}
		}
		var evaluation = instruction as CfgEvaluateInstruction;
		var indirect = evaluation == null ? null : evaluation.value as CfgFunctionValueCall;
		var closure = evaluation == null ? null : evaluation.value as CfgClosureCall;
		if (closure != null) {
			if (OwnedChildComposition.may_invalidate (((ClosureHandleType) closure.callee.semantic_type).environment_type, owner, slot_edges)) {
				return true;
			}
			foreach (var argument in closure.arguments) {
				if (OwnedChildComposition.may_invalidate (argument.semantic_type, owner, slot_edges)) {
					return true;
				}
			}
		}
		if (indirect != null) {
			foreach (var argument in indirect.arguments) {
				if (OwnedChildComposition.may_invalidate (argument.semantic_type, owner, slot_edges)) {
					return true;
				}
			}
		}
		var store = instruction as CfgStore;
		var place = store == null ? null : store.target as CfgIndirectFieldPlace;
		return (place != null && OwnedChildComposition.may_invalidate (place.field.containing_type.semantic_type, owner, slot_edges)) || instruction is CfgCleanupInstruction || instruction is CfgOwnershipReleaseInstruction;
	}

	private void verify_receiver_loan_interval(CfgValue value, CfgInstruction origin, SemanticType owner, bool cross_blocks,
		CfgFunction function, string path, string kind) throws CfgError {
		var start = definition_blocks.lookup (value);
		if (start == null || (start != current_block && !cross_blocks)) {
			fail (path, kind + " loan lacks exact guarded definition block");
		}
		bool[] reaches = new bool[function.blocks.length];
		reaches[current_block.ordinal] = true;
		bool changed = false;
		do {
			changed = false;
			foreach (var candidate in function.blocks) {
				foreach (var next in candidate.terminator.successors ()) {
					if (reaches[next.ordinal] && !reaches[candidate.ordinal]) {
						reaches[candidate.ordinal] = true;
						changed = true;
					}
				}
			}
		} while (changed);
		if (!reaches[start.ordinal]) {
			fail (path, kind + " definition cannot reach its consumer");
		}
		var pending = new GenericArray<CfgBlock> ();
		bool[] seen = new bool[function.blocks.length];
		pending.add (start);
		seen[start.ordinal] = true;
		bool found = false;
		for (int b = 0; b < pending.length; b++) {
			var candidate = pending[b];
			bool started = candidate != start;
			foreach (var instruction in candidate.instructions) {
				if (instruction == origin) {
					started = true;
					continue;
				}
				if (!started) {
					continue;
				}
				if (invalidates_property_loan (instruction, owner)) {
					fail (path, kind + " loan overlaps receiver replacement, destruction or an aliasing call");
				}
				if (candidate == current_block && instruction == current_instruction) {
					found = true;
					break;
				}
			}
			if (!started) {
				fail (path, kind + " definition lost exact original instruction");
			}
			if (candidate == current_block) {
				if (current_instruction == null) {
					found = true;
				}
				continue;
			}
			foreach (var next in candidate.terminator.successors ()) {
				if (reaches[next.ordinal] && !seen[next.ordinal]) {
					seen[next.ordinal] = true;
					pending.add (next);
				}
			}
		}
		if (!found) {
			fail (path, kind + " loan lost its direct consumer");
		}
	}

	private void verify_property_loan(CfgValue value, CfgFunction function, string path, CfgParameter? parameter, bool comparison, CfgCleanupContract? acquisition, bool receiver_use, int depth = 0, bool buffer_view_use = false) throws CfgError {
		var direct_view = value as CfgRecordBufferView;
		var capture = value as CfgEvaluatedValue;
		if (direct_view == null && capture != null) {
			direct_view = evaluated_sources.lookup (capture) as CfgRecordBufferView;
		}
		if (direct_view != null) {
			value = direct_view.source;
		}

		var captured_field_load = capture == null ? null : evaluated_sources.lookup (capture) as CfgLoadValue;
		var captured_field = captured_field_load == null ? null : captured_field_load.source as CfgIndirectFieldPlace;
		if (parameter != null && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && captured_field != null && captured_field.field.owned_cleanup != null) {
			var start = definition_blocks.lookup (capture);
			CfgInstruction? origin = null;
			if (start != null) {
				foreach (var instruction in start.instructions) {
					var evaluation = instruction as CfgEvaluateInstruction;
					if (evaluation != null && evaluation.result == capture) {
						origin = instruction;
					}
				}
			}
			if (origin == null || acquisition != null) {
				fail (path, "borrowed field argument lost its exact non-acquiring capture");
			}
			verify_receiver_loan_interval (capture, origin, captured_field.field.containing_type.semantic_type, false, function, path, "borrowed field argument");
			verify_property_loan (captured_field.pointer, function, path, null, false, null, true, depth + 1);
			return;
		}
		// Validation establishes nonnullness, never a new ownership origin.
		// Follow its reference again at the actual receiver use so argument
		// evaluation cannot invalidate a loan after the validation instruction.
		var validated = value as CfgEvaluatedValue;
		while (validated != null && object_validations.contains (validated)) {
			if (++depth > 128) {
				fail (path, "cyclic or excessive projected receiver chain");
			}
			value = object_validations.lookup (validated).reference;
			var load = value as CfgLoadValue;
			var field = load == null ? null : load.source as CfgIndirectFieldPlace;
			if (field != null && field.field.owned_cleanup != null && field.field.owned_cleanup.is_heap_object) {
				if (!receiver_use || acquisition != null) {
					fail (path, "owned field receiver loan cannot escape its temporary receiver use");
				}
				CfgInstruction? origin = null;
				var start = definition_blocks.lookup (validated);
				if (start != null) {
					foreach (var instruction in start.instructions) {
						var evaluation = instruction as CfgEvaluateInstruction;
						if (evaluation != null && evaluation.result == validated) {
							origin = instruction;
						}
					}
				}
				if (origin == null) {
					fail (path, "owned field receiver loan lost its exact captured definition");
				}
				verify_receiver_loan_interval (validated, origin, field.field.containing_type.semantic_type, false, function, path, "owned field receiver");
				verify_property_loan (field.pointer, function, path, null, false, null, true, depth);
			}
			validated = value as CfgEvaluatedValue;
		}
		var result = value as CfgCallResultValue;
		var producer = result == null ? null : results.lookup (result) as CfgCallInstruction;
		var evaluated = value as CfgEvaluatedValue;
		var success = evaluated == null ? null : property_successes.lookup (evaluated);
		if (success != null) {
			producer = success.call;
		}
		if (producer == null || producer.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW) {
			return;
		}
		// Copied leaves are snapshots taken by the getter. Only owner leaves
		// retain the receiver loan after the complete group is observed.
		if (producer.struct_result != null && producer.struct_result.shape.mode == StructValueMode.BORROW_VALUE && !(value.semantic_type is ClassType || value.semantic_type is HandleType || value.semantic_type is SliceType)) {
			return;
		}
		if (depth != 0 && (!receiver_use || acquisition != null)) {
			fail (path, "borrowed validated receiver cannot escape its temporary receiver use");
		}
		if (acquisition != null || (!receiver_use && !comparison && !(buffer_view_use && value.semantic_type is SliceType) && (parameter == null || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || parameter.semantic_type != value.semantic_type))) {
			fail (path, "borrowed property result cannot escape its direct borrowed argument, temporary receiver or null test");
		}
		var property = ((CfgPropertyGetter) producer.target).property_member;
		var owner = property.declaring_type.semantic_type;
		CfgInstruction origin = success == null ? (CfgInstruction) producer : success;
		verify_receiver_loan_interval (value, origin, owner, property.is_owned_lazy, function, path, "borrowed property");
	}

	private void verify_indirect_record_moves(GenericArray<CfgValue> arguments, GenericArray<StructBoundaryGroup> groups, GenericArray<CfgStructBoundaryMove> moves, CfgFunction function, string path) throws CfgError {
		foreach (var group in groups) {
			verify_record_argument_loan (arguments, group, current_instruction, function, path);
		}
		int required = 0;
		foreach (var group in groups) {
			if (group.shape.mode != StructValueMode.MOVE_VALUE) {
				continue;
			}
			required++;
			int matches = 0;
			foreach (var move in moves) {
				if (move.consumer != current_instruction || move.shape != group.shape || move.leaves.length != group.shape.leaves.length || !current_block.instructions.find (move)) {
					continue;
				}
				bool exact = true;
				for (int leaf = 0; leaf < move.leaves.length; leaf++) {
					exact &= move.leaves[leaf] == arguments[group.first_leaf + leaf];
				}
				if (exact) {
					matches++;
				}
			}
			if (matches != 1) {
				fail (path, "indirect MOVE_VALUE argument requires one exact complete field commit");
			}
		}
		if (required != moves.length) {
			fail (path, "indirect record transfer inventory differs from its signature groups");
		}
	}

	private void verify_indirect_arguments(GenericArray<CfgValue> arguments, GenericArray<CfgParameter> channels, CallableSignature signature, CfgFunction function, string path) throws CfgError {
		GenericArray<SemanticType> physical_types;
		GenericArray<StructBoundaryGroup> groups;
		if (signature is FunctionValueType) {
			physical_types = ((FunctionValueType) signature).physical_parameters ();
			groups = ((FunctionValueType) signature).record_parameters;
		} else {
			physical_types = ((ClosureHandleType) signature).physical_parameters ();
			groups = ((ClosureHandleType) signature).record_parameters;
		}
		var contracts = signature.physical_contracts ();
		for (int i = 0; i < arguments.length; i++) {
			bool record_borrow = CallableRecordGroups.borrowed_record_leaf (groups, i);
			CfgParameter? channel = null;
			if (contracts[i] != PointerParameterContract.UNMANAGED && !record_borrow) {
				for (int p = 0; p < channels.length; p++) {
					int first = p;
					foreach (var group in groups) {
						if (group.source_ordinal < p) {
							first += (int) group.shape.leaves.length - 1;
						}
					}
					if (first == i && channels[p].pointer_contract == contracts[i] && channels[p].semantic_type == arguments[i].semantic_type) {
						channel = channels[p];
					}
				}
				if (channel == null || !contract_parameters.contains (channel)) {
					fail (path, "indirect argument lost its exact declared ownership channel");
				}
			}
			if (contracts[i] == PointerParameterContract.OWNED_TRANSFER) {
				var transfer = arguments[i] as CfgPendingOwnedArgument;
				if (transfer == null || transfer.parameter != channel || transfer.consumer != current_instruction || pending_commit == null || pending_commit.call != current_instruction || committed_transfers.lookup (transfer) != pending_commit || used_transfers.contains (transfer)) {
					fail (path, "indirect owned argument requires one exact committed capture and channel");
				}
				used_transfers.insert (transfer, transfer);
			} else {
				verify_value (arguments[i], function, path + "/argument", channel, record_borrow, null, false, record_borrow);
			}
			if (arguments[i].semantic_type != physical_types[i]) {
				fail (path, "function invocation argument signature mismatch");
			}
		}
		if (pending_commit != null) {
			foreach (var transfer in pending_commit.transfers) {
				if (!used_transfers.contains (transfer)) {
					fail (path, "indirect commit contains a transfer absent from its invocation");
				}
			}
			pending_commit = null;
		}
	}

	private void verify_value(CfgValue value, CfgFunction function, string path, CfgParameter? borrowed_parameter = null, bool pointer_comparison = false, CfgCleanupContract? acquisition = null, bool receiver_use = false, bool buffer_view_use = false) throws CfgError {
		if (value is CfgScopedAllocator) {
			var scoped = (CfgScopedAllocator) value;
			var type = value.semantic_type as HandleType;
			var backing = scoped.backing.semantic_type as SliceType;
			var evaluation = current_instruction as CfgEvaluateInstruction;
			int position = -1;
			for (int i = 0; i < current_block.instructions.length; i++) {
				if (current_block.instructions[i] == evaluation) {
					position = i;
					break;
				}
			}
			var initialization = position < 0 || position + 1 >= current_block.instructions.length ? null : current_block.instructions[position + 1] as CfgInitialize;
			var owner = initialization == null ? null : initialization.acquisition;
			if (type == null || !type.is_scoped_allocator () || type.context_cleanup != "astra_context17_destroy" || !scoped.loan.valid () || evaluation == null || evaluation.value != scoped || initialization == null || initialization.value != evaluation.result || owner == null || initialization.target != owner || owner.ordinal != scoped.loan.context_ordinal || owner.cleanup != scoped.cleanup || !matches_cleanup (type, scoped.cleanup) || scoped.cleanup.external_symbol != type.context_cleanup || !cleanups.contains (scoped.cleanup) || owner.text_extent == null || owner.text_extent.ordinal != scoped.loan.region_ordinal || scoped.backing.text_extent == null || !scoped.backing.text_extent.outlives (owner.text_extent) || scoped.backing.ordinal != scoped.loan.backing_ordinal || backing == null || backing.element_type.kind != TypeKind.U8 || scoped.backing.cleanup == null || !scoped.backing.cleanup.is_buffer || function.async_body != null) {
				fail (path, "scoped context requires immediate exact lexical acquisition and complete owned byte backing");
			}
			verify_place (scoped.backing, function, path + "/backing");
			verify_value (scoped.kind, function, path + "/kind");
			verify_value (scoped.slots, function, path + "/slots");
			if (scoped.kind.semantic_type.kind != TypeKind.INT || scoped.slots.semantic_type.kind != TypeKind.INT) {
				fail (path, "scoped context configuration requires int channels");
			}
			return;
		}
		if (value.semantic_type.kind == TypeKind.VOID && (value is CfgFunctionValueCall || value is CfgClosureCall)) {
			var effect = current_instruction as CfgEvaluateInstruction;
			var checked_effect = current_instruction as CfgCheckedClosureInvoke;
			if ((effect == null || effect.value != value) && (checked_effect == null || checked_effect.call != value)) {
				fail (path, "void callable can occur only as its exact effect instruction");
			}
		}
		if (value.semantic_type.is_struct_storage () && (value is CfgFunctionValueCall || value is CfgClosureCall)) {
			var record = current_instruction as CfgStructInvoke;
			var checked_call = current_instruction as CfgCheckedClosureInvoke;
			if (record == null ? checked_call == null || checked_call.call != value : record.checked_call != null || record.call != value) {
				fail (path, "indirect record result requires its exact bounded invocation definition");
			}
		}
		if (value is CfgRecordParameterBufferView) {
			var view = (CfgRecordParameterBufferView) value;
			var root = view.field.root_local ();
			var captured = evaluated_sources.lookup (view.source) as CfgLoadValue;
			if (!(value.semantic_type is SliceType) || root == null || root.struct_parameter != view.parameter || !function.struct_parameters.find (view.parameter) || view.parameter.shape.mode != StructValueMode.BORROW_VALUE || captured == null || captured.source != view.field || view.source.semantic_type != value.semantic_type || acquisition != null || (borrowed_parameter == null ? !buffer_view_use : borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != value.semantic_type)) {
				fail (path, "record parameter buffer view requires its exact incoming leaf and bounded nonowning use");
			}
			verify_place (view.field, function, path);
			verify_value (view.source, function, path, null, false, null, false, true);
			return;
		}
		if (value is CfgRecordBufferView) {
			var view = (CfgRecordBufferView) value;
			var consumed = consumed_struct_results.lookup (view.group);
			if (view.group.shape.mode != StructValueMode.BORROW_VALUE || !(view.semantic_type is SliceType) || struct_result_leaves.lookup (view.source) != view.group || consumed == null || consumed.use_kind != StructResultUseKind.OBSERVE || acquisition != null || (borrowed_parameter == null ? !buffer_view_use : borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != value.semantic_type)) {
				fail (path, "record buffer view requires one exact complete observed pair and a bounded nonowning use");
			}
			verify_value (view.source, function, path + "/pair", borrowed_parameter, false, null, false, true);
			return;
		}
		if (value is CfgLazyObserve) {
			var observe = (CfgLazyObserve) value;
			var getter = function as CfgPropertyGetter;
			if (getter == null || getter.property_member != observe.property_member || !observe.property_member.is_owned_lazy || acquisition != null || observe.semantic_type != getter.return_type) {
				fail (path, "lazy observation lost exact receiver/property provenance");
			}
			return;
		}
		if (value is CfgRetainedOperation) {
			var operation = (CfgRetainedOperation) value;
			if (!RetainedContracts.valid_action (operation.action) || !RetainedContracts.accepts (operation.action, operation.callee.semantic_type) || value.semantic_type.kind != TypeKind.INT || operation.arguments.length != RetainedContracts.arity (operation.action) || acquisition != null) {
				fail (path, "retained callback requires exact finite action and native carrier signature");
			}
			if (!thread_capture_type (((ClosureHandleType) operation.callee.semantic_type).environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), false, true)) {
				fail (path, "retained callback cannot capture thread-bound state");
			}
			var load = operation.callee as CfgLoadValue;
			var parameter = operation.callee as CfgParameterValue;
			if (load == null ? parameter == null || parameter.parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE : !(load.source is CfgLocalPlace) || ((CfgLocalPlace) load.source).cleanup == null) {
				fail (path, "retained callback requires a live owned local or exact borrowed carrier");
			}
			verify_value (operation.callee, function, path + "/retained", null, true);
			foreach (var argument in operation.arguments) {
				verify_value (argument, function, path + "/argument");
				if (argument.semantic_type != value.semantic_type) {
					fail (path, "retained callback int argument mismatch");
				}
			}
			return;
		}
		if (value is CfgClosureBind) {
			var closure = (CfgClosureBind) value;
			var type = value.semantic_type as ClosureHandleType;
			var target = closure.target;
			if (type == null || !type.supported () || (type.actor ? closure.actor_binding == null || !closure.actor_binding.valid () || !thread_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true) || !thread_capture_type (type.actor_message, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true) : closure.actor_binding != null || type.environment_type.concurrency_policy_identity == 16) || (type.threaded && !thread_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) || !cleanups.contains (closure.cleanup) || !matches_cleanup (type, closure.cleanup) || closure.environment.semantic_type != type.environment_type || target == null || target.kind != CallableKind.FUNCTION || !functions.contains (target) || target.implicit_receiver != null || target.async_body != null || target.throws_type != type.throws_type || target.result_contract != type.result_contract || target.return_type != type.result_type || (type.result_contract == ResultOwnershipContract.OWNED_TRANSFER && type.result_type is ClassType && !target.heap_result) || target.parameters.length != type.physical_parameters ().length + 1 || target.parameters[0].semantic_type != type.environment_type || target.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				fail (path, "closure binding lost exact environment move, native signature or destruction authority");
			}
			if (!type.actor) {
				try {
					type.verify_records (type.record_parameters, struct_fields);
					type.verify_records (target.struct_parameters, struct_fields, 1, 1);
				} catch (StructLeafError error) {
					fail (path, error.message);
				}
			}
			for (int p = 0; p < type.physical_parameters ().length; p++) {
				if (target.parameters[p + 1].semantic_type != type.physical_parameters ()[p] || ((type.actor && type.physical_parameters ()[p] is ClassType) ? target.parameters[p + 1].pointer_contract != PointerParameterContract.OWNED_TRANSFER || !target.parameters[p + 1].heap_object : target.parameters[p + 1].pointer_contract != type.physical_contracts ()[p] || type.physical_contracts ()[p] == PointerParameterContract.OWNED_TRANSFER && type.physical_parameters ()[p] is ClassType && !target.parameters[p + 1].heap_object)) {
					fail (path, "closure code scalar signature mismatch");
				}
			}
			var captured = closure.environment as CfgEvaluatedValue;
			if (captured == null || resource_consumers.lookup (captured) != current_instruction) {
				fail (path, "closure environment requires exact immediately consumed sole heap-owner capture");
			}
			verify_value (closure.environment, function, path + "/environment", null, true);
			return;
		}
		if (value is CfgClosureCall) {
			var call = (CfgClosureCall) value;
			var type = call.callee.semantic_type as ClosureHandleType;
			verify_invocation_result (call, type, path);
			try {
				if (type != null) {
					type.verify_records (type.record_parameters, struct_fields);
					type.verify_records (call.struct_arguments, struct_fields);
				}
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			if (type != null && type.throws_type != null && (!(current_instruction is CfgCheckedClosureInvoke) || ((CfgCheckedClosureInvoke) current_instruction).call != call)) {
				fail (path, "checked closure call cannot erase its explicit exception effect");
			}
			if (type == null || type.threaded || type.actor || value.semantic_type != type.result_type || call.arguments.length != type.physical_parameters ().length || acquisition != null) {
				fail (path, "closure invocation requires exact borrowed carrier and scalar signature");
			}
			var load = call.callee as CfgLoadValue;
			var parameter = call.callee as CfgParameterValue;
			if (load == null ? parameter == null || parameter.parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE : !(load.source is CfgLocalPlace) || ((CfgLocalPlace) load.source).cleanup == null) {
				fail (path, "closure invocation requires an immediate live owned local or borrowed parameter");
			}
			verify_value (call.callee, function, path + "/closure", null, true);
			if (call.channel_parameters.length != (type.has_owner_channels () ? type.parameter_types.length : 0)) {
				fail (path, "closure invocation lost its exact channel declarations");
			}
			verify_indirect_record_moves (call.arguments, call.struct_arguments, call.record_moves, function, path);
			verify_indirect_arguments (call.arguments, call.channel_parameters, type, function, path);
			return;
		}
		if (value is CfgSharedOperation) {
			var operation = (CfgSharedOperation) value;
			if (!SharedContracts.matches (operation.action, operation.operand.semantic_type, value.semantic_type)) {
				fail (path, "shared operation lost exact capability/payload identity");
			}
			if (operation.action == SharedAction.BORROW) {
				var load = operation.operand as CfgLoadValue;
				if (load != null && !(load.source is CfgLocalPlace)) {
					fail (path, "shared field projection requires a named strong clone owner");
				}
				if (borrowed_parameter == null || borrowed_parameter != operation.borrower || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || borrowed_parameter.semantic_type != value.semantic_type) {
					fail (path, "shared payload projection requires exact call-scoped borrow");
				}
			} else if (operation.cleanup == null || !cleanups.contains (operation.cleanup) || !matches_cleanup (value.semantic_type, operation.cleanup)) {
				fail (path, "shared producer lost exact release authority");
			}
			verify_value (operation.operand, function, path + "/operand", null, true);
			return;
		}
		if (value is CfgFunctionValueCall) {
			var call = (CfgFunctionValueCall) value;
			var signature = call.callee.semantic_type as FunctionValueType;
			verify_invocation_result (call, signature, path);
			if (signature == null || value.semantic_type != signature.result_type || call.arguments.length != signature.physical_parameters ().length) {
				fail (path, "function invocation requires exact code signature and arity");
			}
			try {
				signature.verify_records (signature.record_parameters, struct_fields);
				signature.verify_records (call.struct_arguments, struct_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			if (call.channel_parameters.length != (signature.has_owner_channels () ? signature.parameter_types.length : 0)) {
				fail (path, "function invocation lost call-owned channel authority");
			}
			verify_value (call.callee, function, path + "/callee", null, signature is CallbackType);
			verify_indirect_record_moves (call.arguments, call.struct_arguments, call.record_moves, function, path);
			verify_indirect_arguments (call.arguments, call.channel_parameters, signature, function, path);
			return;
		}
		if (value is CfgCallbackParameterView) {
			var view = (CfgCallbackParameterView) value;
			var callback = value.semantic_type as CallbackType;
			if (borrowed_parameter == null || view.parameter != borrowed_parameter || borrowed_parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || value.semantic_type != borrowed_parameter.semantic_type || !function.parameters.find (view.source) || view.source.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || callback == null || !callback.matches_closure (view.source.semantic_type)) {
				fail (path, "captured callback parameter lost exact borrowed source and boundary");
			}
			return;
		}
		if (value is CfgFunctionAddress) {
			var address = (CfgFunctionAddress) value;
			var signature = value.semantic_type as FunctionValueType;
			var target = address.target;
			if (signature == null || target == null || !functions.contains (target) || target.implicit_receiver != null || target.async_body != null || target.throws_type != null || target.result_contract != signature.result_contract || target.return_type != signature.result_type || (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER && signature.result_type is ClassType && !target.heap_result) || target.parameters.length != signature.physical_parameters ().length) {
				fail (path, "function address requires exact program-owned nonthrowing native signature");
			}
			try {
				signature.verify_records (signature.record_parameters, struct_fields);
				signature.verify_records (target.struct_parameters, struct_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			for (int i = 0; i < target.parameters.length; i++) {
				if (target.parameters[i].semantic_type != signature.physical_parameters ()[i] || target.parameters[i].pointer_contract != signature.physical_contracts ()[i] || signature.physical_contracts ()[i] == PointerParameterContract.OWNED_TRANSFER && signature.physical_parameters ()[i] is ClassType && !target.parameters[i].heap_object) {
					fail (path, "function address parameter identity mismatch");
				}
			}
			return;
		}
		verify_property_loan (value, function, path, borrowed_parameter, pointer_comparison, acquisition, receiver_use, 0, buffer_view_use);
		if (value is CfgSlotsLoan) {
			var loan = (CfgSlotsLoan) value;
			if (borrowed_parameter == null || borrowed_parameter != loan.borrower || receiver_use || acquisition != null || (!available_evaluations.contains (loan) && !available_on_entry (loan, function))) {
				fail (path, "owner-slot loan requires its exact dominating inspection call and cannot escape");
			}
			return;
		}
		if (value is CfgSlotsValue) {
			var v = (CfgSlotsValue) value;
			verify_slots_place (v.store, function, true, path);
			if (v.operand != null) {
				verify_value (v.operand, function, path);
			}
			if (v.action == OwnerSlotsAction.TAKE) {
				if (!(current_instruction is CfgInitialize) || ((CfgInitialize) current_instruction).value != v || ((CfgInitialize) current_instruction).acquisition == null || acquisition == null || acquisition != v.store.field.slots_cleanup || !matches_cleanup (v.semantic_type, acquisition) || v.semantic_type != ((OwnerSlotsType) v.store.semantic_type).element || v.operand == null || v.operand.semantic_type.kind != TypeKind.INT) {
					fail (path, "owner-slot take lost exact single heap acquisition/index");
				}
				return;
			}
			if (acquisition != null || v.action == OwnerSlotsAction.BORROW || ((v.action == OwnerSlotsAction.RESERVE) != (v.operand != null)) || (v.operand != null && v.operand.semantic_type.kind != TypeKind.INT) || v.semantic_type.kind != (v.action == OwnerSlotsAction.RESERVE ? TypeKind.BOOL : TypeKind.INT)) {
				fail (path, "owner-slot action lost exact count/capacity operand group");
			}
			return;
		}

		if (value is CfgClassUpcast) {
			var cast = (CfgClassUpcast) value;
			var incoming = cast.reference.semantic_type as ReceiverType;
			var outgoing = value.semantic_type as ReceiverType;
			if (structs.lookup (cast.source_class.semantic_type) != cast.source_class || structs.lookup (cast.target_class.semantic_type) != cast.target_class || cast.source_class == cast.target_class || !((ClassType) cast.source_class.semantic_type).derives_from ((ClassType) cast.target_class.semantic_type) || (incoming == null ? cast.reference.semantic_type != cast.source_class.semantic_type : incoming.instance_type != cast.source_class.semantic_type) || (outgoing == null ? value.semantic_type != cast.target_class.semantic_type : outgoing.instance_type != cast.target_class.semantic_type) || (incoming == null) != (outgoing == null) || (incoming != null && (incoming.mode != outgoing.mode || !receiver_use))) {
				fail (path, "upcast requires exact descendant/ancestor identities and the same borrowed receiver mode");
			}
			var borrow = cast.reference as CfgOwnedBorrowValue;
			verify_value (cast.reference, function, path + "/source", borrow == null ? borrowed_parameter : borrow.parameter, true, null, incoming != null);
			return;
		}

		if (value is CfgEnumTag || value is CfgEnumPayloadValue) {
			CfgEnumSlot source;
			if (value is CfgEnumTag) {
				source = ((CfgEnumTag) value).source;
			} else {
				source = ((CfgEnumPayloadValue) value).source;
			} if (enum_definitions.lookup (source.definition.semantic_type) != source.definition || source.ordinal < 0 || source.ordinal >= function.enum_slots.length || function.enum_slots[source.ordinal] != source) {
				fail (path, "enum projection requires its registered nominal definition and function-owned carrier");
			}
			verify_type (value.semantic_type, true, path);
			return;
		}
		if (value.semantic_type is EnumType) {
			fail (path, "enum is a bounded carrier, not an ordinary value");
		}
		var result_receiver = value as CfgResultStorageReceiverValue;
		if (result_receiver != null) {
			if (!receiver_use || result_receiver.storage != function.result_storage || result_receiver.storage == null || ((ReceiverType) value.semantic_type).mode != ReceiverMode.INITIALIZING || ((ReceiverType) value.semantic_type).instance_type != function.return_type) {
				fail (path, "result receiver requires exact function result storage");
			}
			return;
		}
		if (value.semantic_type is ReceiverType && !receiver_use) {
			fail (path, "receiver is only valid as an implicit method input or receiver field base");
		}
		var storage_receiver = value as CfgStorageReceiverValue;
		if (storage_receiver != null) {
			if (object_owners.lookup (storage_receiver.storage) != function || ((ReceiverType) value.semantic_type).instance_type != storage_receiver.storage.semantic_type) {
				fail (path, "storage receiver requires exact caller-owned ObjectStorage");
			}
			var context = storage_receiver.allocation_context;
			var policy = storage_receiver.storage.object_class.allocation_policy;
			bool contextual = ((ReceiverType) value.semantic_type).mode == ReceiverMode.INITIALIZING && policy != null && policy.kind == AllocationKind.CONTEXT;
			if (contextual != (context != null)) {
				fail (path, "context initializing receiver lost its instance authority");
			}
			if (context != null) {
				var context_type = context.semantic_type as HandleType;
				var load = context as CfgLoadValue;
				if (!(context is CfgParameterValue) && (load == null || !(load.source is CfgLocalPlace))) {
					fail (path, "context receiver requires its exact named local or parameter origin");
				}
				if (!storage_receiver.storage.heap_allocated || context_type == null || !handles.contains (context_type) || handles.lookup (context_type).context_mode != policy.context_mode || context_type.context_mode != policy.context_mode) {
					fail (path, "context receiver lifetime/thread contract or storage responsibility mismatch");
				}
				if (policy.context_mode == "scoped-affine") {
					if (function.async_body != null) {
						fail (path, "scoped construction requires a synchronous backing lifetime");
					}
					if (!scoped_constructions.find (function)) {
						scoped_constructions.add (function);
					}
				}
				verify_value (context, function, path + "/context", null, true);
			}
			verify_type (value.semantic_type, true, path);
			return;
		}
		var validation = value as CfgObjectValidateValue;
		if (validation != null) {
			var contract = value.semantic_type as ReceiverType;
			if (!(validation.reference.semantic_type is ClassType) || (contract == null ? value.semantic_type != validation.reference.semantic_type : contract.instance_type != validation.reference.semantic_type)) {
				fail (path, "object validation requires exact ClassType and receiver contract");
			}
			verify_value (validation.reference, function, path + "/reference", null, false, null, true);
			verify_type (value.semantic_type, true, path);
			return;
		}
		var object_reference = value as CfgObjectReferenceValue;
		if (object_reference != null) {
			var storage = object_reference.storage;
			if (storage.result_candidate || object_owners.lookup (storage) != function || object_constructions.contains (storage)) {
				fail (path, "object reference requires one exact lexical construction");
			}
			if (storage.object_class.constructor != null) {
				var site = constructor_sites.lookup (storage);
				if (site == null || (site == current_block ? !available_constructors.contains (storage) : !block_available_on_entry (site, function))) {
					fail (path, "successful constructor call must precede and dominate reference publication");
				}
			}
			foreach (var field in storage.object_class.fields) {
				if (storage.object_class.constructor != null) {
					continue;
				}
				var place = object_fields.lookup (storage).lookup (field);
				if (place == null || (object_initializations.lookup (place) == current_block ? !initialized.contains (place) : !block_available_on_entry (object_initializations.lookup (place), function))) {
					fail (path, "all object fields must be initialized before the object reference is published");
				}
			}
			object_constructions.insert (storage, storage);
			return;
		}
		var self = value as CfgReceiverValue;
		if (self != null) {
			if (receiver_owners.lookup (self.receiver) != function) {
				fail (path, "this must reference the exact containing method receiver");
			}
			verify_type (value.semantic_type, true, path);
			return;
		}

		if (value is CfgPendingOwnedArgument || value is CfgOwnedReturnValue) {
			fail (path, "ownership transfer value requires its exact native call or return consumer");
		}
		var borrow = value as CfgOwnedBorrowValue;
		if (borrow != null) {
			if (borrow.semantic_type is CallbackType && pending_commit != null) {
				foreach (var transfer in pending_commit.transfers) {
					if (transfer.source == borrow.source) {
						fail (path, "captured callback view overlaps committed Closure transfer");
					}
				}
			}
			if ((borrowed_parameter == null && (!(borrow is CfgBufferBorrowValue) || !buffer_view_use)) || borrow.parameter != borrowed_parameter || (!available_borrows.contains (borrow) && !available_on_entry (borrow, function)) || used_borrows.contains (borrow)) {
				fail (path, "borrow value requires its exact borrowed argument and preceding unique event");
			}
			used_borrows.insert (borrow, borrow);
			return;
		}
		var struct_leaf = value as CfgCallResultValue;
		if (struct_leaf != null && struct_result_leaves.contains (struct_leaf) && !consumed_struct_results.contains (struct_result_leaves.lookup (struct_leaf))) {
			fail (path, "struct result leaves require complete bounded consumption before use");
		}
		var address = value as CfgAddressOfValue;
		if (address != null && address.receiver_place != null) {
			var receiver = value.semantic_type as ReceiverType;
			if (receiver == null || receiver.mode != ReceiverMode.LIVE || address.target != null || address.provenance != null || receiver.instance_type != address.receiver_place.semantic_type || !(address.receiver_place.semantic_type is StructType)) {
				fail (path, "projected receiver requires an exact live struct storage contract");
			}
			verify_place (address.receiver_place, function, path + "/receiver-place");
			return;
		}
		if (address != null) {
			verify_type (value.semantic_type, true, path);
			if (place_owners.lookup (address.target) != function || !address.target.address_taken || !address.target.semantic_type.is_typed_data_pointee () || ((value.semantic_type is ReceiverType) ? ((ReceiverType) value.semantic_type).instance_type != address.target.semantic_type : (!value.semantic_type.is_typed_pointer () || ((TypedPointerType) value.semantic_type).pointee != address.target.semantic_type))) {
				fail (path, "address-of must match exact addressable local storage and pointer type");
			}
			return;
		}
		verify_type (value.semantic_type, true, path);
		var slice = value as CfgSliceFromArrayValue;
		if (slice != null) {
			verify_array_storage (slice.storage, function, true, path);
			var type = value.semantic_type as SliceType;
			if (type == null || slice.storage.semantic_type != slice.array_type || type.element_type != slice.array_type.element_type || !slice.provenance.is_valid () || slice.provenance.origin != DataPointerOrigin.LOCAL || slice.provenance.origin_ordinal != slice.storage.ordinal) {
				fail (path, "slice construction requires exact array element, result type and storage provenance");
			}
			if ((slice.start == null) != (slice.count == null)) {
				fail (path, "slice range requires paired start and count");
			}
			if (slice.start != null && slice.count != null) {
				verify_value (slice.start, function, path + "/operand");
				verify_value (slice.count, function, path + "/operand");
				if (!(slice.start.semantic_type is IntegerType) || !(slice.count.semantic_type is IntegerType)) {
					fail (path, "slice start and count require scalar IntegerTypes");
				}
				if (!(slice.start is CfgEvaluatedValue || slice.start is CfgCallResultValue) || !(slice.count is CfgEvaluatedValue || slice.count is CfgCallResultValue)) {
					fail (path, "slice operands must be captured before range validation");
				}
			}
			return;
		}
		if (value is CfgUtf8FactoryValue) {
			if (utf8_values.lookup ((CfgUtf8FactoryValue) value) != function) {
				fail (path, "unassociated UTF-8 guarded copy boundary");
			}
			return;
		}
		if (value is CfgTextValue) {
			var payload = ((CfgTextValue) value).payload;
			if (!(value.semantic_type is StringType) || !payload.valid () || !text_literals.contains (payload)) {
				fail (path, "text literal requires member immutable UTF-8 payload and exact byte length");
			}
			return;
		}
		if (value is CfgTextLengthValue) {
			var receiver = ((CfgTextLengthValue) value).receiver;
			verify_value (receiver, function, path + "/text");
			if (!(receiver.semantic_type is StringType) || !(value.semantic_type is IntegerType) || value.semantic_type.kind != TypeKind.INT) {
				fail (path, "text byte length requires StringType input and int result");
			}
			return;
		}
		var length = value as CfgSliceLengthValue;
		if (length != null) {
			verify_value (length.slice, function, path + "/operand", null, false, null, false, true);
			if (!(length.slice.semantic_type is SliceType) || !(value.semantic_type is IntegerType) || value.semantic_type.kind != TypeKind.INT) {
				fail (path, "slice length requires SliceType input and exact int result");
			}
			return;
		}
		if (value is CfgExceptionMatch) {
			var match = (CfgExceptionMatch) value;
			verify_value (match.exception, function, path);
			if (!(match.exception.semantic_type is ClassType) || !match.match_type.derives_from ((ClassType) match.exception.semantic_type) || value.semantic_type.kind != TypeKind.BOOL) {
				fail (path, "subtype catch match requires exact rooted exception class and bool result");
			}
			return;
		}
		if (value is CfgCatchBorrow) {
			var caught = (CfgCatchBorrow) value;
			verify_value (caught.exception, function, path);
			if (!(caught.exception.semantic_type is ClassType) || !((ClassType) value.semantic_type).derives_from ((ClassType) caught.exception.semantic_type) || !guarded_exception_catch (caught, function)) {
				fail (path, "catch borrow requires an exact rooted exception subtype");
			}
			return;
		}
		var evaluated = value as CfgEvaluatedValue;
		if (evaluated != null) {
			var producer = owned_results.lookup (evaluated);
			if (producer != null) {
				if (acquisition != producer || consumed_results.contains (evaluated) || !available_evaluations.contains (evaluated)) {
					fail (path, "native owned producer requires exactly one immediate consumer with exact destruction authority");
				}
				consumed_results.insert (evaluated, evaluated);
			}
			verify_buffer_field_interval (evaluated, function, path);
			var receiver_address = evaluated_sources.lookup (evaluated) as CfgAddressOfValue;
			if (receiver_address != null && receiver_address.receiver_place != null) {
				verify_place (receiver_address.receiver_place, function, path + "/live-receiver");
			}
			if (resource_consumers.contains (evaluated) && resource_consumers.lookup (evaluated) != current_instruction) {
				fail (path, "captured Resource ownership has exactly one field store consumer");
			}
			if (!available_evaluations.contains (evaluated) && !available_on_entry (evaluated, function)) {
				fail (path, "evaluated value must be defined earlier in the same block or on every incoming path");
			}
			return;
		}
		var result = value as CfgCallResultValue;
		if (result != null) {
			var frame = results.lookup (result) as CfgTaskCreate;
			if (frame != null && frame.checked_admission && !guarded_exception_success (frame, function)) {
				fail (path, "checked task publication requires its exact guarded admission success");
			}
			var producer = owned_results.lookup (result);
			if (producer != null) {
				if (acquisition != producer || consumed_results.contains (result) || !available_results.contains (result)) {
					fail (path, "owned producer result requires exactly one immediate consumer with its exact cleanup contract");
				}
				consumed_results.insert (result, result);
			}
			if (!available_results.contains (result) && !available_on_entry (result, function)) {
				fail (path, "call result must be defined earlier in the same block or on every incoming path");
			}
			return;
		}
		var load = value as CfgLoadValue;
		if (load != null && load.source is CfgObjectFieldPlace) {
			fail (path, "object reads require a reference field Place");
		}
		if (load != null) {
			if (!VolatileAccessContract.valid (load.volatile_access, load.volatile_enabled, load.source.semantic_type) || (load.volatile_enabled && !(load.source is CfgDereferencePlace || load.source is CfgArrayElementPlace || load.source is CfgSliceElementPlace))) {
				fail (path, "volatile load requires its exact typed memory provenance and flag");
			}
			verify_place (load.source, function, path + "/source");
			string record_part;
			var record_root = CfgConstructorInitialization.record_root (load.source, out record_part);
			if (field_state != null && record_root != null && record_root.pointer is CfgReceiverValue && !field_state.is_definite (record_root.field.ordinal)) {
				fail (path, "constructor record field read before complete initialization");
			}
			if (field_state != null && load.source is CfgIndirectFieldPlace) {
				var field = (CfgIndirectFieldPlace) load.source;
				if (field.pointer is CfgReceiverValue && !field_state.is_definite (field.field.ordinal)) {
					fail (path, "constructor field read before definite initialization: " + field.field.name);
				}
			}
			if (load.semantic_type != load.source.semantic_type) {
				fail (path, "load result type does not match source place type");
			}
			return;
		}
		if (value is CfgNullPointerValue) {
			if (!value.semantic_type.is_nullable_pointer_value ()) {
				fail (path, "null pointer must have type 'void*'");
			}
			return;
		}
		var boolean = value as CfgBooleanValue;
		if (boolean != null) {
			if (value.semantic_type.kind != TypeKind.BOOL) {
				fail (path, "boolean literal must have type 'bool'");
			}
			if (boolean.literal != BooleanLiteral.TRUE && boolean.literal != BooleanLiteral.FALSE) {
				fail (path, "unsupported boolean literal");
			}
			return;
		}
		var dot = value as CfgVectorDotValue;
		if (dot != null) {
			if (dot.accumulator != null) {
				verify_value (dot.accumulator, function, path + "/accumulator");
			}
			verify_value (dot.first, function, path + "/first");
			verify_value (dot.second, function, path + "/second");
			string? error = dot.dot_kind.type_error (dot.source_type, dot.first.semantic_type, dot.second.semantic_type, dot.destination_type, dot.accumulator == null ? null : dot.accumulator.semantic_type);
			if (error != null) {
				fail (path, error);
			}
			return;
		}
		var dsp = value as CfgDspValue;
		if (dsp != null) {
			verify_value (dsp.first, function, path + "/first");
			if (dsp.second != null) {
				verify_value (dsp.second, function, path + "/second");
			}
			if (dsp.source_type != dsp.first.semantic_type) {
				fail (path, "DSP source type must exactly match its first operand");
			}
			string? error = dsp.primitive_kind.type_error (dsp.source_type, dsp.second == null ? null : dsp.second.semantic_type, dsp.destination_type, dsp.destination_element);
			if (error != null) {
				fail (path, error);
			}
			return;
		}
		var shift = value as CfgIntegerShiftValue;
		if (shift != null) {
			verify_value (shift.operand, function, path + "/value");
			verify_value (shift.count, function, path + "/count");
			if (!shift.shift_kind.accepts (shift.operand.semantic_type, shift.count.semantic_type, value.semantic_type)) {
				fail (path, "shift requires exact integer scalar/vector result and scalar integer count; invalid counts trap");
			}
			return;
		}
		var numeric_conversion = value as CfgNumericConversionValue;
		if (numeric_conversion != null) {
			verify_value (numeric_conversion.operand, function, path + "/operand");
			if (numeric_conversion.source_type != numeric_conversion.operand.semantic_type || !numeric_conversion.conversion_kind.accepts (numeric_conversion.source_type, numeric_conversion.destination_type, numeric_conversion.policy)) {
				fail (path, "numeric conversion requires exact scalar types, signedness, kind and rounding/trap policy");
			}
			if (numeric_conversion.conversion_kind.traps ()) {
				var proof = numeric_guards.lookup (numeric_conversion.operand);
				if (proof == null || proof.destination_type != numeric_conversion.destination_type || proof.policy != numeric_conversion.policy) {
					fail (path, "float-to-integer conversion requires a dominating guard for its exact destination range");
				}
			}
			return;
		}
		var floating_conversion = value as CfgFloatConversionValue;
		if (floating_conversion != null) {
			verify_value (floating_conversion.operand, function, path + "/operand");
			if (floating_conversion.source_type != floating_conversion.operand.semantic_type || !floating_conversion.conversion_kind.accepts (floating_conversion.source_type, floating_conversion.destination_type)) {
				fail (path, "float conversion requires exact source type and f32/f64 widen or narrow kind");
			}
			return;
		}
		var conversion = value as CfgIntegerConversionValue;
		if (conversion != null) {
			verify_value (conversion.operand, function, path + "/operand");
			if (conversion.source_type != conversion.operand.semantic_type || !IntegerConversion.accepts (conversion.source_type, conversion.destination_type)) {
				fail (path, "integer conversion requires exact source type and integer scalar types or supported integer vectors with equal lane counts");
			}
			return;
		}
		var splat = value as CfgVectorSplatValue;
		if (splat != null) {
			verify_value (splat.operand, function, path + "/operand");
			var type = value.semantic_type as VectorType;
			if (type == null || type.element_type != splat.operand.semantic_type || type.lane_count != splat.lane_count || !VectorType.supports (splat.operand.semantic_type, splat.lane_count)) {
				fail (path, "vector splat requires exact scalar element, supported shape and matching lane count");
				return;
			}
			return;
		}
		var extract = value as CfgVectorExtractValue;
		if (extract != null) {
			verify_value (extract.vector, function, path + "/vector");
			var type = extract.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector extract requires a vector source");
				return;
			}
			if (value.semantic_type != type.element_type) {
				fail (path, "vector extract result requires exact element type");
				return;
			}
			if (!extract.index.in_range (type)) {
				fail (path, "vector extract index is out of range");
				return;
			}
			return;
		}
		var insert = value as CfgVectorInsertValue;
		if (insert != null) {
			verify_value (insert.vector, function, path + "/vector");
			verify_value (insert.replacement, function, path + "/replacement");
			var type = insert.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector insert requires a vector source");
				return;
			}
			if (value.semantic_type != type) {
				fail (path, "vector insert result requires exact source VectorType");
				return;
			}
			if (insert.replacement.semantic_type != type.element_type) {
				fail (path, "vector insert replacement requires exact element type");
				return;
			}
			if (!insert.index.in_range (type)) {
				fail (path, "vector insert index is out of range");
				return;
			}
			return;
		}
		var shuffle = value as CfgVectorShuffleValue;
		if (shuffle != null) {
			verify_value (shuffle.vector, function, path + "/vector");
			var type = shuffle.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector shuffle requires a vector source");
				return;
			}
			if (value.semantic_type != type) {
				fail (path, "vector shuffle result requires exact source VectorType");
				return;
			}
			if (shuffle.selectors.length != type.lane_count) {
				fail (path, "vector shuffle requires exactly one selector per lane");
				return;
			}
			for (int i = 0; i < shuffle.selectors.length; i++) {
				if (!shuffle.selectors.at (i).in_range (type)) {
					fail (path, "vector shuffle selector is out of range");
				}
			}
			return;
		}
		if (value is CfgVectorMemoryValue) {
			var memory = (CfgVectorMemoryValue) value;
			verify_value (memory.view, function, path + "/view");
			verify_value (memory.offset, function, path + "/offset");
			if (memory.stored != null) {
				verify_value (memory.stored, function, path + "/stored");
			}
			var error = memory.contract.type_error (memory.view.semantic_type, memory.offset.semantic_type, memory.stored == null ? null : memory.stored.semantic_type, value.semantic_type);
			if (error != null) {
				fail (path, error);
			}
			return;
		}
		var select = value as CfgVectorSelectValue;
		if (select != null) {
			verify_value (select.mask, function, path + "/mask");
			verify_value (select.true_value, function, path + "/true_value");
			verify_value (select.false_value, function, path + "/false_value");
			var type = select.true_value.semantic_type as VectorType;
			var mask_type = select.mask.semantic_type as VectorType;
			if (type == null || select.false_value.semantic_type != type || value.semantic_type != type) {
				fail (path, "vector select requires exact matching data and result VectorTypes");
				return;
			}
			if (mask_type == null || !mask_type.is_mask || mask_type.lane_count != type.lane_count) {
				fail (path, "vector select requires bool<N> mask with matching data lane count");
				return;
			}
			return;
		}
		var vector = value as CfgVectorConstructValue;
		if (vector != null) {
			var type = value.semantic_type as VectorType;
			if (type == null || vector.lanes.length != type.lane_count) {
				fail (path, "vector construct requires exact vector type and lane count");
				return;
			}
			foreach (var lane in vector.lanes) {
				verify_value (lane, function, path + "/lane");
				if (lane.semantic_type != type.element_type) {
					fail (path, "vector construct lane requires exact element type");
				}
			}
			return;
		}
		var reduction = value as CfgVectorReductionValue;
		if (reduction != null) {
			verify_value (reduction.operand, function, path + "/operand");
			if (!reduction.operator_kind.accepts (reduction.operand.semantic_type, value.semantic_type)) {
				fail (path, "vector reduction requires bool<N> operand and scalar bool result");
			}
			return;
		}
		if (value is CfgFloatValue) {
			if (!(value.semantic_type is FloatingType) || ((FloatingType) value.semantic_type).format != ((CfgFloatValue) value).value.format) {
				fail (path, "floating constant requires exact canonical type and matching binary format");
			}
			return;
		}
		// Numeric validity is guaranteed by immutable AstraIntegerValue construction.
		if (value is CfgIntegerValue) {
			if (!(value.semantic_type is IntegerType)) {
				fail (path, "integer literal must have type 'int'");
			}
			if (((CfgIntegerValue) value).value.integer_type != value.semantic_type) {
				fail (path, "integer value must retain its exact semantic type identity");
			}
			return;
		}
		// Slices and object references permit local copies; signature/storage guards enforce noescape.
		var reference = value as CfgParameterValue;
		if (reference != null) {
			if (reference.parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				fail (path, "owned incoming parameter may only initialize its slot");
			}
			if (reference.parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(reference.parameter.semantic_type is StringType) && !(reference.parameter.semantic_type is SliceType) && !(reference.parameter.semantic_type is ClassType) && borrowed_parameter == null && !pointer_comparison && !(receiver_use && (CPlainRecordTypes.pointer (reference.parameter.semantic_type, struct_fields) || ForeignApiTypes.scalar_pointee (reference.parameter.semantic_type) != null))) {
				fail (path, "borrowed parameter cannot escape; only equality or direct borrowed forwarding is permitted");
			}
			if (owners.lookup (reference.parameter) != function) {
				fail (path, "parameter reference is not owned by the containing function");
			}
			if (value.semantic_type != reference.parameter.semantic_type) {
				fail (path, "parameter reference type does not match its declaration");
			}
			return;
		}
		var prefix = value as CfgPrefixValue;
		if (prefix != null) {
			switch (prefix.operator_kind) {
			case PrefixOperator.POSITIVE:
			case PrefixOperator.NEGATIVE:
			case PrefixOperator.BIT_NOT:
			case PrefixOperator.NOT:
				break;
				default:
				fail (path, "unsupported semantic prefix operator");
				break;
			}
			verify_value (prefix.operand, function, path + "/operand");
			if (!prefix.operator_kind.accepts (prefix.operand.semantic_type, value.semantic_type)) {
				fail (path, "invalid operand or result type for semantic prefix operator");
			}
			return;
		}
		var binary = value as CfgBinaryValue;
		if (binary != null) {
			if (!binary.operator_kind.is_bitwise () && !binary.operator_kind.is_arithmetic () && !binary.operator_kind.is_relational () && !binary.operator_kind.is_equality ()) {
				fail (path, "unsupported semantic binary operator");
			}
			verify_value (binary.left, function, path + "/left", null, binary.operator_kind.is_equality ());
			verify_value (binary.right, function, path + "/right", null, binary.operator_kind.is_equality ());
			if (!binary.operator_kind.accepts (binary.left.semantic_type, binary.right.semantic_type, value.semantic_type)) {
				fail (path, "invalid operands or result type for semantic binary operator");
			}
			return;
		}
		fail (path, "unsupported CFG value");
	}

}
}
