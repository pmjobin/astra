// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
// A declarative type expression. Parameter ordinals are lexical binders;
// names are resolved declaration identities, never specialization cache keys.
public enum GenericTypePatternKind {
	PARAMETER, METHOD_PARAMETER, NAMED, APPLICATION, OWNER_SLOTS, SLICE, POINTER, NONNULL
}

public class GenericTypePattern : Object {
	public GenericTypePatternKind kind { get; private set; }
	public int parameter { get; private set; default = -1; }
	public GenericValueMode value_mode { get; private set; default = GenericValueMode.VALUE; }
	private string identifier = "";
	public string name { get { return identifier; } }
	private GenericTypePattern[] children;
	public int argument_count { get { return children.length; } }
	public unowned GenericTypePattern argument(int ordinal) {
		return children[ordinal];
	}

	internal GenericTypePattern.bound (int ordinal, bool method = false) {
		kind = method ? GenericTypePatternKind.METHOD_PARAMETER : GenericTypePatternKind.PARAMETER;
		parameter = ordinal;
		children = {};
	}

	internal GenericTypePattern.named (string name) {
		kind = GenericTypePatternKind.NAMED;
		identifier = name;
		children = {};
	}

	internal GenericTypePattern.channel (GenericTypePattern underlying, GenericValueMode mode) {
		kind = underlying.kind;
		parameter = underlying.parameter;
		identifier = underlying.identifier;
		children = underlying.children.copy ();
		value_mode = mode;
	}

	internal GenericTypePattern.shaped (GenericTypePatternKind kind, GenericTypePattern[] arguments, string name = "") {
		this.kind = kind;
		identifier = name;
		children = arguments.copy ();
	}

	public bool valid(int parameters, int method_parameters = 0, int depth = 0) {
		if (depth >= 128 || parameters < 1 || method_parameters < 0) {
			return false;
		}
		if (kind == GenericTypePatternKind.PARAMETER || kind == GenericTypePatternKind.METHOD_PARAMETER) {
			return parameter >= 0 && parameter < (kind == GenericTypePatternKind.PARAMETER ? parameters : method_parameters) && name == "" && children.length == 0;
		}
		if (parameter != -1) {
			return false;
		}
		if (kind == GenericTypePatternKind.NAMED) {
			return name != "" && children.length == 0;
		}
		if (kind == GenericTypePatternKind.APPLICATION) {
			if (name == "" || children.length == 0) {
				return false;
			}
		} else if (kind < GenericTypePatternKind.OWNER_SLOTS || kind > GenericTypePatternKind.NONNULL || name != "" || children.length != 1) {
			return false;
		}
		foreach (var child in children) {
			if (!child.valid (parameters, method_parameters, depth + 1)) {
				return false;
			}
		}
		return true;
	}

	public bool parameterized() {
		if (kind == GenericTypePatternKind.PARAMETER || kind == GenericTypePatternKind.METHOD_PARAMETER) {
			return true;
		}
		foreach (var child in children) {
			if (child.parameterized ()) {
				return true;
			}
		}
		return false;
	}
}

public class GenericFieldPattern : Object {
	private string identifier;
	public string name { get { return identifier; } }
	public GenericTypePattern value_type { get; private set; }
	public bool owned_field { get; private set; }
	public bool private_field { get; private set; }
	public bool readonly_field { get; private set; }

	internal GenericFieldPattern (string name, GenericTypePattern type, bool owned_field, bool private_field, bool readonly_field) {
		identifier = name;
		this.value_type = type;
		this.owned_field = owned_field;
		this.private_field = private_field;
		this.readonly_field = readonly_field;
	}
}

public enum GenericMemberPatternKind {
	CONSTRUCTOR, DESTRUCTOR, METHOD, GETTER, SETTER
}
public enum GenericValueMode {
	VALUE, BORROWED, OWNED
}

public class GenericTypeConstraint : Object {
	public int parameter { get; private set; }
	public bool method_parameter { get; private set; }
	public GenericCapabilitySet capabilities { get; private set; }
	public bool exact_heap_class { get; private set; }
	internal GenericTypeConstraint (int parameter, bool method_parameter, GenericCapabilitySet capabilities, bool exact_heap_class = false) {
		this.parameter = parameter;
		this.method_parameter = method_parameter;
		this.capabilities = capabilities;
		this.exact_heap_class = exact_heap_class;
	}
	public bool valid(int class_parameters, int method_parameters) {
		if (parameter < 0 || parameter >= (method_parameter ? method_parameters : class_parameters)) {
			return false;
		}
		if (exact_heap_class) {
			return capabilities.length == 0;
		}
		if (capabilities.length == 0) {
			return false;
		}
		for (int c = 0; c < capabilities.length; c++) {
			var capability = capabilities.at (c);
			if (!capability.valid () || (capability == GenericCapabilityIdentity.OWNABLE && capabilities.length != 1)) {
				return false;
			}
			for (int prior = 0; prior < c; prior++) {
				if (capabilities.at (prior) == capability) {
					return false;
				}
			}
		}
		return true;
	}
}

