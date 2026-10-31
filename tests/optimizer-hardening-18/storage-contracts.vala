// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.Storage18 {
private SsaProgram program(string path = "tests/optimizer-hardening-18/storage.astra") throws GLib.Error {
	string text;
	FileUtils.get_contents (path, out text);
	var parsed = Parser.parse (new SourceFile.from_text ("storage18-proof", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		error ("%s", checked.diagnostic.format ());
	}
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}
private SsaFunction named(SsaProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	assert_not_reached ();
}
private void allocations() {
	try {
		var source = program ();
		var independent = named (source, "independent18");
		var mixed = named (source, "mixed18");
		assert (independent.stack_objects.length == 2);
		assert (mixed.stack_objects.length == 1 && mixed.stack_objects[0] == mixed.object_storage[1]);
		var beside_call = named (source, "beside_call18");
		assert (beside_call.stack_objects.length == 1 && beside_call.stack_objects[0] == beside_call.object_storage[1]);
		assert (named (source, "main").stack_objects.length == 0);
		SsaVerifier.verify (source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void mutations() {
	try {
		var source = program ();
		var function = named (source, "independent18");
		var root = function.stack_objects[0];
		root.result_candidate = true;
		bool refused = false;
		try {
			SsaStackObjects.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		root.result_candidate = false;
		function.stack_objects.add (root);
		refused = false;
		try {
			SsaStackObjects.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		function.stack_objects.remove_index (2);
		var mixed = named (source, "mixed18");
		mixed.stack_objects.add (mixed.object_storage[0]);
		refused = false;
		try {
			SsaStackObjects.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		mixed.stack_objects.remove_index (1);
		SsaVerifier.verify (source);
		// Remove cleanup on just one branch. The producer's global existence
		// check could still see cleanup on another branch; the independent
		// consumer must reconstruct every reachable lifetime path.
		SsaValue? reference = null;
		foreach (var instruction in function.entry.instructions) {
			var object_reference = instruction as SsaObjectReferenceInstruction;
			if (object_reference != null && object_reference.storage == root) {
				reference = instruction.result;
			}
		}
		assert (reference != null);
		bool tested = false;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				if (cleanup == null || cleanup.value != reference) {
					continue;
				}
				block.instructions.remove_index (i);
				refused = false;
				try {
					SsaStackObjects.verify (source);
				} catch (SsaError failure) {
					refused = true;
					assert (failure.message.contains ("cleanup"));
				}
				assert (refused);
				block.instructions.insert (i, cleanup);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		SsaVerifier.verify (source);

	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void shared_balance() {
	try {
		var source = program ("tests/optimizer-hardening-18/shared.astra");
		var function = named (source, "spaced18");
		assert (function.shared_elisions.length == 1);
		assert (named (source, "weak_observed18").shared_elisions.length == 0);
		assert (named (source, "callback_observed18").shared_elisions.length == 0);
		assert (named (source, "used18").shared_elisions.length == 0);
		var plan = function.shared_elisions[0];
		function.shared_elisions.add (plan);
		bool refused = false;
		try {
			SsaSharedElision.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		function.shared_elisions.remove_index (1);
		bool tested = false;
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] != plan.cleanup) {
					continue;
				}
				block.instructions.remove_index (i);
				refused = false;
				try {
					SsaSharedElision.verify (source);
				} catch (SsaError failure) {
					refused = true;
				}
				assert (refused);
				block.instructions.insert (i, plan.cleanup);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		SsaVerifier.verify (source);
		foreach (string name in new string[] { "weak_observed18", "callback_observed18", "used18" }) {
			var observed = named (source, name);
			SsaSharedOperation? copy = null;
			SsaCleanupInstruction? release = null;
			foreach (var block in observed.blocks) {
				foreach (var instruction in block.instructions) {
					var operation = instruction as SsaSharedOperation;
					if (operation != null && operation.action == SharedAction.CLONE) {
						copy = operation;
					}
				}
			}
			assert (copy != null);
			foreach (var block in observed.blocks) {
				foreach (var instruction in block.instructions) {
					var cleanup = instruction as SsaCleanupInstruction;
					if (cleanup != null && cleanup.value == copy.result) {
						release = cleanup;
					}
				}
			}
			assert (release != null);
			observed.shared_elisions.add (new SsaSharedElisionPlan (copy, release));
			refused = false;
			try {
				SsaSharedElision.verify (source);
			} catch (SsaError failure) {
				refused = true;
			}
			assert (refused);
			observed.shared_elisions.remove_index (0);
		}
		SsaVerifier.verify (source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void checked_cleanup() {
	try {
		var source = program ("tests/optimizer-hardening-18/checked-storage.astra");
		var function = named (source, "unwind18");
		assert (function.stack_objects.length == 2);
		SsaVerifier.verify (source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void independent_reference_formals() {
	try {
		var source = program ("tests/optimizer-hardening-18/reference-storage.astra");
		var function = named (source, "composition18_storage");
		assert (function.parameters[0].semantic_type is ClassType);
		assert (function.stack_objects.length == 2 && function.object_storage.length == 3);
		assert (function.stack_objects[0] == function.object_storage[0] && function.stack_objects[1] == function.object_storage[1]);
		SsaVerifier.verify (source);
		function.stack_objects.add (function.object_storage[2]);
		bool refused = false;
		try {
			SsaStackObjects.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		function.stack_objects.remove_index (2);
		SsaVerifier.verify (source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void checked_shared_regions() {
	try {
		var source = program ("tests/optimizer-hardening-18/checked-shared.astra");
		var function = named (source, "composition18_balance");
		assert (function.throws_type != null && function.shared_elisions.length == 1);
		SsaVerifier.verify (source);
		foreach (string name in new string[] { "composition18_inside", "composition18_callback" }) {
			var observed = named (source, name);
			assert (observed.shared_elisions.length == 0);
			SsaSharedOperation? copy = null;
			SsaCleanupInstruction? release = null;
			foreach (var block in observed.blocks) {
				foreach (var instruction in block.instructions) {
					var operation = instruction as SsaSharedOperation;
					if (operation != null && operation.action == SharedAction.CLONE) {
						copy = operation;
					}
				}
			}
			assert (copy != null);
			foreach (var block in observed.blocks) {
				foreach (var instruction in block.instructions) {
					var cleanup = instruction as SsaCleanupInstruction;
					if (cleanup != null && cleanup.value == copy.result) {
						release = cleanup;
					}
				}
			}
			assert (release != null);
			observed.shared_elisions.add (new SsaSharedElisionPlan (copy, release));
			bool refused = false;
			try {
				SsaSharedElision.verify (source);
			} catch (SsaError failure) {
				refused = true;
			}
			assert (refused);
			observed.shared_elisions.remove_index (0);
		}
		SsaVerifier.verify (source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void formal_effects() {
	try {
		var source = program ("tests/optimizer-hardening-18/formals.astra");
		var read = named (source, "formal18_read");
		var branch = named (source, "formal18_branch");
		var write = named (source, "formal18_write");
		var callback = named (source, "formal18_callback");
		assert (read.effect_facts.parameter (0) == 3 && branch.effect_facts.parameter (0) == 1);
		assert (write.effect_facts.parameter (0) == 1 && write.effect_facts.parameter (1) == 1);
		assert (callback.effect_facts.parameter (0) == 1 && (named (source, "formal18_pure").effect_facts.flags & 4) != 0);
		SsaFormalEffectVerifier.verify (source);
		var original_write = write.effect_facts;
		write.effect_facts = new FunctionEffectFacts (0, new uint[] { 3, 3 });
		bool refused = false;
		try {
			SsaFormalEffectVerifier.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		write.effect_facts = original_write;
		var original_callback = callback.effect_facts;
		callback.effect_facts = new FunctionEffectFacts (0, new uint[] { 3 });
		refused = false;
		try {
			SsaFormalEffectVerifier.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		callback.effect_facts = original_callback;
		// Initialization is a write too. This independent consumer must reject
		// it without depending on the producer's instruction classification.
		bool changed = false;
		foreach (var block in write.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var store = block.instructions[i] as SsaStoreInstruction;
				if (store == null) {
					continue;
				}
				block.instructions[i] = new SsaInitializeInstruction (store.span, store.target, store.value);
				write.effect_facts = new FunctionEffectFacts (0, new uint[] { 3, 3 });
				refused = false;
				try {
					SsaFormalEffectVerifier.verify (source);
				} catch (SsaError failure) {
					refused = true;
				}
				assert (refused);
				write.effect_facts = original_write;
				block.instructions[i] = store;
				changed = true;
				break;
			}
			if (changed) {
				break;
			}
		}
		assert (changed);
		SsaVerifier.verify (source);
		var method = named (source, "method_read18");
		var original_method = method.effect_facts;
		method.effect_facts = new FunctionEffectFacts (9);
		refused = false;
		try {
			SsaFormalEffectVerifier.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		method.effect_facts = original_method;
		var lazy_source = program ("examples/numerical-optimization-11/a94-metadata.astra");
		SsaFunction? factory = null;
		foreach (var function in lazy_source.functions) {
			var getter = function as SsaPropertyGetter;
			if (getter != null && getter.property_member.name == "attenuation") {
				factory = function;
			}
		}
		assert (factory != null);
		var original_factory = factory.effect_facts;
		factory.effect_facts = new FunctionEffectFacts (3);
		refused = false;
		try {
			SsaFormalEffectVerifier.verify (lazy_source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		factory.effect_facts = original_factory;
		SsaVerifier.verify (source);
		SsaVerifier.verify (lazy_source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void numeric_composition() {
	try {
		var source = program ("tests/optimizer-hardening-18/view-storage.astra");
		var views = named (source, "view18_process");
		var buffers = named (source, "view18_buffer");
		assert (views.stack_objects.length == 2 && buffers.stack_objects.length == 2);
		assert (views.object_storage.length == 3 && !views.stack_objects.find (views.object_storage[2]));
		SsaVerifier.verify (source);
		views.stack_objects.add (views.object_storage[2]);
		bool refused = false;
		try {
			SsaStackObjects.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		views.stack_objects.remove_index (2);
		SsaValue? root = null;
		foreach (var block in views.blocks) {
			foreach (var instruction in block.instructions) {
				var reference = instruction as SsaObjectReferenceInstruction;
				if (reference != null && reference.storage == views.stack_objects[0]) {
					root = reference.result;
				}
			}
		}
		assert (root != null);
		bool tested = false;
		foreach (var block in views.blocks) {
			for (int index = 0; index < block.instructions.length; index++) {
				var memory = block.instructions[index] as SsaVectorMemoryInstruction;
				if (memory == null) {
					continue;
				}
				// A forged view cannot smuggle this allocation's address into an
				// admitted numeric operation. Invoke the consumer directly.
				block.instructions[index] = new SsaVectorMemoryInstruction (memory.span, memory.contract, root, memory.offset, memory.stored, memory.result.ordinal);
				refused = false;
				try {
					SsaStackObjects.verify (source);
				} catch (SsaError failure) {
					refused = true;
				}
				assert (refused);
				block.instructions[index] = memory;
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		tested = false;
		foreach (var block in views.blocks) {
			for (int index = 0; index < block.instructions.length; index++) {
				var address = block.instructions[index] as SsaAddressOfInstruction;
				if (address == null) {
					continue;
				}
				var object_field = new SsaObjectFieldPlace (address.span, views.stack_objects[0], views.stack_objects[0].object_class.fields[0]);
				block.instructions[index] = new SsaAddressOfInstruction.projection (address.span, (ReceiverType) address.result.semantic_type, address.result.ordinal, object_field);
				refused = false;
				try {
					SsaStackObjects.verify (source);
				} catch (SsaError failure) {
					refused = true;
				}
				assert (refused);
				block.instructions[index] = address;
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		SsaVerifier.verify (source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
private void exact_receivers() {
	try {
		var source = program ("tests/optimizer-hardening-18/dispatch.astra");
		var pair = named (source, "dispatch18_pair");
		var joined = named (source, "dispatch18_join");
		SsaFunction? actual = null;
		SsaCallInstruction? selected = null;
		foreach (var function in new SsaFunction[] { pair, joined }) {
			int count = 0;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call != null && call.exact_target != null) {
						count++;
						selected = call;
						actual = call.exact_target;
					}
				}
			}
			assert (count == (function == pair ? 4 : 2));
		}
		assert (selected != null && actual != null);
		int properties = 0;
		foreach (var block in named (source, "dispatch18_property").blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call != null && call.exact_target != null) {
					assert (call.exact_target is SsaPropertyGetter);
					properties++;
				}
			}
		}
		assert (properties == 2);
		SsaFunction? different = null;
		foreach (var owner in source.classes) {
			if (owner.name == "Scale18") {
				different = owner.virtual_entries[0];
			}
		}
		assert (different != null);
		selected.exact_target = different;
		bool refused = false;
		try {
			SsaExactCalls.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		selected.exact_target = actual;
		SsaClass? offset_owner = null;
		foreach (var owner in source.classes) {
			if (owner.name == "Offset18") {
				offset_owner = owner;
			}
		}
		assert (offset_owner != null);
		var slot_target = offset_owner.virtual_entries[0];
		offset_owner.virtual_entries[0] = different;
		selected.exact_target = different;
		refused = false;
		try {
			SsaExactCalls.verify (source);
		} catch (SsaError failure) {
			refused = true;
		}
		assert (refused);
		selected.exact_target = actual;
		offset_owner.virtual_entries[0] = slot_target;
		var dynamic = named (source, "dispatch18_dynamic");
		bool tested = false;
		foreach (var block in dynamic.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call == null || call.target.dispatch_kind == ClassDispatchKind.DIRECT) {
					continue;
				}
				assert (call.exact_target == null);
				call.exact_target = actual;
				refused = false;
				try {
					SsaExactCalls.verify (source);
				} catch (SsaError failure) {
					refused = true;
				}
				assert (refused);
				call.exact_target = null;
				tested = true;
			}
		}
		assert (tested);
		// The exact-call consumer independently reconstructs cleanup instead
		// of asking the producer whether this whole function looks eligible.
		tested = false;
		foreach (var block in joined.blocks) {
			for (int index = 0; index < block.instructions.length; index++) {
				var cleanup = block.instructions[index] as SsaCleanupInstruction;
				if (cleanup == null) {
					continue;
				}
				block.instructions.remove_index (index);
				refused = false;
				try {
					SsaExactCalls.verify (source);
				} catch (SsaError failure) {
					refused = true;
				}
				assert (refused);
				block.instructions.insert (index, cleanup);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		SsaVerifier.verify (source);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/storage18/per-allocation", allocations);
	Test.add_func ("/storage18/forged-escape-and-duplicate", mutations);
	Test.add_func ("/shared18/balance-and-observers", shared_balance);
	Test.add_func ("/storage18/checked-cleanup", checked_cleanup);
	Test.add_func ("/storage18/independent-reference-formals", independent_reference_formals);
	Test.add_func ("/shared18/checked-region-boundaries", checked_shared_regions);
	Test.add_func ("/effects18/independent-formal-consumer", formal_effects);
	Test.add_func ("/storage18/numeric-views-buffers-and-aggregate", numeric_composition);
	Test.add_func ("/dispatch18/independent-exact-receivers", exact_receivers);
	return Test.run ();
}
}
