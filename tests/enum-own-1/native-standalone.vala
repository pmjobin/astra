// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
namespace Astra.Tests.OwningNative {
private void contracts() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("independent-owning-native", "x"), 0, 1);
		var identity = new EnumIdentity ("Owner<int>");
		var ready = new EnumVariantIdentity (identity, "Ready", 0);
		var field = new EnumFieldIdentity (ready, "data", 0);
		var fields = new GenericArray<NativeSumField> ();
		var buffer = new NativeSumField (field, null, null, null, new NativeBufferValuePlan (new NativeScalarAbiType (NativeScalarType.I32)));
		fields.add (buffer);
		var variants = new GenericArray<NativeSumVariant> ();
		variants.add (new NativeSumVariant (ready, fields));
		variants.add (new NativeSumVariant (new EnumVariantIdentity (identity, "Empty", 1), new GenericArray<NativeSumField> ()));
		var plan = new NativeSumPlan (identity, variants);
		var program = new NativeAbiProgram (span, NativeAbiVersion.OWNED_SUMS_V13, new GenericArray<NativeFunction> ());
		program.sum_values.add (plan);
		NativeAbiVerifier.verify (program);
		var parameters = new GenericArray<NativeParameter> ();
		var input = new NativeParameter.typed (span, span, "owner", 0, new NativeSumType (identity, NativeSumRole.OWNED_TRANSFER));
		parameters.add (input);
		var signature = new NativeSignature (NativeAbiVersion.OWNED_SUMS_V13, parameters, null);
		signature.sum_result = new NativeSumType (identity, NativeSumRole.OWNED_RESULT_STORAGE);
		NativeAbiVerifier.verify_detached_signature (signature, "owning signature");
		for (int mutation = 0; mutation < 5; mutation++) {
			if (mutation == 0) {
				fields[0] = new NativeSumField (field, null, null, null, new NativeBufferValuePlan (new NativeSumType (identity)));
			}
			if (mutation == 1) {
				fields[0] = new NativeSumField (new EnumFieldIdentity (ready, "data", 1), null, null, null, buffer.buffer);
			}
			if (mutation == 2) {
				parameters[0] = new NativeParameter.typed (span, span, "owner", 0, new NativeSumType (identity, NativeSumRole.OWNED_RESULT_STORAGE));
			}
			if (mutation == 3) {
				signature.sum_result = new NativeSumType (identity, NativeSumRole.OWNED_TRANSFER);
			}
			if (mutation == 4) {
				fields[0] = new NativeSumField (field, new NativeScalarAbiType (NativeScalarType.I32), null, null, buffer.buffer);
			}
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (program);
				NativeAbiVerifier.verify_detached_signature (signature, "mutated owner");
			} catch (NativeAbiError error) {
				Test.message ("owning native mutation %d: %s", mutation, error.message);
				rejected = true;
			}
			assert (rejected);
			fields[0] = buffer;
			parameters[0] = input;
			signature.sum_result = new NativeSumType (identity, NativeSumRole.OWNED_RESULT_STORAGE);
			NativeAbiVerifier.verify (program);
			NativeAbiVerifier.verify_detached_signature (signature, "restored owner");
		}
		var old = new NativeSignature (NativeAbiVersion.SUM_VALUES_V12, parameters, null);
		bool rejected = false;
		try {
			NativeAbiVerifier.verify_detached_signature (old, "wrong ABI");
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}
private void declaration_authority() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("independent-native-authority", "x"), 0, 1);
		var cache = new NativeLazyCache (span, "items", 0, 0, 0, 0, 0, new NativeScalarAbiType (NativeScalarType.PTR));
		cache.bind_owned_factory (1, 2);
		assert (cache.matches_factory ());
		bool twice = false;
		try {
			cache.bind_owned_factory (1, 2);
		} catch (NativeAbiError error) {
			twice = true;
		}
		assert (twice);
		cache.owned_class_ordinal = 3;
		assert (!cache.matches_factory ());
		cache.owned_class_ordinal = 2;
		assert (cache.matches_factory ());
		var signature = new NativeSignature (NativeAbiVersion.OWNED_SUMS_V13, new GenericArray<NativeParameter> (), null);
		signature.bind_struct_transport (0, null);
		NativeAbiVerifier.verify_detached_signature (signature, "empty record transport");
		bool rejected = false;
		try {
			signature.bind_struct_transport (0, null);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		var program = new NativeAbiProgram (span, NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeFunction> ());
		program.bind_private_accesses (new GenericArray<NativePrivateFieldAccess> ());
		NativeAbiVerifier.verify (program);
		rejected = false;
		try {
			program.bind_private_accesses (new GenericArray<NativePrivateFieldAccess> ());
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		string[] members = {
			"init", "reserve", "append", "count", "capacity"
		};
		ExactClassOperation[] operations = {
			ExactClassOperation.INITIALIZE, ExactClassOperation.RESERVE, ExactClassOperation.APPEND, ExactClassOperation.COUNT, ExactClassOperation.CAPACITY
		};
		var identity = new ExactClassDefinitionIdentity ("Bag", "items", members, operations);
		var parameter = new NativeParameter (span, span, "input", 0, NativeScalarType.PTR);
		var resource = new NativeScalarOwner ("R", "resource_release");
		var resource_parameter = new NativeParameter (span, span, "resource", 0, NativeScalarType.PTR);
		resource_parameter.bind_resource (resource, true);
		rejected = false;
		try {
			resource_parameter.bind_resource (resource, false);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		var invalid_resource = new NativeSignature (NativeAbiVersion.SCALAR_PTR_V1, new GenericArray<NativeParameter> (), new NativeResult (NativeScalarType.I32));
		invalid_resource.bind_resource_result (resource);
		rejected = false;
		try {
			NativeAbiVerifier.verify_detached_signature (invalid_resource, "invalid Resource result");
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		parameter.bind_generic_borrow (0, identity);
		rejected = false;
		try {
			parameter.bind_generic_borrow (1, identity);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		var owner = new NativeClassPlan (span, "Bag<Element>", 0, -1, -1, false, false, new GenericArray<NativeClassField> (), new GenericArray<int> ());
		var key = new NativeExactClassInstance (identity, 0, {0, 1, 2, 3, 4});
		owner.bind_generic (key);
		rejected = false;
		try {
			owner.bind_generic (key);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		program.classes.add (owner);
		rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("%s", error.message);
		}
		assert (rejected);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}
private void method_binding() {
	try {
		var span = SourceSpan (new SourceFile.from_text ("independent-method-binding", "x"), 0, 1);
		GenericClassValueRole[] no_parameters = null;
		bool[] no_owners = null;
		var init = new GenericClassMemberSignature (GenericClassValueRole.VOID, false, no_parameters, no_owners);
		var copied = new GenericClassMemberSignature (GenericClassValueRole.INT, false, no_parameters, no_owners, true);
		var definition = new ExactClassDefinitionIdentity ("Store", "entries", {"init"}, {ExactClassOperation.INITIALIZE}, {init}, {"constant"}, {copied});
		assert (definition.valid ());
		var signature = new NativeSignature (NativeAbiVersion.OWNER_SLOTS_V15, new GenericArray<NativeParameter> (), new NativeResult (NativeScalarType.I32), new NativeScalarAbiType (NativeScalarType.PTR));
		var function = new NativeFunction (span, span, "constant<int>", 0, signature, NativeLinkage.NATIVE_INTERNAL, 0, 0, true, NativeCallableKind.METHOD);
		var binding = new NativeGenericMethodInstance (definition, 0, 0, 0, new NativeCopyType ("int", new NativeScalarAbiType (NativeScalarType.I32)));
		function.bind_generic_method (binding);
		assert (function.generic_method_matches ());
		bool rejected = false;
		try {
			function.bind_generic_method (binding);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		function.generic_method_instance = new NativeGenericMethodInstance (definition, 0, 0, 0, new NativeCopyType ("int", new NativeScalarAbiType (NativeScalarType.B1)));
		assert (!function.generic_method_matches ());
		var functions = new GenericArray<NativeFunction> ();
		functions.add (function);
		var program = new NativeAbiProgram (span, NativeAbiVersion.OWNER_SLOTS_V15, functions);
		rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		function.generic_method_instance = null;
		rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		function.generic_method_instance = binding;
		assert (function.generic_method_matches ());
		var input = new NativeParameter (span, span, "values", 0, NativeScalarType.PTR);
		input.object_origin = new NativeObjectOriginPlan (0, "Store<int>", true);
		input.bind_generic_owner (0, definition);
		rejected = false;
		try {
			input.bind_generic_owner (0, definition);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		var inputs = new GenericArray<NativeParameter> ();
		inputs.add (input);
		var returned = new NativeSignature (NativeAbiVersion.SCALAR_PTR_V1, inputs, new NativeResult (NativeScalarType.PTR));
		returned.heap_result = new NativeObjectOriginPlan (0, "Store<int>", true);
		returned.bind_generic_owner_result (0, definition);
		rejected = false;
		try {
			returned.bind_generic_owner_result (0, definition);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		NativeAbiVerifier.verify_detached_signature (returned, "original generic owner channels");
		input.object_origin = null;
		rejected = false;
		try {
			NativeAbiVerifier.verify_detached_signature (returned, "erased generic owner");
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		input.object_origin = new NativeObjectOriginPlan (0, "Store<int>", true);
		returned.heap_result = new NativeObjectOriginPlan (1, "Store<bool>", true);
		rejected = false;
		try {
			NativeAbiVerifier.verify_detached_signature (returned, "wrong generic owner result");
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		returned.heap_result = new NativeObjectOriginPlan (0, "Store<int>", true);
		NativeAbiVerifier.verify_detached_signature (returned, "restored generic owner channels");
		// Restoring a method cannot manufacture the missing declaring Class.
		rejected = false;
		try {
			NativeAbiVerifier.verify (program);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}
private NativeAbiProgram slot_record_graph(bool cyclic) throws NativeAbiError {
	var span = SourceSpan (new SourceFile.from_text ("independent-slot-record-graph", "x"), 0, 1);
	var obligation = new NativeRecordResource.projected ({0}, cyclic ? "Root" : "Leaf", "", 0, cyclic ? 0 : 1);
	var owners = new GenericArray<NativeRecordResource> ();
	owners.add (obligation);
	var declared_owners = new GenericArray<NativeRecordResource> ();
	declared_owners.add (new NativeRecordResource.projected ({0}, cyclic ? "Root" : "Leaf", "", -1, cyclic ? 0 : 1));
	var declaration = new NativeRecordDeclarationPlan (0, "Packet", declared_owners);
	var leaves = new GenericArray<NativeStructLeafChannel> ();
	leaves.add (new NativeStructLeafChannel ("0", new NativeScalarAbiType (NativeScalarType.PTR)));
	var record = new NativeStructValuePlan (0, "Packet", leaves, NativeStructResultCarrier.SINGLE_LEAF, NativeStructValueMode.MOVE_VALUE, owners);
	record.declaration = declaration;
	var signature = new NativeSignature (NativeAbiVersion.SCALAR_PTR_V1, new GenericArray<NativeParameter> (), null, new NativeScalarAbiType (NativeScalarType.PTR));
	var destructor = new NativeFunction (span, span, "deinit", 0, signature, NativeLinkage.NATIVE_INTERNAL, 0, -1, true, NativeCallableKind.DESTRUCTOR);
	var functions = new GenericArray<NativeFunction> ();
	functions.add (destructor);
	var program = new NativeAbiProgram (span, NativeAbiVersion.OWNER_SLOTS_V15, functions);
	program.struct_values.add (record);
	program.record_declarations.add (declaration);
	var fields = new GenericArray<NativeClassField> ();
	fields.add (new NativeClassField (span, "entries", "Packet[slots]", 0, false, new NativeOwnerSlotsType (-1, "Packet", -1, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.I32, null, record), -1));
	program.classes.add (new NativeClassPlan (span, "Root", 0, -1, 0, false, false, fields, new GenericArray<int> ()));
	program.classes.add (new NativeClassPlan (span, "Leaf", 1, -1, -1, false, false, new GenericArray<NativeClassField> (), new GenericArray<int> ()));
	return program;
}
private void slot_record_cycles() {
	try {
		var original = slot_record_graph (false);
		NativeAbiVerifier.verify (original);
		var cyclic = slot_record_graph (true);
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (cyclic);
		} catch (NativeAbiError error) {
			rejected = error.message.contains ("cyclic native slot/record");
		}
		assert (rejected);
		NativeAbiVerifier.verify (original);
	} catch (NativeAbiError error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/generic-ownership/native/independent-slot-record-cycle", slot_record_cycles);
	Test.add_func ("/generic-method/native/independent-immutable-binding", method_binding);
	Test.add_func ("/enum-own/native/independent-buffer-role-version-mutations", contracts);
	Test.add_func ("/enum-own/native/immutable-declaration-authority", declaration_authority);
	return Test.run ();
}
}
