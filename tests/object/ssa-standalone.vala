// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.ObjectSsa {
private SsaProgram sample(int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("object", "C"), 0, 1);
	var type = new ClassType ("C");
	var c = new SsaClass (span, span, "C", type);
	var field = new SsaStructField (span, span, "x", c, t.int_type, 0);
	c.fields.add (field);
	var contract = new ReceiverType (type);
	var receiver = new SsaReceiver (span, contract, 0);
	var method_blocks = new GenericArray<SsaBlock> ();
	var method_block = new SsaBlock (span, 0, 0);
	method_blocks.add (method_block);
	var loaded = new SsaLoadInstruction (span, new SsaIndirectFieldPlace (span, receiver, field), 1);
	method_block.instructions.add (loaded);
	method_block.complete (new SsaReturn (span, loaded.result));
	var method = new SsaMethod (span, span, "get", c, receiver, 0, 1, t.int_type, 1, new GenericArray<SsaFunctionParameter> (), method_blocks, method_block);
	c.methods.add (method);
	var blocks = new GenericArray<SsaBlock> ();
	var block = new SsaBlock (span, 0, 0);
	blocks.add (block);
	var storage = new SsaObjectStorage (span, c, variant == 1 ? 1 : 0, variant == 2 ? -1 : 0);
	var target = new SsaObjectFieldPlace (span, storage, field);
	var initialization = new SsaInitializeInstruction (span, target, new SsaIntegerConstant (span, t.int_type, AstraIntValue.from_int64 (42)));
	if (variant != 3) {
		block.instructions.add (initialization);
	}
	if (variant == 4) {
		block.instructions.add (initialization);
	}
	var reference = new SsaObjectReferenceInstruction (span, storage, 0);
	block.instructions.add (reference);
	if (variant == 3) {
		block.instructions.add (initialization);
	}
	var validation = new SsaObjectValidateInstruction (span, reference.result, variant == 5 ? (SemanticType) new ClassType ("Wrong") : contract, 1);
	block.instructions.add (validation);
	var field_validation = new SsaObjectValidateInstruction (span, reference.result, type, 2);
	block.instructions.add (field_validation);
	block.instructions.add (new SsaStoreInstruction (span, new SsaIndirectFieldPlace (span, variant == 6 ? reference.result : field_validation.result, field), new SsaIntegerConstant (span, t.int_type, AstraIntValue.from_int64 (42))));
	var call = new SsaCallInstruction (span, t.int_type, 3, method, new GenericArray<SsaValue> (), variant == 7 ? reference.result : validation.result);
	block.instructions.add (call);
	block.complete (new SsaReturn (span, call.result));
	var main = new SsaFunction (span, span, "main", t.int_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, block);
	if (variant != 8) {
		main.object_storage.add (storage);
	}
	if (variant == 9) {
		main.object_storage.add (storage);
	}
	var functions = new GenericArray<SsaFunction> ();
	functions.add (main);
	functions.add (method);
	var program = new SsaProgram (span, functions);
	program.classes.add (c);
	if (variant == 10) {
		program.classes.add (new SsaClass (span, span, "Empty", new ClassType ("Empty"), -1));
	}
	return program;
}

private void valid() {
	try {
		SsaProgram? p = sample ();
		SsaVerifier.verify (p);
		assert (p.functions[0].storage.length == 0 && p.functions[0].object_storage.length == 1);
		string dump = SsaDump.format (p);
		assert (dump.contains ("object-ref") && dump.contains ("object-validate") && dump.contains ("method-call"));
		var storage = WeakRef (p.functions[0].object_storage[0]);
		var declaration = WeakRef (p.classes[0]);
		p = null;
		assert (storage.get () == null && declaration.get () == null);
	} catch (SsaError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 10; variant++) {
		try {
			SsaVerifier.verify (sample (variant));
		} catch (SsaError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed object SSA variant %d", variant);
	}
}

private void identity() {
	foreach (var op in new BinaryOperator[] { BinaryOperator.EQUAL, BinaryOperator.NOT_EQUAL }) {
		for (int variant = 0; variant < 2; variant++) {
			try {
				var p = sample ();
				var t = new BuiltinTypes ();
				var span = p.span;
				var type = p.classes[0].semantic_type;
				var left = new SsaNullPointerConstant (span, type);
				var right = new SsaNullPointerConstant (span, variant == 1 ? new ClassType ("C") : type);
				var comparison = new SsaBinaryInstruction (span, t.bool_type, 0, op, left, right);
				var block = new SsaBlock (span, 0, 0);
				block.instructions.add (comparison);
				block.complete (new SsaReturn (span, comparison.result));
				var blocks = new GenericArray<SsaBlock> ();
				blocks.add (block);
				p.functions.add (new SsaFunction (span, span, "equal", t.bool_type, p.functions.length, new GenericArray<SsaFunctionParameter> (), blocks, block));
				SsaVerifier.verify (p);
				assert (variant == 0);
			} catch (SsaError error) {
				if (variant == 0) {
					GLib.error ("%s", error.message);
				}
			}
		}
	}
}

private void missing_storage_class() {
	try {
		var t = new BuiltinTypes ();
		var span = SourceSpan (new SourceFile.from_text ("object", "C"), 0, 1);
		SsaClass? declaration = new SsaClass (span, span, "C", new ClassType ("C"));
		var block = new SsaBlock (span, 0, 0);
		block.complete (new SsaReturn (span, null));
		var blocks = new GenericArray<SsaBlock> ();
		blocks.add (block);
		var function = new SsaFunction (span, span, "empty", t.void_type, 0, new GenericArray<SsaFunctionParameter> (), blocks, block);
		var storage = new SsaObjectStorage (span, declaration, 0, 0);
		function.object_storage.add (storage);
		declaration = null;
		assert (storage.object_class == null);
		var functions = new GenericArray<SsaFunction> ();
		functions.add (function);
		SsaVerifier.verify (new SsaProgram (span, functions));
	} catch (SsaError error) {
		assert (error.message.contains ("object storage requires exact class"));
		return;
	}
	GLib.error ("accepted object storage with no live declaring class");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/object/ssa/independent-storage-reference-guards-and-direct-method", valid);
	Test.add_func ("/object/ssa/malformed-initialization-storage-guard-and-call", malformed);
	Test.add_func ("/object/ssa/exact-class-null-identity-comparison", identity);
	Test.add_func ("/object/ssa/storage-requires-live-stage-class", missing_storage_class);
	return Test.run ();
}
}
