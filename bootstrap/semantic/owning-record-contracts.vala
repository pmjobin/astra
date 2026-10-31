// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
namespace Astra.Semantic {
// Declared shape and argument snapshots contain no syntax, symbols, layout
// or stage nodes. Later verifiers supply their own field/cleanup inventory.
public class OwnedRecordDefinitionContract : Object {
	public RecordDefinitionIdentity nominal { get; private set; }
	private bool[] owners;
	private GenericFieldPattern[] fields;
	public int parameter_count { get { return owners.length; } }
	public int field_count { get { return fields.length; } }
	public bool owned_parameter(int position) {
		return owners[position];
	}
	public GenericFieldPattern field(int position) {
		return fields[position];
	}
	internal OwnedRecordDefinitionContract (RecordDefinitionIdentity nominal, bool[] owners, GenericFieldPattern[] fields) {
		this.nominal = nominal;
		this.owners = owners.copy ();
		this.fields = fields.copy ();
	}
}
public class OwnedRecordApplicationContract : Object {
	public OwnedRecordDefinitionContract definition { get; private set; }
	public TypeArgumentVector arguments { get; private set; }
	internal OwnedRecordApplicationContract (OwnedRecordDefinitionContract definition, GenericArray<SemanticType> arguments) {
		this.definition = definition;
		this.arguments = new TypeArgumentVector (arguments);
	}
	public bool valid(SemanticType type, GenericArray<SemanticType> stage_arguments, CopyabilityFields fields) {
		if (arguments.length != definition.parameter_count || stage_arguments.length != arguments.length || type.logical_identity != definition.nominal.application (arguments.copy_values ())) {
			return false;
		}
		for (int a = 0; a < arguments.length; a++) {
			var argument = stage_arguments[a];
			if (argument.is_parameterized () || argument.logical_identity != arguments.at (a).logical_identity) {
				return false;
			}
			if (definition.owned_parameter (a)) {
				if (!GenericCapabilityAuthority.satisfies (argument, GenericCapabilityIdentity.OWNABLE)) {
					return false;
				}
			} else if (!GenericArgumentTypes.supports (argument, fields)) {
				return false;
			}
		}
		return true;
	}
	public bool field(int position, string name, SemanticType type, bool owned, bool private_field, CopyabilityFields fields) {
		if (position < 0 || position >= definition.field_count) {
			return false;
		}
		var declared = definition.field (position);
		return name == declared.name && private_field == declared.private_field && owned == declared.owned_field && !declared.readonly_field && GenericClassDeclaredShape.arguments (declared.value_type, type, arguments, null, fields);
	}
}
}
