// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
namespace Astra.Semantic {
public delegate bool ExactHeapClassArgument(SemanticType type);
public class GenericClassTypes : Object {
	public static bool general(SemanticType? type) {
		return type is ExactGenericClassType && ((ExactGenericClassType) type).definition.general_bodies;
	}

	public static bool borrowed_context(SemanticType type, PointerParameterContract contract) {
		return contract == PointerParameterContract.BORROWED_NOESCAPE && general (type);
	}

}

// Shared declaration/substitution correspondence. Stage verifiers supply
// their own concrete fields and reconstructed source-level parameter groups.
// No Checked/Core/CFG/SSA objects survive in this authority.
public class GenericClassDeclaredShape : Object {
	public static bool constraint(GenericTypeConstraint constraint, TypeArgumentVector class_arguments, TypeArgumentVector? method_arguments = null, ExactHeapClassArgument? exact_class = null) {
		var arguments = constraint.method_parameter ? method_arguments : class_arguments;
		if (arguments == null || constraint.parameter < 0 || constraint.parameter >= arguments.length) {
			return false;
		}
		var type = arguments.at (constraint.parameter);
		if (constraint.exact_heap_class) {
			return type is ClassType && !(type is ExactGenericClassType) && !((ClassType) type).is_interface && (exact_class == null || exact_class (type));
		}
		for (int c = 0; c < constraint.capabilities.length; c++) {
			if (!GenericCapabilityAuthority.satisfies (type, constraint.capabilities.at (c))) {
				return false;
			}
		}
		return true;
	}

	public static bool type(GenericTypePattern pattern, SemanticType actual, ExactClassGenericInstance key, TypeArgumentVector? method_arguments = null, CopyabilityFields? fields = null) {
		return arguments (pattern, actual, key.arguments, method_arguments, fields);
	}

	public static bool arguments(GenericTypePattern pattern, SemanticType actual, TypeArgumentVector class_arguments, TypeArgumentVector? method_arguments = null, CopyabilityFields? fields = null) {
		switch (pattern.kind) {
		case GenericTypePatternKind.PARAMETER:
			return pattern.parameter >= 0 && pattern.parameter < class_arguments.length && class_arguments.at (pattern.parameter).logical_identity == actual.logical_identity;
		case GenericTypePatternKind.METHOD_PARAMETER:
			return method_arguments != null && pattern.parameter >= 0 && pattern.parameter < method_arguments.length && method_arguments.at (pattern.parameter).logical_identity == actual.logical_identity;
		case GenericTypePatternKind.NONNULL:
			return arguments (pattern.argument (0), actual, class_arguments, method_arguments, fields);
		case GenericTypePatternKind.POINTER:
			var pointer = actual as TypedPointerType;
			var raw = actual as RawPointerType;
			return pointer != null ? arguments(pattern.argument (0), pointer.pointee, class_arguments, method_arguments, fields) : raw != null && arguments (pattern.argument (0), raw.pointee, class_arguments, method_arguments, fields);
		case GenericTypePatternKind.SLICE:
			return actual is SliceType && arguments (pattern.argument (0), ((SliceType) actual).element_type, class_arguments, method_arguments, fields);
		case GenericTypePatternKind.OWNER_SLOTS:
			return actual is OwnerSlotsType && arguments (pattern.argument (0), ((OwnerSlotsType) actual).element, class_arguments, method_arguments, fields);
		case GenericTypePatternKind.APPLICATION:
			var actual_arguments = actual.generic_arguments ();
			if (actual.generic_definition_name () != pattern.name || actual_arguments == null || actual_arguments.length != pattern.argument_count) {
				return false;
			}
			var callable = actual as FunctionValueType;
			if (callable != null) {
				if ((pattern.argument (0).value_mode == GenericValueMode.OWNED) != (callable.result_contract == ResultOwnershipContract.OWNED_TRANSFER)) {
					return false;
				}
				for (int p = 0; p < callable.parameter_types.length; p++) {
					var mode = pattern.argument (p + 1).value_mode;
					var value = callable.parameter_types[p];
					bool owner = value is ClassType || value is HandleType || value is TypeParameterType && ((TypeParameterType) value).transport_mode == GenericTransportMode.OWNABLE;
					bool record = value.is_struct_storage () && fields != null && CopyabilityAuthority.of (value, fields) != Copyability.COPYABLE;
					var contract = mode == GenericValueMode.OWNED ? PointerParameterContract.OWNED_TRANSFER : mode == GenericValueMode.BORROWED && (owner || record) ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED;
					if (callable.parameter_contract (p) != contract) {
						return false;
					}
				}
			}
			for (int a = 0; a < pattern.argument_count; a++) {
				if (!arguments (pattern.argument (a), actual_arguments.at (a), class_arguments, method_arguments, fields)) {
					return false;
				}
			}
			return true;
		case GenericTypePatternKind.NAMED:
			if (pattern.name == "i32" || pattern.name == "int") {
				return actual.kind == TypeKind.INT;
			}
			return actual.display_name () == pattern.name;
		default:
			return false;
		}
	}

