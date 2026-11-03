// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Core {
// Immutable origin tokens have no checked, definition-body or layout backlink.
public class CoreGenericStructIdentity : CoreNode {
	public RecordDefinitionIdentity nominal_identity { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public int ordinal { get; private set; }
	internal CoreGenericStructIdentity (SourceSpan span, string name, int ordinal, RecordDefinitionIdentity? nominal = null) {
		base (span);
		this.identifier = name;
		this.ordinal = ordinal;
		nominal_identity = nominal ?? new RecordDefinitionIdentity (name);
	}

}

public class CoreGenericStructFieldIdentity : CoreNode {
	public CoreGenericStructIdentity definition { get; private set; }
	private string identifier;
	public string name { get { return identifier; } }
	public int ordinal { get; private set; }
	internal CoreGenericStructFieldIdentity (SourceSpan span, CoreGenericStructIdentity definition, string name, int ordinal) {
		base (span);
		this.definition = definition;
		this.identifier = name;
		this.ordinal = ordinal;
	}

}

// No CoreNativeInstance inheritance, concrete semantic type, receiver or layout.
public class CoreGenericStruct : CoreNode {
	public CoreGenericStructIdentity identity { get; private set; }
	public SourceSpan name_span { get; private set; }
	public string name { get { return identity.name; } }
	public GenericArray<CoreTypeParameter> type_parameters { get; private set; }
	public GenericArray<CoreGenericStructField> fields { get; private set; default = new GenericArray<CoreGenericStructField> (); }
	private GenericArray<CoreGenericStructApplicationType> applications = new GenericArray<CoreGenericStructApplicationType> ();
	internal CoreGenericStruct (SourceSpan span, SourceSpan name_span, string name, GenericArray<CoreTypeParameter> parameters, int ordinal, RecordDefinitionIdentity? nominal = null) {
		base (span);
		this.name_span = name_span;
		this.identity = new CoreGenericStructIdentity (span, name, ordinal, nominal);
		this.type_parameters = parameters;
	}

