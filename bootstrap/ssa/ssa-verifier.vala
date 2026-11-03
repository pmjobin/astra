// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;

namespace Astra.Ssa {
internal class SsaDeclaredClassAuthority : Object {
	private static void require(bool valid) throws SsaError {
		if (!valid) {
			throw new SsaError.INVALID_SSA ("declared generic Class lost substituted type/field/member/lifetime authority");
		}
	}

	private static bool exact_heap_class_argument(SsaProgram program, SemanticType type) {
		foreach (var owner in program.classes) {
			if (owner.semantic_type == type) {
				return owner.generic_instance == null && !owner.polymorphic && owner.parent_class == null && !((ClassType) type).is_interface;
			}
		}
		return false;
	}

	private static void callable(SsaProgram program, SsaFunction function, GenericMemberPattern member, ExactClassGenericInstance key, CopyabilityFields field_graph, TypeArgumentVector? method_arguments = null) throws SsaError {
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

	internal static void verify(SsaProgram program, SsaClass owner, ExactClassGenericInstance key) throws SsaError {
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
			require (owned_field == (field.owned_cleanup != null || field.record_owner != null || field.semantic_type is OwnerSlotsType));
		}
		int expected_methods = 0;
		for (int m = 0; m < structure.member_count; m++) {
			var member = structure.member (m);
			if (member.type_parameter_count != 0) {
				continue;
			}
			SsaFunction? function = null;
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

private class DefinitionSite : Object {
	public SsaFunction function;
	public SsaBlock? block;
	public int position;

	public DefinitionSite (SsaFunction function, SsaBlock? block, int position) {
		this.function = function;
		this.block = block;
		this.position = position;
	}

}

// This verifier depends only on SSA nodes and shared semantic authorities.
// It checks dominance by path exclusion, independently of CFG's iterative
// dominator implementation used for construction.
public class SsaVerifier : Object {
	private SsaCallerResultOrigins caller_result_origins;
	private void verify_native_declaration(SsaFunction function, string path) throws SsaError {
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
		var buffer_ordinals = new GenericArray<int> ();
		var buffer_types = new GenericArray<SemanticType> ();
		foreach (var group in function.buffer_parameters) {
			buffer_ordinals.add (group.source_ordinal);
			buffer_types.add (group.cleanup.buffer_type);
		}
		if (!declaration.matches_buffers (buffer_ordinals, buffer_types)) {
			fail (path, "native declaration differs from its original owned buffer contract");
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
		if (function is SsaConstructor) {
			member = "init";
		} else if (function is SsaDestructor) {
			member = "deinit";
		} else if (function is SsaPropertyGetter) {
			member = "get:" + ((SsaPropertyGetter) function).property_member.name;
		} else if (function is SsaPropertySetter) {
			member = "set:" + ((SsaPropertySetter) function).property_member.name;
		}
		var method = function as SsaMethod;
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
			var payload = structs.lookup (shared.payload_type) as SsaClass;
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
		var object_class = owner as SsaClass;
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
				var derived = instance as SsaClass;
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

	private void verify_exact_class(SsaClass owner, SsaProgram program) throws SsaError {
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
			SsaDeclaredClassAuthority.verify (program, owner, key);
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
			SsaFunction? function = operation == Astra.Source.ExactClassOperation.INITIALIZE ? (SsaFunction) owner.constructor : null;
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
				if (function.entry.instructions.length != 1) {
					fail ("generic Class", "query operation recipe mismatch");
				}
				var query = function.entry.instructions[0] as SsaSlotsValueInstruction;
				var returned = function.entry.terminator as SsaReturn;
				if (query == null || query.store.field != owner.fields[0] || query.store.pointer != function.implicit_receiver || returned == null || returned.value != query.result || query.action != (reserve ? OwnerSlotsAction.RESERVE : operation == Astra.Source.ExactClassOperation.COUNT ? OwnerSlotsAction.LENGTH : OwnerSlotsAction.CAPACITY) || (reserve ? query.operand != function.parameters[0] : query.operand != null)) {
					fail ("generic Class", "query lost exact field/receiver/parameter/result operation");
				}
			} else {
				int count = 0;
				foreach (var instruction in function.entry.instructions) {
					var take = instruction as SsaSlotsValueInstruction;
					if (operation == Astra.Source.ExactClassOperation.TAKE && take != null && take.action == OwnerSlotsAction.TAKE) {
						if (++count != 1 || take.store.field != owner.fields[0] || take.store.pointer != function.implicit_receiver || take.operand != function.parameters[0]) {
							fail ("generic Class", "take lost exact specialized receiver/index");
						}
					}
					var effect = instruction as SsaSlotsEffect;
					if (effect != null) {
						var expected = operation == Astra.Source.ExactClassOperation.INITIALIZE ? SsaSlotsAction.INITIALIZE : operation == Astra.Source.ExactClassOperation.REPLACE ? SsaSlotsAction.REPLACE : SsaSlotsAction.APPEND;
						if (++count != 1 || effect.action != expected || effect.store.field != owner.fields[0] || effect.store.pointer != function.implicit_receiver || (operation == Astra.Source.ExactClassOperation.REPLACE && effect.index != function.parameters[0])) {
							fail ("generic Class", "effect lost exact specialized operation/field/receiver");
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

	private HashTable<SsaUtf8FactoryInstruction, SsaFunction> utf8_instructions;
	private void verify_text_exits(SsaFunction function) throws SsaError {
		foreach (var block in function.blocks) {
			foreach (var authority in block.text_exits) {
				var actual = new GenericArray<Object> ();
				foreach (var instruction in block.instructions) {
					var end = instruction as SsaTextLoanEnd;
					if (end != null && end.exit_authority == authority) {
						if (actual.find (end.loan)) {
							fail ("text loan exit authority", "duplicate end of the exact exited extent");
						}
						actual.add (end.loan);
					}
				}
				if (!authority.matches (actual)) {
					fail ("text loan exit authority", "missing end or end of a surviving outer extent");
				}
			}
			foreach (var instruction in block.instructions) {
				var end = instruction as SsaTextLoanEnd;
				if (end != null && !block.text_exits.find (end.exit_authority)) {
					fail ("text loan exit authority", "unassociated or premature loan exit");
				}
			}
		}
	}

	private SsaValue owned_call_value(SsaCallInstruction call) {
		return call.owned_success == null ? call.result : call.owned_success.result;
	}

	private SsaValue transfer_root(SsaValue value) {
		var upcast = class_upcasts.lookup (value);
		if (upcast != null) {
			return transfer_root (upcast.reference);
		}
		var definition = value as SsaDefinition;
		var site = definition == null ? null : definitions.lookup (definition);
		var restore = site == null || site.block == null || site.position < 0 ? null : site.block.instructions[site.position] as SsaFallibleInputRestore;
		if (restore != null) {
			return transfer_root (restore.argument.value);
		}
		var frame_restore = site == null || site.block == null || site.position < 0 ? null : site.block.instructions[site.position] as SsaFrameInputRestore;
		return frame_restore == null ? value : transfer_root (frame_restore.argument.value);
	}

	private void verify_class_hierarchy(SsaProgram program) throws SsaError {
		var classes = new HashTable<SsaClass, bool> (direct_hash, direct_equal);
		foreach (var owner in program.classes) {
			classes.insert (owner, true);
		}
		SsaClass? nominated = null;
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
					if (!SsaForeignApi.valid (owner, program)) {
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
			var seen = new HashTable<SsaClass, bool> (direct_hash, direct_equal);
			int depth = 0;
			for (SsaClass? current = owner; current != null; current = current.parent_class) {
				if (!classes.contains (current) || seen.contains (current) || ++depth > 256) {
					fail ("class parent", "requires a bounded acyclic exact program-owned chain");
				}
				seen.insert (current, true);
			}
		}
		var complete = new HashTable<SsaClass, bool> (direct_hash, direct_equal);
		while (complete.size () != classes.size ()) {
			foreach (var owner in program.classes) {
				if (complete.contains (owner) || (owner.parent_class != null && !complete.contains (owner.parent_class))) {
					continue;
				}
				var expected = new GenericArray<SsaFunction> ();
				if (owner.parent_class != null) {
					foreach (var entry in owner.parent_class.virtual_entries) {
						expected.add (entry);
					}
				}
				var members = new GenericArray<SsaFunction> ();
				foreach (var member in owner.methods) {
					members.add (member);
				}
				foreach (var property in owner.properties) {
					members.add (property.getter);
				}
				foreach (var member in members) {
					var getter = member as SsaPropertyGetter;
					string name = getter == null ? member.name : getter.property_member.name;
					SsaFunction? prior = null;
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
						if (prior == null || prior.dispatch_kind == ClassDispatchKind.DIRECT || (getter == null) != (prior is SsaMethod) || prior.return_type != member.return_type || prior.result_contract != member.result_contract || member.parameters.length != prior.parameters.length || member.virtual_slot != prior.virtual_slot) {
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
						var requirement = entry as SsaMethod;
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
			SsaProperty? message = null;
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
			if (!bound || (function is SsaLifecycle && (!(function is SsaConstructor) || !ConstructorContracts.admitted (((SsaConstructor) function).declaring_class.foreign_export, ((SsaConstructor) function).declaring_class.allocation_policy, ((SsaConstructor) function).member_ordinal, function.throws_type) && (((SsaConstructor) function).declaring_class.concurrency_policy == null || !((SsaConstructor) function).declaring_class.concurrency_policy.singleton))) || (function is SsaPropertyAccessor && (!(function is SsaPropertyGetter) || !(((SsaPropertyAccessor) function).property_member.declaring_type is SsaClass) || ((SsaPropertyAccessor) function).property_member.setter != null || function.dispatch_kind != ClassDispatchKind.DIRECT || (!((SsaPropertyAccessor) function).property_member.is_owned_lazy && !PropertyValueTypes.supports_cache (function.return_type))))) {
				fail ("throws declaration", "requires an exact program-owned nominated exception subtype and native callable");
			}
			foreach (var exported in program.c_exports) {
				if (exported.target == function) {
					fail ("throws declaration", "private exception channel cannot cross a C export");
				}
			}
		}
	}

	private void verify_interface_readonly(SsaMethod method) throws SsaError {
		if (method.native_declaration != null) {
			verify_native_declaration (method, "native interface implementation");
			return;
		}
		foreach (var block in method.blocks) {
			foreach (var instruction in block.instructions) {
				if (!(instruction is SsaLoadInstruction || instruction is SsaBufferReadInstruction || instruction is SsaBufferBorrowInstruction ||
				      instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction ||
				      instruction is SsaNumericGuard || instruction is SsaSliceBoundsCheck || instruction is SsaClassUpcast)) {
					fail ("interface read-only implementation", "requires copied scalar arithmetic and receiver field reads without effects (%s)".printf (instruction.get_type ().name ()));
				}
			}
		}
	}

	private void verify_borrowed_getter(SsaPropertyAccessor accessor) throws SsaError {
		if (accessor.native_declaration != null) {
			verify_native_declaration (accessor, "borrowed native getter");
			if (!accessor.declaration_only ()) {
				fail ("borrowed native getter", "requires its sealed declaration block");
			}
			return;
		}
		if (accessor.blocks.length != 1 || accessor.result_contract != ResultOwnershipContract.RECEIVER_BORROW || accessor.dispatch_kind != ClassDispatchKind.DIRECT) {
			fail ("borrowed getter", "requires one pure receiver projection block");
		}
		if (accessor.struct_result != null) {
			var block = accessor.blocks[0];
			var returned = block.terminator as SsaStructReturn;
			var validation = block.instructions.length == 0 ? null : block.instructions[0] as SsaValidatePlaceInstruction;
			var root = validation == null ? null : validation.place as SsaIndirectFieldPlace;
			var shape = accessor.struct_result;
			if (shape.mode != StructValueMode.BORROW_VALUE || returned == null || returned.record_move != null || returned.shape != shape || returned.leaves.length != shape.leaves.length || root == null || root.pointer != accessor.receiver || root.field.containing_type != accessor.property_member.declaring_type || root.semantic_type != accessor.return_type || root.field.record_owner == null || structs.lookup (root.semantic_type) != root.field.record_owner || root.field.owned_cleanup != null) {
				fail ("borrowed record getter", "requires one complete exact receiver-owned record observation without ownership acquisition");
			}
			int rank = 1;
			for (int i = 0; i < shape.leaves.length; i++) {
				if (rank >= block.instructions.length) {
					fail ("borrowed record getter", "requires every complete ordered storage read");
				}
				var leaf = shape.leaves[i];
				var component = leaf as StructBufferLeafPath;
				SsaMemoryPlace? place;
				if (component != null) {
					var read = block.instructions[rank++] as SsaBufferReadInstruction;
					if (component.component != 0 || i + 1 >= shape.leaves.length || read == null || read.place.record_projection == null || read.pair.shape != component.buffer_shape || read.pair.base_value != returned.leaves[i] || read.pair.length_value != returned.leaves[i + 1]) {
						fail ("borrowed record getter", "requires one complete exact ordered buffer field pair");
					}
					place = read.place.record_projection;
					leaf = component.storage_path ();
					i++;
				} else {
					var load = block.instructions[rank++] as SsaLoadInstruction;
					if (load == null || load.result != returned.leaves[i]) {
						fail ("borrowed record getter", "requires every ordered receiver-field leaf exactly once");
					}
					place = load.source;
				}
				for (int d = leaf.depth - 1; d >= 0; d--) {
					var field = place as SsaFieldPlace;
					if (field == null || field.field.ordinal != leaf.field_ordinal (d) || structs.lookup (field.aggregate.semantic_type) != field.field.containing_type) {
						fail ("borrowed record getter", "requires each exact declared field path in order");
					}
					place = field.aggregate;
				}
				var backing = place as SsaIndirectFieldPlace;
				if (backing == null || backing.field != root.field || backing.pointer != root.pointer) {
					fail ("borrowed record getter", "requires every ordered receiver-field leaf exactly once");
				}
			}
			if (rank != block.instructions.length) {
				fail ("borrowed record getter", "cannot add effects or acquire owner storage");
			}
			return;
		}
		var block = accessor.blocks[0];
		var returned = block.terminator as SsaReturn;
		var load = block.instructions.length == 1 ? block.instructions[0] as SsaLoadInstruction : null;
		var place = load == null ? null : load.source as SsaIndirectFieldPlace;
		if (returned == null || load == null || returned.value != load.result || place == null || place.pointer != accessor.receiver || place.field.containing_type != accessor.property_member.declaring_type || !(place.semantic_type is ClassType || place.semantic_type is HandleType) || place.semantic_type != accessor.return_type) {
			fail ("borrowed getter", "requires one exact owned receiver-field projection without effects or result ownership");
		}
	}

	private void verify_text_getter(SsaPropertyAccessor accessor) throws SsaError {
		if (accessor.native_declaration != null) {
			verify_native_declaration (accessor, "native text getter");
			return;
		}
		if (accessor.blocks.length != 1) {
			fail ("text getter", "requires one pure receiver snapshot or literal return block");
		}
		var block = accessor.blocks[0];
		var returned = block.terminator as SsaReturn;
		var value = returned == null ? null : returned.value;
		if (block.instructions.length == 0 && value is SsaTextConstant) {
			return;
		}
		var load = block.instructions.length == 1 || block.instructions.length == 2 ? block.instructions[block.instructions.length - 1] as SsaLoadInstruction : null;
		var place = load == null ? null : load.source as SsaIndirectFieldPlace;
		var cast = block.instructions.length == 2 ? block.instructions[0] as SsaClassUpcast : null;
		bool backing = place != null && (cast == null ? block.instructions.length == 1 && place.pointer == accessor.receiver && place.field.containing_type == accessor.property_member.declaring_type : place.pointer == cast.result && cast.reference == accessor.receiver && cast.source_class == accessor.property_member.declaring_type && cast.target_class == place.field.containing_type);
		if (place == null || load.result != value || !place.field.text_snapshot || !backing) {
			fail ("text getter", "requires exact readonly receiver snapshot return without effects");
		}
	}

	private HashTable<EnumType, EnumDefinition> enum_definitions = new HashTable<EnumType, EnumDefinition> (direct_hash, direct_equal);
	private SemanticType? string_type;
	private HashTable<Astra.Text.TextBytes, bool> text_literals = new HashTable<Astra.Text.TextBytes, bool> (direct_hash, direct_equal);
	private Astra.Text.TextOrigins text_origins = new Astra.Text.TextOrigins ();
	private HashTable<SsaValue, bool> text_views = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
	private GenericArray<SsaValue> text_returns = new GenericArray<SsaValue> ();
	private Object text_backing_owner(SsaValue value) {
		var definition = value as SsaDefinition;
		var site = definition == null ? null : definitions.lookup (definition);
		SsaInstruction? instruction = site == null || site.block == null || site.position < 0 ? null : site.block.instructions[site.position];
		if (instruction is SsaClassUpcast) {
			return text_backing_owner (((SsaClassUpcast) instruction).reference);
		}
		if (instruction is SsaObjectValidateInstruction) {
			return text_backing_owner (((SsaObjectValidateInstruction) instruction).reference);
		}
		if (instruction is SsaCatchBorrow) {
			return text_backing_owner (((SsaCatchBorrow) instruction).exception);
		}
		if (instruction is SsaLoadInstruction && ((SsaLoadInstruction) instruction).source is SsaLocalMemoryPlace) {
			return ((SsaLocalMemoryPlace) ((SsaLoadInstruction) instruction).source).storage;
		}
		return value;
	}

	private void verify_text_loans(SsaFunction function) throws SsaError {
		verify_text_exits (function);
		function.verify_text_uses ();
		function.verify_volatile_effects ();
		if (function.text_loans.length == 0) {
			return;
		}
		var entries = new HashTable<SsaBlock, Astra.Text.TextOriginState> (direct_hash, direct_equal);
		var invalidations = new HashTable<Object, GenericArray<Object>> (direct_hash, direct_equal);
		var exits = new GenericArray<Object> ();
		var uses = new HashTable<SsaTextLoanUse, Object> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			var state = new Astra.Text.TextOriginState ();
			foreach (var loan in function.text_loans) {
				state.bindings.insert (loan, new Object ());
			}
			entries.insert (block, state);
		}
		foreach (var block in function.blocks) {
			var state = entries.lookup (block).snapshot ();
			foreach (var instruction in block.instructions) {
				if (instruction is SsaTextLoanBind) {
					var binding = (SsaTextLoanBind) instruction;
					var expected = new GenericArray<Object> ();
					for (uint i = 0; i < binding.intent.count; i++) {
						var owner = text_backing_owner ((SsaValue) binding.intent.owner (i));
						if (!expected.find (owner)) {
							expected.add (owner);
						}
					}
					if (!(new Astra.Text.TextLoanIntent (expected)).matches (text_origins.receiver_owners (binding.value))) {
						fail ("text loan", "stored view changed its exact retained receiver association");
					}
					state.bindings.insert (binding.loan, binding.value);
				} else if (instruction is SsaTextLoanEnd) {
					state.bindings.insert (((SsaTextLoanEnd) instruction).loan, new Object ());
				} else if (instruction is SsaTextLoanUse) {
					var use = (SsaTextLoanUse) instruction;
					uses.insert (use, state.bindings.lookup (use.loan));
				}
				SsaValue? invalidated = null;
				if (instruction is SsaCleanupInstruction && ((SsaCleanupInstruction) instruction).value.semantic_type is ClassType) {
					invalidated = ((SsaCleanupInstruction) instruction).value;
				} else if (instruction is SsaOwnedArgumentReservation) {
					invalidated = ((SsaOwnedArgumentReservation) instruction).value;
				} else if (instruction is SsaHeapOwnerEvent && ((SsaHeapOwnerEvent) instruction).action == SsaHeapOwnerAction.MOVE) {
					invalidated = ((SsaHeapOwnerEvent) instruction).value;
				} else if (instruction is SsaExceptionTransfer) {
					invalidated = ((SsaExceptionTransfer) instruction).source;
				}
				if (invalidated != null) {
					var owner = text_backing_owner (invalidated);
					var values = invalidations.lookup (owner);
					if (values == null) {
						values = new GenericArray<Object> ();
						invalidations.insert (owner, values);
					}
					foreach (var key in state.bindings.get_keys ()) {
						values.add (state.bindings.lookup (key));
					}
				}
			}
			if (block.terminator is SsaReturn || block.terminator is SsaFunctionEnd) {
				foreach (var key in state.bindings.get_keys ()) {
					exits.add (state.bindings.lookup (key));
				}
			}
			foreach (var successor in block.terminator.successors ()) {
				foreach (var key in entries.lookup (successor).bindings.get_keys ()) {
					text_origins.copy (entries.lookup (successor).bindings.lookup (key), state.bindings.lookup (key));
				}
			}
		}
		foreach (var owner in invalidations.get_keys ()) {
			foreach (var value in invalidations.lookup (owner)) {
				foreach (var backing in text_origins.receiver_owners (value)) {
					if (backing == owner) {
						fail ("text loan", "receiver invalidation overlaps a surviving exact loan");
					}
				}
			}
		}
		foreach (var value in exits) {
			if (text_origins.has_receiver_borrow (value)) {
				fail ("text loan", "function exit leaves a stored receiver loan active");
			}
		}
		foreach (var use in uses.get_keys ()) {
			if (!text_origins.is_bounded (uses.lookup (use))) {
				int line;
				int column;
				use.span.file.locate (use.span.start, out line, out column);
				fail ("text loan", "stored text use follows an uninitialized or prematurely ended exact loan in %s local #%d at %d:%d".printf (function.name, use.loan.local_ordinal, line, column));
			}
		}
	}

	private void verify_text_returns() throws SsaError {
		foreach (var view in text_views.get_keys ()) {
			if (!text_origins.is_bounded (view)) {
				fail ("text slice", "requires stable deep backing origins");
			}
		}
		foreach (var value in text_returns) {
			if (!text_origins.is_static (value)) {
				fail ("text return", "borrowed text cannot escape through a STATIC_TEXT result");
			}
		}
	}

	private HashTable<SsaValue, SsaEnumSlot> enum_views = new HashTable<SsaValue, SsaEnumSlot> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, SsaNode> buffer_consumers = new HashTable<SsaBufferPair, SsaNode> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaBufferReadInstruction> buffer_views = new HashTable<SsaValue, SsaBufferReadInstruction> (direct_hash, direct_equal);
	private HashTable<SsaBufferWriteInstruction, SsaBufferPair> buffer_disarms = new HashTable<SsaBufferWriteInstruction, SsaBufferPair> (direct_hash, direct_equal);
	private HashTable<SsaBufferDeallocateInstruction, SsaBufferDeallocateInstruction> buffer_field_epilogues = new HashTable<SsaBufferDeallocateInstruction, SsaBufferDeallocateInstruction> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, SsaBufferReadInstruction> buffer_reads = new HashTable<SsaBufferPair, SsaBufferReadInstruction> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, SsaInstruction> buffer_producers = new HashTable<SsaBufferPair, SsaInstruction> (direct_hash, direct_equal);
	private HashTable<SsaBufferPair, SsaBufferPair> buffer_pairs = new HashTable<SsaBufferPair, SsaBufferPair> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaBufferPair> buffer_leaves = new HashTable<SsaValue, SsaBufferPair> (direct_hash, direct_equal);
	private HashTable<SsaBufferStorage, SsaFunction> buffer_storage = new HashTable<SsaBufferStorage, SsaFunction> (direct_hash, direct_equal);
	private HashTable<SsaInstruction, DefinitionSite> buffer_sites = new HashTable<SsaInstruction, DefinitionSite> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaCallInstruction> private_success_values = new HashTable<SsaValue, SsaCallInstruction> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaCallInstruction> exception_results = new HashTable<SsaValue, SsaCallInstruction> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaClassUpcast> class_upcasts = new HashTable<SsaValue, SsaClassUpcast> (direct_hash, direct_equal);
	private HashTable<SsaBaseLifecycleCall, bool> base_epilogues = new HashTable<SsaBaseLifecycleCall, bool> (direct_hash, direct_equal);
	private HashTable<SsaTextSnapshotDestroy, bool> snapshot_epilogues = new HashTable<SsaTextSnapshotDestroy, bool> (direct_hash, direct_equal);
	private HashTable<SsaCleanupInstruction, bool> child_field_epilogues = new HashTable<SsaCleanupInstruction, bool> (direct_hash, direct_equal);
	private HashTable<SsaRecordFieldDrop, bool> record_field_epilogues = new HashTable<SsaRecordFieldDrop, bool> (direct_hash, direct_equal);
	private SsaCleanupInstruction? field_cleanup_before(SsaBlock block, ref int index) {
		var event = index < 0 ? null : block.instructions[index] as SsaHeapOwnerEvent;
		if (event != null) {
			if (event.owner != null || event.action != SsaHeapOwnerAction.END || index < 1 || event.effect != block.instructions[index - 1]) {
				return null;
			}
			index--;
		}
		var cleanup = index < 0 ? null : block.instructions[index--] as SsaCleanupInstruction;
		return cleanup;
	}

	private bool guarded_success(SsaCallInstruction call, SsaBlock consumer) {
		return guarded_effect_success (call.exception_result, consumer);
	}

	private bool guarded_effect_success(SsaDefinition? exception, SsaBlock consumer) {
		if (exception == null) {
			return false;
		}
		var site = definitions.lookup (exception);
		if (site == null || site.block == null) {
			return false;
		}
		var branch = site.block.terminator as SsaConditionalBranch;
		var condition_site = branch == null ? null : definitions.lookup ((SsaDefinition) branch.condition);
		var binary = condition_site == null || condition_site.position < 0 ? null : condition_site.block.instructions[condition_site.position] as SsaBinaryInstruction;
		if (binary == null || binary.left != exception || !(binary.right is SsaNullPointerConstant) || binary.operator_kind != BinaryOperator.EQUAL) {
			return false;
		}
		return dominance[branch.true_edge.target.ordinal, consumer.ordinal] && !dominance[branch.false_edge.target.ordinal, consumer.ordinal];
	}

	private bool guarded_catch(SsaCatchBorrow caught, SsaFunction function, SsaBlock consumer) {
		foreach (var block in function.blocks) {
			var branch = block.terminator as SsaConditionalBranch;
			if (branch == null) {
				continue;
			}
			foreach (var instruction in block.instructions) {
				var match = instruction as SsaExceptionMatch;
				if (match != null && match.result == branch.condition && match.exception == caught.exception && match.match_type == caught.result.semantic_type && dominance[branch.true_edge.target.ordinal, consumer.ordinal] && !dominance[branch.false_edge.target.ordinal, consumer.ordinal]) {
					return true;
				}
			}
		}
		return false;
	}

	private void verify_resource_epilogues(SsaFunction function) throws SsaError {
		var destructor = function as SsaDestructor;
		if (destructor == null) {
			return;
		}
		foreach (var block in function.blocks) {
			if (!(block.terminator is SsaReturn || block.terminator is SsaFunctionEnd)) {
				continue;
			}
			int index = (int) block.instructions.length - 1;
			if (destructor.declaring_class.parent_class != null && destructor.declaring_class.parent_class.destructor != null) {
				var call = index < 0 ? null : block.instructions[index--] as SsaBaseLifecycleCall;
				var cast = index < 0 ? null : block.instructions[index--] as SsaClassUpcast;
				if (call == null || cast == null || cast.reference != destructor.receiver || cast.source_class != destructor.declaring_class || cast.target_class != destructor.declaring_class.parent_class || call.receiver != cast.result || call.target != destructor.declaring_class.parent_class.destructor || call.arguments.length != 0) {
					fail ("base deinit", "normal destructor exit requires exact base teardown after declared field cleanup");
				}
				base_epilogues.insert (call, true);
			}

			foreach (var field in destructor.declaring_class.fields) {
				if (field.record_owner != null) {
					var drop = index < 0 ? null : block.instructions[index--] as SsaRecordFieldDrop;
					if (drop == null || drop.source.pointer != destructor.receiver || drop.source.field != field) {
						fail ("record field cleanup", "destructor requires complete reverse declaration record retirement");
					}
					record_field_epilogues.insert (drop, true);
					continue;
				}
				if (field.semantic_type is OwnerSlotsType) {
					var drop = index < 0 ? null : block.instructions[index--] as SsaSlotsEffect;
					if (drop == null || drop.action != SsaSlotsAction.DROP || drop.store.pointer != destructor.receiver || drop.store.field != field) {
						fail ("owner-slot cleanup", "normal destructor exit requires exact reverse declaration owner-slot cleanup");
					}
					slots_epilogues.insert (drop, true);
					continue;
				}
				if (field.text_snapshot) {
					var cleanup = index < 0 ? null : block.instructions[index--] as SsaTextSnapshotDestroy;
					if (cleanup == null || cleanup.field.pointer != destructor.receiver || cleanup.field.field != field) {
						fail ("snapshot cleanup", "normal destructor exit requires exact reverse declaration snapshot cleanup");
					}
					snapshot_epilogues.insert (cleanup, true);
					continue;
				}
				if (field.semantic_type is SliceType) {
					var cleanup = index < 0 ? null : block.instructions[index--] as SsaBufferDeallocateInstruction;
					var read = index < 0 ? null : block.instructions[index--] as SsaBufferReadInstruction;
					if (cleanup == null || read == null || read.place.field == null || read.place.field.pointer != destructor.receiver || read.place.field.field != field || cleanup.pair != read.pair || !matches_cleanup (field.semantic_type, cleanup.cleanup)) {
						fail ("field cleanup", "normal destructor exit requires exact reverse declaration buffer cleanup");
					}
					buffer_field_epilogues.insert (cleanup, cleanup);
					continue;
				}
				if (!(field.semantic_type is HandleType || field.semantic_type is ClassType)) {
					continue;
				}
				var cleanup = field_cleanup_before (block, ref index);
				var load = index < 0 ? null : block.instructions[index--] as SsaLoadInstruction;
				var place = load == null ? null : load.source as SsaIndirectFieldPlace;
				if (cleanup == null || place == null || place.pointer != destructor.receiver || place.field != field || cleanup.value != load.result || !matches_cleanup (field.semantic_type, cleanup.cleanup)) {
					fail ("field cleanup", "normal destructor exit requires reverse declaration handle loads and exact cleanup calls");
				}
				if (field.semantic_type is ClassType) {
					if (!cleanup.cleanup.is_heap_object) {
						fail ("field cleanup", "child teardown requires exact heap cleanup");
					}
					child_field_epilogues.insert (cleanup, true);
				}
			}
			foreach (var property in destructor.declaring_class.properties) {
				if (!property.is_owned_lazy) {
					continue;
				}
				var drop = index < 0 ? null : block.instructions[index--] as SsaLazyDrop;
				if (drop == null || drop.property_member != property) {
					fail ("owned lazy", "destructor exit lost exact reverse-order cache owner retirement");
				}
				lazy_epilogues.insert (drop, true);
			}

		}
	}

	private HashTable<Astra.Source.SuspensionLoanIdentity, bool> suspension_loan_ids = new HashTable<Astra.Source.SuspensionLoanIdentity, bool> (direct_hash, direct_equal);
	private HashTable<SsaStructCallResults, SsaInstruction> struct_results = new HashTable<SsaStructCallResults, SsaInstruction> (direct_hash, direct_equal);
	private HashTable<SsaInstructionResult, SsaStructCallResults> struct_result_leaves = new HashTable<SsaInstructionResult, SsaStructCallResults> (direct_hash, direct_equal);
	private HashTable<SsaStructCallResults, DefinitionSite> struct_consumptions = new HashTable<SsaStructCallResults, DefinitionSite> (direct_hash, direct_equal);
	private HashTable<SsaObjectStorage, SsaCallInstruction> result_candidates = new HashTable<SsaObjectStorage, SsaCallInstruction> (direct_hash, direct_equal);
	private HashTable<SsaResultObjectStorage, SsaFunction> result_inputs = new HashTable<SsaResultObjectStorage, SsaFunction> (direct_hash, direct_equal);
	private FieldInitializationState? field_state;
	private HashTable<SsaObjectStorage, SsaFunction> object_owners = new HashTable<SsaObjectStorage, SsaFunction> (direct_hash, direct_equal);
	private HashTable<SsaObjectStorage, DefinitionSite> constructor_sites = new HashTable<SsaObjectStorage, DefinitionSite> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaObjectStorage> storage_receivers = new HashTable<SsaValue, SsaObjectStorage> (direct_hash, direct_equal);
	private HashTable<SsaObjectStorage, HashTable<SsaStructField, DefinitionSite>> object_initializations = new HashTable<SsaObjectStorage, HashTable<SsaStructField, DefinitionSite>> (direct_hash, direct_equal);
	private HashTable<SsaObjectStorage, SsaObjectReferenceInstruction> object_constructions = new HashTable<SsaObjectStorage, SsaObjectReferenceInstruction> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaObjectValidateInstruction> object_validations = new HashTable<SsaValue, SsaObjectValidateInstruction> (direct_hash, direct_equal);
	private HashTable<SemanticType, ReceiverType> initializing_types = new HashTable<SemanticType, ReceiverType> (direct_hash, direct_equal);
	private HashTable<SemanticType, ReceiverType> receiver_types = new HashTable<SemanticType, ReceiverType> (direct_hash, direct_equal);
	private HashTable<SsaReceiver, SsaFunction> receiver_owners = new HashTable<SsaReceiver, SsaFunction> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaValue> slice_bounds_views = new HashTable<SsaValue, SsaValue> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaAddressableLocal> bounds_storage = new HashTable<SsaValue, SsaAddressableLocal> (direct_hash, direct_equal);
	private HashTable<SemanticType, SliceType> slices = new HashTable<SemanticType, SliceType> (direct_hash, direct_equal);
	private GenericArray<ArrayType> arrays = new GenericArray<ArrayType> ();
	private HashTable<SemanticType, SsaHandle> handles = new HashTable<SemanticType, SsaHandle> (direct_hash, direct_equal);
	private HashTable<SsaFunctionParameter, SsaFunctionParameter> contract_parameters = new HashTable<SsaFunctionParameter, SsaFunctionParameter> (direct_hash, direct_equal);
	private HashTable<SsaCleanupInstruction, SsaCleanupInstruction> cleanup_instructions = new HashTable<SsaCleanupInstruction, SsaCleanupInstruction> (direct_hash, direct_equal);
	private HashTable<SsaCleanupContract, SsaCleanupContract> cleanups = new HashTable<SsaCleanupContract, SsaCleanupContract> (direct_hash, direct_equal);
	private HashTable<SsaCFunction, SsaCFunction> c_functions = new HashTable<SsaCFunction, SsaCFunction> (direct_hash, direct_equal);
	private HashTable<SsaFunction, SsaFunction> functions = new HashTable<SsaFunction, SsaFunction> (direct_hash, direct_equal);
	private HashTable<SsaInstruction, SsaInstruction> calls = new HashTable<SsaInstruction, SsaInstruction> (direct_hash, direct_equal);
	private HashTable<SsaBlock, SsaFunction> owners = new HashTable<SsaBlock, SsaFunction> (direct_hash, direct_equal);
	private HashTable<SsaDefinition, DefinitionSite> definitions = new HashTable<SsaDefinition, DefinitionSite> (direct_hash, direct_equal);
	private HashTable<SsaValue, SsaNumericGuard> numeric_guards = new HashTable<SsaValue, SsaNumericGuard> (direct_hash, direct_equal);
	private HashTable<int, SemanticType> types = new HashTable<int, SemanticType> (direct_hash, direct_equal);
	private bool[,] dominance;
	private HashTable<SemanticType, SsaNativeInstance> structs = new HashTable<SemanticType, SsaNativeInstance> (direct_hash, direct_equal);
	private GenericArray<SemanticType>? child_edges(SemanticType type) {
		var result = new GenericArray<SemanticType> ();
		var record = structs.lookup (type) as SsaStruct;
		if (record != null) {
			foreach (var field in record.fields) {
				if (field.semantic_type is ClassType || field.semantic_type is StructType) {
					result.add (field.semantic_type);
				}
			}
			return result;
		}
		for (var owner = structs.lookup (type) as SsaClass; owner != null; owner = owner.parent_class) {
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

	private HashTable<SemanticType, SemanticType> pointers = new HashTable<SemanticType, SemanticType> (direct_hash, direct_equal);
	private HashTable<SsaAddressableLocal, SsaFunction> storage_owners = new HashTable<SsaAddressableLocal, SsaFunction> (direct_hash, direct_equal);
	private HashTable<SsaAddressableLocal, HashTable<Object, DefinitionSite>> initializations = new HashTable<SsaAddressableLocal, HashTable<Object, DefinitionSite>> (direct_hash, direct_equal);
	private HashTable<SsaInstruction, SsaInstruction> memory_instructions = new HashTable<SsaInstruction, SsaInstruction> (direct_hash, direct_equal);

	private GenericArray<VectorType> vectors = new GenericArray<VectorType> ();

	private GenericArray<SsaPrivateFieldAccess>? private_accesses;

	private GenericArray<SsaFunction> scoped_constructions = new GenericArray<SsaFunction> ();
	private SsaVerifier () {
	}

	public static void verify(SsaProgram program, GenericArray<SsaPrivateFieldAccess>? accesses = null) throws SsaError {
		foreach (var function in program.functions) {
			if (function.return_type.is_scoped_allocator ()) {
				throw new SsaError.INVALID_SSA ("scoped context cannot escape through a function result");
			}
			foreach (var parameter in function.parameters) {
				if (parameter.semantic_type.is_scoped_allocator () && (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || function.async_body != null)) {
					throw new SsaError.INVALID_SSA ("scoped context requires a synchronous borrowed parameter");
				}
			}
			function.verify_vector_memory ();
		}
		foreach (var structure in program.structs) {
			foreach (var field in structure.fields) {
				if (field.semantic_type.is_scoped_allocator ()) {
					throw new SsaError.INVALID_SSA ("scoped context cannot be stored in a field");
				}
			}
		}
		foreach (var structure in program.classes) {
			foreach (var field in structure.fields) {
				if (field.semantic_type.is_scoped_allocator ()) {
					throw new SsaError.INVALID_SSA ("scoped context cannot be stored in a Class field");
				}
			}
		}
		foreach (var function in program.functions) {
			if (!function.floating_policy_valid ()) {
				throw new SsaError.INVALID_SSA ("floating policy differs from its admitted declaration");
			}
		}
		var verifier = new SsaVerifier ();
		verifier.caller_result_origins = new SsaCallerResultOrigins (program);
		verifier.private_accesses = accesses;
		verifier.utf8_instructions = SsaUtf8FactoryAuthority.authorize (program);
		foreach (var function in program.functions) {
			verifier.verify_native_declaration (function, "native declaration");
		}
		verifier.verify_program (program);
		SsaReadonlyInference.verify_imported (program);
		verifier.verify_class_type_arguments (program);
		SsaEffectAnalysis.verify (program);
		SsaFormalEffectVerifier.verify (program);
		SsaStackObjects.verify (program);
		SsaExactCalls.verify (program);
		SsaSharedElision.verify (program);
		SsaNonNull.verify (program);
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaContinuationRegion) {
						SsaContinuationVerifier.verify ((SsaContinuationRegion) instruction, program.functions, program.structs, program.cleanups);
					}
				}
			}
		}
		verifier.verify_text_returns ();
		foreach (var function in program.functions) {
			verifier.verify_text_loans (function);
		}
		foreach (var pair in verifier.buffer_producers.get_keys ()) {
			if (!verifier.buffer_consumers.contains (pair)) {
				verifier.fail ("buffer producer", "owning allocation/result requires one complete cleanup responsibility consumer");
			}
		}
		foreach (var function in program.functions) {
			if (function.declaration_only ()) {
				continue;
			}
			foreach (var group in function.buffer_parameters) {
				if (!verifier.buffer_consumers.contains (group.pair)) {
					verifier.fail ("buffer parameter", "incoming owner pair must acquire or transfer complete cleanup responsibility");
				}
			}
		}
		foreach (var function in program.functions) {
			if (function.declaration_only ()) {
				continue;
			}
			SsaAllocationFailureVerifier.verify (function);
			verifier.verify_buffer_commits (function);
			SsaObjectLifecycleFlow.verify (function);
			var buffers = SsaBufferMemoryFlow.verify (function);
			var scalars = SsaHeapOwnerFlow.verify (function);
			SsaRecordRetirementFlow.verify (function, scalars, buffers);
			SsaScopedBackingFlow.verify (function, scalars, buffers);
			foreach (var owner in function.frame_catch_owners) {
				owner.verify_events (function);
			}
			SsaTaskFlow.verify (function);
		}
		foreach (var function in program.functions) {
			function.verify_cleanup_effects ();
		}
		SsaRuntimeLifetimes.verify (program, verifier.scoped_constructions);
		foreach (var function in program.c_functions) {
			if (function.return_type.is_scoped_allocator ()) {
				throw new SsaError.INVALID_SSA ("scoped context cannot be acquired from a foreign factory");
			}
		}
	}

	private void verify_class_type_arguments(SsaProgram program) throws SsaError {
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
					bool record = type is StructType && declaration is SsaStruct;
					bool object = type is ClassType && declaration is SsaClass;
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

	private void fail(string path, string message) throws SsaError {
		throw new SsaError.INVALID_SSA ("internal SSA verification error at %s: %s", path, message);
	}

	private GenericArray<SsaStruct> element_structs;
	private SsaArrayElementPlace? initializing_array_entry;
	private HashTable<SsaAddressableLocal, GenericArray<SsaArrayInitialize>> record_initializations = new HashTable<SsaAddressableLocal, GenericArray<SsaArrayInitialize>> (direct_hash, direct_equal);
	private HashTable<SsaArrayInitialize, DefinitionSite> record_initialization_sites = new HashTable<SsaArrayInitialize, DefinitionSite> (direct_hash, direct_equal);
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

	private void verify_collection_element(SemanticType type, string path) throws SsaError {
		if (!type.is_struct_storage ()) {
			verify_type (type, true, path);
			return;
		}
		if (!BufferElementTypes.supports (type, element_fields)) {
			fail (path, "record collection element requires a complete copyable, zeroable, trivially destructible field graph; invalid path " + (BufferElementTypes.invalid_field (type, element_fields) ?? "<copy>"));
		}
	}

	private void verify_array_type(ArrayType array, string path) throws SsaError {
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

	private HashTable<SsaLazyDrop, bool> lazy_seen = new HashTable<SsaLazyDrop, bool> (direct_hash, direct_equal);
	private HashTable<SsaLazyDrop, bool> lazy_epilogues = new HashTable<SsaLazyDrop, bool> (direct_hash, direct_equal);
	private HashTable<SsaSlotsEffect, bool> slots_epilogues = new HashTable<SsaSlotsEffect, bool> (direct_hash, direct_equal);
	private void verify_slots_field(SsaStructField field, string path) throws SsaError {
		var type = field.semantic_type as OwnerSlotsType;
		var cleanup = field.slots_cleanup;
		if (type == null || !(field.containing_type is SsaClass) || ((SsaClass) field.containing_type).polymorphic || field.owned_cleanup != null || field.text_snapshot) {
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

	private void verify_slots_place(SsaIndirectFieldPlace store, SsaFunction function, SsaBlock block, int position, bool read, string path) throws SsaError {
		if (function.async_body != null) {
			fail (path, "owner slots require synchronous code");
		}
		verify_place (store, function, block, position, false, path);
		verify_slots_field (store.field, path);
		if (read && store.pointer == function.implicit_receiver && function is SsaConstructor && (field_state == null || !field_state.is_definite (store.field.ordinal))) {
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

	private SsaScopedInspection scoped_inspections;
	private bool slots_invalidates(SsaInstruction instruction, SemanticType backing, bool readonly_receiver = false) {
		var effect = instruction as SsaSlotsEffect;
		if (effect != null && slot_alias (effect.store.field.containing_type.semantic_type, backing)) {
			return true;
		}
		var operation = instruction as SsaSlotsValueInstruction;
		if (operation != null && (operation.action == OwnerSlotsAction.RESERVE || operation.action == OwnerSlotsAction.TAKE) && slot_alias (operation.store.field.containing_type.semantic_type, backing)) {
			return true;
		}
		var stored = instruction as SsaStoreInstruction;
		var field = stored == null ? null : stored.target as SsaIndirectFieldPlace;
		if (field != null && slot_alias (field.field.containing_type.semantic_type, backing)) {
			return true;
		}
		var cleanup = instruction as SsaCleanupInstruction;
		if (cleanup != null && slot_alias (cleanup.value.semantic_type, backing)) {
			return true;
		}
		var move = instruction as SsaHeapOwnerEvent;
		if (move != null && move.action != SsaHeapOwnerAction.ACQUIRE && slot_alias (move.value.semantic_type, backing)) {
			return true;
		}
		var call = instruction as SsaCallInstruction;
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

	private bool slots_reaches(SsaBlock start, SsaBlock target) {
		var pending = new GenericArray<SsaBlock> ();
		var seen = new HashTable<SsaBlock, bool> (direct_hash, direct_equal);
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

	private void verify_slots_loans(SsaFunction function) throws SsaError {
		foreach (var origin in function.blocks) {
			for (int i = 0; i < origin.instructions.length; i++) {
				var loan = origin.instructions[i] as SsaSlotsValueInstruction;
				if (loan == null || loan.action != OwnerSlotsAction.BORROW) {
					continue;
				}
				SsaCallInstruction? consumer = null;
				SsaBlock? consumer_block = null;
				int consumers = 0;
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaCallInstruction;
						if (call == null) {
							continue;
						}
						for (int a = 0; a < call.arguments.length; a++) {
							if (call.arguments[a] == loan.result) {
								consumers++;
								consumer = call;
								consumer_block = block;
								if (a >= call.target.parameters.length || call.target.parameters[a] != loan.borrower || (call.target.kind != CallableKind.FUNCTION && call.target.kind != CallableKind.METHOD) || call.target.async_body != null || call.target.throws_type != null || !scoped_inspections.copied_result (call.target.return_type)) {
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
					scoped_inspections.verify (consumer.target);
				}
				var backing = loan.store.field.containing_type.semantic_type;
				if (slots_invalidates (consumer, backing, readonly_receiver)) {
					fail ("owner-slot loan", "inspection call carries an overlapping container alias");
				}
				var pending = new GenericArray<SsaBlock> ();
				var seen = new HashTable<SsaBlock, bool> (direct_hash, direct_equal);
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

	private void verify_callable_record_result(CallableSignature signature, SsaStructCallResults? group, SsaInstruction definition, string path) throws SsaError {
		var result_type = CallableTypes.result_type ((SemanticType) signature);
		if (!result_type.is_struct_storage ()) {
			if (group != null) {
				fail (path, "scalar callable cannot publish a record result group");
			}
			return;
		}
		if (signature.record_result == null || group == null || definition.result != null || struct_results.lookup (group) != definition
		    || group.shape.semantic_type != result_type || group.shape.mode != signature.record_result.mode || group.leaves.length != group.shape.leaves.length) {
			fail (path, "indirect record result requires its exact complete bounded group");
		}
		verify_struct_shape (group.shape, result_type, path);
		for (int l = 0; l < group.leaves.length; l++) {
			if (group.leaves[l].semantic_type != group.shape.leaves[l].semantic_type) {
				fail (path, "indirect record result changed an exact physical leaf");
			}
		}
	}

	private void verify_invocation_result(SsaCallableInvocation call, CallableSignature? signature, SsaFunction function, string path) throws SsaError {
		SemanticType result_type;
		if (signature is FunctionValueType) {
			result_type = ((FunctionValueType) signature).result_type;
		} else if (signature is ClosureHandleType) {
			result_type = ((ClosureHandleType) signature).result_type;
		} else {
			fail (path, "indirect result requires its exact callable signature");
			return;
		}
		var cleanup = call.result_cleanup ();
		if (!FunctionValueType.supported_result (result_type, signature.result_contract)
		    || (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER
		            ? cleanup == null || !cleanups.contains (cleanup) || !matches_cleanup (result_type, cleanup) || result_type is ClassType && !cleanup.is_heap_object
		            : cleanup != null)) {
			fail (path, "indirect result requires its exact declared ownership and cleanup contract");
		}
		if (cleanup == null) {
			return;
		}
		var value = call.owned_result_value ();
		int acquisitions = 0;
		int forwards = 0;
		foreach (var block in function.blocks) {
			for (int position = 0; position < block.instructions.length; position++) {
				var instruction = block.instructions[position];
				var event = instruction as SsaHeapOwnerEvent;
				if (event != null && event.value == value && event.action == SsaHeapOwnerAction.RETURN && event.owner == null) {
					var returned = block.terminator as SsaOwnershipReturn;
					var closure = call as SsaClosureCall;
					if (returned == null || returned.value != value || function.owned_cleanup != cleanup
					    || (closure != null && ((ClosureHandleType) closure.callee.semantic_type).throws_type != null
					        && !guarded_effect_success (closure.result, block))) {
						fail (path, "indirect result forwarding requires its exact guarded return and cleanup contract");
					}
					foreach (var candidate in function.blocks) {
						foreach (var effect in candidate.instructions) {
							var retired = effect as SsaCleanupInstruction;
							if (retired != null && retired.value == value) {
								fail (path, "indirect forwarded result cannot be retired by its producer");
							}
						}
					}
					forwards++;
				}
				if (event == null || event.value != value || event.action != SsaHeapOwnerAction.ACQUIRE) {
					continue;
				}
				if (event.owner == null || !function.heap_owners.find (event.owner) || event.owner.cleanup != cleanup) {
					fail (path, "indirect result acquisition changed its declared cleanup");
				}
				var record = event.effect as SsaRecordAcquire;
				var replacement = event.effect as SsaRecordReplace;
				SsaHeapOwnerEvent? previous = null;
				for (int prior = position - 1; prior >= 0; prior--) {
					var candidate = block.instructions[prior] as SsaHeapOwnerEvent;
					if (candidate != null && candidate.value == value && candidate.action != SsaHeapOwnerAction.READ) {
						previous = candidate;
						break;
					}
				}
				// Subsequent transfers have their own independently checked source
				// disarmament. They do not reacquire responsibility from this call.
				if ((record != null && record.source_owner != null)
				    || (replacement != null && replacement.source_owner != null)
				    || event.effect is SsaRecordMove || event.effect is SsaRecordTake
				    || (previous != null && previous.action == SsaHeapOwnerAction.MOVE && previous.owner != event.owner)) {
					continue;
				}
				acquisitions++;
			}
		}
		if (value == null || value.semantic_type != result_type || acquisitions + forwards != 1) {
			fail (path, "indirect owned result requires exactly one guarded producer acquisition or forwarded return");
		}
	}

	private void verify_type(SemanticType? type, bool value, string path) throws SsaError {
		if (type is ClosureHandleType && !((ClosureHandleType) type).actor) {
			var signature = (ClosureHandleType) type;
			try {
				signature.verify_records (signature.record_parameters, struct_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
		}
		if (type is FunctionValueType) {
			var signature = (FunctionValueType) type;
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
		if (type is ExecutorType || type is TaskType) {
			return;
		}
		if (type == null) {
			fail (path, "missing semantic type");
			return;
		}
		if (type is EnumType) {
			if (!enum_definitions.contains ((EnumType) type)) {
				fail (path, "enum requires exact program-owned nominal definition");
			}
			return;
		}
		if (type.kind == TypeKind.STRING) {
			if (!(type is StringType) || (string_type != null && string_type != type)) {
				fail (path, "text requires canonical StringType identity");
			}
			string_type = type;
			return;
		}
		if (type.kind == TypeKind.RECEIVER) {
			var receiver = type as ReceiverType;
			if (receiver == null || (receiver.mode == ReceiverMode.INITIALIZING ? initializing_types : receiver_types).lookup (receiver.instance_type) != receiver) {
				fail (path, "receiver requires exact declared instance type and compiler-owned contract");
			}
			return;
		}
		if (type.kind == TypeKind.SLICE) {
			var slice = type as SliceType;
			if (slice == null || !SliceType.supports (slice.element_type)) {
				fail (path, "unsupported slice element; requires exact supported storage or text descriptor type");
				return;
			}
			verify_collection_element (slice.element_type, path + "/element");
			if (slice is ContextBytesType) {
				var bytes = (ContextBytesType) slice;
				bool declared = false;
				// Buffer cleanup shapes precede handle registration. Consult the
				// exact current program inventory; its full contracts are checked below.
				foreach (var handle in foreign_program.handles) {
					if (handle.semantic_type == bytes.allocator_type && handle.context_mode == bytes.context_mode && handle.cleanup.external_symbol == bytes.allocator_type.context_cleanup) {
						declared = true;
					}
				}
				if (!bytes.valid () || !declared) {
					fail (path, "context byte pair lost its exact declared owned allocator contract");
				}
			}
			var prior = slices.lookup (slice.canonical_key ());
			if (prior != null && prior != slice) {
				fail (path, "inconsistent slice semantic type identity");
			}
			slices.insert (slice.canonical_key (), slice);
			return;
		}
		if (type.kind == TypeKind.VECTOR) {
			var vector = type as VectorType;
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
		if (type.kind == TypeKind.CLASS) {
			if (!(type is ClassType) || !(structs.lookup (type) is SsaClass)) {
				fail (path, "class reference requires exact program-owned nominal identity");
			}
			return;
		}
		if (type.kind == TypeKind.HANDLE) {
			if (!(type is HandleType) || !handles.contains (type)) {
				fail (path, "handle value requires exact declared nominal type identity");
			}
			return;
		}
		if (type.kind == TypeKind.TYPED_POINTER) {
			var pointer = type as TypedPointerType;
			if (pointer == null || !pointer.pointee.is_typed_data_pointee ()) {
				fail (path, "unsupported typed data pointer pointee");
				return;
			}
			if (pointer.pointee is StructType) {
				if (!structs.contains (pointer.pointee)) {
					fail (path, "typed pointer requires exact program-owned struct identity");
				}
				if (CopyabilityAuthority.of (pointer.pointee, element_fields) != Copyability.COPYABLE) {
					fail (path, "owning record pointers are deferred");
				}
			} else {
				verify_type (pointer.pointee, true, path + "/pointee");
			}
			var prior = pointers.lookup (pointer.pointee);
			if (prior != null && prior != pointer) {
				fail (path, "inconsistent typed pointer semantic type identity");
			}
			pointers.insert (pointer.pointee, pointer);
			return;
		}
		if (!(type is IntegerType) && type.kind != TypeKind.F32 && type.kind != TypeKind.F64 && type.kind != TypeKind.INT && type.kind != TypeKind.BOOL && type.kind != TypeKind.VOID && type.kind != TypeKind.RAW_POINTER) {
			fail (path, "unsupported semantic type");
			return;
		}
		if (value && type.kind == TypeKind.VOID) {
			fail (path, "void is not an SSA value type");
		}
		if (type.kind == TypeKind.RAW_POINTER) {
			var pointer = type as RawPointerType;
			if (pointer == null || pointer.pointee.kind != TypeKind.VOID) {
				fail (path, "raw pointer must point to void");
				return;
			}
			if (pointer.pointee.kind == TypeKind.VOID) {
				verify_type (pointer.pointee, false, path + "/pointee");
			}
			var previous = pointers.lookup (pointer.pointee);
			if (previous != null && previous != pointer) {
				fail (path, "inconsistent '%s' semantic type identity".printf (pointer.display_name ()));
			}
			pointers.insert (pointer.pointee, pointer);
			return;
		}
		int index = (int) type.kind;
		if (types.lookup (index) != null && types.lookup (index) != type) {
			fail (path, "inconsistent '%s' semantic type identity".printf (type.display_name ()));
		}
		if (type.kind == TypeKind.INT && !(type is IntegerType)) {
			fail (path, "integer type requires immutable IntegerType authority");
		}
		if (type.kind == TypeKind.F32 && !(type is F32Type)) {
			fail (path, "f32 type requires immutable F32Type authority");
		}
		if (type.kind == TypeKind.F64 && !(type is F64Type)) {
			fail (path, "f64 type requires immutable F64Type authority");
		}
		types.insert (index, type);
	}

	private void define(SsaDefinition value, SsaFunction function, SsaBlock? block, int position, HashTable<int, SsaDefinition> ordinals, string path) throws SsaError {
		verify_type (value.semantic_type, true, path);
		if (definitions.contains (value)) {
			fail (path, "SSA definition occurs in more than one definition slot");
		}
		if (value.ordinal < 0 || ordinals.contains (value.ordinal)) {
			fail (path, "SSA value ordinal must be nonnegative and unique within the function");
		}
		ordinals.insert (value.ordinal, value);
		definitions.insert (value, new DefinitionSite (function, block, position));
	}

	private bool matches_cleanup(SemanticType type, SsaCleanupContract cleanup) {
		if (cleanup.closure_type != null) {
			return type == cleanup.closure_type && cleanup.closure_environment != null && cleanup.closure_environment.semantic_type == cleanup.closure_type.environment_type && !cleanup.closure_environment.polymorphic;
		}
		if (cleanup.shared_type != null) {
			return type == cleanup.shared_type && cleanup.shared_payload != null && cleanup.shared_payload.semantic_type == cleanup.shared_type.payload_type;
		}
		if (cleanup.is_buffer) {
			return cleanup.buffer_type == type && cleanup.buffer_shape.is_valid (element_fields);
		}
		if (cleanup.is_object) {
			return type is ClassType && cleanup.object_class != null && structs.lookup (type) == cleanup.object_class;
		}
		var handle = handles.lookup (type);
		return type.is_void_pointer () || (type is HandleType && handle != null && handle.cleanup == cleanup);
	}

	private void verify_parameter_contract(SsaFunctionParameter parameter, string path, bool record_class_leaf = false) throws SsaError {
		if (parameter.semantic_type is ReceiverType) {
			fail (path, "receiver is not an explicit parameter");
		}
		if (parameter.semantic_type is CallbackType && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			fail (path, "Callback requires exact borrowed-noescape parameter transport");
		}
		if (contract_parameters.contains (parameter) || !parameter.pointer_contract.is_valid () || (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && !(parameter.semantic_type is HandleType) && !(parameter.semantic_type is ClassType)) || (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is CallbackType) && !parameter.semantic_type.is_ownable_handle_type () && !(parameter.semantic_type is TypedPointerType && (CPlainRecordTypes.pointer (parameter.semantic_type, struct_fields) || (CPlainRecordTypes.i32_pointer (parameter.semantic_type) || ForeignApiTypes.scalar_pointee (parameter.semantic_type) != null))) && !(parameter.semantic_type is StringType) && !(parameter.semantic_type is SliceType) && !(parameter.semantic_type is ClassType)) || ((parameter.semantic_type is SliceType && parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) || (parameter.semantic_type is ClassType && parameter.pointer_contract == PointerParameterContract.UNMANAGED && !record_class_leaf))) {
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

	private SsaProgram foreign_program;
	private void verify_program(SsaProgram program) throws SsaError {
		foreign_program = program;
		scoped_inspections = new SsaScopedInspection (program);
		// Accessor links are weak. Reject a retired/missing property before
		// any derived result contract or hierarchy check dereferences it.
		foreach (var function in program.functions) {
			var accessor = function as SsaPropertyAccessor;
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
			for (int p = 0; p < function.parameters.length; p++) {
				var parameter = function.parameters[p];
				bool record_leaf = false;
				foreach (var group in function.struct_parameters) {
					record_leaf |= p >= group.first_leaf && p < group.first_leaf + group.shape.leaves.length;
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
		SsaEnumVerifier.verify (program, element_fields);
		element_structs = program.structs;
		foreach (var payload in program.text_literals) {
			if (!payload.valid ()) {
				fail ("text literal", "invalid UTF-8 payload or signed-I32 byte length");
			}
			text_literals.insert (payload, true);
		}
		var cleanup_symbols = new HashTable<string, string> (str_hash, str_equal);
		var buffer_cleanups = new HashTable<SemanticType, SsaCleanupContract> (direct_hash, direct_equal);
		var object_cleanups = new HashTable<SsaClass, SsaCleanupContract> (direct_hash, direct_equal);
		var heap_cleanups = new HashTable<SsaClass, SsaCleanupContract> (direct_hash, direct_equal);
		for (int c = 0; c < program.cleanups.length; c++) {
			var cleanup = program.cleanups[c];
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
				if (cleanup.ordinal != c || cleanups.contains (cleanup) || buffer_cleanups.contains (cleanup.buffer_type) || !cleanup.buffer_shape.is_valid (element_fields) || cleanup.external_symbol != "" || cleanup.is_object) {
					fail ("cleanup", "buffer requires unique static deallocation and exact eligible element/PTR/I32 shape");
				}
				buffer_cleanups.insert (cleanup.buffer_type, cleanup);
				cleanups.insert (cleanup, cleanup);
				verify_type (cleanup.buffer_type, true, "buffer cleanup");
				verify_type (cleanup.buffer_shape.base_type, true, "buffer base");
				verify_type (cleanup.buffer_shape.length_type, true, "buffer length");
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
						var imported = candidate.entry.terminator as SsaForeignReturn;
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
			string path = "struct " + structure.name;
			if (structure is SsaClass && (structure.ordinal < 0 || structure.ordinal >= program.classes.length || program.classes[structure.ordinal] != structure)) {
				fail (path, "class requires its exact declaration ordinal even without methods");
			}
			if ((structure is SsaStruct && !(structure.semantic_type is StructType)) || (structure is SsaClass && !(structure.semantic_type is ClassType))) {
				fail (path, "native declaration category must match its exact semantic type");
			}
			if (structs.contains (structure.semantic_type) || names.contains (structure.name) || structure.name == "" || structure.name != structure.semantic_type.display_name () || BuiltinTypes.is_builtin_name (structure.name)) {
				fail (path, "struct descriptor must have unique native type identity and name");
			}
			structs.insert (structure.semantic_type, structure);
			names.insert (structure.name, structure.name);
			if (structure is SsaStruct && structure.fields.length == 0) {
				fail (path, "struct must have at least one scalar field");
			}
			var field_names = new HashTable<string, string> (str_hash, str_equal);
			for (int f = 0; f < structure.fields.length; f++) {
				var field = structure.fields[f];
				if (field.semantic_type is CallbackType) {
					fail (path, "call-scoped Callback cannot be stored in a field");
				}
				if (field.is_private && (!(structure is SsaClass) || ((SsaClass) structure).generic_instance != null && ((SsaClass) structure).generic_instance.definition.structure == null)) {
					fail (path, "private fields require an ordinary nongeneric native Class");
				}
				if (field.containing_type != structure || field.ordinal != f || field.name == "" || field_names.contains (field.name)) {
					fail (path, "field must have exact struct owner, unique name and declaration ordinal");
				}
				if (field.text_snapshot && (!(structure is SsaClass) || !(field.semantic_type is StringType))) {
					fail (path, "snapshot requires an exact readonly text class field");
				}
				if (!(field.semantic_type is OwnerSlotsType) && !field.text_snapshot && !NativeFieldTypes.supports (field.semantic_type, true) && !(structure is SsaStruct && field.owned_cleanup != null && (field.semantic_type is HandleType || field.semantic_type is ClassType || field.semantic_type is SliceType)) && !(structure is SsaClass && (field.semantic_type is HandleType || field.semantic_type is ClassType || buffer_cleanups.contains (field.semantic_type)))) {
					fail (path, "struct fields must be int, bool or void*");
				}
				field_names.insert (field.name, field.name);
				bool owning_record = structure is SsaClass && field.semantic_type is StructType && CopyabilityAuthority.of (field.semantic_type, struct_fields) != Copyability.COPYABLE;
				if ((field.record_owner != null) != owning_record || (field.record_owner != null && (structs.lookup (field.semantic_type) != field.record_owner || field.owned_cleanup != null))) {
					fail (path, "record field requires exact inline declaration and recursive ownership authority");
				}
				if (field.semantic_type is SliceType && (field.owned_cleanup == null || !buffer_cleanups.contains (field.semantic_type))) {
					fail (path, "slice fields require static buffer ownership");
				}
				if (field.semantic_type is ReceiverType) {
					fail (path, "receiver cannot be a field");
				}
			}
		}
		foreach (var structure in instances) {
			var record_type = structure.semantic_type as StructType;
			var owning_record = record_type == null ? null : record_type.owning_application;
			if (owning_record != null) {
				if (!(structure is SsaStruct) || !owning_record.valid (record_type, ((SsaStruct) structure).owning_arguments, struct_fields) || structure.fields.length != owning_record.definition.field_count) {
					fail ("owning record", "lost exact closed declared storage and argument authority");
				}
				foreach (var field in structure.fields) {
					if (!owning_record.field (field.ordinal, field.name, field.semantic_type, field.owned_cleanup != null, field.is_private, struct_fields)) {
						fail ("owning record field", "lost declared type, ownership or visibility");
					}
				}
			} else if (structure is SsaStruct && ((SsaStruct) structure).owning_arguments.length != 0) {
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
				for (int p = 0; p < function.parameters.length; p++) {
					SsaBufferParameter? buffer = null;
					int groups = 0;
					foreach (var group in function.buffer_parameters) {
						if (group.first_leaf == p) {
							buffer = group;
							groups++;
						}
					}
					if (buffer != null) {
						if (groups != 1 || p + 1 >= function.parameters.length || buffer.pair.base_value != function.parameters[p] || buffer.pair.length_value != function.parameters[p + 1] || !cleanups.contains (buffer.cleanup) || !buffer.cleanup.is_buffer || !thread_capture_type (buffer.cleanup.buffer_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
							fail ("threaded frame", "owned buffer group lost exact complete storage or structural Send authority");
						}
						p++;
						continue;
					}
					StructBoundaryGroup? record = null;
					foreach (var group in function.struct_parameters) {
						if (group.first_leaf == p) {
							record = group;
						}
					}
					if (record != null) {
						if (record.shape.mode == StructValueMode.BORROW_VALUE || !thread_capture_type (record.shape.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
							fail ("threaded frame", "record capture lost complete structural Send authority");
						}
						p += (int) record.shape.leaves.length - 1;
						continue;
					}
					var parameter = function.parameters[p];
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
				var child = structs.lookup (field.semantic_type) as SsaClass;
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
				} else if (field.owned_cleanup != null ? !matches_cleanup (field.semantic_type, field.owned_cleanup) : !NativeFieldTypes.supports (field.semantic_type, true)) {
					fail ("record ownership", "requires exact supported record storage");
				}
			}
			if (record_owning_paths (owner).length != 0 && (owner.methods.length != 0 || owner.properties.length != 0)) {
				fail ("record ownership", "owning record members require separate receiver lifetime authority");
			}
		}
		int previous_method_struct = -1;
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
					var child = structs.lookup (field.semantic_type) as SsaClass;
					if (child == null || child.polymorphic || !heap_cleanups.contains (child)) {
						fail ("owned child fields", "requires exact nonpolymorphic heap cleanup authority");
					}
				}
			}
			if (!OwnedChildComposition.acyclic (owner.semantic_type, child_edges)) {
				fail ("owned child fields", "cyclic owned child composition");
			}
		}
		var complete_layouts = new HashTable<SsaNativeInstance, SsaNativeInstance> (direct_hash, direct_equal);
		var active_layouts = new GenericArray<SsaNativeInstance> ();
		foreach (var structure in instances) {
			verify_layout (structure, complete_layouts, active_layouts);
		}
		for (int st = 0; st < instances.length; st++) {
			var structure = instances[st];
			if (st == program.structs.length) {
				previous_method_struct = -1;
			}
			if (structure.methods.length > 0 || structure.properties.length > 0) {
				if (structure.ordinal <= previous_method_struct) {
					fail ("methods", "retained method struct ordinals must preserve unique source order");
				}
				previous_method_struct = structure.ordinal;
			}
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
				if (!present || method.declaring_type != structure || method.method_ordinal != m || method.member_ordinal <= previous_member || method.member_ordinal >= structure.fields.length + structure.methods.length + structure.properties.length + ((structure is SsaClass) ? ((SsaClass) structure).lifecycle_count : 0) || method.name == "" || member_names.contains (method.name) || receiver_owners.contains (method.receiver) || method.receiver.contract.mode != ReceiverMode.LIVE || method.receiver.contract.instance_type != structure.semantic_type) {
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
				if (property.declaring_type != structure || property.ordinal != p || property.name == "" || member_names.contains (property.name) || property.member_ordinal <= previous_property_member || property.member_ordinal >= structure.fields.length + structure.methods.length + structure.properties.length + ((structure is SsaClass) ? ((SsaClass) structure).lifecycle_count : 0) || !(property.is_borrowed ? structure is SsaClass && (property.semantic_type is ClassType || property.semantic_type is HandleType || property.semantic_type is StructType && structs.lookup (property.semantic_type) is SsaStruct && CopyabilityAuthority.of (property.semantic_type, struct_fields) != Copyability.COPYABLE) && (!property.is_lazy || property.is_owned_lazy) : PropertyValueTypes.supports (property.semantic_type, struct_fields) || property.getter != null && property.getter.result_contract == ResultOwnershipContract.OWNED_TRANSFER && structure is SsaClass && ForeignApiTypes.owned_property (((SsaClass) structure).foreign_export, property.member_ordinal)) || property.getter == null) {
					fail ("properties", "property requires exact owner, legal value type, unique member name/ordinal and getter");
				}
				if (property.is_owned_lazy) {
					var factory = property.factory;
					var body = property.getter.blocks.length == 1 ? property.getter.blocks[0] : null;
					var returned = body == null ? null : body.terminator as SsaReturn;
					var observe = body == null || body.instructions.length != 1 ? null : body.instructions[0] as SsaLazyObserve;
					if (returned == null || observe == null || observe.property_member != property || returned.value != observe.result) {
						fail ("owned lazy", "borrowed getter must preserve exact receiver cache observation and return");
					}
					if (!property.is_lazy || !property.is_borrowed || !(property.semantic_type is ClassType) || property.setter != null || factory == null || !program.functions.find (factory) || factory.declaring_type != structure || factory.return_type != property.semantic_type || factory.result_contract != ResultOwnershipContract.OWNED_TRANSFER || !factory.heap_result || factory.owned_cleanup == null || !factory.owned_cleanup.is_heap_object || factory.owned_cleanup.object_class.polymorphic || property.semantic_type is ExactGenericClassType && !GenericClassTypes.general (property.semantic_type) || factory.parameters.length != 0 || factory.throws_type != property.getter.throws_type || factory.dispatch_kind != ClassDispatchKind.DIRECT || property.getter.dispatch_kind != ClassDispatchKind.DIRECT) {
						fail ("owned lazy", "requires distinct exact owned factory and receiver-borrow observation channels");
					}
				} else if (property.factory != null) {
					fail ("owned lazy", "ordinary property cannot acquire an owned factory");
				}
				if (structure is SsaClass && (property.name == "init" || property.name == "deinit")) {
					fail ("properties", "class lifecycle names are reserved");
				}
				foreach (var method in structure.methods) {
					if (method.member_ordinal == property.member_ordinal) {
						fail ("properties", "property/member ordinals must be distinct");
					}
				}
				if (property.semantic_type is StructType) {
					if (!(structs.lookup (property.semantic_type) is SsaStruct)) {
						fail ("property/value-type", "copied record property lost exact declaration");
					}
				} else {
					verify_type (property.semantic_type, true, "property/value-type");
				}
				member_names.insert (property.name, property.name);
				previous_property_member = property.member_ordinal;
				if (property.semantic_type is StringType && (!(structure is SsaClass) || property.setter != null)) {
					fail ("property", "receiver text requires a get-only native class property");
				}
				if (property.is_lazy && (!(structure is SsaClass) || property.setter != null || property.getter.dispatch_kind != ClassDispatchKind.DIRECT || (!property.is_owned_lazy && !PropertyValueTypes.supports_cache (property.semantic_type)))) {
					fail ("lazy property", "requires an exact nonvirtual get-only copied-value class property");
				}
				var accessors = new GenericArray<SsaPropertyAccessor> ();
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
					bool getter = accessor is SsaPropertyGetter;
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
					if (!present || accessor.property_member != property || (getter ? property.getter != accessor : property.setter != accessor) || receiver_owners.contains (accessor.receiver) || accessor.receiver.contract.mode != ReceiverMode.LIVE || accessor.receiver.contract.instance_type != structure.semantic_type || (accessor.owned_cleanup != null && !(getter && structure is SsaClass && ForeignApiTypes.owned_property (((SsaClass) structure).foreign_export, property.member_ordinal) && accessor.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) || accessor.result_storage != null || accessor.parameters.length != parameter_count || (getter ? accessor.return_type != property.semantic_type : accessor.return_type.kind != TypeKind.VOID)) {
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
			var lifecycle_members = new GenericArray<SsaLifecycle> ();
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
				bool initializing = lifecycle is SsaConstructor;
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
			if (imported.return_type is SliceType) {
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
				SsaFunction? callback = null;
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
		// Establish ownership and definitions before examining graph/value uses.
		for (int f = 0; f < program.functions.length; f++) {
			var function = program.functions[f];
			string path = "function #%d".printf (f);
			if (function.native_declaration != null) {
				verify_native_declaration (function, path);
				if (!function.declaration_only ()) {
					fail (path, "native declaration requires one empty declaration block without local storage");
				}
			}
			if (functions.contains (function) || function.ordinal != f) {
				fail (path, "function identity/ordinal must be unique and in source order");
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
			if (function.result_contract == ResultOwnershipContract.RECEIVER_BORROW && (!(function is SsaPropertyGetter) || !((SsaPropertyGetter) function).property_member.is_borrowed || function.owned_cleanup != null || function.result_storage != null || function.heap_result)) {
				fail (path, "receiver borrow requires the exact nonowning property getter");
			}
			if (function.return_type is ReceiverType) {
				fail (path, "receiver cannot be a function result");
			}
			if (function.owned_cleanup != null && (!(function.return_type is HandleType || function.return_type is ClassType || function.return_type is SliceType) || !cleanups.contains (function.owned_cleanup) || !matches_cleanup (function.return_type, function.owned_cleanup))) {
				fail (path, "owned native result requires exact nominal handle type and its cleanup contract");
			}
			if (function.return_type is SliceType && function.owned_cleanup == null) {
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
			foreach (var storage in function.object_storage) {
				if (function.async_body != null && function.async_body.runtime.threaded && !thread_capture_type (storage.semantic_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) {
					fail ("threaded frame", "object storage lost its structural Send authority");
				}
				if (((ClassType) storage.semantic_type).intrinsically_shared && !storage.heap_allocated) {
					fail ("shared allocation", "intrinsic weak anchors require independently allocated retained backing");
				}
				if (object_owners.contains (storage) || storage.ordinal < 0 || storage.ordinal >= function.object_storage.length || function.object_storage[storage.ordinal] != storage || storage.region_ordinal < 0 || (!storage.result_candidate && storage.destructor != null && storage.cleanup_rank < 0) || storage.object_class == null || structs.lookup (storage.semantic_type) != storage.object_class) {
					fail (path, "object storage requires exact class and lexical function identity");
				}
				if (storage.fallible) {
					var owner = storage.object_class;
					if (!storage.heap_allocated || storage.result_candidate || owner.allocation_policy == null || owner.constructor == null || function.async_body != null) {
						fail (path, "fallible construction requires fresh synchronous policy-owned storage and exact constructor");
					}
					foreach (var parameter in owner.constructor.parameters) {
						bool buffer = false;
						foreach (var group in owner.constructor.buffer_parameters) {
							if (parameter == owner.constructor.parameters[group.first_leaf] || parameter == owner.constructor.parameters[group.first_leaf + 1]) {
								buffer = true;
							}
						}
						if (buffer) {
							continue;
						}
						bool record = false;
						foreach (var group in owner.constructor.struct_parameters) {
							if (parameter.ordinal >= group.first_leaf && parameter.ordinal < group.first_leaf + group.shape.leaves.length) {
								if (group.shape.mode == StructValueMode.BORROW_VALUE) {
									fail (path, "fallible constructor record requires an owned or copied complete value");
								}
								record = true;
							}
						}
						if (record) {
							continue;
						}
						bool scalar = (parameter.semantic_type is IntegerType || parameter.semantic_type is FloatingType || parameter.semantic_type.kind == TypeKind.BOOL) && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
						bool input = (parameter.semantic_type is ClassType || parameter.semantic_type is HandleType) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER;
						if (!scalar && !input) {
							fail (path, "fallible construction requires scalar or exact nullable Class/Resource inputs");
						}
					}
				}
				object_owners.insert (storage, function);
				object_initializations.insert (storage, new HashTable<SsaStructField, DefinitionSite> (direct_hash, direct_equal));
			}
			int previous_local = -1;
			for (int s = 0; s < function.storage.length; s++) {
				var storage = function.storage[s];
				if (storage_owners.contains (storage) || storage.ordinal != s || storage.source_local_ordinal <= previous_local) {
					fail (path, "addressable storage must have unique function ownership, ordered ordinals and exact owned struct type");
				}
				if (storage.semantic_type is ArrayType) {
					verify_array_type ((ArrayType) storage.semantic_type, path);
					if (storage.structure != null) {
						fail (path, "array storage cannot have a struct descriptor");
					}
				} else if (storage.semantic_type is StructType) {
					if (storage.structure == null || storage.structure.semantic_type != storage.semantic_type || structs.lookup (storage.semantic_type) != storage.structure) {
						fail (path, "addressable struct requires its exact program-owned descriptor");
					}
				} else {
					verify_type (storage.semantic_type, true, path);
					if (!storage.semantic_type.is_directly_dereferenceable_value_type () || storage.structure != null) {
						fail (path, "unsupported addressable value storage type");
					}
				}
				storage_owners.insert (storage, function);
				initializations.insert (storage, new HashTable<Object, DefinitionSite> (SsaMemoryPlace.storage_hash, SsaMemoryPlace.storage_equal));
				previous_local = storage.source_local_ordinal;
			}
			var buffer_owner_ordinals = new HashTable<int, SsaBufferStorage> (direct_hash, direct_equal);
			foreach (var slot in function.buffer_storage) {
				if (buffer_storage.contains (slot) || slot.ordinal < 0 || slot.ordinal >= function.buffer_storage.length || function.buffer_storage[slot.ordinal] != slot || slot.owner_ordinal < 0 || !cleanups.contains (slot.cleanup) || !slot.cleanup.is_buffer) {
					fail (path, "buffer storage requires unique exact static owner identity and cleanup");
				}
				if (buffer_owner_ordinals.contains (slot.owner_ordinal)) {
					fail (path, "buffer slots cannot duplicate one ownership identity");
				}
				buffer_owner_ordinals.insert (slot.owner_ordinal, slot);
				buffer_storage.insert (slot, function);
				if (slot.record_type != null) {
					verify_record_group (slot.record_type, slot.record_source_ordinal, function, path);
				} else if (slot.record_path != null || slot.record_rank != -1 || slot.record_source_ordinal != -1) {
					fail (path, "ordinary buffer storage cannot carry orphaned record ownership metadata");
				}
			}
			foreach (var group in function.buffer_parameters) {
				register_buffer_pair (group.pair, path);
			}
			var ordinals = new HashTable<int, SsaDefinition> (direct_hash, direct_equal);
			if (function.implicit_receiver != null) {
				define (function.implicit_receiver, function, null, -1, ordinals, path + "/receiver");
			}
			for (int p = 0; p < function.parameters.length; p++) {
				bool record_class_leaf = false;
				foreach (var group in function.struct_parameters) {
					if (group.shape.mode != StructValueMode.MOVE_VALUE || p < group.first_leaf || p >= group.first_leaf + group.shape.leaves.length) {
						continue;
					}
					var leaf = group.shape.leaves[p - group.first_leaf];
					var field = record_leaf (group.shape.semantic_type, leaf);
					record_class_leaf = field != null && field.owned_cleanup != null && field.owned_cleanup.is_heap_object;
				}
				verify_parameter_contract (function.parameters[p], path, record_class_leaf);
				define (function.parameters[p], function, null, -1, ordinals, path + "/parameter #%d".printf (p));
			}
			for (int b = 0; b < function.blocks.length; b++) {
				var block = function.blocks[b];
				string block_path = path + "/block #%d".printf (b);
				if (owners.contains (block) || block.ordinal != b) {
					fail (block_path, "block identity/ordinal must be unique and in array order");
				}
				owners.insert (block, function);
				if (!block.is_complete) {
					fail (block_path, "block has no terminator");
				}
				SsaBlockParameter? previous_field = null;
				int previous_origin = -1;
				var previous_kind = SsaPromotionOrigin.SOURCE_LOCAL;
				for (int p = 0; p < block.parameters.length; p++) {
					var parameter = block.parameters[p];
					string parameter_path = block_path + "/argument #%d".printf (p);
					if (parameter.semantic_type is ReceiverType) {
						fail (parameter_path, "receiver cannot be a promoted block parameter");
					}
					define (parameter, function, block, -1, ordinals, parameter_path);
					if ((parameter.origin_kind != SsaPromotionOrigin.SOURCE_LOCAL && parameter.origin_kind != SsaPromotionOrigin.FIELD && parameter.origin_kind != SsaPromotionOrigin.TEMPORARY) || parameter.origin_ordinal < 0 || parameter.origin_kind < previous_kind || (parameter.origin_kind == previous_kind && (parameter.origin_ordinal < previous_origin || (parameter.origin_ordinal == previous_origin && (parameter.origin_kind != SsaPromotionOrigin.FIELD || (previous_field != null && parameter.compare_field_path (previous_field) <= 0)))))) {
						fail (parameter_path, "block parameters must follow ascending source local ordinals, then temporary ordinals");
					}
					if ((parameter.origin_kind == SsaPromotionOrigin.FIELD && (parameter.source_field_ordinal < 0 || parameter.source_field_path.length == 0 || parameter.source_field_path[parameter.source_field_path.length - 1] != parameter.source_field_ordinal)) || (parameter.origin_kind != SsaPromotionOrigin.FIELD && parameter.source_field_ordinal != -1)) {
						fail (parameter_path, "invalid scalar field promotion provenance");
					}
					foreach (var storage in function.storage) {
						if (parameter.origin_kind != SsaPromotionOrigin.TEMPORARY && parameter.source_local_ordinal == storage.source_local_ordinal) {
							fail (parameter_path, "addressable storage and its fields cannot also have promoted definitions");
						}
					}
					previous_field = parameter;
					previous_kind = parameter.origin_kind;
					previous_origin = parameter.origin_ordinal;
				}
				for (int i = 0; i < block.instructions.length; i++) {
					var storage_receiver = block.instructions[i] as SsaStorageReceiverInstruction;
					if (storage_receiver != null && storage_receiver.result != null) {
						storage_receivers.insert (storage_receiver.result, storage_receiver.storage);
					}
					var lifecycle_call = block.instructions[i] as SsaLifecycleCallInstruction;
					if (lifecycle_call != null && lifecycle_call.constructs) {
						if (constructor_sites.contains (lifecycle_call.storage)) {
							fail (block_path, "object storage requires exactly one constructor call site");
						}
						constructor_sites.insert (lifecycle_call.storage, new DefinitionSite (function, block, i));
					}
					var object_reference = block.instructions[i] as SsaObjectReferenceInstruction;
					if (object_reference != null) {
						if (object_owners.lookup (object_reference.storage) != function || object_constructions.contains (object_reference.storage)) {
							fail (block_path, "object construction requires unique function-owned storage");
						}
						object_constructions.insert (object_reference.storage, object_reference);
					}
					var validation = block.instructions[i] as SsaObjectValidateInstruction;
					if (validation != null) {
						object_validations.insert (validation.result, validation);
					}
					var array = block.instructions[i] as SsaArrayInitialize;
					if (array != null) {
						if (array.record_root != null) {
							var entries = record_initializations.lookup (array.storage);
							if (entries == null) {
								entries = new GenericArray<SsaArrayInitialize> ();
								record_initializations.insert (array.storage, entries);
							}
							if (array.record_ordinal != entries.length || array.record_ordinal >= array.record_root.array_type.length) {
								fail (block_path, "record entries must initialize once in positional order");
							}
							entries.add (array);
							record_initialization_sites.insert (array, new DefinitionSite (function, block, i));
						}
						if (!array.completes_array) {
							continue;
						}
						if (storage_owners.lookup (array.storage) != function) {
							fail (block_path, "array initialization requires function-owned storage");
						}
						var sites = initializations.lookup (array.storage);
						if (sites.contains (array.storage)) {
							fail (block_path, "array requires one initialization site");
						}
						sites.insert (array.storage, new DefinitionSite (function, block, i));
					}
					var slice_bounds = block.instructions[i] as SsaSliceBoundsCheck;
					if (slice_bounds != null) {
						slice_bounds_views.insert (slice_bounds.result, slice_bounds.slice);
					}
					var numeric_guard = block.instructions[i] as SsaNumericGuard;
					if (numeric_guard != null) {
						numeric_guards.insert (numeric_guard.result, numeric_guard);
					}
					var bounds = block.instructions[i] as SsaArrayBoundsCheck;
					if (bounds != null) {
						bounds_storage.insert (bounds.result, bounds.storage);
					}
					var initialization = block.instructions[i] as SsaInitializeInstruction;
					if (initialization != null) {
						var object_field = initialization.target as SsaObjectFieldPlace;
						if (object_field != null) {
							var sites = object_initializations.lookup (object_field.storage);
							if (sites == null || object_owners.lookup (object_field.storage) != function || sites.contains (object_field.field)) {
								fail (block_path, "object field requires one exact initialization");
							}
							sites.insert (object_field.field, new DefinitionSite (function, block, i));
						} else if (constructor_field_initialization (initialization.target, function)) {
							// Exact field initialization is validated by constructor dataflow.
						} else {
							var storage = initialization.target.root_storage ();
							if (storage == null || storage_owners.lookup (storage) != function) {
								fail (block_path, "Initialize requires direct storage owned by the function");
							}
							Object key = initialization.target;
							var sites = initializations.lookup (storage);
							if (sites.contains (key)) {
								fail (block_path, "addressable field must have exactly one initialization site");
							}
							sites.insert (key, new DefinitionSite (function, block, i));
						}
					}
					var struct_call = block.instructions[i] as SsaCallInstruction;
					if (struct_call != null && struct_call.exception_result != null) {
						struct_call = null;
					}
					if (block.instructions[i] is SsaGroupCallSuccess) {
						struct_call = ((SsaGroupCallSuccess) block.instructions[i]).call;
					}
					var foreign_struct_call = block.instructions[i] as SsaCCallInstruction;
					var enum_record = block.instructions[i] as SsaEnumReadRecord;
					var slot_record = block.instructions[i] as SsaSlotsRecordRead;
					var task_success = block.instructions[i] as SsaTaskSuccess;
					var result_group = slot_record != null ? slot_record.results : enum_record != null ? enum_record.results : task_success == null ? (foreign_struct_call != null ? foreign_struct_call.struct_result : struct_call == null ? null : struct_call.struct_result) : task_success.struct_result;
					var indirect = block.instructions[i] as SsaFunctionValueCall;
					var closure_result = block.instructions[i] as SsaClosureCall;
					var closure_success = block.instructions[i] as SsaClosureCallSuccess;
					if (indirect != null) {
						result_group = indirect.struct_result;
					}
					if (closure_result != null) {
						result_group = closure_result.struct_result;
					}
					if (closure_success != null) {
						result_group = closure_success.struct_result;
					}
					if (block.instructions[i] is SsaRecordAdmissionRestore) {
						result_group = ((SsaRecordAdmissionRestore) block.instructions[i]).results;
					}
					if (result_group != null) {
						var group = result_group;
						if (struct_results.contains (group)) {
							fail (block_path, "struct result group must belong to one call");
						}
						struct_results.insert (group, (block.instructions[i] is SsaGroupCallSuccess) ? (SsaInstruction) struct_call : block.instructions[i]);
						foreach (var leaf in group.leaves) {
							define (leaf, function, block, i, ordinals, block_path + "/struct-result-leaf");
							struct_result_leaves.insert (leaf, group);
						}
						var values = new GenericArray<SsaValue> ();
						foreach (var leaf in group.leaves) {
							values.add (leaf);
						}
						verify_record_buffer_pairs (group.shape, values, group.buffers, block_path);
						foreach (var pair in group.buffers) {
							register_buffer_pair (pair, block_path);
							if (group.shape.mode != StructValueMode.BORROW_VALUE) {
								buffer_producers.insert (pair, block.instructions[i]);
							}
						}
					}
					var record_entry = block.instructions[i] as SsaStructBoundaryAcquire;
					var record_borrow = block.instructions[i] as SsaStructParameterBorrow;
					if (record_borrow != null) {
						verify_record_buffer_pairs (record_borrow.parameter.shape, record_borrow.leaves, record_borrow.buffers, block_path);
						foreach (var pair in record_borrow.buffers) {
							register_buffer_pair (pair, block_path);
						}
					}
					if (record_entry != null && record_entry.parameter != null) {
						verify_record_buffer_pairs (record_entry.shape, record_entry.leaves, record_entry.buffer_pairs, block_path);
						foreach (var pair in record_entry.buffer_pairs) {
							register_buffer_pair (pair, block_path);
						}
					}
					var consumption = block.instructions[i] as SsaStructResultConsume;
					if (consumption != null) {
						if (struct_consumptions.contains (consumption.results)) {
							fail (block_path, "struct result group requires one bounded consumer");
						}
						struct_consumptions.insert (consumption.results, new DefinitionSite (function, block, i));
					}
					var enum_read = block.instructions[i] as SsaEnumRead;
					if (enum_read != null && enum_read.field.owns_buffer) {
						enum_views.insert (enum_read.result, enum_read.source);
					}
					var buffer_pair = instruction_buffer_pair (block.instructions[i]);
					if (buffer_pair != null) {
						register_buffer_pair (buffer_pair, block_path);
						if (block.instructions[i] is SsaBufferReadInstruction) {
							buffer_reads.insert (buffer_pair, (SsaBufferReadInstruction) block.instructions[i]);
						} else {
							buffer_producers.insert (buffer_pair, block.instructions[i]);
						}
						if (!(buffer_pair.base_value is SsaInstructionResult) || !(buffer_pair.length_value is SsaInstructionResult)) {
							fail (block_path, "buffer instruction requires two scalar instruction results");
						}
						define ((SsaInstructionResult) buffer_pair.base_value, function, block, i, ordinals, block_path + "/buffer-base");
						define ((SsaInstructionResult) buffer_pair.length_value, function, block, i, ordinals, block_path + "/buffer-length");
					}
					if ((block.instructions[i] is SsaBufferSlotCaptureInstruction || block.instructions[i] is SsaBufferExchangeInstruction) && buffer_sites.contains (block.instructions[i])) {
						fail (block_path, "buffer exchange instruction identity cannot be repeated");
					}
					buffer_sites.insert (block.instructions[i], new DefinitionSite (function, block, i));
					var async_operation = block.instructions[i] as SsaAsyncOperation;
					if (async_operation != null && async_operation.exception != null) {
						define (async_operation.exception, function, block, i, ordinals, block_path + "/runtime-exception");
					}
					var exception_call = block.instructions[i] as SsaCallInstruction;
					if (exception_call != null && exception_call.exception_result != null) {
						define (exception_call.exception_result, function, block, i, ordinals, block_path + "/exception-result");
						exception_results.insert (exception_call.exception_result, exception_call);
						if (exception_call.result != null) {
							private_success_values.insert (exception_call.result, exception_call);
						}
					}
					var result = block.instructions[i].result;
					if (result != null) {
						define (result, function, block, i, ordinals, block_path + "/instruction #%d/result".printf (i));
					}
				}
			}
		}
		foreach (var function in program.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var borrow = instruction as SsaBufferBorrowInstruction;
					if (borrow != null) {
						var read = buffer_reads.lookup (borrow.pair);
						if (read != null && borrow.result != null) {
							buffer_views.insert (borrow.result, read);
						}
					}
				}
			}
		}
		foreach (var group in struct_results.get_keys ()) {
			if (!struct_consumptions.contains (group)) {
				fail ("struct-result", "struct call result has no bounded complete consumer");
			}
		}
		for (int e = 0; e < program.c_exports.length; e++) {
			var exported = program.c_exports[e];
			string path = "C export #%d".printf (e);
			var target = exported.target;
			if (target != null && target.buffer_parameters.length != 0) {
				fail (path, "C buffer ownership boundaries are unsupported");
			}
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
		for (int f = 0; f < program.functions.length; f++) {
			var function = program.functions[f];
			string path = "function #%d".printf (f);
			if (function.declaration_only ()) {
				continue;
			}
			verify_resource_epilogues (function);
			verify_slots_loans (function);
			function.verify_exception_dispositions ();
			foreach (var handler in function.handlers) {
				var branch = handler.dispatch == null ? null : handler.dispatch.terminator as SsaConditionalBranch;
				if (branch == null || branch.condition != handler.selection.result || branch.true_edge.target != handler.matched || branch.false_edge.target != handler.next || handler.borrow.exception != handler.selection.exception || handler.borrow.result.semantic_type != handler.selection.match_type) {
					fail (path, "protected group lost source-ordered subtype selection and exact handler target/owner");
				}
				bool bound = false;
				foreach (var instruction in handler.matched.instructions) {
					if (instruction == handler.borrow) {
						bound = true;
					}
				}
				if (!bound) {
					fail (path, "handler target lost its exact guarded borrowed binding");
				}
			}
			if (function.entry == null || owners.lookup (function.entry) != function) {
				fail (path + "/entry", "entry block is not owned by the containing function");
			}
			if (function.entry.parameters.length != 0) {
				fail (path + "/entry", "entry block must not require edge arguments");
			}
			for (int b = 0; b < function.blocks.length; b++) {
				verify_targets (function.blocks[b].terminator, function, path + "/block #%d/terminator".printf (b));
			}
			var reachable = reachable_without (function, null);
			int count = function.blocks.length;
			var constructor_flow = (function is SsaConstructor) ? new SsaConstructorInitialization ((SsaConstructor) function, struct_fields) : null;
			dominance = new bool[count, count];
			for (int b = 0; b < count; b++) {
				if (!reachable[b]) {
					fail (path + "/block #%d".printf (b), "SSA block is unreachable");
				}
				var without = reachable_without (function, function.blocks[b]);
				for (int use = 0; use < count; use++) {
					dominance[b, use] = !without[use];
				}
			}
			foreach (var storage in function.storage) {
				var sites = initializations.lookup (storage);
				if (sites.size () > 0 && sites.size () != (storage.structure == null ? 1 : storage_leaf_count (storage.structure))) {
					fail (path, "addressable struct must initialize every field");
				}
			}
			for (int b = 0; b < count; b++) {
				var block = function.blocks[b];
				string block_path = path + "/block #%d".printf (b);
				for (int i = 0; i < block.instructions.length; i++) {
					if (i == 0) {
						field_state = constructor_flow == null ? null : constructor_flow.at_entry (block);
					}
					verify_instruction (block.instructions[i], function, block, i, block_path + "/instruction #%d".printf (i));
				}
				if (block.instructions.length == 0) {
					field_state = constructor_flow == null ? null : constructor_flow.at_entry (block);
				}
				verify_terminator (block.terminator, function, block, block_path + "/terminator");
			}
			verify_argument_reservations (function);
			verify_enum_scalar_reservations (function);
			verify_buffer_exchanges (function);
			verify_object_cleanup_domains (function);
			verify_exception_bounds (function);
		}
	}

	private void verify_enum_scalar_reservations(SsaFunction function) throws SsaError {
		foreach (var start in function.blocks) {
			for (int position = 0; position < start.instructions.length; position++) {
				var capture = start.instructions[position] as SsaEnumScalarCapture;
				if (capture == null) {
					continue;
				}
				int consumers = 0;
				int commits = 0;
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var construction = instruction as SsaEnumConstruct;
						if (construction != null) {
							foreach (var input in construction.fields) {
								if (input.scalar_owner == capture) {
									consumers++;
								}
							}
						}
						var commit = instruction as SsaEnumScalarCommit;
						if (commit != null && commit.capture == capture) {
							commits++;
						}
					}
				}
				if (consumers != 1 || commits != 1) {
					fail ("enum scalar capture", "requires one exact constructor field and one original owner commit");
				}
				var pending = new GenericArray<SsaBlock> ();
				var states = new GenericArray<int> ();
				var visited = new HashTable<SsaBlock, int> (direct_hash, direct_equal);
				pending.add (start);
				states.add (0);
				for (int p = 0; p < pending.length; p++) {
					var block = pending[p];
					int state = states[p];
					int bit = 1 << state;
					if ((visited.lookup (block) & bit) != 0) {
						continue;
					}
					visited.insert (block, visited.lookup (block) | bit);
					for (int i = block == start ? position + 1 : 0; i < block.instructions.length; i++) {
						var instruction = block.instructions[i];
						var abort = instruction as SsaEnumScalarAbort;
						var commit = instruction as SsaEnumScalarCommit;
						if ((abort != null && abort.capture == capture) || (commit != null && commit.capture == capture)) {
							if (state != 0) {
								fail ("enum scalar capture", "reservation was already committed or aborted on this control edge");
							}
							state = abort != null ? 1 : 2;
						} else {
							var event = instruction as SsaHeapOwnerEvent;
							if (state == 0 && event != null && event.owner == capture.owner && event.action != SsaHeapOwnerAction.READ) {
								fail ("enum scalar capture", "reserved owner was invalidated before its constructor commit");
							}
						}
					}
					var successors = SsaConstructorInitialization.successors (block);
					if (successors.length == 0 && state == 0 && !(block.terminator is SsaAllocationFailureTrap)) {
						fail ("enum scalar capture", "pending owner reaches an exit without exact commit or abort");
					}
					foreach (var successor in successors) {
						if (successor == start) {
							if (state == 0) {
								fail ("enum scalar capture", "capture repeats before its disposition");
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

	private static GenericArray<SsaOwnedArgumentReservation>? invocation_reservations(SsaInstruction instruction) {
		var direct = instruction as SsaCallInstruction;
		if (direct != null) {
			return direct.reservations;
		}
		var callable = instruction as SsaCallableInvocation;
		return callable == null ? null : callable.reservations;
	}

	private void verify_argument_reservations(SsaFunction function) throws SsaError {
		var reservations = new HashTable<SsaOwnedArgumentReservation, SsaBlock> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var reservation = instruction as SsaOwnedArgumentReservation;
				if (reservation != null && !reservations.insert (reservation, block)) {
					fail ("argument reservation", "duplicate pending transfer identity");
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var aborted = instruction as SsaOwnedArgumentAbort;
				if (aborted != null && !reservations.contains (aborted.reservation)) {
					fail ("argument abort", "orphaned abort has no function-owned reservation");
				}
				var claims = invocation_reservations (instruction);
				if (claims == null) {
					continue;
				}
				var seen = new HashTable<SsaOwnedArgumentReservation, bool> (direct_hash, direct_equal);
				foreach (var reservation in claims) {
					if (!reservations.contains (reservation) || reservation.consumer != instruction || !seen.insert (reservation, true)) {
						fail ("argument reservation", "native call must claim each exact reservation once");
					}
				}
			}
		}
		foreach (var reservation in reservations.get_keys ()) {
			var consumer = reservation.consumer;
			var declared = consumer == null ? null : invocation_reservations (consumer);
			int claims = 0;
			if (declared != null) {
				foreach (var claimed in declared) {
					if (claimed == reservation) {
						claims++;
					}
				}
			}
			bool exact = false;
			var direct = consumer as SsaCallInstruction;
			if (direct != null) {
				foreach (var argument in direct.buffer_arguments) {
					var read = buffer_reads.lookup (argument.pair);
					if (argument.pair == reservation.pair && read != null && read.place.storage != null && read.place.storage.owner_ordinal == reservation.owner_ordinal) {
						exact = true;
					}
				}
				foreach (var argument in direct.owned_arguments) {
					if (argument.value == reservation.value && argument.source_ordinal == reservation.owner_ordinal) {
						exact = true;
					}
				}
			}
			var callable = consumer as SsaCallableInvocation;
			if (callable != null) {
				foreach (var argument in callable.owned_arguments) {
					if (argument.value == reservation.value && argument.source_ordinal == reservation.owner_ordinal) {
						exact = true;
					}
				}
			}
			if (claims != 1 || !exact) {
				fail ("argument reservation", "reservation lost its exact owned native argument association");
			}
			uint[] entries = new uint[function.blocks.length];
			uint[] exits = new uint[function.blocks.length];
			bool[] ready = new bool[function.blocks.length];
			bool changed = false;
			do {
				changed = false;
				foreach (var block in function.blocks) {
					uint state = 0;
					foreach (var prior in function.blocks) {
						if (!ready[prior.ordinal]) {
							continue;
						}
						foreach (var next in SsaConstructorInitialization.successors (prior)) {
							if (next == block) {
								state |= exits[prior.ordinal];
							}
						}
					}
					entries[block.ordinal] = state;
					foreach (var instruction in block.instructions) {
						if (instruction == reservation) {
							state = 1;
						} else if (instruction == consumer) {
							state = 2;
						} else if (instruction is SsaOwnedArgumentAbort && ((SsaOwnedArgumentAbort) instruction).reservation == reservation) {
							state = 4;
						}
					}
					if (!ready[block.ordinal] || exits[block.ordinal] != state) {
						ready[block.ordinal] = true;
						exits[block.ordinal] = state;
						changed = true;
					}
				}
			} while (changed);
			bool aborted_once = false;
			foreach (var block in function.blocks) {
				uint state = entries[block.ordinal];
				foreach (var instruction in block.instructions) {
					if (instruction == reservation) {
						if ((state & 1) != 0) {
							fail ("argument reservation", "pending transfer captured again before commit or abort");
						}
						state = 1;
					} else if (instruction == consumer) {
						if (state != 1) {
							fail ("argument commit", "native call must consume a pending transfer on every incoming path");
						}
						state = 2;
					} else if (instruction is SsaOwnedArgumentAbort && ((SsaOwnedArgumentAbort) instruction).reservation == reservation) {
						if (state != 1) {
							fail ("argument abort", "abort cannot restore a committed, missing or already aborted transfer");
						}
						state = 4;
						aborted_once = true;
					}
				}
				if (state == 1 && SsaConstructorInitialization.successors (block).length == 0 && !(block.terminator is SsaAllocationFailureTrap) && !(block.terminator is SsaExceptionUnreachable)) {
					fail ("argument reservation", "pending transfer reaches an exit without commit or abort");
				}
			}
			if (!aborted_once) {
				fail ("argument reservation", "exception reservation requires an actual abort edge");
			}
		}
	}

	private SsaValue exception_identity(SsaValue value) {
		var seen = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
		while (value is SsaDefinition && !seen.contains (value)) {
			seen.insert (value, true);
			var site = definitions.lookup ((SsaDefinition) value);
			if (site == null || site.position < 0 || site.block == null) {
				break;
			}
			var instruction = site.block.instructions[site.position];
			if (instruction is SsaClassUpcast) {
				value = ((SsaClassUpcast) instruction).reference;
			} else if (instruction is SsaExceptionTransfer) {
				value = ((SsaExceptionTransfer) instruction).source;
			} else if (instruction is SsaObjectValidateInstruction) {
				value = ((SsaObjectValidateInstruction) instruction).reference;
			} else {
				break;
			}
		}
		return value;
	}

	private SsaExceptionBounds filtered_exception_bounds(SsaValue value, SsaBlock at, SsaFunction function, HashTable<SsaValue, SsaExceptionBounds> bounds) {
		var result = new SsaExceptionBounds ();
		result.include (bounds.lookup (value));
		foreach (var block in function.blocks) {
			var branch = block.terminator as SsaConditionalBranch;
			if (branch == null) {
				continue;
			}
			foreach (var instruction in block.instructions) {
				var match = instruction as SsaExceptionMatch;
				if (match == null || match.result != branch.condition || exception_identity (match.exception) != exception_identity (value)) {
					continue;
				}
				bool yes = dominance[branch.true_edge.target.ordinal, at.ordinal];
				bool no = dominance[branch.false_edge.target.ordinal, at.ordinal];
				if (yes == no) {
					continue;
				}
				var narrowed = new SsaExceptionBounds ();
				foreach (var type in result.types) {
					if (yes) {
						if (type.derives_from (match.match_type)) {
							narrowed.add (type);
						} else if (match.match_type.derives_from (type)) {
							narrowed.add (match.match_type);
						}
					} else if (!type.derives_from (match.match_type)) {
						narrowed.add (type);
					}
				}
				result = narrowed;
			}
		}
		return result;
	}

	private void verify_exception_bounds(SsaFunction function) throws SsaError {
		var bounds = new HashTable<SsaValue, SsaExceptionBounds> (direct_hash, direct_equal);
		foreach (var parameter in function.parameters) {
			var type = parameter.semantic_type as ClassType;
			if (type != null) {
				var incoming = new SsaExceptionBounds ();
				incoming.add (type);
				bounds.insert (parameter, incoming);
			}
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var operation = instruction as SsaAsyncOperation;
					if (operation != null && operation.exception != null) {
						var known = bounds.lookup (operation.exception);
						if (known == null) {
							known = new SsaExceptionBounds ();
							bounds.insert (operation.exception, known);
						}
						changed = known.add (operation.contract.runtime.error_type) || changed;
						var task = operation.task == null ? null : operation.task.semantic_type as TaskType;
						if (operation.contract.kind == AsyncOperationKind.RUN && task != null && task.exception_bound != null) {
							changed = known.add (task.exception_bound) || changed;
						}
					}
					var call = instruction as SsaCallInstruction;
					if (call != null && call.exception_result != null) {
						var known = bounds.lookup (call.exception_result);
						if (known == null) {
							known = new SsaExceptionBounds ();
							bounds.insert (call.exception_result, known);
						}
						changed = known.add ((call is SsaTaskCreate) ? call.target.async_body.runtime.error_type : call.target.throws_type) || changed;
					}
					if (instruction.result == null || !(instruction.result.semantic_type is ClassType)) {
						continue;
					}
					var incoming = new SsaExceptionBounds ();
					if (instruction is SsaActorSend) {
						incoming.add (((SsaActorSend) instruction).error_type);
					}
					if (instruction is SsaClosureCall && ((ClosureHandleType) ((SsaClosureCall) instruction).callee.semantic_type).throws_type != null) {
						incoming.add (((ClosureHandleType) ((SsaClosureCall) instruction).callee.semantic_type).throws_type);
					} else if (instruction is SsaAsyncDelay) {
						incoming.add (((SsaAsyncDelay) instruction).body.runtime.error_type);
					} else if (instruction is SsaTaskWait) {
						var wait = (SsaTaskWait) instruction;
						var task = (TaskType) wait.child.semantic_type;
						if (!wait.discard) {
							incoming.add (wait.body.runtime.error_type);
							if (task.exception_bound != null) {
								incoming.add (task.exception_bound);
							}
						}
					} else if (instruction is SsaObjectReferenceInstruction) {
						incoming.add ((ClassType) instruction.result.semantic_type);
					} else if (instruction is SsaSlotsValueInstruction && instruction.result.semantic_type is ClassType && ((SsaSlotsValueInstruction) instruction).action == OwnerSlotsAction.TAKE) {
						incoming.add ((ClassType) ((OwnerSlotsType) ((SsaSlotsValueInstruction) instruction).store.semantic_type).element);
					} else if (instruction is SsaCallInstruction && ((SsaCallInstruction) instruction).target.heap_result) {
						incoming.add ((ClassType) ((SsaCallInstruction) instruction).target.return_type);
					} else if (instruction is SsaCallSuccess && ((SsaCallSuccess) instruction).call.target.heap_result) {
						incoming.add ((ClassType) ((SsaCallSuccess) instruction).call.target.return_type);
					} else if (callable_heap_result (instruction)) {
						incoming.add ((ClassType) instruction.result.semantic_type);
					} else if (instruction is SsaClassUpcast) {
						incoming = filtered_exception_bounds (((SsaClassUpcast) instruction).reference, block, function, bounds);
					} else if (instruction is SsaExceptionTransfer) {
						incoming = filtered_exception_bounds (((SsaExceptionTransfer) instruction).source, block, function, bounds);
					} else if (instruction is SsaObjectValidateInstruction) {
						incoming = filtered_exception_bounds (((SsaObjectValidateInstruction) instruction).reference, block, function, bounds);
					} else if (instruction is SsaCatchBorrow) {
						incoming = filtered_exception_bounds (((SsaCatchBorrow) instruction).exception, block, function, bounds);
					}
					var known = bounds.lookup (instruction.result);
					if (known == null) {
						known = new SsaExceptionBounds ();
						bounds.insert (instruction.result, known);
					}
					changed = known.include (incoming) || changed;
				}
				var edges = new GenericArray<SsaEdge> ();
				if (block.terminator is SsaBranch) {
					edges.add (((SsaBranch) block.terminator).edge);
				} else if (block.terminator is SsaConditionalBranch) {
					edges.add (((SsaConditionalBranch) block.terminator).true_edge);
					edges.add (((SsaConditionalBranch) block.terminator).false_edge);
				} else if (block.terminator is SsaBufferAllocationBranch) {
					edges.add (((SsaBufferAllocationBranch) block.terminator).success_edge);
					edges.add (((SsaBufferAllocationBranch) block.terminator).failure_edge);
				}
				foreach (var edge in edges) {
					for (int p = 0; p < edge.arguments.length; p++) {
						var parameter = edge.target.parameters[p];
						if (!(parameter.semantic_type is ClassType)) {
							continue;
						}
						var known = bounds.lookup (parameter);
						if (known == null) {
							known = new SsaExceptionBounds ();
							bounds.insert (parameter, known);
						}
						changed = known.include (filtered_exception_bounds (edge.arguments[p], block, function, bounds)) || changed;
					}
				}
			}
		} while (changed);
		foreach (var block in function.blocks) {
			var returned = block.terminator as SsaExceptionReturn;
			var exhausted = block.terminator as SsaExceptionUnreachable;
			SsaValue? value = returned == null ? exhausted == null ? null : exhausted.exception : returned.value;
			if (value == null) {
				continue;
			}
			var incoming = filtered_exception_bounds (value, block, function, bounds);
			if (exhausted != null) {
				if (incoming.types.length != 0) {
					fail ("exception exhaustion", "unmatched channel retains an open checked exception bound");
				}
			} else {
				if (incoming.types.length == 0 && (bounds.lookup (value) == null || bounds.lookup (value).types.length == 0)) {
					fail ("exception propagation", "requires independently reconstructed incoming effect bounds in %s block #%d".printf (function.name, block.ordinal));
				}
				foreach (var type in incoming.types) {
					if (function.throws_type == null || !type.derives_from (function.throws_type)) {
						fail ("exception propagation", "declared throws cannot narrow the incoming checked bound");
					}
				}
			}
		}
	}

	private bool callable_heap_result(SsaInstruction instruction) {
		var success = instruction as SsaClosureCallSuccess;
		var invocation = success == null ? instruction as SsaCallableInvocation : success.call;
		if (invocation == null || instruction.result == null || invocation.owned_result_value () != instruction.result || !(instruction.result.semantic_type is ClassType)) {
			return false;
		}
		var code = invocation as SsaFunctionValueCall;
		CallableSignature signature = code == null ? (CallableSignature) ((SsaClosureCall) invocation).callee.semantic_type : (CallableSignature) code.callee.semantic_type;
		return signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER;
	}

	// Allocation domain is reconstructed from SSA definitions and edges. A
	// cleanup flag cannot convert a caller/lexical pointer into heap authority.
	private void verify_object_cleanup_domains(SsaFunction function) throws SsaError {
		var origins = new HashTable<SsaValue, int> (direct_hash, direct_equal);
		// A field read (bit 16) is a borrow. Only a verified replacement or
		// final destructor epilogue may retire it; it cannot become an owner.
		var field_reads = new HashTable<SsaValue, SsaLoadInstruction> (direct_hash, direct_equal);
		foreach (var parameter in function.parameters) {
			if (parameter.semantic_type is ClassType) {
				origins.insert (parameter, parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER ? (parameter.heap_object ? 2 : 4) : 8);
			}
		}
		foreach (var group in function.struct_parameters) {
			if (group.shape.mode != StructValueMode.MOVE_VALUE) {
				continue;
			}
			for (int i = 0; i < group.shape.leaves.length; i++) {
				var leaf = group.shape.leaves[i];
				var field = record_leaf (group.shape.semantic_type, leaf);
				if (leaf.semantic_type is ClassType && field != null && field.owned_cleanup != null && field.owned_cleanup.is_heap_object) {
					origins.insert (function.parameters[group.first_leaf + i], 2);
				}
			}
		}
		bool changed = false;
		do {
			changed = false;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaAsyncOperation && ((SsaAsyncOperation) instruction).exception != null) {
						origins.insert (((SsaAsyncOperation) instruction).exception, 3);
					}
					if (instruction is SsaCallInstruction && ((SsaCallInstruction) instruction).exception_result != null) {
						origins.insert (((SsaCallInstruction) instruction).exception_result, 3);
					}
					var record_call = instruction as SsaCallInstruction;
					var enum_record = instruction as SsaEnumReadRecord;
					var record = enum_record != null ? enum_record.results : record_call == null ? null : record_call.struct_result;
					if (instruction is SsaFunctionValueCall) {
						record = ((SsaFunctionValueCall) instruction).struct_result;
					}
					if (instruction is SsaClosureCall) {
						record = ((SsaClosureCall) instruction).struct_result;
					}
					if (instruction is SsaClosureCallSuccess) {
						record = ((SsaClosureCallSuccess) instruction).struct_result;
					}
					if (instruction is SsaTaskSuccess) {
						record = ((SsaTaskSuccess) instruction).struct_result;
					}
					if (instruction is SsaRecordAdmissionRestore) {
						record = ((SsaRecordAdmissionRestore) instruction).results;
					}
					if (record != null && record.shape.mode == StructValueMode.MOVE_VALUE) {
						for (int i = 0; i < record.shape.leaves.length; i++) {
							var leaf = record.shape.leaves[i];
							var field = record_leaf (record.shape.semantic_type, leaf);
							if (leaf.semantic_type is ClassType && field != null && field.owned_cleanup != null && field.owned_cleanup.is_heap_object) {
								var restored = instruction as SsaRecordAdmissionRestore;
								int origin = restored == null ? 2 : (object_origin (origins, restored.original.leaves[i]) | 1);
								origins.insert (record.leaves[i], origin);
							}
						}
					}
					if (instruction.result == null || !(instruction.result.semantic_type is ClassType)) {
						continue;
					}
					int origin = 0;
					if (instruction is SsaActorSend || instruction is SsaTaskWait || instruction is SsaAsyncDelay || (instruction is SsaClosureCall && ((ClosureHandleType) ((SsaClosureCall) instruction).callee.semantic_type).throws_type != null)) {
						origin = 3;
					} else if (instruction is SsaObjectReferenceInstruction) {
						origin = ((SsaObjectReferenceInstruction) instruction).storage.heap_allocated ? 2 : 4;
					} else if (instruction is SsaFallibleInputRestore) {
						origin = object_origin (origins, ((SsaFallibleInputRestore) instruction).argument.value) | 1;
					} else if (instruction is SsaFrameInputRestore) {
						origin = object_origin (origins, ((SsaFrameInputRestore) instruction).argument.value) | 1;
					} else if (instruction is SsaSharedOperation && ((ClassType) instruction.result.semantic_type).intrinsically_shared) {
						var sharing = (SsaSharedOperation) instruction;
						if (sharing.action == SharedAction.UPGRADE || sharing.action == SharedAction.SINGLETON_SHUTDOWN) {
							origin = 3;
						} else if (sharing.action == SharedAction.CLONE) {
							origin = 3;
						}
					} else if (instruction is SsaSlotsValueInstruction && ((SsaSlotsValueInstruction) instruction).action == OwnerSlotsAction.TAKE) {
						origin = 2;
					} else if (instruction is SsaEnumReadScalar && ((SsaEnumReadScalar) instruction).field.owns_child) {
						origin = 2;
					} else if (instruction is SsaExceptionTransfer) {
						origin = object_origin (origins, ((SsaExceptionTransfer) instruction).source);
					} else if (instruction is SsaObjectValidateInstruction) {
						origin = object_origin (origins, ((SsaObjectValidateInstruction) instruction).reference);
					} else if (instruction is SsaClassUpcast) {
						origin = object_origin (origins, ((SsaClassUpcast) instruction).reference);
					} else if (instruction is SsaCallInstruction) {
						origin = ((SsaCallInstruction) instruction).target.heap_result ? 2 : 4;
					} else if (instruction is SsaCallSuccess) {
						origin = ((SsaCallSuccess) instruction).call.target.heap_result ? 2 : 4;
					} else if (callable_heap_result (instruction)) {
						origin = 2;
					} else if (instruction is SsaLoadInstruction && ((SsaLoadInstruction) instruction).source is SsaIndirectFieldPlace) {
						origin = 16;
						field_reads.insert (instruction.result, (SsaLoadInstruction) instruction);
					} else {
						origin = 8;
					}
					int joined = origins.lookup (instruction.result) | origin;
					if (joined != origins.lookup (instruction.result)) {
						origins.insert (instruction.result, joined);
						changed = true;
					}
				}
				var edges = new GenericArray<SsaEdge> ();
				if (block.terminator is SsaBranch) {
					edges.add (((SsaBranch) block.terminator).edge);
				} else if (block.terminator is SsaConditionalBranch) {
					edges.add (((SsaConditionalBranch) block.terminator).true_edge);
					edges.add (((SsaConditionalBranch) block.terminator).false_edge);
				} else if (block.terminator is SsaBufferAllocationBranch) {
					edges.add (((SsaBufferAllocationBranch) block.terminator).success_edge);
					edges.add (((SsaBufferAllocationBranch) block.terminator).failure_edge);
				}
				foreach (var edge in edges) {
					for (int p = 0; p < edge.arguments.length; p++) {
						var parameter = edge.target.parameters[p];
						if (!(parameter.semantic_type is ClassType)) {
							continue;
						}
						int joined = origins.lookup (parameter) | object_origin (origins, edge.arguments[p]);
						if (joined != origins.lookup (parameter)) {
							origins.insert (parameter, joined);
							changed = true;
						}
					}
				}
			}
		} while (changed);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var store = instruction as SsaStoreInstruction;
				var initialize = instruction as SsaInitializeInstruction;
				var target = (store != null ? store.target : initialize == null ? null : initialize.target) as SsaIndirectFieldPlace;
				if (target == null || !(target.semantic_type is ClassType)) {
					continue;
				}
				var value = store != null ? store.value : initialize.value;
				int origin = object_origin (origins, value);
				if (origin == 0 || (origin & ~3) != 0) {
					fail ("owned child field", "store requires independently proved heap ownership");
				}
				if (store != null) {
					int position = 0;
					while (block.instructions[position] != store) {
						position++;
					}
					int previous = position - 1;
					var cleanup = field_cleanup_before (block, ref previous);
					var read = cleanup == null ? null : field_reads.lookup (cleanup.value);
					var old = read == null ? null : read.source as SsaIndirectFieldPlace;
					if (old == null || old.field != target.field || text_backing_owner (old.pointer) != text_backing_owner (target.pointer) || !cleanup.cleanup.is_heap_object || cleanup.cleanup.object_class.semantic_type != target.semantic_type) {
						fail ("owned child field", "replacement requires exact old field cleanup-then-store");
					}
				}
			}
		}
		foreach (var block in function.blocks) {
			for (int p = 0; p < block.instructions.length; p++) {
				var cleanup = block.instructions[p] as SsaCleanupInstruction;
				if (cleanup == null || (object_origin (origins, cleanup.value) & 16) == 0) {
					continue;
				}
				var read = field_reads.lookup (cleanup.value);
				var field = read == null ? null : read.source as SsaIndirectFieldPlace;
				int following = p + 1;
				var event = following < block.instructions.length ? block.instructions[following] as SsaHeapOwnerEvent : null;
				if (event != null && event.owner == null && event.action == SsaHeapOwnerAction.END && event.effect == cleanup) {
					following++;
				}
				var next = following < block.instructions.length ? block.instructions[following] as SsaStoreInstruction : null;
				bool replacement = field != null && next != null && next.target is SsaIndirectFieldPlace && ((SsaIndirectFieldPlace) next.target).field == field.field && text_backing_owner (((SsaIndirectFieldPlace) next.target).pointer) == text_backing_owner (field.pointer);
				bool final_cleanup = child_field_epilogues.contains (cleanup);
				if (field == null || !cleanup.cleanup.is_heap_object || cleanup.cleanup.object_class.semantic_type != field.semantic_type || (!replacement && !final_cleanup)) {
					fail ("owned child field", "destruction requires exact replacement or final destructor authority");
				}
			}
		}
		foreach (var block in function.blocks) {
			var returned = block.terminator as SsaOwnershipReturn;
			if (returned != null && function.heap_result) {
				int origin = object_origin (origins, returned.value);
				if (origin == 0 || (origin & ~3) != 0 || (returned.provenance != ObjectResultProvenance.HEAP_OBJECT && returned.provenance != ObjectResultProvenance.FORWARDED_OWNED_RESULT && returned.provenance != ObjectResultProvenance.NULL)) {
					fail ("heap result", "requires independently reconstructed unique heap allocation domain");
				}
			}
			foreach (var instruction in block.instructions) {
				var cleanup = instruction as SsaCleanupInstruction;
				if (cleanup == null || !cleanup.cleanup.is_object) {
					continue;
				}
				int origin = object_origin (origins, cleanup.value);
				int permitted = cleanup.cleanup.is_heap_object ? 19 : 5;
				if (origin == 0 || (origin & ~permitted) != 0) {
					fail ("object cleanup", "requires exact independently proved heap or lexical allocation domain");
				}
			}
		}
	}

	private static int object_origin(HashTable<SsaValue, int> origins, SsaValue value) {
		return (value is SsaNullPointerConstant) ? 1 : origins.lookup (value);
	}

	private void verify_target(SsaEdge edge, SsaFunction function, string path) throws SsaError {
		if (edge.target == null || owners.lookup (edge.target) != function) {
			fail (path, "successor block is not owned by the containing function");
			return;
		}
		if (edge.arguments.length != edge.target.parameters.length) {
			fail (path, "edge argument count does not match target block parameters");
		}
	}

	private void verify_targets(SsaTerminator terminator, SsaFunction function, string path) throws SsaError {
		if (terminator is SsaExceptionUnreachable) {
			return;
		}
		if (terminator is SsaExceptionReturn) {
			if (function.throws_type == null || !(((SsaExceptionReturn) terminator).value.semantic_type is ClassType)) {
				fail (path, "exception return requires exact checked throws declaration");
			}
			return;
		}
		var dispatch = terminator as SsaEnumDispatch;
		if (dispatch != null) {
			foreach (var branch in dispatch.cases) {
				verify_target (branch.edge, function, path + "/case");
			}
			verify_target (dispatch.invalid_edge, function, path + "/invalid");
			return;
		}
		if (terminator is SsaEnumInvalidTag) {
			return;
		}
		if (terminator is SsaEnumReturn) {
			if (((SsaEnumReturn) terminator).source.definition.semantic_type != function.return_type) {
				fail (path, "enum return nominal mismatch");
			}
			return;
		}
		var request = terminator as SsaBufferAllocationBranch;
		if (request != null) {
			verify_target (request.success_edge, function, path + "/success");
			verify_target (request.failure_edge, function, path + "/allocator-null");
			return;
		}
		if (terminator is SsaAllocationFailureTrap) {
			return;
		}
		var branch = terminator as SsaBranch;
		var conditional = terminator as SsaConditionalBranch;
		if (branch != null) {
			verify_target (branch.edge, function, path + "/edge");
		} else if (conditional != null) {
			verify_target (conditional.true_edge, function, path + "/true");
			verify_target (conditional.false_edge, function, path + "/false");
		} else if (!(terminator is SsaReturn) && !(terminator is SsaFunctionEnd)) {
			fail (path, "unsupported SSA terminator");
		}
	}

	private bool[] reachable_without(SsaFunction function, SsaBlock? omitted) {
		var visited = new bool[function.blocks.length];
		if (function.entry == omitted) {
			return visited;
		}
		var pending = new GenericArray<SsaBlock> ();
		pending.add (function.entry);
		visited[function.entry.ordinal] = true;
		for (int i = 0; i < pending.length; i++) {
			var successors = pending[i].terminator.successors ();
			for (int s = 0; s < successors.length; s++) {
				var target = successors[s];
				if (target != omitted && !visited[target.ordinal]) {
					visited[target.ordinal] = true;
					pending.add (target);
				}
			}
		}
		return visited;
	}

	private bool enum_view_place(SsaMemoryPlace place) {
		if (place is SsaFieldPlace && ((SsaFieldPlace) place).aggregate != null) {
			return enum_view_place (((SsaFieldPlace) place).aggregate);
		}
		return place is SsaSliceElementPlace && enum_views.contains (((SsaSliceElementPlace) place).slice);
	}

	private bool invalidates_property_loan(SsaInstruction instruction, SemanticType owner) {
		if (instruction is SsaRecordFieldCommit) {
			return OwnedChildComposition.may_invalidate (((SsaRecordFieldCommit) instruction).destination.field.containing_type.semantic_type, owner, slot_edges);
		}
		if (instruction is SsaRecordFieldDrop) {
			return OwnedChildComposition.may_invalidate (((SsaRecordFieldDrop) instruction).source.field.containing_type.semantic_type, owner, slot_edges);
		}
		var event = instruction as SsaHeapOwnerEvent;
		if (event != null && event.action != SsaHeapOwnerAction.ACQUIRE && event.action != SsaHeapOwnerAction.READ && OwnedChildComposition.may_invalidate (event.value.semantic_type, owner, slot_edges)) {
			return true;
		}
		var reservation = instruction as SsaOwnedArgumentReservation;
		if (reservation != null && reservation.value != null && OwnedChildComposition.may_invalidate (reservation.value.semantic_type, owner, slot_edges)) {
			return true;
		}

		var call = instruction as SsaCallInstruction;
		if (call != null && call.target is SsaPropertyGetter && (((SsaPropertyGetter) call.target).property_member.is_owned_lazy || call.target.struct_result != null && call.target.struct_result.mode == StructValueMode.BORROW_VALUE)) {
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
		var indirect = instruction as SsaFunctionValueCall;
		if (indirect != null) {
			foreach (var argument in indirect.arguments) {
				if (OwnedChildComposition.may_invalidate (argument.semantic_type, owner, slot_edges)) {
					return true;
				}
			}
		}
		var closure = instruction as SsaClosureCall;
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
		var store = instruction as SsaStoreInstruction;
		var place = store == null ? null : store.target as SsaIndirectFieldPlace;
		return (place != null && OwnedChildComposition.may_invalidate (place.field.containing_type.semantic_type, owner, slot_edges)) || instruction is SsaCleanupInstruction;
	}

	private void verify_receiver_loan_interval(DefinitionSite site, SemanticType owner, SsaFunction function,
		SsaBlock block, int position, string path, bool cross_blocks, string kind) throws SsaError {
		if (site.block == null || site.position < 0 || (site.block == block ? site.position >= position : !cross_blocks || !dominance[site.block.ordinal, block.ordinal])) {
			fail (path, kind + " loan lacks its exact dominating definition");
		}
		bool[] reaches = new bool[function.blocks.length];
		reaches[block.ordinal] = true;
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
		var pending = new GenericArray<SsaBlock> ();
		bool[] seen = new bool[function.blocks.length];
		pending.add (site.block);
		seen[site.block.ordinal] = true;
		for (int b = 0; b < pending.length; b++) {
			var candidate = pending[b];
			int first = candidate == site.block ? site.position + 1 : 0;
			int last = candidate == block ? position : (int) candidate.instructions.length - 1;
			for (int i = first; i <= last && i < candidate.instructions.length; i++) {
				if (invalidates_property_loan (candidate.instructions[i], owner)) {
					fail (path, kind + " loan overlaps receiver replacement, destruction or an aliasing call");
				}
			}
			if (candidate == block) {
				continue;
			}
			foreach (var next in candidate.terminator.successors ()) {
				if (reaches[next.ordinal] && !seen[next.ordinal]) {
					seen[next.ordinal] = true;
					pending.add (next);
				}
			}
		}
	}

	private void verify_property_loan(SsaValue value, SsaFunction function, SsaBlock block, int position, string path, bool noescape, bool receiver_use, int depth = 0) throws SsaError {
		if (depth > 128) {
			fail (path, "cyclic or excessive projected receiver chain");
		}
		var view_definition = value as SsaDefinition;
		var view_site = view_definition == null ? null : definitions.lookup (view_definition);
		var observed = view_site == null || view_site.block == null || view_site.position < 0 ? null : view_site.block.instructions[view_site.position] as SsaBufferBorrowInstruction;
		if (observed != null && observed.record_source != null) {
			verify_property_loan (observed.pair.base_value, function, block, position, path, noescape, receiver_use, depth);
			return;
		}
		while (object_validations.contains (value)) {
			if (++depth > 128) {
				fail (path, "cyclic or excessive projected receiver chain");
			}
			value = object_validations.lookup (value).reference;
		}
		var definition = value as SsaDefinition;
		var site = definition == null ? null : definitions.lookup (definition);
		var load = site == null || site.block == null || site.position < 0 ? null : site.block.instructions[site.position] as SsaLoadInstruction;
		var field = load == null ? null : load.source as SsaIndirectFieldPlace;
		if (field != null && (depth != 0 || receiver_use) && field.field.owned_cleanup != null && field.field.owned_cleanup.is_heap_object) {
			if (!receiver_use) {
				fail (path, "owned field receiver loan cannot escape its temporary receiver use");
			}
			verify_receiver_loan_interval (site, field.field.containing_type.semantic_type, function, block, position, path, false, "owned field receiver");
			verify_property_loan (field.pointer, function, block, position, path, true, true, depth + 1);
			return;
		}
		if (field != null && noescape && field.field.owned_cleanup != null) {
			verify_receiver_loan_interval (site, field.field.containing_type.semantic_type, function, block, position, path, false, "borrowed field argument");
			verify_property_loan (field.pointer, function, block, position, path, true, true, depth + 1);
			return;
		}
		var producer = site == null || site.block == null || site.position < 0 ? null : site.block.instructions[site.position] as SsaCallInstruction;
		var success = site == null || site.block == null || site.position < 0 ? null : site.block.instructions[site.position] as SsaCallSuccess;
		if (success != null) {
			producer = success.call;
		}
		if (producer == null || producer.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW) {
			return;
		}
		if (producer.struct_result != null) {
			if (producer.struct_result.shape.mode != StructValueMode.BORROW_VALUE) {
				fail (path, "receiver record observation lost its bounded borrow mode");
			}
			int ordinal = -1;
			for (int i = 0; i < producer.struct_result.leaves.length; i++) {
				if (producer.struct_result.leaves[i] == value) {
					ordinal = i;
				}
			}
			if (ordinal < 0) {
				return;
			}
			var buffer = producer.struct_result.shape.leaves[ordinal] as StructBufferLeafPath;
			if (!(value.semantic_type is ClassType || value.semantic_type is HandleType) && (buffer == null || buffer.component != 0)) {
				return;
			}
		} else if (success == null && producer.result != value) {
			return;
		}
		if (depth != 0 && !receiver_use) {
			fail (path, "borrowed validated receiver cannot escape its temporary receiver use");
		}
		var property = ((SsaPropertyGetter) producer.target).property_member;
		if ((!noescape && !receiver_use) || (site.block == block && site.position >= position) || (site.block != block && (!property.is_owned_lazy || !dominance[site.block.ordinal, block.ordinal]))) {
			fail (path, "borrowed property result cannot escape its direct borrowed argument, temporary receiver or null test");
		}
		var owner = property.declaring_type.semantic_type;
		verify_receiver_loan_interval (site, owner, function, block, position, path, property.is_owned_lazy, "borrowed property");
	}

	private void verify_callable_record_moves(SsaInstruction consumer, GenericArray<SsaValue> arguments, GenericArray<StructBoundaryGroup> groups, GenericArray<SsaStructBoundaryMove> moves, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		foreach (var group in groups) {
			verify_record_argument_loan (arguments, group, function, block, position, path);
		}
		int required = 0;
		foreach (var group in groups) {
			if (group.shape.mode != StructValueMode.MOVE_VALUE) {
				continue;
			}
			required++;
			int matches = 0;
			foreach (var move in moves) {
				var site = buffer_sites.lookup (move);
				if (site == null || site.block != block || site.position >= position || move.consumer != consumer || move.shape != group.shape || move.leaves.length != group.shape.leaves.length) {
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
				fail (path, "indirect MOVE_VALUE argument requires one exact complete prior field commit");
			}
		}
		if (required != moves.length) {
			fail (path, "indirect record transfer inventory differs from its signature groups");
		}
	}

	private void verify_callable_arguments(SsaInstruction consumer, SsaCallableInvocation call, GenericArray<PointerParameterContract> contracts, GenericArray<StructBoundaryGroup> groups, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		int borrowed_index = 0;
		int owned_index = 0;
		var moved_sources = new HashTable<int, bool> (direct_hash, direct_equal);
		for (int i = 0; i < call.arguments.length; i++) {
			if (contracts[i] == PointerParameterContract.OWNED_TRANSFER) {
				if (owned_index >= call.owned_arguments.length) {
					fail (path, "indirect owned argument lost its complete transfer contract");
				}
				var transfer = call.owned_arguments[owned_index++];
				if (transfer.ordinal != i || transfer.value != call.arguments[i] || !cleanups.contains (transfer.cleanup) || !matches_cleanup (transfer.value.semantic_type, transfer.cleanup) || transfer.value.semantic_type is ClassType && !transfer.cleanup.is_heap_object) {
					fail (path, "indirect owned argument lost exact ordinal, value or cleanup");
				}
				if (transfer.source_ordinal < 0) {
					if (!(transfer.value is SsaNullPointerConstant) || transfer.source_after_commit != null || transfer.source_storage != null) {
						fail (path, "indirect owned null argument cannot invent source storage");
					}
				} else {
					if (moved_sources.contains (transfer.source_ordinal) || transfer.source_after_commit == null || transfer.source_after_commit.semantic_type != transfer_root (transfer.value).semantic_type) {
						fail (path, "indirect owned argument requires one distinct source and exact committed null");
					}
					moved_sources.insert (transfer.source_ordinal, true);
					if (transfer.source_storage != null && (object_owners.lookup (transfer.source_storage) != function || !transfer.source_storage.transferable || transfer.source_storage.semantic_type != transfer_root (transfer.value).semantic_type || object_constructions.lookup (transfer.source_storage) == null || object_constructions.lookup (transfer.source_storage).result != transfer_root (transfer.value))) {
						fail (path, "indirect object transfer lost its original local storage provenance");
					}
				}
			}
			bool record_borrow = CallableRecordGroups.borrowed_record_leaf (groups, i);
			bool borrowed = contracts[i] == PointerParameterContract.BORROWED_NOESCAPE || record_borrow;
			if (borrowed && !record_borrow) {
				if (borrowed_index >= call.borrowed_arguments.length) {
					fail (path, "indirect argument lost its exact bounded loan");
				}
				var loan = call.borrowed_arguments[borrowed_index++];
				if (loan.ordinal != i || loan.value != call.arguments[i]) {
					fail (path, "indirect borrow lost original physical argument identity");
				}
				if (loan.source_owner != null) {
					bool read = false;
					for (int p = position - 1; p >= 0; p--) {
						var event = block.instructions[p] as SsaHeapOwnerEvent;
						if (event == null || event.action != SsaHeapOwnerAction.READ || event.effect != consumer) {
							break;
						}
						if (event.owner == loan.source_owner && event.value == loan.value) {
							read = true;
						}
					}
					if (!function.heap_owners.find (loan.source_owner) || !matches_cleanup (loan.value.semantic_type, loan.source_owner.cleanup) || !read) {
						fail (path, "indirect owner loan lost exact original live backing owner");
					}
				} else if (!callable_borrow_origin (loan.value, function, new HashTable<SsaValue, bool> (direct_hash, direct_equal))) {
					fail (path, "indirect borrow without an owner requires its exact non-acquiring origin");
				}
			}
			bool buffer_component = false;
			foreach (var group in groups) {
				if (group.shape.mode != StructValueMode.COPY_VALUE && i >= group.first_leaf && i < group.first_leaf + group.shape.leaves.length && group.shape.leaves[i - group.first_leaf] is StructBufferLeafPath) {
					buffer_component = true;
				}
			}
			verify_value (call.arguments[i], function, block, position, path + "/argument", borrowed, false, false, buffer_component);

		}
		if (borrowed_index != call.borrowed_arguments.length) {
			fail (path, "indirect call contains an extra or reordered bounded loan");
		}
		if (owned_index != call.owned_arguments.length) {
			fail (path, "indirect call contains an extra or reordered ownership transfer");
		}
	}

	private bool callable_borrow_origin(SsaValue value, SsaFunction function, HashTable<SsaValue, bool> seen) {
		if (seen.contains (value)) {
			return true;
		}
		seen.insert (value, true);
		if (value is SsaNullPointerConstant) {
			return true;
		}
		var parameter = value as SsaFunctionParameter;
		if (parameter != null) {
			return function.parameters.find (parameter) && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE;
		}
		var definition = value as SsaDefinition;
		var site = definition == null ? null : definitions.lookup (definition);
		if (site == null || site.function != function || site.block == null) {
			return false;
		}
		if (value is SsaBlockParameter) {
			bool found = false;
			foreach (var predecessor in function.blocks) {
				var edges = new GenericArray<SsaEdge> ();
				var branch = predecessor.terminator as SsaBranch;
				var choice = predecessor.terminator as SsaConditionalBranch;
				if (branch != null) {
					edges.add (branch.edge);
				}
				if (choice != null) {
					edges.add (choice.true_edge);
					edges.add (choice.false_edge);
				}
				foreach (var edge in edges) {
					if (edge.target != site.block) {
						continue;
					}
					for (int p = 0; p < site.block.parameters.length; p++) {
						if (site.block.parameters[p] == value) {
							found = true;
							if (p >= edge.arguments.length || !callable_borrow_origin (edge.arguments[p], function, seen)) {
								return false;
							}
						}
					}
				}
			}
			return found;
		}
		if (site.position < 0) {
			return false;
		}
		var producer = site.block.instructions[site.position];
		var getter = producer as SsaCallInstruction;
		var success = producer as SsaCallSuccess;
		if (success != null) {
			getter = success.call;
		}
		if (getter != null && getter.target is SsaPropertyGetter && getter.target.result_contract == ResultOwnershipContract.RECEIVER_BORROW) {
			if (getter.struct_result != null) {
				return getter.struct_result.shape.mode == StructValueMode.BORROW_VALUE && getter.struct_result.leaves.find ((SsaInstructionResult) value);
			}
			return success == null ? getter.result == value : success.result == value;
		}
		var loaded = producer as SsaLoadInstruction;
		var field = loaded == null ? null : loaded.source as SsaIndirectFieldPlace;
		return field != null && field.field.owned_cleanup != null;
	}

	private void verify_value(SsaValue value, SsaFunction function, SsaBlock block, int position, string path, bool noescape_use = false, bool receiver_use = false, bool struct_consumption = false, bool buffer_component = false, bool enum_view_use = false) throws SsaError {
		var shared_definition = value as SsaDefinition;
		var shared_site = shared_definition == null ? null : definitions.lookup (shared_definition);
		var shared_loan = shared_site == null || shared_site.block == null || shared_site.position < 0 ? null : shared_site.block.instructions[shared_site.position] as SsaSharedOperation;
		if (shared_loan != null && shared_loan.action == SharedAction.BORROW) {
			if (!noescape_use || receiver_use || shared_site.block != block || shared_site.position >= position) {
				fail (path, "shared payload loan cannot escape its exact direct borrowed call");
			}
			for (int i = shared_site.position + 1; i <= position && i < block.instructions.length; i++) {
				var event = block.instructions[i] as SsaHeapOwnerEvent;
				if (event != null && event.owner == shared_loan.source_owner && event.action != SsaHeapOwnerAction.READ) {
					fail (path, "shared payload loan backing strong owner was retired before its call");
				}
			}
		}
		if (value is SsaCallbackView) {
			var view = (SsaCallbackView) value;
			var callback = view.semantic_type as CallbackType;
			if (!noescape_use || receiver_use || callback == null || !callback.matches_closure (view.closure.semantic_type)) {
				fail (path, "captured callback view lost exact borrowed Closure signature");
			}
			verify_value (view.closure, function, block, position, path + "/closure", true);
			return;
		}
		if (value is SsaFunctionAddress) {
			var address = (SsaFunctionAddress) value;
			var signature = value.semantic_type as FunctionValueType;
			var target = address.target;
			if (signature == null || target == null || !functions.contains (target) || target.implicit_receiver != null || target.async_body != null || target.throws_type != null || target.result_contract != signature.result_contract || target.return_type != signature.result_type || (signature.result_contract == ResultOwnershipContract.OWNED_TRANSFER && signature.result_type is ClassType && !target.heap_result) || target.parameters.length != CallableRecordGroups.physical_parameters (signature, target.struct_parameters).length) {
				fail (path, "function address requires exact program-owned nonthrowing native signature");
			}
			try {
				signature.verify_records (signature.record_parameters, struct_fields);
				signature.verify_records (target.struct_parameters, struct_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			for (int i = 0; i < target.parameters.length; i++) {
				if (target.parameters[i].semantic_type != CallableRecordGroups.physical_parameters (signature, target.struct_parameters)[i] || target.parameters[i].pointer_contract != CallableRecordGroups.physical_contracts (signature, target.struct_parameters)[i] || CallableRecordGroups.physical_contracts (signature, target.struct_parameters)[i] == PointerParameterContract.OWNED_TRANSFER && CallableRecordGroups.physical_parameters (signature, target.struct_parameters)[i] is ClassType && !target.parameters[i].heap_object) {
					fail (path, "function address parameter identity mismatch");
				}
			}
			return;
		}
		verify_property_loan (value, function, block, position, path, noescape_use || enum_view_use && value.semantic_type is SliceType, receiver_use);
		var slot_definition = value as SsaDefinition;
		var slot_site = slot_definition == null ? null : definitions.lookup (slot_definition);
		var slot_loan = slot_site == null || slot_site.block == null || slot_site.position < 0 ? null : slot_site.block.instructions[slot_site.position] as SsaSlotsValueInstruction;
		if (slot_loan != null && slot_loan.action == OwnerSlotsAction.BORROW && (!noescape_use || receiver_use)) {
			fail (path, "indexed owner-slot loan cannot escape its direct inspection argument");
		}

		if (value is SsaTaskAbsent) {
			if (!(value.semantic_type is TaskType)) {
				fail (path, "absent task slot requires its exact logical task type");
			}
			return;
		}
		if (enum_views.contains (value) && !enum_view_use) {
			fail (path, "enum inspection array view cannot escape or enter mutable slice transport");
		}
		if (value.semantic_type is EnumType) {
			fail (path, "enum is a bounded carrier, not an ordinary value");
		}
		if (buffer_leaves.contains (value) && !buffer_component) {
			fail (path, "owning buffer leaves require a complete group operation; individual transport is forbidden");
		}
		var buffer_view = buffer_views.lookup (value);
		if (buffer_view != null) {
			verify_buffer_interval (buffer_view, function, block, position, path);
			if (position < block.instructions.length && block.instructions[position] is SsaCallInstruction && invalidates_buffer (block.instructions[position], buffer_view.place)) {
				fail (path, "buffer field borrow overlaps a possibly aliasing object call");
			}
		}
		var result_receiver = value as SsaResultStorageReceiverValue;
		if (result_receiver != null) {
			if (!receiver_use || result_receiver.storage != function.result_storage || result_receiver.storage == null || ((ReceiverType) value.semantic_type).mode != ReceiverMode.INITIALIZING || ((ReceiverType) value.semantic_type).instance_type != function.return_type) {
				fail (path, "result receiver requires exact function result storage");
			}
			return;
		}
		if (value.semantic_type is ReceiverType && !receiver_use) {
			fail (path, "receiver is only valid as an implicit method input or receiver field base");
		}
		// Slices and object references permit local copies; signature/storage guards enforce noescape.
		var parameter = value as SsaFunctionParameter;
		if (parameter != null && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(parameter.semantic_type is StringType) && !(parameter.semantic_type is SliceType) && !(parameter.semantic_type is ClassType) && !noescape_use && !(receiver_use && (CPlainRecordTypes.pointer (parameter.semantic_type, struct_fields) || (CPlainRecordTypes.i32_pointer (parameter.semantic_type) || ForeignApiTypes.scalar_pointee (parameter.semantic_type) != null)))) {
			fail (path, "borrowed parameter cannot escape; only equality or direct borrowed forwarding is permitted");
		}
		verify_type (value.semantic_type, true, path);
		if (value.semantic_type.is_text_slice ()) {
			text_views.insert (value, true);
		}
		if (value is SsaFunctionParameter && value.semantic_type.is_text_view ()) {
			text_origins.borrowed (value);
		}
		if (value is SsaTextConstant) {
			var payload = ((SsaTextConstant) value).payload;
			if (!(value.semantic_type is StringType) || !payload.valid () || !text_literals.contains (payload)) {
				fail (path, "text literal requires member immutable UTF-8 payload and exact byte length");
			}
			text_origins.literal (value);
			return;
		}
		if (value is SsaFloatConstant) {
			if (!(value.semantic_type is FloatingType) || ((FloatingType) value.semantic_type).format != ((SsaFloatConstant) value).value.format) {
				fail (path, "floating constant requires exact canonical type and matching binary format");
			}
			return;
		}
		var integer = value as SsaIntegerConstant;
		if (integer != null) {
			if (!(value.semantic_type is IntegerType)) {
				fail (path, "integer constant must have type 'int'");
			}
			if (integer.value.integer_type != value.semantic_type) {
				fail (path, "integer value must retain its exact semantic type identity");
			}
			// AstraIntegerValue construction guarantees representability. The
			// source span may include a sign/parentheses or synthetic provenance.
			return;
		}
		if (value is SsaNullPointerConstant) {
			if (!value.semantic_type.is_nullable_pointer_value ()) {
				fail (path, "null pointer must have type 'void*'");
			}
			return;
		}
		var boolean = value as SsaBooleanConstant;
		if (boolean != null) {
			if (value.semantic_type.kind != TypeKind.BOOL || (boolean.literal != BooleanLiteral.TRUE && boolean.literal != BooleanLiteral.FALSE)) {
				fail (path, "invalid semantic bool constant");
			}
			return;
		}
		var struct_leaf = value as SsaInstructionResult;
		if (!struct_consumption && struct_leaf != null && struct_result_leaves.contains (struct_leaf)) {
			var consumed = struct_consumptions.lookup (struct_result_leaves.lookup (struct_leaf));
			if (consumed == null || consumed.function != function || (consumed.block == block ? consumed.position >= position : !dominance[consumed.block.ordinal, block.ordinal])) {
				fail (path, "struct result leaf used before complete bounded consumption");
			}
		}
		var definition = value as SsaDefinition;
		if (private_success_values.contains (value)) {
			var frame = private_success_values.lookup (value) as SsaTaskCreate;
			if (frame == null || !frame.checked_admission || !guarded_success (frame, block)) {
				fail (path, "throwing success carrier requires its guarded success load");
			}
		}
		if (!(value is SsaReceiver) && !(value is SsaFunctionParameter) && !(value is SsaBlockParameter) && !(value is SsaInstructionResult)) {
			fail (path, "unsupported SSA value");
			return;
		}
		var site = definitions.lookup (definition);
		if (site == null || site.function != function) {
			fail (path, "value definition is not owned by the containing function");
			return;
		}
		if (site.block == block && site.position >= position) {
			fail (path, "instruction result is used before its definition");
		}
		if (site.block != null && !dominance[site.block.ordinal, block.ordinal]) {
			fail (path, "value definition does not dominate its use");
		}
		if (receiver_use && site.block != null && site.position >= 0) {
			var address = site.block.instructions[site.position] as SsaAddressOfInstruction;
			if (address != null && address.receiver_place != null) {
				verify_place (address.receiver_place, function, block, position, true, path + "/live-receiver");
			}
		}
	}

	private void verify_layout(SsaNativeInstance structure, HashTable<SsaNativeInstance, SsaNativeInstance> complete, GenericArray<SsaNativeInstance> active) throws SsaError {
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
			if (!(dependency is SsaStruct)) {
				fail ("struct layout", "embedded struct requires its exact program-owned descriptor");
			}
			verify_layout (dependency, complete, active);
		}
		active.remove_index (active.length - 1);
		complete.insert (structure, structure);
	}

	private int storage_leaf_count(SsaNativeInstance structure) {
		int count = 0;
		foreach (var field in structure.fields) {
			count += (field.semantic_type is StructType) ? storage_leaf_count (structs.lookup (field.semantic_type)) : 1;
		}
		return count;
	}

	private void verify_storage(SsaAddressableLocal storage, SsaFunction function, SsaBlock block, int position, bool requires_initialization, string path) throws SsaError {
		if (storage_owners.lookup (storage) != function) {
			fail (path, "addressable storage is not owned by the containing function");
		}
		if (!requires_initialization) {
			return;
		}
		var sites = initializations.lookup (storage);
		if (storage.structure == null) {
			var site = sites.lookup (storage);
			if (site == null || (site.block == block && site.position >= position) || !dominance[site.block.ordinal, block.ordinal]) {
				fail (path, "scalar initialization must precede and dominate storage use");
			}
			return;
		}
		if (sites.size () != storage_leaf_count (storage.structure)) {
			fail (path, "complete struct initialization must precede storage use");
		}
		foreach (var site in sites.get_values ()) {
			if ((site.block == block && site.position >= position) || !dominance[site.block.ordinal, block.ordinal]) {
				fail (path, "complete struct initialization must precede and dominate storage use");
			}
		}
	}

	private void verify_record_array_entry(SsaArrayInitialize entry, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var root = entry.record_root;
		var type = entry.storage.semantic_type as ArrayType;
		var entries = record_initializations.lookup (entry.storage);
		if (type == null || !(type.element_type is StructType) || entry.result != null || root.storage != entry.storage || root.array_type != type || entry.elements.length != entry.record_fields.length || entries == null || entries.length != type.length) {
			fail (path, "record array requires N complete exact typed entry initializations");
		}
		if (entry.record_ordinal > 0) {
			var prior = record_initialization_sites.lookup (entries[entry.record_ordinal - 1]);
			if (prior == null || prior.function != function || (prior.block == block && prior.position >= position) || !dominance[prior.block.ordinal, block.ordinal]) {
				fail (path, "each record entry must finish before the next entry initialization");
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
			verify_place (field, function, block, position, false, path);
			initializing_array_entry = null;
			string key = "";
			SsaMemoryPlace base_place = field;
			while (base_place is SsaFieldPlace && ((SsaFieldPlace) base_place).aggregate != null) {
				var projection = (SsaFieldPlace) base_place;
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
			verify_value (entry.elements[i], function, block, position, path);
			if (entry.elements[i].semantic_type != field.semantic_type) {
				fail (path, "record field initialization requires exact scalar/vector leaf type");
			}
		}
	}

	private static bool constructor_field_initialization(SsaMemoryPlace place, SsaFunction function) {
		if (!(function is SsaConstructor)) {
			return false;
		}
		string part;
		var root = place as SsaIndirectFieldPlace;
		if (root == null) {
			root = SsaConstructorInitialization.record_root (place, out part);
		}
		return root != null && root.pointer == function.implicit_receiver && root.field.containing_type == ((SsaConstructor) function).declaring_class;
	}

	private void verify_field_visibility(SsaStructField field, SsaFunction function, string path) throws SsaError {
		if (!field.is_private) {
			return;
		}
		var owner = field.containing_type as SsaClass;
		var receiver = function.implicit_receiver;
		if (owner == null || receiver == null || receiver.contract.instance_type != owner.semantic_type) {
			fail (path, "private field access requires its exact lexical declaring Class");
		}
		if (private_accesses != null) {
			bool found = false;
			foreach (var access in private_accesses) {
				if (access.class_ordinal == owner.ordinal && access.field_ordinal == field.ordinal && access.function_ordinal == function.ordinal) {
					found = true;
				}
			}
			if (!found) {
				private_accesses.add (new SsaPrivateFieldAccess (owner.ordinal, field.ordinal, function.ordinal));
			}
		}
	}

	private void verify_place(SsaMemoryPlace place, SsaFunction function, SsaBlock block, int position, bool requires_initialization, string path) throws SsaError {
		if (place.semantic_type is CallbackType) {
			fail (path, "call-scoped Callback cannot occupy storage");
		}
		var object_field = place as SsaObjectFieldPlace;
		if (object_field != null) {
			var storage = object_field.storage;
			var field = object_field.field;
			verify_field_visibility (field, function, path);
			if (storage.result_candidate || requires_initialization || object_owners.lookup (storage) != function || field.containing_type != storage.object_class || field.ordinal < 0 || field.ordinal >= storage.object_class.fields.length || storage.object_class.fields[field.ordinal] != field || place.semantic_type != field.semantic_type) {
				fail (path, "direct object field Place is restricted to exact construction initialization");
			}
			return;
		}
		if (place.semantic_type is StructType) {
			if (!(structs.lookup (place.semantic_type) is SsaStruct)) {
				fail (path, "struct Place requires exact program-owned storage type");
			}
		} else if (!(place.semantic_type is OwnerSlotsType && place is SsaIndirectFieldPlace)) {
			verify_type (place.semantic_type, true, path);
		}
		var slice = place as SsaSliceElementPlace;
		if (slice != null) {
			verify_value (slice.slice, function, block, position, path + "/operand", false, false, false, false, true);
			verify_value (slice.index, function, block, position, path + "/operand");
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
		var array = place as SsaArrayElementPlace;
		if (array != null) {
			verify_storage (array.storage, function, block, position, array != initializing_array_entry, path);
			verify_array_type (array.array_type, path);
			verify_value (array.index, function, block, position, path + "/index");
			if (array.storage.semantic_type != array.array_type || place.semantic_type != array.array_type.element_type || !(array.index.semantic_type is IntegerType) || !array.provenance.is_valid () || array.provenance.origin != DataPointerOrigin.LOCAL || array.provenance.origin_ordinal != array.storage.source_local_ordinal) {
				fail (path, "array element requires exact type, integer index and storage provenance");
			}
			var constant = array.index as SsaIntegerConstant;
			if (constant != null) {
				if (!constant.value.fits_nonnegative ((uint64) array.array_type.length - 1)) {
					fail (path, "constant array index outside bounds");
				}
			} else if (bounds_storage.lookup (array.index) != array.storage) {
				fail (path, "array element requires validated index for exact storage");
			}
			return;
		}
		var local = place as SsaLocalMemoryPlace;
		if (local != null) {
			if (!place.semantic_type.is_typed_data_pointee () || place.semantic_type != local.storage.semantic_type) {
				fail (path, "local memory place requires exact value storage type");
			}
			verify_storage (local.storage, function, block, position, requires_initialization, path);
			return;
		}
		var dereference = place as SsaDereferencePlace;
		if (dereference != null) {
			verify_value (dereference.pointer, function, block, position, path + "/pointer", false, true);
			var pointer = dereference.pointer.semantic_type as TypedPointerType;
			if (pointer == null || !pointer.pointee.is_typed_data_pointee () || pointer.pointee != place.semantic_type || !dereference.provenance.is_valid ()) {
				fail (path, "dereference place requires the exact directly dereferenceable pointee and lexical provenance");
			}
			return;
		}
		var field_place = place as SsaFieldPlace;
		if (field_place == null) {
			fail (path, "unsupported SSA memory place");
			return;
		}
		verify_field_visibility (field_place.field, function, path);
		var structure = field_place.field.containing_type;
		if (place.semantic_type != field_place.field.semantic_type || structure == null || structs.lookup (structure.semantic_type) != structure || field_place.field.ordinal < 0 || field_place.field.ordinal >= structure.fields.length || structure.fields[field_place.field.ordinal] != field_place.field) {
			fail (path, "memory place must use an exact program-owned struct field");
		}
		if (field_place.aggregate != null) {
			if (!(structure is SsaStruct) || field_place.aggregate.semantic_type != structure.semantic_type) {
				fail (path, "recursive field must match its exact StructType base and owner");
			}
			verify_place (field_place.aggregate, function, block, position, requires_initialization, path + "/base");
			return;
		}
		var direct = place as SsaDirectFieldPlace;
		if (direct != null) {
			verify_storage (direct.storage, function, block, position, requires_initialization, path);
			if (direct.storage.structure != structure) {
				fail (path, "direct field must match its exact storage struct");
			}
			return;
		}
		var indirect = place as SsaIndirectFieldPlace;
		if (indirect == null) {
			fail (path, "unsupported SSA memory place");
			return;
		}
		if (indirect.pointer.semantic_type is ClassType && !object_validations.contains (indirect.pointer)) {
			fail (path, "object field requires a dominating null-validated reference");
		}
		if (indirect.pointer.semantic_type is ReceiverType && !(indirect.pointer is SsaReceiver) && !class_upcasts.contains (indirect.pointer)) {
			fail (path, "receiver field base must be this input or its exact verified ancestor upcast");
		}
		verify_value (indirect.pointer, function, block, position, path + "/pointer", false, true);
		if (((indirect.pointer.semantic_type is ReceiverType) ? ((ReceiverType) indirect.pointer.semantic_type).instance_type != structure.semantic_type : (indirect.pointer.semantic_type is ClassType) ? indirect.pointer.semantic_type != structure.semantic_type : (!indirect.pointer.semantic_type.is_struct_pointer () || ((TypedPointerType) indirect.pointer.semantic_type).pointee != structure.semantic_type))) {
			fail (path, "indirect field pointer pointee must match its exact field owner");
		}
	}

	private GenericArray<SemanticType>? struct_fields(SemanticType type) {
		var structure = structs.lookup (type) as SsaStruct;
		if (structure == null) {
			return null;
		}
		var fields = new GenericArray<SemanticType> ();
		foreach (var field in structure.fields) {
			fields.add (field.semantic_type);
		}
		return fields;
	}

	private void verify_record_field(SsaIndirectFieldPlace place, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		verify_place (place, function, block, position, false, path);
		var record = place.field.record_owner;
		if (!(place.field.containing_type is SsaClass) || !(place.semantic_type is StructType) || record == null || structs.lookup (place.semantic_type) != record || place.field.owned_cleanup != null || CopyabilityAuthority.of (place.semantic_type, struct_fields) == Copyability.COPYABLE) {
			fail (path, "inline record field lost exact Class storage and recursive cleanup authority");
		}
	}

	private void verify_struct_shape(StructValueShape? shape, SemanticType type, string path) throws SsaError {
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
			if (leaf.semantic_type is SliceType) {
				fail (path, "SSA record buffers require complete physical PTR/I32 field channels");
			}
			verify_type (leaf.semantic_type, true, path + "/leaf");
		}
	}

	private StructLeafPath record_buffer_path(StructValueShape shape, int ordinal) throws SsaError {
		int index = 0;
		foreach (var leaf in shape.leaves) {
			var component = leaf as StructBufferLeafPath;
			if (component != null && component.component == 0 && index++ == ordinal) {
				return component.storage_path ();
			}
		}
		throw new SsaError.INVALID_SSA ("record buffer has no original declared physical field pair");
	}

	private void verify_record_buffer_pairs(StructValueShape shape, GenericArray<SsaValue> leaves, GenericArray<SsaBufferPair> pairs, string path) throws SsaError {
		int pair_index = 0;
		for (int i = 0; i < shape.leaves.length; i++) {
			var component = shape.leaves[i] as StructBufferLeafPath;
			if (component == null) {
				continue;
			}
			if (component.component != 0 || i + 1 >= leaves.length || pair_index >= pairs.length) {
				fail (path, "record buffer requires one original complete physical field pair");
			}
			var pair = pairs[pair_index++];
			if (pair.shape != component.buffer_shape || pair.base_value != leaves[i] || pair.length_value != leaves[i + 1]) {
				fail (path, "record buffer split or substituted an original PTR/I32 pair");
			}
			i++;
		}
		if (pair_index != pairs.length) {
			fail (path, "record buffer has duplicated or foreign complete pairs");
		}
	}

	private void verify_struct_parameter_groups(SsaFunction function, string path) throws SsaError {
		int physical = 0;
		int logical = 0;
		int group_index = 0;
		int buffer_index = 0;
		while (physical < function.parameters.length) {
			var buffer = buffer_index < function.buffer_parameters.length ? function.buffer_parameters[buffer_index] : null;
			if (buffer != null && buffer.first_leaf <= physical) {
				if (buffer.first_leaf != physical || buffer.source_ordinal != logical || physical + 1 >= function.parameters.length || !cleanups.contains (buffer.cleanup) || !buffer.cleanup.is_buffer || buffer.pair.shape != buffer.cleanup.buffer_shape || buffer.pair.base_value != function.parameters[physical] || buffer.pair.length_value != function.parameters[physical + 1] || function.parameters[physical].pointer_contract != PointerParameterContract.UNMANAGED || function.parameters[physical + 1].pointer_contract != PointerParameterContract.UNMANAGED) {
					fail (path, "buffer parameter requires complete ordered PTR/I32 leaves and owned-transfer cleanup");
				}
				physical += 2;
				logical++;
				buffer_index++;
				continue;
			}
			var group = group_index < function.struct_parameters.length ? function.struct_parameters[group_index] : null;
			if (group != null && group.first_leaf <= physical) {
				if (group.first_leaf != physical || group.source_ordinal != logical || group.shape.leaves.length > function.parameters.length - physical) {
					fail (path, "struct parameter grouping must preserve complete ordered source positions");
				}
				verify_struct_shape (group.shape, group.shape.semantic_type, path + "/parameter");
				foreach (var leaf in group.shape.leaves) {
					var parameter = function.parameters[physical++];
					var contract = group.shape.mode == StructValueMode.BORROW_VALUE && (leaf.semantic_type is ClassType || leaf.semantic_type is HandleType) ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED;
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
		if (buffer_index != function.buffer_parameters.length) {
			fail (path, "buffer parameter group exceeds parameters");
		}
		if (group_index != function.struct_parameters.length) {
			fail (path, "struct parameter grouping exceeds leaf parameters");
		}
		if (function.declaration_only ()) {
			return;
		}
		foreach (var group in function.struct_parameters) {
			if (group.shape.mode == StructValueMode.BORROW_VALUE) {
				int bindings = 0;
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var binding = instruction as SsaStructParameterBorrow;
						if (binding != null && binding.parameter == group) {
							bindings++;
						}
					}
				}
				if (bindings != 1 || function.async_body != null) {
					fail (path, "borrowed record parameter requires exactly one synchronous complete entry binding");
				}
			}
			if (group.shape.mode != StructValueMode.MOVE_VALUE) {
				continue;
			}
			int acquired = 0;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var acquire = instruction as SsaStructBoundaryAcquire;
					if (acquire != null && acquire.parameter == group) {
						acquired++;
					}
				}
			}
			if (acquired != 1) {
				fail (path, "MOVE_VALUE parameter requires exactly one complete incoming ownership acquisition");
			}
		}
	}

	private void verify_record_argument_loan(GenericArray<SsaValue> arguments, StructBoundaryGroup argument, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		if (argument.shape.mode == StructValueMode.BORROW_VALUE) {
			var result_loan = argument as SsaStructBorrowResultArgument;
			if (result_loan != null) {
				var results = result_loan.results;
				var origin = struct_results.lookup (results) as SsaCallInstruction;
				var consumed = struct_consumptions.lookup (results);
				var consumption = consumed == null ? null : consumed.block.instructions[consumed.position] as SsaStructResultConsume;
				var site = origin == null ? null : buffer_sites.lookup (origin);
				if (origin == null || !(origin.target is SsaPropertyGetter) || origin.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW || results.shape.mode != StructValueMode.BORROW_VALUE || results.shape.semantic_type != argument.shape.semantic_type || results.leaves.length != argument.shape.leaves.length || consumption == null || consumption.use_kind != StructResultUseKind.OBSERVE || site == null || site.function != function) {
					fail (path, "record getter argument requires its exact complete observed noescape result");
				}
				for (int l = 0; l < results.leaves.length; l++) {
					if (arguments[argument.first_leaf + l] != results.leaves[l]) {
						fail (path, "record getter argument changed an original ordered result leaf");
					}
				}
				var property = ((SsaPropertyGetter) origin.target).property_member;
				verify_receiver_loan_interval (site, property.declaring_type.semantic_type, function, block, position, path, true, "borrowed record argument");
			} else {
				var loan = argument as SsaStructBorrowArgument;
				if (loan == null || structs.lookup (argument.shape.semantic_type) != loan.record_type || loan.source_local_ordinal < 0) {
					fail (path, "record argument loan lost its exact original source and nominal group");
				}
				if (loan.incoming != null) {
					var incoming = loan.incoming;
					if (!function.struct_parameters.find (incoming) || incoming.shape.mode != StructValueMode.BORROW_VALUE || incoming.shape.semantic_type != argument.shape.semantic_type || loan.owners.length != 0 || loan.buffers.length != 0 || incoming.shape.leaves.length != argument.shape.leaves.length) {
						fail (path, "forwarded record loan lost its exact incoming borrowed group");
					}
					for (int l = 0; l < argument.shape.leaves.length; l++) {
						if (arguments[argument.first_leaf + l] != function.parameters[incoming.first_leaf + l]) {
							fail (path, "forwarded record loan changed an original incoming leaf");
						}
					}
				} else {
					int owners = 0;
					int buffers = 0;
					for (int l = 0; l < argument.shape.leaves.length; l++) {
						var leaf = argument.shape.leaves[l];
						var field = record_leaf (argument.shape.semantic_type, leaf);
						var component = leaf as StructBufferLeafPath;
						if (component != null) {
							if (component.component != 0 || l + 1 >= argument.shape.leaves.length || buffers >= loan.buffers.length) {
								fail (path, "record argument loan lost an original complete buffer view");
							}
							var view = loan.buffers[buffers++];
							var read = buffer_reads.lookup (view.pair);
							var storage = read == null ? null : read.place.storage;
							if (storage == null || storage.record_type != loan.record_type || storage.record_source_ordinal != loan.source_local_ordinal || storage.record_path == null || !storage.record_path.same_path (component.storage_path ()) || view.pair.shape != component.buffer_shape || view.pair.base_value != arguments[argument.first_leaf + l] || view.pair.length_value != arguments[argument.first_leaf + l + 1]) {
								fail (path, "record argument loan changed its original buffer storage, path or complete pair");
							}
							var site = buffer_sites.lookup (view);
							if (site == null || site.function != function || site.block != block || site.position >= position) {
								fail (path, "record argument buffer view must precede its exact bounded call");
							}
							verify_value (view.result, function, block, position, path, true);
							l++;
							continue;
						}
						if (field == null || field.owned_cleanup == null) {
							continue;
						}
						if (owners >= loan.owners.length || loan.owner_leaf (owners) != l) {
							fail (path, "record argument loan must retain every exact owner leaf");
						}
						var owner = loan.owners[owners++];
						if (owner == null || owner.ordinal < 0 || owner.ordinal >= function.heap_owners.length || function.heap_owners[owner.ordinal] != owner || owner.record_type != loan.record_type || owner.source_ordinal != loan.source_local_ordinal || owner.record_path == null || !owner.record_path.same_path (leaf) || owner.cleanup != field.owned_cleanup) {
							fail (path, "record argument loan changed its original owner path or cleanup authority");
						}
						bool live = false;
						for (int p = position - 1; p >= 0; p--) {
							var read = block.instructions[p] as SsaHeapOwnerEvent;
							if (read == null || read.action != SsaHeapOwnerAction.READ) {
								break;
							}
							if (read.owner == owner && read.value == arguments[argument.first_leaf + l] && read.effect == null) {
								live = true;
							}
						}
						if (!live) {
							fail (path, "record argument loan requires its exact live owner READ immediately before invocation");
						}
					}
					if (owners != loan.owners.length || buffers != loan.buffers.length) {
						fail (path, "record argument loan duplicated or added foreign owner or buffer leaves");
					}
				}
			}
		} else if (argument is SsaStructBorrowArgument || argument is SsaStructBorrowResultArgument) {
			fail (path, "record argument loan cannot be relabeled as copied or owning transport");
		}
	}

	private void verify_struct_arguments(SsaCallInstruction call, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
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
				fail (path, "record argument cannot change its original copy/move mode");
			}
			verify_record_argument_loan (call.arguments, argument, function, block, position, path);
			if (argument.shape.mode == StructValueMode.MOVE_VALUE) {
				int matches = 0;
				foreach (var move in call.record_moves) {
					var site = buffer_sites.lookup (move);
					var call_site = buffer_sites.lookup (call);
					if (site == null || call_site == null || site.block != call_site.block || site.position >= call_site.position || move.consumer != call || move.shape != argument.shape || move.leaves.length != argument.shape.leaves.length) {
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
					fail (path, "MOVE_VALUE argument requires one exact complete prior field commit");
				}
			}
		}
	}

	private void verify_struct_consumption(SsaStructResultConsume consumption, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var group = consumption.results;
		if (consumption.result != null || !struct_results.contains (group)) {
			fail (path, "struct result consumption requires its exact call group and no SSA result");
		}
		verify_struct_shape (group.shape, group.shape.semantic_type, path);
		if (consumption.use_kind == StructResultUseKind.OBSERVE || group.shape.mode == StructValueMode.BORROW_VALUE) {
			var origin = struct_results.lookup (group) as SsaCallInstruction;
			if (consumption.use_kind != StructResultUseKind.OBSERVE || group.shape.mode != StructValueMode.BORROW_VALUE || origin == null || origin.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW) {
				fail (path, "record observation requires its exact nonescaping borrowed getter result");
			}
			for (int i = 0; i < group.leaves.length; i++) {
				verify_value (group.leaves[i], function, block, position, path + "/observed-leaf", true, false, true, group.shape.leaves[i] is StructBufferLeafPath);
			}
			return;
		}
		if (consumption.use_kind != StructResultUseKind.INITIALIZE && consumption.use_kind != StructResultUseKind.ASSIGN && consumption.use_kind != StructResultUseKind.ARGUMENT && consumption.use_kind != StructResultUseKind.RETURN && consumption.use_kind != StructResultUseKind.ENUM_PAYLOAD && consumption.use_kind != StructResultUseKind.CONTAINER_ELEMENT) {
			fail (path, "invalid bounded struct result consumer");
		}
		for (int i = 0; i < group.leaves.length; i++) {
			verify_value (group.leaves[i], function, block, position, path + "/leaf", false, false, true, group.shape.leaves[i] is StructBufferLeafPath);
		}
		if (group.shape.mode == StructValueMode.MOVE_VALUE && (consumption.use_kind == StructResultUseKind.INITIALIZE || consumption.use_kind == StructResultUseKind.ASSIGN)) {
			var field = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaRecordFieldCommit;
			if (field != null) {
				if (field.results != group || field.shape != group.shape || field.record_move != null || consumption.use_kind != (field.initializes ? StructResultUseKind.INITIALIZE : StructResultUseKind.ASSIGN)) {
					fail (path, "record field result lost exact complete consumption");
				}
				return;
			}
			var acquire = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaStructBoundaryAcquire;
			if (acquire == null || acquire.results != group || acquire.shape != group.shape) {
				fail (path, "MOVE_VALUE result requires immediate complete owner acquisition");
			}
			return;
		}
		if (group.shape.mode == StructValueMode.MOVE_VALUE && consumption.use_kind != StructResultUseKind.RETURN) {
			fail (path, "MOVE_VALUE result requires exact fresh owner acquisition or complete result forwarding");
		}
		if (consumption.use_kind == StructResultUseKind.INITIALIZE || consumption.use_kind == StructResultUseKind.ASSIGN) {
			return;
		}
		int consumers = 0;
		foreach (var candidate in function.blocks) {
			if (consumption.use_kind == StructResultUseKind.CONTAINER_ELEMENT) {
				foreach (var instruction in candidate.instructions) {
					var transfer = instruction as SsaSlotsRecordTransfer;
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
				foreach (var instruction in candidate.instructions) {
					var construction = instruction as SsaEnumConstruct;
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
				var returned = candidate.terminator as SsaStructReturn;
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
				foreach (var instruction in candidate.instructions) {
					var call = instruction as SsaCallInstruction;
					var foreign_call = instruction as SsaCCallInstruction;
					var indirect = instruction as SsaFunctionValueCall;
					var closure = instruction as SsaClosureCall;
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
			fail (path, "forwarded struct result requires one exact complete argument or return consumer");
		}
	}

	private void consume_buffer_pair(SsaBufferPair pair, SsaNode consumer, SsaFunction function, SsaBlock block, int position, bool transfers, string path) throws SsaError {
		if (pair.is_empty) {
			return;
		}
		var observed = buffer_reads.lookup (pair);
		if (observed != null && observed.place.record_projection != null) {
			fail (path, "record buffer observation cannot acquire or transfer cleanup ownership");
		}
		if (buffer_consumers.contains (pair)) {
			fail (path, "buffer owner group cannot be copied or consumed twice");
		}
		buffer_consumers.insert (pair, consumer);
		var read = buffer_reads.lookup (pair);
		if (read == null) {
			var producer = buffer_producers.lookup (pair);
			if (producer != null) {
				var site = buffer_sites.lookup (producer);
				if (site.block != block || site.position >= position) {
					fail (path, "buffer producer requires one bounded same-block ownership consumer");
				}
			}
			var extraction = producer as SsaEnumReadBuffer;
			if (extraction != null) {
				var write = consumer as SsaBufferWriteInstruction;
				if (!transfers || write == null || !write.initializes || write.place.storage == null || write.place.storage.owner_ordinal != extraction.binding.local_ordinal) {
					fail (path, "owned enum buffer pair lost its exact selected binding destination");
				}
			}
			return;
		}
		if (!transfers) {
			verify_buffer_interval (read, function, block, position, path);
			return;
		}
		if (read.place.storage == null) {
			fail (path, "buffer field move-out is unsupported");
		}
		var site = buffer_sites.lookup (read);
		bool disarmed = false;
		var argument = consumer as SsaBufferArgument;
		var record_move = consumer as SsaStructBoundaryMove;
		if (site.block != block && record_move != null) {
			SsaBufferWriteInstruction? disarm = null;
			int disarm_position = -1;
			for (int i = 0; i < position; i++) {
				var write = block.instructions[i] as SsaBufferWriteInstruction;
				if (write != null && write.record_boundary == record_move && write.place.storage == read.place.storage) {
					if (disarm != null || !write.pair.is_empty) {
						fail (path, "record transfer requires one exact complete source disarm");
					}
					disarm = write;
					disarm_position = i;
				}
			}
			if (site.function != function || !dominance[site.block.ordinal, block.ordinal] || disarm == null || buffer_disarms.contains (disarm)) {
				fail (path, "record transfer lost its dominating original field capture and committed pair disarm");
			}
			verify_buffer_interval (read, function, block, disarm_position, path);
			buffer_disarms.insert (disarm, pair);
			return;
		}
		if (site.block != block && consumer is SsaEnumConstruct) {
			SsaBufferWriteInstruction? disarm = null;
			int disarm_position = -1;
			for (int i = 0; i < position; i++) {
				var write = block.instructions[i] as SsaBufferWriteInstruction;
				if (write != null && write.place.storage == read.place.storage) {
					if (disarm != null || !write.pair.is_empty) {
						fail (path, "cross-block enum transfer requires one exact whole-group disarm");
					}
					disarm = write;
					disarm_position = i;
				}
			}
			if (site.function != function || !dominance[site.block.ordinal, block.ordinal] || disarm == null || buffer_disarms.contains (disarm)) {
				fail (path, "cross-block enum transfer lost dominating reservation and exact disarm");
			}
			verify_buffer_interval (read, function, block, disarm_position, path);
			buffer_disarms.insert (disarm, pair);
			return;
		}
		if (site.block != block && argument != null && argument.disarm != null) {
			int disarm_position = -1;
			for (int i = 0; i < position; i++) {
				if (block.instructions[i] == argument.disarm) {
					disarm_position = i;
				}
			}
			if (site.function != function || !dominance[site.block.ordinal, block.ordinal] || disarm_position < 0 || argument.disarm.place.storage != read.place.storage || !argument.disarm.pair.is_empty || buffer_disarms.contains (argument.disarm)) {
				fail (path, "cross-block transfer requires exact dominating capture and committed whole-group disarm");
			}
			verify_buffer_interval (read, function, block, disarm_position, path);
			buffer_disarms.insert (argument.disarm, pair);
			return;
		}
		if (site.function != function || site.block != block || site.position >= position) {
			fail (path, "buffer owner capture and transfer must remain one bounded ordered action");
		}
		for (int i = site.position + 1; i < position; i++) {
			var write = block.instructions[i] as SsaBufferWriteInstruction;
			if (write != null && write.place.storage == read.place.storage) {
				var restored = buffer_producers.lookup (write.pair) as SsaFallibleBufferRestore;
				var call_site = restored == null || restored.call == null ? null : buffer_sites.lookup (restored.call);
				if (disarmed && argument != null && restored != null && restored.argument == argument && restored.call.buffer_arguments.find (argument) && call_site != null && call_site.function == function && call_site.block == block && call_site.position == position && write.place == argument.disarm.place) {
					continue;
				}
				if (disarmed || !write.pair.is_empty) {
					fail (path, "buffer transfer requires one whole null/zero source disarm");
				}
				if (buffer_disarms.contains (write)) {
					fail (path, "one buffer disarm cannot transfer multiple captures");
				}
				verify_buffer_interval (read, function, block, i, path);
				buffer_disarms.insert (write, pair);
				disarmed = true;
			}
		}
		if (!disarmed) {
			fail (path, "buffer transfer must disarm its complete captured source group");
		}
	}

	private static bool same_buffer_place(SsaBufferPlace left, SsaBufferPlace right) {
		if (left.record_projection != null || right.record_projection != null) {
			SsaMemoryPlace? a = left.record_projection;
			SsaMemoryPlace? b = right.record_projection;
			if (a == null || b == null) {
				return false;
			}
			while (a is SsaFieldPlace && b is SsaFieldPlace) {
				var x = (SsaFieldPlace) a;
				var y = (SsaFieldPlace) b;
				if (x.field != y.field) {
					return false;
				}
				if (x.aggregate == null || y.aggregate == null) {
					var xr = x as SsaIndirectFieldPlace;
					var yr = y as SsaIndirectFieldPlace;
					return xr != null && yr != null && xr.pointer == yr.pointer;
				}
				a = x.aggregate;
				b = y.aggregate;
			}
			return a == b;
		}
		if (left.storage != null || right.storage != null) {
			return left.storage != null && left.storage == right.storage;
		}
		return left.field != null && right.field != null && left.field.field == right.field.field && left.field.pointer == right.field.pointer;
	}

	private void verify_buffer_commits(SsaFunction function) throws SsaError {
		verify_enum_buffer_reservations (function);
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var write = block.instructions[i] as SsaBufferWriteInstruction;
				if (write != null && (write.pair.is_empty || (write.place.field != null && !write.initializes))) {
					var cleanup = i == 0 ? null : block.instructions[i - 1] as SsaBufferDeallocateInstruction;
					var read = cleanup == null ? null : buffer_reads.lookup (cleanup.pair);
					if (!buffer_disarms.contains (write) && (read == null || !same_buffer_place (read.place, write.place))) {
						fail ("buffer commit", "disarm/replacement requires exact prior transfer or old-value deallocation");
					}
				}
				var cleanup = block.instructions[i] as SsaBufferDeallocateInstruction;
				var read = cleanup == null ? null : buffer_reads.lookup (cleanup.pair);
				if (read != null && read.place.field != null && !buffer_field_epilogues.contains (cleanup)) {
					var replacement = i + 1 >= block.instructions.length ? null : block.instructions[i + 1] as SsaBufferWriteInstruction;
					if (replacement == null || replacement.initializes || replacement.pair.is_empty || !same_buffer_place (read.place, replacement.place)) {
						fail ("buffer field cleanup", "persistent owner field cleanup requires replacement or exact final destructor epilogue");
					}
				}
			}
		}
	}

	private void verify_enum_buffer_reservations(SsaFunction function) throws SsaError {
		foreach (var start in function.blocks) {
			for (int position = 0; position < start.instructions.length; position++) {
				var capture = start.instructions[position] as SsaEnumBufferCapture;
				if (capture == null) {
					continue;
				}
				var read = buffer_reads.lookup (capture.pair);
				if (read == null || !same_buffer_place (read.place, capture.place)) {
					fail ("enum staging", "reservation requires its exact original pointer/count owner read");
				}
				int consumers = 0;
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var construction = instruction as SsaEnumConstruct;
						if (construction != null) {
							foreach (var field in construction.fields) {
								if (field.buffer == capture.pair) {
									consumers++;
								}
							}
						}
					}
				}
				if (consumers != 1) {
					fail ("enum staging", "reservation requires one exact constructor field consumer");
				}
				var pending = new GenericArray<SsaBlock> ();
				var states = new GenericArray<int> ();
				var visited = new HashTable<SsaBlock, int> (direct_hash, direct_equal);
				pending.add (start);
				states.add (0);
				for (int p = 0; p < pending.length; p++) {
					var block = pending[p];
					int state = states[p];
					int bit = 1 << state;
					if ((visited.lookup (block) & bit) != 0) {
						continue;
					}
					visited.insert (block, visited.lookup (block) | bit);
					for (int i = block == start ? position + 1 : 0; i < block.instructions.length; i++) {
						var instruction = block.instructions[i];
						var aborted = instruction as SsaEnumBufferAbort;
						var construction = instruction as SsaEnumConstruct;
						bool commits = false;
						if (construction != null) {
							foreach (var field in construction.fields) {
								if (field.buffer == capture.pair) {
									commits = true;
								}
							}
						}
						if ((aborted != null && aborted.capture == capture) || commits) {
							if (state != 0) {
								fail ("enum staging", "reservation was already committed or aborted on this edge");
							}
							if (aborted != null && capture.fresh) {
								var released = i + 1 < block.instructions.length ? block.instructions[i + 1] as SsaBufferReadInstruction : null;
								var release = i + 2 < block.instructions.length ? block.instructions[i + 2] as SsaBufferDeallocateInstruction : null;
								if (released == null || release == null || release.pair != released.pair || !same_buffer_place (released.place, capture.place) || release.cleanup != capture.place.cleanup) {
									fail ("enum staging", "abandoned fresh reservation lost its exact original cleanup owner");
								}
							}
							state = 1;
						} else if (state == 0 && invalidates_buffer (instruction, capture.place)) {
							var disarm = instruction as SsaBufferWriteInstruction;
							if (disarm == null || !buffer_disarms.contains (disarm)) {
								fail ("enum staging", "pending reservation owner was invalidated before disposition");
							}
						}
					}
					var successors = block.terminator.successors ();
					if (successors.length == 0 && state == 0 && !(block.terminator is SsaAllocationFailureTrap)) {
						fail ("enum staging", "pending fresh/reserved buffer reaches exit without exact disposition");
					}
					foreach (var successor in successors) {
						if (successor == start) {
							if (state == 0) {
								fail ("enum staging", "reservation repeats before disposition");
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

	private bool invalidates_buffer(SsaInstruction instruction, SsaBufferPlace place) {
		var scoped = instruction as SsaScopedAllocator;
		if (scoped != null && scoped.backing == place.storage) {
			return true;
		}
		if (place.record_projection != null) {
			SsaMemoryPlace root = place.record_projection;
			while (root is SsaFieldPlace && ((SsaFieldPlace) root).aggregate != null) {
				root = ((SsaFieldPlace) root).aggregate;
			}
			var field = root as SsaIndirectFieldPlace;
			return field == null || invalidates_property_loan (instruction, field.field.containing_type.semantic_type);
		}
		var exchange = instruction as SsaBufferExchangeInstruction;
		if (exchange != null) {
			foreach (var slot in new SsaBufferPlace[] { exchange.left, exchange.right }) {
				if (same_buffer_place (slot, place) || (slot.field != null && place.field != null && slot.field.field.containing_type.semantic_type == place.field.field.containing_type.semantic_type)) {
					return true;
				}
			}
		}
		var write = instruction as SsaBufferWriteInstruction;
		if (write != null && same_buffer_place (write.place, place)) {
			return true;
		}
		var cleanup = instruction as SsaBufferDeallocateInstruction;
		var read = cleanup == null ? null : buffer_reads.lookup (cleanup.pair);
		if (read != null && same_buffer_place (read.place, place)) {
			return true;
		}
		if (place.field == null) {
			return false;
		}
		var type = place.field.field.containing_type.semantic_type;
		if (write != null && write.place.field != null && write.place.field.field.containing_type.semantic_type == type) {
			return true;
		}
		if (read != null && read.place.field != null && read.place.field.field.containing_type.semantic_type == type) {
			return true;
		}
		var call = instruction as SsaCallInstruction;
		if (call == null) {
			return false;
		}
		var receiver = call.receiver == null ? null : call.receiver.semantic_type as ReceiverType;
		if (receiver != null && receiver.instance_type == type) {
			return true;
		}
		foreach (var argument in call.arguments) {
			if (argument.semantic_type == type) {
				return true;
			}
		}
		return false;
	}

	private void verify_buffer_interval(SsaBufferReadInstruction read, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var site = buffer_sites.lookup (read);
		if (site == null || site.function != function) {
			fail (path, "buffer borrow/capture requires exact owner read provenance");
		}
		bool[] reaches = new bool[function.blocks.length];
		reaches[block.ordinal] = true;
		bool changed = false;
		do {
			changed = false;
			foreach (var candidate in function.blocks) {
				if (candidate == site.block || reaches[candidate.ordinal]) {
					continue;
				}
				foreach (var next in SsaConstructorInitialization.successors (candidate)) {
					if (reaches[next.ordinal]) {
						reaches[candidate.ordinal] = true;
						changed = true;
						break;
					}
				}
			}
		} while (changed);
		var pending = new GenericArray<SsaBlock> ();
		pending.add (site.block);
		bool[] visited = new bool[function.blocks.length];
		for (int p = 0; p < pending.length; p++) {
			var candidate = pending[p];
			if (visited[candidate.ordinal]) {
				continue;
			}
			visited[candidate.ordinal] = true;
			int first = candidate == site.block ? site.position + 1 : 0;
			int end = candidate == block ? position : (int) candidate.instructions.length;
			for (int i = first; i < end; i++) {
				if (invalidates_buffer (candidate.instructions[i], read.place)) {
					fail (path, "buffer borrow/capture outlives owner replacement, transfer or destruction");
				}
			}
			if (candidate == block) {
				continue;
			}
			foreach (var next in SsaConstructorInitialization.successors (candidate)) {
				if (next != site.block && reaches[next.ordinal]) {
					pending.add (next);
				}
			}
		}
	}

	private static SsaBufferPair? instruction_buffer_pair(SsaInstruction instruction) {
		if (instruction is SsaFallibleBufferRestore) {
			return ((SsaFallibleBufferRestore) instruction).pair;
		}
		if (instruction is SsaFrameBufferRestore) {
			return ((SsaFrameBufferRestore) instruction).pair;
		}
		if (instruction is SsaTaskSuccess) {
			return ((SsaTaskSuccess) instruction).buffer_result;
		}
		if (instruction is SsaEnumReadBuffer) {
			return ((SsaEnumReadBuffer) instruction).pair;
		}
		if (instruction is SsaBufferAllocateInstruction) {
			return ((SsaBufferAllocateInstruction) instruction).pair;
		}
		if (instruction is SsaBufferReadInstruction) {
			return ((SsaBufferReadInstruction) instruction).pair;
		}
		if (instruction is SsaGroupCallSuccess) {
			return ((SsaGroupCallSuccess) instruction).call.buffer_result;
		}
		if (instruction is SsaCallInstruction) {
			return ((SsaCallInstruction) instruction).exception_result == null ? ((SsaCallInstruction) instruction).buffer_result : null;
		}
		return null;
	}

	private void register_buffer_pair(SsaBufferPair pair, string path) throws SsaError {
		if (!pair.shape.is_valid (element_fields) || pair.base_value.semantic_type != pair.shape.base_type || pair.length_value.semantic_type != pair.shape.length_type || pair.base_value == pair.length_value || buffer_pairs.contains (pair) || buffer_leaves.contains (pair.base_value) || buffer_leaves.contains (pair.length_value)) {
			fail (path, "buffer group requires unique complete exact PTR/I32 definitions");
		}
		buffer_pairs.insert (pair, pair);
		buffer_leaves.insert (pair.base_value, pair);
		buffer_leaves.insert (pair.length_value, pair);
	}

	private void verify_buffer_pair(SsaBufferPair pair, SsaFunction function, SsaBlock block, int position, string path, bool observation = false) throws SsaError {
		if (!pair.shape.is_valid (element_fields) || pair.base_value.semantic_type != pair.shape.base_type || pair.length_value.semantic_type != pair.shape.length_type) {
			fail (path, "buffer group shape or component type mismatch");
		}
		if (!pair.is_empty && (!buffer_pairs.contains (pair) || buffer_leaves.lookup (pair.base_value) != pair || buffer_leaves.lookup (pair.length_value) != pair)) {
			fail (path, "buffer base and length must originate as one exact complete group");
		}
		verify_value (pair.base_value, function, block, position, path + "/base", observation, false, false, true);
		verify_value (pair.length_value, function, block, position, path + "/length", observation, false, false, true);
	}

	private void verify_buffer_place(SsaBufferPlace place, SsaFunction function, SsaBlock block, int position, bool initialized, string path) throws SsaError {
		if (!cleanups.contains (place.cleanup) || !place.cleanup.is_buffer || !place.cleanup.buffer_shape.is_valid (element_fields) || (place.storage == null ? 0 : 1) + (place.field == null ? 0 : 1) + (place.record_projection == null ? 0 : 1) != 1) {
			fail (path, "buffer place requires one exact storage origin and static cleanup");
		}
		if (place.record_projection != null) {
			var leaf = place.record_projection;
			if (leaf.aggregate == null || leaf.semantic_type != place.cleanup.buffer_type || leaf.field.owned_cleanup != place.cleanup) {
				fail (path, "record buffer observation requires its exact declared field and cleanup graph");
			}
			verify_place (leaf, function, block, position, true, path);
			SsaMemoryPlace root = leaf;
			while (root is SsaFieldPlace && ((SsaFieldPlace) root).aggregate != null) {
				root = ((SsaFieldPlace) root).aggregate;
			}
			var field = root as SsaIndirectFieldPlace;
			if (field == null || field.field.record_owner == null) {
				fail (path, "record buffer observation requires an exact receiver-owned inline record");
			}
			return;
		}
		if (place.storage != null) {
			if (buffer_storage.lookup (place.storage) != function || place.cleanup != place.storage.cleanup) {
				fail (path, "buffer place storage/cleanup identity mismatch");
			}
			if ((place.record_path == null) != (place.storage.record_path == null) || (place.record_path != null && !place.record_path.same_path (place.storage.record_path))) {
				fail (path, "buffer place lost its original record field path");
			}
			if (place.record_rank != place.storage.record_rank) {
				fail (path, "buffer place lost its written acquisition rank");
			}
		} else {
			if (!(place.field.field.containing_type is SsaClass) || place.field.semantic_type != place.cleanup.buffer_type) {
				fail (path, "buffer field place requires exact native class owner contract");
			}
			verify_place (place.field, function, block, position, initialized, path);
			if (initialized && field_state != null && place.field.pointer == function.implicit_receiver && !field_state.is_definite (place.field.field.ordinal)) {
				fail (path, "buffer field read before definite initialization");
			}
		}
	}

	private bool verify_buffer_instruction(SsaInstruction instruction, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var slot_capture = instruction as SsaBufferSlotCaptureInstruction;
		if (slot_capture != null) {
			if (slot_capture.place.record_projection != null) {
				fail (path, "record buffer observation cannot acquire an exchange slot");
			}
			if (instruction.result != null) {
				fail (path, "buffer slot capture cannot produce a value or owner");
			}
			verify_buffer_place (slot_capture.place, function, block, position, true, path);
			return true;
		}
		var exchange = instruction as SsaBufferExchangeInstruction;
		if (exchange != null) {
			if (exchange.left.record_projection != null || exchange.right.record_projection != null) {
				fail (path, "record buffer observation cannot exchange owning storage");
			}
			verify_buffer_place (exchange.left, function, block, position, true, path + "/left");
			verify_buffer_place (exchange.right, function, block, position, true, path + "/right");
			if (instruction.result != null || exchange.left.cleanup != exchange.right.cleanup) {
				fail (path, "buffer exchange requires two complete exact owner slots and no value result");
			}
			return true;
		}
		var allocation = instruction as SsaBufferAllocateInstruction;
		var fallible_restore = instruction as SsaFallibleBufferRestore;
		if (fallible_restore != null) {
			var call = fallible_restore.call;
			var argument = fallible_restore.argument;
			var site = call == null ? null : buffer_sites.lookup (call);
			if (call == null || !call.constructs || !call.storage.fallible || !call.storage.heap_allocated || site == null || site.function != function || site.block != block || site.position <= position || !call.buffer_arguments.find (argument) || !call.buffer_restores.find (fallible_restore) || argument.disarm.place.storage == null || argument.disarm.place.storage.record_type != null || fallible_restore.pair.shape != argument.pair.shape || fallible_restore.result != null) {
				fail (path, "fallible buffer restoration lost exact constructor capture or original standalone caller storage");
			}
			verify_buffer_pair (argument.pair, function, block, position, path + "/original", true);
			var write = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaBufferWriteInstruction;
			if (write == null || write.initializes || write.place != argument.disarm.place || write.pair != fallible_restore.pair) {
				fail (path, "fallible buffer restoration requires immediate complete original caller publication");
			}
			for (int i = position + 2; i < site.position; i++) {
				if (!fallible_restore_effect (block.instructions[i], call)) {
					fail (path, "fallible buffer restoration cannot cross another effect before its constructor");
				}
			}
			return true;
		}
		var frame_restore = instruction as SsaFrameBufferRestore;
		if (frame_restore != null) {
			var creation = frame_restore.creation;
			var argument = frame_restore.argument;
			var site = creation == null ? null : buffer_sites.lookup (creation);
			if (creation == null || !creation.checked_admission || creation.exception_result == null || site == null || site.function != function || site.block != block || site.position >= position || !creation.buffer_arguments.find (argument) || !creation.buffer_restores.find (frame_restore) || argument.disarm.place.storage == null || argument.disarm.place.storage.record_type != null || frame_restore.pair.shape != argument.pair.shape || frame_restore.result != null) {
				fail (path, "checked frame buffer restoration lost exact admitted capture or standalone caller storage");
			}
			verify_buffer_pair (argument.pair, function, block, position, path + "/original", true);
			var write = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaBufferWriteInstruction;
			if (write == null || write.initializes || write.place != argument.disarm.place || write.pair != frame_restore.pair) {
				fail (path, "checked frame buffer restoration requires immediate complete pointer/length publication to its original caller slot");
			}
			for (int i = site.position + 1; i < position; i++) {
				var prior = block.instructions[i];
				var event = prior as SsaHeapOwnerEvent;
				var stored = prior as SsaBufferWriteInstruction;
				bool restored = false;
				if (stored != null) {
					foreach (var candidate in creation.buffer_restores) {
						restored |= candidate.pair == stored.pair && candidate.argument.disarm.place == stored.place;
					}
				}
				if (!(prior is SsaFrameInputRestore || prior is SsaFrameBufferRestore) && !restored && (event == null || event.action != SsaHeapOwnerAction.ACQUIRE || !(event.effect is SsaFrameInputRestore))) {
					fail (path, "checked frame buffer restoration cannot cross another effect after admission");
				}
			}
			return true;
		}
		if (allocation != null) {
			if (instruction.result != null || !cleanups.contains (allocation.cleanup) || !allocation.cleanup.is_buffer || allocation.pair.shape != allocation.cleanup.buffer_shape || allocation.count.semantic_type != allocation.pair.shape.length_type) {
				fail (path, "buffer allocation requires exact eligible element, static cleanup and int count");
			}
			var bytes = allocation.cleanup.buffer_type as ContextBytesType;
			var context = allocation.allocation_context;
			if ((bytes != null) != (context != null) || context == null && allocation.context_owner != null) {
				fail (path, "byte allocation lost exact selected context authority");
			}
			if (context != null) {
				if (context.semantic_type != bytes.allocator_type || !handles.contains (bytes.allocator_type)) {
					fail (path, "byte allocation changed its exact allocator contract");
				}
				var owner = allocation.context_owner;
				if (owner != null) {
					SsaHeapOwnerEvent? read = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
					if (allocation.failure != null) {
						read = null;
						int requests = 0;
						foreach (var candidate in function.blocks) {
							var branch = candidate.terminator as SsaBufferAllocationBranch;
							if (branch != null && branch.allocation == allocation) {
								requests++;
								read = candidate.instructions.length == 0 ? null : candidate.instructions[candidate.instructions.length - 1] as SsaHeapOwnerEvent;
							}
						}
						if (requests != 1) {
							fail (path, "checked byte allocation requires one original admission request");
						}
					}
					if (!function.heap_owners.find (owner) || !matches_cleanup (bytes.allocator_type, owner.cleanup) || read == null || read.owner != owner || read.action != SsaHeapOwnerAction.READ || read.effect != allocation || read.value != context) {
						fail (path, "byte allocation requires its exact preceding live context read");
					}
				} else {
					var parameter = context as SsaFunctionParameter;
					if (parameter == null || !function.parameters.find (parameter) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						fail (path, "byte allocation requires a live context owner or borrowed parameter");
					}
				}
				verify_value (context, function, block, position, path + "/context", true);
			}
			verify_value (allocation.count, function, block, position, path + "/count");
			var count = allocation.count as SsaIntegerConstant;
			if (count != null && count.value.mathematical_value < 0) {
				fail (path, "negative constant buffer count");
			}
			return true;
		}
		var read = instruction as SsaBufferReadInstruction;
		if (read != null) {
			if (instruction.result != null || read.pair.shape != read.place.cleanup.buffer_shape) {
				fail (path, "buffer read requires complete pair from exact owner storage");
			}
			verify_buffer_place (read.place, function, block, position, true, path);
			return true;
		}
		var write = instruction as SsaBufferWriteInstruction;
		if (write != null) {
			if (write.place.record_projection != null) {
				fail (path, "record buffer observation cannot write or disarm its owning field");
			}
			if (instruction.result != null || write.pair.shape != write.place.cleanup.buffer_shape) {
				fail (path, "buffer write requires one complete exact group");
			}
			verify_buffer_place (write.place, function, block, position, !write.initializes, path);
			verify_buffer_pair (write.pair, function, block, position, path);
			var captured = buffer_reads.lookup (write.pair);
			var moved = captured == null ? null : captured.place.storage;
			bool replacement = write.place.storage != null && write.place.storage.record_type != null && !write.initializes && !write.pair.is_empty;
			if (replacement || write.record_retirement != null) {
				var retirement = write.record_retirement;
				var retired = retirement == null ? null : buffer_reads.lookup (retirement.pair);
				var retirement_site = retirement == null ? null : buffer_sites.lookup (retirement);
				SsaInstruction? incoming_producer = captured == null ? buffer_producers.lookup(write.pair) : captured;
				var incoming_site = incoming_producer == null ? null : buffer_sites.lookup (incoming_producer);
				if (!replacement || retirement == null || retired == null || !same_buffer_place (retired.place, write.place) || retirement.cleanup != write.place.cleanup || retirement_site == null || retirement_site.block != block || retirement_site.position >= position || incoming_site == null || (incoming_site.block == block ? incoming_site.position >= retirement_site.position : !dominance[incoming_site.block.ordinal, block.ordinal])) {
					fail (path, "record buffer replacement requires complete incoming capture before exact old-field retirement and publication");
				}
			}
			bool record_transfer = !write.pair.is_empty && moved != null && moved.record_type != null;
			if (write.record_boundary != null) {
				var boundary = write.record_boundary;
				var site = buffer_sites.lookup (boundary);
				if (site == null || site.function != function || site.block != block || site.position >= position || !boundary.buffers.find (write.place.storage) || write.record_move_source != null || write.record_take_source != null || write.record_retirement != null) {
					fail (path, "record boundary buffer write requires its exact original acquisition or disarm");
				}
			} else if (write.record_take_source != null || (record_transfer && write.place.storage != null && write.place.storage.record_type == null)) {
				var destination = write.place.storage;
				if (!record_transfer || !write.initializes || write.record_take_source != moved || write.record_move_source != null || destination == null || destination.record_type != null || moved == destination || moved.cleanup != destination.cleanup) {
					fail (path, "record buffer take requires the original complete pair and one fresh standalone owner");
				}
			} else if (record_transfer || write.record_move_source != null) {
				var destination = write.place.storage;
				if (!record_transfer || !write.initializes || write.record_move_source != moved || destination == null || moved == destination || moved.record_type != destination.record_type || moved.record_source_ordinal == destination.record_source_ordinal || moved.record_path == null || destination.record_path == null || !moved.record_path.same_path (destination.record_path) || moved.record_rank != destination.record_rank || moved.cleanup != destination.cleanup) {
					fail (path, "whole-record buffer move requires the original complete pair and exact source/destination paths");
				}
			}
			var acquisition = write.record_boundary as SsaStructBoundaryAcquire;
			var source_move = acquisition == null ? null : acquisition.record_move;
			if (source_move != null && !write.pair.is_empty) {
				var site = buffer_sites.lookup (acquisition);
				int index = -1;
				for (int b = 0; b < acquisition.buffers.length; b++) {
					if (acquisition.buffers[b] == write.place.storage) {
						index = b;
					}
				}
				if (source_move.consumer != acquisition || buffer_consumers.lookup (write.pair) != source_move || index < 0 || index >= source_move.buffer_pairs.length || acquisition.buffer_pairs[index] != write.pair || source_move.buffer_pairs[index] != write.pair || site == null || site.block != block || position != site.position + (int) acquisition.owners.length + index + 1) {
					fail (path, "record subobject buffer acquisition lost its exact once-only source transfer");
				}
				// The source boundary proved and consumed the original complete pair.
				// Retain its one destination write as the final transfer consumer.
				buffer_consumers.insert (write.pair, instruction);
			} else {
				consume_buffer_pair (write.pair, instruction, function, block, position, true, path);
			}
			if (write.place.field != null && write.pair.is_empty) {
				fail (path, "buffer field move-out/disarm is unsupported");
			}
			if (field_state != null && write.place.field != null && write.place.field.pointer == function.implicit_receiver) {
				if (!write.initializes || field_state.is_possible (write.place.field.field.ordinal)) {
					fail (path, "constructor buffer field requires one definite initialization");
				}
				field_state.initialize (write.place.field.field.ordinal);
			}
			return true;
		}
		var cleanup = instruction as SsaBufferDeallocateInstruction;
		if (cleanup != null) {
			if (instruction.result != null || !cleanups.contains (cleanup.cleanup) || !cleanup.cleanup.is_buffer || cleanup.pair.shape != cleanup.cleanup.buffer_shape) {
				fail (path, "buffer deallocation requires exact complete owner group and cleanup");
			}
			verify_buffer_pair (cleanup.pair, function, block, position, path);
			consume_buffer_pair (cleanup.pair, instruction, function, block, position, false, path);
			return true;
		}
		var borrow = instruction as SsaBufferBorrowInstruction;
		if (borrow != null) {
			if (instruction.result == null || instruction.result.semantic_type != borrow.pair.shape.slice_type && !ContextBytesType.permits_view (borrow.pair.shape.slice_type, instruction.result.semantic_type)) {
				fail (path, "buffer borrow requires the existing nonowning SliceType result or bounded context byte view");
			}
			if (borrow.record_parameter != null) {
				var group = borrow.record_parameter;
				SsaStructParameterBorrow? binding = null;
				foreach (var entry in function.entry.instructions) {
					var candidate = entry as SsaStructParameterBorrow;
					if (candidate != null && candidate.parameter == group) {
						binding = candidate;
					}
				}
				if (borrow.record_source != null || borrow.record_path == null || !function.struct_parameters.find (group) || group.shape.mode != StructValueMode.BORROW_VALUE || binding == null || !binding.buffers.find (borrow.pair) || function.async_body != null) {
					fail (path, "record parameter buffer view lost its exact complete incoming pair and synchronous loan");
				}
				bool exact = false;
				for (int l = 0; l + 1 < group.shape.leaves.length; l++) {
					var component = group.shape.leaves[l] as StructBufferLeafPath;
					if (component != null && component.component == 0 && component.storage_path ().same_path (borrow.record_path) && component.buffer_shape == borrow.pair.shape && function.parameters[group.first_leaf + l] == borrow.pair.base_value && function.parameters[group.first_leaf + l + 1] == borrow.pair.length_value) {
						exact = true;
					}
				}
				if (!exact) {
					fail (path, "record parameter buffer view changed its original declared field path or pair");
				}
				verify_buffer_pair (borrow.pair, function, block, position, path, true);
				return true;
			}
			if (borrow.record_source != null) {
				var group = borrow.record_source;
				var producer = struct_results.lookup (group) as SsaCallInstruction;
				if (group.shape.mode != StructValueMode.BORROW_VALUE || producer == null || producer.target.result_contract != ResultOwnershipContract.RECEIVER_BORROW || !group.buffers.find (borrow.pair)) {
					fail (path, "record buffer view lost its exact borrowed getter pair and receiver loan");
				}
				verify_buffer_pair (borrow.pair, function, block, position, path, true);
				verify_value (borrow.pair.base_value, function, block, position, path + "/pair", true, false, false, true);
				verify_value (borrow.pair.length_value, function, block, position, path + "/length", true, false, false, true);
				return true;
			}
			var source = buffer_reads.lookup (borrow.pair);
			if (source == null) {
				fail (path, "buffer borrow requires an existing named or field owner slot");
			}
			verify_buffer_pair (borrow.pair, function, block, position, path);
			verify_buffer_interval (source, function, block, position, path);
			buffer_views.insert (borrow.result, source);
			return true;
		}
		return false;
	}

	private bool invalidates_exchange_slot(SsaInstruction instruction, SsaBufferPlace place) {
		if (invalidates_buffer (instruction, place)) {
			return true;
		}
		if (place.field == null) {
			return false;
		}
		var cleanup = instruction as SsaCleanupInstruction;
		return cleanup != null && cleanup.value.semantic_type == place.field.field.containing_type.semantic_type;
	}

	private void verify_buffer_exchanges(SsaFunction function) throws SsaError {
		bool present = false;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is SsaBufferSlotCaptureInstruction || instruction is SsaBufferExchangeInstruction) {
					present = true;
				}
			}
		}
		if (!present) {
			return;
		}
		var consumed = new HashTable<SsaBufferSlotCaptureInstruction, bool> (direct_hash, direct_equal);
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var exchange = instruction as SsaBufferExchangeInstruction;
				if (exchange == null) {
					continue;
				}
				SsaInstruction[] ordered = {
					exchange.left_capture, exchange.right_capture, exchange
				};
				for (int i = 0; i < 2; i++) {
					var capture = (SsaBufferSlotCaptureInstruction) ordered[i];
					var site = buffer_sites.lookup (capture);
					var next = buffer_sites.lookup (ordered[i + 1]);
					if (site == null || next == null || site.function != function || next.function != function || consumed.contains (capture)) {
						fail ("buffer exchange", "each slot capture must belong to this function and one exchange operand");
					}
					consumed.insert (capture, true);
					if (site.block == next.block ? site.position >= next.position : !dominance[site.block.ordinal, next.block.ordinal]) {
						fail ("buffer exchange", "left capture must precede and dominate right capture, then exchange");
					}
					var pending = new GenericArray<SsaBlock> ();
					bool[] visited = new bool[function.blocks.length];
					pending.add (site.block);
					for (int p = 0; p < pending.length; p++) {
						var candidate = pending[p];
						if (visited[candidate.ordinal]) {
							continue;
						}
						visited[candidate.ordinal] = true;
						int first = candidate == site.block ? site.position + 1 : 0;
						bool committed = false;
						for (int j = first; j < candidate.instructions.length; j++) {
							var effect = candidate.instructions[j];
							if (effect == exchange) {
								committed = true;
								break;
							}
							if (effect == capture || invalidates_exchange_slot (effect, capture.place)) {
								fail ("buffer exchange", "captured slot or containing object is invalidated before exchange");
							}
						}
						if (committed) {
							continue;
						}
						var successors = SsaConstructorInitialization.successors (candidate);
						if (successors.length == 0 && !(candidate.terminator is SsaAllocationFailureTrap)) {
							fail ("buffer exchange", "slot capture reaches a normal exit without its exchange");
						}
						foreach (var successor in successors) {
							if (successor == site.block) {
								fail ("buffer exchange", "slot capture can repeat before its exchange");
							}
							pending.add (successor);
						}
					}
				}
			}
		}
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is SsaBufferSlotCaptureInstruction && !consumed.contains ((SsaBufferSlotCaptureInstruction) instruction)) {
					fail ("buffer exchange", "orphan slot capture");
				}
			}
		}
	}

	private void verify_buffer_arguments(SsaCallInstruction call, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		if (call.buffer_arguments.length != call.target.buffer_parameters.length) {
			fail (path, "buffer arguments require exact complete ownership transfer metadata");
		}
		var disarms = new HashTable<SsaBufferWriteInstruction, SsaBufferWriteInstruction> (direct_hash, direct_equal);
		for (int i = 0; i < call.buffer_arguments.length; i++) {
			var argument = call.buffer_arguments[i];
			var parameter = call.target.buffer_parameters[i];
			var pair = argument.pair;
			if (argument.parameter != parameter || parameter.first_leaf < 0 || parameter.first_leaf + 1 >= call.arguments.length || pair.shape != parameter.cleanup.buffer_shape || call.arguments[parameter.first_leaf] != pair.base_value || call.arguments[parameter.first_leaf + 1] != pair.length_value) {
				fail (path, "buffer argument base/length group does not match exact parameter");
			}
			verify_buffer_pair (pair, function, block, position, path);
			consume_buffer_pair (pair, argument, function, block, position, true, path);
			var site = buffer_sites.lookup (argument.disarm);
			if (site == null || site.block != block || site.position >= position || argument.disarm.place.storage == null || argument.disarm.place.cleanup != parameter.cleanup || !argument.disarm.pair.is_empty || buffer_disarms.lookup (argument.disarm) != pair || disarms.contains (argument.disarm)) {
				fail (path, "buffer call requires one prior complete null/zero source disarm for its exact captured pair");
			}
			disarms.insert (argument.disarm, argument.disarm);
		}
	}

	private HashTable<SsaValue, bool> record_producers = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
	private SsaCleanupContract? callable_result_cleanup(SsaInstruction? producer) {
		var success = producer as SsaClosureCallSuccess;
		var invocation = success == null ? producer as SsaCallableInvocation : success.call;
		return invocation == null ? null : invocation.result_cleanup ();
	}

	private void verify_record_scalar_acquire(SsaHeapOwnerEvent event, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		if (event.owner == null || event.owner.record_type != null || event.action != SsaHeapOwnerAction.ACQUIRE) {
			return;
		}
		var restored = event.effect as SsaFallibleInputRestore;
		if (restored != null && restored.owner == event.owner && restored.result == event.value && position > 0 && block.instructions[position - 1] == restored) {
			return;
		}
		var frame_restore = event.effect as SsaFrameInputRestore;
		if (frame_restore != null && frame_restore.owner == event.owner && frame_restore.result == event.value && position > 0 && block.instructions[position - 1] == frame_restore) {
			return;
		}
		int related = 0;
		bool participates = false;
		foreach (var owner in function.heap_owners) {
			if (owner.cleanup == event.owner.cleanup) {
				related++;
				participates |= owner.record_type != null;
			}
		}
		foreach (var candidate_block in function.blocks) {
			foreach (var instruction in candidate_block.instructions) {
				var append = instruction as SsaSlotsEffect;
				if (append != null && (append.action == SsaSlotsAction.APPEND || append.action == SsaSlotsAction.REPLACE) && append.owner != null && append.owner.cleanup == event.owner.cleanup) {
					participates = true;
				}
			}
		}
		if (!participates && (related < 2 || !SsaHeapOwnerFlow.local_input (function))) {
			return;
		}
		// A named scalar transfer must dispose the original owner immediately;
		// replacement may retire the destination between capture and acquire.
		int previous = position - 1;
		while (previous >= 0 && (block.instructions[previous] is SsaCleanupInstruction || (block.instructions[previous] is SsaHeapOwnerEvent && ((SsaHeapOwnerEvent) block.instructions[previous]).action == SsaHeapOwnerAction.END))) {
			previous--;
		}
		var moved = previous < 0 ? null : block.instructions[previous] as SsaHeapOwnerEvent;
		var extracted = moved == null ? null : moved.effect as SsaRecordTake;
		if (extracted != null && event.effect == null && extracted.destination == event.owner && extracted.pointer == event.value && moved != null && moved.owner == extracted.source && moved.effect == extracted && moved.action == SsaHeapOwnerAction.MOVE && moved.value == event.value) {
			return;
		}
		if (moved != null && moved.action == SsaHeapOwnerAction.MOVE && moved.effect == null && moved.owner != null && moved.owner.record_type == null && moved.owner != event.owner && moved.owner.cleanup == event.owner.cleanup && moved.value == event.value) {
			return;
		}
		var parameter = event.value as SsaFunctionParameter;
		bool owned_parameter = parameter != null && function.parameters.find (parameter) && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && matches_cleanup (parameter.semantic_type, event.owner.cleanup);
		var definition = event.value as SsaDefinition;
		var site = definition == null ? null : definitions.lookup (definition);
		var producer = site == null || site.position < 0 ? null : site.block.instructions[site.position];
		var native_call = producer as SsaCallInstruction;
		var success = producer as SsaCallSuccess;
		if (success != null) {
			native_call = success.call;
		}
		var foreign_call = producer as SsaCCallInstruction;
		var object_reference = producer as SsaObjectReferenceInstruction;
		bool constructed = object_reference != null && event.owner.cleanup.is_object && object_reference.storage.heap_allocated == event.owner.cleanup.is_heap_object && object_reference.storage.object_class == event.owner.cleanup.object_class;
		var take_producer = producer as SsaSlotsValueInstruction;
		var closure_producer = producer as SsaClosureBind;
		var shared_producer = producer as SsaSharedOperation;
		var enum_producer = producer as SsaEnumReadScalar;
		bool native_owner = producer is SsaScopedAllocator && ((SsaScopedAllocator) producer).owner == event.owner && event.effect == producer || callable_result_cleanup (producer) == event.owner.cleanup || enum_producer != null && enum_producer.owner == event.owner && enum_producer.result == event.value && event.effect == enum_producer || take_producer != null && take_producer.action == OwnerSlotsAction.TAKE && take_producer.owner == event.owner && event.effect == take_producer || closure_producer != null && closure_producer.cleanup == event.owner.cleanup || shared_producer != null && shared_producer.cleanup == event.owner.cleanup;
		if (!owned_parameter && !constructed && !native_owner && (native_call == null || native_call.target.owned_cleanup != event.owner.cleanup) && (foreign_call == null || foreign_call.target.owned_cleanup != event.owner.cleanup)) {
			fail (path, "record incoming scalar authority requires an exact owned parameter, producer or original owner transfer");
		}
		if (record_producers.contains (event.value)) {
			fail (path, "record producer cannot acquire duplicated ownership");
		}
		record_producers.insert (event.value, true);
	}

	private SsaStructField? record_leaf(SemanticType type, owned StructLeafPath path) {
		path = path.storage_path ();
		SsaStructField? field = null;
		for (int d = 0; d < path.depth; d++) {
			var record = structs.lookup (type) as SsaStruct;
			int ordinal = path.field_ordinal (d);
			if (record == null || ordinal < 0 || ordinal >= record.fields.length) {
				return null;
			}
			field = record.fields[ordinal];
			type = field.semantic_type;
		}
		return field != null && field.semantic_type == path.semantic_type ? field : null;
	}

	private GenericArray<StructLeafPath> record_owning_paths(SsaStruct record) throws SsaError {
		var result = new GenericArray<StructLeafPath> ();
		try {
			foreach (var path in StructLeafOrder.enumerate_storage (record.semantic_type, struct_fields)) {
				var field = record_leaf (record.semantic_type, path);
				if (field != null && field.owned_cleanup != null) {
					result.add (path);
				}
			}
		} catch (StructLeafError error) {
			fail ("record obligations", error.message);
		}
		return result;
	}

	private void verify_record_group(SsaStruct record, int source_ordinal, SsaFunction function, string path) throws SsaError {
		if (structs.lookup (record.semantic_type) != record || source_ordinal < 0 || record.methods.length != 0 || record.properties.length != 0) {
			fail (path, "record group requires exact promoted local storage and complete field authority");
		}
		var paths = new HashTable<string, bool> (str_hash, str_equal);
		var ranks = new HashTable<int, bool> (direct_hash, direct_equal);
		int expected = (int) record_owning_paths (record).length;
		foreach (var owner in function.heap_owners) {
			if (owner.record_type != record || owner.source_ordinal != source_ordinal) {
				continue;
			}
			var field = owner.record_path == null ? null : record_leaf (record.semantic_type, owner.record_path);
			if (field == null || field != owner.record_field || field.owned_cleanup != owner.cleanup || owner.cleanup.is_buffer || paths.contains (owner.record_path.spelling ()) || owner.record_rank < 0 || owner.record_rank >= expected || ranks.contains (owner.record_rank)) {
				fail (path, "record scalar obligation lost unique exact path, cleanup or rank");
			}
			paths.insert (owner.record_path.spelling (), true);
			ranks.insert (owner.record_rank, true);
		}
		foreach (var slot in function.buffer_storage) {
			if (slot.record_type != record || slot.record_source_ordinal != source_ordinal) {
				continue;
			}
			var field = slot.record_path == null ? null : record_leaf (record.semantic_type, slot.record_path);
			if (field == null || field.owned_cleanup != slot.cleanup || !slot.cleanup.is_buffer || paths.contains (slot.record_path.spelling ()) || slot.record_rank < 0 || slot.record_rank >= expected || ranks.contains (slot.record_rank)) {
				fail (path, "record buffer obligation lost unique complete pair path, cleanup or rank");
			}
			paths.insert (slot.record_path.spelling (), true);
			ranks.insert (slot.record_rank, true);
		}
		if (paths.size () != expected) {
			fail (path, "record local omitted a recursive ownership obligation");
		}
	}

	private void verify_record_fields(SsaHeapOwner owner, SsaValue pointer, GenericArray<SsaValue> values, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var record = owner.record_type;
		var field = owner.record_field;
		if (record == null || structs.lookup (record.semantic_type) != record || field == null || owner.record_path == null || record_leaf (record.semantic_type, owner.record_path) != field || field.owned_cleanup == null || record.methods.length != 0 || record.properties.length != 0 || owner.ordinal < 0 || owner.ordinal >= function.heap_owners.length || function.heap_owners[owner.ordinal] != owner || values.length != 1 || values[0] != pointer || pointer.semantic_type != field.semantic_type) {
			fail (path, "record owner requires exact field-path-derived local Resource obligation");
		}
		int count = (int) record_owning_paths (record).length;
		if (owner.record_rank < 0 || owner.record_rank >= count) {
			fail (path, "record field lost exact initialized-prefix ordinal");
		}
		verify_record_group (record, owner.source_ordinal, function, path);
		if (field.owned_cleanup != owner.cleanup || !matches_cleanup (field.semantic_type, owner.cleanup)) {
			fail (path, "record field lost exact Resource cleanup identity");
		}
		verify_value (pointer, function, block, position, path);
	}

	private void verify_record_marker(SsaInstruction instruction, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var acquire = instruction as SsaRecordAcquire;
		var move = instruction as SsaRecordMove;
		var owner = acquire == null ? move.destination : acquire.owner;
		var pointer = acquire == null ? move.pointer : acquire.pointer;
		verify_record_fields (owner, pointer, acquire == null ? move.fields : acquire.fields, function, block, position, path);
		var recorded_path = acquire == null ? move.path : acquire.path;
		if (recorded_path == null || !recorded_path.same_path (owner.record_path) || (acquire == null ? move.rank : acquire.rank) != owner.record_rank) {
			fail (path, "record event lost its original full field path");
		}
		var next = position + 1 < block.instructions.length ? block.instructions[position + 1] as SsaHeapOwnerEvent : null;
		if (acquire != null) {
			if (next == null || next.owner != owner || next.value != pointer || next.action != SsaHeapOwnerAction.ACQUIRE || next.effect != acquire) {
				fail (path, "record acquisition lost its exact owner event");
			}
			if (acquire.source_owner != null) {
				var previous = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
				if (acquire.source_owner.record_type != null || acquire.source_owner.cleanup != owner.cleanup || previous == null || previous.owner != acquire.source_owner || previous.action != SsaHeapOwnerAction.MOVE || previous.value != pointer) {
					fail (path, "record incoming move lacks exact scalar owner disposition");
				}
			} else {
				var definition = pointer as SsaDefinition;
				var site = definition == null ? null : definitions.lookup (definition);
				var producer = site == null || site.position < 0 ? null : site.block.instructions[site.position];
				var success = producer as SsaCallSuccess;
				var native_call = success == null ? producer as SsaCallInstruction : success.call;
				var foreign_call = producer as SsaCCallInstruction;
				if (callable_result_cleanup (producer) != owner.cleanup && (native_call == null || native_call.target.owned_cleanup != owner.cleanup || (native_call.target.throws_type != null && (success == null || native_call.owned_success != success))) && (foreign_call == null || foreign_call.target.owned_cleanup != owner.cleanup)) {
					fail (path, "record acquisition requires an independently proved exact owned producer");
				}
				if (record_producers.contains (pointer)) {
					fail (path, "record producer cannot acquire duplicated ownership");
				}
				record_producers.insert (pointer, true);
			}
		} else {
			var moved_fields = new HashTable<string, bool> (str_hash, str_equal);
			int expected = 0;
			foreach (var leaf in record_owning_paths (owner.record_type)) {
				if (!record_leaf (owner.record_type.semantic_type, leaf).owned_cleanup.is_buffer) {
					expected++;
				}
			}
			foreach (var candidate in block.instructions) {
				var moved = candidate as SsaRecordMove;
				if (moved == null || moved.source.source_ordinal != move.source.source_ordinal || moved.destination.source_ordinal != move.destination.source_ordinal || moved.source.record_type != move.source.record_type) {
					continue;
				}
				if (moved.source.record_path == null || moved_fields.contains (moved.source.record_path.spelling ())) {
					fail (path, "whole record move duplicates a field-path obligation");
				}
				moved_fields.insert (moved.source.record_path.spelling (), true);
			}
			if (moved_fields.size () != expected) {
				fail (path, "whole record move omitted a field obligation");
			}
			var committed = position + 2 < block.instructions.length ? block.instructions[position + 2] as SsaHeapOwnerEvent : null;
			if (move.source == owner || move.source.record_type != owner.record_type || move.source.record_path == null || !move.source.record_path.same_path (owner.record_path) || move.source.record_field != owner.record_field || move.source.record_rank != owner.record_rank || move.source.cleanup != owner.cleanup || next == null || next.owner != move.source || next.action != SsaHeapOwnerAction.MOVE || next.value != pointer || next.effect != move || committed == null || committed.owner != owner || committed.action != SsaHeapOwnerAction.ACQUIRE || committed.value != pointer) {
				fail (path, "whole record move requires exact unique source and destination disposition");
			}
		}
	}

	private void verify_record_boundary(SsaStructBoundary boundary, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var projected = boundary.projection == null ? null : record_leaf (boundary.record_type.semantic_type, boundary.projection);
		var value_type = boundary.projection == null ? boundary.record_type.semantic_type : projected == null ? null : projected.semantic_type;
		var value_record = value_type == null ? null : structs.lookup (value_type) as SsaStruct;
		if (value_record == null || (boundary.projection != null && !(boundary is SsaStructBoundaryAcquire))) {
			fail (path, "record subobject boundary requires its exact declared target projection");
		}
		verify_struct_shape (boundary.shape, value_type, path);
		if (boundary.shape.mode != StructValueMode.MOVE_VALUE || structs.lookup (boundary.record_type.semantic_type) != boundary.record_type || boundary.leaves.length != boundary.shape.leaves.length || boundary.owners.length + boundary.buffers.length == 0 || boundary.owners.length + boundary.buffers.length != record_owning_paths (value_record).length || boundary.buffers.length != boundary.buffer_pairs.length) {
			fail (path, "MOVE_VALUE requires an exact complete nominal target, leaf set and cleanup responsibility");
		}
		for (int i = 0; i < boundary.leaves.length; i++) {
			verify_value (boundary.leaves[i], function, block, position, path + "/leaf", false, false, false, boundary.shape.leaves[i] is StructBufferLeafPath);
			if (boundary.leaves[i].semantic_type != boundary.shape.leaves[i].semantic_type) {
				fail (path, "MOVE_VALUE leaf changed its exact declared type");
			}
		}
		var seen = new HashTable<string, bool> (str_hash, str_equal);
		for (int i = 0; i < boundary.owners.length; i++) {
			var owner = boundary.owners[i];
			var leaf = boundary.owner_path (i);
			if (owner.record_type != boundary.record_type || owner.source_ordinal != boundary.source_ordinal || owner.record_path == null || !leaf.same_path (owner.record_path) || owner.record_rank != boundary.owner_rank (i) || seen.contains (leaf.spelling ())) {
				fail (path, "MOVE_VALUE changed an original field path, rank or root identity");
			}
			seen.insert (leaf.spelling (), true);
			SsaValue? value = null;
			for (int l = 0; l < boundary.shape.leaves.length; l++) {
				if (boundary.root_path (boundary.shape.leaves[l]).same_path (leaf)) {
					value = boundary.leaves[l];
				}
			}
			if (value == null) {
				fail (path, "MOVE_VALUE omitted an original owner leaf");
			}
			var values = new GenericArray<SsaValue> ();
			values.add (value);
			verify_record_fields (owner, value, values, function, block, position, path);
			var event = position + i + 1 >= block.instructions.length ? null : block.instructions[position + i + 1] as SsaHeapOwnerEvent;
			if (event == null || event.owner != owner || event.value != value || event.effect != boundary || event.action != ((boundary is SsaStructBoundaryAcquire) ? SsaHeapOwnerAction.ACQUIRE : SsaHeapOwnerAction.MOVE)) {
				fail (path, "MOVE_VALUE requires each exact field acquisition or disarm before another effect");
			}
		}
		verify_record_buffer_pairs (boundary.shape, boundary.leaves, boundary.buffer_pairs, path);
		for (int b = 0; b < boundary.buffers.length; b++) {
			var storage = boundary.buffers[b];
			var leaf = boundary.buffer_path (b);
			var pair = boundary.buffer_pairs[b];
			var field = record_leaf (boundary.record_type.semantic_type, leaf);
			if (!function.buffer_storage.find (storage) || storage.record_type != boundary.record_type || storage.record_source_ordinal != boundary.source_ordinal || storage.record_path == null || !storage.record_path.same_path (leaf) || !leaf.same_path (boundary.root_path (record_buffer_path (boundary.shape, b))) || storage.record_rank != boundary.buffer_rank (b) || seen.contains (leaf.spelling ()) || field == null || field.owned_cleanup != storage.cleanup || pair.shape != storage.cleanup.buffer_shape) {
				fail (path, "MOVE_VALUE buffer changed an original complete field path, rank, cleanup or root");
			}
			seen.insert (leaf.spelling (), true);
			int next = position + (int) boundary.owners.length + b + 1;
			var write = next >= block.instructions.length ? null : block.instructions[next] as SsaBufferWriteInstruction;
			bool acquiring = boundary is SsaStructBoundaryAcquire;
			if (write == null || write.record_boundary != boundary || write.place.storage != storage || write.initializes != acquiring || (acquiring ? write.pair != pair : !write.pair.is_empty)) {
				fail (path, "MOVE_VALUE requires every complete buffer acquisition/disarm before another effect");
			}
			verify_buffer_pair (pair, function, block, position, path);
			if (!acquiring) {
				consume_buffer_pair (pair, boundary, function, block, position + (int) boundary.owners.length + (int) boundary.buffers.length + 1, true, path);
			}
		}
		var acquire = boundary as SsaStructBoundaryAcquire;
		if (acquire != null) {
			if (acquire.admission_restore != null && (acquire.admission_restore.acquisition != acquire || acquire.results != acquire.admission_restore.results || acquire.source_ordinal != acquire.admission_restore.original.source_ordinal || acquire.record_type != acquire.admission_restore.original.record_type)) {
				fail (path, "checked record restoration changed its original complete caller destination");
			}
			int sources = (acquire.parameter == null ? 0 : 1) + (acquire.results == null ? 0 : 1) + (acquire.record_move == null ? 0 : 1);
			if (sources != 1) {
				fail (path, "MOVE_VALUE acquisition requires one original parameter, result or move group");
			}
			if (acquire.parameter != null) {
				if (acquire.projection != null || !function.struct_parameters.find (acquire.parameter) || acquire.parameter.shape != acquire.shape || block != function.entry) {
					fail (path, "MOVE_VALUE parameter requires its exact complete entry group");
				}
				for (int i = 0; i < acquire.leaves.length; i++) {
					if (acquire.leaves[i] != function.parameters[acquire.parameter.first_leaf + i]) {
						fail (path, "MOVE_VALUE parameter changed an original incoming channel");
					}
				}
			} else if (acquire.results != null) {
				var site = struct_consumptions.lookup (acquire.results);
				var consumed = site == null ? null : site.block.instructions[site.position] as SsaStructResultConsume;
				if (site == null || site.block != block || site.position + 1 != position || consumed == null || consumed.use_kind != StructResultUseKind.INITIALIZE || acquire.results.shape != acquire.shape) {
					fail (path, "MOVE_VALUE result lost its exact immediate complete consumption");
				}
				for (int i = 0; i < acquire.leaves.length; i++) {
					if (acquire.leaves[i] != acquire.results.leaves[i]) {
						fail (path, "MOVE_VALUE result changed an original incoming channel");
					}
				}
			} else {
				var moved = acquire.record_move;
				if (moved.consumer != acquire || moved.source_ordinal == acquire.source_ordinal || moved.shape != acquire.shape || moved.use_kind != StructResultUseKind.INITIALIZE || moved.leaves.length != acquire.leaves.length) {
					fail (path, "record subobject acquisition lost its complete original source move");
				}
				for (int i = 0; i < acquire.leaves.length; i++) {
					if (acquire.leaves[i] != moved.leaves[i]) {
						fail (path, "record subobject acquisition changed an original moved leaf");
					}
				}
			}
			return;
		}
		var move = (SsaStructBoundaryMove) boundary;
		var direct = move.consumer as SsaCallInstruction;
		var indirect = move.consumer as SsaCallableInvocation;
		var invocation = move.consumer as SsaInstruction;
		var call_moves = direct != null ? direct.record_moves : indirect == null ? null : indirect.record_moves;
		var returned = move.consumer as SsaStructReturn;
		var enumeration = move.consumer as SsaEnumConstruct;
		var inserted = move.consumer as SsaSlotsRecordTransfer;
		var field_commit = move.consumer as SsaRecordFieldCommit;
		var subobject = move.consumer as SsaStructBoundaryAcquire;
		if (subobject != null) {
			int next = position + (int) move.owners.length + (int) move.buffers.length + 1;
			if (move.use_kind != StructResultUseKind.INITIALIZE || subobject.record_move != move || subobject.shape != move.shape || subobject.leaves.length != move.leaves.length || next >= block.instructions.length || block.instructions[next] != subobject) {
				fail (path, "record subobject move requires one exact immediate complete acquisition");
			}
			for (int i = 0; i < move.leaves.length; i++) {
				if (move.leaves[i] != subobject.leaves[i]) {
					fail (path, "record subobject move changed an original captured leaf");
				}
			}
			return;
		}
		if (field_commit != null) {
			int next = position + (int) move.owners.length + (int) move.buffers.length + 1;
			var use_kind = field_commit.initializes ? StructResultUseKind.INITIALIZE : StructResultUseKind.ASSIGN;
			if (move.use_kind != use_kind || field_commit.record_move != move || field_commit.shape != move.shape || field_commit.leaves.length != move.leaves.length || next >= block.instructions.length || block.instructions[next] != field_commit) {
				fail (path, "record field move requires one exact immediate complete commit");
			}
			for (int i = 0; i < move.leaves.length; i++) {
				if (move.leaves[i] != field_commit.leaves[i]) {
					fail (path, "record field move changed an original captured leaf");
				}
			}
			return;
		}
		if (inserted != null) {
			int next = position + (int) move.owners.length + (int) move.buffers.length + 1;
			if (move.use_kind != StructResultUseKind.CONTAINER_ELEMENT || inserted.record_move != move || inserted.shape != move.shape || inserted.leaves.length != move.leaves.length || next >= block.instructions.length || block.instructions[next] != inserted) {
				fail (path, "record slot move requires one exact immediate complete consumer");
			}
			for (int l = 0; l < move.leaves.length; l++) {
				if (move.leaves[l] != inserted.leaves[l]) {
					fail (path, "record slot move changed an original captured field");
				}
			}
			return;
		}
		if (enumeration != null) {
			int matches = 0;
			foreach (var input in enumeration.fields) {
				if (input.record_move != move || !input.field.owns_record || input.field.semantic_type != move.shape.semantic_type || input.leaves.length != move.leaves.length) {
					continue;
				}
				bool exact = true;
				for (int l = 0; l < move.leaves.length; l++) {
					exact &= input.leaves[l] == move.leaves[l];
				}
				if (exact) {
					matches++;
				}
			}
			if (matches != 1 || move.use_kind != StructResultUseKind.ENUM_PAYLOAD || !block.instructions.find (enumeration)) {
				fail (path, "record enum payload requires one exact complete original constructor field");
			}
			bool found = false;
			foreach (var instruction in block.instructions) {
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
				if (!found) {
					continue;
				}
				var event = instruction as SsaHeapOwnerEvent;
				var write = instruction as SsaBufferWriteInstruction;
				if (!(instruction is SsaStructBoundaryMove || instruction is SsaEnumScalarCommit || (event != null && event.action == SsaHeapOwnerAction.MOVE && (event.effect is SsaStructBoundaryMove || event.effect is SsaEnumScalarCommit)) || (write != null && write.record_boundary is SsaStructBoundaryMove))) {
					fail (path, "record enum payload cannot commit before another payload effect");
				}
			}
		} else if (call_moves != null) {
			if (move.use_kind != StructResultUseKind.ARGUMENT || !call_moves.find (move) || !block.instructions.find (invocation)) {
				fail (path, "MOVE_VALUE argument lost its exact call commit");
			}
			bool found = false;
			foreach (var instruction in block.instructions) {
				if (instruction == move) {
					found = true;
					continue;
				}
				if (instruction == invocation) {
					if (!found) {
						fail (path, "MOVE_VALUE must commit before its exact consumer");
					}
					break;
				}
				var event = instruction as SsaHeapOwnerEvent;
				var disarm = instruction as SsaBufferWriteInstruction;
				var constructor = direct as SsaLifecycleCallInstruction;
				bool restored = constructor != null && constructor.constructs && constructor.storage.fallible && fallible_restore_effect (instruction, constructor);
				if (found && !(restored || instruction is SsaStructBoundaryMove || instruction is SsaEnumCommit || (event != null && (event.action == SsaHeapOwnerAction.MOVE || (event.action == SsaHeapOwnerAction.READ && event.effect == invocation))) || (disarm != null && disarm.pair.is_empty))) {
					fail (path, "MOVE_VALUE cannot commit before another argument effect (%s)".printf (instruction.get_type ().name ()));
				}
			}
		} else {
			if (returned == null || move.use_kind != StructResultUseKind.RETURN || block.terminator != returned || returned.record_move != move || returned.shape != move.shape || returned.leaves.length != move.leaves.length) {
				fail (path, "MOVE_VALUE return lost its exact complete consumer");
			}
			for (int i = 0; i < move.leaves.length; i++) {
				if (returned.leaves[i] != move.leaves[i]) {
					fail (path, "MOVE_VALUE return changed a committed field");
				}
			}
		}
	}

	private void verify_record_take(SsaRecordTake take, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		verify_record_fields (take.source, take.pointer, take.fields, function, block, position, path);
		var destination = take.destination;
		var moved = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaHeapOwnerEvent;
		var acquired = position + 2 >= block.instructions.length ? null : block.instructions[position + 2] as SsaHeapOwnerEvent;
		if (destination == null || !function.heap_owners.find (destination) || destination.record_type != null || destination.record_path != null || destination.cleanup != take.source.cleanup || take.path == null || !take.path.same_path (take.source.record_path) || take.rank != take.source.record_rank || moved == null || moved.action != SsaHeapOwnerAction.MOVE || moved.owner != take.source || moved.value != take.pointer || moved.effect != take || acquired == null || acquired.action != SsaHeapOwnerAction.ACQUIRE || acquired.owner != destination || acquired.value != take.pointer || acquired.effect != null) {
			fail (path, "record field take lost its original path, pointer, cleanup or unique scalar destination disposition");
		}
	}

	private void verify_record_replace(SsaRecordReplace replace, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		verify_record_fields (replace.owner, replace.old_value, replace.fields, function, block, position, path);
		if (replace.path == null || !replace.path.same_path (replace.owner.record_path) || replace.rank != replace.owner.record_rank || replace.incoming.semantic_type != replace.old_value.semantic_type) {
			fail (path, "record replacement lost its original path/rank or exact incoming leaf type");
		}
		verify_value (replace.incoming, function, block, position, path + "/incoming");
		int next = position + 1;
		if (replace.source_owner != null) {
			var moved = next >= block.instructions.length ? null : block.instructions[next++] as SsaHeapOwnerEvent;
			if (!function.heap_owners.find (replace.source_owner) || replace.source_owner.record_type != null || replace.source_owner.cleanup != replace.owner.cleanup || moved == null || moved.owner != replace.source_owner || moved.action != SsaHeapOwnerAction.MOVE || moved.value != replace.incoming || moved.effect != null) {
				fail (path, "record replacement lost exact incoming scalar owner disposition");
			}
		} else {
			var definition = replace.incoming as SsaDefinition;
			var site = definition == null ? null : definitions.lookup (definition);
			var producer = site == null || site.position < 0 ? null : site.block.instructions[site.position];
			var success = producer as SsaCallSuccess;
			var native_call = success == null ? producer as SsaCallInstruction : success.call;
			var foreign_call = producer as SsaCCallInstruction;
			if (callable_result_cleanup (producer) != replace.owner.cleanup && (native_call == null || native_call.target.owned_cleanup != replace.owner.cleanup || (native_call.target.throws_type != null && (success == null || native_call.owned_success != success))) && (foreign_call == null || foreign_call.target.owned_cleanup != replace.owner.cleanup)) {
				fail (path, "record replacement requires an independently proved exact owned producer");
			}
			if (record_producers.contains (replace.incoming)) {
				fail (path, "record replacement cannot duplicate incoming producer ownership");
			}
			record_producers.insert (replace.incoming, true);
		}
		var cleanup = next >= block.instructions.length ? null : block.instructions[next++];
		var ended = next >= block.instructions.length ? null : block.instructions[next++] as SsaHeapOwnerEvent;
		var acquired = next >= block.instructions.length ? null : block.instructions[next] as SsaHeapOwnerEvent;
		if (cleanup != replace.retirement || replace.retirement.value != replace.old_value || replace.retirement.cleanup != replace.owner.cleanup || replace.retirement.record_replacement != replace || ended == null || ended.owner != replace.owner || ended.action != SsaHeapOwnerAction.END || ended.value != replace.old_value || ended.effect != replace.retirement || acquired == null || acquired.owner != replace.owner || acquired.action != SsaHeapOwnerAction.ACQUIRE || acquired.value != replace.incoming || acquired.effect != replace) {
			fail (path, "record replacement must acquire incoming ownership, retire exactly the old field, then publish the new owner");
		}
	}

	private void verify_constructor_abort(SsaConstructorAbort abort, SsaFunction function, string path) throws SsaError {
		var constructor = function as SsaConstructor;
		var owner = constructor == null ? null : constructor.declaring_class;
		if (owner == null || abort.receiver != function.implicit_receiver || !ConstructorContracts.admitted (owner.foreign_export, owner.allocation_policy, constructor.member_ordinal, function.throws_type)) {
			fail (path, "constructor abort requires its exact admitted initializing receiver and checked effect");
		}
		int cursor = 0;
		for (int f = owner.fields.length - 1; f >= 0; f--) {
			var field = owner.fields[f];
			if (field.owned_cleanup == null && field.record_owner == null && !field.text_snapshot && !(field.semantic_type is OwnerSlotsType)) {
				continue;
			}
			var cleanup = (field.semantic_type is OwnerSlotsType) ? field.slots_cleanup : field.owned_cleanup;
			if (cursor >= abort.fields.length || abort.fields[cursor].field != field || abort.fields[cursor].cleanup != cleanup) {
				fail (path, "constructor abort lost exact complete field retirement recipes");
			}
			verify_field_visibility (field, function, path);
			var recipe = abort.fields[cursor++];
			if (field.record_owner != null) {
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

	private bool fallible_restore_effect(SsaInstruction instruction, SsaLifecycleCallInstruction call) {
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
			foreach (var restored in call.buffer_restores) {
				if (write.pair == restored.pair && write.place == restored.argument.disarm.place) {
					return true;
				}
			}
		}
		foreach (var restored in call.record_restores) {
			var consumed = instruction as SsaStructResultConsume;
			if (consumed != null && consumed.results == restored.results || instruction == restored.acquisition || event != null && event.action == SsaHeapOwnerAction.ACQUIRE && event.effect == restored.acquisition || write != null && write.record_boundary == restored.acquisition) {
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
				if (restored.pair == write.pair && restored.argument.disarm.place.storage == write.place.storage) {
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

	private void verify_record_restore_group(SsaRecordAdmissionRestore restored, SsaCallInstruction consumer, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var moved = restored.original;
		var group = restored.results;
		var acquired = restored.acquisition;
		if (!consumer.record_moves.find (moved) || moved.consumer != consumer || group.shape != moved.shape || group.shape.mode != StructValueMode.MOVE_VALUE || group.leaves.length != moved.leaves.length || struct_results.lookup (group) != restored || acquired == null || acquired.admission_restore != restored || acquired.results != group || acquired.record_type != moved.record_type || acquired.source_ordinal != moved.source_ordinal || acquired.owners.length != moved.owners.length || acquired.buffers.length != moved.buffers.length || position + 2 >= block.instructions.length || block.instructions[position + 2] != acquired) {
			fail (path, "record admission restore lost complete original capture and immediate caller acquisition");
		}
		for (int i = 0; i < group.leaves.length; i++) {
			if (group.leaves[i].semantic_type != moved.shape.leaves[i].semantic_type) {
				fail (path, "record admission restoration changed an original physical leaf type");
			}
			verify_value (moved.leaves[i], function, block, position, path + "/original", false, false, false, moved.shape.leaves[i] is StructBufferLeafPath);
		}
		for (int i = 0; i < moved.owners.length; i++) {
			if (acquired.owners[i] != moved.owners[i]) {
				fail (path, "record admission restoration changed an original caller field owner");
			}
		}
		for (int i = 0; i < moved.buffers.length; i++) {
			if (acquired.buffers[i] != moved.buffers[i] || acquired.buffer_pairs[i] != group.buffers[i]) {
				fail (path, "record admission restoration changed an original complete caller buffer");
			}
		}
	}

	private void verify_frame_record_restore(SsaFrameRecordRestore restored, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var creation = restored.creation;
		var site = creation == null ? null : buffer_sites.lookup (creation);
		if (creation == null || !creation.checked_admission || creation.exception_result == null || site == null || site.function != function || site.block != block || site.position >= position || !creation.record_restores.find (restored) || restored.admission_value () != creation.result) {
			fail (path, "checked record restore requires its exact earlier unpublished task factory");
		}
		verify_record_restore_group (restored, creation, function, block, position, path);
		for (int i = site.position + 1; i < position; i++) {
			if (!frame_restore_effect (block.instructions[i], creation)) {
				fail (path, "checked record restoration cannot cross another effect after admission");
			}
		}
	}

	private void verify_fallible_record_restore(SsaFallibleRecordRestore restored, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		var call = restored.call;
		var site = call == null ? null : buffer_sites.lookup (call);
		if (call == null || !call.constructs || !call.storage.fallible || !call.storage.heap_allocated || site == null || site.function != function || site.block != block || site.position <= position || !call.record_restores.find (restored) || restored.admission_value () != call.receiver) {
			fail (path, "fallible record restore requires its exact later constructor and admission receiver");
		}
		verify_record_restore_group (restored, call, function, block, position, path);
		int end = position + 3 + (int) restored.original.owners.length + (int) restored.original.buffers.length;
		for (int i = end; i < site.position; i++) {
			if (!fallible_restore_effect (block.instructions[i], call)) {
				fail (path, "fallible record restoration cannot cross another effect before its constructor");
			}
		}
	}

	private void verify_instruction(SsaInstruction instruction, SsaFunction function, SsaBlock block, int position, string path) throws SsaError {
		if (instruction is SsaScopedAllocator) {
			var scoped = (SsaScopedAllocator) instruction;
			var type = scoped.result.semantic_type as HandleType;
			var read = buffer_reads.lookup (scoped.pair);
			var acquire = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaHeapOwnerEvent;
			if (type == null || !type.is_scoped_allocator () || type.context_cleanup != "astra_context17_destroy" || function.async_body != null || !scoped.loan.valid () || !function.buffer_storage.find (scoped.backing) || scoped.backing.owner_ordinal != scoped.loan.backing_ordinal || scoped.backing.record_type != null || scoped.backing.cleanup.buffer_type.element_type.kind != TypeKind.U8 || scoped.backing.text_extent == null || !function.heap_owners.find (scoped.owner) || scoped.owner.source_ordinal != scoped.loan.context_ordinal || scoped.owner.text_extent == null || scoped.owner.text_extent.ordinal != scoped.loan.region_ordinal || !scoped.backing.text_extent.outlives (scoped.owner.text_extent) || scoped.owner.cleanup.external_symbol != type.context_cleanup || !matches_cleanup (type, scoped.owner.cleanup) || !cleanups.contains (scoped.owner.cleanup) || acquire == null || acquire.owner != scoped.owner || acquire.action != SsaHeapOwnerAction.ACQUIRE || acquire.value != scoped.result || acquire.effect != scoped || read == null || read.place.storage != scoped.backing || position < 1 || block.instructions[position - 1] != read) {
				fail (path, "scoped context lost exact lexical owner, backing pair or immediate acquisition");
			}
			verify_buffer_pair (scoped.pair, function, block, position, path);
			verify_buffer_interval (read, function, block, position, path);
			verify_value (scoped.kind, function, block, position, path);
			verify_value (scoped.slots, function, block, position, path);
			if (scoped.kind.semantic_type.kind != TypeKind.INT || scoped.slots.semantic_type.kind != TypeKind.INT) {
				fail (path, "scoped context configuration requires int channels");
			}
			return;
		}
		if (instruction is SsaFrameRecordRestore) {
			verify_frame_record_restore ((SsaFrameRecordRestore) instruction, function, block, position, path);
			return;
		}
		if (instruction is SsaFallibleRecordRestore) {
			verify_fallible_record_restore ((SsaFallibleRecordRestore) instruction, function, block, position, path);
			return;
		}
		if (instruction is SsaConstructorAbort) {
			verify_constructor_abort ((SsaConstructorAbort) instruction, function, path);
			if (!(block.terminator is SsaExceptionReturn) || block.instructions[block.instructions.length - 1] != instruction) {
				fail (path, "constructor abort belongs immediately before exceptional completion");
			}
			return;
		}
		if (instruction is SsaRecordFieldCommit) {
			var commit = (SsaRecordFieldCommit) instruction;
			verify_record_field (commit.destination, function, block, position, path);
			verify_struct_shape (commit.shape, commit.destination.semantic_type, path);
			if (commit.shape.mode != StructValueMode.MOVE_VALUE || commit.leaves.length != commit.shape.leaves.length || (commit.record_move == null) == (commit.results == null)) {
				fail (path, "record field commit requires one complete moved or produced record");
			}
			if (commit.record_move != null && commit.record_move.consumer != commit) {
				fail (path, "record field move lost exact consumer");
			}
			if (commit.results != null && (struct_consumptions.lookup (commit.results) == null || commit.results.shape != commit.shape)) {
				fail (path, "record field producer lacks complete original consumption");
			}
			if (commit.results != null) {
				foreach (var pair in commit.results.buffers) {
					verify_buffer_pair (pair, function, block, position, path);
					consume_buffer_pair (pair, commit, function, block, position, true, path);
				}
			}
			for (int i = 0; i < commit.leaves.length; i++) {
				if (commit.leaves[i].semantic_type != commit.shape.leaves[i].semantic_type || (commit.results != null && commit.leaves[i] != commit.results.leaves[i])) {
					fail (path, "record field commit changed an original leaf");
				}
				verify_value (commit.leaves[i], function, block, position, path + "/leaf", false, false, true, commit.shape.leaves[i] is StructBufferLeafPath);
			}
			if (commit.initializes) {
				if (!(function is SsaConstructor) || commit.destination.pointer != function.implicit_receiver || commit.destination.field.containing_type != ((SsaConstructor) function).declaring_class || field_state == null || field_state.is_possible (commit.destination.field.ordinal)) {
					fail (path, "record field requires one fresh exact constructor initialization");
				}
				field_state.initialize (commit.destination.field.ordinal);
			} else if (field_state != null) {
				fail (path, "constructor record field cannot be replaced before complete publication");
			}
			return;
		}
		if (instruction is SsaRecordFieldDrop) {
			var drop = (SsaRecordFieldDrop) instruction;
			verify_record_field (drop.source, function, block, position, path);
			verify_struct_shape (drop.shape, drop.source.semantic_type, path);
			if (drop.shape.mode != StructValueMode.MOVE_VALUE) {
				fail (path, "record field retirement requires complete ownership shape");
			}
			if (!record_field_epilogues.contains (drop)) {
				fail (path, "record field drop lacks exact destructor epilogue authority");
			}
			return;
		}
		if (instruction is SsaStructBoundary) {
			verify_record_boundary ((SsaStructBoundary) instruction, function, block, position, path);
			return;
		}
		if (instruction is SsaRecordTake) {
			verify_record_take ((SsaRecordTake) instruction, function, block, position, path);
			return;
		}
		if (instruction is SsaRecordReplace) {
			verify_record_replace ((SsaRecordReplace) instruction, function, block, position, path);
			return;
		}
		if (instruction is SsaLazyDrop) {
			var drop = (SsaLazyDrop) instruction;
			var destructor = function as SsaDestructor;
			if (destructor == null || !drop.property_member.is_owned_lazy || drop.property_member.declaring_type != destructor.declaring_class || !lazy_epilogues.contains (drop) || lazy_seen.contains (drop)) {
				fail (path, "cache retirement requires exact declaring destructor and owned lazy property");
			}
			lazy_seen.insert (drop, true);
			return;
		}
		if (instruction is SsaLazyObserve) {
			var observe = (SsaLazyObserve) instruction;
			var getter = function as SsaPropertyGetter;
			if (getter == null || getter.property_member != observe.property_member || !observe.property_member.is_owned_lazy || observe.result == null || observe.result.semantic_type != getter.return_type) {
				fail (path, "lazy observation lost exact receiver and property provenance");
			}
			return;
		}
		if (instruction is SsaActorSend) {
			var send = (SsaActorSend) instruction;
			var type = send.sender.semantic_type as ClosureHandleType;
			var error = structs.lookup (send.error_type) as SsaClass;
			if (type == null || !type.actor || !type.supported () || send.action < Astra.Source.ActorAction.SEND || send.action > Astra.Source.ActorAction.CANCEL || function.async_body != null || error == null || !error.exception_root || error.parent_class != null || error.constructor == null || error.constructor.throws_type != null || error.constructor.parameters.length != 1 || !(error.constructor.parameters[0].semantic_type is StringType) || send.result == null || send.result.semantic_type != send.error_type) {
				fail (path, "Actor operation lost exact sender, action or nominated Error constructor");
			}
			var branch = block.terminator as SsaConditionalBranch;
			var site = branch == null ? null : definitions.lookup (branch.condition as SsaDefinition);
			var condition = site == null || site.position < 0 ? null : site.block.instructions[site.position] as SsaBinaryInstruction;
			if (condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != send.result || !(condition.right is SsaNullPointerConstant) || branch.true_edge.target == branch.false_edge.target) {
				fail (path, "Actor operation requires exact distinct success/error edges");
			}
			int previous = position - 1;
			if (send.sender_owner == null) {
				var parameter = send.sender as SsaFunctionParameter;
				if (parameter == null || !function.parameters.find (parameter) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					fail (path, "Actor operation requires exact borrowed sender parameter");
				}
			} else {
				var read = previous < 0 ? null : block.instructions[previous--] as SsaHeapOwnerEvent;
				if (!function.heap_owners.find (send.sender_owner) || send.sender_owner.cleanup.closure_type != type || read == null || read.action != SsaHeapOwnerAction.READ || read.owner != send.sender_owner || read.value != send.sender || read.effect != send) {
					fail (path, "Actor operation lost exact preceding live sender loan");
				}
			}
			verify_value (send.sender, function, block, position, path + "/sender", true);
			if (send.action == Astra.Source.ActorAction.SEND) {
				if (send.message == null || send.message.semantic_type != type.actor_message) {
					fail (path, "Actor message differs from exact sender signature");
				}
				if (type.actor_message is ClassType) {
					var move = previous < 0 ? null : block.instructions[previous] as SsaHeapOwnerEvent;
					if (send.message_owner == null || !function.heap_owners.find (send.message_owner) || !send.message_owner.cleanup.is_heap_object || send.message_owner.cleanup.object_class.polymorphic || send.message_owner.cleanup.object_class.semantic_type != type.actor_message || move == null || move.action != SsaHeapOwnerAction.MOVE || move.owner != send.message_owner || move.value != send.message || move.effect != null) {
						fail (path, "Actor admission requires exact prior sole heap-message disposition");
					}
				} else if (send.message_owner != null) {
					fail (path, "Actor copied scalar cannot acquire an owner");
				}
				verify_value (send.message, function, block, position, path + "/message", type.actor_message is ClassType);
			} else if (send.message != null || send.message_owner != null) {
				fail (path, "Actor lifecycle operation cannot carry a message owner");
			}
			return;
		}
		if (instruction is SsaClosureBind) {
			var closure = (SsaClosureBind) instruction;
			var type = closure.result == null ? null : closure.result.semantic_type as ClosureHandleType;
			var target = closure.target;
			if (type == null || !type.supported () || (type.actor ? closure.actor_binding == null || !closure.actor_binding.valid () || !thread_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true) || !thread_capture_type (type.actor_message, new HashTable<SemanticType, bool> (direct_hash, direct_equal), true) : closure.actor_binding != null || type.environment_type.concurrency_policy_identity == 16) || (type.threaded && !thread_capture_type (type.environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal))) || !cleanups.contains (closure.cleanup) || !matches_cleanup (type, closure.cleanup) || closure.environment.semantic_type != type.environment_type || target == null || target.kind != CallableKind.FUNCTION || !functions.contains (target) || target.implicit_receiver != null || target.async_body != null || target.throws_type != type.throws_type || target.result_contract != type.result_contract || target.return_type != type.result_type || (type.result_contract == ResultOwnershipContract.OWNED_TRANSFER && type.result_type is ClassType && !target.heap_result) || target.parameters.length != CallableRecordGroups.physical_parameters (type, target.struct_parameters).length + 1 || target.parameters[0].semantic_type != type.environment_type || target.parameters[0].pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				fail (path, "closure binding lost exact native signature or environment destruction authority");
			}
			if (!type.actor) {
				try {
					type.verify_records (type.record_parameters, struct_fields);
					type.verify_records (target.struct_parameters, struct_fields, 1, 1);
				} catch (StructLeafError error) {
					fail (path, error.message);
				}
			}
			for (int p = 0; p < CallableRecordGroups.physical_parameters (type, target.struct_parameters).length; p++) {
				if (target.parameters[p + 1].semantic_type != CallableRecordGroups.physical_parameters (type, target.struct_parameters)[p] || ((type.actor && CallableRecordGroups.physical_parameters (type, target.struct_parameters)[p] is ClassType) ? target.parameters[p + 1].pointer_contract != PointerParameterContract.OWNED_TRANSFER || !target.parameters[p + 1].heap_object : target.parameters[p + 1].pointer_contract != CallableRecordGroups.physical_contracts (type, target.struct_parameters)[p] || CallableRecordGroups.physical_contracts (type, target.struct_parameters)[p] == PointerParameterContract.OWNED_TRANSFER && CallableRecordGroups.physical_parameters (type, target.struct_parameters)[p] is ClassType && !target.parameters[p + 1].heap_object)) {
					fail (path, "closure code scalar signature mismatch");
				}
			}
			var previous = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
			if (previous == null || previous.action != SsaHeapOwnerAction.MOVE || previous.owner == null || !previous.owner.cleanup.is_heap_object || previous.owner.cleanup.object_class != closure.cleanup.closure_environment || previous.value != closure.environment) {
				fail (path, "closure acquisition requires preceding exact sole heap environment owner disposition");
			}
			verify_value (closure.environment, function, block, position, path + "/environment", true);
			return;
		}
		if (instruction is SsaRetainedOperation) {
			var operation = (SsaRetainedOperation) instruction;
			if (!RetainedContracts.valid_action (operation.action) || !RetainedContracts.accepts (operation.action, operation.callee.semantic_type) || operation.result == null || operation.result.semantic_type.kind != TypeKind.INT || operation.arguments.length != RetainedContracts.arity (operation.action)) {
				fail (path, "retained callback requires exact finite action and carrier signature");
			}
			if (!thread_capture_type (((ClosureHandleType) operation.callee.semantic_type).environment_type, new HashTable<SemanticType, bool> (direct_hash, direct_equal), false, true)) {
				fail (path, "retained callback cannot capture thread-bound state");
			}
			var parameter = operation.callee as SsaFunctionParameter;
			if (operation.source_owner == null) {
				if (parameter == null || !function.parameters.find (parameter) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					fail (path, "retained callback requires borrowed parameter or live owner loan");
				}
			} else {
				var read = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
				if (!function.heap_owners.find (operation.source_owner) || operation.source_owner.cleanup.closure_type != operation.callee.semantic_type || read == null || read.action != SsaHeapOwnerAction.READ || read.owner != operation.source_owner || read.value != operation.callee || read.effect != operation) {
					fail (path, "retained callback lost exact preceding owner loan");
				}
			} verify_value (operation.callee, function, block, position, path + "/retained", true);
			foreach (var argument in operation.arguments) {
				verify_value (argument, function, block, position, path + "/argument");
				if (argument.semantic_type != operation.result.semantic_type) {
					fail (path, "retained callback int argument mismatch");
				}
			}
			return;
		}
		if (instruction is SsaClosureCallSuccess) {
			var success = (SsaClosureCallSuccess) instruction;
			var type = success.call.callee.semantic_type as ClosureHandleType;
			var site = success.call.result == null ? null : definitions.lookup (success.call.result);
			if (type == null || type.throws_type == null || site == null || site.function != function || success.call.owned_success != success || !guarded_effect_success (success.call.result, block)
			    || ((type.result_type.kind == TypeKind.VOID || type.result_type.is_struct_storage ()) ? success.result != null : success.result == null || success.result.semantic_type != type.result_type)) {
				fail (path, "checked closure result requires exact dominating null-error successor");
			}
			verify_callable_record_result (type, success.struct_result, success, path);
			return;
		}
		if (instruction is SsaClosureCall) {
			var call = (SsaClosureCall) instruction;
			var type = call.callee.semantic_type as ClosureHandleType;
			verify_invocation_result (call, type, function, path);
			try {
				if (type != null) {
					type.verify_records (type.record_parameters, struct_fields);
					type.verify_records (call.struct_arguments, struct_fields);
				}
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			if (type == null || type.threaded || type.actor || (type.throws_type == null ? ((type.result_type.kind == TypeKind.VOID || type.result_type.is_struct_storage ()) ? call.result != null : call.result == null || call.result.semantic_type != type.result_type) : call.result == null || !(call.result.semantic_type is ClassType) || ((ClassType) call.result.semantic_type).parent_type != null || !type.throws_type.derives_from ((ClassType) call.result.semantic_type)) || call.arguments.length != CallableRecordGroups.physical_parameters (type, call.struct_arguments).length) {
				fail (path, "closure invocation requires exact borrowed carrier and scalar signature");
			}
			if (type.throws_type == null) {
				verify_callable_record_result (type, call.struct_result, call, path);
			} else if (call.struct_result != null) {
				fail (path, "checked invocation cannot publish record leaves before success");
			}
			if (type.throws_type != null) {
				var branch = block.terminator as SsaConditionalBranch;
				var site = branch == null ? null : definitions.lookup (branch.condition as SsaDefinition);
				var condition = site == null || site.position < 0 ? null : site.block.instructions[site.position] as SsaBinaryInstruction;
				if (condition == null || condition.operator_kind != BinaryOperator.EQUAL || condition.left != call.result || !(condition.right is SsaNullPointerConstant) || branch.true_edge.target == branch.false_edge.target) {
					fail (path, "checked closure invocation requires exact distinct success/error edges");
				}
			}
			var parameter = call.callee as SsaFunctionParameter;
			if (call.source_owner == null) {
				if (parameter == null || !function.parameters.find (parameter) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
					fail (path, "closure invocation requires exact borrowed parameter or live owned local loan");
				}
			} else {
				var read = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
				if (!function.heap_owners.find (call.source_owner) || call.source_owner.cleanup.closure_type != type || read == null || read.action != SsaHeapOwnerAction.READ || read.owner != call.source_owner || read.value != call.callee || read.effect != call) {
					fail (path, "closure invocation lost exact preceding retained owner loan");
				}
			}
			verify_value (call.callee, function, block, position, path + "/closure", true);
			verify_callable_record_moves (call, call.arguments, call.struct_arguments, call.record_moves, function, block, position, path);
			verify_callable_arguments (call, call, CallableRecordGroups.physical_contracts (type, call.struct_arguments), call.struct_arguments, function, block, position, path);
			for (int p = 0; p < call.arguments.length; p++) {
				if (call.arguments[p].semantic_type != CallableRecordGroups.physical_parameters (type, call.struct_arguments)[p]) {
					fail (path, "closure invocation scalar signature mismatch");
				}
			}
			return;
		}
		if (instruction is SsaSharedOperation) {
			var operation = (SsaSharedOperation) instruction;
			if (operation.result == null || !SharedContracts.matches (operation.action, operation.operand.semantic_type, operation.result.semantic_type)) {
				fail (path, "shared operation lost exact strong/weak payload capability");
			}
			if (operation.action == SharedAction.BORROW) {
				if (operation.source_owner == null && !(operation.operand is SsaFunctionParameter && ((SsaFunctionParameter) operation.operand).pointer_contract == PointerParameterContract.BORROWED_NOESCAPE)) {
					fail (path, "shared payload loan requires exact named strong owner or borrowed parameter");
				}
				int consumers = 0;
				foreach (var consumer_block in function.blocks) {
					foreach (var candidate in consumer_block.instructions) {
						var call = candidate as SsaCallInstruction;
						if (call == null) {
							continue;
						}
						for (int argument = 0; argument < call.arguments.length; argument++) {
							if (call.arguments[argument] != operation.result) {
								continue;
							}
							consumers++;
							if (consumer_block != block || argument >= call.target.parameters.length || call.target.parameters[argument] != operation.borrower) {
								fail (path, "shared payload loan lost its exact original borrowed call parameter");
							}
						}
					}
				}
				if (consumers != 1) {
					fail (path, "shared payload loan requires one direct borrowed call consumer");
				}
				if (operation.cleanup != null || operation.borrower == null || operation.borrower.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || operation.borrower.semantic_type != operation.result.semantic_type) {
					fail (path, "shared payload loan lost exact borrowed call parameter");
				}
			} else if (operation.cleanup == null || !cleanups.contains (operation.cleanup) || !matches_cleanup (operation.result.semantic_type, operation.cleanup)) {
				fail (path, "shared producer lost exact native cleanup identity");
			}
			if (operation.source_owner != null) {
				var read = position <= 0 ? null : block.instructions[position - 1] as SsaHeapOwnerEvent;
				if (read == null || read.action != SsaHeapOwnerAction.READ || read.owner != operation.source_owner || read.value != operation.operand || read.effect != operation) {
					fail (path, "shared operation lost exact live backing owner READ");
				}
			}
			if (operation.action == SharedAction.ACQUIRE) {
				var moved = position <= 0 ? null : block.instructions[position - 1] as SsaHeapOwnerEvent;
				if (moved == null || moved.action != SsaHeapOwnerAction.MOVE || moved.owner == null || !moved.owner.cleanup.is_heap_object || moved.value != operation.operand || moved.owner.cleanup.object_class.semantic_type != operation.operand.semantic_type) {
					fail (path, "shared acquisition lost immediate exact unique payload move");
				}
			}
			verify_value (operation.operand, function, block, position, path, true, false);
			return;
		}
		if (instruction is SsaFunctionValueCall) {
			var call = (SsaFunctionValueCall) instruction;
			var signature = call.callee.semantic_type as FunctionValueType;
			verify_invocation_result (call, signature, function, path);
			if (signature == null || ((signature.result_type.kind == TypeKind.VOID || signature.result_type.is_struct_storage ()) ? call.result != null : call.result == null || call.result.semantic_type != signature.result_type)) {
				fail (path, "function invocation requires exact code signature and arity");
			}
			try {
				signature.verify_records (signature.record_parameters, struct_fields);
				signature.verify_records (call.struct_arguments, struct_fields);
			} catch (StructLeafError error) {
				fail (path, error.message);
			}
			if (call.arguments.length != CallableRecordGroups.physical_parameters (signature, call.struct_arguments).length) {
				fail (path, "function invocation requires exact code signature and arity");
			}
			verify_callable_record_result (signature, call.struct_result, call, path);
			verify_value (call.callee, function, block, position, path + "/callee", signature is CallbackType);
			verify_callable_record_moves (call, call.arguments, call.struct_arguments, call.record_moves, function, block, position, path);
			verify_callable_arguments (call, call, CallableRecordGroups.physical_contracts (signature, call.struct_arguments), call.struct_arguments, function, block, position, path);
			for (int p = 0; p < call.arguments.length; p++) {
				if (call.arguments[p].semantic_type != CallableRecordGroups.physical_parameters (signature, call.struct_arguments)[p]) {
					fail (path, "function invocation argument signature mismatch");
				}
			}
			return;
		}
		if (instruction is SsaSlotsRecordTransfer) {
			var transfer = (SsaSlotsRecordTransfer) instruction;
			verify_slots_place (transfer.store, function, block, position, true, path);
			verify_struct_shape (transfer.shape, ((OwnerSlotsType) transfer.store.semantic_type).element, path);
			if ((transfer.shape.mode == StructValueMode.MOVE_VALUE) != (transfer.record_move != null) || transfer.leaves.length != transfer.shape.leaves.length) {
				fail (path, "record slot copy requires its exact complete value group");
			}
			if (transfer.record_move != null && (transfer.record_move.consumer != transfer || !block.instructions.find (transfer.record_move))) {
				fail (path, "record slot insertion lacks its exact complete ownership commit");
			}
			if (transfer.index != null) {
				verify_value (transfer.index, function, block, position, path);
				if (transfer.index.semantic_type.kind != TypeKind.INT) {
					fail (path, "record slot replacement requires I32 index");
				}
			}
			for (int l = 0; l < transfer.leaves.length; l++) {
				if (transfer.leaves[l].semantic_type != transfer.shape.leaves[l].semantic_type) {
					fail (path, "record slot copy changed an exact leaf type");
				}
				verify_value (transfer.leaves[l], function, block, position, path, false, false, true, transfer.shape.leaves[l] is StructBufferLeafPath);
			}
			return;
		}
		if (instruction is SsaSlotsRecordRead) {
			var read = (SsaSlotsRecordRead) instruction;
			var group = read.results;
			verify_slots_place (read.store, function, block, position, true, path);
			verify_struct_shape (group.shape, ((OwnerSlotsType) read.store.semantic_type).element, path);
			verify_value (read.index, function, block, position, path);
			if (read.index.semantic_type.kind != TypeKind.INT || (group.shape.mode == StructValueMode.MOVE_VALUE && !read.remove) || group.leaves.length != group.shape.leaves.length || struct_results.lookup (group) != read) {
				fail (path, "record slot read lost complete exact copied result group authority");
			}
			for (int l = 0; l < group.leaves.length; l++) {
				if (group.leaves[l].semantic_type != group.shape.leaves[l].semantic_type) {
					fail (path, "record slot read changed an exact physical result leaf");
				}
			}
			return;
		}
		if (instruction is SsaSlotsEffect) {
			var operation = (SsaSlotsEffect) instruction;
			if ((operation.action == SsaSlotsAction.REPLACE) != (operation.index != null)) {
				fail (path, "owner-slot effect lost exact replacement index");
			}
			if (operation.index != null) {
				verify_value (operation.index, function, block, position, path);
				if (operation.index.semantic_type.kind != TypeKind.INT) {
					fail (path, "owner-slot replace requires I32 index");
				}
			}
			verify_slots_place (operation.store, function, block, position, operation.action != SsaSlotsAction.INITIALIZE, path);
			if (operation.action == SsaSlotsAction.INITIALIZE) {
				if (operation.incoming != null || operation.owner != null || field_state == null || !(function is SsaConstructor) || operation.store.pointer != function.implicit_receiver || operation.store.field.containing_type != ((SsaConstructor) function).declaring_class || field_state.is_possible (operation.store.field.ordinal)) {
					fail (path, "owner-slot initialization lost exact constructor field and zero state");
				}
				field_state.initialize (operation.store.field.ordinal);
			} else if ((operation.action == SsaSlotsAction.APPEND || operation.action == SsaSlotsAction.REPLACE)) {
				var owner = operation.owner;
				if (owner == null || owner.ordinal < 0 || owner.ordinal >= function.heap_owners.length || function.heap_owners[owner.ordinal] != owner || owner.cleanup != operation.store.field.slots_cleanup || operation.incoming == null || operation.incoming.semantic_type != ((OwnerSlotsType) operation.store.semantic_type).element) {
					fail (path, "owner-slot append lost exact heap input ownership");
				}
				verify_value (operation.incoming, function, block, position, path);
				var disarm = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaHeapOwnerEvent;
				if (disarm == null || disarm.action != SsaHeapOwnerAction.MOVE || disarm.owner != owner || disarm.value != operation.incoming || disarm.effect != operation) {
					fail (path, "owner-slot append lacks one immediate exact input disarm");
				}
			} else if (operation.action == SsaSlotsAction.DROP) {
				if (operation.incoming != null || operation.owner != null || !slots_epilogues.contains (operation)) {
					fail (path, "owner-slot drop lacks exact destructor epilogue authority");
				}
			} else {
				fail (path, "unsupported owner-slot effect");
			} return;
		}
		if (instruction is SsaSlotsValueInstruction) {
			var v = (SsaSlotsValueInstruction) instruction;
			verify_slots_place (v.store, function, block, position, true, path);
			if (v.operand != null) {
				verify_value (v.operand, function, block, position, path);
				if (v.operand.semantic_type.kind != TypeKind.INT) {
					fail (path, "owner-slot operand lost exact I32 count/index");
				}
			}
			if (v.action == OwnerSlotsAction.TAKE) {
				var acquired = position + 1 < block.instructions.length ? block.instructions[position + 1] as SsaHeapOwnerEvent : null;
				if (v.owner == null || !function.heap_owners.find (v.owner) || v.owner.cleanup != v.store.field.slots_cleanup || !matches_cleanup (v.result.semantic_type, v.owner.cleanup) || v.result.semantic_type != ((OwnerSlotsType) v.store.semantic_type).element || v.operand == null || v.borrower != null || acquired == null || acquired.action != SsaHeapOwnerAction.ACQUIRE || acquired.owner != v.owner || acquired.value != v.result || acquired.effect != v) {
					fail (path, "owner-slot take lost exact immediately acquired heap owner");
				}
				return;
			}
			if (v.owner != null) {
				fail (path, "only take may carry a slot acquisition owner");
			}
			if (v.action == OwnerSlotsAction.BORROW) {
				if (v.borrower == null || v.borrower.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || v.borrower.semantic_type != ((OwnerSlotsType) v.store.semantic_type).element || v.result.semantic_type != v.borrower.semantic_type || v.operand == null) {
					fail (path, "indexed loan lost exact element, occupied index and borrower");
				}
			} else if (v.borrower != null || (v.action != OwnerSlotsAction.LENGTH && v.action != OwnerSlotsAction.CAPACITY && v.action != OwnerSlotsAction.RESERVE) || ((v.action == OwnerSlotsAction.RESERVE) != (v.operand != null)) || v.result.semantic_type.kind != (v.action == OwnerSlotsAction.RESERVE ? TypeKind.BOOL : TypeKind.INT)) {
				fail (path, "owner-slot query/reserve lost exact grouped operation shape");
			}
			return;
		}

		if (instruction is SsaRecordAcquire || instruction is SsaRecordMove) {
			verify_record_marker (instruction, function, block, position, path);
			return;
		}
		if (instruction is SsaAsyncRunStatus) {
			var run = (SsaAsyncRunStatus) instruction;
			verify_value (run.operation.result, function, block, position, path);
			if (run.operation.contract.kind != AsyncOperationKind.RUN || run.destination.definition.semantic_type != run.operation.contract.runtime.status_type || !guarded_effect_success (run.operation.exception, block)) {
				fail (path, "run status lost exact guarded root/ordinary enum association");
			}
			return;
		}
		if (instruction is SsaExecutorEnd) {
			verify_value (((SsaExecutorEnd) instruction).source, function, block, position, path);
			if (!(((SsaExecutorEnd) instruction).source.semantic_type is ExecutorType)) {
				fail (path, "executor cleanup lost its dedicated exact handle type");
			}
			return;
		}
		if (instruction is SsaTaskBorrow) {
			verify_value (((SsaTaskBorrow) instruction).source, function, block, position, path);
			return;
		}
		if (instruction is SsaTaskStarted) {
			var started = (SsaTaskStarted) instruction;
			if (started.operation.contract.kind != AsyncOperationKind.START || started.operation.task_owner != started.owner_ordinal || !guarded_effect_success (started.operation.exception, block)) {
				fail (path, "started obligation requires the exact guarded enrollment operation");
			}
			return;
		}
		if (instruction is SsaAsyncOperation) {
			var operation = (SsaAsyncOperation) instruction;
			if (!operation.contract.valid_shape (operation.executor == null ? null : operation.executor.semantic_type, operation.task == null ? null : operation.task.semantic_type, operation.argument == null ? null : operation.argument.semantic_type, function.async_body)) {
				fail (path, "virtual operation lost exact registered operand/result/effect/context contract");
			}
			if (operation.executor != null) {
				verify_value (operation.executor, function, block, position, path);
				if (operation.executor.semantic_type != operation.contract.runtime.executor_type) {
					fail (path, "runtime operation lost exact executor identity");
				}
			}
			if (operation.task != null) {
				verify_value (operation.task, function, block, position, path);
			}
			if (operation.argument != null) {
				verify_value (operation.argument, function, block, position, path);
			}
			if ((operation.exception != null) != operation.contract.raises || (operation.result != null) != (operation.contract.result.kind != TypeKind.VOID)) {
				fail (path, "runtime operation lost exact result/exception channel shape");
			}
			return;
		}
		if (instruction is SsaFrameCatchEvent) {
			var event = (SsaFrameCatchEvent) instruction;
			if (!function.frame_catch_owners.find (event.owner) || !event.owner.matches_event (event) || event.source.semantic_type != event.owner.semantic_type) {
				fail (path, "active catch frame owner lost exact exception-slot authority");
			}
			verify_value (event.source, function, block, position, path);
			return;
		}
		if (instruction is SsaTaskWait) {
			var wait = (SsaTaskWait) instruction;
			verify_value (wait.child, function, block, position, path + "/child");
			var bridge = wait.bridge_executor;
			if (bridge == null && wait.bridge_owner != null) {
				fail (path, "bridge owner has no target pool value");
			}
			if (bridge != null) {
				var handle = bridge.semantic_type as HandleType;
				var owner = wait.bridge_owner;
				var read = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
				if (handle == null || !handles.contains (handle) || !AsyncBridgeTypes.matches (handle, handles.lookup (handle).cleanup.external_symbol) || owner == null || !function.heap_owners.find (owner) || !matches_cleanup (handle, owner.cleanup) || read == null || read.owner != owner || read.action != SsaHeapOwnerAction.READ || read.value != bridge || read.effect != wait) {
					fail (path, "bridge lost exact live pool owner and bounded submission-through-observation loan");
				}
				verify_value (bridge, function, block, position, path + "/bridge", true);
			}
			var task = wait.child.semantic_type as TaskType;
			if (wait.body != function.async_body || task == null || (bridge == null ? !task.runtime.compatible (wait.body.runtime) : !AsyncBridgeTypes.compatible (wait.body.runtime, task.runtime)) || !(wait.result.semantic_type is ClassType)) {
				fail (path, "wait lost exact body/task/runtime/exception identity");
			}
			return;
		}
		if (instruction is SsaTaskSuccess) {
			var success = (SsaTaskSuccess) instruction;
			var wait = success.operation;
			var site = definitions.lookup (wait.result);
			if (site == null || site.function != function || wait.success != success || wait.discard || success.success_type.logical_identity != ((TaskType) wait.child.semantic_type).success_type.logical_identity || !dominance[site.block.ordinal, block.ordinal] || !guarded_effect_success (wait.result, block)) {
				fail (path, "wait success lost exact original guarded typed result association");
			}
			if (success.struct_result != null) {
				if (success.result != null || success.enum_result != null || success.buffer_result != null || success.struct_result.shape.semantic_type != success.success_type || success.struct_result.leaves.length != success.struct_result.shape.leaves.length || struct_results.lookup (success.struct_result) != success) {
					fail (path, "record await lost exact complete grouped result authority");
				}
				verify_struct_shape (success.struct_result.shape, success.success_type, path);
				for (int l = 0; l < success.struct_result.leaves.length; l++) {
					if (success.struct_result.leaves[l].semantic_type != success.struct_result.shape.leaves[l].semantic_type) {
						fail (path, "record await lost ordered leaf type correspondence");
					}
				}
			} else if (success.enum_result != null) {
				if (success.result != null || success.buffer_result != null || success.enum_result.definition.semantic_type != success.success_type || !function.enum_slots.find (success.enum_result)) {
					fail (path, "enum await lost exact guarded carrier authority");
				}
			} else if (success.buffer_result == null && (success.result == null || success.result.semantic_type != success.success_type)) {
				fail (path, "await lost exact scalar success definition");
			}
			if (success.buffer_result != null && (success.result != null || !cleanups.contains (success.buffer_cleanup) || !success.buffer_cleanup.is_buffer || success.buffer_result.shape != success.buffer_cleanup.buffer_shape || success.success_type != success.buffer_cleanup.buffer_type || ((TaskType) wait.child.semantic_type).success_mode != ResultOwnershipContract.OWNED_TRANSFER)) {
				fail (path, "await buffer lost exact complete owned result group");
			}
			return;
		}
		if (instruction is SsaTaskAcquire) {
			verify_value (((SsaTaskAcquire) instruction).source, function, block, position, path + "/task-acquire");
			return;
		}
		if (instruction is SsaTaskMove) {
			var move = (SsaTaskMove) instruction;
			verify_value (move.source, function, block, position, path + "/source");
			if (!(move.source.semantic_type is TaskType) || move.result == null || move.result.semantic_type != move.source.semantic_type || move.owner_ordinal < 0) {
				fail (path, "task move lost its unique source/result owner contract");
			}
			return;
		}
		if (instruction is SsaTaskEnd) {
			var end = (SsaTaskEnd) instruction;
			verify_value (end.source, function, block, position, path + "/source");
			if (!(end.source.semantic_type is TaskType) || end.owner_ordinal < 0) {
				fail (path, "task scope cleanup lost exact unique owner contract");
			}
			return;
		}
		if (instruction is SsaTaskCreate) {
			var creation = (SsaTaskCreate) instruction;
			if (!creation.matches_captures () || creation.target == null || !functions.contains (creation.target) || creation.target.async_body == null || creation.result == null || creation.result.semantic_type != creation.target.async_body.task_type || creation.arguments.length != creation.target.parameters.length || creation.checked_admission != (creation.exception_result != null) || creation.checked_admission && creation.allocation_context == null || creation.buffer_result != null || creation.enum_result != null || creation.struct_result != null) {
				fail (path, "task creation lost exact body/capture/logical-result association");
			}
			var frame_context = creation.allocation_context;
			if (frame_context == null && creation.context_owner != null) {
				fail (path, "task frame owner has no selected context");
			}
			if (frame_context != null) {
				var type = frame_context.semantic_type as HandleType;
				if (type == null || !handles.contains (type) || type.context_mode == "" || handles.lookup (type).context_mode != type.context_mode || creation.target.async_body.runtime.threaded && type.context_mode != "owned-concurrent" || creation.loans.length != 0) {
					fail (path, "task frame lost exact backing lifetime/thread capability");
				}
				var owner = creation.context_owner;
				if (owner != null) {
					var read = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
					if (!function.heap_owners.find (owner) || !matches_cleanup (type, owner.cleanup) || read == null || read.owner != owner || read.action != SsaHeapOwnerAction.READ || read.value != frame_context || read.effect != creation) {
						fail (path, "task frame allocation lost its exact preceding live-owner read");
					}
				} else {
					var parameter = frame_context as SsaFunctionParameter;
					if (parameter == null || !function.parameters.find (parameter) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						fail (path, "task frame context requires a live owner or exact borrowed parameter");
					}
				}
				verify_value (frame_context, function, block, position, path + "/frame-context", true);
			}
			verify_struct_arguments (creation, function, block, position, path);
			verify_buffer_arguments (creation, function, block, position, path);
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
				SsaSliceConstructInstruction? view = null;
				foreach (var candidate in function.blocks) {
					foreach (var prior in candidate.instructions) {
						if (prior.result == loan.view) {
							view = prior as SsaSliceConstructInstruction;
						}
					}
				}
				int wait_position = creation.direct_wait_position (block, position);
				var wait = wait_position < 0 ? null : block.instructions[wait_position] as SsaTaskWait;
				if (function.async_body == null || wait == null || wait.child != creation.result || loan.parameter_ordinal != p || loan.view != creation.arguments[p] || view == null || view.storage != loan.storage || !(loan.storage.semantic_type is ArrayType) || !function.storage.find (loan.storage) || !(parameter.semantic_type is SliceType) || suspension_loan_ids.contains (loan.identity)) {
					fail (path, "suspension loan lost exact direct wait/view/declared parent storage authority");
				}
				foreach (var candidate in function.blocks) {
					foreach (var prior in candidate.instructions) {
						var alias = prior as SsaSliceConstructInstruction;
						if (alias == null || alias.storage != loan.storage || alias == view) {
							continue;
						}
						bool sealed = false;
						foreach (var owner_block in function.blocks) {
							foreach (var candidate_instruction in owner_block.instructions) {
								var owner = candidate_instruction as SsaTaskCreate;
								if (owner == null) {
									continue;
								}
								foreach (var other in owner.loans) {
									if (other.view == alias.result && other.storage == loan.storage) {
										sealed = true;
									}
								}
							}
						}
						if (!sealed) {
							fail (path, "parent-local suspension backing has an uncontrolled alias");
						}
					}
				}
				suspension_loan_ids.insert (loan.identity, true);
			}
			if (borrowed != creation.loans.length) {
				fail (path, "task has an unrelated suspension loan");
			}
			int transfer_index = 0;
			var moved_sources = new HashTable<int, bool> (direct_hash, direct_equal);
			for (int a = 0; a < creation.arguments.length; a++) {
				var parameter = creation.target.parameters[a];
				var capture = creation.arguments[a];
				bool buffer = false;
				foreach (var group in creation.target.buffer_parameters) {
					if (a == group.first_leaf || a == group.first_leaf + 1) {
						buffer = true;
					}
				}
				bool record = false;
				foreach (var group in creation.struct_arguments) {
					if (a < group.first_leaf || a >= group.first_leaf + group.shape.leaves.length) {
						continue;
					}
					record = group.shape.mode == StructValueMode.MOVE_VALUE;
					buffer |= group.shape.leaves[a - group.first_leaf] is StructBufferLeafPath;
				}
				if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && !record) {
					if (transfer_index >= creation.owned_arguments.length) {
						fail (path, "task capture requires its exact committed owner transfer");
					}
					var transfer = creation.owned_arguments[transfer_index++];
					if (transfer.parameter != parameter || transfer.value != capture || !cleanups.contains (transfer.cleanup) || !matches_cleanup (capture.semantic_type, transfer.cleanup) || transfer.cleanup.is_heap_object != parameter.heap_object) {
						fail (path, "task capture lost exact owner/parameter/cleanup correspondence");
					}
					if (transfer.source_ordinal >= 0) {
						if (transfer.source_after_commit == null || transfer.source_after_commit.semantic_type != capture.semantic_type || moved_sources.contains (transfer.source_ordinal)) {
							fail (path, "task capture requires one distinct committed source disarm");
						}
						moved_sources.insert (transfer.source_ordinal, true);
					} else if (!(capture is SsaNullPointerConstant) || transfer.source_after_commit != null) {
						fail (path, "task capture cannot manufacture an uncommitted owner");
					}
				}
				if (!(capture is SsaEnumArgument)) {
					verify_value (capture, function, block, position, path + "/capture", parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE, false, false, buffer);
				}
				if (capture.semantic_type != parameter.semantic_type) {
					fail (path, "task creation lost exact capture type/mode");
				}
			}
			if (transfer_index != creation.owned_arguments.length) {
				fail (path, "task capture has an unrelated owner transfer");
			}
			if (creation.checked_admission) {
				if (creation.record_restores.length != creation.record_moves.length) {
					fail (path, "checked frame capture requires one complete conditional restoration per record");
				}
				var records = new HashTable<SsaStructBoundaryMove, bool> (direct_hash, direct_equal);
				foreach (var restore in creation.record_restores) {
					var site = buffer_sites.lookup (restore);
					if (restore.creation != creation || site == null || site.function != function || site.block != block || site.position <= position || site.block.instructions[site.position] != restore || !records.insert (restore.original, true) || !creation.record_moves.find (restore.original)) {
						fail (path, "checked frame requires unique exact record restoration definitions");
					}
				}
				if (creation.buffer_restores.length != creation.buffer_arguments.length) {
					fail (path, "checked frame requires one complete conditional buffer restoration per captured buffer");
				}
				var buffers = new HashTable<SsaBufferArgument, bool> (direct_hash, direct_equal);
				foreach (var restore in creation.buffer_restores) {
					var site = buffer_sites.lookup (restore);
					if (restore.creation != creation || site == null || site.function != function || site.block != block || site.position <= position || site.block.instructions[site.position] != restore || !buffers.insert (restore.argument, true)) {
						fail (path, "checked frame requires unique original buffer restoration definitions");
					}
				}
				int expected = 0;
				var restored = new HashTable<SsaOwnedArgument, bool> (direct_hash, direct_equal);
				foreach (var input in creation.owned_arguments) {
					if (!(input.value.semantic_type is ClassType || input.value.semantic_type is HandleType)) {
						fail (path, "checked frame capture lacks exact conditional owner restoration");
					}
					if (input.source_ordinal >= 0) {
						expected++;
					}
				}
				if (creation.input_restores.length != expected) {
					fail (path, "checked frame requires one conditional restoration for every named input");
				}
				foreach (var restore in creation.input_restores) {
					var site = definitions.lookup (restore.result);
					if (restore.creation != creation || site == null || site.function != function || site.block != block || site.position <= position || site.block.instructions[site.position] != restore || !restored.insert (restore.argument, true)) {
						fail (path, "checked frame requires unique exact conditional input definitions");
					}
				}
			} else if (creation.input_restores.length != 0 || creation.buffer_restores.length != 0 || creation.record_restores.length != 0) {
				fail (path, "ordinary task factory cannot restore transferred owners");
			}
			return;
		}
		if (instruction is SsaAsyncDelay) {
			var delay = (SsaAsyncDelay) instruction;
			if (delay.body != function.async_body || delay.result == null || !(delay.result.semantic_type is ClassType)) {
				fail (path, "suspension requires exact async body and exception channel");
			}
			if (delay.payload) {
				var read = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
				if (!delay.body.runtime.linux || delay.source_owner == null || !function.heap_owners.find (delay.source_owner) || !AsyncPayloadTypes.matches (delay.ticks.semantic_type, delay.source_owner.cleanup.external_symbol) || read == null || read.owner != delay.source_owner || read.value != delay.ticks || read.effect != delay || read.action != SsaHeapOwnerAction.READ) {
					fail (path, "payload suspension lost exact retained unique owner read authority");
				}
				verify_value (delay.ticks, function, block, position, path + "/payload", true);
			} else {
				verify_value (delay.ticks, function, block, position, path + "/ticks");
				if (delay.source_owner != null || (delay.ticks.semantic_type.kind != TypeKind.U32 && delay.ticks.semantic_type.kind != TypeKind.INT)) {
					fail (path, "virtual suspension requires integral ticks");
				}
			}
			return;
		}
		if (instruction is SsaNonNullUse) {
			var use = (SsaNonNullUse) instruction;
			if (!NonNullReferenceTypes.supports (use.value.semantic_type) || use.result != null || use.source_ordinal < 0) {
				fail (path, "nonnull use requires exact reference and local declaration rank");
			}
			verify_value (use.value, function, block, position, path);
			return;
		}
		if (instruction is SsaTextLoanUse) {
			var use = (SsaTextLoanUse) instruction;
			if (!function.text_loans.find (use.loan) || !(use.value.semantic_type is StringType)) {
				fail (path, "stored text use requires exact function loan and complete string");
			}
			verify_value (use.value, function, block, position, path);
			return;
		}
		if (instruction is SsaHeapOwnerEvent) {
			var event = (SsaHeapOwnerEvent) instruction;
			if (event.value.semantic_type.is_scoped_allocator () && event.action == SsaHeapOwnerAction.ACQUIRE) {
				var scoped = event.effect as SsaScopedAllocator;
				if (scoped == null || scoped.owner != event.owner || scoped.result != event.value) {
					fail (path, "scoped context requires its exact lexical intrinsic acquisition");
				}
			}
			verify_value (event.value, function, block, position, path);
			verify_record_scalar_acquire (event, function, block, position, path);
			return;
		}
		if (instruction is SsaEnumReadRecord) {
			var extraction = (SsaEnumReadRecord) instruction;
			var group = extraction.results;
			if (!extraction.field.owns_record || extraction.source.inspection_root != null || group.shape.semantic_type != extraction.field.semantic_type || group.shape.mode != StructValueMode.MOVE_VALUE || group.leaves.length != group.shape.leaves.length || struct_results.lookup (group) != extraction || extraction.binding.field != extraction.field.identity || extraction.binding.instance != extraction.source.instance) {
				fail (path, "enum record read requires its exact complete active owning field result");
			}
			verify_struct_shape (group.shape, extraction.field.semantic_type, path);
			for (int l = 0; l < group.leaves.length; l++) {
				if (group.leaves[l].semantic_type != group.shape.leaves[l].semantic_type) {
					fail (path, "enum record read changed an exact declared physical leaf");
				}
			}
			var consume = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaStructResultConsume;
			var acquire = position + 2 >= block.instructions.length ? null : block.instructions[position + 2] as SsaStructBoundaryAcquire;
			if (consume == null || consume.results != group || consume.use_kind != StructResultUseKind.INITIALIZE || acquire == null || acquire.results != group || acquire.source_ordinal != extraction.binding.local_ordinal) {
				fail (path, "enum record binding requires immediate complete consumption and fresh root acquisition");
			}
			return;
		}
		if (instruction is SsaEnumScalarCapture) {
			var capture = (SsaEnumScalarCapture) instruction;
			var owner = capture.owner;
			var read = position == 0 ? null : block.instructions[position - 1] as SsaHeapOwnerEvent;
			if (owner == null || !function.heap_owners.find (owner) || owner.cleanup.is_buffer || !matches_cleanup (capture.pointer.semantic_type, owner.cleanup) || read == null || read.action != SsaHeapOwnerAction.READ || read.owner != owner || read.value != capture.pointer || read.effect != capture) {
				fail (path, "enum scalar capture requires its exact preceding live owner loan");
			}
			verify_value (capture.pointer, function, block, position, path);
			return;
		}
		if (instruction is SsaEnumScalarAbort) {
			var capture = ((SsaEnumScalarAbort) instruction).capture;
			var site = buffer_sites.lookup (capture);
			if (site == null || site.function != function || (site.block == block ? site.position >= position : !dominance[site.block.ordinal, block.ordinal])) {
				fail (path, "enum scalar abort lost its exact dominating original reservation");
			}
			return;
		}
		if (instruction is SsaEnumScalarCommit) {
			var commit = (SsaEnumScalarCommit) instruction;
			var capture = commit.capture;
			var consumer = commit.consumer;
			var site = buffer_sites.lookup (capture);
			var consumer_site = consumer == null ? null : buffer_sites.lookup (consumer);
			var moved = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaHeapOwnerEvent;
			if (site == null || site.function != function || (site.block == block ? site.position >= position : !dominance[site.block.ordinal, block.ordinal]) || consumer_site == null || consumer_site.block != block || consumer_site.position <= position || moved == null || moved.owner != capture.owner || moved.action != SsaHeapOwnerAction.MOVE || moved.value != capture.pointer || moved.effect != commit) {
				fail (path, "enum scalar commit requires its original capture, complete consumer and immediate source disarm");
			}
			int fields = 0;
			foreach (var input in consumer.fields) {
				if (input.field == commit.field && input.scalar_owner == capture && input.leaves.length == 1 && input.leaves[0] == capture.pointer) {
					fields++;
				}
			}
			if (fields != 1) {
				fail (path, "enum scalar commit changed its original exact constructor field");
			}
			for (int i = position + 1; i < consumer_site.position; i++) {
				var effect = block.instructions[i];
				var event = effect as SsaHeapOwnerEvent;
				if (!(effect is SsaEnumScalarCommit) && !(event != null && event.action == SsaHeapOwnerAction.MOVE && event.effect is SsaEnumScalarCommit)) {
					fail (path, "enum scalar owner cannot commit before another payload effect");
				}
			}
			return;
		}
		if (instruction is SsaEnumReadScalar) {
			var read = (SsaEnumReadScalar) instruction;
			var owner = read.owner;
			var acquired = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaHeapOwnerEvent;
			if (owner == null || !function.heap_owners.find (owner) || read.result == null || !read.field.owns_scalar || !matches_cleanup (read.field.semantic_type, owner.cleanup) || owner.cleanup.is_heap_object != read.field.owns_child || (read.field.owned_cleanup != null && owner.cleanup.external_symbol != read.field.owned_cleanup.external_symbol) || acquired == null || acquired.action != SsaHeapOwnerAction.ACQUIRE || acquired.owner != owner || acquired.value != read.result || acquired.effect != read) {
				fail (path, "enum scalar binding requires its exact fresh selected-field owner acquisition");
			}
			return;
		}
		if (instruction is SsaEnumBufferCapture) {
			var capture = (SsaEnumBufferCapture) instruction;
			verify_buffer_pair (capture.pair, function, block, position, path);
			verify_buffer_place (capture.place, function, block, position, true, path);
			return;
		}
		if (instruction is SsaEnumBufferAbort) {
			var capture = ((SsaEnumBufferAbort) instruction).capture;
			bool found = false;
			foreach (var candidate in function.blocks) {
				for (int i = 0; i < candidate.instructions.length; i++) {
					if (candidate.instructions[i] == capture && (candidate == block ? i < position : dominance[candidate.ordinal, block.ordinal])) {
						found = true;
					}
				}
			}
			if (!found) {
				fail (path, "enum abort lost exact dominating reservation");
			}
			return;
		}
		if (instruction is SsaTextLoanBind || instruction is SsaTextLoanEnd) {
			var binding = instruction as SsaTextLoanBind;
			var loan = binding == null ? ((SsaTextLoanEnd) instruction).loan : binding.loan;
			if (loan == null || !function.text_loans.find (loan) || loan.extent == null || instruction.result != null) {
				fail (path, "text loan event requires its exact function-owned extent");
			}
			if (binding != null) {
				if (!(binding.value.semantic_type is StringType)) {
					fail (path, "text loan requires the complete text result");
				}
				verify_value (binding.value, function, block, position, path);
			}
			return;
		}

		if (instruction is SsaOwnedArgumentReservation) {
			var reservation = (SsaOwnedArgumentReservation) instruction;
			if (reservation.value != null) {
				verify_value (reservation.value, function, block, position, path);
			}
			if (reservation.pair != null) {
				verify_buffer_pair (reservation.pair, function, block, position, path);
			}
			if ((reservation.value == null) == (reservation.pair == null) || reservation.consumer == null || instruction.result != null) {
				fail (path, "pending transfer requires one exact value group and native consumer");
			}
			return;
		}
		if (instruction is SsaOwnedArgumentAbort) {
			if (instruction.result != null) {
				fail (path, "abort cannot publish a new value");
			}
			return;
		}

		if (instruction is SsaGroupCallSuccess) {
			var success = (SsaGroupCallSuccess) instruction;
			if (success.call == null || success.call.exception_result == null || !guarded_success (success.call, block) || (success.call.buffer_result == null && success.call.struct_result == null && success.call.enum_result == null)) {
				fail (path, "success group requires exact guarded private call publication");
			}
			return;
		}
		if (instruction is SsaExceptionTransfer) {
			var transfer = (SsaExceptionTransfer) instruction;
			verify_value (transfer.source, function, block, position, path);
			if (!(transfer.source.semantic_type is ClassType) || transfer.disarmed.semantic_type != transfer.source.semantic_type || transfer.owner_ordinal < 0 || transfer.result.semantic_type != transfer.source.semantic_type) {
				fail (path, "exception move requires exact source, disarm and heap owner");
			}
			return;
		}
		if (instruction is SsaExceptionStamp) {
			var stamp = (SsaExceptionStamp) instruction;
			verify_value (stamp.exception, function, block, position, path);
			if (!(stamp.exception.semantic_type is ClassType)) {
				fail (path, "exception origin requires exact native class reference");
			}
			return;
		}
		if (instruction is SsaExceptionMatch) {
			var match = (SsaExceptionMatch) instruction;
			verify_value (match.exception, function, block, position, path);
			if (!(match.exception.semantic_type is ClassType) || !match.match_type.derives_from ((ClassType) match.exception.semantic_type) || match.result.semantic_type.kind != TypeKind.BOOL) {
				fail (path, "subtype catch match requires rooted native exception and bool result");
			}
			return;
		}
		if (instruction is SsaCatchBorrow) {
			var caught = (SsaCatchBorrow) instruction;
			verify_value (caught.exception, function, block, position, path);
			if (!(caught.exception.semantic_type is ClassType) || !((ClassType) caught.result.semantic_type).derives_from ((ClassType) caught.exception.semantic_type) || !guarded_catch (caught, function, block)) {
				fail (path, "catch borrow requires exact rooted native exception subtype");
			}
			return;
		}
		if (instruction is SsaCallSuccess) {
			var success = (SsaCallSuccess) instruction;
			var site = success.call.result == null ? null : definitions.lookup (success.call.result);
			if (site == null || site.function != function || success.call.exception_result == null || success.result.semantic_type != success.call.result.semantic_type || !dominance[site.block.ordinal, block.ordinal] || !guarded_success (success.call, block)) {
				fail (path, "success load requires the exact dominating private throwing call");
			}
			return;
		}
		if (instruction is SsaClassUpcast) {
			var cast = (SsaClassUpcast) instruction;
			var incoming = cast.reference.semantic_type as ReceiverType;
			var outgoing = cast.result == null ? null : cast.result.semantic_type as ReceiverType;
			if (cast.result == null || structs.lookup (cast.source_class.semantic_type) != cast.source_class || structs.lookup (cast.target_class.semantic_type) != cast.target_class || cast.source_class == cast.target_class || !((ClassType) cast.source_class.semantic_type).derives_from ((ClassType) cast.target_class.semantic_type) || (incoming == null ? cast.reference.semantic_type != cast.source_class.semantic_type : incoming.instance_type != cast.source_class.semantic_type) || (outgoing == null ? cast.result.semantic_type != cast.target_class.semantic_type : outgoing.instance_type != cast.target_class.semantic_type) || (incoming == null) != (outgoing == null) || (incoming != null && incoming.mode != outgoing.mode)) {
				fail (path, "upcast requires exact descendant/ancestor identities and retained receiver mode");
			}
			verify_value (cast.reference, function, block, position, path + "/source", true, incoming != null);
			class_upcasts.insert (cast.result, cast);
			return;
		}

		if (instruction is SsaTextSnapshotDestroy) {
			var snapshot = (SsaTextSnapshotDestroy) instruction;
			if (!snapshot_epilogues.contains (snapshot) || snapshot.result != null) {
				fail (path, "snapshot destroy requires its exact generated destructor epilogue position");
			}
			verify_place (snapshot.field, function, block, position, true, path);
			return;
		}
		var enum_construct = instruction as SsaEnumConstruct;
		if (enum_construct != null) {
			if (instruction.result != null) {
				fail (path, "enum construction cannot define an ordinary value");
			}
			foreach (var field in enum_construct.fields) {
				for (int l = 0; l < field.leaves.length; l++) {
					bool component = field.record_move != null && l < field.record_move.shape.leaves.length && field.record_move.shape.leaves[l] is StructBufferLeafPath;
					verify_value (field.leaves[l], function, block, position, path + "/payload", false, false, false, component);
				}
				if (field.buffer != null) {
					verify_buffer_pair (field.buffer, function, block, position, path);
					consume_buffer_pair (field.buffer, enum_construct, function, block, position, true, path);
				}
			}
			return;
		}
		if (instruction is SsaEnumEndInspection || instruction is SsaEnumFinishArm || instruction is SsaEnumReadBuffer || instruction is SsaEnumDrop || instruction is SsaEnumCommit || instruction is SsaEnumCopy || instruction is SsaEnumAcquire || instruction is SsaEnumExtractSum) {
			if (instruction.result != null) {
				fail (path, "enum transport cannot define an ordinary value");
			}
			return;
		}
		if (instruction is SsaEnumTagInstruction || instruction is SsaEnumRead) {
			if (instruction.result == null || instruction.result.semantic_type is EnumType) {
				fail (path, "enum projection requires its scalar/record-leaf result");
			}
			verify_type (instruction.result.semantic_type, true, path);
			return;
		}
		var continuation = instruction as SsaContinuationRegion;
		if (continuation != null) {
			foreach (var operand in continuation.operands) {
				verify_value (operand, function, block, position, path + "/continuation-operand");
			}
			return;
		}
		if (verify_buffer_instruction (instruction, function, block, position, path)) {
			return;
		}
		if (instruction is SsaStructParameterBorrow) {
			var binding = (SsaStructParameterBorrow) instruction;
			var group = binding.parameter;
			if (binding.result != null || block != function.entry || !function.struct_parameters.find (group) || group.shape.mode != StructValueMode.BORROW_VALUE || binding.leaves.length != group.shape.leaves.length) {
				fail (path, "borrowed record lost its exact complete nonowning entry binding");
			}
			for (int i = 0; i < binding.leaves.length; i++) {
				if (binding.leaves[i] != function.parameters[group.first_leaf + i]) {
					fail (path, "borrowed record binding changed an original ordered parameter leaf");
				}
				verify_value (binding.leaves[i], function, block, position, path, true, false, false, true);
			}
			verify_record_buffer_pairs (group.shape, binding.leaves, binding.buffers, path);
			return;
		}
		if (instruction is SsaStructResultConsume) {
			verify_struct_consumption ((SsaStructResultConsume) instruction, function, block, position, path);
			return;
		}
		var frame_restore = instruction as SsaFrameInputRestore;
		if (frame_restore != null) {
			var creation = frame_restore.creation;
			var argument = frame_restore.argument;
			var owner = frame_restore.owner;
			var site = creation == null ? null : definitions.lookup (creation.result);
			if (creation == null || !creation.checked_admission || creation.exception_result == null || site == null || site.function != function || site.block != block || site.position >= position || !creation.input_restores.find (frame_restore) || !creation.owned_arguments.find (argument) || !function.heap_owners.find (owner) || owner.record_type != null || owner.source_ordinal != argument.source_ordinal || argument.source_ordinal < 0 || owner.cleanup != argument.cleanup || instruction.result == null || instruction.result.semantic_type != argument.value.semantic_type || !matches_cleanup (instruction.result.semantic_type, owner.cleanup)) {
				fail (path, "checked frame restore lost exact unpublished task, capture or caller owner authority");
			}
			verify_value (argument.value, function, block, position, path);
			var acquired = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaHeapOwnerEvent;
			if (acquired == null || acquired.owner != owner || acquired.action != SsaHeapOwnerAction.ACQUIRE || acquired.effect != instruction || acquired.value != instruction.result) {
				fail (path, "checked frame restore requires one immediate exact caller acquisition");
			}
			for (int i = site.position + 1; i < position; i++) {
				var prior = block.instructions[i];
				var event = prior as SsaHeapOwnerEvent;
				if (!(prior is SsaFrameInputRestore) && (event == null || event.action != SsaHeapOwnerAction.ACQUIRE || !(event.effect is SsaFrameInputRestore))) {
					fail (path, "checked frame restoration cannot cross another effect after admission");
				}
			}
			return;
		}
		var restored_input = instruction as SsaFallibleInputRestore;
		if (restored_input != null) {
			var call = restored_input.call;
			var argument = restored_input.argument;
			var owner = restored_input.owner;
			if (call == null || !call.constructs || !call.storage.fallible || !call.storage.heap_allocated || !block.instructions.find (call) || !call.input_restores.find (restored_input) || !call.owned_arguments.find (argument) || !function.heap_owners.find (owner) || owner.record_type != null || owner.source_ordinal != argument.source_ordinal || argument.source_ordinal < 0 || owner.cleanup != argument.cleanup || instruction.result == null || instruction.result.semantic_type != argument.value.semantic_type || !matches_cleanup (instruction.result.semantic_type, owner.cleanup)) {
				fail (path, "fallible input restore lost exact constructor, argument or caller owner authority");
			}
			verify_value (argument.value, function, block, position, path);
			verify_value (call.receiver, function, block, position, path, false, true);
			var acquired = position + 1 >= block.instructions.length ? null : block.instructions[position + 1] as SsaHeapOwnerEvent;
			if (acquired == null || acquired.owner != owner || acquired.action != SsaHeapOwnerAction.ACQUIRE || acquired.effect != instruction || acquired.value != instruction.result) {
				fail (path, "fallible input restore requires one immediate exact caller acquisition");
			}
			bool reached = false;
			for (int i = position + 2; i < block.instructions.length; i++) {
				var next = block.instructions[i];
				if (next == call) {
					reached = true;
					break;
				}
				if (!fallible_restore_effect (next, call)) {
					fail (path, "fallible input restore cannot cross another effect before its constructor");
				}
			}
			if (!reached) {
				fail (path, "fallible input restore must precede its constructor");
			}
			return;
		}
		var storage_receiver = instruction as SsaStorageReceiverInstruction;
		if (storage_receiver != null) {
			var contract = instruction.result == null ? null : instruction.result.semantic_type as ReceiverType;
			if (contract == null || object_owners.lookup (storage_receiver.storage) != function || contract.instance_type != storage_receiver.storage.semantic_type) {
				fail (path, "storage receiver requires exact caller-owned ObjectStorage");
			}
			var context = storage_receiver.allocation_context;
			var policy = storage_receiver.storage.object_class.allocation_policy;
			bool contextual = contract.mode == ReceiverMode.INITIALIZING && policy != null && policy.kind == AllocationKind.CONTEXT;
			if (contextual != (context != null) || context == null && storage_receiver.context_owner != null) {
				fail (path, "context receiver lost exact instance/owner authority");
			}
			if (context != null) {
				var context_type = context.semantic_type as HandleType;
				if (!storage_receiver.storage.heap_allocated || context_type == null || !handles.contains (context_type) || handles.lookup (context_type).context_mode != policy.context_mode || context_type.context_mode != policy.context_mode) {
					fail (path, "context receiver changed its nominal lifetime/thread contract");
				}
				if (policy.context_mode == "scoped-affine") {
					if (function.async_body != null) {
						fail (path, "scoped construction requires a synchronous backing lifetime");
					}
					if (!scoped_constructions.find (function)) {
						scoped_constructions.add (function);
					}
				}
				var owner = storage_receiver.context_owner;
				if (owner != null) {
					var read = position > 0 ? block.instructions[position - 1] as SsaHeapOwnerEvent : null;
					if (!function.heap_owners.find (owner) || !matches_cleanup (context_type, owner.cleanup) || read == null || read.owner != owner || read.action != SsaHeapOwnerAction.READ || read.effect != instruction || read.value != context) {
						fail (path, "context allocation requires its exact preceding live-owner read");
					}
				} else {
					var parameter = context as SsaFunctionParameter;
					if (parameter == null || !function.parameters.find (parameter) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
						fail (path, "context allocation requires a live owner or borrowed parameter");
					}
				}
				verify_value (context, function, block, position, path + "/context", true);
			}
			verify_type (contract, true, path);
			return;
		}
		var object_reference = instruction as SsaObjectReferenceInstruction;
		if (object_reference != null) {
			var storage = object_reference.storage;
			if ((storage.heap_allocated && (!storage.transferable || storage.object_class.constructor == null)) || storage.result_candidate || object_owners.lookup (storage) != function || object_constructions.lookup (storage) != object_reference || instruction.result == null || instruction.result.semantic_type != storage.semantic_type || !object_reference.provenance.is_valid () || object_reference.provenance.origin_ordinal != storage.ordinal || object_reference.provenance.region_ordinal != storage.region_ordinal) {
				fail (path, "object reference requires exact storage identity, ClassType and lexical provenance");
			}
			if (storage.object_class.constructor != null) {
				var site = constructor_sites.lookup (storage);
				if (site == null || (site.block == block && site.position >= position) || !dominance[site.block.ordinal, block.ordinal]) {
					fail (path, "successful constructor must precede and dominate publication");
				}
			}
			foreach (var field in storage.object_class.fields) {
				if (storage.object_class.constructor != null) {
					continue;
				}
				var site = object_initializations.lookup (storage).lookup (field);
				if (site == null || (site.block == block && site.position >= position) || !dominance[site.block.ordinal, block.ordinal]) {
					fail (path, "complete object initialization must precede and dominate publication");
				}
			}
			return;
		}
		var object_validation = instruction as SsaObjectValidateInstruction;
		if (object_validation != null) {
			if (instruction.result == null || !(object_validation.reference.semantic_type is ClassType)) {
				fail (path, "object validation requires exact class reference and result");
			}
			var type = instruction.result.semantic_type;
			var contract = type as ReceiverType;
			if (contract == null ? type != object_validation.reference.semantic_type : contract.instance_type != object_validation.reference.semantic_type) {
				fail (path, "object validation must preserve exact class or form its receiver contract");
			}
			verify_type (type, true, path);
			verify_value (object_validation.reference, function, block, position, path + "/reference", true, true);
			return;
		}
		if (instruction.result != null && instruction.result.semantic_type is ReceiverType && !(instruction is SsaAddressOfInstruction) && !(instruction is SsaObjectValidateInstruction)) {
			fail (path, "receiver values can only be defined by address of exact instance storage");
		}
		var slice = instruction as SsaSliceConstructInstruction;
		if (slice != null) {
			verify_storage (slice.storage, function, block, position, true, path);
			verify_array_type (slice.array_type, path);
			var type = instruction.result == null ? null : instruction.result.semantic_type as SliceType;
			if (type == null || slice.storage.semantic_type != slice.array_type || type.element_type != slice.array_type.element_type || !slice.provenance.is_valid () || slice.provenance.origin != DataPointerOrigin.LOCAL || slice.provenance.origin_ordinal != slice.storage.source_local_ordinal) {
				fail (path, "slice construction requires exact array element, result type and storage provenance");
			}
			if ((slice.start == null) != (slice.count == null)) {
				fail (path, "slice range requires paired start and count");
			}
			if (slice.start != null && slice.count != null) {
				verify_value (slice.start, function, block, position, path + "/operand");
				verify_value (slice.count, function, block, position, path + "/operand");
				if (!(slice.start.semantic_type is IntegerType) || !(slice.count.semantic_type is IntegerType)) {
					fail (path, "slice start and count require scalar IntegerTypes");
				}
			}
			return;
		}
		if (instruction is SsaUtf8FactoryInstruction) {
			var operation = (SsaUtf8FactoryInstruction) instruction;
			if (utf8_instructions.lookup (operation) != function) {
				fail (path, "unassociated UTF-8 validated-copy instruction");
			}
			verify_value (operation.input, function, block, position, path + "/bytes", false, false, false, false, true);
			if (!operation.validates) {
				text_origins.borrowed (operation.result);
			}
			return;
		}
		if (instruction is SsaTextLengthInstruction) {
			var receiver = ((SsaTextLengthInstruction) instruction).receiver;
			verify_value (receiver, function, block, position, path + "/text");
			if (!(receiver.semantic_type is StringType) || instruction.result == null || !(instruction.result.semantic_type is IntegerType) || instruction.result.semantic_type.kind != TypeKind.INT) {
				fail (path, "text byte length requires StringType input and int result");
			}
			return;
		}
		var length = instruction as SsaSliceLengthInstruction;
		if (length != null) {
			verify_value (length.slice, function, block, position, path + "/operand", false, false, false, false, true);
			if (!(length.slice.semantic_type is SliceType) || instruction.result == null || !(instruction.result.semantic_type is IntegerType) || instruction.result.semantic_type.kind != TypeKind.INT) {
				fail (path, "slice length requires SliceType input and exact int result");
			}
			return;
		}
		var slice_bounds = instruction as SsaSliceBoundsCheck;
		if (slice_bounds != null) {
			verify_value (slice_bounds.slice, function, block, position, path + "/slice", false, false, false, false, true);
			verify_value (slice_bounds.index, function, block, position, path + "/index");
			if (!(slice_bounds.slice.semantic_type is SliceType) || !(slice_bounds.index.semantic_type is IntegerType) || slice_bounds.result == null || slice_bounds.result.semantic_type != slice_bounds.index.semantic_type) {
				fail (path, "slice bounds require one exact view and integer index/result");
			}
			return;
		}

		var array = instruction as SsaArrayInitialize;
		if (array != null) {
			verify_storage (array.storage, function, block, position, false, path);
			var type = array.storage.semantic_type as ArrayType;
			if (array.record_root != null) {
				verify_record_array_entry (array, function, block, position, path);
				return;
			}
			if (type != null && (type.element_type is StructType || array.record_fields.length != 0 || record_initializations.contains (array.storage))) {
				fail (path, "record arrays require complete typed entry initialization");
			}
			if (type == null || array.result != null || array.elements.length != type.length) {
				fail (path, "array initialization requires exactly N values, array storage and no result");
				return;
			}
			foreach (var element in array.elements) {
				verify_value (element, function, block, position, path + "/element");
				if (element.semantic_type != type.element_type) {
					fail (path, "array initializer element requires exact type");
				}
			}
			return;
		}
		var numeric_guard = instruction as SsaNumericGuard;
		if (numeric_guard != null) {
			verify_value (numeric_guard.operand, function, block, position, path + "/operand");
			verify_type (numeric_guard.destination_type, true, path + "/destination");
			if (!(numeric_guard.operand.semantic_type is FloatingType) || !(numeric_guard.destination_type is IntegerType) || numeric_guard.policy != NumericConversionPolicy.TRUNCATE_TRAP || numeric_guard.result == null || numeric_guard.result.semantic_type != numeric_guard.operand.semantic_type) {
				fail (path, "numeric guard requires exact floating scalar result, integer destination and truncation/trap policy");
			}
			return;
		}
		var bounds = instruction as SsaArrayBoundsCheck;
		if (bounds != null) {
			verify_storage (bounds.storage, function, block, position, true, path);
			verify_value (bounds.index, function, block, position, path + "/index");
			if (!(bounds.storage.semantic_type is ArrayType) || !(bounds.index.semantic_type is IntegerType) || bounds.result == null || bounds.result.semantic_type != bounds.index.semantic_type) {
				fail (path, "array bounds check requires exact storage and integer index/result");
			}
			return;
		}
		var address = instruction as SsaAddressOfInstruction;
		if (address != null && address.receiver_place != null && enum_view_place (address.receiver_place)) {
			fail (path, "enum inspection view cannot expose mutable record storage");
		}
		var validation = instruction as SsaValidatePlaceInstruction;
		if (validation != null) {
			verify_place (validation.place, function, block, position, true, path + "/place");
			return;
		}
		var load = instruction as SsaLoadInstruction;
		if (load != null && (!VolatileAccessContract.valid (load.volatile_access, load.volatile_enabled, load.source.semantic_type) || (load.volatile_enabled && !(load.source is SsaDereferencePlace || load.source is SsaArrayElementPlace || load.source is SsaSliceElementPlace)))) {
			fail (path, "volatile load requires its exact typed memory provenance and flag");
		}
		if (load != null && load.source.semantic_type is SliceType) {
			fail (path, "buffer owner fields require a complete group read and explicit bounded borrow");
		}
		var store = instruction as SsaStoreInstruction;
		if (store != null && (!VolatileAccessContract.valid (store.volatile_access, store.volatile_enabled, store.target.semantic_type) || (store.volatile_enabled && !(store.target is SsaDereferencePlace || store.target is SsaArrayElementPlace || store.target is SsaSliceElementPlace)))) {
			fail (path, "volatile store requires its exact typed memory provenance and flag");
		}
		if (store != null && store.target is SsaIndirectFieldPlace && ((SsaIndirectFieldPlace) store.target).field.text_snapshot) {
			fail (path, "readonly snapshot cannot be rebound");
		}
		if (store != null && enum_view_place (store.target)) {
			fail (path, "enum inspection array view is read-only");
		}
		if (store != null && store.target is SsaSliceElementPlace && ((SsaSliceElementPlace) store.target).slice_type.element_access != SliceElementAccess.READ_WRITE) {
			fail (path, "text slice descriptor elements are read-only");
		}
		var initialization = instruction as SsaInitializeInstruction;
		if (address != null || load != null || store != null || initialization != null) {
			if (memory_instructions.contains (instruction)) {
				fail (path, "memory instruction identity occurs in more than one instruction slot");
			}
			memory_instructions.insert (instruction, instruction);
		}
		if (address != null && address.receiver_place != null) {
			var receiver = address.result == null ? null : address.result.semantic_type as ReceiverType;
			if (receiver == null || receiver.mode != ReceiverMode.LIVE || address.target != null || address.provenance != null || receiver.instance_type != address.receiver_place.semantic_type || !(address.receiver_place.semantic_type is StructType)) {
				fail (path, "projected receiver requires an exact live struct storage contract");
			}
			verify_place (address.receiver_place, function, block, position, true, path + "/receiver-place");
			return;
		}
		if (address != null) {
			verify_storage (address.target, function, block, position, true, path);
			if (address.result == null || ((address.result.semantic_type is ReceiverType) ? ((ReceiverType) address.result.semantic_type).instance_type != address.target.semantic_type : (!address.result.semantic_type.is_typed_pointer () || ((TypedPointerType) address.result.semantic_type).pointee != address.target.semantic_type))) {
				fail (path, "AddressOf result must point to the exact storage type");
			}
			return;
		}
		if (load != null) {
			verify_place (load.source, function, block, position, true, path);
			string record_part;
			var record_root = SsaConstructorInitialization.record_root (load.source, out record_part);
			if (field_state != null && record_root != null && record_root.pointer == function.implicit_receiver && !field_state.is_definite (record_root.field.ordinal)) {
				fail (path, "constructor record field read before complete initialization");
			}
			var field = load.source as SsaIndirectFieldPlace;
			if (field_state != null && field != null && text_backing_owner (field.pointer) == text_backing_owner (function.implicit_receiver) && !field_state.is_definite (field.field.ordinal)) {
				fail (path, "constructor field read before definite initialization: " + field.field.name);
			}
			if (field != null && field.field.text_snapshot && load.result != null) {
				text_origins.receiver_borrow (load.result, text_backing_owner (field.pointer));
			}
			if (load.source is SsaSliceElementPlace && load.result != null && load.result.semantic_type is StringType) {
				text_origins.copy (load.result, ((SsaSliceElementPlace) load.source).slice);
			}
			if (load.result == null || load.result.semantic_type != load.source.semantic_type) {
				fail (path, "Load result must match the exact scalar field type");
			}
			return;
		}
		if (initialization != null && (initialization.target is SsaArrayElementPlace || initialization.target is SsaSliceElementPlace)) {
			fail (path, "array initialization requires complete ordered ArrayInitialize");
		}
		if (store != null && field_state != null && store.target is SsaIndirectFieldPlace && ((SsaIndirectFieldPlace) store.target).pointer == function.implicit_receiver) {
			fail (path, "constructor field writes must be Initialize");
		}
		if (store != null && field_state != null) {
			string part;
			var root = SsaConstructorInitialization.record_root (store.target, out part);
			if (root != null && root.pointer == function.implicit_receiver) {
				fail (path, "constructor record leaf writes must be Initialize");
			}
		}
		if (store != null || initialization != null) {
			var target = store != null ? store.target : initialization.target;
			var value = store != null ? store.value : initialization.value;
			verify_value (value, function, block, position, path + "/value");
			verify_place (target, function, block, position, store != null, path + "/target");
			if (initialization != null) {
				string part;
				var root = SsaConstructorInitialization.record_root (target, out part);
				if (root != null) {
					if (!(function is SsaConstructor) || field_state == null || root.pointer != function.implicit_receiver || root.field.containing_type != ((SsaConstructor) function).declaring_class || field_state.is_part_possible (root.field.ordinal, part)) {
						fail (path, "constructor record leaf possibly initialized twice or outside its exact receiver");
					}
					try {
						if (!field_state.initialize_record_part (root.field.ordinal, part, StructLeafOrder.path_names (root.semantic_type, struct_fields))) {
							fail (path, "constructor record initialization lost exact leaf path");
						}
					} catch (StructLeafError error) {
						fail (path, error.message);
					}
				}
			}
			if (initialization != null && initialization.target is SsaIndirectFieldPlace) {
				var field_target = (SsaIndirectFieldPlace) initialization.target;
				if (field_state == null || field_target.pointer != function.implicit_receiver || field_state.is_possible (field_target.field.ordinal)) {
					fail (path, "constructor field possibly initialized twice: " + field_target.field.name);
				}
				field_state.initialize (field_target.field.ordinal);
			}
			if (instruction.result != null || value.semantic_type != target.semantic_type) {
				fail (path, "memory write must have no result and an exact scalar field value type");
			}
			return;
		}
		var cleanup = instruction as SsaCleanupInstruction;
		if (cleanup != null) {
			if (!cleanups.contains (cleanup.cleanup) || (!cleanup.value.semantic_type.is_ownable_handle_type () && !(cleanup.value.semantic_type is ClassType)) || !matches_cleanup (cleanup.value.semantic_type, cleanup.cleanup) || instruction.result != null) {
				fail (path, "cleanup requires exact program-owned void (void*) contract, void* argument and no result");
			}
			if (cleanup_instructions.contains (cleanup)) {
				fail (path, "cleanup instruction identity occurs in more than one ordered instruction slot");
			}
			cleanup_instructions.insert (cleanup, cleanup);
			verify_value (cleanup.value, function, block, position, path + "/value");
			return;
		}
		var c_call = instruction as SsaCCallInstruction;
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
						verify_value (value, function, block, position, path, target.parameters[p].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
					}
				} else {
					if (leaf >= c_call.arguments.length || c_call.arguments[leaf].semantic_type != type) {
						fail (path, "C scalar argument lost exact type");
					}
					var value = c_call.arguments[leaf++];
					verify_value (value, function, block, position, path, target.parameters[p].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE);
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
				for (int r = 0; r < group.leaves.length; r++) {
					if (group.leaves[r].semantic_type != group.shape.leaves[r].semantic_type) {
						fail (path, "C record result lost exact ordered fields");
					}
				}
			} else if (c_call.struct_result != null) {
				fail (path, "C scalar result cannot carry record fields");
			} else if (target.return_type.kind == TypeKind.VOID) {
				if (c_call.result != null) {
					fail (path, "void call must not define a result");
				}
			} else if (c_call.result == null || c_call.result.semantic_type != target.return_type) {
				fail (path, "non-void call must define a result matching the target return type");
			}
			return;
		}
		var call = instruction as SsaCallInstruction;
		if (call != null) {
			foreach (var argument in call.arguments) {
				var captured = argument as SsaCallbackView;
				if (captured == null) {
					continue;
				}
				foreach (var transfer in call.owned_arguments) {
					if (transfer.value == captured.closure) {
						fail (path, "captured callback view overlaps exact Closure owner transfer");
					}
				}
			}

			if (!call.readonly_context_valid ()) {
				fail (path, "call lost original readonly scope context");
			}
			if (call.target != null && call.target.async_body != null) {
				fail (path, "ordinary call cannot invoke a deferred async body or native resume entry");
			}
			if (calls.contains (call)) {
				fail (path, "call instruction identity occurs in more than one instruction slot");
			}
			calls.insert (call, call);
			var target = call.target;
			if (target != null && functions.contains (target) && target.blocks.length != 0 && target.entry.is_complete && target.entry.terminator is SsaForeignReturn && ((SsaForeignReturn) target.entry.terminator).binding.root.api.active_personalities == 0) {
				fail (path, "call requires unselected foreign import");
			}
			if (target != null && functions.contains (target) && target.blocks.length != 0 && target.entry.is_complete && target.entry.terminator is SsaForeignSignalReturn) {
				if (call.receiver != function.implicit_receiver || function.implicit_receiver == null || target.implicit_receiver.contract.instance_type != function.implicit_receiver.contract.instance_type) {
					fail (path, "signal emission requires the exact defining Class self receiver");
				}
			}
			var caller_policy = function.implicit_receiver == null ? null : function.implicit_receiver.contract.instance_type as ClassType;
			var callee_policy = target == null || target.implicit_receiver == null ? null : target.implicit_receiver.contract.instance_type as ClassType;
			if (caller_policy != null && caller_policy.monitored && !(function is SsaLifecycle) && callee_policy != null && callee_policy.monitored && !(target is SsaLifecycle)) {
				if (call.receiver != function.implicit_receiver) {
					fail (path, "cross-object monitor nesting requires a qualified ordered-lock operation");
				}
			}

			var factory_method = target as SsaMethod;
			if (factory_method != null) {
				foreach (var property in factory_method.declaring_type.properties) {
					if (property.factory == factory_method) {
						fail (path, "owning lazy factory is reserved for its exact compiler cache gate");
					}
				}
			}
			if (target == null || !functions.contains (target)) {
				fail (path, "call target is not owned by the containing program");
				return;
			}
			if (call.result != null && call.result.semantic_type is StringType && target.result_contract == ResultOwnershipContract.STATIC_TEXT) {
				text_origins.literal (call.result);
			} else if (call.result != null && call.result.semantic_type is StringType && target.result_contract == ResultOwnershipContract.RECEIVER_TEXT) {
				text_origins.receiver_borrow (call.result, call.receiver == null ? null : text_backing_owner (call.receiver));
			}
			var receiver_contract = target.implicit_receiver;
			if ((receiver_contract == null) != (call.receiver == null)) {
				fail (path, "method call requires exactly one implicit receiver; free calls have none");
			}
			if (call.receiver != null) {
				if (call.receiver.semantic_type != receiver_contract.contract || !(call.receiver is SsaReceiver || call.receiver is SsaInstructionResult || (call is SsaResultConstructionInstruction && call.receiver is SsaResultStorageReceiverValue))) {
					fail (path, "method receiver requires exact declaring type and storage input");
				}
				verify_value (call.receiver, function, block, position, path + "/receiver", false, true);
			}
			var construction = call as SsaResultConstructionInstruction;
			if (construction != null) {
				var returned = block.terminator as SsaOwnershipReturn;
				if (returned == null || returned.value != construction.storage || returned.provenance != ObjectResultProvenance.RESULT_STORAGE) {
					fail (path, "constructed result must transfer through this block's owned return");
				}
				if (construction.storage != function.result_storage || construction.storage == null || !(target is SsaConstructor) || construction.storage.object_class.constructor != target || !(call.receiver is SsaResultStorageReceiverValue) || ((SsaResultStorageReceiverValue) call.receiver).storage != construction.storage) {
					fail (path, "fresh result requires exact constructor and supplied result storage");
				}
			}
			if (target.result_storage != null) {
				if (call.candidate_storage != null && call.owned_result_use != SsaOwnedResultUse.ACQUIRE) {
					fail (path, "candidate call requires visible local acquisition");
				}
				if (call.result_storage != null) {
					var returned = block.terminator as SsaOwnershipReturn;
					if (call.owned_result_use != SsaOwnedResultUse.FORWARD || returned == null || returned.value != call.result || returned.provenance != ObjectResultProvenance.FORWARDED_OWNED_RESULT) {
						fail (path, "forwarded call requires exact owner return");
					}
				}
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
			if (call is SsaBaseLifecycleCall) {
				var lifecycle = function as SsaLifecycle;
				var cast = class_upcasts.lookup (call.receiver);
				if (lifecycle == null || lifecycle.declaring_class.parent_class == null || cast == null || cast.reference != lifecycle.receiver || cast.source_class != lifecycle.declaring_class || cast.target_class != lifecycle.declaring_class.parent_class) {
					fail (path, "base lifecycle requires an exact child lifecycle receiver");
				}
				if (lifecycle is SsaConstructor) {
					if (target != lifecycle.declaring_class.parent_class.constructor || field_state == null || field_state.is_possible ((int) lifecycle.declaring_class.fields.length)) {
						fail (path, "base init requires one exact direct-parent constructor call");
					}
					field_state.initialize ((int) lifecycle.declaring_class.fields.length);
				} else if (!(lifecycle is SsaDestructor) || !base_epilogues.contains ((SsaBaseLifecycleCall) call) || target != lifecycle.declaring_class.parent_class.destructor || call.arguments.length != 0) {
					fail (path, "base deinit requires exact direct-parent teardown and no arguments");
				}
			}
			var lifecycle_call = call as SsaLifecycleCallInstruction;
			if ((target is SsaLifecycle) != (lifecycle_call != null || call is SsaResultConstructionInstruction || call is SsaBaseLifecycleCall)) {
				fail (path, "lifecycle invocation requires explicit construction or object cleanup authority");
			}
			if (lifecycle_call != null) {
				var storage = lifecycle_call.storage;
				var lifecycle = (SsaLifecycle) target;
				if (storage_receivers.lookup (call.receiver) != storage) {
					fail (path, "lifecycle receiver must be the original storage address, never a reference binding");
				}
				var restored = new HashTable<SsaOwnedArgument, bool> (direct_hash, direct_equal);
				foreach (var restore in lifecycle_call.input_restores) {
					var site = restore.result == null ? null : definitions.lookup (restore.result);
					if (!storage.fallible || !lifecycle_call.constructs || restore.call != lifecycle_call || site == null || site.function != function || site.block != block || site.position >= position || site.block.instructions[site.position] != restore || !restored.insert (restore.argument, true)) {
						fail (path, "fallible constructor requires unique original input restoration definitions");
					}
				}
				foreach (var argument in call.owned_arguments) {
					if ((storage.fallible && lifecycle_call.constructs && argument.source_ordinal >= 0) != restored.contains (argument)) {
						fail (path, "fallible constructor must preserve every named input exactly once");
					}
				}
				if (lifecycle_call.record_restores.length != (storage.fallible && lifecycle_call.constructs ? call.record_moves.length : 0)) {
					fail (path, "fallible constructor requires every complete record restoration");
				}
				var restored_records = new HashTable<SsaStructBoundaryMove, bool> (direct_hash, direct_equal);
				foreach (var restore in lifecycle_call.record_restores) {
					var site = buffer_sites.lookup (restore);
					if (restore.call != lifecycle_call || site == null || site.function != function || site.block != block || site.position >= position || !restored_records.insert (restore.original, true) || !call.record_moves.find (restore.original)) {
						fail (path, "fallible constructor requires unique original conditional record definitions");
					}
				}
				if (lifecycle_call.buffer_restores.length != (storage.fallible && lifecycle_call.constructs ? call.buffer_arguments.length : 0)) {
					fail (path, "fallible constructor requires every exact complete buffer restoration");
				}
				var buffers = new HashTable<SsaBufferArgument, bool> (direct_hash, direct_equal);
				foreach (var restore in lifecycle_call.buffer_restores) {
					var site = buffer_sites.lookup (restore);
					if (restore.call != lifecycle_call || site == null || site.function != function || site.block != block || site.position >= position || !buffers.insert (restore.argument, true) || !call.buffer_arguments.find (restore.argument)) {
						fail (path, "fallible constructor requires unique original conditional buffer definitions");
					}
				}
				if (storage.result_candidate || (!lifecycle_call.constructs && storage.transferable) || object_owners.lookup (storage) != function || storage.object_class != lifecycle.declaring_class || (lifecycle_call.constructs ? storage.object_class.constructor != lifecycle : storage.destructor != lifecycle)) {
					fail (path, "lifecycle cleanup/construction requires exact original ObjectStorage and matching class member");
				}
			}
			verify_struct_arguments (call, function, block, position, path);
			if (call.arguments.length != target.parameters.length) {
				fail (path, "call argument count does not match target parameters");
			}
			if (call.owned_success != null) {
				var site = definitions.lookup (call.owned_success.result);
				if (site == null || site.function != function || call.owned_success.call != call || call.exception_result == null || !guarded_success (call, site.block)) {
					fail (path, "owned success requires the exact guarded heap/handle result publication");
				}
			}
			if (call.owned_result_use == SsaOwnedResultUse.FORWARD && !target.owned_cleanup.is_buffer) {
				int consumers = 0;
				foreach (var candidate in function.blocks) {
					var returned = candidate.terminator as SsaOwnershipReturn;
					if (returned != null && returned.value == owned_call_value (call)) {
						consumers++;
					}
				}
				if (consumers != 1 || function.owned_cleanup != target.owned_cleanup) {
					fail (path, "owned result forwarding requires the exact guarded producer pointer, return and cleanup contract");
				}
			}
			if (target.owned_cleanup != null ? (call.owned_result_use != SsaOwnedResultUse.ACQUIRE && call.owned_result_use != SsaOwnedResultUse.REARM && call.owned_result_use != SsaOwnedResultUse.FORWARD && !(call.owned_result_use == SsaOwnedResultUse.DISCARD && (target.owned_cleanup.is_buffer || target.heap_result) && target.throws_type != null)) : call.owned_result_use != SsaOwnedResultUse.NONE) {
				fail (path, "native owned result requires exact acquire or rearm consumption");
			}
			int transfer_index = 0;
			var moved_sources = new HashTable<int, bool> (direct_hash, direct_equal);
			for (int i = 0; i < call.arguments.length; i++) {
				var class_cast = class_upcasts.lookup (call.arguments[i]);
				if (class_cast != null && class_cast.borrowed_parameter != null && class_cast.borrowed_parameter != target.parameters[i]) {
					fail (path, "upcast borrow must reach its exact noescape consumer parameter");
				}
				string argument_path = path + "/argument #%d".printf (i);
				if (target.parameters[i].pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
					if (transfer_index >= call.owned_arguments.length) {
						fail (argument_path, "owned native argument requires explicit transfer metadata");
					}
					var transfer = call.owned_arguments[transfer_index++];
					if (transfer.parameter != target.parameters[i] || transfer.cleanup.is_heap_object != target.parameters[i].heap_object || transfer.value != call.arguments[i] || !cleanups.contains (transfer.cleanup) || !matches_cleanup (transfer.value.semantic_type, transfer.cleanup)) {
						fail (argument_path, "owned argument requires exact parameter, pointer and nominal cleanup contract");
					}
					if (transfer.source_storage != null && (object_owners.lookup (transfer.source_storage) != function || !transfer.source_storage.transferable || transfer.source_storage.semantic_type != transfer_root (transfer.value).semantic_type || transfer.source_ordinal < 0 || object_constructions.lookup (transfer.source_storage) == null || object_constructions.lookup (transfer.source_storage).result != transfer_root (transfer.value))) {
						fail (argument_path, "object transfer must retain the exact original local ObjectStorage pointer");
					}
					if (transfer.source_ordinal < 0) {
						if (!(transfer.value is SsaNullPointerConstant) || transfer.source_after_commit != null) {
							fail (argument_path, "owned null argument must have no source owner");
						}
					} else {
						if (moved_sources.contains (transfer.source_ordinal) || transfer.source_after_commit == null || transfer.source_after_commit.semantic_type != transfer_root (transfer.value).semantic_type) {
							fail (argument_path, "owned argument requires a distinct source with an exact committed null definition");
						}
						moved_sources.insert (transfer.source_ordinal, true);
					}
				}
				bool buffer_argument = false;
				bool borrowed_record_buffer = false;
				foreach (var group in target.buffer_parameters) {
					if (i == group.first_leaf || i == group.first_leaf + 1) {
						buffer_argument = true;
					}
				}
				foreach (var group in target.struct_parameters) {
					if (i >= group.first_leaf && i < group.first_leaf + group.shape.leaves.length && group.shape.leaves[i - group.first_leaf] is StructBufferLeafPath) {
						buffer_argument = true;
						borrowed_record_buffer = group.shape.mode == StructValueMode.BORROW_VALUE;
					}
				}
				if (target.parameters[i].semantic_type is EnumType) {
					var argument = call.arguments[i] as SsaEnumArgument;
					if (argument == null || argument.source.source_ordinal >= 0 || argument.semantic_type != target.parameters[i].semantic_type) {
						fail (argument_path, "enum argument requires exact independent by-value snapshot");
					}
				} else {
					verify_value (call.arguments[i], function, block, position, argument_path, target.parameters[i].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE || borrowed_record_buffer, false, false, buffer_argument);
				}
				if (call.arguments[i].semantic_type != target.parameters[i].semantic_type) {
					fail (argument_path, "call argument type does not match target parameter");
				}
			}
			if ((target.throws_type == null) != (call.exception_result == null)) {
				fail (path, "throwing call requires exact private exception result");
			}
			verify_buffer_arguments (call, function, block, position, path);
			if (target.owned_cleanup != null && target.owned_cleanup.is_buffer) {
				if (call.result != null || call.buffer_result == null || call.buffer_result.shape != target.owned_cleanup.buffer_shape) {
					fail (path, "buffer call requires its exact complete PTR/I32 result pair and no aggregate Value");
				}
				if (call.owned_result_use == SsaOwnedResultUse.FORWARD) {
					int consumers = 0;
					foreach (var candidate in function.blocks) {
						var returned = candidate.terminator as SsaBufferReturn;
						if (returned != null && returned.pair == call.buffer_result && (candidate == block || (call.exception_result != null && guarded_success (call, candidate)))) {
							consumers++;
						}
					}
					if (consumers != 1 || function.owned_cleanup != target.owned_cleanup) {
						fail (path, "forwarding requires exact guarded buffer result and cleanup");
					}
				}
			} else if (call.buffer_result != null) {
				fail (path, "nonbuffer call cannot carry buffer owner results");
			} else if (target.struct_result != null) {
				var group = call.struct_result;
				if (call.result != null || group == null || group.leaves.length != target.struct_result.leaves.length) {
					fail (path, "struct call requires N ordinary leaf results and no aggregate SSA Value");
				}
				verify_struct_shape (group.shape, target.return_type, path + "/result");
				if (group.shape.mode != target.struct_result.mode) {
					fail (path, "record call result changed its declared copy, move or bounded borrow operation");
				}
				for (int i = 0; i < group.leaves.length; i++) {
					if (group.leaves[i].semantic_type != group.shape.leaves[i].semantic_type) {
						fail (path, "struct result leaf type or order mismatch");
					}
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
			} else if (call.result == null || call.result.semantic_type != target.return_type) {
				fail (path, "non-void call must define a result matching the target return type");
			}
			if (transfer_index != call.owned_arguments.length) {
				fail (path, "extraneous owned argument metadata");
			}
			return;
		}
		if (instruction.result == null) {
			fail (path, "computation instruction must define a result");
		}
		var dot = instruction as SsaVectorDotInstruction;
		if (dot != null) {
			if (dot.accumulator != null) {
				verify_value (dot.accumulator, function, block, position, path + "/accumulator");
			}
			verify_value (dot.first, function, block, position, path + "/first");
			verify_value (dot.second, function, block, position, path + "/second");
			string? error = dot.dot_kind.type_error (dot.source_type, dot.first.semantic_type, dot.second.semantic_type, dot.destination_type, dot.accumulator == null ? null : dot.accumulator.semantic_type);
			if (error != null) {
				fail (path, error);
			}
			return;
		}
		var dsp = instruction as SsaDspInstruction;
		if (dsp != null) {
			verify_value (dsp.first, function, block, position, path + "/first");
			if (dsp.second != null) {
				verify_value (dsp.second, function, block, position, path + "/second");
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
		var shift = instruction as SsaIntegerShiftInstruction;
		if (shift != null) {
			verify_value (shift.operand, function, block, position, path + "/value");
			verify_value (shift.count, function, block, position, path + "/count");
			if (!shift.shift_kind.accepts (shift.operand.semantic_type, shift.count.semantic_type, instruction.result.semantic_type)) {
				fail (path, "shift requires exact integer scalar/vector result and scalar integer count; invalid counts trap");
			}
			return;
		}
		var numeric_conversion = instruction as SsaNumericConversionInstruction;
		if (numeric_conversion != null) {
			verify_value (numeric_conversion.operand, function, block, position, path + "/operand");
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
		var floating_conversion = instruction as SsaFloatConversionInstruction;
		if (floating_conversion != null) {
			verify_value (floating_conversion.operand, function, block, position, path + "/operand");
			if (floating_conversion.source_type != floating_conversion.operand.semantic_type || !floating_conversion.conversion_kind.accepts (floating_conversion.source_type, floating_conversion.destination_type)) {
				fail (path, "float conversion requires exact source type and f32/f64 widen or narrow kind");
			}
			return;
		}
		var conversion = instruction as SsaIntegerConversionInstruction;
		if (conversion != null) {
			verify_value (conversion.operand, function, block, position, path + "/operand");
			if (conversion.source_type != conversion.operand.semantic_type || !IntegerConversion.accepts (conversion.source_type, conversion.destination_type)) {
				fail (path, "integer conversion requires exact source type and integer scalar types or supported integer vectors with equal lane counts");
			}
			return;
		}
		var splat = instruction as SsaVectorSplatInstruction;
		if (splat != null) {
			verify_value (splat.operand, function, block, position, path + "/operand");
			var type = instruction.result.semantic_type as VectorType;
			if (type == null || type.element_type != splat.operand.semantic_type || type.lane_count != splat.lane_count || !VectorType.supports (splat.operand.semantic_type, splat.lane_count)) {
				fail (path, "vector splat requires exact scalar element, supported shape and matching lane count");
				return;
			}
			return;
		}
		var extract = instruction as SsaVectorExtractInstruction;
		if (extract != null) {
			verify_value (extract.vector, function, block, position, path + "/vector");
			var type = extract.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector extract requires a vector source");
				return;
			}
			if (instruction.result.semantic_type != type.element_type) {
				fail (path, "vector extract result requires exact element type");
				return;
			}
			if (!extract.index.in_range (type)) {
				fail (path, "vector extract index is out of range");
				return;
			}
			return;
		}
		var insert = instruction as SsaVectorInsertInstruction;
		if (insert != null) {
			verify_value (insert.vector, function, block, position, path + "/vector");
			verify_value (insert.replacement, function, block, position, path + "/replacement");
			var type = insert.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector insert requires a vector source");
				return;
			}
			if (instruction.result.semantic_type != type) {
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
		var shuffle = instruction as SsaVectorShuffleInstruction;
		if (shuffle != null) {
			verify_value (shuffle.vector, function, block, position, path + "/vector");
			var type = shuffle.vector.semantic_type as VectorType;
			if (type == null) {
				fail (path, "vector shuffle requires a vector source");
				return;
			}
			if (instruction.result.semantic_type != type) {
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
		if (instruction is SsaVectorMemoryInstruction) {
			var memory = (SsaVectorMemoryInstruction) instruction;
			verify_value (memory.view, function, block, position, path + "/view");
			verify_value (memory.offset, function, block, position, path + "/offset");
			if (memory.stored != null) {
				verify_value (memory.stored, function, block, position, path + "/stored");
			}
			var error = memory.contract.type_error (memory.view.semantic_type, memory.offset.semantic_type, memory.stored == null ? null : memory.stored.semantic_type, instruction.result.semantic_type);
			if (error != null) {
				fail (path, error);
			}
			return;
		}
		var select = instruction as SsaVectorSelectInstruction;
		if (select != null) {
			verify_value (select.mask, function, block, position, path + "/mask");
			verify_value (select.true_value, function, block, position, path + "/true_value");
			verify_value (select.false_value, function, block, position, path + "/false_value");
			var type = select.true_value.semantic_type as VectorType;
			var mask_type = select.mask.semantic_type as VectorType;
			if (type == null || select.false_value.semantic_type != type || instruction.result.semantic_type != type) {
				fail (path, "vector select requires exact matching data and result VectorTypes");
				return;
			}
			if (mask_type == null || !mask_type.is_mask || mask_type.lane_count != type.lane_count) {
				fail (path, "vector select requires bool<N> mask with matching data lane count");
				return;
			}
			return;
		}
		var vector = instruction as SsaVectorConstructInstruction;
		if (vector != null) {
			var type = vector.result == null ? null : vector.result.semantic_type as VectorType;
			if (type == null || vector.lanes.length != type.lane_count) {
				fail (path, "vector construct requires exact vector result and lane count");
				return;
			}
			foreach (var lane in vector.lanes) {
				verify_value (lane, function, block, position, path + "/lane");
				if (lane.semantic_type != type.element_type) {
					fail (path, "vector construct lane requires exact element type");
				}
			}
			return;
		}
		var reduction = instruction as SsaVectorReductionInstruction;
		if (reduction != null) {
			verify_value (reduction.operand, function, block, position, path + "/operand");
			if (reduction.result == null || !reduction.operator_kind.accepts (reduction.operand.semantic_type, reduction.result.semantic_type)) {
				fail (path, "vector reduction requires bool<N> operand and scalar bool result");
			}
			return;
		}
		var prefix = instruction as SsaPrefixInstruction;
		if (prefix != null) {
			verify_value (prefix.operand, function, block, position, path + "/operand");
			if (!prefix.operator_kind.accepts (prefix.operand.semantic_type, prefix.result.semantic_type)) {
				fail (path, "invalid semantic prefix operator or operand/result type");
			}
			return;
		}
		var binary = instruction as SsaBinaryInstruction;
		if (binary != null) {
			verify_value (binary.left, function, block, position, path + "/left", binary.operator_kind.is_equality ());
			verify_value (binary.right, function, block, position, path + "/right", binary.operator_kind.is_equality ());
			if (!binary.operator_kind.accepts (binary.left.semantic_type, binary.right.semantic_type, binary.result.semantic_type)) {
				fail (path, "invalid semantic binary operator or operand/result type");
			}
			return;
		}
		fail (path, "unsupported SSA instruction");
	}

	private void verify_edge(SsaEdge edge, SsaFunction function, SsaBlock block, string path) throws SsaError {
		for (int i = 0; i < edge.arguments.length; i++) {
			string argument_path = path + "/argument #%d".printf (i);
			verify_value (edge.arguments[i], function, block, block.instructions.length, argument_path);
			if (edge.arguments[i].semantic_type.is_text_view ()) {
				text_origins.copy (edge.target.parameters[i], edge.arguments[i]);
			}
			if (edge.arguments[i].semantic_type != edge.target.parameters[i].semantic_type) {
				fail (argument_path, "edge argument type does not match target block parameter");
			}
		}
	}

	private void verify_terminator(SsaTerminator terminator, SsaFunction function, SsaBlock block, string path) throws SsaError {
		if (terminator is SsaForeignSignalReturn) {
			var binding = ((SsaForeignSignalReturn) terminator).binding;
			var method = function as SsaMethod;
			var owner = method == null ? null : method.declaring_type as SsaClass;
			if (!binding.valid () || owner == null || owner.foreign_export == null || owner.foreign_export.identity () != binding.root.identity () || SsaForeignApi.target (owner, binding.member) != function || !SsaForeignApi.valid (owner, foreign_program) || function.blocks.length != 1 || function.entry.terminator != terminator || function.entry.instructions.length != 0) {
				fail (path, "native signal lost its exact shared receiver, signature, member or intrinsic body authority");
			}
			return;
		}
		if (terminator is SsaForeignReturn) {
			var imported = (SsaForeignReturn) terminator;
			var types = new GenericArray<SemanticType> ();
			var contracts = new GenericArray<PointerParameterContract> ();
			if (function.return_type.is_struct_storage () && (function.struct_result == null || function.struct_result.mode != StructValueMode.COPY_VALUE)) {
				fail (path, "CImport POD requires an exact copied native result");
			}
			foreach (var p in function.parameters) {
				types.add (p.semantic_type);
				contracts.add (p.pointer_contract);
			}
			if (!ForeignImportTypes.signature (imported.binding, function.name, function.return_type, function.result_contract, function.owned_cleanup == null ? "" : function.owned_cleanup.external_symbol, function.throws_type, types, contracts, (type) => SsaForeignApi.record (foreign_program, type), function.struct_parameters, (type) => { var handle = handles.lookup (type); return handle == null ? null : handle.c_import; }) || !ForeignApiTypes.errors (imported.binding.member, function.throws_type, (name) => { foreach (var type in structs.get_keys ()) {
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
			uint transfers = 0;
			foreach (var parameter in function.parameters) {
				if (parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER) {
					continue;
				}
				if (transfers >= imported.consumed.length || imported.consumed[transfers] != parameter) {
					fail (path, "CImport lost exact ordered owned-parameter consumption");
				}
				verify_value (imported.consumed[transfers], function, block, block.instructions.length, path + "/consumed");
				transfers++;
			}
			if (transfers != imported.consumed.length) {
				fail (path, "CImport consumed inventory differs from owned parameters");
			}
			if (function.blocks.length != 1 || function.entry != block || block.instructions.length != 0) {
				fail (path, "CImport adapter requires one typed return and no executable body");
			}
			return;
		}

		if (terminator is SsaExceptionReturn && function is SsaConstructor && ConstructorContracts.admitted (((SsaConstructor) function).declaring_class.foreign_export, ((SsaConstructor) function).declaring_class.allocation_policy, ((SsaConstructor) function).member_ordinal, function.throws_type)) {
			if (block.instructions.length == 0 || !(block.instructions[block.instructions.length - 1] is SsaConstructorAbort)) {
				fail (path, "checked constructor exceptional exit lacks partial-field retirement");
			}
		}
		if (terminator is SsaNativeDeclaration) {
			if (!function.declaration_only ()) {
				fail (path, "native declaration terminator lost its exact imported signature");
			}
			return;
		}
		if (terminator is SsaExceptionReturn) {
			verify_value (((SsaExceptionReturn) terminator).value, function, block, block.instructions.length, path);
		}
		if (terminator is SsaExceptionUnreachable) {
			verify_value (((SsaExceptionUnreachable) terminator).exception, function, block, block.instructions.length, path);
			return;
		}
		if (terminator is SsaExceptionReturn) {
			if (function.throws_type == null || !(((SsaExceptionReturn) terminator).value.semantic_type is ClassType)) {
				fail (path, "exception return requires exact checked throws declaration");
			}
			return;
		}
		var dispatch = terminator as SsaEnumDispatch;
		if (dispatch != null) {
			foreach (var branch in dispatch.cases) {
				verify_edge (branch.edge, function, block, path + "/case");
			}
			verify_edge (dispatch.invalid_edge, function, block, path + "/invalid");
			return;
		}
		if (terminator is SsaEnumInvalidTag) {
			return;
		}
		if (terminator is SsaEnumReturn) {
			if (((SsaEnumReturn) terminator).source.definition.semantic_type != function.return_type) {
				fail (path, "enum return nominal mismatch");
			}
			return;
		}
		var request = terminator as SsaBufferAllocationBranch;
		if (request != null) {
			verify_value (request.allocation.count, function, block, block.instructions.length, path + "/count");
			verify_edge (request.success_edge, function, block, path + "/success");
			verify_edge (request.failure_edge, function, block, path + "/allocator-null");
			return;
		}
		if (terminator is SsaAllocationFailureTrap) {
			var receiver = ((SsaAllocationFailureTrap) terminator).failure.captured_receiver;
			if (receiver != null) {
				verify_value (receiver, function, block, block.instructions.length, path + "/captured-receiver", false, true);
			}
			return;
		}
		if (function is SsaConstructor && terminator is SsaReturn) {
			fail (path, "constructor explicit return is unsupported");
		}
		if (field_state != null && terminator is SsaFunctionEnd) {
			if (((SsaConstructor) function).declaring_class.parent_class != null && !field_state.is_definite ((int) ((SsaConstructor) function).declaring_class.fields.length)) {
				fail (path, "constructor completion requires exact completed base initialization");
			}
			foreach (var field in ((SsaConstructor) function).declaring_class.fields) {
				if (!field_state.is_definite (field.ordinal)) {
					fail (path, "constructor field not initialized on successful completion: " + field.name);
				}
			}
		}

		var branch = terminator as SsaBranch;
		if (branch != null) {
			verify_edge (branch.edge, function, block, path + "/edge");
			return;
		}
		var conditional = terminator as SsaConditionalBranch;
		if (conditional != null) {
			verify_value (conditional.condition, function, block, block.instructions.length, path + "/condition");
			if (conditional.condition.semantic_type.kind != TypeKind.BOOL) {
				fail (path + "/condition", "conditional branch condition must have type 'bool'");
			}
			verify_edge (conditional.true_edge, function, block, path + "/true");
			verify_edge (conditional.false_edge, function, block, path + "/false");
			return;
		}
		if (terminator is SsaFunctionEnd) {
			if (function.return_type.kind != TypeKind.VOID) {
				fail (path, "non-void function must not reach function-end");
			}
			return;
		}
		if (terminator is SsaBufferReturn) {
			var buffer = (SsaBufferReturn) terminator;
			if (function.owned_cleanup == null || buffer.cleanup != function.owned_cleanup || !matches_cleanup (function.return_type, buffer.cleanup) || buffer.pair.shape != buffer.cleanup.buffer_shape) {
				fail (path, "buffer return requires exact owner result responsibility");
			}
			verify_buffer_pair (buffer.pair, function, block, (int) block.instructions.length, path);
			consume_buffer_pair (buffer.pair, buffer, function, block, (int) block.instructions.length, true, path);
			return;
		}
		if ((terminator is SsaOwnershipReturn) != (function.owned_cleanup != null)) {
			fail (path, "return must match the native result ownership contract");
		}
		if (terminator is SsaStructReturn) {
			var returned = (SsaStructReturn) terminator;
			verify_struct_shape (returned.shape, function.return_type, path);
			if (function.struct_result == null || returned.value != null || returned.leaves.length != returned.shape.leaves.length) {
				fail (path, "struct return requires an exact complete ordered leaf set");
			}
			if (returned.shape.mode != function.struct_result.mode || (returned.shape.mode == StructValueMode.BORROW_VALUE && (function.result_contract != ResultOwnershipContract.RECEIVER_BORROW || returned.record_move != null))) {
				fail (path, "record return cannot change its declared copy, move or bounded borrow mode");
			}
			if (returned.shape.mode == StructValueMode.MOVE_VALUE && returned.record_move != null) {
				var site = buffer_sites.lookup (returned.record_move);
				if (site == null || site.function != function || site.block != block || returned.record_move.consumer != returned) {
					fail (path, "MOVE_VALUE return lost its exact prior complete ownership commit");
				}
			}
			if (returned.shape.mode == StructValueMode.MOVE_VALUE && returned.record_move == null) {
				var first = returned.leaves.length == 0 ? null : returned.leaves[0] as SsaInstructionResult;
				var group = first == null ? null : struct_result_leaves.lookup (first);
				var site = group == null ? null : struct_consumptions.lookup (group);
				var consumption = site == null ? null : site.block.instructions[site.position] as SsaStructResultConsume;
				if (group == null || group.shape != returned.shape || group.leaves.length != returned.leaves.length || consumption == null || consumption.use_kind != StructResultUseKind.RETURN) {
					fail (path, "MOVE_VALUE return requires one complete root move or exact owned result forwarding");
				}
				for (int i = 0; i < returned.leaves.length; i++) {
					if (returned.leaves[i] != group.leaves[i]) {
						fail (path, "MOVE_VALUE forwarding changed an original result field");
					}
				}
				foreach (var pair in group.buffers) {
					consume_buffer_pair (pair, returned, function, block, (int) block.instructions.length, true, path);
				}
			}
			for (int i = 0; i < returned.leaves.length; i++) {
				verify_value (returned.leaves[i], function, block, block.instructions.length, path + "/leaf", false, false, false, returned.shape.leaves[i] is StructBufferLeafPath);
				if (returned.leaves[i].semantic_type != returned.shape.leaves[i].semantic_type) {
					fail (path, "struct return leaf type or order mismatch");
				}
			}
			return;
		}
		var returned = (SsaReturn) terminator;
		if (returned.value == null) {
			if (function.return_type.kind != TypeKind.VOID) {
				fail (path, "non-void function return must carry a value");
			}
			return;
		}
		if (function.heap_result && returned is SsaOwnershipReturn) {
			var owned = (SsaOwnershipReturn) returned;
			if (owned.source_parameter != null && (owned.source_parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER || !owned.source_parameter.heap_object || transfer_root (returned.value) != owned.source_parameter)) {
				fail (path, "heap parameter return must preserve its exact incoming owner pointer");
			}
			if (!(returned.value is SsaNullPointerConstant)) {
				foreach (var instruction in block.instructions) {
					var cleanup = instruction as SsaCleanupInstruction;
					if (cleanup != null && transfer_root (cleanup.value) == transfer_root (returned.value)) {
						fail (path, "callee cannot clean up its transferred heap result pointer");
					}
				}
			}
		}
		if (function.result_storage != null) {
			var owned = (SsaOwnershipReturn) returned;
			foreach (var instruction in block.instructions) {
				var cleanup = instruction as SsaCleanupInstruction;
				if (cleanup != null && cleanup.value == returned.value) {
					fail (path, "callee cannot clean up its transferred owner result");
				}
			}
			if (!owned.provenance.is_returnable ()) {
				fail (path, "owned result has illegal storage provenance");
			}
			if (owned.provenance == ObjectResultProvenance.RESULT_STORAGE) {
				int constructions = 0;
				foreach (var instruction in block.instructions) {
					var construction = instruction as SsaResultConstructionInstruction;
					if (construction != null && construction.storage == function.result_storage) {
						constructions++;
					}
				}
				if (returned.value != function.result_storage || constructions != 1) {
					fail (path, "fresh return requires exact result input and one constructor call");
				}
				return;
			}
			if (owned.provenance == ObjectResultProvenance.NULL && !(returned.value is SsaNullPointerConstant) && !caller_result_origins.null_only (function, returned.value)) {
				fail (path, "null provenance requires an independently proved null pointer");
			}
			if (owned.provenance == ObjectResultProvenance.OWNED_PARAMETER_STORAGE) {
				bool exact_parameter = owned.source_parameter != null && function.parameters.find (owned.source_parameter)
				    && owned.source_parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && returned.value == owned.source_parameter;
				bool direct = returned.value is SsaFunctionParameter || owned.source_parameter != null;
				if (direct ? !exact_parameter : !caller_result_origins.incoming (function, returned.value)) {
					fail (path, "owned parameter return must preserve exact incoming pointer identity or independently derived caller roots");
				}
			}
			if (owned.provenance == ObjectResultProvenance.FORWARDED_OWNED_RESULT) {
				SsaCallInstruction? producer = null;
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call != null && call.result == returned.value) {
						producer = call;
					}
				}
				if (producer == null || producer.result_storage != function.result_storage || producer.owned_result_use != SsaOwnedResultUse.FORWARD) {
					fail (path, "forwarded return must preserve producer pointer and result storage");
				}
				foreach (var transfer in producer.owned_arguments) {
					if (transfer.value.semantic_type == function.return_type && !(transfer.value is SsaNullPointerConstant) && (!(transfer.value is SsaFunctionParameter) || ((SsaFunctionParameter) transfer.value).pointer_contract != PointerParameterContract.OWNED_TRANSFER)) {
						fail (path, "callee-local ObjectStorage cannot escape through forwarding");
					}
				}
			}
		}
		verify_value (returned.value, function, block, block.instructions.length, path + "/value");
		if (returned.value.semantic_type is StringType) {
			if (function.result_contract != ResultOwnershipContract.RECEIVER_TEXT) {
				text_returns.add (returned.value);
			}
		}
		if (returned.value.semantic_type != function.return_type) {
			fail (path, "return value type does not match function return type");
		}
	}

}
}