public class GenericMemberPattern : Object {
	private string identifier;
	public string name { get { return identifier; } }
	public GenericMemberPatternKind kind { get; private set; }
	public int type_parameter_count { get; private set; }
	public GenericTypePattern result { get; private set; }
	public GenericValueMode result_mode { get; private set; }
	public GenericTypePattern? error { get; private set; }
	public bool async_member { get; private set; }
	public int dispatch { get; private set; }
	private GenericTypePattern[] parameters;
	private GenericArray<GenericValueMode> modes = new GenericArray<GenericValueMode> ();
	private GenericTypeConstraint[] constraints;
	public int constraint_count { get { return constraints.length; } }
	public unowned GenericTypeConstraint constraint(int index) {
		return constraints[index];
	}
	public int parameter_count { get { return parameters.length; } }
	public unowned GenericTypePattern parameter_type(int ordinal) {
		return parameters[ordinal];
	}
	public GenericValueMode parameter_mode(int ordinal) {
		return modes[ordinal];
	}

	internal GenericMemberPattern (string name, GenericMemberPatternKind kind, int type_parameter_count,
	                               GenericTypePattern result, GenericValueMode result_mode, GenericTypePattern[] parameters,
	                               GenericValueMode[]? modes, GenericTypePattern? error, bool async_member, int dispatch, GenericTypeConstraint[]? constraints = null) {
		identifier = name;
		this.kind = kind;
		this.type_parameter_count = type_parameter_count;
		this.result = result;
		this.result_mode = result_mode;
		this.parameters = parameters.copy ();
		if (modes != null) {
			foreach (var mode in modes) {
				this.modes.add (mode);
			}
		}
		this.error = error;
		this.async_member = async_member;
		this.dispatch = dispatch;
		this.constraints = constraints == null ? new GenericTypeConstraint[0] : constraints.copy ();
	}

	public bool valid(int class_parameters) {
		if (name == "" || type_parameter_count < 0 || parameters.length != modes.length || !result.valid (class_parameters, type_parameter_count)) {
			return false;
		}
		if (error != null && !error.valid (class_parameters, type_parameter_count)) {
			return false;
		}
		for (int c = 0; c < constraints.length; c++) {
			var constraint = constraints[c];
			if (!constraint.valid (class_parameters, type_parameter_count)) {
				return false;
			}
			for (int prior = 0; prior < c; prior++) {
				if (constraints[prior].parameter == constraint.parameter && constraints[prior].method_parameter == constraint.method_parameter) {
					return false;
				}
			}
		}
		foreach (var parameter in parameters) {
			if (!parameter.valid (class_parameters, type_parameter_count)) {
				return false;
			}
		}
		return true;
	}
}

public class GenericPropertyPattern : Object {
	private string identifier;
	public string name { get { return identifier; } }
	public GenericMemberPattern getter { get; private set; }
	public GenericMemberPattern? setter { get; private set; }
	public bool lazy_property { get; private set; }

	internal GenericPropertyPattern (string name, GenericMemberPattern getter, GenericMemberPattern? setter, bool lazy_property) {
		identifier = name;
		this.getter = getter;
		this.setter = setter;
		this.lazy_property = lazy_property;
	}
}

// Immutable declaration structure, with no syntax/body/stage backlinks.
public class GenericClassStructure : Object {
	public int parameter_count { get; private set; }
	private GenericFieldPattern[] fields;
	private GenericMemberPattern[] members;
	private GenericPropertyPattern[] properties;
	private GenericTypeConstraint[] constraints;
	public int constraint_count { get { return constraints.length; } }
	public unowned GenericTypeConstraint constraint(int index) {
		return constraints[index];
	}
	public int field_count { get { return fields.length; } }
	public int member_count { get { return members.length; } }
	public int property_count { get { return properties.length; } }
	public unowned GenericFieldPattern field(int ordinal) {
		return fields[ordinal];
	}
	public unowned GenericMemberPattern member(int ordinal) {
		return members[ordinal];
	}
	public unowned GenericPropertyPattern property(int ordinal) {
		return properties[ordinal];
	}
	public GenericMemberPattern? find_member(string name) {
		foreach (var member in members) {
			if (member.name == name) {
				return member;
			}
		}
		return null;
	}

	internal GenericClassStructure (int parameter_count, GenericFieldPattern[] fields,
	                                GenericMemberPattern[] members, GenericPropertyPattern[] properties, GenericTypeConstraint[]? constraints = null) {
		this.parameter_count = parameter_count;
		this.fields = fields.copy ();
		this.members = members.copy ();
		this.properties = properties.copy ();
		this.constraints = constraints == null ? new GenericTypeConstraint[0] : constraints.copy ();
	}

	public bool valid() {
		if (parameter_count < 1) {
			return false;
		}
		for (int c = 0; c < constraints.length; c++) {
			if (!constraints[c].valid (parameter_count, 0)) {
				return false;
			}
			for (int prior = 0; prior < c; prior++) {
				if (constraints[prior].parameter == constraints[c].parameter) {
					return false;
				}
			}
		}
		var names = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var field in fields) {
			if (field.name == "" || names.contains (field.name) || !field.value_type.valid (parameter_count)) {
				return false;
			}
			names.insert (field.name, true);
		}
		foreach (var member in members) {
			if (!member.valid (parameter_count) || names.contains (member.name)) {
				return false;
			}
			names.insert (member.name, true);
		}
		foreach (var property in properties) {
			if (property.name == "" || names.contains (property.name) || !property.getter.valid (parameter_count) || (property.setter != null && !property.setter.valid (parameter_count))) {
				return false;
			}
			names.insert (property.name, true);
		}
		return true;
	}
}
}
