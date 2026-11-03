// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.ObjectBoundSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("obj-bound", "c"), 0, 1);
	var type = new ClassType ("C");
	var c = new SsaClass (span, span, "C", type);
	var other = new SsaClass (span, span, "D", new ClassType ("D"), 1);
	var field = new SsaStructField (span, span, "x", c, t.int_type, 0);
	c.fields.add (field);
	var contract = variant == 1 ? PointerParameterContract.UNMANAGED : variant == 2 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	var parameter = new SsaFunctionParameter (span, span, "c", variant == 4 ? new ClassType ("C") : type, 0, contract);
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (parameter);
	var foreign = new SsaFunctionParameter (span, span, "c", type, 0, PointerParameterContract.BORROWED_NOESCAPE);
	var receiver_type = new ReceiverType (type);
	var receiver = new SsaReceiver (span, receiver_type, 0);
	var method_block = new SsaBlock (span, 0, 0);
	var load = new SsaLoadInstruction (span, new SsaIndirectFieldPlace (span, receiver, field), 1);
	method_block.instructions.add (load);
	method_block.complete (new SsaReturn (span, load.result));
	var method_blocks = new GenericArray<SsaBlock> ();
	method_blocks.add (method_block);
	var method = new SsaMethod (span, span, "get", c, receiver, 0, 1, t.int_type, 1, new GenericArray<SsaFunctionParameter> (), method_blocks, method_block);
	c.methods.add (method);
	var block = new SsaBlock (span, 0, 0);
	SsaValue input = variant == 7 ? foreign : parameter;
	var valid_field = new SsaObjectValidateInstruction (span, input, type, 1);
	block.instructions.add (valid_field);
	block.instructions.add (new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, variant == 8 ? input : valid_field.result, field), new SsaIntegerConstant (span, t.int_type, AstraIntValue.from_int64 (42))));
	var valid_receiver = new SsaObjectValidateInstruction (span, input, receiver_type, 2);
	block.instructions.add (valid_receiver);
	var call = new SsaCallInstruction (span, t.int_type, 3, method, new GenericArray<SsaValue> (), variant == 9 ? input : valid_receiver.result);
	block.instructions.add (call);
	block.complete (new SsaReturn (span, call.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var function = new SsaFunction (span, span, "f", variant == 3 ? (SemanticType) type : t.int_type, 0, parameters, blocks, block);
	var arguments = new GenericArray<SsaValue> ();
	arguments.add (new SsaNullPointerConstant (span, variant == 5 ? other.semantic_type : variant == 6 ? (SemanticType) t.raw_pointer_type : type));
	var caller_block = new SsaBlock (span, 0, 0);
	var caller_call = new SsaCallInstruction (span, t.int_type, 0, function, arguments);
	caller_block.instructions.add (caller_call);
	caller_block.complete (new SsaReturn (span, caller_call.result));
	var caller_blocks = new GenericArray<SsaBlock> ();
	caller_blocks.add (caller_block);
	var caller = new SsaFunction (span, span, "g", t.int_type, 2, new GenericArray<SsaFunctionParameter> (), caller_blocks, caller_block);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	functions.add (method);
	functions.add (caller);
	var program = new SsaProgram (span, functions);
	program.classes.add (c);
	program.classes.add (other);
	return program;
}

private void valid() {
	try {
		SsaProgram? program = sample ();
		SsaVerifier.verify (program);
		assert (program.functions[0].parameters.length == 1 && program.functions[0].parameters[0].semantic_type == program.classes[0].semantic_type);
		assert (program.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && program.functions[0].object_storage.length == 0);
		assert (SsaDump.format (program).contains ("(contract borrowed-noescape)"));
		var witness = WeakRef (program.functions[0].parameters[0]);
		var declaration = WeakRef (program.classes[0]);
		program = null;
		assert (witness.get () == null && declaration.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 9; variant++) {
		try {
			SsaVerifier.verify (sample (variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed object boundary variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/ssa/independent-parameter-null-field-method-and-stage-lifetime", valid);
	Test.add_func ("/obj-bound/ssa/malformed-contract-type-result-call-and-guard", malformed);
	return Test.run ();
}

}
