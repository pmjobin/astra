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

namespace Astra.Tests.Effects {
private SsaProgram program(bool imported = false) throws GLib.Error {
	var file = new SourceFile.from_text ("effect-proof", "extern(C) void observe(int x); class Cell { int x; init(int x){this.x=x;} int read(){return this.x;} void noisy(){observe(this.x);} } f64 pure(f64 x){return x*3.0+1.0;} int trapping(int x){return x*3+1;} void external(int x){observe(x);}", imported);
	var syntax = Parser.parse (file);
	assert (syntax.diagnostic == null);
	SemanticResult checked;
	if (imported) {
		var producer = program ();
		var native = NativeAbiBuilder.build (producer);
		var registry = new NativeDeclarationRegistry ();
		foreach (var function in producer.functions) {
			var physical = native.functions[function.ordinal];
			var receiver = function.implicit_receiver;
			string key = receiver == null ? "F:" + function.name : "C:" + ((ReceiverType) receiver.semantic_type).instance_type.display_name () + "::" + function.name_span.text ();
			registry.add (file, new NativeDeclarationIdentity ("effect-proof", key, "astra_effect_" + function.ordinal.to_string (),
				LlvmNativeModulePlan.signature_shape (function, physical.signature, native), "",
				physical.scoped_readonly, physical.readonly_inputs, physical.callback_inputs));
		}
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (syntax.unit);
		checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
	} else {
		checked = SemanticAnalyzer.analyze (syntax.unit);
	}
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}
private SsaFunction named(SsaProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name || (function is SsaPropertyGetter && ((SsaPropertyGetter) function).property_member.name == name)) {
			return function;
		}
	}
	assert_not_reached ();
}
private void ssa_facts() {
	try {
		var source = program ();
		var pure = named (source, "pure");
		var read = named (source, "read");
		var noisy = named (source, "noisy");
		assert (pure.effect_facts.flags == 4 && read.effect_facts.flags == 3 && noisy.effect_facts.flags == 1);
		assert (named (source, "trapping").effect_facts.flags == 0);
		var saved = pure.effect_facts;
		pure.effect_facts = new FunctionEffectFacts (7);
		bool rejected = false;
		try {
			SsaVerifier.verify (source);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		pure.effect_facts = saved;
		SsaVerifier.verify (source);
		bool tested = false;
		foreach (var block in noisy.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (!(block.instructions[i] is SsaCCallInstruction)) {
					continue;
				}
				var call = block.instructions[i];
				block.instructions.remove_index (i);
				rejected = false;
				try {
					SsaVerifier.verify (source);
				} catch (SsaError error) {
					rejected = true;
				}
				assert (rejected);
				block.instructions.insert (i, call);
				SsaVerifier.verify (source);
				tested = true;
				break;
			}
		}
		assert (tested);
		foreach (var function in program (true).functions) {
			assert (function.effect_facts.flags == 0);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void native_facts() {
	try {
		SsaProgram? source = program ();
		var native = NativeAbiBuilder.build (source);
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		var target = native.functions[native.functions.length - 1];
		var saved = target.effect_facts;
		target.effect_facts = new FunctionEffectFacts (4);
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		target.effect_facts = saved;
		NativeAbiVerifier.verify (native);
		target.effect_facts = null;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		target.effect_facts = saved;
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void reject(LlvmModuleArtifact artifact) {
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}
private SsaProgram stack_program() throws GLib.Error {
	var syntax = Parser.parse (new SourceFile.from_text ("stack-proof", "extern(C) void observe(int x); class Packet {int x;init(int x){this.x=x;}deinit(){observe(this.x);}int read(){return this.x;}} int process(int x){owned Packet packet=new Packet(x);if(x==0){return packet.read();}return packet.read()+1;}"));
	assert (syntax.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (syntax.unit);
	assert (checked.diagnostic == null);
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}
private void stack_facts() {
	try {
		SsaProgram? source = stack_program ();
		var function = named (source, "process");
		assert (function.stack_objects.length == 1);
		var root = function.stack_objects[0];
		function.stack_objects.add (root);
		bool rejected = false;
		try {
			SsaVerifier.verify (source);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		function.stack_objects.remove_index (1);
		SsaVerifier.verify (source);
		root.result_candidate = true;
		rejected = false;
		try {
			SsaStackObjects.verify (source);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		root.result_candidate = false;
		SsaVerifier.verify (source);
		var native = NativeAbiBuilder.build (source);
		int ordinal = function.ordinal;
		var upstream = WeakRef (source);
		function = null;
		root = null;
		source = null;
		assert (upstream.get () == null);
		var selected = native.functions[ordinal];
		assert (selected.stack_objects.length == 1);
		selected.stack_objects[0] = 42;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		selected.stack_objects[0] = 0;
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void stack_llvm() {
	try {
		SsaProgram? source = stack_program ();
		var native = NativeAbiBuilder.build (source);
		var artifact = LlvmLowering.lower (source, native, CAbiBuilder.build (source, native), null, null, false, true);
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		assert (artifact.unique_receivers.length >= 4);
		var binding = artifact.unique_receivers[0];
		uint kind = CApi.enum_attribute_kind ("noalias", 7);
		var attribute = CApi.call_enum_attribute (binding.call, 1, kind);
		CApi.remove_call_enum_attribute (binding.call, 1, kind);
		reject (artifact);
		CApi.add_call_attribute (binding.call, 1, attribute);
		artifact.verify ();
		var pointer = CApi.operand (binding.call, 0);
		CApi.set_operand (binding.call, 0, CApi.const_null (CApi.type_of (pointer)));
		reject (artifact);
		CApi.set_operand (binding.call, 0, pointer);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private SsaProgram application(string path) throws GLib.Error {
	string text;
	FileUtils.get_contents (path, out text);
	var syntax = Parser.parse (new SourceFile.from_text (path, text));
	assert (syntax.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (syntax.unit);
	assert (checked.diagnostic == null);
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}
private void lazy_factory() {
	try {
		var source = application ("examples/numerical-optimization-11/a94-metadata.astra");
		var factory = named (source, "attenuation");
		assert (factory.effect_facts.flags == 9);
		var saved = factory.effect_facts;
		factory.effect_facts = new FunctionEffectFacts (1);
		bool rejected = false;
		try {
			SsaStackObjects.verify (source);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		factory.effect_facts = saved;
		SsaLoadInstruction? load = null;
		foreach (var instruction in factory.entry.instructions) {
			if (instruction is SsaLoadInstruction) {
				load = (SsaLoadInstruction) instruction;
				break;
			}
		}
		assert (load != null);
		var mutation = new SsaStoreInstruction (load.span, load.source, load.result);
		factory.entry.instructions.add (mutation);
		rejected = false;
		try {
			SsaEffectAnalysis.verify (source);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		factory.entry.instructions.remove (mutation);
		SsaVerifier.verify (source);
		var native = NativeAbiBuilder.build (source);
		var selected = native.functions[factory.ordinal];
		var original = selected.effect_facts;
		selected.effect_facts = new FunctionEffectFacts (1);
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		selected.effect_facts = original;
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void dispatch_and_shared() {
	try {
		SsaProgram? source = application ("examples/numerical-optimization-11/a95-pipeline.astra");
		var main = named (source, "main");
		assert (main.shared_elisions.length == 1);
		var plan = main.shared_elisions[0];
		main.shared_elisions.add (plan);
		bool rejected = false;
		try {
			SsaSharedElision.verify (source);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		main.shared_elisions.remove_index (1);
		SsaVerifier.verify (source);
		var function = named (source, "exact11");
		SsaCallInstruction? exact = null;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call != null && call.exact_target != null) {
					exact = call;
				}
			}
		}
		assert (exact != null);
		var target = exact.exact_target;
		exact.exact_target = source.functions[0];
		rejected = false;
		try {
			SsaExactCalls.verify (source);
		} catch (SsaError error) {
			rejected = true;
		}
		assert (rejected);
		exact.exact_target = target;
		SsaVerifier.verify (source);
		var native = NativeAbiBuilder.build (source);
		var dispatch = native.functions[function.ordinal];
		int saved = dispatch.exact_calls[2];
		dispatch.exact_calls[2] = 0;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		dispatch.exact_calls[2] = saved;
		var shared = native.functions[main.ordinal];
		saved = shared.shared_elisions[0];
		shared.shared_elisions[0] = saved + 1;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
		}
		assert (rejected);
		shared.shared_elisions[0] = saved;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (source, native, CAbiBuilder.build (source, native), null, null, false, true);
		int ordinal = function.ordinal;
		var upstream = WeakRef (source);
		target = null;
		exact = null;
		plan = null;
		main = null;
		function = null;
		source = null;
		assert (upstream.get () == null);
		bool changed = false;
		var replacement = CApi.named_function (artifact.module, "astra.class.method.2.0");
		assert ((void*) replacement != null);
		for (var block = CApi.first_block (artifact.effects[ordinal].function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) CApi.named_function (artifact.module, "astra.class.method.1.0")) {
					continue;
				}
				int operand = CApi.operand_count (instruction) - 1;
				var original = CApi.operand (instruction, operand);
				CApi.set_operand (instruction, operand, replacement);
				reject (artifact);
				CApi.set_operand (instruction, operand, original);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
private void llvm_facts() {
	try {
		SsaProgram? source = program ();
		var native = NativeAbiBuilder.build (source);
		var artifact = LlvmLowering.lower (source, native, CAbiBuilder.build (source, native), null, null, false, true);
		var upstream = WeakRef (source);
		source = null;
		assert (upstream.get () == null);
		int tested = 0;
		foreach (var binding in artifact.effects) {
			foreach (string name in new string[] { "captures", "readonly", "memory" }) {
				uint index = name == "memory" ? uint.MAX : 1;
				uint kind = CApi.enum_attribute_kind (name, name.length);
				var attribute = CApi.enum_attribute (binding.function, index, kind);
				if ((void*) attribute == null) {
					continue;
				}
				CApi.remove_enum_attribute (binding.function, index, kind);
				reject (artifact);
				CApi.add_attribute (binding.function, index, attribute);
				artifact.verify ();
				tested++;
			}
		}
		assert (tested >= 4);
		var target = artifact.effects[artifact.effects.length - 1].function;
		uint kind = CApi.enum_attribute_kind ("noalias", 7);
		CApi.add_attribute (target, 1, CApi.create_enum_attribute (artifact.context, kind, 0));
		reject (artifact);
		CApi.remove_enum_attribute (target, 1, kind);
		artifact.verify ();
		bool changed = false;
		foreach (var binding in artifact.effects) {
			for (var block = CApi.first_block (binding.function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.LOAD) {
						continue;
					}
					var operand = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (operand)));
					reject (artifact);
					CApi.set_operand (instruction, 0, operand);
					artifact.verify ();
					changed = true;
					break;
				}
				if (changed) {
					break;
				}
			}
			if (changed) {
				break;
			}
		}
		assert (changed);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
public static int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/effects/ssa-body-and-interface", ssa_facts);
	Test.add_func ("/effects/native-detached", native_facts);
	Test.add_func ("/effects/llvm-detached", llvm_facts);
	Test.add_func ("/escape/ssa-native", stack_facts);
	Test.add_func ("/escape/llvm-detached", stack_llvm);
	Test.add_func ("/optimizer/lazy-factory", lazy_factory);
	Test.add_func ("/optimizer/dispatch-shared-detached", dispatch_and_shared);
	return Test.run ();
}
}