	public static PointerParameterContract parameter_contract(GenericValueMode mode, SemanticType type, CopyabilityFields fields) {
		if (type is ClassType || type is HandleType || type is TypeParameterType && ((TypeParameterType) type).transport_mode == GenericTransportMode.OWNABLE) {
			return mode == GenericValueMode.OWNED ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
		}
		if (mode == GenericValueMode.BORROWED && type.is_struct_storage () && CopyabilityAuthority.of (type, fields) != Copyability.COPYABLE) {
			return PointerParameterContract.BORROWED_NOESCAPE;
		}
		return PointerParameterContract.UNMANAGED;
	}

	public static bool owns_value(GenericValueMode mode, SemanticType type) {
		return mode == GenericValueMode.OWNED && (type is ClassType || type is HandleType || type is SliceType || type is OwnerSlotsType || type is TypeParameterType && ((TypeParameterType) type).transport_mode == GenericTransportMode.OWNABLE);
	}

	public static bool owns_field(bool declared, SemanticType type, CopyabilityFields fields) {
		return (type is StructType) ? CopyabilityAuthority.of (type, fields) != Copyability.COPYABLE : owns_value (declared ? GenericValueMode.OWNED : GenericValueMode.VALUE, type);
	}

	public static bool signature(GenericMemberPattern member, ExactClassGenericInstance key,
		SemanticType result, GenericArray<SemanticType> parameters, GenericArray<PointerParameterContract> contracts,
		ClassType? error, bool async_member, CopyabilityFields fields, TypeArgumentVector? method_arguments = null, ExactHeapClassArgument? exact_class = null) {
		for (int c = 0; c < member.constraint_count; c++) {
			if (!constraint (member.constraint (c), key.arguments, method_arguments, exact_class)) {
				return false;
			}
		}
		if (parameters.length != member.parameter_count || contracts.length != parameters.length || !type (member.result, result, key, method_arguments, fields)) {
			return false;
		}
		if (member.async_member != async_member || (member.error == null ? error != null : error == null || !type (member.error, error, key, method_arguments))) {
			return false;
		}
		for (int p = 0; p < member.parameter_count; p++) {
			if (!type (member.parameter_type (p), parameters[p], key, method_arguments, fields) || parameter_contract (member.parameter_mode (p), parameters[p], fields) != contracts[p]) {
				return false;
			}
		}
		return true;
	}

}
public class ClassMethodInstance : Object {
	public ExactClassGenericInstance class_instance { get; private set; }
	public int member { get; private set; }
	public TypeArgumentVector arguments { get; private set; }
	public SemanticType argument { get { return arguments.at (0); } }
	public string name { owned get { return class_instance.definition.generic_method_name (member) + arguments.display_suffix (true); } }
	internal ClassMethodInstance (ExactClassGenericInstance owner, int member, SemanticType argument) {
		this.application (owner, member, new TypeArgumentVector.single (argument));
	}

	internal ClassMethodInstance.application (ExactClassGenericInstance owner, int member, TypeArgumentVector arguments) {
		this.class_instance = owner.copy ();
		this.member = member;
		this.arguments = arguments;
	}
	public ClassMethodInstance copy(TypeArgumentVector? arguments = null) {
		return new ClassMethodInstance.application (class_instance, member, arguments ?? this.arguments);
	}

	public bool valid(ExactClassGenericInstance owner) {
		return arguments.closed () && valid_application (owner);
	}

	public bool valid_application(ExactClassGenericInstance owner) {
		if (!owner.definition.general_bodies || class_instance.definition != owner.definition || class_instance.instance_type != owner.instance_type || !class_instance.arguments.matches (owner.arguments) || member < 0 || member >= owner.definition.generic_method_count) {
			return false;
		}
		var structure = owner.definition.structure;
		if (structure == null) {
			return arguments.length == 1 && owner.definition.generic_method_signature (member).is_generic_method;
		}
		var declaration = structure.find_member (owner.definition.generic_method_name (member));
		return declaration != null && declaration.type_parameter_count == arguments.length;
	}

}
public class ExactGenericClassType : ClassType {
	public ExactClassDefinitionIdentity definition { get; private set; }
	public TypeArgumentVector arguments { get; private set; }
	public SemanticType argument { get { return arguments.at (0); } }
	internal ExactGenericClassType (ExactClassDefinitionIdentity definition, SemanticType argument) {
		this.application (definition, new TypeArgumentVector.single (argument));
	}

	internal ExactGenericClassType.application (ExactClassDefinitionIdentity definition, TypeArgumentVector arguments) {
		base (definition.name + arguments.display_suffix ());
		this.definition = definition;
		this.arguments = arguments;
	}
	public override bool is_parameterized() {
		return !arguments.closed ();
	}

	internal override SemanticType substitute(TypeSubstitution substitution) {
		return substitution.class_type (this);
	}

	public override string? generic_definition_name() {
		return definition.name;
	}

