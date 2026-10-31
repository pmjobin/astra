// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.GenericMember {
private CheckedProgram check() throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	foreach (string path in new string[] { "examples/generic-diagnostic-bags/main.astra", "examples/generic-diagnostic-bags/model.astra", "lib/astra/collections/bag.astra", "lib/astra/text/utf8-message.astra", "lib/astra/base/errors.astra", "lib/astra/hosted/text.astra" }) {
		string text;
		FileUtils.get_contents (path, out text);
		files.add (new SourceFile.from_text (path, text));
	}
	var parsed = SyntaxProgram.parse (new SourceSet (files));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze_program (parsed.program);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private CoreProgram core() throws GLib.Error {
	var p = CoreGenericMonomorphizer.build (CoreBuilder.build (check ()));
	CoreVerifier.verify_concrete (p);
	return p;
}
private CfgProgram cfg() throws GLib.Error {
	return CfgBuilder.build (core ());
}
private SsaProgram ssa() throws GLib.Error {
	return SsaBuilder.build (cfg ());
}
private CoreClass core_bag(CoreProgram p, string argument) {
	foreach (var c in p.classes) {
		if (c.generic_instance != null && c.generic_instance.argument.display_name () == argument) {
			return c;
		}
	}
	assert_not_reached ();
}
private CfgClass cfg_bag(CfgProgram p, string argument) {
	foreach (var c in p.classes) {
		if (c.generic_instance != null && c.generic_instance.argument.display_name () == argument) {
			return c;
		}
	}
	assert_not_reached ();
}
private SsaClass ssa_bag(SsaProgram p, string argument) {
	foreach (var c in p.classes) {
		if (c.generic_instance != null && c.generic_instance.argument.display_name () == argument) {
			return c;
		}
	}
	assert_not_reached ();
}
private void core_reject(CoreProgram p) {
	bool failed = false;
	try {
		CoreVerifier.verify_concrete (p);
	} catch (CoreError e) {
		Test.message ("%s", e.message);
		failed = true;
	}
	assert (failed);
}
private void cfg_reject(CfgProgram p, string diagnostic = "") {
	bool failed = false;
	try {
		CfgVerifier.verify (p);
	} catch (CfgError e) {
		Test.message ("%s", e.message);
		failed = e.message.contains (diagnostic);
	}
	assert (failed);
}
private void ssa_reject(SsaProgram p, string diagnostic = "") {
	bool failed = false;
	try {
		SsaVerifier.verify (p);
	} catch (SsaError e) {
		Test.message ("%s", e.message);
		failed = e.message.contains (diagnostic);
	}
	assert (failed);
}
private void native_reject(NativeAbiProgram p) {
	bool failed = false;
	try {
		NativeAbiVerifier.verify (p);
	} catch (NativeAbiError e) {
		Test.message ("%s", e.message);
		failed = true;
	}
	assert (failed);
}
private void llvm_reject(LlvmModuleArtifact p) {
	bool failed = false;
	try {
		p.verify ();
	} catch (LlvmError e) {
		Test.message ("%s", e.message);
		failed = true;
	}
	assert (failed);
}

