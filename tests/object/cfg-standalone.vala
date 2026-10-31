// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Cfg;

namespace Astra.Tests.ObjectCfg {
private CfgProgram sample(int variant = 0) throws CfgError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("object", "C"), 0, 1);
	var type = new ClassType ("C");
	var c = new CfgClass (span, span, "C", type);
	var other = new CfgClass (span, span, "D", new ClassType ("D"), 1);
	var field = new CfgStructField (span, span, "x", c, t.int_type, 0);
	c.fields.add (field);
	var other_field = new CfgStructField (span, span, "x", other, t.int_type, 0);
	other.fields.add (other_field);
	var contract = new ReceiverType (type);
	var receiver = new CfgReceiver (span, contract);
	var method_blocks = new GenericArray<CfgBlock> ();
	var method_block = new CfgBlock.reserve (span, 0);
	method_blocks.add (method_block);
	method_block.complete (span, new CfgReturn (span, new CfgLoadValue (span, new CfgIndirectFieldPlace (span, new CfgReceiverValue (span, receiver), field))));
	var method = new CfgMethod (span, span, "get", c, receiver, 0, 1, t.int_type, 1, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), method_blocks, method_block);
	c.methods.add (method);
	var locals = new GenericArray<CfgLocalPlace> ();
	var local = new CfgLocalPlace (span, span, "reference", type, 0);
	locals.add (local);
	var blocks = new GenericArray<CfgBlock> ();
	var block = new CfgBlock.reserve (span, 0);
	blocks.add (block);
	var storage = new CfgObjectStorage (span, c, variant == 1 ? 1 : 0, 0);
	var target = new CfgObjectFieldPlace (span, storage, variant == 2 ? other_field : field);
	var initialization = new CfgInitialize (span, target, new CfgIntegerValue (span, t.int_type, AstraIntValue.from_int64 (42)));
	if (variant != 3) {
		block.instructions.add (initialization);
	}
	if (variant == 4) {
		block.instructions.add (initialization);
	}
	var reference = new CfgEvaluatedValue (span, type);
	block.instructions.add (new CfgEvaluateInstruction (span, new CfgObjectReferenceValue (span, storage), reference));
	if (variant == 3) {
		block.instructions.add (initialization);
	}
	block.instructions.add (new CfgInitialize (span, local, reference));
	var validated = new CfgEvaluatedValue (span, contract);
	block.instructions.add (new CfgEvaluateInstruction (span, new CfgObjectValidateValue (span, new CfgLoadValue (span, local), variant == 5 ? (SemanticType) type : contract), validated));
	var field_reference = new CfgEvaluatedValue (span, type);
	block.instructions.add (new CfgEvaluateInstruction (span, variant == 6 ? (CfgValue) new CfgLoadValue (span, local) : new CfgObjectValidateValue (span, new CfgLoadValue (span, local), type), field_reference));
	block.instructions.add (new CfgStore (span, new CfgIndirectFieldPlace (span, field_reference, field), new CfgIntegerValue (span, t.int_type, AstraIntValue.from_int64 (42))));
	var result = new CfgCallResultValue (span, t.int_type);
	block.instructions.add (new CfgCallInstruction (span, method, new GenericArray<CfgValue> (), result, variant == 7 ? (CfgValue) reference : validated));
	block.complete (span, new CfgReturn (span, result));
	var main = new CfgFunction (span, span, "main", t.int_type, 0, new GenericArray<CfgParameter> (), locals, blocks, block);
	if (variant != 8) {
		main.object_storage.add (storage);
	}
	if (variant == 9) {
		main.object_storage.add (storage);
	}
	var functions = new GenericArray<CfgFunction> ();
	functions.add (main);
	functions.add (method);
	var program = new CfgProgram (span, functions);
	program.classes.add (c);
	program.classes.add (other);
	if (variant == 10) {
		program.classes.add (new CfgClass (span, span, "Empty", new ClassType ("Empty"), -1));
	}
	return program;
}

private void valid() {
	try {
		CfgProgram? p = sample ();
		CfgVerifier.verify (p);
		assert (CfgFlowChecker.check (p).diagnostic == null);
		assert (p.functions[0].locals[0].is_promotable () && p.functions[0].object_storage.length == 1);
		string dump = CfgDump.format (p);
		assert (dump.contains ("object-ref") && dump.contains ("object-validate") && dump.contains ("method-call"));
		var storage = WeakRef (p.functions[0].object_storage[0]);
		var declaration = WeakRef (p.classes[0]);
		p = null;
		assert (storage.get () == null && declaration.get () == null);
	} catch (CfgError error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 10; variant++) {
		try {
			CfgVerifier.verify (sample (variant));
		} catch (CfgError error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed object CFG variant %d", variant);
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
				var left = new CfgNullPointerValue (span, type);
				var right = new CfgNullPointerValue (span, variant == 1 ? new ClassType ("C") : type);
				var comparison = new CfgBinaryValue (span, t.bool_type, op, left, right);
				var block = new CfgBlock.reserve (span, 0);
				block.complete (span, new CfgReturn (span, comparison));
				var blocks = new GenericArray<CfgBlock> ();
				blocks.add (block);
				p.functions.add (new CfgFunction (span, span, "equal", t.bool_type, p.functions.length, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, block));
				CfgVerifier.verify (p);
				assert (variant == 0);
			} catch (CfgError error) {
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
		CfgClass? declaration = new CfgClass (span, span, "C", new ClassType ("C"));
		var block = new CfgBlock.reserve (span, 0);
		block.complete (span, new CfgReturn (span, null));
		var blocks = new GenericArray<CfgBlock> ();
		blocks.add (block);
		var function = new CfgFunction (span, span, "empty", t.void_type, 0, new GenericArray<CfgParameter> (), new GenericArray<CfgLocalPlace> (), blocks, block);
		var storage = new CfgObjectStorage (span, declaration, 0, 0);
		function.object_storage.add (storage);
		declaration = null;
		assert (storage.object_class == null);
		var functions = new GenericArray<CfgFunction> ();
		functions.add (function);
		CfgVerifier.verify (new CfgProgram (span, functions));
	} catch (CfgError error) {
		assert (error.message.contains ("object storage requires exact class"));
		return;
	}
	GLib.error ("accepted object storage with no live declaring class");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/object/cfg/independent-storage-null-guards-reference-and-method", valid);
	Test.add_func ("/object/cfg/malformed-storage-initialization-guard-and-method", malformed);
	Test.add_func ("/object/cfg/exact-class-null-identity-comparison", identity);
	Test.add_func ("/object/cfg/storage-requires-live-stage-class", missing_storage_class);
	return Test.run ();
}
}
