// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.MethodSsa {
private SsaProgram sample(int shape = 0, int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("method", "S"), 0, 1);
	var type = new StructType ("S");
	var structure = new SsaStruct (span, span, "S", type);
	var other_type = new StructType ("Other");
	var other = new SsaStruct (span, span, "Other", other_type, 1);
	var contract = new ReceiverType (variant == 2 ? other_type : type);
	var field = new SsaStructField (span, span, "x", structure, t.int_type, 0);
	structure.fields.add (field);
	var other_field = new SsaStructField (span, span, "x", other, t.int_type, 0);
	other.fields.add (other_field);
	var structures = new GenericArray<SsaStruct> ();
	structures.add (structure);
	structures.add (other);
	SemanticType argument_type = shape == 1 ? (SemanticType) t.u8_type : shape == 2 ? (SemanticType) t.f32_type : shape == 3 ? (SemanticType) t.vector_of (t.i16_type, 8) : shape == 4 ? (SemanticType) t.slice_of (t.int_type) : t.int_type;
	var pointer_contract = shape == 4 ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED;
	var parameters = new GenericArray<SsaFunctionParameter> ();
	var parameter = new SsaFunctionParameter (span, span, "n", variant == 15 ? (SemanticType) contract : argument_type, 1, pointer_contract);
	parameters.add (parameter);
	var receiver = new SsaReceiver (span, contract, 0);
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var method = new SsaMethod (span, span, "f", variant == 1 ? other : structure, receiver, 0, 1, t.int_type, 1, parameters, blocks, block);
	SsaValue self = variant == 3 ? new SsaReceiver (span, contract, 0) : receiver;
	var place = new SsaIndirectFieldPlace (span, self, variant == 7 ? other_field : field);
	var load = new SsaLoadInstruction (span, place, 2);
	block.instructions.add (load);
	block.instructions.add (new SsaStoreInstruction (span, place, load.result));
	var arguments = new GenericArray<SsaValue> ();
	if (variant != 11) {
		arguments.add (variant == 10 ? (SsaValue) new SsaBooleanConstant (span, t.bool_type, BooleanLiteral.TRUE) : parameter);
	}
	SsaValue? invocation_receiver = variant == 4 ? null : variant == 5 ? (SsaValue) new SsaNullPointerConstant (span, t.raw_pointer_type) : variant == 6 ? (SsaValue) new SsaReceiver (span, new ReceiverType (other_type), 0) : self;
	var call = new SsaCallInstruction (span, variant == 12 ? t.bool_type : t.int_type, 3, method, arguments, invocation_receiver);
	block.instructions.add (call);
	block.complete (new SsaReturn (span, call.result));
	var caller_block = new SsaBlock (span, 0, 0);
	var caller_blocks = new GenericArray<SsaBlock> ();
	caller_blocks.add (caller_block);
	var main = new SsaFunction (span, span, "main", t.int_type, 0, new GenericArray<SsaFunctionParameter> (), caller_blocks, caller_block);
	var storage = new SsaAddressableLocal (span, span, "c", type, 0, 0, structure);
	if (variant != 9) {
		main.storage.add (storage);
	}
	var direct = new SsaDirectFieldPlace (span, storage, field);
	caller_block.instructions.add (new SsaInitializeInstruction (span, direct, new SsaIntegerConstant (span, t.int_type, AstraIntValue.from_int64 (40))));
	if (shape == 0) {
		var args = new GenericArray<SsaValue> ();
		args.add (new SsaIntegerConstant (span, t.int_type, AstraIntValue.from_int64 (2)));
		var address = new SsaAddressOfInstruction (span, contract, 0, storage);
		caller_block.instructions.add (address);
		caller_block.instructions.add (new SsaCallInstruction (span, t.int_type, 1, method, args, address.result));
	}
	var observed = new SsaLoadInstruction (span, direct, 2);
	caller_block.instructions.add (observed);
	caller_block.complete (new SsaReturn (span, variant == 13 ? (SsaValue) receiver : observed.result));
	if (variant != 14) {
		structure.methods.add (method);
	}
	if (variant == 8) {
		structure.methods.add (method);
	}
	var functions = new GenericArray<SsaFunction> ();
	functions.add (main);
	functions.add (method);
	var program = new SsaProgram (span, functions, null, null, structures);
	if (variant == 16) {
		program.c_exports.add (new SsaCExport (span, span, method, "external_method", ForeignAbi.C, 0));
	}
	return program;
}

private void model() {
	try {
		for (int shape = 0; shape < 5; shape++) {
			SsaProgram? program = sample (shape);
			SsaVerifier.verify (program);
			assert (program.structs[0].methods[0] == program.functions[1]);
			string dump = SsaDump.format (program);
			assert (dump.contains ("method-call") && dump.contains ("Receiver<S>"));
			var method = WeakRef (program.functions[1]);
			var receiver = WeakRef (((SsaMethod) program.functions[1]).receiver);
			program = null;
			assert (method.get () == null && receiver.get () == null);
		}
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 16; variant++) {
		try {
			SsaVerifier.verify (sample (0, variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed method variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/method/ssa/independent-receiver-fields-calls-recursion-signatures-lifetime", model);
	Test.add_func ("/method/ssa/malformed-identity-receiver-storage-and-call-contracts", malformed);
	return Test.run ();
}

}