private void independent() {
	try {
		CheckedProgram? checked = check ();
		ClassSymbol? a = null;
		ClassSymbol? b = null;
		foreach (var c in checked.classes) {
			if (c.generic_instance == null) {
				continue;
			}
			if (a == null) {
				a = c;
			} else {
				assert (b == null);
				b = c;
			}
		}
		assert (a != null && b != null && a.semantic_type != b.semantic_type && a.generic_instance.definition == b.generic_instance.definition && a.generic_instance.argument != b.generic_instance.argument);
		var old = WeakRef (a);
		a = null;
		b = null;
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		assert (old.get () == null);
		CoreVerifier.verify (c);
		CoreProgram? concrete = CoreGenericMonomorphizer.build (c);
		c = null;
		old = WeakRef (core_bag (concrete, "Diagnostic"));
		CfgProgram? g = CfgBuilder.build (concrete);
		concrete = null;
		assert (old.get () == null);
		CfgVerifier.verify (g);
		old = WeakRef (cfg_bag (g, "Diagnostic"));
		SsaProgram? s = SsaBuilder.build (g);
		g = null;
		assert (old.get () == null);
		SsaVerifier.verify (s);
		old = WeakRef (ssa_bag (s, "Diagnostic"));
		var n = NativeAbiBuilder.build (s);
		CAbiProgram? cabi = CAbiBuilder.build (s, n);
		var artifact = LlvmLowering.lower (s, n, cabi);
		cabi = null;
		s = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (n);
		artifact.verify ();
		assert (n.abi_version == NativeAbiVersion.OWNER_SLOTS_V15);
		int instances = 0;
		foreach (var p in n.classes) {
			if (p.generic_instance != null) {
				instances++;
			}
		}
		assert (instances == 2);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void checked_mutations() {
	try {
		var p = check ();
		ClassSymbol? a = null;
		ClassSymbol? b = null;
		foreach (var c in p.classes) {
			if (c.generic_instance != null) {
				if (a == null) {
					a = c;
				} else {
					b = c;
				}
			}
		}
		var saved = a.generic_instance;
		a.generic_instance = b.generic_instance.copy ();
		bool failed = false;
		try {
			CoreBuilder.build (p);
		} catch (CoreError e) {
			Test.message ("%s", e.message);
			failed = true;
		}
		assert (failed);
		a.generic_instance = saved;
		CoreVerifier.verify (CoreBuilder.build (p));
		var definition = p.generic_classes[0];
		p.generic_classes.remove_index (0);
		failed = false;
		try {
			CoreBuilder.build (p);
		} catch (CoreError e) {
			Test.message ("%s", e.message);
			failed = true;
		}
		assert (failed);
		p.generic_classes.add (definition);
		CoreVerifier.verify (CoreBuilder.build (p));
		var field = a.fields[0];
		a.fields[0] = new StructFieldSymbol (field.span, field.name_span, a, b.fields[0].semantic_type, 0);
		failed = false;
		try {
			CoreBuilder.build (p);
		} catch (CoreError e) {
			Test.message ("%s", e.message);
			failed = true;
		}
		assert (failed);
		a.fields[0] = field;
		CoreVerifier.verify (CoreBuilder.build (p));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void core_mutations() {
	try {
		var p = core ();
		var a = core_bag (p, "Diagnostic");
		var b = core_bag (p, "Utf8Message");
		var key = a.generic_instance;
		a.generic_instance = b.generic_instance.copy ();
		core_reject (p);
		a.generic_instance = key;
		CoreVerifier.verify_concrete (p);
		var type = a.fields[0].semantic_type;
		a.fields[0].semantic_type = b.fields[0].semantic_type;
		core_reject (p);
		a.fields[0].semantic_type = type;
		CoreVerifier.verify_concrete (p);
		var cleanup = a.fields[0].slots_cleanup;
		a.fields[0].slots_cleanup = b.fields[0].slots_cleanup;
		core_reject (p);
		a.fields[0].slots_cleanup = cleanup;
		CoreVerifier.verify_concrete (p);
		var first = a.constructor.body.statements[0];
		a.constructor.body.statements.remove_index (0);
		core_reject (p);
		a.constructor.body.statements.add (first);
		CoreVerifier.verify_concrete (p);
		var count = a.methods[2];
		var body = count.body.statements[0];
		count.body.statements[0] = b.methods[2].body.statements[0];
		core_reject (p);
		count.body.statements[0] = body;
		CoreVerifier.verify_concrete (p);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void cfg_mutations() {
	try {
		var p = cfg ();
		var a = cfg_bag (p, "Diagnostic");
		var b = cfg_bag (p, "Utf8Message");
		var key = a.generic_instance;
		a.generic_instance = b.generic_instance.copy ();
		cfg_reject (p);
		a.generic_instance = key;
		CfgVerifier.verify (p);
		var cleanup = a.fields[0].slots_cleanup;
		a.fields[0].slots_cleanup = b.fields[0].slots_cleanup;
		cfg_reject (p);
		a.fields[0].slots_cleanup = cleanup;
		CfgVerifier.verify (p);
		var count = a.methods[2];
		var saved = count.entry.instructions[0];
		var query = (CfgEvaluateInstruction) saved;
		var value = (CfgSlotsValue) query.value;
		count.entry.instructions[0] = new CfgEvaluateInstruction (query.span, new CfgSlotsValue (value.span, value.semantic_type, value.store, OwnerSlotsAction.CAPACITY, null), query.result);
		CfgVerifier.verify (p);
		count.entry.instructions[0] = saved;
		CfgVerifier.verify (p);
		count.entry.instructions[0] = new CfgEvaluateInstruction (query.span, new CfgSlotsValue (value.span, a.methods[0].return_type, value.store, OwnerSlotsAction.CAPACITY, null), query.result);
		cfg_reject (p);
		count.entry.instructions[0] = saved;
		CfgVerifier.verify (p);
		var drop = a.destructor.entry.instructions[0];
		a.destructor.entry.instructions.remove_index (0);
		cfg_reject (p);
		a.destructor.entry.instructions.add (drop);
		CfgVerifier.verify (p);
		CfgFunction? inspect = null;
		foreach (var f in p.functions) {
			if (f.name == "inspect_diagnostic") {
				inspect = f;
			}
		}
		assert (inspect != null);
		CfgSlotsBorrow? borrow = null;
		int position = -1;
		for (int i = 0; i < inspect.entry.instructions.length; i++) {
			if (inspect.entry.instructions[i] is CfgSlotsBorrow) {
				borrow = (CfgSlotsBorrow) inspect.entry.instructions[i];
				position = i;
			}
		}
		assert (borrow != null);
		var loan = borrow.result;
		var request = new CfgIntegerValue.typed (loan.span, loan.index.semantic_type, AstraIntegerValue.from_int64 ((IntegerType) loan.index.semantic_type, 3));
		var mutation = new CfgSlotsValue (loan.span, a.methods[0].return_type, loan.store, OwnerSlotsAction.RESERVE, request);
		inspect.entry.instructions.insert (position + 1, new CfgEvaluateInstruction (loan.span, mutation, new CfgEvaluatedValue (loan.span, mutation.semantic_type)));
		cfg_reject (p, "crosses indexed loan");
		inspect.entry.instructions.remove_index (position + 1);
		CfgVerifier.verify (p);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void ssa_mutations() {
	try {
		var p = ssa ();
		var a = ssa_bag (p, "Diagnostic");
		var b = ssa_bag (p, "Utf8Message");
		var key = a.generic_instance;
		a.generic_instance = b.generic_instance.copy ();
		ssa_reject (p);
		a.generic_instance = key;
		SsaVerifier.verify (p);
		var cleanup = a.fields[0].slots_cleanup;
		a.fields[0].slots_cleanup = b.fields[0].slots_cleanup;
		ssa_reject (p);
		a.fields[0].slots_cleanup = cleanup;
		SsaVerifier.verify (p);
		var count = a.methods[2];
		var query = (SsaSlotsValueInstruction) count.entry.instructions[0];
		count.entry.instructions[0] = new SsaSlotsValueInstruction (query.span, query.result.semantic_type, query.result.ordinal, query.store, OwnerSlotsAction.CAPACITY);
		ssa_reject (p);
		count.entry.instructions[0] = query;
		SsaVerifier.verify (p);
		foreach (var bag in new SsaClass[] { a, b }) {
			var append = bag.methods[1];
			var disarm = append.entry.instructions[2];
			append.entry.instructions.remove_index (2);
			ssa_reject (p);
			append.entry.instructions.insert (2, disarm);
			SsaVerifier.verify (p);
		}
		SsaFunction? inspect = null;
		foreach (var f in p.functions) {
			if (f.name == "inspect_diagnostic") {
				inspect = f;
			}
		}
		assert (inspect != null);
		SsaSlotsValueInstruction? loan = null;
		int position = -1;
		int next = 0;
		for (int i = 0; i < inspect.entry.instructions.length; i++) {
			var instruction = inspect.entry.instructions[i];
			if (instruction.result != null) {
				next = int.max (next, instruction.result.ordinal + 1);
			}
			if (instruction is SsaSlotsValueInstruction && ((SsaSlotsValueInstruction) instruction).action == OwnerSlotsAction.BORROW) {
				loan = (SsaSlotsValueInstruction) instruction;
				position = i;
			}
		}
		assert (loan != null);
		var request = new SsaIntegerConstant.typed (loan.span, loan.operand.semantic_type, AstraIntegerValue.from_int64 ((IntegerType) loan.operand.semantic_type, 3));
		inspect.entry.instructions.insert (position + 1, new SsaSlotsValueInstruction (loan.span, a.methods[0].return_type, next, loan.store, OwnerSlotsAction.RESERVE, request));
		ssa_reject (p, "crosses indexed loan");
		inspect.entry.instructions.remove_index (position + 1);
		SsaVerifier.verify (p);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void native_mutations() {
	try {
		var s = ssa ();
		var p = NativeAbiBuilder.build (s);
		var a = p.classes[ssa_bag (s, "Diagnostic").ordinal];
		var b = p.classes[ssa_bag (s, "Utf8Message").ordinal];
		var key = a.generic_instance;
		a.generic_instance = null;
		native_reject (p);
		a.generic_instance = key;
		NativeAbiVerifier.verify (p);
		a.generic_instance = b.generic_instance;
		native_reject (p);
		a.generic_instance = key;
		NativeAbiVerifier.verify (p);
		var targets = new int[5];
		for (int i = 0; i < 5; i++) {
			targets[i] = key.member_target (i);
		}
		targets[1] = b.generic_instance.member_target (1);
		a.generic_instance = new NativeExactClassInstance (key.definition, key.argument_ordinal, targets);
		native_reject (p);
		a.generic_instance = key;
		NativeAbiVerifier.verify (p);
		var field = a.fields[0];
		var slots = (NativeOwnerSlotsType) field.storage_type;
		a.fields[0] = new NativeClassField (field.span, field.name, field.type_name, 0, false, new NativeOwnerSlotsType (slots.element_ordinal, slots.element_name, slots.destructor_ordinal, NativeScalarType.PTR, NativeScalarType.I32, NativeScalarType.PTR), -1);
		native_reject (p);
		a.fields[0] = field;
		NativeAbiVerifier.verify (p);
		a.fields[0] = new NativeClassField (field.span, field.name, field.type_name, 0, false, b.fields[0].storage_type, -1);
		native_reject (p);
		a.fields[0] = field;
		NativeAbiVerifier.verify (p);
		bool borrowed = false;
		foreach (var function in p.functions) {
			foreach (var parameter in function.signature.parameters) {
				if (parameter.generic_borrow_class == a.ordinal && !borrowed) {
					parameter.generic_borrow_class = b.ordinal;
					native_reject (p);
					parameter.generic_borrow_class = a.ordinal;
					NativeAbiVerifier.verify (p);
					borrowed = true;
				}
			}
		}
		assert (borrowed);
		LlvmLowering.lower (s, p, CAbiBuilder.build (s, p)).verify ();
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void llvm_mutations() {
	try {
		var s = ssa ();
		var n = NativeAbiBuilder.build (s);
		var artifact = LlvmLowering.lower (s, n, CAbiBuilder.build (s, n));
		int transfers = 0, clears = 0, commits = 0, bounds = 0, releases = 0, extents = 0, lengths = 0, reverse = 0, backing_free = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			string name = CApi.value_name (function, out length);
			if (!name.has_prefix ("astra.slots.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					string value_name = CApi.value_name (instruction, out length);
					if (name.has_suffix (".reserve") && value_name == "reserve.checked.bytes") {
						var value = CApi.operand (instruction, 0);
						CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (value), uint64.MAX, 0));
						llvm_reject (artifact);
						CApi.set_operand (instruction, 0, value);
						artifact.verify ();
						extents++;
					}
					if (name.has_suffix (".reserve") && value_name == "slots.length") {
						var address = CApi.operand (instruction, 0);
						CApi.set_operand (instruction, 0, CApi.get_param (function, 0));
						llvm_reject (artifact);
						CApi.set_operand (instruction, 0, address);
						artifact.verify ();
						lengths++;
					}
					if (name.has_suffix (".drop") && value_name == "drop.slot.address") {
						var index = CApi.operand (instruction, 1);
						CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (index)));
						llvm_reject (artifact);
						CApi.set_operand (instruction, 1, index);
						artifact.verify ();
						reverse++;
					}
					if (name.has_suffix (".reserve") && CApi.opcode (instruction) == CApi.Opcode.CALL) {
						var target = CApi.called_value (instruction);
						string called = CApi.value_name (target, out length);
						if (called == "free") {
							var pointer = CApi.operand (instruction, 0);
							CApi.set_operand (instruction, 0, CApi.get_param (function, 0));
							llvm_reject (artifact);
							CApi.set_operand (instruction, 0, pointer);
							artifact.verify ();
							backing_free++;
						}
					}
					if (name.has_suffix (".reserve") && value_name == "reserve.old.slot") {
						var index = CApi.operand (instruction, 1);
						CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (index), int32.MAX, 0));
						llvm_reject (artifact);
						CApi.set_operand (instruction, 1, index);
						artifact.verify ();
						transfers++;
					}
					if (name.has_suffix (".reserve") && CApi.opcode (instruction) == CApi.Opcode.STORE) {
						var destination = CApi.operand (instruction, 1);
						string target = CApi.value_name (destination, out length);
						if (target == "reserve.old.slot") {
							var value = CApi.operand (instruction, 0);
							CApi.set_operand (instruction, 0, CApi.get_param (function, 0));
							llvm_reject (artifact);
							CApi.set_operand (instruction, 0, value);
							artifact.verify ();
							clears++;
						}
						if (target == "slots.capacity.address") {
							var value = CApi.operand (instruction, 0);
							CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (value)));
							llvm_reject (artifact);
							CApi.set_operand (instruction, 0, value);
							artifact.verify ();
							commits++;
						}
					}
					if (name.has_suffix (".borrow") && value_name == "slots.index.outside.live") {
						var value = CApi.operand (instruction, 1);
						CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (value), int32.MAX, 0));
						llvm_reject (artifact);
						CApi.set_operand (instruction, 1, value);
						artifact.verify ();
						bounds++;
					}
					if (name.has_suffix (".drop") && CApi.opcode (instruction) == CApi.Opcode.CALL) {
						var target = CApi.called_value (instruction);
						string called = CApi.value_name (target, out length);
						if (called.has_prefix ("astra.dtor.")) {
							int other = int.parse (called.substring ("astra.dtor.".length)) == ssa_bag (s, "Diagnostic").fields[0].slots_cleanup.object_class.ordinal ? ssa_bag (s, "Utf8Message").fields[0].slots_cleanup.object_class.ordinal : ssa_bag (s, "Diagnostic").fields[0].slots_cleanup.object_class.ordinal;
							var wrong = CApi.named_function (artifact.module, "astra.dtor.%d".printf (other));
							CApi.set_operand (instruction, CApi.argument_count (instruction), wrong);
							llvm_reject (artifact);
							CApi.set_operand (instruction, CApi.argument_count (instruction), target);
							artifact.verify ();
							releases++;
						}
					}
				}
			}
		}
		assert (transfers == 2 && clears == 2 && commits == 2 && bounds == 2 && releases == 2 && extents == 2 && lengths == 2 && reverse == 2 && backing_free == 2);
		var from = CApi.named_function (artifact.module, "astra.class.method.%d.2".printf (ssa_bag (s, "Diagnostic").ordinal));
		var to = CApi.named_function (artifact.module, "astra.class.method.%d.2".printf (ssa_bag (s, "Utf8Message").ordinal));
		bool swapped = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (!swapped && CApi.opcode (instruction) == CApi.Opcode.CALL) {
						var target = CApi.called_value (instruction);
						if ((void*) target == (void*) from) {
							CApi.set_operand (instruction, CApi.argument_count (instruction), to);
							llvm_reject (artifact);
							CApi.set_operand (instruction, CApi.argument_count (instruction), from);
							artifact.verify ();
							swapped = true;
						}
					}
				}
			}
		}
		assert (swapped);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-member-1a/independent-two-instance-stage-models", independent);
	Test.add_func ("/gen-member-1a/checked-key-definition-slot-type-restored", checked_mutations);
	Test.add_func ("/gen-member-1a/core-key-field-cleanup-init-member-restored", core_mutations);
	Test.add_func ("/gen-member-1a/cfg-key-cleanup-query-drop-restored", cfg_mutations);
	Test.add_func ("/gen-member-1a/ssa-key-cleanup-query-both-disarms-restored", ssa_mutations);
	Test.add_func ("/gen-member-1a/native-key-member-capacity-element-restored", native_mutations);
	Test.add_func ("/gen-member-1a/actual-llvm-both-transfer-clear-commit-bounds-exact-dtor-restored", llvm_mutations);
	return Test.run ();
}
}
