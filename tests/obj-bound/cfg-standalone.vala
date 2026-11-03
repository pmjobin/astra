// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.ObjectBoundCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("obj-bound", "c"), 0, 1);
	var type = new ClassType ("C");
	var c = new CfgClass (span, span, "C", type);
	var other = new CfgClass (span, span, "D", new ClassType ("D"), 1);
	var field = new CfgStructField (span, span, "x", c, t.int_type, 0);
	c.fields.add (field);
	var contract = variant == 1 ? PointerParameterContract.UNMANAGED : variant == 2 ? PointerParameterContract.OWNED_TRANSFER : PointerParameterContract.BORROWED_NOESCAPE;
	var parameter = new CfgParameter (span, span, "c", variant == 4 ? new ClassType ("C") : type, 0, contract);
	var parameters = new GenericArray<CfgParameter> ();
	parameters.add (parameter);
	var foreign = new CfgParameter (span, span, "c", type, 0, PointerParameterContract.BORROWED_NOESCAPE);
	var receiver_type = new ReceiverType (type);
	var receiver = new CfgReceiver (span, receiver_type);
	var method_block = new CfgBlock.reserve (span, 0);
	method_block.complete (span, new CfgReturn (span, new CfgLoadValue (span, new CfgIndirectFieldPlace (span, new CfgReceiverValue (span, receiver), field))));
	var method_blocks = new GenericArray<CfgBlock> ();
	method_blocks.add (method_block);
	var method = new CfgMethod (span, span, "get", c, receiver, 0, 1, t.int_type, 1, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), method_blocks, method_block);
	c.methods.add (method);
	var block = new CfgBlock.reserve (span, 0);
	var locals = new GenericArray<CfgLocalPlace> ();
	var local = new CfgLocalPlace (span, span, "copy", type, 0);
	locals.add (local);
	var input = new CfgParameterValue (span, variant == 7 ? foreign : parameter);
	block.instructions.add (new CfgInitialize (span, local, input));
	var valid_field = new CfgEvaluatedValue (span, type);
	block.instructions.add (new CfgEvaluateInstruction (span, new CfgObjectValidateValue (span, new CfgLoadValue (span, local), type), valid_field));
	block.instructions.add (new CfgStore (span, new CfgIndirectFieldPlace (span, variant == 8 ? (CfgValue) input : valid_field, field), new CfgIntegerValue (span, t.int_type, AstraIntValue.from_int64 (42))));
	var valid_receiver = new CfgEvaluatedValue (span, receiver_type);
	block.instructions.add (new CfgEvaluateInstruction (span, new CfgObjectValidateValue (span, input, receiver_type), valid_receiver));
	var result = new CfgCallResultValue (span, t.int_type);
	block.instructions.add (new CfgCallInstruction (span, method, new GenericArray<CfgValue> (), result, variant == 9 ? (CfgValue) input : valid_receiver));
	block.complete (span, new CfgReturn (span, result));
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var function = new CfgFunction (span, span, "f", variant == 3 ? (SemanticType) type : t.int_type, 0, parameters, locals, blocks, block);
	var arguments = new GenericArray<CfgValue> ();
	arguments.add (new CfgNullPointerValue (span, variant == 5 ? other.semantic_type : variant == 6 ? (SemanticType) t.raw_pointer_type : type));
	var caller_block = new CfgBlock.reserve (span, 0);
	var caller_result = new CfgCallResultValue (span, t.int_type);
	caller_block.instructions.add (new CfgCallInstruction (span, function, arguments, caller_result));
	caller_block.complete (span, new CfgReturn (span, caller_result));
	var caller_blocks = new GenericArray<CfgBlock> ();
	caller_blocks.add (caller_block);
	var caller = new CfgFunction (span, span, "g", t.int_type, 2, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), caller_blocks, caller_block);
	var functions = new GenericArray<CfgFunction> ();
	functions.add (function);
	functions.add (method);
	functions.add (caller);
	var program = new CfgProgram (span, functions);
	program.classes.add (c);
	program.classes.add (other);
	return program;
}

private void valid() {
	try {
		CfgProgram? program = sample ();
		CfgVerifier.verify (program);
		assert (program.functions[0].parameters.length == 1 && program.functions[0].parameters[0].semantic_type == program.classes[0].semantic_type);
		assert (program.functions[0].parameters[0].pointer_contract == PointerParameterContract.BORROWED_NOESCAPE && program.functions[0].object_storage.length == 0);
		assert (CfgDump.format (program).contains ("(contract borrowed-noescape)"));
		var witness = WeakRef (program.functions[0].parameters[0]);
		var declaration = WeakRef (program.classes[0]);
		program = null;
		assert (witness.get () == null && declaration.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 9; variant++) {
		try {
			CfgVerifier.verify (sample (variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed object boundary variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-bound/cfg/independent-parameter-null-field-method-and-stage-lifetime", valid);
	Test.add_func ("/obj-bound/cfg/malformed-contract-type-result-call-and-guard", malformed);
	return Test.run ();
}

}
