// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
public enum ExactClassOperation {
	INITIALIZE, RESERVE, APPEND, COUNT, CAPACITY, TAKE, REPLACE, BODY
}
public enum GenericClassValueRole {
	VOID, BOOL, INT, ARGUMENT, METHOD_ARGUMENT
}
// A declaration's type expressions, independent of syntax and IR bodies.
public class GenericClassMemberSignature : Object {
	public bool is_generic_method { get; private set; }
	public GenericClassValueRole result { get; private set; }
	public bool owned_result { get; private set; }
	private GenericClassValueRole[] parameters;
	private bool[] owned_parameters;
	public int parameter_count { get { return parameters.length; } }
	public GenericClassValueRole parameter(int index) {
		return parameters[index];
	}
	public bool owns_parameter(int index) {
		return owned_parameters[index];
	}
	internal GenericClassMemberSignature (GenericClassValueRole result, bool owned_result, GenericClassValueRole[] parameters, bool[] owned_parameters, bool generic_method = false) {
		this.is_generic_method = generic_method;
		this.result = result;
		this.owned_result = owned_result;
		this.parameters = parameters.copy ();
		this.owned_parameters = owned_parameters.copy ();
	}
	public bool valid() {
		if (result < GenericClassValueRole.VOID || result > GenericClassValueRole.METHOD_ARGUMENT || (result == GenericClassValueRole.METHOD_ARGUMENT && !is_generic_method) || owned_result != (result == GenericClassValueRole.ARGUMENT) || parameters.length != owned_parameters.length) {
			return false;
		}
		for (int p = 0; p < parameters.length; p++) {
			if (parameters[p] <= GenericClassValueRole.VOID || parameters[p] > GenericClassValueRole.METHOD_ARGUMENT || (parameters[p] == GenericClassValueRole.METHOD_ARGUMENT && !is_generic_method) || (owned_parameters[p] && parameters[p] != GenericClassValueRole.ARGUMENT)) {
				return false;
			}
		}
		return true;
	}
}

