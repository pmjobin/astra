// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
// A type constructor, deliberately neither NativeInstanceSymbol nor StructSymbol.
public class GenericStructSymbol : Symbol {
	public OwnedRecordDefinitionContract? owning_contract { get; internal set; }
	public bool owning_storage { get; internal set; }
	internal bool fields_complete;
	internal HashTable<GenericStructApplicationType, StructSymbol> owning_instances = new HashTable<GenericStructApplicationType, StructSymbol> (direct_hash, direct_equal);
	public RecordDefinitionIdentity nominal_identity { get; private set; }
	public int ordinal { get; private set; }
	public GenericArray<TypeParameterSymbol> type_parameters { get; private set; default = new GenericArray<TypeParameterSymbol> (); }
	public GenericArray<GenericStructFieldSymbol> fields { get; private set; default = new GenericArray<GenericStructFieldSymbol> (); }
	private GenericArray<GenericStructApplicationType> applications = new GenericArray<GenericStructApplicationType> ();
	internal GenericStructSymbol (SourceSpan span, SourceSpan name_span, int ordinal, string? name = null, GenericArray<string>? imported_applications = null) {
		base (span, name_span, name);
		this.ordinal = ordinal;
		nominal_identity = new RecordDefinitionIdentity (this.name, imported_applications);
	}
	public GenericStructFieldSymbol? find_field(string name) {
		foreach (var field in fields) {
			if (field.name == name) {
				return field;
			}
		}
		return null;
	}
	public GenericStructApplicationType application(GenericArray<SemanticType> arguments) {
		foreach (var prior in applications) {
			if (prior.matches (arguments)) {
				return prior;
			}
		}
		var result = new GenericStructApplicationType (this, arguments);
		applications.add (result);
		return result;
	}
	public TypeSubstitution substitution(GenericArray<SemanticType> arguments) {
		assert (arguments.length == type_parameters.length);
		var result = new TypeSubstitution ();
		for (int i = 0; i < arguments.length; i++) {
			result.bind (type_parameters[i].semantic_type, arguments[i]);
		}
		return result;
	}
}
public class OwnedRecordInstantiation : Object {
	private WeakRef definition;
	public GenericStructSymbol? origin { owned get { return (GenericStructSymbol?) definition.get (); } }
	public TypeArgumentVector arguments { get; private set; }
	internal OwnedRecordInstantiation (GenericStructSymbol origin, GenericArray<SemanticType> arguments) {
		definition = WeakRef (origin);
		this.arguments = new TypeArgumentVector (arguments);
	}
}

public class GenericStructFieldSymbol : FieldSymbol {
	public bool is_private { get; internal set; }
	private WeakRef owner;
	public GenericStructSymbol? definition { owned get { return (GenericStructSymbol?) owner.get (); } }
	internal GenericStructFieldSymbol (SourceSpan span, SourceSpan name_span, GenericStructSymbol definition, SemanticType type, int ordinal) {
		base (span, name_span, type, ordinal);
		this.owner = WeakRef (definition);
	}
}

public class GenericStructApplicationType : SemanticType {
	private WeakRef owner;
	public GenericStructSymbol? definition { owned get { return (GenericStructSymbol?) owner.get (); } }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	private string identifier;
	internal GenericStructApplicationType (GenericStructSymbol definition, GenericArray<SemanticType> arguments) {
		base (TypeKind.GENERIC_STRUCT_APPLICATION);
		this.owner = WeakRef (definition);
		this.identifier = definition.name;
		this.type_arguments = new GenericArray<SemanticType> ();
		foreach (var argument in arguments) {
			type_arguments.add (argument);
		}
		bind_logical_identity (definition.nominal_identity.application (arguments));
	}
	public bool matches(GenericArray<SemanticType> arguments) {
		return TypeArgumentVector.same_values (type_arguments, arguments);
	}
	public override bool is_parameterized() {
		foreach (var argument in type_arguments) {
			if (argument.is_parameterized ()) {
				return true;
			}
		}
		return false;
	}
	public override string? generic_definition_name() {
		return identifier;
	}
	public override TypeArgumentVector? generic_arguments() {
		return new TypeArgumentVector (type_arguments);
	}
	public override string display_name() {
		var result = new StringBuilder (identifier + "<");
		for (int i = 0; i < type_arguments.length; i++) {
			if (i != 0) {
				result.append (",");
			}
			result.append (type_arguments[i].display_name ());
		}
		result.append (">");
		return result.str;
	}
	internal override SemanticType substitute(TypeSubstitution substitution) {
		return definition.application (substitution.apply_arguments (type_arguments));
	}
	public SemanticType field_type(GenericStructFieldSymbol field) {
		assert (field.definition == definition);
		return definition.substitution (type_arguments).apply (field.semantic_type);
	}
}

public class CheckedGenericStruct : CheckedNode {
	public GenericStructSymbol definition { get; private set; }
	public GenericArray<TypeParameterSymbol> type_parameters { get { return definition.type_parameters; } }
	public GenericArray<GenericStructFieldSymbol> fields { get { return definition.fields; } }
	internal CheckedGenericStruct (GenericStructSymbol definition) {
		base (definition.span);
		this.definition = definition;
	}
}

// Temporary projection in the same recursive Place tree. Its exact origin is
// mapped directly to an ordinary field during Core materialization.
public class CheckedGenericStructFieldPlace : CheckedPlace {
	public CheckedPlace aggregate { get; private set; }
	public GenericStructApplicationType application { get; private set; }
	public GenericStructFieldSymbol field { get; private set; }
	internal CheckedGenericStructFieldPlace (SourceSpan span, CheckedPlace aggregate, GenericStructFieldSymbol field) {
		base (span, ((GenericStructApplicationType) aggregate.semantic_type).field_type (field));
		this.aggregate = aggregate;
		this.application = (GenericStructApplicationType) aggregate.semantic_type;
		this.field = field;
	}
}
}
