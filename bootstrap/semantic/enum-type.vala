// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;

namespace Astra.Semantic {
public enum EnumUse {
	COPY, MOVE, INSPECT
}

public class EnumType : SemanticType {
	public EnumIdentity identity { get; private set; }
	private WeakRef definition;
	private GenericArray<SemanticType> arguments = new GenericArray<SemanticType> ();
	private GenericArray<EnumType> applications = new GenericArray<EnumType> ();
	private bool[] array_elements;
	public EnumType? origin { owned get { return (EnumType?) definition.get (); } }
	public uint argument_count { get { return arguments.length; } }
	public SemanticType argument(uint ordinal) {
		return arguments[ordinal];
	}

	internal EnumType (string name, GenericArray<SemanticType>? parameters = null, bool[]? array_elements = null) {
		base (TypeKind.ENUM);
		identity = new EnumIdentity (name);
		definition = WeakRef (this);
		if (parameters != null) {
			foreach (var parameter in parameters) {
				arguments.add (parameter);
			}
		}
		this.array_elements = new bool[arguments.length];
		if (array_elements != null) {
			for (int i = 0; i < arguments.length; i++) {
				this.array_elements[i] = array_elements[i];
			}
		}
	}

	public bool require_array_element(uint ordinal) {
		if (array_elements[ordinal]) {
			return false;
		}
		array_elements[ordinal] = true;
		return true;
	}

	public bool requires_array_element(uint ordinal) {
		var origin = this.origin;
		return origin != null && origin.array_elements[ordinal];
	}

	public bool declares_copy(TypeParameterType parameter) {
		foreach (var argument in arguments) {
			if (argument == parameter) {
				return parameter.transport_mode == GenericTransportMode.PLAIN_COPY;
			}
		}
		return false;
	}

	public bool declares_element(TypeParameterType parameter) {
		for (uint i = 0; i < arguments.length; i++) {
			if (arguments[i] == parameter && requires_array_element (i)) {
				return declares_copy (parameter);
			}
		}
		return false;
	}

	private EnumType.applied (EnumType origin, GenericArray<SemanticType> arguments) {
		base (TypeKind.ENUM);
		definition = WeakRef (origin);
		var name = new StringBuilder (origin.identity.name + "<");
		for (int i = 0; i < arguments.length; i++) {
			this.arguments.add (arguments[i]);
			if (i != 0) {
				name.append (",");
			}
			name.append (arguments[i].display_name ());
		}
		name.append (">");
		identity = new EnumIdentity (name.str);
	}
	private bool matches(GenericArray<SemanticType> key) {
		if (key.length != arguments.length) {
			return false;
		}
		for (int i = 0; i < key.length; i++) {
			if (key[i] != arguments[i]) {
				return false;
			}
		}
		return true;
	}

	public EnumType application(GenericArray<SemanticType> key) {
		var origin = this.origin;
		assert (origin != null && key.length == origin.argument_count);
		if (origin.matches (key)) {
			return origin;
		}
		foreach (var prior in origin.applications) {
			if (prior.matches (key)) {
				return prior;
			}
		}
		var result = new EnumType.applied (origin, key);
		origin.applications.add (result);
		return result;
	}

	public override bool is_parameterized() {
		foreach (var argument in arguments) {
			if (argument.is_parameterized ()) {
				return true;
			}
		}
		return false;
	}

	internal override SemanticType substitute(TypeSubstitution substitution) {
		if (arguments.length == 0) {
			return this;
		}
		return application (substitution.apply_arguments (arguments));
	}

	public override string display_name() {
		return identity.name;
	}

}

}