// Immutable definition identity, signatures and legacy operation recipes. No syntax,
// stage model, semantic type, storage, or runtime ownership backlink.
public class ExactClassDefinitionIdentity : Object {
	public GenericClassStructure? structure { get; private set; }
	public int parameter_count { get { return structure == null ? 1 : structure.parameter_count; } }
	private string identifier;
	private string field_identifier;
	public string name { get { return identifier; } }
	public string field_name { get { return field_identifier; } }
	private string[] members;
	private GenericArray<ExactClassOperation> operations = new GenericArray<ExactClassOperation> ();
	private GenericClassMemberSignature[]? signatures;
	private string[] generic_methods;
	private GenericClassMemberSignature[] generic_signatures;
	private string[] properties;
	private GenericClassValueRole[]? property_results;
	public int property_count { get { return properties.length; } }
	public string property_name(int property) {
		return properties[property];
	}
	public GenericClassValueRole property_result(int property) {
		return property_results[property];
	}
	public int generic_method_count { get { return generic_methods.length; } }
	public string generic_method_name(int member) {
		return generic_methods[member];
	}
	public GenericClassMemberSignature? generic_method_signature(int member) {
		return member < 0 || member >= generic_signatures.length ? null : generic_signatures[member];
	}
	public bool general_bodies { get { return structure != null || signatures != null; } }
	public GenericClassMemberSignature? signature(int member) {
		return signatures == null || member < 0 || member >= signatures.length ? null : signatures[member];
	}
	public int member_count { get { return members.length; } }
	internal ExactClassDefinitionIdentity (string name, string field_name, string[] members, ExactClassOperation[] operations, GenericClassMemberSignature[]? signatures = null, string[]? generic_methods = null, GenericClassMemberSignature[]? generic_signatures = null, string[]? properties = null, GenericClassValueRole[]? property_results = null) {
		this.identifier = name;
		this.field_identifier = field_name;
		this.members = members.copy ();
		foreach (var operation in operations) {
			this.operations.add (operation);
		}
		this.signatures = signatures == null ? null : signatures.copy ();
		this.generic_methods = generic_methods == null ? new string[0] : generic_methods.copy ();
		this.generic_signatures = generic_signatures == null ? new GenericClassMemberSignature[0] : generic_signatures.copy ();
		this.properties = properties == null ? new string[0] : properties.copy ();
		if (property_results != null) {
			this.property_results = property_results.copy ();
		}
	}
	internal ExactClassDefinitionIdentity.declared (string name, GenericClassStructure structure) {
		identifier = name;
		this.structure = structure;
		field_identifier = structure.field_count == 0 ? "" : structure.field (0).name;
		members = {};
		generic_methods = {};
		generic_signatures = {};
		properties = {};
		for (int m = 0; m < structure.member_count; m++) {
			var member = structure.member (m);
			if (member.kind == GenericMemberPatternKind.DESTRUCTOR) {
				continue;
			}
			if (member.type_parameter_count != 0) {
				generic_methods += member.name;
				continue;
			}
			members += member.name;
			operations.add (member.kind == GenericMemberPatternKind.CONSTRUCTOR ? ExactClassOperation.INITIALIZE : ExactClassOperation.BODY);
		}
		for (int p = 0; p < structure.property_count; p++) {
			properties += structure.property (p).name;
		}
	}
	public string member_name(int index) {
		return members[index];
	}
	public ExactClassOperation operation(int index) {
		return operations[index];
	}
	public bool valid() {
		if (structure != null) {
			return name != "" && structure.valid ();
		}
		if (properties.length != (property_results == null ? 0 : property_results.length) || (!general_bodies && properties.length != 0)) {
			return false;
		}
		for (int p = 0; p < properties.length; p++) {
			string property = properties[p];
			if (property == "" || property == field_name || property == "init" || property == "deinit" || (property_results[p] != GenericClassValueRole.INT && property_results[p] != GenericClassValueRole.BOOL)) {
				return false;
			}
			foreach (string member in members) {
				if (property == member) {
					return false;
				}
			}
			foreach (string member in generic_methods) {
				if (property == member) {
					return false;
				}
			}
			for (int prior = 0; prior < p; prior++) {
				if (property == properties[prior]) {
					return false;
				}
			}
		}
		if (generic_methods.length != generic_signatures.length || (!general_bodies && generic_methods.length != 0)) {
			return false;
		}
		for (int m = 0; m < generic_methods.length; m++) {
			if (generic_methods[m] == "" || generic_methods[m] == field_name || generic_methods[m] == "init" || generic_methods[m] == "deinit" || !generic_signatures[m].valid () || !generic_signatures[m].is_generic_method) {
				return false;
			}
			foreach (var name in members) {
				if (name == generic_methods[m]) {
					return false;
				}
			}
			for (int p = 0; p < m; p++) {
				if (generic_methods[p] == generic_methods[m]) {
					return false;
				}
			}
		}
		if (general_bodies) {
			if (name == "" || field_name == "" || members.length == 0 || members.length != operations.length || members.length != signatures.length) {
				return false;
			}
			int constructors = 0;
			for (int m = 0; m < members.length; m++) {
				if (members[m] == "" || members[m] == field_name || !signatures[m].valid () || signatures[m].is_generic_method) {
					return false;
				}
				for (int prior = 0; prior < m; prior++) {
					if (members[prior] == members[m]) {
						return false;
					}
				}
				if (operations[m] == ExactClassOperation.INITIALIZE) {
					if (members[m] != "init" || signatures[m].result != GenericClassValueRole.VOID) {
						return false;
					}
					constructors++;
				} else if (operations[m] != ExactClassOperation.BODY || members[m] == "init") {
					return false;
				}
			}
			return constructors == 1;
		}
		if (name == "" || field_name == "" || members.length < 5 || members.length > 7 || operations.length != members.length) {
			return false;
		}
		uint seen = 0;
		for (int i = 0; i < members.length; i++) {
			int op = (int) operations[i];
			if (op < 0 || op > 6 || (seen & (1u << op)) != 0 || members[i] == "" || members[i] == field_name || (op == 0) != (members[i] == "init")) {
				return false;
			}
			for (int j = 0; j < i; j++) {
				if (members[j] == members[i]) {
					return false;
				}
			}
			seen |= 1u << op;
		}
		return (seen & 31) == 31;
	}
}
}
