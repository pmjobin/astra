// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.MethodCfg {
private CfgProgram sample(int shape = 0, int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("method", "S"), 0, 1);
	var type = new StructType ("S");
	var structure = new CfgStruct (span, span, "S", type);
	var other_type = new StructType ("Other");
	var other = new CfgStruct (span, span, "Other", other_type, 1);
	var contract = new ReceiverType (variant == 2 ? other_type : type);
	var field = new CfgStructField (span, span, "x", structure, t.int_type, 0);
	structure.fields.add (field);
	var other_field = new CfgStructField (span, span, "x", other, t.int_type, 0);
	other.fields.add (other_field);
	var structures = new GenericArray<CfgStruct> ();
	structures.add (structure);
	structures.add (other);
	SemanticType argument_type = shape == 1 ? (SemanticType) t.u8_type : shape == 2 ? (SemanticType) t.f32_type : shape == 3 ? (SemanticType) t.vector_of (t.i16_type, 8) : shape == 4 ? (SemanticType) t.slice_of (t.int_type) : t.int_type;
	var pointer_contract = shape == 4 ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED;
	var parameters = new GenericArray<CfgParameter> ();
	var parameter = new CfgParameter (span, span, "n", variant == 15 ? (SemanticType) contract : argument_type, 0, pointer_contract);
	parameters.add (parameter);
	var receiver = new CfgReceiver (span, contract);
	var block = new CfgBlock.reserve (span, 0);
	var blocks = new GenericArray<CfgBlock> ();
	blocks.add (block);
	var locals = new GenericArray<CfgLocalPlace> ();
	var method = new CfgMethod (span, span, "f", variant == 1 ? other : structure, receiver, 0, 1, t.int_type, 1, parameters, locals, blocks, block);
	CfgValue self = new CfgReceiverValue (span, variant == 3 ? new CfgReceiver (span, contract) : receiver);
	var place = new CfgIndirectFieldPlace (span, self, variant == 7 ? other_field : field);
	block.instructions.add (new CfgStore (span, place, new CfgLoadValue (span, place)));
	var arguments = new GenericArray<CfgValue> ();
	if (variant != 11) {
		arguments.add (variant == 10 ? (CfgValue) new CfgBooleanValue (span, t.bool_type, BooleanLiteral.TRUE) : new CfgParameterValue (span, parameter));
	}
	CfgValue? invocation_receiver = variant == 4 ? null : variant == 5 ? (CfgValue) new CfgNullPointerValue (span, t.raw_pointer_type) : variant == 6 ? (CfgValue) new CfgReceiverValue (span, new CfgReceiver (span, new ReceiverType (other_type))) : self;
	var result = new CfgCallResultValue (span, variant == 12 ? t.bool_type : t.int_type);
	block.instructions.add (new CfgCallInstruction (span, method, arguments, result, invocation_receiver));
	block.complete (span, new CfgReturn (span, result));
	var caller_block = new CfgBlock.reserve (span, 0);
	var caller_blocks = new GenericArray<CfgBlock> ();
	caller_blocks.add (caller_block);
	var caller_locals = new GenericArray<CfgLocalPlace> ();
	var local = new CfgLocalPlace (span, span, "c", type, 0, variant != 9);
	caller_locals.add (local);
	var direct = new CfgFieldPlace (span, local, field);
	caller_block.instructions.add (new CfgInitialize (span, direct, new CfgIntegerValue (span, t.int_type, AstraIntValue.from_int64 (40))));
	var main = new CfgFunction (span, span, "main", t.int_type, 0, new GenericArray<CfgParameter> (), caller_locals, caller_blocks, caller_block);
	main.field_places.add (direct);
	if (shape == 0) {
		var args = new GenericArray<CfgValue> ();
		args.add (new CfgIntegerValue (span, t.int_type, AstraIntValue.from_int64 (2)));
		var address = new CfgEvaluatedValue (span, contract);
		caller_block.instructions.add (new CfgEvaluateInstruction (span, new CfgAddressOfValue (span, contract, local), address));
		caller_block.instructions.add (new CfgCallInstruction (span, method, args, new CfgCallResultValue (span, t.int_type), address));
	}
	caller_block.complete (span, new CfgReturn (span, new CfgLoadValue (span, direct)));
	if (variant == 13) {
		locals.add (new CfgLocalPlace (span, span, "copy", contract, 0));
	}
	if (variant != 14) {
		structure.methods.add (method);
	}
	if (variant == 8) {
		structure.methods.add (method);
	}
	var functions = new GenericArray<CfgFunction> ();
	functions.add (main);
	functions.add (method);
	var program = new CfgProgram (span, functions, null, null, structures);
	if (variant == 16) {
		program.c_exports.add (new CfgCExport (span, span, method, "external_method", ForeignAbi.C, 0));
	}
	return program;
}

private void model() {
	try {
		for (int shape = 0; shape < 5; shape++) {
			CfgProgram? program = sample (shape);
			CfgVerifier.verify (program);
			assert (program.structs[0].methods[0] == program.functions[1]);
			string dump = CfgDump.format (program);
			assert (dump.contains ("method-call") && dump.contains ("Receiver<S>"));
			var method = WeakRef (program.functions[1]);
			var receiver = WeakRef (((CfgMethod) program.functions[1]).receiver);
			program = null;
			assert (method.get () == null && receiver.get () == null);
		}
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 16; variant++) {
		try {
			CfgVerifier.verify (sample (0, variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed method variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/method/cfg/independent-receiver-fields-calls-recursion-signatures-lifetime", model);
	Test.add_func ("/method/cfg/malformed-identity-receiver-storage-and-call-contracts", malformed);
	return Test.run ();
}

}
