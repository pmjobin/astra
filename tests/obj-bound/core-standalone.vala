// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.ObjectBoundCore {
private CoreProgram sample(int variant = 0) throws CoreError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("obj-bound", "c"), 0, 1);
	var type = new ClassType ("C");
	var c = new CoreClass (span, span, "C", type);
	var other = new CoreClass (span, span, "D", new ClassType ("D"), 1);
	var field = new CoreStructField (span, span, "x", c, t.int_type, 0);
	c.fields.add (field);
	var contract = variant == 1 ? PointerParameterContract.UNMANAGED : variant == 2 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	var parameter = new CoreParameter (span, span, "c", variant == 4 ? new ClassType ("C") : type, 0, contract);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (parameter);
	var foreign = new CoreParameter (span, span, "c", type, 0, PointerParameterContract.BORROWED_NOESCAPE);
	var receiver_type = new ReceiverType (type);
	var receiver = new CoreReceiver (span, receiver_type);
	var method_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	method_body.statements.add (new CoreReturn (span, new CoreLoadValue (span, new CoreIndirectFieldPlace (span, new CoreReceiverValue (span, receiver), field))));
	var method = new CoreMethod (span, span, "get", c, receiver, 0, 1, t.int_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), method_body);
	c.methods.add (method);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var locals = new GenericArray<CoreLocalPlace> ();
	var local = new CoreLocalPlace (span, span, "copy", type, 0);
	locals.add (local);
	var input = new CoreParameterValue (span, variant == 7 ? foreign : parameter);
	body.statements.add (new CoreInitialize (span, local, input));
	body.statements.add (new CoreStore (span, new CoreIndirectFieldPlace (span, new CoreLoadValue (span, local), field), new CoreIntegerValue (span, t.int_type, AstraIntValue.from_int64 (42))));
	body.statements.add (new CoreReturn (span, new CoreCallValue (span, t.int_type, method, new GenericArray<CoreValue> (), new CoreObjectReceiverValue (span, input, receiver_type))));
	var function = new CoreFunction (span, span, "f", variant == 3 ? (SemanticType) type : t.int_type, parameters, locals, body);
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreNullPointerValue (span, variant == 5 ? other.semantic_type : variant == 6 ? (SemanticType) t.raw_pointer_type : type));
	var caller_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	caller_body.statements.add (new CoreReturn (span, new CoreCallValue (span, t.int_type, function, arguments)));
	var caller = new CoreFunction (span, span, "g", t.int_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), caller_body);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (function);
	functions.add (method);
	functions.add (caller);
	var program = new CoreProgram (span, functions);
	program.classes.add (c);
	program.classes.add (other);
	return program;
}

private void valid() {
	try {
		CoreProgram? program = sample ();
		CoreVerifier.verify (program);
		assert (program.functions[0].parameters.length == 1 && program.functions[0].parameters[0].semantic_type == program.classes[0].semantic_type);
		assert (program.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && program.functions[0].object_storage.length == 0);
		assert (CoreDump.format (program).contains ("(contract borrowed-noescape)"));
		var witness = WeakRef (program.functions[0].parameters[0]);
		var declaration = WeakRef (program.classes[0]);
		program = null;
		assert (witness.get () == null && declaration.get () == null);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 7; variant++) {
		try {
			CoreVerifier.verify (sample (variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed object boundary variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/core/independent-parameter-null-field-method-and-stage-lifetime", valid);
	Test.add_func ("/obj-bound/core/malformed-contract-type-result-call-and-guard", malformed);
	return Test.run ();
}

}
