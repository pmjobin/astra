// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
// Pure type identity: no dependency on foreign metadata or Checked nodes.
namespace Astra.Semantic {
// A distinct linear handle. The carrier owns one exact independently heap
// allocated environment; copied function signatures never acquire that cost.
public class ClosureHandleType : HandleType, CallableSignature {
	private ResultOwnershipContract result_ownership;
	public ResultOwnershipContract result_contract { get { return result_ownership; } }
	public bool actor {
		get;
		private set;
	}
	public SemanticType? actor_message {
		get {
			return actor && parameter_types.length == 1 ? parameter_types[0] : null;
		}
	}
	public bool threaded {
		get;
		private set;
	}
	public ClassType environment_type {
		get;
		private set;
	}
	public ClassType? throws_type {
		get;
		private set;
	}
	public SemanticType result_type {
		get;
		private set;
	}
	private StructValueShape? result_shape;
	public StructValueShape? record_result { get { return result_shape; } }
	private GenericArray<SemanticType> declared_parameters;
	public GenericArray<SemanticType> parameter_types {
		get {
			return declared_parameters;
		}
	}
	private GenericArray<PointerParameterContract> parameter_contracts = new GenericArray<PointerParameterContract> ();
	public PointerParameterContract parameter_contract(int ordinal) {
		return parameter_contracts[ordinal];
	}

	public GenericArray<StructBoundaryGroup> record_parameters { get; private set; default = new GenericArray<StructBoundaryGroup> (); }
	internal void complete_records(CopyabilityFields fields) throws StructLeafError {
		if (parameter_contracts.length != parameter_types.length) {
			throw new StructLeafError.INVALID_FIELDS ("closure signature lost its complete parameter channel contracts");
		}
		if (!actor) {
			CallableRecordGroups.complete (this, record_parameters, fields);
			result_shape = CallableRecordGroups.complete_result (result_type, fields);
		}
	}

	public void verify_records(GenericArray<StructBoundaryGroup> groups, CopyabilityFields fields, int source_offset = 0, int physical_offset = 0) throws StructLeafError {
		if (parameter_contracts.length != parameter_types.length) {
			throw new StructLeafError.INVALID_FIELDS ("closure signature lost its complete parameter channel contracts");
		}
		CallableRecordGroups.verify (this, groups, fields, source_offset, physical_offset);
		CallableRecordGroups.verify_result (result_type, result_shape, fields);
	}

	public GenericArray<SemanticType> physical_parameters() {
		return CallableRecordGroups.physical_parameters (this, record_parameters);
	}

	public GenericArray<PointerParameterContract> physical_contracts() {
		return CallableRecordGroups.physical_contracts (this, record_parameters);
	}

	public bool has_owner_channels() {
		for (int p = 0; p < parameter_contracts.length; p++) {
			if (parameter_contracts[p] != PointerParameterContract.UNMANAGED) {
				return true;
			}
		}
		return false;
	}

	public override bool is_parameterized() {
		if (environment_type.is_parameterized () || result_type.is_parameterized ()) {
			return true;
		}
		foreach (var parameter in parameter_types) {
			if (parameter.is_parameterized ()) {
				return true;
			}
		}
		return false;
	}

	internal override SemanticType substitute(TypeSubstitution substitution) {
		return substitution.closure (this);
	}

	internal ClosureHandleType (ClassType environment, SemanticType result, GenericArray<SemanticType> parameters, ClassType? throws_type = null, bool threaded = false, bool actor = false, GenericArray<PointerParameterContract>? contracts = null, ResultOwnershipContract result_contract = ResultOwnershipContract.UNMANAGED) {
		base (actor ? "ActorSender<" + environment.display_name () + "," + (parameters.length == 1 ? parameters[0].display_name () : "invalid") + ">" : (threaded ? "Thread" : "") + signature_name (environment, result, parameters, throws_type, contracts, result_contract));
		result_ownership = result_contract;
		this.actor = actor;
		this.threaded = threaded;
		this.throws_type = throws_type;
		environment_type = environment;
		result_type = result;
		declared_parameters = parameters;
		for (int p = 0; p < parameters.length; p++) {
			parameter_contracts.add (contracts == null ? PointerParameterContract.UNMANAGED : contracts[p]);
		}
	}

	private static string signature_name(ClassType environment, SemanticType result, GenericArray<SemanticType> parameters, ClassType? throws_type, GenericArray<PointerParameterContract>? contracts, ResultOwnershipContract result_contract) {
		string name = (throws_type == null ? "Closure<" : "CheckedClosure<") + environment.display_name () + "," + (throws_type == null ? "" : throws_type.display_name () + ",") + (result_contract == ResultOwnershipContract.OWNED_TRANSFER ? "owned " : "") + result.display_name ();
		for (int p = 0; p < parameters.length; p++) {
			name += "," + (contracts != null && contracts[p] == PointerParameterContract.BORROWED_NOESCAPE ? "borrowed " : contracts != null && contracts[p] == PointerParameterContract.OWNED_TRANSFER ? "owned " : "") + parameters[p].display_name ();
		}
		return name + ">";
	}

	public static bool supports_environment(ClassType environment, bool threaded = false) {
		return !environment.is_interface && (!(environment is ExactGenericClassType) || !threaded && GenericClassTypes.general (environment));
	}

	public bool supported() {
		if (actor) {
			return !threaded && throws_type == null && environment_type.concurrency_policy_identity == 16 && !environment_type.is_interface && !(environment_type is ExactGenericClassType) && result_type.kind == TypeKind.INT && parameter_types.length == 1 && (FunctionValueType.scalar (parameter_types[0]) || parameter_types[0] is ClassType && !((ClassType) parameter_types[0]).is_interface && !(parameter_types[0] is ExactGenericClassType));
		}
		if (!supports_environment (environment_type, threaded) || !FunctionValueType.supported_result (result_type, result_contract) || threaded && (result_contract != ResultOwnershipContract.UNMANAGED || result_type.is_struct_storage ()) || parameter_types.length > 4) {
			return false;
		}
		if (parameter_contracts.length != parameter_types.length) {
			return false;
		}
		for (int p = 0; p < parameter_types.length; p++) {
			var parameter = parameter_types[p];
			if (FunctionValueType.scalar (parameter) || !threaded && parameter.is_struct_storage ()) {
				if (parameter_contract (p) != PointerParameterContract.UNMANAGED && !(!threaded && parameter.is_struct_storage () && parameter_contract (p) == PointerParameterContract.BORROWED_NOESCAPE)) {
					return false;
				}
			} else if (threaded || !(parameter_contract (p) == PointerParameterContract.BORROWED_NOESCAPE && (parameter is ClassType || parameter.get_type () == typeof (HandleType)) || parameter_contract (p) == PointerParameterContract.OWNED_TRANSFER && (parameter is ClassType || parameter.get_type () == typeof (HandleType)))) {
				return false;
			}
		}
		return true;
	}

}
}
