// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.MethodCore {
private CoreProgram sample(int shape = 0, int variant = 0) throws CoreError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("method", "S"), 0, 1);
	var type = new StructType ("S");
	var structure = new CoreStruct (span, span, "S", type);
	var other_type = new StructType ("Other");
	var other = new CoreStruct (span, span, "Other", other_type, 1);
	var contract = new ReceiverType (variant == 2 ? other_type : type);
	var field = new CoreStructField (span, span, "x", structure, t.int_type, 0);
	structure.fields.add (field);
	var other_field = new CoreStructField (span, span, "x", other, t.int_type, 0);
	other.fields.add (other_field);
	var structures = new GenericArray<CoreStruct> ();
	structures.add (structure);
	structures.add (other);
	SemanticType argument_type = shape == 1 ? (SemanticType) t.u8_type : shape == 2 ? (SemanticType) t.f32_type : shape == 3 ? (SemanticType) t.vector_of (t.i16_type, 8) : shape == 4 ? (SemanticType) t.slice_of (t.int_type) : t.int_type;
	var pointer_contract = shape == 4 ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED;
	var parameters = new GenericArray<CoreParameter> ();
	var parameter = new CoreParameter (span, span, "n", variant == 15 ? (SemanticType) contract : argument_type, 0, pointer_contract);
	parameters.add (parameter);
	var receiver = new CoreReceiver (span, contract);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var locals = new GenericArray<CoreLocalPlace> ();
	var method = new CoreMethod (span, span, "f", variant == 1 ? other : structure, receiver, 0, 1, t.int_type, parameters, locals, body);
	CoreValue self = new CoreReceiverValue (span, variant == 3 ? new CoreReceiver (span, contract) : receiver);
	var place = new CoreIndirectFieldPlace (span, self, variant == 7 ? other_field : field);
	body.statements.add (new CoreStore (span, place, new CoreLoadValue (span, place)));
	var arguments = new GenericArray<CoreValue> ();
	if (variant != 11) {
		arguments.add (variant == 10 ? (CoreValue) new CoreBooleanValue (span, t.bool_type, BooleanLiteral.TRUE) : new CoreParameterValue (span, parameter));
	}
	CoreValue? invocation_receiver = variant == 4 ? null : variant == 5 ? (CoreValue) new CoreNullPointerValue (span, t.raw_pointer_type) : variant == 6 ? (CoreValue) new CoreReceiverValue (span, new CoreReceiver (span, new ReceiverType (other_type))) : self;
	body.statements.add (new CoreReturn (span, new CoreCallValue (span, variant == 12 ? t.bool_type : t.int_type, method, arguments, invocation_receiver)));
	var caller_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var caller_locals = new GenericArray<CoreLocalPlace> ();
	var local = new CoreLocalPlace (span, span, "c", type, 0, variant != 9);
	caller_locals.add (local);
	var direct = new CoreFieldPlace (span, local, field);
	caller_body.statements.add (new CoreInitialize (span, direct, new CoreIntegerValue (span, t.int_type, AstraIntValue.from_int64 (40))));
	var main = new CoreFunction (span, span, "main", t.int_type, new GenericArray<CoreParameter> (), caller_locals, caller_body);
	main.field_places.add (direct);
	if (shape == 0) {
		var args = new GenericArray<CoreValue> ();
		args.add (new CoreIntegerValue (span, t.int_type, AstraIntValue.from_int64 (2)));
		caller_body.statements.add (new CoreCallStatement (span, method, args, new CoreAddressOfValue (span, contract, local)));
	}
	caller_body.statements.add (new CoreReturn (span, new CoreLoadValue (span, direct)));
	if (variant == 13) {
		locals.add (new CoreLocalPlace (span, span, "copy", contract, 0));
	}
	if (variant != 14) {
		structure.methods.add (method);
	}
	if (variant == 8) {
		structure.methods.add (method);
	}
	var functions = new GenericArray<CoreFunction> ();
	functions.add (main);
	functions.add (method);
	var program = new CoreProgram (span, functions, null, null, structures);
	if (variant == 16) {
		program.c_exports.add (new CoreCExport (span, span, method, "external_method", ForeignAbi.C, 0));
	}
	return program;
}

private void model() {
	try {
		for (int shape = 0; shape < 5; shape++) {
			CoreProgram? program = sample (shape);
			CoreVerifier.verify (program);
			assert (program.structs[0].methods[0] == program.functions[1]);
			string dump = CoreDump.format (program);
			assert (dump.contains ("method-call") && dump.contains ("Receiver<S>"));
			var method = WeakRef (program.functions[1]);
			var receiver = WeakRef (((CoreMethod) program.functions[1]).receiver);
			program = null;
			assert (method.get () == null && receiver.get () == null);
		}
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}
private void malformed() {
	for (int variant = 1; variant <= 16; variant++) {
		try {
			CoreVerifier.verify (sample (0, variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed method variant %d", variant);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/method/core/independent-receiver-fields-calls-recursion-signatures-lifetime", model);
	Test.add_func ("/method/core/malformed-identity-receiver-storage-and-call-contracts", malformed);
	return Test.run ();
}
}
