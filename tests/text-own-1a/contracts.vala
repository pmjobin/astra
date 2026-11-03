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

namespace Astra.Tests.Utf8Messages {
private CheckedProgram check() throws GLib.Error {
	var files = new GenericArray<SourceFile> ();
	foreach (string path in new string[] { "tests/text-own-1a/smoke.astra", "lib/astra/text/utf8-message.astra", "lib/astra/base/errors.astra" }) {
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
	var result = CoreBuilder.build (check ());
	CoreVerifier.verify (result);
	return result;
}

private CfgProgram cfg() throws GLib.Error {
	return CfgBuilder.build (core ());
}

private SsaProgram ssa() throws GLib.Error {
	return SsaBuilder.build (cfg ());
}

private CoreFunction core_factory(CoreProgram p) {
	foreach (var f in p.functions) {
		if (f.utf8_factory) {
			return f;
		}
	}
	assert_not_reached ();
}

private CfgFunction cfg_factory(CfgProgram p) {
	foreach (var f in p.functions) {
		if (f.utf8_factory) {
			return f;
		}
	}
	assert_not_reached ();
}

private SsaFunction ssa_factory(SsaProgram p) {
	foreach (var f in p.functions) {
		if (f.utf8_factory) {
			return f;
		}
	}
	assert_not_reached ();
}

private void core_reject(CoreProgram p) {
	bool rejected = false;
	try {
		CoreVerifier.verify (p);
	} catch (CoreError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private void cfg_reject(CfgProgram p) {
	bool rejected = false;
	try {
		CfgVerifier.verify (p);
	} catch (CfgError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private void ssa_reject(SsaProgram p) {
	bool rejected = false;
	try {
		SsaVerifier.verify (p);
	} catch (SsaError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private void llvm_reject(LlvmModuleArtifact artifact) {
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private void lifetimes() {
	try {
		CheckedProgram? checked = check ();
		var prior = WeakRef (checked.functions[0]);
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		assert (prior.get () == null);
		CoreVerifier.verify (c);
		assert (CoreDump.format (c).contains ("utf8-certified-copy-input"));
		prior = WeakRef (core_factory (c));
		CfgProgram? graph = CfgBuilder.build (c);
		c = null;
		assert (prior.get () == null);
		CfgVerifier.verify (graph);
		prior = WeakRef (cfg_factory (graph));
		SsaProgram? model = SsaBuilder.build (graph);
		graph = null;
		assert (prior.get () == null);
		SsaVerifier.verify (model);
		var function = ssa_factory (model);
		assert (function.parameters[0].semantic_type is SliceType && function.heap_result && function.throws_type != null);
		var native = NativeAbiBuilder.build (model);
		var foreign = CAbiBuilder.build (model, native);
		var plan = native.functions[function.ordinal];
		assert (native.abi_version == NativeAbiVersion.NATIVE_EXCEPTIONS_V14 && plan.utf8_factory && plan.signature.has_exception_success_slot && plan.signature.parameters[0].abi_type is NativeSliceType && !(plan.signature.parameters[0].abi_type is NativeTextType));
		var artifact = LlvmLowering.lower (model, native, foreign);
		prior = WeakRef (function);
		function = null;
		model = null;
		assert (prior.get () == null);
		NativeAbiVerifier.verify (native);
		CAbiVerifier.verify (foreign);
		artifact.verify ();
		assert (artifact.dump ().contains ("@astra.text.validate.utf8") && artifact.dump ().contains ("width4.bounds"));
		assert (artifact.dump ().contains ("lib/astra/text/utf8-message.astra") && !artifact.dump ().contains ("<Utf8MessageFactory>"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void checked_mutations() {
	try {
		var p = check ();
		CheckedFunction? f = null;
		foreach (var candidate in p.functions) {
			if (candidate.symbol.utf8_factory) {
				f = candidate;
			}
		}
		assert (f != null);
		var branch = (CheckedIf) f.body.statements[0];
		var input = (CheckedUtf8FactoryExpression) branch.condition;
		var forged = new ParameterSymbol (input.input.span, input.input.name_span, input.input.semantic_type, 0, PointerParameterContract.BORROWED_NOESCAPE);
		f.body.statements[0] = new CheckedIf (branch.span, new CheckedUtf8FactoryExpression (input.span, input.semantic_type, forged, true), branch.then_body, null);
		bool rejected = false;
		try {
			CoreBuilder.build (p);
		} catch (CoreError error) {
			Test.message ("%s", error.message);
			rejected = true;
		}
		assert (rejected);
		f.body.statements[0] = branch;
		CoreVerifier.verify (CoreBuilder.build (p));
		var construction = (CheckedConstructorObjectInitialization) branch.then_body.statements[0];
		var text = construction.arguments[0];
		construction.arguments[0] = new CheckedUtf8FactoryExpression (text.span, p.types.string_type, input.input, true);
		rejected = false;
		try {
			CoreBuilder.build (p);
		} catch (CoreError error) {
			rejected = true;
		}
		assert (rejected);
		construction.arguments[0] = text;
		CoreVerifier.verify (CoreBuilder.build (p));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void core_mutations() {
	try {
		var p = core ();
		var f = core_factory (p);
		var branch = (CoreIf) f.body.statements[0];
		var construction = (CoreConstructorObjectInitialization) branch.then_block.statements[0];
		var saved = construction.arguments[0];
		var test = (CoreUtf8FactoryValue) branch.condition;
		construction.arguments[0] = new CoreUtf8FactoryValue (saved.span, saved.semantic_type, test.input, true);
		core_reject (p);
		construction.arguments[0] = saved;
		CoreVerifier.verify (p);
		f.utf8_factory = false;
		core_reject (p);
		f.utf8_factory = true;
		CoreVerifier.verify (p);
		var owner = construction.constructor.declaring_class;
		var init = (CoreFieldInitialize) owner.constructor.body.statements[0];
		owner.constructor.body.statements[0] = new CoreFieldInitialize (init.span, (CoreIndirectFieldPlace) init.target, saved);
		core_reject (p);
		owner.constructor.body.statements[0] = init;
		CoreVerifier.verify (p);
		var action = owner.destructor.field_cleanups[0];
		owner.destructor.field_cleanups.remove_index (0);
		core_reject (p);
		owner.destructor.field_cleanups.add (action);
		CoreVerifier.verify (p);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void forged_ranges() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("ranges", "void inspect(u8[] b){}int main(){u8[1] bytes={0};inspect(slice(bytes));return 0;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var p = CoreBuilder.build (checked.program);
		CoreVerifier.verify (p);
		var main = p.functions[1];
		var call = (CoreCallStatement) main.body.statements[1];
		var view = (CoreSliceFromArrayValue) call.arguments[0];
		var type = ((CoreReturn) main.body.statements[2]).value.semantic_type;
		var zero = new CoreIntegerValue.typed (view.span, type, AstraIntegerValue.from_int64 ((IntegerType) type, 0));
		var negative = new CoreIntegerValue.typed (view.span, type, AstraIntegerValue.from_int64 ((IntegerType) type, -1));
		call.arguments[0] = new CoreSliceFromArrayValue (view.span, (SliceType) view.semantic_type, view.storage, view.array_type, zero, negative, view.provenance);
		core_reject (p);
		call.arguments[0] = view;
		CoreVerifier.verify (p);
		var origin = new DataPointerProvenance (DataPointerOrigin.LOCAL, view.storage.ordinal + 1, view.provenance.region_ordinal);
		call.arguments[0] = new CoreSliceFromArrayValue (view.span, (SliceType) view.semantic_type, view.storage, view.array_type, null, null, origin);
		core_reject (p);
		call.arguments[0] = view;
		CoreVerifier.verify (p);
		var count = new CoreIntegerValue.typed (view.span, type, AstraIntegerValue.from_int64 ((IntegerType) type, int32.MAX));
		call.arguments[0] = new CoreSliceFromArrayValue (view.span, (SliceType) view.semantic_type, view.storage, view.array_type, zero, count, view.provenance);
		core_reject (p);
		call.arguments[0] = view;
		CoreVerifier.verify (p);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_mutations() {
	try {
		var p = cfg ();
		var f = cfg_factory (p);
		var branch = (CfgConditionalBranch) f.entry.terminator;
		CfgLifecycleCallInstruction? construction = null;
		foreach (var instruction in branch.true_target.instructions) {
			if (instruction is CfgLifecycleCallInstruction) {
				construction = (CfgLifecycleCallInstruction) instruction;
			}
		}
		assert (construction != null);
		var saved = (CfgUtf8FactoryValue) construction.arguments[0];
		var wrong = new CfgParameter (saved.input.span, saved.input.name_span, saved.input.name, saved.input.semantic_type, 0, saved.input.pointer_contract);
		construction.arguments[0] = new CfgUtf8FactoryValue (saved.span, saved.semantic_type, wrong, false);
		cfg_reject (p);
		construction.arguments[0] = saved;
		CfgVerifier.verify (p);
		var original = f.entry;
		var reversed = new CfgBlock (original.span, original.ordinal, original.instructions, new CfgConditionalBranch (original.span, branch.condition, branch.false_target, branch.true_target));
		var blocks = new GenericArray<CfgBlock> ();
		foreach (var block in f.blocks) {
			blocks.add (block == original ? reversed : block);
		}
		var wrong_guard = new CfgFunction (f.span, f.name_span, f.name, f.return_type, f.ordinal, f.parameters, f.locals, blocks, reversed, f.owned_cleanup);
		wrong_guard.utf8_factory = true;
		wrong_guard.heap_result = true;
		wrong_guard.throws_type = f.throws_type;
		p.functions[f.ordinal] = wrong_guard;
		bool rejected = false;
		try {
			CfgVerifier.verify (p);
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("UTF-8 factory lost exact guarded byte group");
		}
		assert (rejected);
		p.functions[f.ordinal] = f;
		CfgVerifier.verify (p);
		var ctor = construction.target as CfgConstructor;
		var init = (CfgInitialize) ctor.entry.instructions[0];
		ctor.entry.instructions[0] = new CfgInitialize (init.span, init.target, saved);
		cfg_reject (p);
		ctor.entry.instructions[0] = init;
		CfgVerifier.verify (p);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ssa_mutations() {
	try {
		var p = ssa ();
		var f = ssa_factory (p);
		var test = (SsaUtf8FactoryInstruction) f.entry.instructions[0];
		var wrong = new SsaFunctionParameter (test.input.span, test.input.name_span, test.input.name, test.input.semantic_type, 0, test.input.pointer_contract);
		f.entry.instructions[0] = new SsaUtf8FactoryInstruction (test.span, test.result.semantic_type, wrong, true, test.result.ordinal);
		ssa_reject (p);
		f.entry.instructions[0] = test;
		SsaVerifier.verify (p);
		var branch = (SsaConditionalBranch) f.entry.terminator;
		var success = branch.true_edge.target;
		int transfer_position = -1;
		SsaInstruction? transfer = null;
		for (int i = 0; i < success.instructions.length; i++) {
			var event = success.instructions[i] as SsaHeapOwnerEvent;
			if (event != null && event.action == SsaHeapOwnerAction.RETURN) {
				transfer_position = i;
				transfer = event;
			}
		}
		assert (transfer != null);
		var event = (SsaHeapOwnerEvent) transfer;
		success.instructions[transfer_position] = new SsaHeapOwnerEvent (event.span, event.owner, SsaHeapOwnerAction.RELEASE, event.value, event.effect);
		ssa_reject (p);
		success.instructions[transfer_position] = transfer;
		SsaVerifier.verify (p);
		foreach (var function in p.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var binding = block.instructions[i] as SsaTextLoanBind;
					if (binding == null) {
						continue;
					}
					block.instructions[i] = new SsaTextLoanBind (binding.span, binding.loan, binding.value, new Astra.Text.TextLoanIntent (new GenericArray<Object> ()));
					ssa_reject (p);
					block.instructions[i] = binding;
					SsaVerifier.verify (p);
					return;
				}
			}
		}
		assert_not_reached ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_mutations() {
	try {
		var p = ssa ();
		var f = ssa_factory (p);
		var native = NativeAbiBuilder.build (p);
		var foreign = CAbiBuilder.build (p, native);
		var plan = native.functions[f.ordinal];
		var saved = plan.signature.parameters[0];
		plan.signature.parameters[0] = new NativeParameter.typed (saved.span, saved.name_span, saved.name, saved.ordinal, new NativeTextType (NativeTextContract.BORROWED_NOESCAPE));
		bool rejected = false;
		try {
			LlvmLowering.lower (p, native, foreign);
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = true;
		}
		assert (rejected);
		plan.signature.parameters[0] = saved;
		LlvmLowering.lower (p, native, foreign).verify ();
		plan.utf8_factory = false;
		rejected = false;
		try {
			LlvmLowering.lower (p, native, foreign);
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = true;
		}
		assert (rejected);
		plan.utf8_factory = true;
		LlvmLowering.lower (p, native, foreign).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private LlvmModuleArtifact artifact() throws GLib.Error {
	var p = ssa ();
	var n = NativeAbiBuilder.build (p);
	return LlvmLowering.lower (p, n, CAbiBuilder.build (p, n));
}

private void llvm_mutations() {
	try {
		var a = artifact ();
		a.verify ();
		var helper = CApi.named_function (a.module, "astra.text.validate.utf8");
		assert ((void*) helper != null);
		var entry = CApi.first_block (helper);
		var condition = CApi.block_terminator (entry);
		var target = CApi.successor (condition, 0);
		CApi.set_successor (condition, 0, CApi.successor (condition, 1));
		llvm_reject (a);
		CApi.set_successor (condition, 0, target);
		a.verify ();
		bool count_done = false, copy_done = false, load_done = false;
		for (var function = CApi.first_function (a.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.CALL) {
						var called = CApi.called_value (instruction);
						if ((void*) called == (void*) helper && !count_done) {
							var count = CApi.operand (instruction, 1);
							CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (count), uint32.MAX, 0));
							llvm_reject (a);
							CApi.set_operand (instruction, 1, count);
							a.verify ();
							count_done = true;
						}
						size_t length;
						string name = CApi.value_name (called, out length);
						if (name.has_prefix ("llvm.memcpy") && !copy_done) {
							var extent = CApi.operand (instruction, 2);
							CApi.set_operand (instruction, 2, CApi.const_null (CApi.type_of (extent)));
							llvm_reject (a);
							CApi.set_operand (instruction, 2, extent);
							a.verify ();
							copy_done = true;
						}
					}
					if ((void*) function == (void*) helper && CApi.opcode (instruction) == CApi.Opcode.LOAD && !load_done) {
						CApi.set_volatile (instruction, 1);
						llvm_reject (a);
						CApi.set_volatile (instruction, 0);
						a.verify ();
						load_done = true;
					}
				}
			}
		}
		assert (count_done && copy_done && load_done);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/text-own-1a/independent-stages-and-physical-contract", lifetimes);
	Test.add_func ("/text-own-1a/checked-byte-origin-and-validity-restored", checked_mutations);
	Test.add_func ("/text-own-1a/core-copy-origin-and-cleanup-restored", core_mutations);
	Test.add_func ("/text-own-1a/forged-negative-max-count-and-origin-restored", forged_ranges);
	Test.add_func ("/text-own-1a/cfg-guard-input-and-constructor-restored", cfg_mutations);
	Test.add_func ("/text-own-1a/ssa-byte-group-disarm-and-loan-restored", ssa_mutations);
	Test.add_func ("/text-own-1a/native-byte-text-and-marker-restored", native_mutations);
	Test.add_func ("/text-own-1a/llvm-guard-count-copy-and-read-restored", llvm_mutations);
	return Test.run ();
}

}