	public CoreGenericStructApplicationType application(GenericArray<SemanticType> arguments) {
		foreach (var prior in applications) {
			if (prior.matches (arguments)) {
				return prior;
			}
		}
		var result = new CoreGenericStructApplicationType (this, arguments);
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

public class CoreGenericStructField : CoreNode {
	private WeakRef owner;
	public CoreGenericStruct? definition { owned get { return (CoreGenericStruct?) owner.get (); } }
	public CoreGenericStructFieldIdentity identity { get; private set; }
	public SourceSpan name_span { get; private set; }
	public string name { get { return identity.name; } }
	public int ordinal { get { return identity.ordinal; } }
	public SemanticType semantic_type { get; private set; }
	internal CoreGenericStructField (SourceSpan span, SourceSpan name_span, string name, CoreGenericStruct definition, SemanticType type, int ordinal) {
		base (span);
		this.owner = WeakRef (definition);
		this.name_span = name_span;
		this.identity = new CoreGenericStructFieldIdentity (span, definition.identity, name, ordinal);
		this.semantic_type = type;
	}

}

public class CoreGenericStructApplicationType : SemanticType {
	private WeakRef owner;
	public CoreGenericStruct? definition { owned get { return (CoreGenericStruct?) owner.get (); } }
	public CoreGenericStructIdentity origin { get; private set; }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	internal CoreGenericStructApplicationType (CoreGenericStruct definition, GenericArray<SemanticType> arguments) {
		base (TypeKind.GENERIC_STRUCT_APPLICATION);
		this.owner = WeakRef (definition);
		this.origin = definition.identity;
		this.type_arguments = new GenericArray<SemanticType> ();
		foreach (var argument in arguments) {
			type_arguments.add (argument);
		}
		bind_logical_identity (definition.identity.nominal_identity.application (arguments));
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
		return origin.name;
	}

	public override TypeArgumentVector? generic_arguments() {
		return new TypeArgumentVector (type_arguments);
	}

	public override string display_name() {
		return GenericStructInstance.application_name (origin, type_arguments);
	}

	internal override SemanticType substitute(TypeSubstitution substitution) {
		return definition.application (substitution.apply_arguments (type_arguments));
	}

	public SemanticType field_type(CoreGenericStructField field) {
		assert (field.definition == definition);
		return definition.substitution (type_arguments).apply (field.semantic_type);
	}

}

public class CoreGenericStructFieldPlace : CoreStorageFieldPlace {
	public CoreGenericStructApplicationType application { get; private set; }
	public CoreGenericStructField field { get; private set; }
	internal CoreGenericStructFieldPlace (SourceSpan span, CorePlace aggregate, CoreGenericStructField field) {
		base (span, aggregate, ((CoreGenericStructApplicationType) aggregate.semantic_type).field_type (field));
		this.application = (CoreGenericStructApplicationType) aggregate.semantic_type;
		this.field = field;
	}

}

public enum GenericStructInstanceState {
	DECLARED, MATERIALIZING, COMPLETE
}

public class GenericStructRequester : Object {
	private WeakRef caller;
	public Object? identity { owned get { return caller.get (); } }
	private string identifier;
	public string label { get { return identifier; } }
	internal GenericStructRequester (Object identity, string label) {
		this.caller = WeakRef (identity);
		this.identifier = label;
	}

}

public class GenericStructInstance : Object {
	private WeakRef definition;
	private GenericArray<SemanticType> canonical_arguments = new GenericArray<SemanticType> ();
	private WeakRef structure;
	public CoreGenericStruct? origin_definition { owned get { return (CoreGenericStruct?) definition.get (); } }
	public CoreStruct? concrete_struct { owned get { return (CoreStruct?) structure.get (); } }
	public CoreGenericStructIdentity origin { get; private set; }
	public GenericArray<SemanticType> type_arguments { get; private set; }
	public int ordinal { get; private set; }
	public GenericStructInstanceState state { get; internal set; default = GenericStructInstanceState.DECLARED; }
	public uint requests { get; internal set; }
	public GenericArray<GenericStructRequester> requesters { get; private set; default = new GenericArray<GenericStructRequester> (); }
	private HashTable<CoreGenericStructFieldIdentity, CoreStructField> fields = new HashTable<CoreGenericStructFieldIdentity, CoreStructField> (direct_hash, direct_equal);
	internal GenericStructInstance (CoreGenericStruct origin, GenericArray<SemanticType> arguments, int ordinal) {
		this.definition = WeakRef (origin);
		this.origin = origin.identity;
		this.ordinal = ordinal;
		this.type_arguments = new GenericArray<SemanticType> ();
		foreach (var argument in arguments) {
			type_arguments.add (argument);
			canonical_arguments.add (argument);
		}
	}

	internal void attach(CoreStruct value) {
		structure = WeakRef (value);
	}

	internal void map_field(CoreGenericStructField origin, CoreStructField field) {
		assert (!fields.contains (origin.identity));
		fields.insert (origin.identity, field);
	}

	public CoreStructField? field_for(CoreGenericStructField origin) {
		return fields.lookup (origin.identity);
	}

	public bool has_canonical_key() {
		if (type_arguments.length != canonical_arguments.length) {
			return false;
		}
		for (int i = 0; i < type_arguments.length; i++) {
			if (type_arguments[i] != canonical_arguments[i]) {
				return false;
			}
		}
		return true;
	}

	public bool matches(CoreGenericStructIdentity origin, GenericArray<SemanticType> arguments) {
		if (!has_canonical_key () || this.origin != origin || arguments.length != type_arguments.length) {
			return false;
		}
		for (int i = 0; i < arguments.length; i++) {
			if (arguments[i] != type_arguments[i]) {
				return false;
			}
		}
		return true;
	}

	public string symbol_name() {
		return "astra.gen.struct.%d.%d".printf (origin.ordinal, ordinal);
	}

	public string display_name() {
		return application_name (origin, type_arguments);
	}

	internal static string application_name(CoreGenericStructIdentity origin, GenericArray<SemanticType> arguments) {
		var result = new StringBuilder (origin.name + "<");
		for (int i = 0; i < arguments.length; i++) {
			if (i != 0) {
				result.append (",");
			}
			result.append (arguments[i].display_name ());
		}
		result.append (">");
		return result.str;
	}

}
}
