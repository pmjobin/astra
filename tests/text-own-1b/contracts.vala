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
namespace Astra.Tests.ByteBuilder {
private CheckedProgram check() throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	foreach (string path in new string[] { "tests/text-own-1b/privacy.astra", "tests/text-own-1b/privacy-model.astra", "tests/text-own-1b/smoke.astra", "lib/astra/text/utf8-byte-builder.astra", "lib/astra/text/utf8-message.astra", "lib/astra/base/errors.astra" }) {
		if (path == "tests/text-own-1b/smoke.astra") {
			continue;
		}
		string text;
		FileUtils.get_contents (path, out text);
		files.add (new SourceFile.from_text (path, text));
	}
	var parsed = SyntaxProgram.parse (new SourceSet (files));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze_program (parsed.program);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
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
private void checked_and_core() {
	try {
		var p = check ();
		CheckedFunction? inspect = null;
		ClassSymbol? vault = null;
		foreach (var f in p.all_definitions ()) {
			if (f.symbol.name == "inspect") {
				inspect = f;
			}
		}
		foreach (var c in p.classes) {
			if (c.name == "Vault") {
				vault = c;
			}
		}
		assert (inspect != null && vault != null && vault.fields[0].is_private && !vault.fields[3].is_private);
		var saved = inspect.body.statements[0];
		var returned = (CheckedReturnStatement) saved;
		var load = (CheckedLoadExpression) returned.expression;
		var place = (CheckedObjectFieldPlace) load.source;
		inspect.body.statements[0] = new CheckedReturnStatement (returned.span, new CheckedLoadExpression (load.span, new CheckedObjectFieldPlace (place.span, place.reference, vault.fields[0])));
		bool failed = false;
		try {
			CoreBuilder.build (p);
		} catch (CoreError e) {
			failed = e.message.contains ("private field");
			Test.message ("%s", e.message);
		}
		assert (failed);
		inspect.body.statements[0] = saved;
		CoreVerifier.verify (CoreBuilder.build (p));
		var c = core ();
		CoreFunction? function = null;
		CoreClass? owner = null;
		foreach (var f in c.functions) {
			if (f.name == "inspect") {
				function = f;
			}
		}
		foreach (var v in c.classes) {
			if (v.name == "Vault") {
				owner = v;
			}
		}
		var old = function.body.statements[0];
		var ret = (CoreReturn) old;
		var value = (CoreLoadValue) ret.value;
		var field = (CoreIndirectFieldPlace) value.source;
		function.body.statements[0] = new CoreReturn (ret.span, new CoreLoadValue (value.span, new CoreIndirectFieldPlace (field.span, field.pointer, owner.fields[0])));
		failed = false;
		try {
			CoreVerifier.verify_concrete (c);
		} catch (CoreError e) {
			failed = e.message.contains ("private field");
			Test.message ("%s", e.message);
		}
		assert (failed);
		function.body.statements[0] = old;
		CoreVerifier.verify_concrete (c);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void cfg_mutation() {
	try {
		var p = cfg ();
		CfgFunction? inspect = null;
		CfgClass? vault = null;
		foreach (var f in p.functions) {
			if (f.name == "inspect") {
				inspect = f;
			}
		}
		foreach (var c in p.classes) {
			if (c.name == "Vault") {
				vault = c;
			}
		}
		bool tested = false;
		foreach (var block in inspect.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var evaluation = block.instructions[i] as CfgEvaluateInstruction;
				var load = evaluation == null ? null : evaluation.value as CfgLoadValue;
				if (load == null || !(load.source is CfgIndirectFieldPlace)) {
					continue;
				}
				var place = (CfgIndirectFieldPlace) load.source;
				var value = new CfgLoadValue (load.span, new CfgIndirectFieldPlace (place.span, place.pointer, vault.fields[0]));
				int slot = (int) block.instructions.length;
				var public_value = new CfgLoadValue (load.span, new CfgIndirectFieldPlace (place.span, place.pointer, vault.fields[3]));
				block.instructions.add (new CfgEvaluateInstruction (load.span, public_value, new CfgEvaluatedValue (load.span, public_value.semantic_type)));
				CfgVerifier.verify (p);
				block.instructions[slot] = new CfgEvaluateInstruction (load.span, value, new CfgEvaluatedValue (load.span, value.semantic_type));
				bool failed = false;
				try {
					CfgVerifier.verify (p);
				} catch (CfgError e) {
					failed = e.message.contains ("private field");
					Test.message ("%s", e.message);
				}
				assert (failed);
				block.instructions.remove_index (slot);
				CfgVerifier.verify (p);
				tested = true;
				break;
			}
		}
		assert (tested);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void ssa_mutation() {
	try {
		var p = ssa ();
		SsaFunction? inspect = null;
		SsaClass? vault = null;
		int next = 0;
		foreach (var f in p.functions) {
			if (f.name == "inspect") {
				inspect = f;
			}
		}
		foreach (var c in p.classes) {
			if (c.name == "Vault") {
				vault = c;
			}
		}
		foreach (var block in inspect.blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction.result != null) {
					next = int.max (next, instruction.result.ordinal + 1);
				}
			}
		}
		bool tested = false;
		foreach (var block in inspect.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var load = block.instructions[i] as SsaLoadInstruction;
				if (load == null || !(load.source is SsaIndirectFieldPlace)) {
					continue;
				}
				var place = (SsaIndirectFieldPlace) load.source;
				int slot = (int) block.instructions.length;
				block.instructions.add (new SsaLoadInstruction (load.span, new SsaIndirectFieldPlace (place.span, place.pointer, vault.fields[3]), next));
				SsaVerifier.verify (p);
				block.instructions[slot] = new SsaLoadInstruction (load.span, new SsaIndirectFieldPlace (place.span, place.pointer, vault.fields[0]), next);
				bool failed = false;
				try {
					SsaVerifier.verify (p);
				} catch (SsaError e) {
					failed = e.message.contains ("private field");
					Test.message ("%s", e.message);
				}
				assert (failed);
				block.instructions.remove_index (slot);
				SsaVerifier.verify (p);
				tested = true;
				break;
			}
		}
		assert (tested);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void native_mutations() {
	try {
		var s = ssa ();
		var p = NativeAbiBuilder.build (s);
		assert (p.private_accesses.length > 3);
		int outside = -1;
		foreach (var f in p.functions) {
			if (f.name == "inspect") {
				outside = f.ordinal;
			}
		}
		assert (outside >= 0);
		var saved = p.private_accesses[0];
		p.private_accesses[0] = new NativePrivateFieldAccess (saved.class_ordinal, saved.field_ordinal, outside);
		bool failed = false;
		try {
			NativeAbiVerifier.verify (p);
		} catch (NativeAbiError e) {
			failed = e.message.contains ("private field");
			Test.message ("%s", e.message);
		}
		assert (failed);
		p.private_accesses[0] = saved;
		NativeAbiVerifier.verify (p);
		p.private_accesses.remove_index (0);
		failed = false;
		try {
			NativeAbiVerifier.verify (p);
		} catch (NativeAbiError e) {
			failed = e.message.contains ("inventory");
		}
		assert (failed);
		p.private_accesses.insert (0, saved);
		NativeAbiVerifier.verify (p);
		var owner = p.classes[saved.class_ordinal];
		var field = owner.fields[saved.field_ordinal];
		owner.fields[saved.field_ordinal] = new NativeClassField (field.span, field.name, field.type_name, field.ordinal, field.text_snapshot, field.storage_type, field.record_ordinal);
		failed = false;
		try {
			NativeAbiVerifier.verify (p);
		} catch (NativeAbiError e) {
			failed = e.message.contains ("private field");
		}
		assert (failed);
		owner.fields[saved.field_ordinal] = field;
		NativeAbiVerifier.verify (p);
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
		LlvmClassAddressBinding? selected = null;
		foreach (var binding in artifact.class_addresses) {
			if (binding.is_private) {
				selected = binding;
				break;
			}
		}
		assert (selected != null);
		var address = selected.instruction;
		var index = CApi.operand (address, 2);
		CApi.set_operand (address, 2, CApi.const_int (CApi.type_of (index), CApi.const_int_zext (index) == 0 ? 1 : 0, 0));
		bool failed = false;
		try {
			artifact.verify ();
		} catch (LlvmError e) {
			Test.message ("%s", e.message);
			failed = true;
		}
		assert (failed);
		CApi.set_operand (address, 2, index);
		artifact.verify ();
		int outsider = -1;
		foreach (var f in s.functions) {
			if (f.name == "inspect") {
				outsider = f.ordinal;
			}
		}
		assert (outsider >= 0);
		var next = CApi.next_instruction (address);
		var outside = CApi.named_function (artifact.module, "astra.fn.%d".printf (outsider));
		assert ((void*) next != null && (void*) outside != null);
		var target = CApi.first_instruction (CApi.first_block (outside));
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.remove_instruction (address);
		CApi.position_builder_before (builder, target);
		CApi.insert_instruction (builder, address);
		failed = false;
		try {
			selected.verify ();
		} catch (LlvmError e) {
			failed = e.message.contains ("private field address escaped");
			Test.message ("%s", e.message);
		}
		assert (failed);
		CApi.remove_instruction (address);
		CApi.position_builder_before (builder, next);
		CApi.insert_instruction (builder, address);
		CApi.dispose_builder (builder);
		artifact.verify ();
		int builder_class = -1;
		foreach (var c in s.classes) {
			if (c.name == "Utf8ByteBuilder") {
				builder_class = c.ordinal;
			}
		}
		assert (builder_class >= 0);
		int allocations = 0, releases = 0;
		foreach (string name in new string[] { "astra.class.method.%d.2".printf (builder_class), "astra.class.method.%d.4".printf (builder_class), "astra.dtor.%d".printf (builder_class) }) {
			var f = CApi.named_function (artifact.module, name);
			assert ((void*) f != null);
			bool tested = false;
			for (var b = CApi.first_block (f); (void*) b != null && !tested; b = CApi.next_block (b)) {
				for (var i = CApi.first_instruction (b); (void*) i != null; i = CApi.next_instruction (i)) {
					if (CApi.opcode (i) != CApi.Opcode.CALL) {
						continue;
					}
					size_t size;
					string target_name = CApi.value_name (CApi.called_value (i), out size);
					bool drop = name.has_prefix ("astra.dtor.");
					if (target_name != (drop ? "free" : "calloc")) {
						continue;
					}
					var operand = CApi.operand (i, 0);
					CApi.set_operand (i, 0, CApi.const_null (CApi.type_of (operand)));
					failed = false;
					try {
						artifact.verify ();
					} catch (LlvmError e) {
						failed = true;
						Test.message ("%s: %s", name, e.message);
					}
					assert (failed);
					CApi.set_operand (i, 0, operand);
					artifact.verify ();
					if (drop) {
						releases++;
					} else {
						allocations++;
					} tested = true;
					break;
				}
			}
			assert (tested);
		}
		assert (allocations == 2 && releases == 1);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void independent() {
	try {
		CheckedProgram? checked = check ();
		var old = WeakRef (checked.classes[0]);
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		assert (old.get () == null);
		CoreVerifier.verify (c);
		c = CoreGenericMonomorphizer.build (c);
		old = WeakRef (c.classes[0]);
		CfgProgram? g = CfgBuilder.build (c);
		c = null;
		assert (old.get () == null);
		CfgVerifier.verify (g);
		old = WeakRef (g.classes[0]);
		SsaProgram? s = SsaBuilder.build (g);
		g = null;
		assert (old.get () == null);
		SsaVerifier.verify (s);
		old = WeakRef (s.classes[0]);
		var n = NativeAbiBuilder.build (s);
		var artifact = LlvmLowering.lower (s, n, CAbiBuilder.build (s, n));
		s = null;
		assert (old.get () == null);
		NativeAbiVerifier.verify (n);
		artifact.verify ();
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-own-1b/checked-core-private-access-restored", checked_and_core);
	Test.add_func ("/text-own-1b/cfg-private-access-restored", cfg_mutation);
	Test.add_func ("/text-own-1b/ssa-private-access-restored", ssa_mutation);
	Test.add_func ("/text-own-1b/native-private-access-inventory-restored", native_mutations);
	Test.add_func ("/text-own-1b/llvm-field-scope-index-extent-restored", llvm_mutations);
	Test.add_func ("/text-own-1b/stages-retire-predecessor-graphs", independent);
	return Test.run ();
}
}
