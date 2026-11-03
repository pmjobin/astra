// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
namespace Astra.Core {
internal class CoreDeclaredClassAuthority : Object {
	private static void require(bool valid) throws CoreError {
		if (!valid) {
			throw new CoreError.INVALID_IR ("declared generic Class lost substituted type/field/member/lifetime authority");
		}
	}

	private static bool exact_heap_class_argument(CoreProgram program, SemanticType type) {
		foreach (var owner in program.classes) {
			if (owner.semantic_type == type) {
				return owner.generic_instance == null && !owner.polymorphic && owner.parent_class == null && !((ClassType) type).is_interface;
			}
		}
		return false;
	}

	private static void callable(CoreProgram program, CoreFunction function, GenericMemberPattern member, ExactClassGenericInstance key, CopyabilityFields field_graph, TypeArgumentVector? method_arguments = null) throws CoreError {
		var types = new GenericArray<SemanticType> ();
		var contracts = new GenericArray<PointerParameterContract> ();
		foreach (var parameter in function.parameters) {
			types.add (parameter.semantic_type);
			contracts.add (parameter.pointer_contract);
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

	internal static void verify(CoreProgram program, CoreClass owner, ExactClassGenericInstance key) throws CoreError {
		CopyabilityFields field_graph = (type) => {
			var application = type as CoreGenericStructApplicationType;
			if (application != null && application.definition != null) {
				var fields = new GenericArray<SemanticType> ();
				foreach (var field in application.definition.fields) {
					fields.add (application.field_type (field));
				}
				return fields;
			}
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
			CoreFunction? function = null;
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

// Reconstruct concrete template signatures independently of Checked. The
// legacy profile also retains its finite operation recipes. Ordinary bodies,
// ownership, origin, cleanup, loans and effects remain CoreVerifier's.
internal class CoreExactClassAuthority : Object {
	private static void require(bool valid) throws CoreError {
		if (!valid) {
			throw new CoreError.INVALID_IR ("exact-Class generic specialization lost definition/key/field/member operation authority");
		}
	}

	private static bool store(CoreIndirectFieldPlace value, CoreClass owner, CoreFunction function) {
		var receiver = value.pointer as CoreReceiverValue;
		return owner.fields.length == 1 && value.field == owner.fields[0] && receiver != null && receiver.receiver == function.implicit_receiver;
	}

	private static void body(CoreFunction function, CoreClass owner, ExactClassOperation operation, int member, ClassMethodInstance? method_key = null) throws CoreError {
		var key = owner.generic_instance;
		var types = new GenericArray<SemanticType> ();
		var contracts = new GenericArray<PointerParameterContract> ();
		foreach (var parameter in function.parameters) {
			types.add (parameter.semantic_type);
			contracts.add (parameter.pointer_contract);
		}
		var signature = method_key == null ? key.definition.signature(member) : key.definition.generic_method_signature (method_key.member);
		bool owned_result = key.definition.general_bodies && (key.argument is StructType) ? false : key.definition.general_bodies ? signature.owned_result : operation == ExactClassOperation.TAKE;
		require (function.async_body == null && function.throws_type == null && function.generic_instance == null && !(function is CoreGenericFunction) && (owned_result ? function.owned_cleanup == owner.fields[0].slots_cleanup && function.heap_result == (key.argument is ClassType) : function.owned_cleanup == null) && function.dispatch_kind == ClassDispatchKind.DIRECT && ExactClassGenericShape.signature (key, operation, function.return_type, types, contracts, function.parameters.length > 0 && function.parameters[function.parameters.length - 1].heap_object, member, method_key));
		if (key.definition.general_bodies) {
			return;
		}
		var statements = function.body.statements;
		if (operation == ExactClassOperation.INITIALIZE) {
			require (statements.length == 1 && statements[0] is CoreSlotsInitialize);
			require (store (((CoreSlotsInitialize) statements[0]).store, owner, function));
			return;
		}
		if (operation == ExactClassOperation.TAKE) {
			require (statements.length == 2 && statements[0] is CoreInitialize && statements[1] is CoreOwnershipReturn);
			var initialize = (CoreInitialize) statements[0];
			var returned = (CoreOwnershipReturn) statements[1];
			var take = initialize.value as CoreSlotsTake;
			require (take != null && initialize.acquisition != null && initialize.acquisition.cleanup == owner.fields[0].slots_cleanup && returned.source == initialize.acquisition && returned.producer == null && store (take.store, owner, function) && take.index is CoreParameterValue && ((CoreParameterValue) take.index).parameter == function.parameters[0]);
			return;
		}
		if (operation == ExactClassOperation.REPLACE) {
			require (statements.length == 2 && statements[0] is CoreAcquireParameter && statements[1] is CoreSlotsReplace);
			var acquire = (CoreAcquireParameter) statements[0];
			var replace = (CoreSlotsReplace) statements[1];
			require (store (replace.store, owner, function) && acquire.acquisition == replace.incoming && acquire.value is CoreParameterValue && ((CoreParameterValue) acquire.value).parameter == function.parameters[1] && replace.index is CoreParameterValue && ((CoreParameterValue) replace.index).parameter == function.parameters[0]);
			return;
		}
		if (operation == ExactClassOperation.APPEND) {
			require (statements.length == 2 && statements[0] is CoreAcquireParameter && statements[1] is CoreSlotsAppend);
			var acquire = (CoreAcquireParameter) statements[0];
			var append = (CoreSlotsAppend) statements[1];
			require (store (append.store, owner, function) && acquire.acquisition == append.incoming && acquire.value is CoreParameterValue && ((CoreParameterValue) acquire.value).parameter == function.parameters[0]);
			return;
		}
		require (statements.length == 1 && statements[0] is CoreReturn && ((CoreReturn) statements[0]).value is CoreSlotsValue);
		var value = (CoreSlotsValue) ((CoreReturn) statements[0]).value;
		require (store (value.store, owner, function) && value.borrower == null);
		if (operation == ExactClassOperation.RESERVE) {
			require (value.action == OwnerSlotsAction.RESERVE && value.operand is CoreParameterValue && ((CoreParameterValue) value.operand).parameter == function.parameters[0]);
		} else {
			require (value.operand == null && value.action == (operation == ExactClassOperation.COUNT ? OwnerSlotsAction.LENGTH : OwnerSlotsAction.CAPACITY));
		}
	}

	internal static void verify(CoreProgram program) throws CoreError {
		var definitions = new HashTable<ExactClassDefinitionIdentity, bool> (direct_hash, direct_equal);
		foreach (var definition in program.generic_classes) {
			require (definition.valid () && !definitions.contains (definition));
			definitions.insert (definition, true);
		}
		foreach (var function in program.all_definitions ()) {
			if (GenericClassTypes.general (function.return_type)) {
				require (function.async_body == null);
			} else {
				require (!(function.return_type is ExactGenericClassType));
			}
			foreach (var parameter in function.parameters) {
				if (GenericClassTypes.general (parameter.semantic_type)) {
					require (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && function.async_body == null || parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && (function.async_body == null || parameter.heap_object));
				} else if (parameter.semantic_type is ExactGenericClassType) {
					require (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && !(function is CoreGenericFunction) && function.generic_instance == null && function.async_body == null && function.throws_type == null && (function.return_type.kind == TypeKind.VOID || GenericBorrowTypes.scalar (function.return_type)));
				}
			}
		}
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				require (!(field.semantic_type is ExactGenericClassType) || GenericClassTypes.general (field.semantic_type) && field.owned_cleanup != null && field.owned_cleanup.is_heap_object);
			}
			var key = owner.generic_instance;
			require ((key != null) == (owner.semantic_type is ExactGenericClassType));
			if (key == null) {
				foreach (var method in owner.methods) {
					require (method.generic_method_instance == null);
				}
				continue;
			}
			if (key.definition.structure != null) {
				require (definitions.contains (key.definition));
				CoreDeclaredClassAuthority.verify (program, owner, key);
				continue;
			}
			int generic_count = 0;
			foreach (var method in owner.methods) {
				if (method.generic_method_instance != null) {
					generic_count++;
				}
			}
			require (key.valid (owner.semantic_type) && definitions.contains (key.definition) && owner.name == key.instance_type.name && owner.fields.length == 1 && owner.methods.length == key.definition.member_count - 1 + generic_count && owner.constructor != null && owner.destructor != null && owner.properties.length == key.definition.property_count && !owner.polymorphic && owner.parent_class == null && !owner.exception_root);
			require (ExactClassGenericShape.field (key, owner.fields[0].semantic_type, owner.fields[0].name));
			for (int p = 0; p < owner.properties.length; p++) {
				var property = owner.properties[p];
				var getter = property.getter;
				require (ExactClassGenericShape.property (key, p, property.name, property.semantic_type) && property.ordinal == p && !property.is_lazy && !property.is_owned_lazy && !property.is_borrowed && property.setter == null && property.factory == null);
				require (getter != null && getter.property_member == property && program.functions.find (getter) && getter.return_type == property.semantic_type && getter.parameters.length == 0 && getter.result_contract == ResultOwnershipContract.UNMANAGED && getter.owned_cleanup == null && !getter.heap_result && getter.async_body == null && getter.throws_type == null && getter.dispatch_kind == ClassDispatchKind.DIRECT);
			}
			foreach (var other in program.classes) {
				var prior = other.generic_instance;
				if (other != owner && prior != null) {
					require (prior.definition != key.definition || prior.argument != key.argument);
				}
			}
			for (int i = 0; i < key.definition.member_count; i++) {
				var operation = key.definition.operation (i);
				CoreFunction? function = operation == ExactClassOperation.INITIALIZE ? (CoreFunction) owner.constructor : null;
				if (function == null) {
					foreach (var method in owner.methods) {
						if (method.name == key.definition.member_name (i)) {
							require (function == null);
							function = method;
						}
					}
				}
				require (function != null && program.functions.find (function));
				body (function, owner, operation, i);
			}
			foreach (var method in owner.methods) {
				var request = method.generic_method_instance;
				if (request == null) {
					continue;
				}
				require (request.valid (key) && method.name == request.name);
				CopyabilityFields fields = (type) => {
					foreach (var enumeration in program.enums) {
						if (enumeration.semantic_type == type) {
							return enumeration.value_fields ();
						}
					}
					var result = new GenericArray<SemanticType> ();
					var application = type as CoreGenericStructApplicationType;
					if (application != null && application.definition != null) {
						foreach (var field in application.definition.fields) {
							result.add (application.field_type (field));
						}
						return result;
					}
					foreach (var record in program.structs) {
						if (record.semantic_type == type) {
							foreach (var field in record.fields) {
								result.add (field.semantic_type);
							}
							return result;
						}
					}
					return null;
				};
				require (GenericArgumentTypes.plain_copy (request.argument, fields));
				foreach (var prior in owner.methods) {
					var other = prior.generic_method_instance;
					if (prior != method && other != null) {
						require (other.member != request.member || other.argument != request.argument);
					}
				}
				body (method, owner, ExactClassOperation.BODY, -1, request);
			}
			require (owner.destructor.body.statements.length == 0);
		}
	}

}
}
