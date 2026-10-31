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
namespace Astra.Tests.OwnedState {
private CheckedProgram check() throws GLib.Error {
	string source, bag;
	FileUtils.get_contents ("tests/owned-state-6/proof.astra", out source);
	FileUtils.get_contents ("lib/astra/collections/bag.astra", out bag);
	var parsed = Parser.parse (new SourceFile.from_text ("owned-state-proof", source + "\n" + bag));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.format ());
	}
	return checked.program;
}
private CoreProgram core() throws GLib.Error {
	var p = CoreBuilder.build (check ());
	CoreVerifier.verify (p);
	return p;
}
private CfgProgram cfg() throws GLib.Error {
	var p = CfgBuilder.build (core ());
	CfgVerifier.verify (p);
	return p;
}
private SsaProgram ssa() throws GLib.Error {
	var p = SsaBuilder.build (cfg ());
	SsaVerifier.verify (p);
	return p;
}
private void core_reject(CoreProgram p) {
	bool rejected = false;
	try {
		CoreVerifier.verify (p);
	} catch (CoreError e) {
		Test.message ("%s", e.message);
		rejected = true;
	}
	assert (rejected);
}
private void cfg_reject(CfgProgram p) {
	bool rejected = false;
	try {
		CfgVerifier.verify (p);
	} catch (CfgError e) {
		Test.message ("%s", e.message);
		rejected = true;
	}
	assert (rejected);
}
private void ssa_reject(SsaProgram p) {
	bool rejected = false;
	try {
		SsaVerifier.verify (p);
	} catch (SsaError e) {
		Test.message ("%s", e.message);
		rejected = true;
	}
	assert (rejected);
}
private void independent() {
	try {
		CheckedProgram? checked = check ();
		var previous = WeakRef (checked.functions[0]);
		CoreProgram? c = CoreBuilder.build (checked);
		checked = null;
		assert (previous.get () == null);
		CoreVerifier.verify (c);
		previous = WeakRef (c.functions[0]);
		CfgProgram? graph = CfgBuilder.build (c);
		c = null;
		assert (previous.get () == null);
		CfgVerifier.verify (graph);
		previous = WeakRef (graph.functions[0]);
		SsaProgram? model = SsaBuilder.build (graph);
		graph = null;
		assert (previous.get () == null);
		SsaVerifier.verify (model);
		var native = NativeAbiBuilder.build (model);
		var artifact = LlvmLowering.lower (model, native, CAbiBuilder.build (model, native));
		previous = WeakRef (model.functions[0]);
		model = null;
		assert (previous.get () == null);
		NativeAbiVerifier.verify (native);
		artifact.verify ();
		assert (artifact.dump ().contains ("take.shift.header") && artifact.dump ().contains ("replace.retired.free"));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void checked_origin() {
	try {
		var p = check ();
		CheckedOwnedLocalDeclaration? found = null;
		foreach (var f in p.functions) {
			foreach (var statement in f.body.statements) {
				var declaration = statement as CheckedOwnedLocalDeclaration;
				if (declaration != null && declaration.initializer is CheckedSlotsTake) {
					found = declaration;
				}
			}
		}
		assert (found != null);
		found.local.heap_object = false;
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (p));
		} catch (CoreError e) {
			Test.message ("%s", e.message);
			rejected = true;
		}
		assert (rejected);
		found.local.heap_object = true;
		CoreVerifier.verify (CoreBuilder.build (p));
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void core_authorities() {
	try {
		var p = core ();
		int tested = 0;
		foreach (var f in p.functions) {
			for (int i = 0; i < f.body.statements.length; i++) {
				var initialize = f.body.statements[i] as CoreInitialize;
				var take = initialize == null ? null : initialize.value as CoreSlotsTake;
				if (take != null) {
					f.body.statements[i] = new CoreInitialize (initialize.span, initialize.target, initialize.value, null);
					core_reject (p);
					f.body.statements[i] = initialize;
					CoreVerifier.verify (p);
					tested++;
					f.body.statements.insert (i + 1, new CoreReturn (take.span, take));
					core_reject (p);
					f.body.statements.remove_index (i + 1);
					CoreVerifier.verify (p);
					tested++;
				}
				var replace = f.body.statements[i] as CoreSlotsReplace;
				if (replace != null) {
					var other = new BuiltinTypes ().bool_type;
					var wrong = new CoreBooleanValue (replace.span, other, BooleanLiteral.TRUE);
					f.body.statements[i] = new CoreSlotsReplace (replace.span, replace.store, wrong, replace.incoming);
					core_reject (p);
					f.body.statements[i] = replace;
					CoreVerifier.verify (p);
					tested++;
				}
			}
		}
		assert (tested == 6); // two take and two replace specializations
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void cfg_acquisition() {
	try {
		var p = cfg ();
		int tested = 0;
		foreach (var f in p.functions) {
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var initialize = block.instructions[i] as CfgInitialize;
					var take = initialize == null ? null : initialize.value as CfgSlotsValue;
					if (take != null && take.action == OwnerSlotsAction.TAKE) {
						block.instructions[i] = new CfgInitialize (initialize.span, initialize.target, initialize.value, null);
						cfg_reject (p);
						block.instructions[i] = initialize;
						CfgVerifier.verify (p);
						tested++;
						var result = new CfgEvaluatedValue (take.span, take.semantic_type);
						block.instructions.insert (i, new CfgEvaluateInstruction (take.span, take, result));
						cfg_reject (p);
						block.instructions.remove_index (i);
						CfgVerifier.verify (p);
						tested++;
					}
				}
			}
		}
		assert (tested == 4);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void ssa_dispositions() {
	try {
		var p = ssa ();
		int tested = 0;
		foreach (var f in p.functions) {
			foreach (var block in f.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var take = block.instructions[i] as SsaSlotsValueInstruction;
					var replace = block.instructions[i] as SsaSlotsEffect;
					if (take != null && take.action == OwnerSlotsAction.TAKE || replace != null && replace.action == SsaSlotsAction.REPLACE) {
						var event = block.instructions[i + 1];
						block.instructions.remove_index (i + 1);
						ssa_reject (p);
						block.instructions.insert (i + 1, event);
						SsaVerifier.verify (p);
						tested++;
						if (take != null) {
							var owner = take.owner;
							take.owner = null;
							ssa_reject (p);
							take.owner = owner;
							SsaVerifier.verify (p);
							tested++;
						}
						if (replace != null) {
							var index = replace.index;
							replace.index = null;
							ssa_reject (p);
							replace.index = index;
							SsaVerifier.verify (p);
							tested++;
						}
					}
				}
			}
		}
		assert (tested == 8);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void native_result() {
	try {
		var p = ssa ();
		var n = NativeAbiBuilder.build (p);
		int tested = 0;
		foreach (var owner in n.classes) {
			var key = owner.generic_instance;
			if (key == null) {
				continue;
			}
			var targets = new int[key.member_count];
			int take = -1, count = -1;
			for (int i = 0; i < targets.length; i++) {
				targets[i] = key.member_target (i);
				if (key.definition.member_name (i) == "take") {
					take = i;
				}
				if (key.definition.member_name (i) == "count") {
					count = i;
				}
			}
			assert (take >= 0 && count >= 0);
			int prior = targets[take];
			targets[take] = targets[count];
			var properties = new int[key.property_count];
			for (int i = 0; i < properties.length; i++) {
				properties[i] = key.property_target (i);
			}
			var replacement = key.declared_structure == null ? new NativeExactClassInstance (key.definition, key.argument_ordinal, targets, key.resource_argument, key.record_argument, key.generic_methods, properties) : new NativeExactClassInstance.declared (key.definition, key.declared_structure, targets, properties);
			if (key.declared_structure != null) {
				foreach (var method in key.generic_methods) {
					replacement.generic_methods.add (method);
				}
			}
			owner.generic_instance = replacement;
			bool rejected = false;
			try {
				NativeAbiVerifier.verify (n);
			} catch (NativeAbiError e) {
				Test.message ("%s", e.message);
				rejected = true;
			}
			assert (rejected);
			owner.generic_instance = key;
			NativeAbiVerifier.verify (n);
			targets[take] = prior;
			tested++;
		}
		assert (tested == 2);
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
private void llvm_effects() {
	try {
		var p = ssa ();
		var n = NativeAbiBuilder.build (p);
		var a = LlvmLowering.lower (p, n, CAbiBuilder.build (p, n));
		a.verify ();
		int tested = 0;
		for (var function = CApi.first_function (a.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			string name = CApi.value_name (function, out length);
			if (!name.has_prefix ("astra.slots.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					string identifier = CApi.value_name (instruction, out length);
					bool mutate = false;
					uint operand = 0;
					CApi.ValueRef replacement = CApi.get_param (function, 0);
					if (name.has_suffix (".take") && identifier == "take.outside.live") {
						mutate = true;
						operand = 1;
						replacement = CApi.const_int (CApi.type_of (CApi.operand (instruction, 1)), int32.MAX, 0);
					}
					if (name.has_suffix (".take") && CApi.opcode (instruction) == CApi.Opcode.STORE) {
						string target = CApi.value_name (CApi.operand (instruction, 1), out length);
						if (target == "take.vacated") {
							mutate = true;
						}
					}
					if (name.has_suffix (".replace") && CApi.opcode (instruction) == CApi.Opcode.STORE) {
						string target = CApi.value_name (CApi.operand (instruction, 1), out length);
						if (target == "replace.slot") {
							mutate = true;
						}
					}
					if (!mutate) {
						continue;
					}
					var value = CApi.operand (instruction, operand);
					CApi.set_operand (instruction, operand, replacement);
					bool rejected = false;
					try {
						a.verify ();
					} catch (LlvmError e) {
						Test.message ("%s", e.message);
						rejected = true;
					}
					assert (rejected);
					CApi.set_operand (instruction, operand, value);
					a.verify ();
					tested++;
				}
			}
		}
		assert (tested == 6); // take bounds, vacated slot, replacement for two exact elements
	} catch (GLib.Error e) {
		GLib.error ("%s", e.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	register_records ();
	register_lazy ();
	Test.add_func ("/owned-state-6/independent-stage-models", independent);
	Test.add_func ("/owned-state-6/checked-heap-origin", checked_origin);
	Test.add_func ("/owned-state-6/core-acquisition-and-index", core_authorities);
	Test.add_func ("/owned-state-6/cfg-acquisition-and-escape", cfg_acquisition);
	Test.add_func ("/owned-state-6/ssa-take-and-replace-events", ssa_dispositions);
	Test.add_func ("/owned-state-6/native-exact-take-result", native_result);
	Test.add_func ("/owned-state-6/llvm-bounds-vacated-slot-replacement", llvm_effects);
	return Test.run ();
}
}
