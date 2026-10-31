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

namespace Astra.Tests.BorrowedProperties {
private CoreProgram source() throws GLib.Error {
	string text = "class Child{int value;init(){this.value=42;}}"
	    + "class Holder{private owned Child child;private owned Child other;init(owned Child child,owned Child other){this.child=move child;this.other=move other;}"
	    + "property borrowed Child view{get{return this.child;}set(owned Child incoming){this.child=move incoming;}}}"
	    + "int inspect(Child child){return child.value;}int observe(Child child,Holder holder){return child.value;}void mutate(Holder holder){}"
	    + "int alias(Holder holder){return inspect(holder.view);}int main(){var child=new Child();var other=new Child();var holder=new Holder(move child,move other);return alias(holder);}";
	var parsed = Parser.parse (new SourceFile.from_text ("borrowed-property-proof", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return CoreBuilder.build (checked.program);
}
private CoreFunction core_named(CoreProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}
private CfgFunction cfg_named(CfgProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}
private SsaFunction ssa_named(SsaProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}

private void authority() {
	try {
		var core = source ();
		CoreVerifier.verify (core);
		var property = core.classes[1].properties[0];
		var getter = property.getter;
		property.is_borrowed = false;
		bool rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core marker: %s", error.message);
		}
		assert (rejected);
		property.is_borrowed = true;
		CoreVerifier.verify (core);
		var returned = getter.body.statements[0];
		getter.body.statements[0] = new CoreReturn (getter.span, new CoreNullPointerValue (getter.span, getter.return_type));
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core backing: %s", error.message);
		}
		assert (rejected);
		getter.body.statements[0] = returned;
		CoreVerifier.verify (core);

		// Same typed values, but an illegal concurrent containing-object alias.
		var alias = core_named (core, "alias");
		var saved_return = alias.body.statements[0];
		var old_call = (CoreCallValue) ((CoreReturn) saved_return).value;
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (old_call.arguments[0]);
		arguments.add (new CoreParameterValue (alias.span, alias.parameters[0]));
		alias.body.statements[0] = new CoreReturn (alias.span, new CoreCallValue (alias.span, alias.return_type, core_named (core, "observe"), arguments));
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core loan alias: %s", error.message);
		}
		assert (rejected);
		alias.body.statements[0] = saved_return;
		CoreVerifier.verify (core);

		var cfg = CfgBuilder.build (core);
		CfgVerifier.verify (cfg);
		var cfg_property = cfg.classes[1].properties[0];
		var cfg_getter = cfg_property.getter;
		cfg_property.is_borrowed = false;
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG marker: %s", error.message);
		}
		assert (rejected);
		cfg_property.is_borrowed = true;
		CfgVerifier.verify (cfg);
		var evaluation = (CfgEvaluateInstruction) cfg_getter.entry.instructions[0];
		cfg_getter.entry.instructions[0] = new CfgEvaluateInstruction (evaluation.span, new CfgNullPointerValue (evaluation.span, cfg_getter.return_type), evaluation.result);
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG backing: %s", error.message);
		}
		assert (rejected);
		cfg_getter.entry.instructions[0] = evaluation;
		CfgVerifier.verify (cfg);
		var cfg_alias = cfg_named (cfg, "alias");
		int cfg_position = -1;
		for (int i = 0; i < cfg_alias.entry.instructions.length; i++) {
			var call = cfg_alias.entry.instructions[i] as CfgCallInstruction;
			if (call != null && call.target == cfg_getter) {
				cfg_position = i + 1;
			}
		}
		assert (cfg_position >= 0);
		var cfg_arguments = new GenericArray<CfgValue> ();
		cfg_arguments.add (new CfgParameterValue (cfg_alias.span, cfg_alias.parameters[0]));
		cfg_alias.entry.instructions.insert (cfg_position, new CfgCallInstruction (cfg_alias.span, cfg_named (cfg, "mutate"), cfg_arguments, null));
		rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG loan interval: %s", error.message);
		}
		assert (rejected);
		cfg_alias.entry.instructions.remove_index (cfg_position);
		CfgVerifier.verify (cfg);

		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		var ssa_property = ssa.classes[1].properties[0];
		var ssa_getter = ssa_property.getter;
		ssa_property.is_borrowed = false;
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA marker: %s", error.message);
		}
		assert (rejected);
		ssa_property.is_borrowed = true;
		SsaVerifier.verify (ssa);
		var load = (SsaLoadInstruction) ssa_getter.entry.instructions[0];
		var place = (SsaIndirectFieldPlace) load.source;
		ssa_getter.entry.instructions[0] = new SsaLoadInstruction (load.span, new SsaIndirectFieldPlace (place.span, new SsaNullPointerConstant (place.span, ssa.classes[1].semantic_type), place.field), load.result.ordinal);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA backing: %s", error.message);
		}
		assert (rejected);
		ssa_getter.entry.instructions[0] = load;
		SsaVerifier.verify (ssa);
		var ssa_alias = ssa_named (ssa, "alias");
		int ssa_position = -1;
		for (int i = 0; i < ssa_alias.entry.instructions.length; i++) {
			var call = ssa_alias.entry.instructions[i] as SsaCallInstruction;
			if (call != null && call.target == ssa_getter) {
				ssa_position = i + 1;
			}
		}
		assert (ssa_position >= 0);
		var ssa_arguments = new GenericArray<SsaValue> ();
		ssa_arguments.add (ssa_alias.parameters[0]);
		ssa_alias.entry.instructions.insert (ssa_position, new SsaCallInstruction (ssa_alias.span, null, -1, ssa_named (ssa, "mutate"), ssa_arguments));
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA loan interval: %s", error.message);
		}
		assert (rejected);
		ssa_alias.entry.instructions.remove_index (ssa_position);
		SsaVerifier.verify (ssa);

		var native = NativeAbiBuilder.build (ssa);
		NativeAbiVerifier.verify (native);
		var physical = native.functions[ssa_getter.ordinal];
		assert (physical.receiver_borrow);
		var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
		foreach (var function in ssa.functions) {
			map.insert (function, native.functions[function.ordinal]);
		}
		physical.receiver_borrow = false;
		rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native source contract: %s", error.message);
		}
		assert (rejected);
		physical.receiver_borrow = true;
		NativeAbiVerifier.verify (native);
		NativeAbiValidator.validate_ssa_calls (ssa, native, map);
		// A claimed borrow on an ordinary int function must fail independently.
		var ordinary = native.functions[ssa_named (ssa, "inspect").ordinal];
		ordinary.receiver_borrow = true;
		rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("Native detached contract: %s", error.message);
		}
		assert (rejected);
		ordinary.receiver_borrow = false;
		NativeAbiVerifier.verify (native);

		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		int mutations = 0;
		foreach (var binding in artifact.class_addresses) {
			var instruction = binding.instruction;
			if (!binding.is_private || (void*) CApi.is_instruction (instruction) == null || CApi.operand_count (instruction) != 3) {
				continue;
			}
			var member = CApi.operand (instruction, 2);
			if ((void*) CApi.is_constant_int (member) == null || CApi.const_int_zext (member) > 1) {
				continue;
			}
			var layout = CApi.gep_source_type (instruction);
			if (CApi.count_struct_element_types (layout) != 2) {
				continue;
			}
			CApi.set_operand (instruction, 2, CApi.const_int (CApi.type_of (member), 1 - CApi.const_int_zext (member), 0));
			char* message = null;
			int generic_failure = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
			if (message != null) {
				CApi.dispose_message (message);
			}
			assert (generic_failure == 0);
			rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM private projection: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (instruction, 2, member);
			artifact.verify ();
			mutations++;
		}
		assert (mutations > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/borrowed-property/authority-backing-loan-interval-native-llvm", authority);
	return Test.run ();
}
}