	public override TypeArgumentVector? generic_arguments() {
		return arguments;
	}

}

// Each compiler stage copies this immutable provenance into its own class
// descriptor. Exact nominal types remain the existing ownership authority.
public class ExactClassGenericInstance : Object {
	public ExactClassDefinitionIdentity definition { get; private set; }
	public TypeArgumentVector arguments { get; private set; }
	public SemanticType argument { get { return arguments.at (0); } }
	public ExactGenericClassType instance_type { get; private set; }
	internal ExactClassGenericInstance (ExactClassDefinitionIdentity definition, SemanticType argument, ExactGenericClassType type) {
		this.application (definition, new TypeArgumentVector.single (argument), type);
	}

	internal ExactClassGenericInstance.application (ExactClassDefinitionIdentity definition, TypeArgumentVector arguments, ExactGenericClassType type) {
		this.definition = definition;
		this.arguments = arguments;
		this.instance_type = type;
	}
	public ExactClassGenericInstance copy() {
		return new ExactClassGenericInstance.application (definition, arguments, instance_type);
	}

	public bool valid(SemanticType type) {
		if (!definition.valid () || type != instance_type || instance_type.definition != definition || !instance_type.arguments.matches (arguments) || !arguments.closed () || arguments.length != definition.parameter_count) {
			return false;
		}
		if (definition.structure != null) {
			for (int a = 0; a < arguments.length; a++) {
				if (arguments.at (a).kind == TypeKind.VOID) {
					return false;
				}
			}
			return true;
		}
		return (!(argument is ExactGenericClassType) || definition.general_bodies && GenericClassTypes.general (argument)) && (argument is ClassType || definition.general_bodies && (argument.get_type () == typeof (HandleType) || argument is StructType));
	}

}

public class ExactClassGenericShape : Object {
	public static bool property(ExactClassGenericInstance key, int ordinal, string name, SemanticType result) {
		return key.definition.general_bodies && ordinal >= 0 && ordinal < key.definition.property_count && key.definition.property_name (ordinal) == name && role (key.definition.property_result (ordinal), result, key);
	}

	public static bool field(ExactClassGenericInstance key, SemanticType type, string name) {
		var slots = type as OwnerSlotsType;
		return slots != null && slots.element == key.argument && name == key.definition.field_name;
	}

	private static bool role(GenericClassValueRole role, SemanticType type, ExactClassGenericInstance key, SemanticType? method_argument = null) {
		return role == GenericClassValueRole.METHOD_ARGUMENT ? type == method_argument : role == GenericClassValueRole.ARGUMENT ? type == key.argument : role == GenericClassValueRole.VOID ? type.kind == TypeKind.VOID : role == GenericClassValueRole.BOOL ? type.kind == TypeKind.BOOL : role == GenericClassValueRole.INT && type.kind == TypeKind.INT;
	}

	public static bool signature(ExactClassGenericInstance key, ExactClassOperation op, SemanticType result, GenericArray<SemanticType> types, GenericArray<PointerParameterContract> contracts, bool heap, int member = -1, ClassMethodInstance? method = null) {
		if (types.length != contracts.length) {
			return false;
		}
		if (key.definition.general_bodies) {
			if (method != null && !method.valid (key)) {
				return false;
			}
			var signature = method == null ? key.definition.signature(member) : key.definition.generic_method_signature (method.member);
			var method_argument = method == null ? null : method.argument;
			if (signature == null || !role (signature.result, result, key, method_argument) || types.length != signature.parameter_count) {
				return false;
			}
			for (int p = 0; p < types.length; p++) {
				var expected = signature.parameter (p) == GenericClassValueRole.ARGUMENT && !(key.argument is StructType) ? (signature.owns_parameter (p) ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE) : PointerParameterContract.UNMANAGED;
				if (!role (signature.parameter (p), types[p], key, method_argument) || contracts[p] != expected) {
					return false;
				}
			}
			return true;
		}
		if (op == ExactClassOperation.INITIALIZE) {
			return result.kind == TypeKind.VOID && types.length == 0;
		}
		if (op == ExactClassOperation.APPEND) {
			return result.kind == TypeKind.VOID && types.length == 1 && types[0] == key.argument && contracts[0] == PointerParameterContract.OWNED_TRANSFER && heap;
		}
		if (op == ExactClassOperation.TAKE) {
			return result == key.argument && types.length == 1 && types[0].kind == TypeKind.INT && contracts[0] == PointerParameterContract.UNMANAGED;
		}
		if (op == ExactClassOperation.REPLACE) {
			return result.kind == TypeKind.VOID && types.length == 2 && types[0].kind == TypeKind.INT && contracts[0] == PointerParameterContract.UNMANAGED && types[1] == key.argument && contracts[1] == PointerParameterContract.OWNED_TRANSFER && heap;
		}
		if (op == ExactClassOperation.RESERVE) {
			return result.kind == TypeKind.BOOL && types.length == 1 && types[0].kind == TypeKind.INT && contracts[0] == PointerParameterContract.UNMANAGED;
		}
		return (op == ExactClassOperation.COUNT || op == ExactClassOperation.CAPACITY) && result.kind == TypeKind.INT && types.length == 0;
	}

}
}
