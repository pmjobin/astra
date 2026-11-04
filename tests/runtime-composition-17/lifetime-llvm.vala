// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Backend.LLVM;

namespace Astra.Tests.ContextContracts {
// Detached, well-formed LLVM controls. These modules are inspected, never run;
// public Astra execution is qualified separately by the runtime recipes.
private class ScopedLlvmFixture : Object {
	internal CApi.ContextRef context;
	internal CApi.ModuleRef module;
	private CApi.BuilderRef builder;
	internal HashTable<void*, LlvmScopedTaskFrame> task_frames = new HashTable<void*, LlvmScopedTaskFrame> (direct_hash, direct_equal);
	private CApi.ValueRef function;
	private CApi.ValueRef allocation_function;
	private CApi.ValueRef release_function;
	private CApi.ValueRef destroy_function;
	private CApi.ValueRef loan;
	private CApi.TypeRef pointer;
	private CApi.TypeRef word;
	private CApi.TypeRef size;
	private CApi.ValueRef tag;
	private bool borrowed_module;
	private CApi.ValueRef declare(string name, CApi.TypeRef result, CApi.TypeRef[] arguments) {
		var type = CApi.function_type (result, arguments, arguments.length, 0);
		var prior = CApi.named_function (module, name);
		if ((void*) prior != null) {
			assert ((void*) CApi.global_value_type (prior) == (void*) type);
			return prior;
		}
		return CApi.add_function (module, name, type);
	}

	private CApi.ValueRef call(CApi.ValueRef target, CApi.ValueRef[] arguments, string name = "") {
		var result = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, arguments.length, name);
		CApi.set_instruction_call_conv (result, CApi.CallConv.C);
		return result;
	}

	private CApi.BasicBlockRef block(string name) {
		return CApi.append_basic_block_in_context (context, function, name);
	}

	private void at(CApi.BasicBlockRef block) {
		CApi.position_builder_at_end (builder, block);
	}

	private CApi.ValueRef allocate(int mode) {
		return call (allocation_function, new CApi.ValueRef[] { mode == 16 ? CApi.const_null (pointer) : loan, CApi.const_int (size, 1, 0), CApi.const_int (size, mode == 26 ? 4 : 37, 0), CApi.const_int (word, mode == 26 ? 4 : 8, 0), tag, CApi.const_int (word, mode == 15 ? 2 : 3, 0) }, "allocation");
	}

	private void release(CApi.ValueRef owner, bool wrong = false) {
		call (release_function, new CApi.ValueRef[] { owner, wrong ? CApi.const_int (size, 78, 0) : tag }, "retired");
	}

	private void destroy() {
		call (destroy_function, new CApi.ValueRef[] { loan });
	}

	private void finish() {
		destroy ();
		CApi.build_ret (builder, CApi.const_int (word, 0, 0));
	}

	private CApi.ValueRef address(CApi.ValueRef owner) {
		var zero = CApi.const_int (word, 0, 0);
		return CApi.build_gep (builder, word, owner, &zero, 1, "field");
	}

	internal ScopedLlvmFixture (int mode, LlvmModuleArtifact? artifact = null) {
		borrowed_module = artifact != null;
		context = artifact == null ? CApi.context_create() : artifact.context;
		module = artifact == null ? CApi.module_create_with_name_in_context("scoped-owner-proof", context) : artifact.module;
		builder = CApi.create_builder_in_context (context);
		pointer = CApi.pointer_type_in_context (context, 0);
		word = CApi.int32_type_in_context (context);
		size = CApi.int_type_in_context (context, 64);
		tag = CApi.const_int (size, 77, 0);
		if (mode == 26) {
			assert (artifact != null);
			try {
				tag = new LlvmPolicyAllocation (artifact).tag ("Observer", "object");
			} catch (LlvmError failure) {
				error ("%s", failure.message);
			}
		}
		function = declare ("exercise", word, new CApi.TypeRef[] { CApi.int1_type_in_context (context), pointer });
		at (block ("entry"));
		var open = declare ("astra_context17_open_scoped", pointer, new CApi.TypeRef[] { pointer, word, word, word });
		allocation_function = declare ("astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
		release_function = declare ("astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		destroy_function = declare ("astra_context17_destroy", CApi.void_type_in_context (context), new CApi.TypeRef[] { pointer });
		if (mode == 22) {
			var caller = CApi.insert_block (builder);
			var body = CApi.append_basic_block_in_context (context, release_function, "false.retirement");
			at (body);
			CApi.build_ret (builder, CApi.const_int (word, 1, 0));
			at (caller);
		}
		loan = call (open, new CApi.ValueRef[] { CApi.const_null (pointer), CApi.const_int (word, 4097, 0), CApi.const_int (word, 1, 0), CApi.const_int (word, 7, 0) }, "context");
		var condition = CApi.get_param (function, 0);
		if (mode >= 58) {
			var descriptor_function = declare ("astra_context17_frame_descriptor", pointer, new CApi.TypeRef[] { word });
			var descriptor = call (descriptor_function, new CApi.ValueRef[] { CApi.const_int (word, 3, 0) }, "frame.descriptor");
			var factory = declare ("scoped.test.task.create", pointer, new CApi.TypeRef[] { pointer, pointer, pointer });
			CApi.set_function_call_conv (factory, LlvmLowering.CALL_CONVENTION);
			CApi.ValueRef[] captured = {
				CApi.const_null (pointer), descriptor, loan
			};
			if (mode == 74) {
				destroy ();
			}
			var task = call (factory, captured, "scoped.cold.task");
			CApi.set_instruction_call_conv (task, LlvmLowering.CALL_CONVENTION);
			try {
				task_frames.insert ((void*) task, new LlvmScopedTaskFrame (task, factory, CApi.global_value_type (factory), captured));
			} catch (LlvmError failure) {
				error ("%s", failure.message);
			}
			if (mode >= 75) {
				var drop = declare ("astra_async_drop", CApi.void_type_in_context (context), new CApi.TypeRef[] { pointer });
				var make_error = declare ("unknown.task.error", pointer, new CApi.TypeRef[] {});
				var admitted = block ("frame.accepted");
				var refused = block ("frame.refused");
				var joined = block ("frame.outcome");
				var observed = CApi.build_icmp (builder, CApi.IntPredicate.EQ, task, CApi.const_null (pointer), "frame.refusal");
				CApi.build_cond_br (builder, observed, refused, admitted);
				at (admitted);
				var success_error = mode == 76 ? call (make_error, new CApi.ValueRef[] {}, "wrong.success.error") : CApi.const_null (pointer);
				CApi.build_br (builder, joined);
				at (refused);
				var failure_error = mode == 76 ? CApi.const_null (pointer) : call (make_error, new CApi.ValueRef[] {}, "deferred.failure.error");
				CApi.build_br (builder, joined);
				at (joined);
				var error = CApi.build_phi (builder, pointer, "checked.frame.error");
				CApi.add_incoming (error, &success_error, &admitted, 1);
				CApi.add_incoming (error, &failure_error, &refused, 1);
				var accepted = block ("checked.success");
				var caught = block ("checked.catch");
				var drop_block = block ("checked.drop");
				var done = block ("checked.done");
				var test = mode == 78 ? condition : CApi.build_icmp (builder, mode == 80 ? CApi.IntPredicate.NE : CApi.IntPredicate.EQ, error, CApi.const_null (pointer), "checked.success.test");
				CApi.build_cond_br (builder, test, accepted, caught);
				at (accepted);
				CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, task, CApi.const_null (pointer), "checked.task.absent"), done, drop_block);
				at (drop_block);
				if (mode != 77) {
					call (drop, new CApi.ValueRef[] { mode == 79 ? CApi.const_null (pointer) : task });
				}
				CApi.build_br (builder, done);
				at (caught);
				CApi.build_br (builder, done);
				at (done);
				finish ();
				return;
			}
			if (mode == 64) {
				CApi.set_operand (descriptor, 0, CApi.const_int (word, 2, 0));
			}
			if (mode == 65) {
				CApi.set_operand (task, 2, CApi.const_null (pointer));
			}
			if (mode == 66) {
				task_frames.remove ((void*) task);
			}
			var drop = declare ("astra_async_drop", CApi.void_type_in_context (context), new CApi.TypeRef[] { pointer });
			var phase = declare ("astra_async_phase", word, new CApi.TypeRef[] { pointer });
			if (mode == 60) {
				destroy ();
			}
			if (mode == 67) {
				var escape = declare ("escape.scoped.task", word, new CApi.TypeRef[] { pointer });
				call (escape, new CApi.ValueRef[] { task }, "escaped.task");
			}
			if (mode == 69) {
				call (phase, new CApi.ValueRef[] { task }, "task.phase");
			}
			if (mode == 72) {
				address (task);
			}
			if (mode == 71) {
				var present = block ("task.live");
				var done = block ("task.done");
				CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, task, CApi.const_null (pointer), "task.refused"), done, present);
				at (present);
				call (drop, new CApi.ValueRef[] { task });
				CApi.build_br (builder, done);
				at (done);
				finish ();
				return;
			}
			if (mode == 59 || mode == 70 || mode == 73) {
				var run = declare ("astra_async_run", word, new CApi.TypeRef[] { pointer, pointer, pointer });
				if (mode == 73) {
					var caller = CApi.insert_block (builder);
					var fake = CApi.append_basic_block_in_context (context, run, "fake.observation");
					at (fake);
					CApi.build_ret (builder, CApi.const_int (word, 5, 0));
					at (caller);
				}
				if (mode == 70) {
					var cancel = declare ("astra_async_cancel", CApi.void_type_in_context (context), new CApi.TypeRef[] { pointer });
					call (cancel, new CApi.ValueRef[] { task });
				}
				var error = CApi.build_alloca (builder, pointer, "task.error");
				call (run, new CApi.ValueRef[] { CApi.get_param (function, 1), task, error }, "task.observed");
			} else if (mode != 61) {
				call (drop, new CApi.ValueRef[] { mode == 68 ? CApi.const_null (pointer) : task });
			}
			if (mode == 62) {
				call (drop, new CApi.ValueRef[] { task });
			}
			if (mode == 63) {
				call (phase, new CApi.ValueRef[] { task }, "stale.task.phase");
			}
			if (mode == 60 || mode == 74) {
				CApi.build_ret (builder, CApi.const_int (word, 0, 0));
			} else {
				finish ();
			} return;
		}

		if (mode >= 53 && mode <= 57) {
			var owner = allocate (mode);
			var slot = CApi.build_alloca (builder, pointer, "branch.storage");
			var transferred = block ("transferred");
			var retained = block ("retained");
			var joined = block ("short.circuit.join");
			var stored_cleanup = block ("stored.cleanup");
			var original_cleanup = block ("original.cleanup");
			var done = block ("done");
			var unrelated = CApi.build_icmp (builder, CApi.IntPredicate.EQ, CApi.get_param (function, 1), CApi.const_null (pointer), "unrelated.condition");
			CApi.build_cond_br (builder, condition, transferred, retained);
			at (transferred);
			CApi.build_store (builder, owner, slot);
			CApi.build_br (builder, joined);
			at (retained);
			CApi.build_br (builder, joined);
			at (joined);
			var selected = CApi.build_phi (builder, CApi.int1_type_in_context (context), "short.circuit");
			var yes = mode == 57 ? unrelated : CApi.const_int (CApi.int1_type_in_context (context), mode == 54 ? 0 : 1, 0);
			var no = CApi.const_int (CApi.int1_type_in_context (context), mode == 55 ? 1 : 0, 0);
			CApi.add_incoming (selected, &yes, &transferred, 1);
			CApi.add_incoming (selected, &no, &retained, 1);
			CApi.build_cond_br (builder, selected, stored_cleanup, original_cleanup);
			at (stored_cleanup);
			var loaded = CApi.build_load (builder, pointer, slot, "stored.owner");
			if (mode != 56) {
				release (loaded);
			}
			CApi.build_br (builder, done);
			at (original_cleanup);
			release (owner);
			CApi.build_br (builder, done);
			at (done);
			finish ();
			return;
		}
		if (mode >= 32) {
			var owner = allocate (mode);
			CApi.TypeRef layout = pointer;
			CApi.ValueRef slot;
			if (mode == 33 || mode == 36 || mode == 43 || mode == 47 || mode == 48 || mode == 52) {
				layout = CApi.struct_create_named (context, "local.carrier");
				CApi.TypeRef[] fields = {
					pointer, pointer
				};
				CApi.struct_set_body (layout, fields, 2, 0);
			}
			var local = CApi.build_alloca (builder, layout, "owner.storage");
			slot = (void*) layout == (void*) pointer ? local : CApi.build_struct_gep (builder, layout, local, 0, "owner.field");
			if (mode == 42) {
				var stored = block ("store");
				var joined = block ("join");
				CApi.build_cond_br (builder, condition, stored, joined);
				at (stored);
				CApi.build_store (builder, owner, slot);
				CApi.build_br (builder, joined);
				at (joined);
			} else {
				CApi.build_store (builder, owner, slot);
			}
			if (mode == 33) {
				slot = CApi.build_struct_gep (builder, layout, local, 0, "same.physical.field");
			}
			if (mode == 37) {
				CApi.build_load (builder, word, owner, "invalid.pretransfer.owner");
			}
			if (mode == 40) {
				CApi.build_store (builder, CApi.get_param (function, 1), slot);
			}
			if (mode == 41) {
				var escape = declare ("escape.storage", CApi.void_type_in_context (context), new CApi.TypeRef[] { pointer });
				call (escape, new CApi.ValueRef[] { local });
			}
			if (mode == 43) {
				CApi.build_store (builder, CApi.const_int (size, 0, 0), slot);
			}
			if (mode == 44) {
				CApi.build_store (builder, CApi.const_null (pointer), slot);
			}
			if (mode == 45) {
				CApi.build_store (builder, owner, slot);
			}
			if (mode == 47) {
				CApi.build_load (builder, layout, local, "invalid.whole.carrier");
			}
			if (mode == 48) {
				var projected = CApi.build_gep (builder, pointer, slot, &condition, 1, "invalid.dynamic.address");
				CApi.build_load (builder, pointer, projected, "invalid.dynamic.read");
			}
			var loaded = CApi.build_load (builder, pointer, slot, "stored.owner");
			if (mode == 34) {
				CApi.build_store (builder, CApi.const_null (pointer), slot);
			}
			if (mode == 35) {
				var second = CApi.build_alloca (builder, pointer, "second.storage");
				CApi.build_store (builder, loaded, second);
				CApi.build_store (builder, CApi.const_null (pointer), slot);
				loaded = CApi.build_load (builder, pointer, second, "second.owner");
			}
			if (mode == 49) {
				var second = CApi.build_alloca (builder, pointer, "second.storage");
				CApi.build_store (builder, loaded, second);
				CApi.build_load (builder, pointer, slot, "invalid.moved.slot");
				release (CApi.build_load (builder, pointer, second, "second.owner"));
				finish ();
				return;
			}
			if (mode == 50) {
				release (CApi.build_load (builder, pointer, slot, "duplicate.loaded.owner"));
			}
			if (mode == 51) {
				var next = block ("nullable.done");
				var present = block ("nullable.live");
				CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.NE, loaded, CApi.const_null (pointer), "present"), present, next);
				at (present);
				release (loaded);
				CApi.build_br (builder, next);
				at (next);
				finish ();
				return;
			}
			if (mode == 52) {
				var other = CApi.build_struct_gep (builder, layout, local, 1, "different.physical.field");
				CApi.build_store (builder, loaded, other);
				release (CApi.build_load (builder, pointer, slot, "invalid.old.field"));
				release (CApi.build_load (builder, pointer, other, "new.field"));
				finish ();
				return;
			}
			if (mode == 36) {
				var second = allocate (mode);
				var field = CApi.build_struct_gep (builder, layout, local, 1, "second.field");
				CApi.build_store (builder, second, field);
				release (CApi.build_load (builder, pointer, field, "second.owner"));
			}
			if (mode != 38) {
				release (loaded);
			}
			if (mode == 39) {
				CApi.build_load (builder, pointer, slot, "invalid.retired.slot");
			}
			if (mode == 46) {
				var alias = CApi.build_alloca (builder, pointer, "invalid.slot.alias");
				CApi.build_store (builder, slot, alias);
			}
			finish ();
			return;
		}
		if (mode == 31) {
			var owner = allocate (mode);
			var entry = CApi.insert_block (builder);
			var body = block ("loop");
			var end = block ("end");
			CApi.build_br (builder, body);
			at (body);
			var stable = CApi.build_phi (builder, pointer, "stable.loop.owner");
			CApi.add_incoming (stable, &owner, &entry, 1);
			CApi.add_incoming (stable, &owner, &body, 1);
			CApi.build_load (builder, word, stable, "stable.loop.read");
			CApi.build_cond_br (builder, condition, body, end);
			at (end);
			release (owner);
			finish ();
			return;
		}
		if (mode == 30) {
			var entry = CApi.insert_block (builder);
			var body = block ("loop");
			var end = block ("end");
			CApi.build_br (builder, body);
			at (body);
			var prior = CApi.build_phi (builder, pointer, "prior.generation");
			var fresh = allocate (mode);
			var zero = CApi.const_null (pointer);
			CApi.add_incoming (prior, &zero, &entry, 1);
			CApi.add_incoming (prior, &fresh, &body, 1);
			CApi.build_load (builder, word, prior, "invalid.prior.generation");
			release (fresh);
			CApi.build_cond_br (builder, condition, body, end);
			at (end);
			finish ();
			return;
		}
		if (mode == 3 || mode == 18) {
			var body = block ("loop");
			var end = block ("end");
			CApi.build_br (builder, body);
			at (body);
			var owner = allocate (mode);
			if (mode != 18) {
				release (owner);
			}
			CApi.build_cond_br (builder, condition, body, end);
			at (end);
			finish ();
			return;
		}
		if (mode == 14) {
			destroy ();
		}
		CApi.ValueRef owner;
		if (mode == 2 || mode == 24 || mode >= 27) {
			var selected = block ("selected");
			var empty = block ("empty");
			var joined = block ("joined");
			var allocated = mode == 24 ? allocate (mode) : (CApi.ValueRef) null;
			var branch = mode >= 27 ? CApi.const_int (CApi.int1_type_in_context (context), mode == 27 ? 0 : 1, 0) : condition;
			CApi.build_cond_br (builder, branch, selected, empty);
			at (selected);
			if (mode != 24) {
				allocated = allocate (mode);
			}
			CApi.build_br (builder, joined);
			at (empty);
			CApi.build_br (builder, joined);
			at (joined);
			owner = CApi.build_phi (builder, pointer, "owner");
			var zero = CApi.const_null (pointer);
			CApi.add_incoming (owner, &allocated, &selected, 1);
			CApi.add_incoming (owner, &zero, &empty, 1);
		} else {
			owner = allocate (mode);
		}
		if (mode == 25) {
			owner = CApi.build_select (builder, condition, owner, CApi.const_null (pointer), "discarded");
		}
		if (mode == 1 || mode == 2 || mode == 17 || mode == 24 || mode == 25 || mode == 27) {
			var live = block ("live");
			var end = block ("end");
			var present = mode == 17 ? condition : CApi.build_icmp (builder, CApi.IntPredicate.NE, owner, CApi.const_null (pointer), "present");
			CApi.build_cond_br (builder, present, live, end);
			at (live);
			release (owner);
			CApi.build_br (builder, end);
			at (end);
			finish ();
			return;
		}
		if (mode == 5) {
			destroy ();
		}
		if (mode == 10) {
			var slot = CApi.build_alloca (builder, pointer, "escaped");
			CApi.build_store (builder, owner, slot);
		}
		if (mode == 11) {
			CApi.build_ptr_to_int (builder, owner, size, "escaped.integer");
		}
		if (mode == 12) {
			var target = declare ("opaque", CApi.void_type_in_context (context), new CApi.TypeRef[] { pointer });
			call (target, new CApi.ValueRef[] { owner });
		}
		if (mode == 21) {
			var target = CApi.get_param (function, 1);
			string name = "astra_context17_release_origin_checked";
			CApi.set_value_name (target, name, name.length);
			CApi.TypeRef[] parameters = {
				pointer, size
			};
			var signature = CApi.function_type (word, parameters, 2, 0);
			CApi.ValueRef[] arguments = {
				owner, tag
			};
			var forged = CApi.build_call (builder, signature, target, arguments, 2, "false.retirement");
			CApi.set_instruction_call_conv (forged, CApi.CallConv.C);
		}
		if (mode == 23) {
			CApi.set_function_call_conv (release_function, CApi.CallConv.FAST);
		}
		if (mode == 4) {
			owner = CApi.build_select (builder, condition, owner, owner, "same.owner");
		}
		if (mode == 19) {
			var other = allocate (mode);
			owner = CApi.build_select (builder, condition, owner, other, "ambiguous");
		}
		if (mode == 20) {
			CApi.build_load (builder, pointer, address (owner), "hidden.owner");
		}
		if (mode == 26) {
			var constructor = CApi.named_function (module, "astra.ctor.0");
			var observation = CApi.named_function (module, "astra.class.method.0.0");
			assert ((void*) constructor != null && (void*) observation != null);
			var initialized = call (constructor, new CApi.ValueRef[] { owner, CApi.const_int (word, 7, 0) });
			CApi.set_instruction_call_conv (initialized, LlvmLowering.CALL_CONVENTION);
			var observed = call (observation, new CApi.ValueRef[] { owner }, "observed");
			CApi.set_instruction_call_conv (observed, LlvmLowering.CALL_CONVENTION);
		}
		if (mode == 0) {
			var field = address (owner);
			CApi.build_store (builder, CApi.const_int (word, 7, 0), field);
			CApi.build_load (builder, word, field, "observed");
		}
		if (mode == 28) {
			CApi.build_load (builder, word, address (owner), "constant.path");
		}
		if (mode != 6 && mode != 21 && mode != 29) {
			release (mode == 13 ? address (owner) : owner, mode == 8);
		}
		if (mode == 7) {
			release (owner);
		}
		if (mode == 9) {
			CApi.build_load (builder, word, address (owner), "stale");
		}
		finish ();
	}

	internal void verify_ir() {
		char* message;
		int failed = CApi.verify_module (module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
		string detail = message == null ? "" : (string) message;
		if (message != null) {
			CApi.dispose_message (message);
		}
		if (failed != 0) {
			error ("invalid LLVM fixture: %s", detail);
		}
	}

	internal void remove_function() {
		CApi.dispose_builder (builder);
		builder = (CApi.BuilderRef) null;
		CApi.delete_function (function);
		function = (CApi.ValueRef) null;
	}

	~ScopedLlvmFixture () {
		if ((void*) builder != null) {
			CApi.dispose_builder (builder);
		}
		if (!borrowed_module) {
			CApi.dispose_module (module);
			CApi.context_dispose (context);
		}
	}

}
internal class LlvmLifetimeTests : Object {
	internal static void record_lifecycle(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef constructor, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		CApi.delete_function (caller);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		assert (artifact.has_scoped_owned_inputs (constructor) && artifact.has_scoped_owned_inputs (destructor));
		foreach (var function in new CApi.ValueRef[] { constructor, destructor }) {
			int frees = 0, projections = 0, stores = 0;
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					var opcode = CApi.opcode (instruction);
					if (opcode == CApi.Opcode.GEP && CApi.operand_count (instruction) == 3) {
						var type = CApi.gep_source_type (instruction);
						var member = CApi.operand (instruction, 2);
						if (CApi.type_kind (type) == CApi.TypeKind.STRUCT && CApi.count_struct_element_types (type) == 3 && CApi.type_kind (CApi.struct_get_type_at_index (type, 0)) == CApi.TypeKind.POINTER && CApi.type_kind (CApi.struct_get_type_at_index (type, 1)) == CApi.TypeKind.POINTER && (void*) CApi.struct_get_type_at_index (type, 2) == (void*) CApi.int32_type_in_context (artifact.context) && (void*) CApi.is_constant_int (member) != null && CApi.const_int_zext (member) < 2) {
							CApi.set_operand (instruction, 2, CApi.const_int (CApi.type_of (member), 1 - CApi.const_int_zext (member), 0));
							valid_ir (artifact.module);
							refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed");
							CApi.set_operand (instruction, 2, member);
							projections++;
						}
					}
					bool release = LlvmScopedHeapCarrier.named_call (instruction, "free");
					bool store = opcode == CApi.Opcode.STORE;
					if (!release && !store) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					var type = CApi.type_of (original);
					if (CApi.type_kind (type) == CApi.TypeKind.POINTER && (void*) CApi.is_constant_pointer_null (original) == null) {
						CApi.set_operand (instruction, 0, CApi.const_null (type));
						valid_ir (artifact.module);
						refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed");
						CApi.set_operand (instruction, 0, original);
						if (release) {
							frees++;
						} else {
							stores++;
						}
					}
				}
			}
			assert (frees >= 2 && projections >= 2);
			if ((void*) function == (void*) constructor) {
				assert (stores >= 2);
			}
		}
		artifact.verify_scoped_allocations ();
	}

	internal static void record_child_paths(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef constructor, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		CApi.delete_function (caller);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		assert (artifact.has_scoped_owned_inputs (constructor) && artifact.has_scoped_owned_inputs (destructor));
		foreach (var function in new CApi.ValueRef[] { constructor, destructor }) {
			int projections = 0, transfers = 0;
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					var opcode = CApi.opcode (instruction);
					if (opcode == CApi.Opcode.GEP && CApi.operand_count (instruction) == 3) {
						var type = CApi.gep_source_type (instruction);
						var member = CApi.operand (instruction, 2);
						if (CApi.type_kind (type) == CApi.TypeKind.STRUCT && CApi.count_struct_element_types (type) == 3 && CApi.type_kind (CApi.struct_get_type_at_index (type, 0)) == CApi.TypeKind.POINTER && CApi.type_kind (CApi.struct_get_type_at_index (type, 1)) == CApi.TypeKind.POINTER && (void*) CApi.is_constant_int (member) != null && CApi.const_int_zext (member) < 2) {
							CApi.set_operand (instruction, 2, CApi.const_int (CApi.type_of (member), 1 - CApi.const_int_zext (member), 0));
							valid_ir (artifact.module);
							refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed", "original owner load", "field transfer");
							CApi.set_operand (instruction, 2, member);
							projections++;
						}
					}
					bool release = LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked");
					if (!release && opcode != CApi.Opcode.STORE) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					if (CApi.type_kind (CApi.type_of (original)) != CApi.TypeKind.POINTER || (void*) CApi.is_constant_pointer_null (original) != null) {
						continue;
					}
					CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (original)));
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed", "field transfer", "input or initialized field");
					CApi.set_operand (instruction, 0, original);
					transfers++;
				}
			}
			assert (projections >= 2 && transfers >= 2);
		}
		artifact.verify_scoped_allocations ();
	}

	internal static void buffer_storage(LlvmModuleArtifact artifact, CApi.ValueRef constructor, CApi.ValueRef destructor, bool aggregate_required) throws GLib.Error {
		artifact.verify ();
		int accesses = 0, aggregates = 0;
		foreach (var function in new CApi.ValueRef[] { constructor, destructor }) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					var opcode = CApi.opcode (instruction);
					if (opcode != CApi.Opcode.STORE && opcode != CApi.Opcode.LOAD) {
						continue;
					}
					var type = opcode == CApi.Opcode.LOAD ? CApi.type_of (instruction) : CApi.type_of (CApi.operand (instruction, 0));
					var address = CApi.operand (instruction, opcode == CApi.Opcode.LOAD ? 0 : 1);
					if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.GEP || CApi.operand_count (address) != 3) {
						continue;
					}
					bool aggregate = CApi.type_kind (type) == CApi.TypeKind.STRUCT;
					if (!aggregate) {
						address = CApi.operand (address, 0);
					}
					if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.GEP || CApi.operand_count (address) != 3 || (void*) CApi.operand (address, 0) != (void*) CApi.get_param (function, 0)) {
						continue;
					}
					var member = CApi.operand (address, 2);
					uint64 field = CApi.const_int_zext (member);
					if (field != 1 && field != 2) {
						continue;
					}
					var pair_type = CApi.struct_get_type_at_index (CApi.gep_source_type (address), (uint) field);
					assert (CApi.type_kind (pair_type) == CApi.TypeKind.STRUCT && CApi.count_struct_element_types (pair_type) == 2);
					accesses++;
					if (aggregate) {
						aggregates++;
					}
					CApi.set_operand (address, 2, CApi.const_int (CApi.type_of (member), field == 1 ? 2 : 1, 0));
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed");
					CApi.set_operand (address, 2, member);
					CApi.set_volatile (instruction, 1);
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "scalar accesses", "owning sum effect changed");
					CApi.set_volatile (instruction, 0);
					if (aggregate && opcode == CApi.Opcode.STORE) {
						var original = CApi.operand (instruction, 0);
						CApi.ValueRef[] leaves = {
							CApi.const_null (CApi.struct_get_type_at_index (type, 0)), CApi.const_int (CApi.struct_get_type_at_index (type, 1), 1001, 0)
						};
						var replacement = CApi.const_struct (artifact.context, leaves, leaves.length, 0);
						assert ((void*) replacement != (void*) original);
						CApi.set_operand (instruction, 0, replacement);
						valid_ir (artifact.module);
						refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed");
						CApi.set_operand (instruction, 0, original);
					}
				}
			}
		}
		assert (accesses >= 4 && (!aggregate_required || aggregates >= 2));
		artifact.verify ();
	}

	internal static void buffer_constructor(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef constructor, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef call = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) constructor) {
					assert ((void*) call == null);
					call = instruction;
				}
			}
		}
		assert ((void*) call != null && CApi.argument_count (call) == 7);
		// Both complete pairs retain their exact physical call channels.
		for (uint p = 2; p <= 5; p++) {
			var original = CApi.operand (call, p);
			var replacement = CApi.operand (call, p < 4 ? p + 2 : p - 2);
			assert ((void*) original != (void*) replacement);
			CApi.set_operand (call, p, replacement);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify (), "intended receiver/input/success/cleanup channel");
			CApi.set_operand (call, p, original);
		}
		// Remove the caller: body controls depend on the copied typed contract
		// and actual emitted constructor/destructor seals alone.
		CApi.delete_function (caller);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		assert (artifact.has_scoped_owned_inputs (constructor) && artifact.has_scoped_owned_inputs (destructor));
		foreach (var body in new CApi.ValueRef[] { constructor, destructor }) {
			int pointers = 0, lengths = 0, frees = 0;
			for (var block = CApi.first_block (body); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					bool release = LlvmScopedHeapCarrier.named_call (instruction, "free");
					bool store = CApi.opcode (instruction) == CApi.Opcode.STORE;
					if (!release && !store) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					var kind = CApi.type_kind (CApi.type_of (original));
					bool pointer = kind == CApi.TypeKind.POINTER && (void*) CApi.is_constant_pointer_null (original) == null;
					bool length = store && kind == CApi.TypeKind.INTEGER && (void*) CApi.type_of (original) == (void*) CApi.int32_type_in_context (artifact.context) && (void*) CApi.is_constant_int (original) == null;
					if (!pointer && !length) {
						continue;
					}
					CApi.set_operand (instruction, 0, pointer ? CApi.const_null (CApi.type_of (original)) : CApi.const_int (CApi.type_of (original), 1001, 0));
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed", "producer/store/call/read publication order");
					CApi.set_operand (instruction, 0, original);
					if (release) {
						frees++;
					} else if (pointer) {
						pointers++;
					} else {
						lengths++;
					}
				}
			}
			assert (frees >= 2);
			if ((void*) body == (void*) constructor) {
				assert (pointers >= 2 && lengths >= 2);
			}
		}
		artifact.verify_scoped_allocations ();
	}

	internal static void constructor_stack(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef constructor, int capacity, bool heap_children = false) throws GLib.Error {
		artifact.verify ();
		// Remove the only caller. Callee mutations below must be rejected by
		// reconstructed ownership/stack effects, independently of its call seal.
		CApi.delete_function (caller);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		assert (artifact.has_scoped_owned_inputs (constructor));
		var word = CApi.int32_type_in_context (artifact.context);
		var array = CApi.array_type (word, capacity);
		CApi.ValueRef count = (CApi.ValueRef) null, stack = (CApi.ValueRef) null, initial = (CApi.ValueRef) null, push = (CApi.ValueRef) null, pop = (CApi.ValueRef) null, address = (CApi.ValueRef) null;
		var releases = new GenericArray<void*> ();
		var stores = new GenericArray<void*> ();
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				var opcode = CApi.opcode (instruction);
				if (opcode == CApi.Opcode.ALLOCA) {
					if ((void*) CApi.allocated_type (instruction) == (void*) word) {
						count = instruction;
					}
					if ((void*) CApi.allocated_type (instruction) == (void*) array) {
						stack = instruction;
					}
				}
				if (opcode == CApi.Opcode.ADD && (void*) CApi.type_of (instruction) == (void*) word) {
					push = instruction;
				}
				if (opcode == CApi.Opcode.SUB && (void*) CApi.type_of (instruction) == (void*) word) {
					pop = instruction;
				}
				if (opcode == CApi.Opcode.GEP && (void*) CApi.gep_source_type (instruction) == (void*) array) {
					address = instruction;
				}
				if (opcode == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) count && (void*) CApi.is_constant_int (CApi.operand (instruction, 0)) != null && CApi.const_int_zext (CApi.operand (instruction, 0)) == 0) {
					initial = instruction;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, heap_children ? "free" : "astra_context17_release_origin_checked")) {
					var input = CApi.operand (instruction, 0);
					bool parameter = (void*) input == (void*) CApi.get_param (constructor, 1) || (void*) input == (void*) CApi.get_param (constructor, 2);
					bool loaded = (void*) CApi.is_instruction (input) != null && CApi.opcode (input) == CApi.Opcode.LOAD;
					if (loaded) {
						var source = CApi.operand (input, 0);
						loaded = (void*) CApi.is_instruction (source) != null && CApi.opcode (source) == CApi.Opcode.GEP && (void*) CApi.operand (source, 0) == (void*) CApi.get_param (constructor, 0);
					}
					if (parameter || loaded) {
						releases.add ((void*) instruction);
					}
				}
				if (opcode == CApi.Opcode.STORE && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.POINTER && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					var target = CApi.operand (instruction, 1);
					if ((void*) CApi.is_instruction (target) != null && CApi.opcode (target) == CApi.Opcode.GEP && (void*) CApi.operand (target, 0) == (void*) CApi.get_param (constructor, 0)) {
						stores.add ((void*) instruction);
					}
				}
			}
		}
		assert ((void*) count != null && (void*) stack != null && (void*) initial != null && (void*) push != null && (void*) pop != null && (void*) address != null && releases.length >= 4 && stores.length == 2);
		// Every exceptional prefix emits every field case. Mutate the final
		// full-prefix field cases; earlier uninitialized cases are unreachable.
		var active_releases = new GenericArray<void*> ();
		for (int i = 0; i < releases.length; i++) {
			if (i < 2 || i >= releases.length - 2) {
				active_releases.add (releases[i]);
			}
		}
		foreach (void* item in active_releases) {
			var release = (CApi.ValueRef) item;
			var value = CApi.operand (release, 0);
			CApi.set_operand (release, 0, CApi.const_null (CApi.type_of (value)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "input or initialized field", "unretired scoped allocation", "live owner");
			CApi.set_operand (release, 0, value);
		}
		foreach (void* item in stores) {
			var store = (CApi.ValueRef) item;
			var value = CApi.operand (store, 0);
			CApi.set_operand (store, 0, CApi.const_null (CApi.type_of (value)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "field transfer", "owner load", "input or initialized field");
			CApi.set_operand (store, 0, value);
		}
		var zero = CApi.operand (initial, 0);
		CApi.set_operand (initial, 0, CApi.const_int (word, capacity + 1, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "stack count lacks its proven native bound");
		CApi.set_operand (initial, 0, zero);
		var one = CApi.operand (push, 1);
		CApi.set_operand (push, 1, CApi.const_int (word, 0, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "input or initialized field", "unretired scoped allocation");
		CApi.set_operand (push, 1, one);
		one = CApi.operand (pop, 1);
		CApi.set_operand (pop, 1, CApi.const_int (word, 0, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "owner load", "live owner", "proven current bound");
		CApi.set_operand (pop, 1, one);
		zero = CApi.operand (address, 1);
		CApi.set_operand (address, 1, CApi.const_int (word, 1, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "original bounded address");
		CApi.set_operand (address, 1, zero);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, initial);
		var escape = declaration (artifact, "escape.constructor.stack", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { CApi.type_of (stack) });
		CApi.ValueRef[] args = {
			stack
		};
		var escaped = CApi.build_call (builder, CApi.global_value_type (escape), escape, args, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "original bounded address");
		CApi.erase_instruction (escaped);
		CApi.delete_function (escape);
		CApi.dispose_builder (builder);
		artifact.verify_scoped_allocations ();
	}

	internal static void constructor_graph_cleanup(LlvmModuleArtifact artifact, CApi.ValueRef constructor, CApi.ValueRef destructor, CApi.ValueRef touch, bool heap_children = false) throws GLib.Error {
		// constructor_stack removed the only caller. These replacements keep
		// valid LLVM and a real neutral borrowed callee, but lose graph cleanup.
		// Skip already-empty parameter PHIs on the successful constructor exit.
		var cleanups = new GenericArray<void*> ();
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) destructor) {
					var input = CApi.operand (instruction, 0);
					bool parameter = (void*) input == (void*) CApi.get_param (constructor, 1) || (void*) input == (void*) CApi.get_param (constructor, 2);
					bool field = (void*) CApi.is_instruction (input) != null && CApi.opcode (input) == CApi.Opcode.LOAD;
					if (field) {
						var address = CApi.operand (input, 0);
						field = (void*) CApi.is_instruction (address) != null && CApi.opcode (address) == CApi.Opcode.GEP && (void*) CApi.operand (address, 0) == (void*) CApi.get_param (constructor, 0);
					}
					if (parameter || field) {
						cleanups.add ((void*) instruction);
					}
				}
			}
		}
		assert (cleanups.length >= 4 && (void*) CApi.global_value_type (destructor) == (void*) CApi.global_value_type (touch));
		for (int c = 0; c < cleanups.length; c++) {
			if (c >= 2 && c < cleanups.length - 2) {
				continue;
			}
			var call = (CApi.ValueRef) cleanups[c];
			uint target = CApi.operand_count (call) - 1;
			CApi.set_operand (call, target, touch);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its delegated child cleanup", "exact child obligation");
			CApi.set_operand (call, target, destructor);
		}
		for (int c = 0; c < 2; c++) {
			var call = (CApi.ValueRef) cleanups[c];
			var input = CApi.operand (call, 0);
			CApi.set_operand (call, 0, CApi.get_param (constructor, (void*) input == (void*) CApi.get_param (constructor, 1) ? 2 : 1));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its delegated child cleanup", "exact live child obligation", "exact live owner");
			CApi.set_operand (call, 0, input);
		}
		var cleanup = (CApi.ValueRef) cleanups[0];
		var owner = CApi.operand (cleanup, 0);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, cleanup);
		if (heap_children) {
			var runtime = CApi.named_function (artifact.module, "astra_context17_release_origin_checked");
			CApi.ValueRef[] arguments = {
				owner, CApi.const_int (CApi.int_type_in_context (artifact.context, 64), 77, 0)
			};
			var wrong = CApi.build_call (builder, CApi.global_value_type (runtime), runtime, arguments, 2, "wrong.heap.retirement");
			CApi.set_instruction_call_conv (wrong, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "default heap graph cannot retire through a context operation");
			CApi.erase_instruction (wrong);
		}
		var source = declaration (artifact, "unknown.deep.cleanup.condition", CApi.int1_type_in_context (artifact.context), new CApi.TypeRef[] {});
		CApi.ValueRef[] none = {};
		var condition = CApi.build_call (builder, CApi.global_value_type (source), source, none, 0, "unknown.deep.cleanup");
		CApi.set_instruction_call_conv (condition, CApi.CallConv.C);
		var selected = CApi.build_select (builder, condition, owner, CApi.const_null (CApi.type_of (owner)), "discarded.deep.cleanup");
		CApi.set_operand (cleanup, 0, selected);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation absence");
		CApi.set_operand (cleanup, 0, owner);
		CApi.erase_instruction (selected);
		CApi.erase_instruction (condition);
		CApi.delete_function (source);
		CApi.dispose_builder (builder);
		artifact.verify_scoped_allocations ();
	}

	internal static void constructor_prefix_unwind(LlvmModuleArtifact artifact, CApi.ValueRef constructor) throws GLib.Error {
		artifact.verify ();
		int releases = 0, fields = 0;
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				bool release = LlvmScopedHeapCarrier.named_call (instruction, "free");
				bool field = CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.POINTER;
				if (!release && !field) {
					continue;
				}
				var value = CApi.operand (instruction, 0);
				if ((void*) CApi.is_constant_pointer_null (value) != null) {
					continue;
				}
				CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (value)));
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed", "producer/store/call/read publication order");
				CApi.set_operand (instruction, 0, value);
				if (release) {
					releases++;
				} else {
					fields++;
				}
			}
		}
		assert (releases >= 2 && fields >= 2);
		artifact.verify ();
	}

	internal static void constructor_rollback(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef constructor, bool field_receiver = false) throws GLib.Error {
		artifact.verify ();
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) != CApi.Opcode.SWITCH || CApi.successor_count (end) < 2) {
				continue;
			}
			var original = CApi.switch_case_value (end, 1);
			CApi.set_switch_case_value (end, 1, CApi.const_int (CApi.type_of (original), 1001, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed its exact switch case value");
			CApi.set_switch_case_value (end, 1, original);
		}
		CApi.ValueRef call = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) constructor) {
					assert ((void*) call == null);
					call = instruction;
				}
			}
		}
		assert ((void*) call != null);
		var branch = CApi.block_terminator (CApi.instruction_parent (call));
		assert (CApi.opcode (branch) == CApi.Opcode.COND_BR && CApi.successor_count (branch) == 2);
		var condition = CApi.operand (branch, 0);
		assert (CApi.opcode (condition) == CApi.Opcode.ICMP && (void*) CApi.operand (condition, 0) == (void*) call);
		var failure = CApi.successor (branch, 1);
		var retirement = CApi.block_terminator (failure);
		assert (CApi.opcode (retirement) == CApi.Opcode.COND_BR && CApi.successor_count (retirement) == 2);
		failure = CApi.successor (retirement, 1);
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var instruction = CApi.first_instruction (failure); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
				assert ((void*) release == null);
				release = instruction;
			}
		}
		assert ((void*) release != null);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var owner = CApi.operand (release, 0);
		var tag = CApi.operand (release, 1);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.set_operand (release, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation", "unretired scoped allocation", "exact live owner");
		CApi.set_operand (release, 0, owner);
		CApi.set_operand (release, 1, CApi.const_int (CApi.type_of (tag), 77, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation tag", "retirement ABI or allocation tag");
		CApi.set_operand (release, 1, tag);
		CApi.position_builder_before (builder, CApi.next_instruction (release));
		CApi.ValueRef[] arguments = {
			owner, tag
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), arguments, 2, "duplicate.rollback");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner", "exact live backing");
		CApi.erase_instruction (duplicate);
		CApi.set_operand (condition, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation", "unretired scoped allocation", "exact live owner");
		CApi.set_operand (condition, 0, call);
		var receiver = CApi.operand (call, 0);
		CApi.set_operand (call, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation or borrowed origin", "actual tracked allocation", "nonescaping local carrier");
		CApi.set_operand (call, 0, receiver);
		CApi.position_builder_before (builder, call);
		var unknown_target = declaration (artifact, "unknown.constructor.condition", CApi.int1_type_in_context (artifact.context), new CApi.TypeRef[] {});
		CApi.ValueRef[] none = {};
		var unknown = CApi.build_call (builder, CApi.global_value_type (unknown_target), unknown_target, none, 0, "unknown.constructor.test");
		CApi.set_instruction_call_conv (unknown, CApi.CallConv.C);
		var discarded = CApi.build_select (builder, unknown, receiver, CApi.const_null (pointer), "discarded.constructor.receiver");
		CApi.set_operand (call, 0, discarded);
		if (!field_receiver) {
			CApi.set_operand (discarded, 0, CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0));
			valid_ir (artifact.module);
			artifact.verify_scoped_allocations ();
			CApi.set_operand (discarded, 0, unknown);
		}
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation absence", "exact live pointer", "nonescaping local carrier");
		CApi.set_operand (call, 0, receiver);
		CApi.erase_instruction (discarded);
		CApi.erase_instruction (unknown);
		CApi.delete_function (unknown_target);
		CApi.position_builder_before (builder, CApi.next_instruction (release));
		var stale = CApi.build_load (builder, CApi.int32_type_in_context (artifact.context), owner, "stale.failed.candidate");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner", "exact live backing", "exact ordinary scalar accesses");
		CApi.erase_instruction (stale);
		uint convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact ownership effect", "before its derived allocation", "scoped field call lost its exact physical signature");
		CApi.set_instruction_call_conv (call, convention);
		CApi.ValueRef stored = (CApi.ValueRef) null;
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.INTEGER) {
					stored = instruction;
					break;
				}
			}
			if ((void*) stored != null) {
				break;
			}
		}
		assert ((void*) stored != null);
		var value = CApi.operand (stored, 0);
		CApi.set_operand (stored, 0, CApi.const_int (CApi.type_of (value), 71, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed", "producer/store/call/read publication order");
		CApi.set_operand (stored, 0, value);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void graph_consumer(LlvmModuleArtifact artifact, CApi.ValueRef consumer, CApi.ValueRef touch) throws GLib.Error {
		artifact.verify ();
		var destructor = CApi.named_function (artifact.module, "astra.dtor.1");
		var cleanups = new GenericArray<void*> ();
		var releases = new GenericArray<void*> ();
		var owners = new GenericArray<void*> ();
		for (var block = CApi.first_block (consumer); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if ((void*) CApi.called_value (instruction) == (void*) destructor && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					cleanups.add ((void*) instruction);
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked") && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					releases.add ((void*) instruction);
					owners.add ((void*) CApi.operand (instruction, 0));
				}
			}
		}
		assert (cleanups.length != 0 && releases.length != 0);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (void* address in cleanups) {
			var call = (CApi.ValueRef) address;
			CApi.set_operand (call, CApi.operand_count (call) - 1, touch);
		}
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its delegated child cleanup", "exact child obligation");
		foreach (void* address in cleanups) {
			var call = (CApi.ValueRef) address;
			CApi.set_operand (call, CApi.operand_count (call) - 1, destructor);
		}
		// The early null return also emits unreachable cleanup arms.
		// Target the final nonnull return for single-site mutations.
		var cleanup = (CApi.ValueRef) cleanups[cleanups.length - 1];
		var release = (CApi.ValueRef) releases[releases.length - 1];
		CApi.position_builder_before (builder, cleanup);
		CApi.ValueRef[] disposed = {
			CApi.operand (cleanup, 0)
		};
		var duplicate = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, disposed, 1, "");
		CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live child obligation");
		CApi.erase_instruction (duplicate);
		CApi.position_builder_before (builder, cleanup);
		var runtime = CApi.called_value (release);
		CApi.ValueRef[] retired = {
			CApi.operand (cleanup, 0), CApi.operand (release, 1)
		};
		var early = CApi.build_call (builder, CApi.global_value_type (runtime), runtime, retired, 2, "early.parent.retirement");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its delegated child cleanup");
		CApi.erase_instruction (early);
		foreach (void* address in releases) {
			CApi.set_operand ((CApi.ValueRef) address, 0, CApi.const_null (pointer));
		}
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		foreach (void* address in cleanups) {
			var call = (CApi.ValueRef) address;
			CApi.set_operand (call, CApi.operand_count (call) - 1, touch);
		}
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact child obligation");
		foreach (void* address in cleanups) {
			var call = (CApi.ValueRef) address;
			CApi.set_operand (call, CApi.operand_count (call) - 1, destructor);
		}
		for (int r = 0; r < releases.length; r++) {
			CApi.set_operand ((CApi.ValueRef) releases[r], 0, (CApi.ValueRef) owners[r]);
		}
		CApi.position_builder_before (builder, release);
		retired[0] = CApi.operand (release, 0);
		var repeated = CApi.build_call (builder, CApi.global_value_type (runtime), runtime, retired, 2, "duplicate.parent.retirement");
		CApi.set_instruction_call_conv (repeated, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (repeated);
		var tag = CApi.operand (release, 1);
		CApi.set_operand (release, 1, CApi.const_int (CApi.type_of (tag), 77, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation tag");
		CApi.set_operand (release, 1, tag);
		uint convention = CApi.function_call_conv (consumer);
		CApi.set_function_call_conv (consumer, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact physical signature");
		CApi.set_function_call_conv (consumer, convention);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void graph_consumer_caller(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef consumer) throws GLib.Error {
		artifact.verify ();
		var allocations = new GenericArray<void*> ();
		CApi.ValueRef call = (CApi.ValueRef) null;
		CApi.ValueRef constructed = (CApi.ValueRef) null;
		var constructor = CApi.named_function (artifact.module, "astra.ctor.1");
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocations.add ((void*) instruction);
				}
				if ((void*) CApi.called_value (instruction) == (void*) consumer) {
					call = instruction;
				}
				if ((void*) CApi.called_value (instruction) == (void*) constructor) {
					constructed = instruction;
				}
			}
		}
		assert (allocations.length == 3 && (void*) call != null && (void*) constructed != null);
		var allocation = (CApi.ValueRef) allocations[2];
		var owner = CApi.operand (call, 0);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (var value in new CApi.ValueRef[] { CApi.const_null (pointer), CApi.operand (allocation, 0), CApi.operand (constructed, 2) }) {
			CApi.set_operand (call, 0, value);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "derived allocation", "actual tracked allocation", "original field carrier");
			CApi.set_operand (call, 0, owner);
		}
		var global = CApi.add_global (artifact.module, word, "unproved.consumer.owner");
		CApi.set_initializer (global, CApi.const_int (word, 7, 0));
		CApi.set_operand (call, 0, global);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual tracked allocation");
		CApi.set_operand (call, 0, owner);
		CApi.delete_global (global);
		CApi.position_builder_before (builder, call);
		var condition_source = declaration (artifact, "unproved.consume.condition", CApi.int1_type_in_context (artifact.context), new CApi.TypeRef[] {});
		CApi.ValueRef[] none = {};
		var condition = CApi.build_call (builder, CApi.global_value_type (condition_source), condition_source, none, 0, "unknown.consumer.condition");
		CApi.set_instruction_call_conv (condition, CApi.CallConv.C);
		var discarded = CApi.build_select (builder, condition, owner, CApi.const_null (pointer), "discarded.consumer.owner");
		CApi.set_operand (call, 0, discarded);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "original field carrier", "exact allocation absence");
		CApi.set_operand (call, 0, owner);
		CApi.erase_instruction (discarded);
		CApi.erase_instruction (condition);
		CApi.delete_function (condition_source);
		CApi.position_builder_before (builder, call);
		CApi.ValueRef[] moved = {
			owner
		};
		var duplicate = CApi.build_call (builder, CApi.global_value_type (consumer), consumer, moved, 1, "duplicate.graph.consumption");
		CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing", "exact live owner");
		CApi.erase_instruction (duplicate);
		CApi.position_builder_before (builder, CApi.next_instruction (call));
		var method = CApi.named_function (artifact.module, "astra.class.method.1.0");
		var stale = CApi.build_call (builder, CApi.global_value_type (method), method, moved, 1, "stale.consumed.parent");
		CApi.set_instruction_call_conv (stale, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing", "exact live owner");
		CApi.erase_instruction (stale);
		CApi.position_builder_before (builder, call);
		var destructor = CApi.named_function (artifact.module, "astra.dtor.1");
		var early = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, moved, 1, "");
		CApi.set_instruction_call_conv (early, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live child owner", "exact live backing", "exact live owner");
		CApi.erase_instruction (early);
		CApi.position_builder_before (builder, call);
		var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
		CApi.ValueRef[] closed = {
			CApi.operand (allocation, 0)
		};
		early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, closed, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation", "exact live loan");
		CApi.erase_instruction (early);
		uint convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact type, extent, alignment, tag or transfer channel");
		CApi.set_instruction_call_conv (call, convention);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void nullable_owned_arguments(LlvmModuleArtifact artifact, CApi.ValueRef target) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_owned_inputs (target));
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocation = instruction;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					release = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var tag = new LlvmPolicyAllocation (artifact).tag ("Leaf", "object");
		CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (CApi.operand (allocation, 2)), 4, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (CApi.type_of (CApi.operand (allocation, 3)), 4, 0));
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 1, tag);
		var owner = CApi.operand (release, 0);
		CApi.set_operand (release, 0, CApi.const_null (pointer));
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, release);
		CApi.ValueRef[] arguments = {
			owner
		};
		var consumed = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, 1, "consumed");
		CApi.set_instruction_call_conv (consumed, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, consumed);
		var discarded = CApi.build_select (builder, CApi.get_param (caller, 0), owner, CApi.const_null (pointer), "discarded.live.owner");
		CApi.set_operand (consumed, 0, discarded);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation absence");
		CApi.set_operand (discarded, 0, CApi.const_int (CApi.int1_type_in_context (artifact.context), 0, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation absence");
		CApi.set_operand (discarded, 0, CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (consumed, 0, owner);
		CApi.erase_instruction (discarded);
		CApi.erase_instruction (consumed);
		CApi.position_builder_before (builder, release);
		discarded = CApi.build_select (builder, CApi.get_param (caller, 0), owner, CApi.const_null (pointer), "discarded.retirement.owner");
		CApi.set_operand (release, 0, discarded);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation absence");
		CApi.set_operand (discarded, 0, CApi.const_int (CApi.int1_type_in_context (artifact.context), 0, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation absence");
		CApi.set_operand (discarded, 0, CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (release, 0, owner);
		CApi.erase_instruction (discarded);
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		artifact.verify ();
	}

	internal static void fresh_graph_results(LlvmModuleArtifact artifact, CApi.ValueRef target, CApi.ValueRef caller, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_fresh_result (target));
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.ValueRef publication = (CApi.ValueRef) null, call = (CApi.ValueRef) null, cleanup = (CApi.ValueRef) null, tag = (CApi.ValueRef) null;
		for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) == CApi.Opcode.RET) {
				assert ((void*) publication == null);
				publication = end;
			}
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode") && (void*) CApi.operand (instruction, 0) == (void*) CApi.get_param (target, 0)) {
					tag = CApi.operand (instruction, 4);
				}
			}
		}
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if ((void*) CApi.called_value (instruction) == (void*) target) {
					assert ((void*) call == null);
					call = instruction;
				}
				if ((void*) CApi.called_value (instruction) == (void*) destructor) {
					assert ((void*) cleanup == null);
					cleanup = instruction;
				}
			}
		}
		assert ((void*) publication != null && (void*) call != null && (void*) cleanup != null && (void*) tag != null);
		var destroy = declaration (artifact, "astra_context17_destroy", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		var release = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		// Each context is independently protected after the graph publication.
		for (uint p = 0; p < 2; p++) {
			CApi.position_builder_before (builder, CApi.next_instruction (call));
			CApi.ValueRef[] arguments = {
				CApi.operand (call, p)
			};
			var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, arguments, 1, "");
			CApi.set_instruction_call_conv (early, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.erase_instruction (early);
		}
		CApi.position_builder_before (builder, cleanup);
		CApi.ValueRef[] retired = {
			CApi.operand (cleanup, 0), tag
		};
		var early_release = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "invalid.graph.backing.retirement");
		CApi.set_instruction_call_conv (early_release, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "backing retired before its delegated child cleanup");
		CApi.erase_instruction (early_release);
		var root = CApi.operand (cleanup, 0);
		CApi.set_operand (cleanup, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "lifecycle receiver requires its actual tracked allocation", "backing retired before its delegated child cleanup");
		CApi.set_operand (cleanup, 0, root);
		var result = CApi.operand (publication, 0);
		CApi.set_operand (publication, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation", "unretired heap carrier");
		CApi.set_operand (publication, 0, result);
		var global = CApi.add_global (artifact.module, word, "invalid.fresh.graph.global");
		CApi.set_initializer (global, CApi.const_int (word, 17, 0));
		CApi.set_operand (publication, 0, global);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "fresh scoped return lost");
		CApi.set_operand (publication, 0, result);
		CApi.delete_global (global);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void fresh_results(LlvmModuleArtifact artifact, CApi.ValueRef target) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_fresh_result (target) && artifact.has_scoped_context_inputs (target));
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef returned = (CApi.ValueRef) null;
		for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) == CApi.Opcode.RET) {
				assert ((void*) returned == null);
				returned = end;
			}
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					assert ((void*) allocation == null);
					allocation = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) returned != null);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var builder = CApi.create_builder_in_context (artifact.context);
		var result = CApi.operand (returned, 0);
		var tag = CApi.operand (allocation, 4);
		for (uint p = 1; p <= 5; p++) {
			var original = CApi.operand (allocation, p);
			CApi.set_operand (allocation, p, CApi.const_int (CApi.type_of (original), p == 1 || p == 5 ? 2 : p == 4 ? 77 : CApi.const_int_zext (original) * 2, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), p == 5 ? "exact affine mode" : "exact Class allocation shape");
			CApi.set_operand (allocation, p, original);
		}
		var context = CApi.operand (allocation, 0);
		CApi.set_operand (allocation, 0, CApi.get_param (target, 1));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "ownership effect", "fresh scoped return");
		CApi.set_operand (allocation, 0, context);
		CApi.set_operand (returned, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (returned, 0, result);
		CApi.set_operand (returned, 0, CApi.get_param (target, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "borrowed scoped context escaped");
		CApi.set_operand (returned, 0, result);
		var global = CApi.add_global (artifact.module, word, "invalid.fresh.global");
		CApi.set_initializer (global, CApi.const_int (word, 7, 0));
		CApi.set_operand (returned, 0, global);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "fresh scoped return lost");
		CApi.set_operand (returned, 0, result);
		CApi.delete_global (global);
		CApi.position_builder_before (builder, returned);
		var condition = CApi.build_icmp (builder, CApi.IntPredicate.EQ, CApi.get_param (target, 2), CApi.const_int (word, 0, 0), "invalid.fresh.discard.test");
		var discarded = CApi.build_select (builder, condition, CApi.const_null (pointer), result, "invalid.fresh.discard");
		CApi.set_operand (returned, 0, discarded);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "fresh scoped return lost");
		CApi.set_operand (returned, 0, result);
		CApi.erase_instruction (discarded);
		CApi.erase_instruction (condition);
		CApi.position_builder_before (builder, returned);
		var one = CApi.const_int (word, 1, 0);
		var interior = CApi.build_gep (builder, word, result, &one, 1, "invalid.fresh.interior");
		CApi.set_operand (returned, 0, interior);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "fresh scoped return lost", "live owner");
		CApi.set_operand (returned, 0, result);
		CApi.erase_instruction (interior);
		var release = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		CApi.position_builder_before (builder, returned);
		CApi.ValueRef[] retired = {
			result, tag
		};
		var early = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "invalid.fresh.retirement");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner", "fresh scoped return lost");
		CApi.erase_instruction (early);
		uint convention = CApi.function_call_conv (target);
		CApi.set_function_call_conv (target, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "physical signature");
		CApi.set_function_call_conv (target, convention);
		artifact.verify ();
		fresh_result_callers (artifact, target, tag, builder);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	private static void fresh_result_callers(LlvmModuleArtifact artifact, CApi.ValueRef target, CApi.ValueRef tag, CApi.BuilderRef builder) throws GLib.Error {
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var caller = declaration (artifact, "fresh.result.caller", word, new CApi.TypeRef[] { pointer });
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, caller, "entry"));
		var open = declaration (artifact, "astra_context17_open_scoped", pointer, new CApi.TypeRef[] { pointer, word, word, word });
		var release = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		var destroy = declaration (artifact, "astra_context17_destroy", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		var contexts = new CApi.ValueRef[2];
		var calls = new CApi.ValueRef[2];
		var retirements = new CApi.ValueRef[2];
		for (int c = 0; c < 2; c++) {
			CApi.ValueRef[] backing = {
				CApi.const_null (pointer), CApi.const_int (word, (uint64) (4097 + c * 2), 0), CApi.const_int (word, 1, 0), CApi.const_int (word, 7, 0)
			};
			contexts[c] = CApi.build_call (builder, CApi.global_value_type (open), open, backing, 4, "context");
			CApi.set_instruction_call_conv (contexts[c], CApi.CallConv.C);
		}
		for (int c = 0; c < 2; c++) {
			CApi.ValueRef[] arguments = {
				contexts[c], contexts[1 - c], CApi.const_int (word, 17, 0)
			};
			calls[c] = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, 3, "fresh.owner");
			CApi.set_instruction_call_conv (calls[c], LlvmLowering.CALL_CONVENTION);
		}
		for (int c = 0; c < 2; c++) {
			CApi.ValueRef[] arguments = {
				calls[c], tag
			};
			retirements[c] = CApi.build_call (builder, CApi.global_value_type (release), release, arguments, 2, "retired");
			CApi.set_instruction_call_conv (retirements[c], CApi.CallConv.C);
		}
		for (int c = 0; c < 2; c++) {
			CApi.ValueRef[] arguments = {
				contexts[c]
			};
			var closed = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, arguments, 1, "");
			CApi.set_instruction_call_conv (closed, CApi.CallConv.C);
		}
		CApi.build_ret (builder, CApi.const_int (word, 0, 0));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		foreach (var value in new CApi.ValueRef[] { CApi.const_null (pointer), CApi.get_param (caller, 0) }) {
			CApi.set_operand (calls[0], 0, value);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "original live context or borrowed input");
			CApi.set_operand (calls[0], 0, contexts[0]);
		}
		for (int c = 0; c < 2; c++) {
			CApi.set_operand (retirements[c], 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.set_operand (retirements[c], 0, calls[c]);
		}
		CApi.position_builder_before (builder, calls[0]);
		CApi.ValueRef[] arguments = {
			contexts[0]
		};
		var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, arguments, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live context");
		CApi.erase_instruction (early);
		uint convention = CApi.instruction_call_conv (calls[0]);
		CApi.set_instruction_call_conv (calls[0], CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "ABI/context position");
		CApi.set_instruction_call_conv (calls[0], convention);
		artifact.verify_scoped_allocations ();
		CApi.delete_function (caller);
	}

	internal static void fresh_construction(LlvmModuleArtifact artifact, CApi.ValueRef function) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		var releases = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t length;
				string name = CApi.value_name (CApi.called_value (instruction), out length);
				if (name == "astra_context17_allocate_mode") {
					assert ((void*) allocation == null);
					allocation = instruction;
				}
				if (name == "astra_context17_release_origin_checked") {
					releases.add ((void*) instruction);
				}
			}
		}
		assert ((void*) allocation != null && releases.length != 0);
		for (uint position = 1; position <= 5; position++) {
			var original = CApi.operand (allocation, position);
			var changed = CApi.const_int (CApi.type_of (original), position == 1 || position == 5 ? 2 : position == 4 ? 77 : CApi.const_int_zext (original) * 2, 0);
			CApi.set_operand (allocation, position, changed);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), position == 5 ? "exact affine mode" : "exact Class allocation shape");
			CApi.set_operand (allocation, position, original);
		}
		var context = CApi.operand (allocation, 0);
		CApi.set_operand (allocation, 0, CApi.const_null (CApi.type_of (context)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "complete emitted context-input contract");
		CApi.set_operand (allocation, 0, context);
		var owners = new GenericArray<void*> ();
		for (int r = 0; r < releases.length; r++) {
			var release = (CApi.ValueRef) releases[r];
			var owner = CApi.operand (release, 0);
			owners.add ((void*) owner);
			CApi.set_operand (release, 0, CApi.const_null (CApi.type_of (owner)));
		}
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation", "before its derived allocation");
		for (int r = 0; r < releases.length; r++) {
			CApi.set_operand ((CApi.ValueRef) releases[r], 0, (CApi.ValueRef) owners[r]);
		}
		artifact.verify ();
	}

	internal static void owning_receiver(LlvmModuleArtifact artifact, CApi.ValueRef constructor, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_owned_inputs (constructor) && artifact.has_scoped_owned_inputs (destructor));
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (bool constructing in new bool[] { false, true }) {
			var caller = declaration (artifact, "unproved.owning.receiver", word, new CApi.TypeRef[] { pointer, CApi.int1_type_in_context (artifact.context) });
			CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, caller, "entry"));
			var local = CApi.build_alloca (builder, word, "unproved.local");
			var global = CApi.add_global (artifact.module, word, "unproved.owning.global");
			CApi.set_initializer (global, CApi.const_int (word, 7, 0));
			var external = declaration (artifact, "unknown.owning.receiver", pointer, new CApi.TypeRef[] {});
			CApi.ValueRef[] none = {};
			var unknown = CApi.build_call (builder, CApi.global_value_type (external), external, none, 0, "unproved.external");
			CApi.set_instruction_call_conv (unknown, CApi.CallConv.C);
			var selection = CApi.build_select (builder, CApi.get_param (caller, 1), local, CApi.get_param (caller, 0), "unproved.selection");
			var target = constructing ? constructor : destructor;
			CApi.ValueRef[] arguments = {
				CApi.const_null (pointer)
			};
			if (constructing) {
				arguments += CApi.const_int (word, 7, 0);
				arguments += CApi.const_null (pointer);
			}
			var call = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, arguments.length, "");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			CApi.build_ret (builder, CApi.const_int (word, 0, 0));
			foreach (var value in new CApi.ValueRef[] { CApi.const_null (pointer), global, local, CApi.get_param (caller, 0), unknown, selection }) {
				CApi.set_operand (call, 0, value);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "scoped lifecycle receiver requires its actual tracked allocation");
			}
			CApi.delete_function (caller);
			CApi.delete_global (global);
			bool changed = false;
			for (var block = CApi.first_block (target); (void*) block != null && !changed; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null && !changed; instruction = CApi.next_instruction (instruction)) {
					bool store = CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.POINTER;
					bool cleanup = !constructing && CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.argument_count (instruction) == 1 && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.POINTER;
					if (!store && !cleanup) {
						continue;
					}
					var original = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_null (pointer));
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_owned_inputs (), "original", "operand");
					CApi.set_operand (instruction, 0, original);
					changed = true;
				}
			}
			assert (changed);
			artifact.verify ();
		}
		CApi.dispose_builder (builder);
	}

	internal static void graph_forwarding(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef relay) throws GLib.Error {
		artifact.verify ();
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.ValueRef end = (CApi.ValueRef) null;
		for (var block = CApi.first_block (relay); (void*) block != null; block = CApi.next_block (block)) {
			var candidate = CApi.block_terminator (block);
			if (CApi.opcode (candidate) == CApi.Opcode.RET) {
				assert ((void*) end == null);
				end = candidate;
			}
		}
		assert ((void*) end != null);
		var input = CApi.operand (end, 0);
		var global = CApi.add_global (artifact.module, word, "invalid.graph.result");
		CApi.set_initializer (global, CApi.const_int (word, 7, 0));
		CApi.position_builder_before (builder, end);
		var zero = CApi.const_int (word, 0, 0);
		var interior = CApi.build_gep (builder, word, input, &zero, 1, "invalid.graph.interior");
		foreach (var value in new CApi.ValueRef[] { CApi.const_null (pointer), global, interior }) {
			CApi.set_operand (end, 0, value);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "original complete owner publication");
			CApi.set_operand (end, 0, input);
		}
		CApi.erase_instruction (interior);
		CApi.delete_global (global);
		CApi.ValueRef call = (CApi.ValueRef) null;
		CApi.ValueRef read = (CApi.ValueRef) null;
		CApi.ValueRef constructed = (CApi.ValueRef) null;
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		var method = CApi.named_function (artifact.module, "astra.class.method.1.0");
		var constructor = CApi.named_function (artifact.module, "astra.ctor.1");
		var destructor = CApi.named_function (artifact.module, "astra.dtor.1");
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocation = instruction;
				}
				if ((void*) CApi.called_value (instruction) == (void*) relay) {
					call = instruction;
				}
				if ((void*) CApi.called_value (instruction) == (void*) method) {
					read = instruction;
				}
				if ((void*) CApi.called_value (instruction) == (void*) constructor) {
					constructed = instruction;
				}
			}
		}
		assert ((void*) call != null && (void*) read != null && (void*) constructed != null && (void*) allocation != null);
		var owner = CApi.operand (call, 0);
		foreach (var value in new CApi.ValueRef[] { CApi.const_null (pointer), CApi.operand (allocation, 0), CApi.operand (constructed, 2) }) {
			CApi.set_operand (call, 0, value);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "carrier", "actual tracked allocation", "exact allocation or borrowed origin");
			CApi.set_operand (call, 0, owner);
		}
		CApi.position_builder_before (builder, call);
		CApi.ValueRef[] moved = {
			owner
		};
		var duplicate = CApi.build_call (builder, CApi.global_value_type (relay), relay, moved, 1, "invalid.duplicate.forward");
		CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner handle");
		CApi.erase_instruction (duplicate);
		CApi.position_builder_before (builder, read);
		CApi.ValueRef[] borrowed = {
			owner
		};
		var stale = CApi.build_call (builder, CApi.global_value_type (method), method, borrowed, 1, "invalid.stale.parent");
		CApi.set_instruction_call_conv (stale, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner handle");
		CApi.erase_instruction (stale);
		CApi.position_builder_before (builder, read);
		CApi.ValueRef[] retired = {
			call
		};
		var early = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, retired, 1, "");
		CApi.set_instruction_call_conv (early, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "occupied live carrier");
		CApi.erase_instruction (early);
		uint convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact type, extent, alignment, tag or transfer channel");
		CApi.set_instruction_call_conv (call, convention);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void child_graph(LlvmModuleArtifact artifact, CApi.ValueRef function, bool checked) throws GLib.Error {
		artifact.verify ();
		var constructor = CApi.named_function (artifact.module, "astra.ctor.1");
		var destructor = CApi.named_function (artifact.module, "astra.dtor.1");
		var method = CApi.named_function (artifact.module, "astra.class.method.1.0");
		CApi.ValueRef constructed = (CApi.ValueRef) null;
		CApi.ValueRef read = (CApi.ValueRef) null;
		CApi.ValueRef selected = (CApi.ValueRef) null;
		var allocations = new GenericArray<void*> ();
		var cleanups = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.SELECT && CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.POINTER) {
					selected = instruction;
				}
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocations.add ((void*) instruction);
				}
				if ((void*) CApi.called_value (instruction) == (void*) constructor) {
					constructed = instruction;
				}
				if ((void*) CApi.called_value (instruction) == (void*) destructor) {
					cleanups.add ((void*) instruction);
				}
				if ((void*) CApi.called_value (instruction) == (void*) method) {
					read = instruction;
				}
			}
		}
		assert (allocations.length == 3 && (void*) constructed != null && (void*) read != null && cleanups.length != 0);
		var allocation = (CApi.ValueRef) allocations[2];
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var builder = CApi.create_builder_in_context (artifact.context);
		for (uint p = 1; p <= 5; p++) {
			var original = CApi.operand (allocation, p);
			CApi.set_operand (allocation, p, CApi.const_int (CApi.type_of (original), p == 5 ? 2 : CApi.const_int_zext (original) * 2, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "heap carrier", "scoped");
			CApi.set_operand (allocation, p, original);
		}
		var left = CApi.operand (constructed, 2);
		var right = CApi.operand (constructed, 3);
		CApi.set_operand (constructed, 2, right);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "one exact transfer", "duplicates");
		CApi.set_operand (constructed, 2, left);
		var context = CApi.operand (allocation, 0);
		CApi.set_operand (constructed, 2, context);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual tracked allocation", "one exact transfer", "original owned field");
		CApi.set_operand (constructed, 2, left);
		var receiver = CApi.operand (constructed, 0);
		CApi.set_operand (constructed, 0, left);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "heap carrier", "scoped");
		CApi.set_operand (constructed, 0, receiver);
		var release = CApi.named_function (artifact.module, "astra_context17_release_origin_checked");
		CApi.position_builder_before (builder, read);
		CApi.ValueRef[] retired = {
			receiver, CApi.operand (allocation, 4)
		};
		var early = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "early.parent.release");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its owned field cleanup");
		CApi.erase_instruction (early);
		CApi.position_builder_before (builder, read);
		retired[0] = left;
		retired[1] = CApi.operand ((CApi.ValueRef) allocations[0], 4);
		early = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "early.child.release");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner handle");
		CApi.erase_instruction (early);
		var foreign = declaration (artifact, "unproved.graph.cleanup", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		foreach (void* address in cleanups) {
			var call = (CApi.ValueRef) address;
			CApi.set_operand (call, CApi.operand_count (call) - 1, foreign);
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		}
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "ownership effect", "address escaped");
		foreach (void* address in cleanups) {
			var call = (CApi.ValueRef) address;
			CApi.set_operand (call, CApi.operand_count (call) - 1, destructor);
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		}
		CApi.delete_function (foreign);
		if (checked) {
			assert ((void*) selected != null);
			CApi.position_builder_before (builder, selected);
			var unknown = declaration (artifact, "unproved.admission.condition", CApi.int1_type_in_context (artifact.context), new CApi.TypeRef[] {});
			CApi.ValueRef[] none = {};
			var condition = CApi.build_call (builder, CApi.global_value_type (unknown), unknown, none, 0, "unknown.admission");
			CApi.set_instruction_call_conv (condition, CApi.CallConv.C);
			var original = CApi.operand (selected, 0);
			CApi.set_operand (selected, 0, condition);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation absence", "live owner", "exact live child owner");
			CApi.set_operand (selected, 0, original);
			CApi.erase_instruction (condition);
			CApi.delete_function (unknown);
		}
		uint convention = CApi.instruction_call_conv (constructed);
		CApi.set_instruction_call_conv (constructed, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "physical signature");
		CApi.set_instruction_call_conv (constructed, convention);
		artifact.verify ();
		CApi.dispose_builder (builder);
	}

	internal static void receiver_origins(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		var target = CApi.named_function (artifact.module, "astra.class.method.0.0");
		var constructor = CApi.named_function (artifact.module, "astra.ctor.0");
		assert (artifact.scoped_borrow (target) && artifact.scoped_borrow (constructor));
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (bool constructing in new bool[] { false, true }) {
			var function = declaration (artifact, "scoped.receiver.origins", word, new CApi.TypeRef[] { pointer });
			CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, function, "entry"));
			var local = CApi.build_alloca (builder, word, "unproved.receiver");
			var global = CApi.add_global (artifact.module, word, "unproved.receiver.global");
			CApi.set_initializer (global, CApi.const_int (word, 7, 0));
			CApi.ValueRef[] arguments = {
				CApi.const_null (pointer)
			};
			if (constructing) {
				arguments += CApi.const_int (word, 7, 0);
			}
			var called = constructing ? constructor : target;
			var call = CApi.build_call (builder, CApi.global_value_type (called), called, arguments, arguments.length, constructing ? "" : "observed");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			CApi.build_ret (builder, constructing ? CApi.const_int (word, 0, 0) : call);
			foreach (var value in new CApi.ValueRef[] { global, local, CApi.get_param (function, 0), CApi.const_null (pointer) }) {
				CApi.set_operand (call, 0, value);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "scoped receiver requires its exact allocation or borrowed origin");
			}
			CApi.delete_function (function);
			CApi.delete_global (global);
		}
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (caller)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (CApi.called_value (instruction), out length);
			if (name == "astra_context17_allocate_mode") {
				allocation = instruction;
			}
			if (name == "astra_context17_release_origin_checked") {
				release = instruction;
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		CApi.set_operand (allocation, 2, CApi.const_int (size, 4, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (word, 4, 0));
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 1, tag);
		CApi.position_builder_before (builder, release);
		var owner = CApi.operand (release, 0);
		CApi.ValueRef[] initialized = {
			owner, CApi.const_int (word, 7, 0)
		};
		var constructed = CApi.build_call (builder, CApi.global_value_type (constructor), constructor, initialized, 2, "");
		CApi.set_instruction_call_conv (constructed, LlvmLowering.CALL_CONVENTION);
		CApi.ValueRef[] observed = {
			owner
		};
		var read = CApi.build_call (builder, CApi.global_value_type (target), target, observed, 1, "observed");
		CApi.set_instruction_call_conv (read, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		for (uint position = 1; position <= 4; position++) {
			var original = CApi.operand (allocation, position);
			var wrong = CApi.const_int (CApi.type_of (original), position == 1 ? 2 : position == 4 ? 77 : 8, 0);
			CApi.set_operand (allocation, position, wrong);
			if (position == 4) {
				CApi.set_operand (release, 1, wrong);
			}
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped receiver lost its exact Class allocation shape");
			CApi.set_operand (allocation, position, original);
			if (position == 4) {
				CApi.set_operand (release, 1, original);
			}
		}
		artifact.verify_scoped_allocations ();
		fixture.remove_function ();
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void class_loan_origins(LlvmModuleArtifact artifact, CApi.ValueRef target, bool owning = false) throws GLib.Error {
		artifact.verify ();
		assert (owning ? artifact.has_scoped_owned_inputs (target) : artifact.has_scoped_class_loans (target));
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var builder = CApi.create_builder_in_context (artifact.context);
		var function = declaration (artifact, "class.loan.origins", word, new CApi.TypeRef[] { pointer, CApi.int1_type_in_context (artifact.context) });
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, function, "entry"));
		var local = CApi.build_alloca (builder, word, "unproved.local");
		var external = declaration (artifact, "unproved.pointer", pointer, new CApi.TypeRef[] {});
		CApi.ValueRef[] none = {};
		var unknown = CApi.build_call (builder, CApi.global_value_type (external), external, none, 0, "unproved.result");
		CApi.set_instruction_call_conv (unknown, CApi.CallConv.C);
		var selected = CApi.build_select (builder, CApi.get_param (function, 1), local, CApi.get_param (function, 0), "unproved.selection");
		var global = CApi.add_global (artifact.module, word, "unproved.class.global");
		CApi.set_initializer (global, CApi.const_int (word, 7, 0));
		CApi.ValueRef[] arguments = {
			CApi.const_null (pointer)
		};
		var call = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, 1, "observed");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		CApi.build_ret (builder, call);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		foreach (var value in new CApi.ValueRef[] { global, local, unknown, CApi.get_param (function, 0), selected }) {
			CApi.set_operand (call, 0, value);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), owning ? "scoped Class call requires an actual tracked allocation or proven null input" : "Class loan requires an actual tracked allocation or matching borrowed parameter");
			CApi.set_operand (call, 0, CApi.const_null (pointer));
		}
		CApi.dispose_builder (builder);
		CApi.delete_function (function);
		CApi.delete_global (global);
		artifact.verify ();
	}

	internal static void record_result_loans(LlvmModuleArtifact artifact, CApi.ValueRef target, bool checked, bool with_context) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_owned_inputs (target) && artifact.has_scoped_class_loans (target));
		assert (artifact.has_scoped_context_inputs (target) == with_context);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var builder = CApi.create_builder_in_context (artifact.context);
		var function = declaration (artifact, "record.result.loan.caller", word, new CApi.TypeRef[] { word });
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, function, "entry"));
		var open = declaration (artifact, "astra_context17_open_scoped", pointer, new CApi.TypeRef[] { pointer, word, word, word });
		CApi.ValueRef[] backing = {
			CApi.const_null (pointer), CApi.const_int (word, 4097, 0), CApi.const_int (word, 1, 0), CApi.const_int (word, 7, 0)
		};
		var context = CApi.build_call (builder, CApi.global_value_type (open), open, backing, 4, "context");
		CApi.set_instruction_call_conv (context, CApi.CallConv.C);
		var allocate = declaration (artifact, "astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
		var release = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		var destroy = declaration (artifact, "astra_context17_destroy", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		var owners = new CApi.ValueRef[3];
		for (int f = 0; f < 3; f++) {
			CApi.ValueRef[] extent = {
				context, CApi.const_int (size, 1, 0), CApi.const_int (size, 4, 0), CApi.const_int (word, 4, 0), tag, CApi.const_int (word, 3, 0)
			};
			owners[f] = CApi.build_call (builder, CApi.global_value_type (allocate), allocate, extent, 6, "allocation");
			CApi.set_instruction_call_conv (owners[f], CApi.CallConv.C);
		}
		CApi.TypeRef tuple = CApi.return_type (CApi.global_value_type (target));
		if (checked) {
			for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) CApi.get_param (target, 0)) {
						tuple = CApi.type_of (CApi.operand (instruction, 0));
					}
				}
			}
		}
		assert (CApi.type_kind (tuple) == CApi.TypeKind.STRUCT);
		CApi.ValueRef[] arguments = {};
		CApi.ValueRef slot = (CApi.ValueRef) null;
		if (checked) {
			slot = CApi.build_alloca (builder, tuple, "success.tuple");
			arguments += slot;
			arguments += CApi.get_param (function, 0);
		}
		for (int f = 0; f < 3; f++) {
			arguments += owners[f];
		}
		if (with_context) {
			arguments += context;
		}
		var call = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, arguments.length, "result");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		if (checked) {
			var success = CApi.append_basic_block_in_context (artifact.context, function, "success");
			var failure = CApi.append_basic_block_in_context (artifact.context, function, "failure");
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, call, CApi.const_null (pointer), "observed.success"), success, failure);
			CApi.position_builder_at_end (builder, failure);
			CApi.ValueRef[] loan = {
				owners[2], tag
			};
			var retired = CApi.build_call (builder, CApi.global_value_type (release), release, loan, 2, "loan.retired");
			CApi.set_instruction_call_conv (retired, CApi.CallConv.C);
			var free_error = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
			CApi.ValueRef[] error = {
				call
			};
			var freed = CApi.build_call (builder, CApi.global_value_type (free_error), free_error, error, 1, "");
			CApi.set_instruction_call_conv (freed, CApi.CallConv.C);
			CApi.ValueRef[] closed = {
				context
			};
			var close = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, closed, 1, "");
			CApi.set_instruction_call_conv (close, CApi.CallConv.C);
			CApi.build_ret (builder, CApi.const_int (word, 0, 0));
			CApi.position_builder_at_end (builder, success);
		}
		var values = new CApi.ValueRef[3];
		var result = checked ? CApi.build_load (builder, tuple, slot, "successful.result") : call;
		int at = 0;
		for (uint f = 0; f < CApi.count_struct_element_types (tuple); f++) {
			if (CApi.type_kind (CApi.struct_type_at_index (tuple, f)) == CApi.TypeKind.POINTER) {
				values[at++] = CApi.build_extract_value (builder, result, f, "result.owner");
			}
		}
		assert (at == 2);
		values[2] = owners[2];
		var live_read = CApi.build_load (builder, word, owners[2], "still.borrowed");
		var retirements = new CApi.ValueRef[3];
		for (int f = 0; f < 3; f++) {
			CApi.ValueRef[] retired = {
				values[f], tag
			};
			retirements[f] = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "retired");
			CApi.set_instruction_call_conv (retirements[f], CApi.CallConv.C);
		}
		CApi.ValueRef[] closed = {
			context
		};
		var close = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, closed, 1, "");
		CApi.set_instruction_call_conv (close, CApi.CallConv.C);
		CApi.build_ret (builder, CApi.const_int (word, 0, 0));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		for (int f = 0; f < 2; f++) {
			uint position = (uint) f + (checked ? 2U : 0U);
			CApi.set_operand (call, position, owners[2]);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "both consuming and borrowed inputs");
			CApi.set_operand (call, position, owners[f]);
			CApi.position_builder_before (builder, live_read);
			var stale = CApi.build_load (builder, word, owners[f], "stale.input");
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
			CApi.erase_instruction (stale);
		}
		for (int f = 0; f < 3; f++) {
			CApi.set_operand (retirements[f], 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.set_operand (retirements[f], 0, values[f]);
		}
		uint borrowed_position = checked ? 4U : 2U;
		CApi.set_operand (call, borrowed_position, context);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "context cannot substitute for a Class loan");
		CApi.set_operand (call, borrowed_position, owners[2]);
		CApi.position_builder_before (builder, call);
		CApi.ValueRef[] retired = {
			owners[2], tag
		};
		var early = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "invalid.early.loan.retirement");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (early);
		uint convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_instruction_call_conv (call, convention);
		CApi.dispose_builder (builder);
		CApi.delete_function (function);
		artifact.verify ();
	}

	private static void checked_record_allocations(LlvmModuleArtifact artifact, CApi.ValueRef target, CApi.TypeRef tuple, CApi.ValueRef fault_destructor) throws GLib.Error {
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var builder = CApi.create_builder_in_context (artifact.context);
		var function = declaration (artifact, "checked.record.allocations", word, new CApi.TypeRef[] { word });
		var entry = CApi.append_basic_block_in_context (artifact.context, function, "entry");
		CApi.position_builder_at_end (builder, entry);
		var open = declaration (artifact, "astra_context17_open_scoped", pointer, new CApi.TypeRef[] { pointer, word, word, word });
		var allocate = declaration (artifact, "astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
		var release = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		var destroy = declaration (artifact, "astra_context17_destroy", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		var contexts = new CApi.ValueRef[2];
		var owners = new CApi.ValueRef[2];
		var slots = new CApi.ValueRef[2];
		for (int f = 0; f < 2; f++) {
			CApi.ValueRef[] backing = {
				CApi.const_null (pointer), CApi.const_int (word, 4097, 0), CApi.const_int (word, 1, 0), CApi.const_int (word, 7, 0)
			};
			contexts[f] = CApi.build_call (builder, CApi.global_value_type (open), open, backing, 4, "context");
			CApi.set_instruction_call_conv (contexts[f], CApi.CallConv.C);
			CApi.ValueRef[] extent = {
				contexts[f], CApi.const_int (size, 1, 0), CApi.const_int (size, 1, 0), CApi.const_int (word, 1, 0), tag, CApi.const_int (word, 3, 0)
			};
			owners[f] = CApi.build_call (builder, CApi.global_value_type (allocate), allocate, extent, 6, "owner");
			CApi.set_instruction_call_conv (owners[f], CApi.CallConv.C);
			slots[f] = CApi.build_alloca (builder, tuple, "result.storage");
		}
		var error_cleanups = new GenericArray<void*> ();
		var error_releases = new GenericArray<void*> ();
		var fields = new GenericArray<uint> ();
		for (uint f = 0; f < CApi.count_struct_element_types (tuple); f++) {
			if (CApi.type_kind (CApi.struct_type_at_index (tuple, f)) == CApi.TypeKind.POINTER) {
				fields.add (f);
			}
		}
		assert (fields.length == 2);
		var called = new CApi.ValueRef[2];
		var values = new CApi.ValueRef[4];
		for (int round = 0; round < 2; round++) {
			CApi.ValueRef[] arguments = {
				slots[round], round == 0 ? CApi.get_param (function, 0) : CApi.const_int (word, 0, 0), round == 0 ? owners[0] : values[0], round == 0 ? owners[1] : values[1]
			};
			if (CApi.count_params (target) == 5) {
				arguments += contexts[0];
			}
			called[round] = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, arguments.length, "checked.record");
			CApi.set_instruction_call_conv (called[round], LlvmLowering.CALL_CONVENTION);
			var success = CApi.append_basic_block_in_context (artifact.context, function, "success");
			var failed = CApi.append_basic_block_in_context (artifact.context, function, "failure");
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, called[round], CApi.const_null (pointer), "observed.success"), success, failed);
			CApi.position_builder_at_end (builder, failed);
			if ((void*) fault_destructor != null) {
				CApi.ValueRef[] error = {
					called[round]
				};
				var cleanup = CApi.build_call (builder, CApi.global_value_type (fault_destructor), fault_destructor, error, 1, "");
				CApi.set_instruction_call_conv (cleanup, LlvmLowering.CALL_CONVENTION);
				error_cleanups.add ((void*) cleanup);
				var release_error = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
				var freed = CApi.build_call (builder, CApi.global_value_type (release_error), release_error, error, 1, "");
				CApi.set_instruction_call_conv (freed, CApi.CallConv.C);
				error_releases.add ((void*) freed);
			}
			for (int f = 0; f < 2; f++) {
				CApi.ValueRef[] loan = {
					contexts[f]
				};
				var close = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, loan, 1, "");
				CApi.set_instruction_call_conv (close, CApi.CallConv.C);
			}
			CApi.build_ret (builder, CApi.const_int (word, 0, 0));
			CApi.position_builder_at_end (builder, success);
			var loaded = CApi.build_load (builder, tuple, slots[round], "record.owners");
			for (int f = 0; f < 2; f++) {
				values[round * 2 + f] = CApi.build_extract_value (builder, loaded, fields[f], "returned.owner");
			}
		}
		var retirements = new CApi.ValueRef[2];
		for (int f = 0; f < 2; f++) {
			CApi.ValueRef[] returned = {
				values[2 + f], tag
			};
			retirements[f] = CApi.build_call (builder, CApi.global_value_type (release), release, returned, 2, "retired");
			CApi.set_instruction_call_conv (retirements[f], CApi.CallConv.C);
		}
		for (int f = 0; f < 2; f++) {
			CApi.ValueRef[] loan = {
				contexts[f]
			};
			var close = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, loan, 1, "");
			CApi.set_instruction_call_conv (close, CApi.CallConv.C);
		}
		CApi.build_ret (builder, CApi.const_int (word, 0, 0));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		foreach (var stale in new CApi.ValueRef[] { owners[0], owners[1], values[0], values[1] }) {
			CApi.position_builder_before (builder, retirements[0]);
			var read = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), stale, "invalid.stale.record.owner");
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
			CApi.erase_instruction (read);
		}
		for (int f = 0; f < 2; f++) {
			CApi.set_operand (retirements[f], 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.set_operand (retirements[f], 0, values[2 + f]);
		}
		CApi.set_operand (called[0], 3, owners[0]);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "duplicates one allocation");
		CApi.set_operand (called[0], 3, owners[1]);
		CApi.position_builder_before (builder, retirements[0]);
		var alias = CApi.build_extract_value (builder, CApi.operand (values[2], 0), fields[0], "duplicate.checked.record.extraction");
		var live_read = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), alias, "live.duplicate.record.owner");
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.erase_instruction (live_read);
		CApi.position_builder_before (builder, CApi.next_instruction (retirements[1]));
		var dead_read = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), alias, "invalid.retired.duplicate.owner");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (dead_read);
		CApi.erase_instruction (alias);
		for (uint mask = 1; mask < 4; mask++) {
			var early = new GenericArray<void*> ();
			CApi.position_builder_before (builder, called[0]);
			for (int f = 0; f < 2; f++) {
				if ((mask & (1U << f)) == 0) {
					continue;
				}
				CApi.ValueRef[] returned = {
					owners[f], tag
				};
				var close = CApi.build_call (builder, CApi.global_value_type (release), release, returned, 2, "nullable.input.retired");
				CApi.set_instruction_call_conv (close, CApi.CallConv.C);
				early.add ((void*) close);
				CApi.set_operand (called[0], (uint) f + 2, CApi.const_null (pointer));
			}
			valid_ir (artifact.module);
			artifact.verify_scoped_allocations ();
			for (int f = 0; f < 2; f++) {
				CApi.set_operand (called[0], (uint) f + 2, owners[f]);
			}
			foreach (void* value in early) {
				CApi.erase_instruction ((CApi.ValueRef) value);
			}
		}
		foreach (void* address in error_cleanups) {
			var cleanup = (CApi.ValueRef) address;
			var original = CApi.operand (cleanup, 0);
			CApi.set_operand (cleanup, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its owned field cleanup");
			CApi.set_operand (cleanup, 0, original);
			CApi.position_builder_before (builder, cleanup);
			CApi.ValueRef[] context = {
				contexts[1]
			};
			var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, context, 1, "");
			CApi.set_instruction_call_conv (early, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.erase_instruction (early);
			CApi.position_builder_before (builder, CApi.next_instruction (cleanup));
			CApi.ValueRef[] input = {
				original
			};
			var repeated = CApi.build_call (builder, CApi.global_value_type (fault_destructor), fault_destructor, input, 1, "");
			CApi.set_instruction_call_conv (repeated, LlvmLowering.CALL_CONVENTION);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "occupied live carrier");
			CApi.erase_instruction (repeated);
		}
		foreach (void* address in error_releases) {
			var freed = (CApi.ValueRef) address;
			var original = CApi.operand (freed, 0);
			CApi.set_operand (freed, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired heap carrier");
			CApi.set_operand (freed, 0, original);
		}
		CApi.dispose_builder (builder);
		CApi.delete_function (function);
		artifact.verify ();
	}

	internal static void checked_record_result(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef target, CApi.ValueRef fault_destructor = (CApi.ValueRef) null) throws GLib.Error {
		artifact.verify ();
		var builder = CApi.create_builder_in_context (artifact.context);
		var output = CApi.get_param (target, 0);
		CApi.ValueRef publication = (CApi.ValueRef) null, normal = (CApi.ValueRef) null, failure = (CApi.ValueRef) null;
		for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) output) {
					assert ((void*) publication == null);
					publication = instruction;
				}
			}
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) == CApi.Opcode.RET) {
				if ((void*) CApi.is_constant_pointer_null (CApi.operand (end, 0)) != null) {
					normal = end;
				} else {
					failure = end;
				}
			}
		}
		assert ((void*) publication != null && (void*) normal != null && (void*) failure != null);
		int fields = 0;
		for (var value = CApi.operand (publication, 0); (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.INSERT_VALUE; value = CApi.operand (value, 0)) {
			var original = CApi.operand (value, 1);
			if (CApi.type_kind (CApi.type_of (original)) != CApi.TypeKind.POINTER) {
				continue;
			}
			fields++;
			CApi.set_operand (value, 1, CApi.const_null (CApi.type_of (original)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "checked scoped record null field retains its live input owner");
			CApi.set_operand (value, 1, original);
		}
		assert (fields == 2);
		for (var value = CApi.operand (publication, 0); (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.INSERT_VALUE; value = CApi.operand (value, 0)) {
			var original = CApi.operand (value, 1);
			if (CApi.type_kind (CApi.type_of (original)) != CApi.TypeKind.POINTER) {
				continue;
			}
			CApi.set_operand (value, 1, CApi.get_param (target, (void*) original == (void*) CApi.get_param (target, 2) ? 3 : 2));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "ownership effect");
			CApi.set_operand (value, 1, original);
			var release = CApi.named_function (artifact.module, "astra_context17_release_origin_checked");
			var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
			foreach (bool before in new bool[] { true, false }) {
				CApi.position_builder_before (builder, before ? publication : CApi.next_instruction (publication));
				CApi.ValueRef[] arguments = {
					original, tag
				};
				var retired = CApi.build_call (builder, CApi.global_value_type (release), release, arguments, 2, "invalid.checked.field.retirement");
				CApi.set_instruction_call_conv (retired, CApi.CallConv.C);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
				CApi.erase_instruction (retired);
			}
		}
		var tuple = CApi.operand (publication, 0);
		CApi.set_operand (publication, 0, CApi.const_null (CApi.type_of (tuple)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "complete actual member publication");
		CApi.set_operand (publication, 0, tuple);
		CApi.position_builder_before (builder, publication);
		var fork = CApi.build_insert_value (builder, tuple, CApi.const_null (CApi.type_of (CApi.operand (tuple, 1))), CApi.indices (tuple)[0], "invalid.copied.record.publication");
		var hidden = CApi.build_alloca (builder, CApi.type_of (tuple), "hidden.record.result");
		var hidden_store = CApi.build_store (builder, fork, hidden);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "publication escaped its exact return chain");
		CApi.erase_instruction (hidden_store);
		CApi.erase_instruction (hidden);
		CApi.erase_instruction (fork);
		CApi.position_builder_before (builder, CApi.next_instruction (publication));
		var duplicate = CApi.build_store (builder, tuple, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "success was published more than once");
		CApi.erase_instruction (duplicate);
		var error = CApi.operand (failure, 0);
		CApi.set_operand (failure, 0, CApi.const_null (CApi.type_of (error)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "return lost its exact success/error publication");
		CApi.set_operand (failure, 0, error);
		CApi.ValueRef call = (CApi.ValueRef) null, loaded = (CApi.ValueRef) null, guard = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) target) {
					assert ((void*) call == null);
					call = instruction;
				}
			}
		}
		assert ((void*) call != null);
		var slot = CApi.operand (call, 0);
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.LOAD && (void*) CApi.operand (instruction, 0) == (void*) slot) {
					assert ((void*) loaded == null);
					loaded = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.ICMP && ((void*) CApi.operand (instruction, 0) == (void*) call || (void*) CApi.operand (instruction, 1) == (void*) call)) {
					var branch = CApi.block_terminator (block);
					if (CApi.opcode (branch) == CApi.Opcode.COND_BR && (void*) CApi.operand (branch, 0) == (void*) instruction) {
						guard = branch;
					}
				}
			}
		}
		assert ((void*) loaded != null && (void*) guard != null);
		CApi.set_operand (call, 0, CApi.operand (call, 2));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unique exact local success tuple");
		CApi.set_operand (call, 0, slot);
		foreach (var position in new CApi.ValueRef[] { call, CApi.next_instruction (call), CApi.next_instruction (loaded) }) {
			CApi.position_builder_before (builder, position);
			var early = CApi.build_load (builder, CApi.type_of (loaded), slot, "invalid.record.success.read");
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "success read lacks its observed successful target");
			CApi.erase_instruction (early);
		}
		var condition = CApi.operand (guard, 0);
		for (uint mode = 0; mode < 2; mode++) {
			CApi.set_operand (guard, 0, CApi.const_int (CApi.type_of (condition), mode, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "checked scoped", (void*) fault_destructor != null ? "exact live backing or nonnull allocation guard" : null);
			CApi.set_operand (guard, 0, condition);
		}
		CApi.position_builder_before (builder, CApi.next_instruction (loaded));
		var escaped = CApi.build_alloca (builder, CApi.type_of (loaded), "invalid.record.tuple.storage");
		var store = CApi.build_store (builder, loaded, escaped);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "load escaped exact member extraction");
		CApi.erase_instruction (store);
		CApi.erase_instruction (escaped);
		uint convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_instruction_call_conv (call, convention);
		CApi.dispose_builder (builder);
		artifact.verify ();
		checked_record_allocations (artifact, target, CApi.type_of (tuple), fault_destructor);
	}

	private static void record_result_context(LlvmModuleArtifact artifact, CApi.ValueRef target) throws GLib.Error {
		var context = CApi.get_param (target, CApi.count_params (target) - 1);
		var builder = CApi.create_builder_in_context (artifact.context);
		var first = CApi.first_instruction (CApi.first_block (target));
		CApi.position_builder_before (builder, first);
		var slot = CApi.build_alloca (builder, CApi.type_of (context), "invalid.result.context.storage");
		var stored = CApi.build_store (builder, context, slot);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "borrowed scoped context escaped");
		CApi.erase_instruction (stored);
		CApi.erase_instruction (slot);
		CApi.position_builder_before (builder, first);
		var integer = CApi.build_ptr_to_int (builder, context, CApi.int_type_in_context (artifact.context, 64), "invalid.result.context.integer");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "borrowed scoped context escaped");
		CApi.erase_instruction (integer);
		CApi.ValueRef[] arguments = {
			context
		};
		var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
		CApi.position_builder_before (builder, first);
		var close = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, arguments, 1, "");
		CApi.set_instruction_call_conv (close, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "cannot be retired by its callee");
		CApi.erase_instruction (close);
		var opaque = declaration (artifact, "invalid.result.context.pointer", CApi.type_of (context), new CApi.TypeRef[] { CApi.type_of (context) });
		CApi.position_builder_before (builder, first);
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "invalid.result.context.pointer");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "pointer-result lifetime effect");
		CApi.erase_instruction (escaped);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	private static CApi.ValueRef record_call(CApi.BuilderRef builder, CApi.ValueRef target, CApi.ValueRef first, CApi.ValueRef second, CApi.ValueRef context = (CApi.ValueRef) null) {
		CApi.ValueRef[] arguments = {
			first, second
		};
		if (CApi.count_params (target) - ((void*) context != null ? 1 : 0) == 3) {
			arguments += CApi.const_int (CApi.type_of (CApi.get_param (target, 2)), 17, 0);
		}
		if ((void*) context != null) {
			arguments += context;
		}
		var call = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, arguments.length, "record.result");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		return call;
	}

	internal static void record_results(LlvmModuleArtifact artifact, CApi.ValueRef target, bool with_context = false) throws GLib.Error {
		assert ((void*) target != null && artifact.has_scoped_owned_inputs (target));
		assert (artifact.has_scoped_context_inputs (target) == with_context);
		artifact.verify ();
		if (with_context) {
			record_result_context (artifact, target);
		}
		var forged_type = CApi.function_type (CApi.int32_type_in_context (artifact.context), null, 0, 0);
		var forged_caller = CApi.add_function (artifact.module, "unproved.record.caller", forged_type);
		var forged_builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (forged_builder, CApi.append_basic_block_in_context (artifact.context, forged_caller, "entry"));
		var unproved = CApi.add_global (artifact.module, CApi.int_type_in_context (artifact.context, 8), "unproved.record.origin");
		record_call (forged_builder, target, unproved, CApi.const_null (CApi.type_of (unproved)), with_context ? CApi.const_null (CApi.type_of (unproved)) : (CApi.ValueRef) null);
		CApi.build_ret (forged_builder, CApi.const_int (CApi.int32_type_in_context (artifact.context), 0, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual tracked allocation or proven null input");
		CApi.dispose_builder (forged_builder);
		CApi.delete_function (forged_caller);
		CApi.delete_global (unproved);
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (caller)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (CApi.called_value (instruction), out length);
			if (name == "astra_context17_allocate_mode") {
				allocation = instruction;
			}
			if (name == "astra_context17_release_origin_checked") {
				release = instruction;
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 1, tag);
		CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (tag), 1, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0));
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, release);
		var arguments = new CApi.ValueRef[6];
		for (int p = 0; p < arguments.length; p++) {
			arguments[p] = CApi.operand (allocation, p);
		}
		var other = CApi.build_call (builder, CApi.called_function_type (allocation), CApi.called_value (allocation), arguments, arguments.length, "second.allocation");
		CApi.set_instruction_call_conv (other, CApi.CallConv.C);
		var call = record_call (builder, target, allocation, other, with_context ? CApi.operand (allocation, 0) : (CApi.ValueRef) null);
		var first = CApi.build_extract_value (builder, call, 0, "first.owner");
		var second = CApi.build_extract_value (builder, call, 1, "second.owner");
		CApi.build_extract_value (builder, call, 2, "record.marker");
		var again = record_call (builder, target, first, second, with_context ? CApi.operand (allocation, 0) : (CApi.ValueRef) null);
		var final_first = CApi.build_extract_value (builder, again, 0, "final.first.owner");
		var final_second = CApi.build_extract_value (builder, again, 1, "final.second.owner");
		CApi.set_operand (release, 0, final_first);
		CApi.position_builder_before (builder, CApi.next_instruction (release));
		CApi.ValueRef[] retired = {
			final_second, tag
		};
		var other_release = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), retired, 2, "second.retirement");
		CApi.set_instruction_call_conv (other_release, CApi.CallConv.C);
		fixture.verify_ir ();
		artifact.verify_scoped_allocations ();
		if (with_context) {
			var open = CApi.operand (allocation, 0);
			CApi.position_builder_before (builder, other);
			var backing = new CApi.ValueRef[4];
			for (int a = 0; a < backing.length; a++) {
				backing[a] = CApi.operand (open, a);
			}
			var separate = CApi.build_call (builder, CApi.called_function_type (open), CApi.called_value (open), backing, backing.length, "second.context.instance");
			CApi.set_instruction_call_conv (separate, CApi.CallConv.C);
			CApi.set_operand (other, 0, separate);
			var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
			CApi.ValueRef[] close_arguments = {
				separate
			};
			CApi.position_builder_before (builder, CApi.next_instruction (other_release));
			var close = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, close_arguments, 1, "");
			CApi.set_instruction_call_conv (close, CApi.CallConv.C);
			fixture.verify_ir ();
			artifact.verify_scoped_allocations ();
			CApi.position_builder_before (builder, call);
			var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, close_arguments, 1, "");
			CApi.set_instruction_call_conv (early, CApi.CallConv.C);
			fixture.verify_ir ();
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.erase_instruction (early);
			uint context_position = CApi.count_params (target) - 1;
			var actual_context = CApi.operand (call, context_position);
			CApi.set_operand (call, context_position, allocation);
			fixture.verify_ir ();
			refusal_text (() => artifact.verify_scoped_allocations (), "ownership effect");
			CApi.set_operand (call, context_position, actual_context);
			var missing = CApi.add_function (artifact.module, "invalid.record.result.context.same.abi", CApi.global_value_type (target));
			CApi.set_function_call_conv (missing, LlvmLowering.CALL_CONVENTION);
			uint callee_position = CApi.operand_count (call) - 1;
			CApi.set_operand (call, callee_position, missing);
			fixture.verify_ir ();
			refusal_text (() => artifact.verify_scoped_allocations (), "ownership effect");
			CApi.set_operand (call, callee_position, target);
			CApi.delete_function (missing);
		}
		foreach (var stale in new CApi.ValueRef[] { allocation, other, first, second }) {
			CApi.position_builder_before (builder, release);
			var load = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), stale, "stale.record.owner");
			fixture.verify_ir ();
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
			CApi.erase_instruction (load);
		}
		CApi.set_operand (again, 1, first);
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "duplicates one allocation");
		CApi.set_operand (again, 1, second);
		foreach (var cleanup in new CApi.ValueRef[] { release, other_release }) {
			var owner = CApi.operand (cleanup, 0);
			CApi.set_operand (cleanup, 0, CApi.const_null (CApi.type_of (owner)));
			fixture.verify_ir ();
			refusal_text (() => artifact.verify_scoped_allocations (), "context retired before its derived allocation");
			CApi.set_operand (cleanup, 0, owner);
		}
		CApi.position_builder_before (builder, release);
		var duplicate = CApi.build_extract_value (builder, again, 0, "duplicate.extraction");
		CApi.position_builder_before (builder, CApi.next_instruction (other_release));
		var stale_load = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), duplicate, "retired.duplicate");
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (stale_load);
		CApi.erase_instruction (duplicate);
		CApi.position_builder_before (builder, release);
		var escaped = CApi.build_alloca (builder, CApi.type_of (again), "escaped.aggregate");
		var store = CApi.build_store (builder, again, escaped);
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "without aggregate escape");
		CApi.erase_instruction (store);
		CApi.erase_instruction (escaped);
		CApi.set_instruction_call_conv (again, CApi.CallConv.C);
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "record call lost its exact physical ABI");
		CApi.set_instruction_call_conv (again, LlvmLowering.CALL_CONVENTION);
		CApi.ValueRef end = (CApi.ValueRef) null;
		for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
			var terminator = CApi.block_terminator (block);
			if (CApi.opcode (terminator) == CApi.Opcode.RET) {
				assert ((void*) end == null);
				end = terminator;
			}
		}
		assert ((void*) end != null);
		for (var value = CApi.operand (end, 0); (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.INSERT_VALUE; value = CApi.operand (value, 0)) {
			if (CApi.type_kind (CApi.type_of (CApi.operand (value, 1))) != CApi.TypeKind.POINTER) {
				continue;
			}
			var original = CApi.operand (value, 1);
			CApi.set_operand (value, 1, CApi.const_null (CApi.type_of (original)));
			fixture.verify_ir ();
			refusal_text (() => artifact.verify_scoped_allocations (), "null result retains its original live input", with_context ? "owning sum effect" : null);
			bool refused = false;
			try {
				artifact.verify_scoped_owned_inputs ();
			} catch (LlvmError failure) {
				refused = true;
			}
			assert (refused);
			CApi.set_operand (value, 1, original);
		}
		var original_return = CApi.operand (end, 0);
		CApi.set_operand (end, 0, CApi.const_null (CApi.type_of (original_return)));
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "complete actual member publication");
		CApi.set_operand (end, 0, original_return);
		CApi.set_operand (end, 0, CApi.operand (original_return, 0));
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "complete actual member publication");
		CApi.set_operand (end, 0, original_return);
		CApi.ValueRef first_insert = original_return;
		while (CApi.indices (first_insert)[0] != 0) {
			first_insert = CApi.operand (first_insert, 0);
		}
		var original_first = CApi.operand (first_insert, 1);
		CApi.set_operand (first_insert, 1, CApi.get_param (target, 1));
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "emitted scoped pointer", with_context ? "owning sum effect" : null);
		CApi.set_operand (first_insert, 1, original_first);
		CApi.position_builder_before (builder, end);
		var fork = CApi.build_insert_value (builder, CApi.operand (original_return, 0), CApi.const_int (CApi.int32_type_in_context (artifact.context), 99, 0), 2, "forked.publication");
		var fork_storage = CApi.build_alloca (builder, CApi.type_of (fork), "fork.storage");
		var fork_store = CApi.build_store (builder, fork, fork_storage);
		fixture.verify_ir ();
		refusal_text (() => artifact.verify_scoped_allocations (), "publication escaped its exact return chain");
		CApi.erase_instruction (fork_store);
		CApi.erase_instruction (fork_storage);
		CApi.erase_instruction (fork);
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		artifact.verify ();
		for (uint selected = 0; selected < 2; selected++) {
			var nullable = new ScopedLlvmFixture (1, artifact);
			caller = CApi.named_function (artifact.module, "exercise");
			CApi.ValueRef condition = (CApi.ValueRef) null;
			for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.ICMP) {
						condition = instruction;
					}
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					size_t length;
					string name = CApi.value_name (CApi.called_value (instruction), out length);
					if (name == "astra_context17_allocate_mode") {
						allocation = instruction;
					}
					if (name == "astra_context17_release_origin_checked") {
						release = instruction;
					}
				}
			}
			assert ((void*) condition != null);
			CApi.set_operand (allocation, 4, tag);
			CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (tag), 1, 0));
			CApi.set_operand (allocation, 3, CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0));
			CApi.set_operand (release, 1, tag);
			builder = CApi.create_builder_in_context (artifact.context);
			CApi.position_builder_before (builder, condition);
			var zero = CApi.const_null (CApi.type_of (allocation));
			call = record_call (builder, target, selected == 0 ? allocation : zero, selected == 1 ? allocation : zero, with_context ? CApi.operand (allocation, 0) : (CApi.ValueRef) null);
			var maybe_first = CApi.build_extract_value (builder, call, 0, "nullable.first");
			var maybe_second = CApi.build_extract_value (builder, call, 1, "nullable.second");
			var repeated = record_call (builder, target, maybe_first, maybe_second, with_context ? CApi.operand (allocation, 0) : (CApi.ValueRef) null);
			var returned = CApi.build_extract_value (builder, repeated, selected, "nullable.record.owner");
			CApi.set_operand (condition, 0, returned);
			CApi.set_operand (release, 0, returned);
			nullable.verify_ir ();
			artifact.verify_scoped_allocations ();
			CApi.dispose_builder (builder);
			nullable.remove_function ();
			artifact.verify ();
		}
	}

	internal static void null_outputs(LlvmModuleArtifact artifact, CApi.ValueRef empty, CApi.ValueRef conditional) throws GLib.Error {
		artifact.verify ();
		var forged = CApi.add_global (artifact.module, CApi.int_type_in_context (artifact.context, 8), "invalid.null.scope.result");
		int returns = 0;
		foreach (var function in new CApi.ValueRef[] { empty, conditional }) {
			assert (artifact.has_scoped_owned_inputs (function));
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				var end = CApi.block_terminator (block);
				if (CApi.opcode (end) != CApi.Opcode.RET) {
					continue;
				}
				returns++;
				var original = CApi.operand (end, 0);
				assert ((void*) CApi.is_constant_pointer_null (original) != null);
				CApi.set_operand (end, 0, forged);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "literal-null return publication");
				CApi.set_operand (end, 0, original);
			}
			uint convention = CApi.function_call_conv (function);
			CApi.set_function_call_conv (function, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact physical signature");
			CApi.set_function_call_conv (function, convention);
		}
		assert (returns == 3);
		artifact.verify ();
	}

	internal static void mixed_records(LlvmModuleArtifact artifact, CApi.ValueRef callee, uint second_position, bool reversed, bool with_context) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_owned_inputs (callee) && artifact.has_scoped_class_loans (callee));
		assert (artifact.has_scoped_context_inputs (callee) == with_context);
		uint owned_at = reversed ? 3U : 0U;
		uint borrowed_at = reversed ? 0U : 3U;
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		var builder = CApi.create_builder_in_context (artifact.context);
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocation = instruction;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					release = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var release_function = CApi.called_value (release);
		var constructor = CApi.named_function (artifact.module, "astra.ctor.0");
		assert ((void*) constructor != null);
		CApi.ValueRef[] owners = new CApi.ValueRef[4];
		owners[0] = CApi.operand (release, 0);
		CApi.set_operand (allocation, 2, CApi.const_int (size, 4, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (word, 4, 0));
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 0, CApi.const_null (pointer));
		CApi.set_operand (release, 1, tag);
		CApi.position_builder_before (builder, release);
		CApi.ValueRef[] extent = new CApi.ValueRef[6];
		for (uint p = 0; p < 6; p++) {
			extent[p] = CApi.operand (allocation, p);
		}
		for (int p = 1; p < 4; p++) {
			owners[p] = CApi.build_call (builder, CApi.called_function_type (allocation), CApi.called_value (allocation), extent, 6, "mixed.record.field.%d".printf (p));
			CApi.set_instruction_call_conv (owners[p], CApi.CallConv.C);
		}
		foreach (var owner in owners) {
			CApi.ValueRef[] initialized = {
				owner, CApi.const_int (word, 5, 0)
			};
			var call = CApi.build_call (builder, CApi.global_value_type (constructor), constructor, initialized, 2, "");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		}
		CApi.ValueRef[] arguments = new CApi.ValueRef[with_context ? 7 : 6];
		arguments[owned_at] = owners[0];
		arguments[owned_at + second_position] = owners[1];
		arguments[borrowed_at] = owners[2];
		arguments[borrowed_at + second_position] = owners[3];
		arguments[owned_at + (second_position == 1 ? 2 : 1)] = CApi.const_int (word, 17, 0);
		arguments[borrowed_at + (second_position == 1 ? 2 : 1)] = CApi.const_int (word, 23, 0);
		if (with_context) {
			arguments[6] = CApi.operand (allocation, 0);
		}
		var transferred = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, arguments.length, "mixed.record.call");
		CApi.set_instruction_call_conv (transferred, LlvmLowering.CALL_CONVENTION);
		var retirements = new GenericArray<void*> ();
		CApi.position_builder_before (builder, release);
		foreach (var owner in new CApi.ValueRef[] { owners[2], owners[3] }) {
			CApi.ValueRef[] retired = {
				owner, tag
			};
			var call = CApi.build_call (builder, CApi.global_value_type (release_function), release_function, retired, 2, "mixed.record.borrow.retired");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			retirements.add ((void*) call);
		}
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		foreach (uint owned_position in new uint[] { owned_at, owned_at + second_position }) {
			foreach (uint borrowed_position in new uint[] { borrowed_at, borrowed_at + second_position }) {
				var original = CApi.operand (transferred, borrowed_position);
				CApi.set_operand (transferred, borrowed_position, CApi.operand (transferred, owned_position));
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "both consuming and borrowed inputs");
				CApi.set_operand (transferred, borrowed_position, original);
			}
		}
		var original = CApi.operand (transferred, owned_at + second_position);
		CApi.set_operand (transferred, owned_at + second_position, CApi.operand (transferred, owned_at));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "duplicates one allocation");
		CApi.set_operand (transferred, owned_at + second_position, original);
		foreach (void* item in retirements) {
			var retirement = (CApi.ValueRef) item;
			original = CApi.operand (retirement, 0);
			CApi.set_operand (retirement, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.set_operand (retirement, 0, original);
		}
		CApi.set_operand (release, 0, owners[0]);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner");
		CApi.set_operand (release, 0, CApi.const_null (pointer));
		CApi.position_builder_before (builder, release);
		var repeated = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, arguments.length, "invalid.mixed.record.repeated");
		CApi.set_instruction_call_conv (repeated, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner");
		CApi.erase_instruction (repeated);
		CApi.set_instruction_call_conv (transferred, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_instruction_call_conv (transferred, LlvmLowering.CALL_CONVENTION);
		foreach (uint position in new uint[] { 2, 3, 4 }) {
			original = CApi.operand (allocation, position);
			CApi.set_operand (allocation, position, CApi.const_int (CApi.type_of (original), position == 4 ? 77 : 8, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "extent, alignment");
			CApi.set_operand (allocation, position, original);
		}
		foreach (uint position in new uint[] { owned_at, owned_at + second_position, borrowed_at, borrowed_at + second_position }) {
			original = CApi.operand (transferred, position);
			CApi.set_operand (transferred, position, CApi.const_null (pointer));
			if (position == owned_at || position == owned_at + second_position) {
				CApi.set_operand (release, 0, original);
			}
			valid_ir (artifact.module);
			artifact.verify_scoped_allocations ();
			CApi.set_operand (release, 0, CApi.const_null (pointer));
			CApi.set_operand (transferred, position, original);
		}
		original = CApi.operand (transferred, borrowed_at + second_position);
		CApi.set_operand (transferred, borrowed_at + second_position, CApi.operand (transferred, borrowed_at));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (transferred, borrowed_at + second_position, original);
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		artifact.verify ();
	}

	internal static void record_context(LlvmModuleArtifact artifact, CApi.ValueRef callee, uint second_position, bool borrowed) throws GLib.Error {
		artifact.verify ();
		assert (CApi.count_params (callee) == 4 && artifact.has_scoped_context_inputs (callee));
		assert (borrowed ? artifact.has_scoped_class_loans (callee) && !artifact.has_scoped_owned_inputs (callee) : artifact.has_scoped_owned_inputs (callee));
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		var builder = CApi.create_builder_in_context (artifact.context);
		var context = CApi.get_param (callee, 3);
		var first_instruction = CApi.first_instruction (CApi.first_block (callee));
		CApi.position_builder_before (builder, first_instruction);
		var local = CApi.build_alloca (builder, pointer, "invalid.record.context.storage");
		var store = CApi.build_store (builder, context, local);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "borrowed scoped context escaped");
		CApi.erase_instruction (store);
		CApi.erase_instruction (local);
		CApi.position_builder_before (builder, first_instruction);
		var integer = CApi.build_ptr_to_int (builder, context, size, "invalid.record.context.integer");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "borrowed scoped context escaped");
		CApi.erase_instruction (integer);
		var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
		CApi.position_builder_before (builder, first_instruction);
		CApi.ValueRef[] context_argument = {
			context
		};
		var invalid = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, context_argument, 1, "");
		CApi.set_instruction_call_conv (invalid, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "cannot be retired by its callee");
		CApi.erase_instruction (invalid);
		var opaque = declaration (artifact, "invalid.record.context.pointer", pointer, new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, first_instruction);
		invalid = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, context_argument, 1, "invalid.context.escape");
		CApi.set_instruction_call_conv (invalid, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "pointer-result lifetime effect");
		CApi.erase_instruction (invalid);
		artifact.verify ();
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocation = instruction;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					release = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var first = CApi.operand (release, 0);
		var loan = CApi.operand (allocation, 0);
		var release_function = CApi.called_value (release);
		CApi.set_operand (allocation, 2, CApi.const_int (size, 1, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (word, 1, 0));
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 1, tag);
		if (!borrowed) {
			CApi.set_operand (release, 0, CApi.const_null (pointer));
		}
		CApi.position_builder_before (builder, release);
		CApi.ValueRef[] extent = new CApi.ValueRef[6];
		for (uint p = 0; p < 6; p++) {
			extent[p] = CApi.operand (allocation, p);
		}
		var second = CApi.build_call (builder, CApi.called_function_type (allocation), CApi.called_value (allocation), extent, 6, "second.context.record.field");
		CApi.set_instruction_call_conv (second, CApi.CallConv.C);
		CApi.ValueRef[] arguments = new CApi.ValueRef[4];
		arguments[0] = first;
		arguments[second_position] = second;
		arguments[second_position == 1 ? 2 : 1] = CApi.const_int (word, 17, 0);
		arguments[3] = loan;
		var call = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, 4, "record.context.call");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		CApi.position_builder_before (builder, CApi.next_instruction (release));
		CApi.ValueRef[] retired = {
			borrowed ? second : CApi.const_null (pointer), tag
		};
		var second_release = CApi.build_call (builder, CApi.global_value_type (release_function), release_function, retired, 2, "second.context.record.retired");
		CApi.set_instruction_call_conv (second_release, CApi.CallConv.C);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		bool missing_contract = false;
		try {
			LlvmScopedAllocationVerifier.verify (artifact.module);
		} catch (LlvmError failure) {
			missing_contract = true;
			Test.message ("record/context inventory refused: %s", failure.message);
		}
		assert (missing_contract);
		foreach (var retirement in new CApi.ValueRef[] { release, second_release }) {
			var original = CApi.operand (retirement, 0);
			CApi.set_operand (retirement, 0, borrowed ? CApi.const_null (pointer) : first);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), borrowed ? "before its derived allocation" : "live owner");
			CApi.set_operand (retirement, 0, original);
		}
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		var missing = declaration (artifact, "invalid.record.context.same.abi", word, second_position == 1 ? new CApi.TypeRef[] { pointer, pointer, word, pointer } : new CApi.TypeRef[] { pointer, word, pointer, pointer });
		CApi.set_function_call_conv (missing, LlvmLowering.CALL_CONVENTION);
		uint target = CApi.operand_count (call) - 1;
		CApi.set_operand (call, target, missing);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (call, target, callee);
		CApi.set_operand (call, 3, first);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (call, 3, loan);
		CApi.position_builder_before (builder, call);
		CApi.ValueRef[] early_context = {
			loan
		};
		var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, early_context, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
		CApi.erase_instruction (early);
		foreach (uint position in new uint[] { 2, 3, 4 }) {
			var original = CApi.operand (allocation, position);
			CApi.set_operand (allocation, position, CApi.const_int (CApi.type_of (original), position == 4 ? 77 : 8, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), borrowed ? "Class allocation shape" : "extent, alignment");
			CApi.set_operand (allocation, position, original);
		}
		CApi.set_operand (call, second_position, first);
		valid_ir (artifact.module);
		if (borrowed) {
			artifact.verify_scoped_allocations ();
		} else {
			refusal_text (() => artifact.verify_scoped_allocations (), "duplicates one allocation");
		} CApi.set_operand (call, second_position, second);
		CApi.position_builder_before (builder, release);
		var repeated = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, 4, "record.context.repeated");
		CApi.set_instruction_call_conv (repeated, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		if (borrowed) {
			artifact.verify_scoped_allocations ();
		} else {
			refusal_text (() => artifact.verify_scoped_allocations (), "live owner");
		} CApi.erase_instruction (repeated);
		foreach (uint position in new uint[] { 0, second_position }) {
			var original = CApi.operand (call, position);
			CApi.set_operand (call, position, CApi.const_null (pointer));
			if (!borrowed) {
				CApi.set_operand (release, 0, original);
			}
			valid_ir (artifact.module);
			artifact.verify_scoped_allocations ();
			CApi.set_operand (release, 0, borrowed ? first : CApi.const_null (pointer));
			CApi.set_operand (call, position, original);
		}
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		artifact.verify ();
	}

	internal static void record_borrows(LlvmModuleArtifact artifact, CApi.ValueRef callee, uint second_position) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_class_loans (callee) && !artifact.has_scoped_owned_inputs (callee) && CApi.count_params (callee) == 3);
		var pointer = CApi.type_of (CApi.get_param (callee, 0));
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		var builder = CApi.create_builder_in_context (artifact.context);
		var first_instruction = CApi.first_instruction (CApi.first_block (callee));
		var release_function = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		var constructor = CApi.named_function (artifact.module, "astra.ctor.0");
		var wrong_method = CApi.named_function (artifact.module, "astra.class.method.1.0");
		assert ((void*) constructor != null && (void*) wrong_method != null);
		foreach (uint position in new uint[] { 0, second_position }) {
			var view = CApi.get_param (callee, position);
			CApi.position_builder_before (builder, first_instruction);
			var local = CApi.build_alloca (builder, pointer, "invalid.record.loan.slot");
			var store = CApi.build_store (builder, view, local);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (store);
			CApi.erase_instruction (local);
			CApi.position_builder_before (builder, first_instruction);
			var integer = CApi.build_ptr_to_int (builder, view, size, "invalid.record.loan.integer");
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (integer);
			CApi.position_builder_before (builder, first_instruction);
			CApi.ValueRef[] retired = {
				view, tag
			};
			var call = CApi.build_call (builder, CApi.global_value_type (release_function), release_function, retired, 2, "invalid.record.loan.retire");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (call);
			var free = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
			CApi.position_builder_before (builder, first_instruction);
			CApi.ValueRef[] argument = {
				view
			};
			call = CApi.build_call (builder, CApi.global_value_type (free), free, argument, 1, "");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (call);
			CApi.position_builder_before (builder, first_instruction);
			CApi.ValueRef[] initialized = {
				view, CApi.const_int (word, 5, 0)
			};
			call = CApi.build_call (builder, CApi.global_value_type (constructor), constructor, initialized, 2, "");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (call);
			CApi.position_builder_before (builder, first_instruction);
			call = CApi.build_call (builder, CApi.global_value_type (wrong_method), wrong_method, argument, 1, "invalid.record.loan.nominal");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (call);
			var opaque = declaration (artifact, "invalid.record.loan.opaque", word, new CApi.TypeRef[] { pointer });
			CApi.position_builder_before (builder, first_instruction);
			call = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, argument, 1, "invalid.record.loan.capture");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (call);
		}
		uint function_convention = CApi.function_call_conv (callee);
		CApi.set_function_call_conv (callee, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact physical signature");
		CApi.set_function_call_conv (callee, function_convention);
		artifact.verify ();
		var fixture = new ScopedLlvmFixture (4, artifact);
		var function = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocation = instruction;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					release = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var first = CApi.operand (release, 0);
		CApi.set_operand (allocation, 2, CApi.const_int (size, 4, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (word, 4, 0));
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 1, tag);
		CApi.position_builder_before (builder, release);
		CApi.ValueRef[] extent = new CApi.ValueRef[6];
		for (uint p = 0; p < 6; p++) {
			extent[p] = CApi.operand (allocation, p);
		}
		var second = CApi.build_call (builder, CApi.called_function_type (allocation), CApi.called_value (allocation), extent, 6, "second.borrowed.record.field");
		CApi.set_instruction_call_conv (second, CApi.CallConv.C);
		foreach (var owner in new CApi.ValueRef[] { first, second }) {
			CApi.ValueRef[] values = {
				owner, CApi.const_int (word, 5, 0)
			};
			var initialized = CApi.build_call (builder, CApi.global_value_type (constructor), constructor, values, 2, "");
			CApi.set_instruction_call_conv (initialized, LlvmLowering.CALL_CONVENTION);
		}
		CApi.ValueRef[] arguments = new CApi.ValueRef[3];
		arguments[0] = first;
		arguments[second_position] = second;
		arguments[second_position == 1 ? 2 : 1] = CApi.const_int (word, 17, 0);
		var borrowed_call = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, 3, "record.borrowed");
		CApi.set_instruction_call_conv (borrowed_call, function_convention);
		CApi.position_builder_before (builder, CApi.next_instruction (release));
		CApi.ValueRef[] retired = {
			second, tag
		};
		var second_release = CApi.build_call (builder, CApi.global_value_type (release_function), release_function, retired, 2, "second.borrowed.record.retired");
		CApi.set_instruction_call_conv (second_release, CApi.CallConv.C);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		foreach (var retirement in new CApi.ValueRef[] { release, second_release }) {
			var original = CApi.operand (retirement, 0);
			CApi.set_operand (retirement, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.set_operand (retirement, 0, original);
		}
		CApi.position_builder_before (builder, borrowed_call);
		CApi.ValueRef[] premature = {
			first, tag
		};
		var early = CApi.build_call (builder, CApi.global_value_type (release_function), release_function, premature, 2, "invalid.record.borrow.retire");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner");
		CApi.erase_instruction (early);
		CApi.position_builder_before (builder, borrowed_call);
		var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
		CApi.ValueRef[] context = {
			CApi.operand (allocation, 0)
		};
		early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, context, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
		CApi.erase_instruction (early);
		CApi.set_instruction_call_conv (borrowed_call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact ownership effect");
		CApi.set_instruction_call_conv (borrowed_call, function_convention);
		var missing = declaration (artifact, "invalid.record.borrow.same.abi", word, second_position == 1 ? new CApi.TypeRef[] { pointer, pointer, word } : new CApi.TypeRef[] { pointer, word, pointer });
		CApi.set_function_call_conv (missing, function_convention);
		uint target = CApi.operand_count (borrowed_call) - 1;
		CApi.set_operand (borrowed_call, target, missing);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact ownership effect");
		CApi.set_operand (borrowed_call, target, callee);
		foreach (uint position in new uint[] { 2, 3, 4 }) {
			var original = CApi.operand (allocation, position);
			CApi.set_operand (allocation, position, CApi.const_int (CApi.type_of (original), position == 4 ? 77 : 8, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact Class allocation shape");
			CApi.set_operand (allocation, position, original);
		}
		CApi.position_builder_before (builder, CApi.next_instruction (second_release));
		var stale = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), first, "invalid.retired.record.loan");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner");
		CApi.erase_instruction (stale);
		CApi.position_builder_before (builder, release);
		var repeated = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, 3, "record.borrowed.again");
		CApi.set_instruction_call_conv (repeated, function_convention);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.erase_instruction (repeated);
		CApi.set_operand (borrowed_call, second_position, first);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (borrowed_call, second_position, second);
		foreach (uint position in new uint[] { 0, second_position }) {
			var original = CApi.operand (borrowed_call, position);
			CApi.set_operand (borrowed_call, position, CApi.const_null (pointer));
			valid_ir (artifact.module);
			artifact.verify_scoped_allocations ();
			CApi.set_operand (borrowed_call, position, original);
		}
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		artifact.verify ();
	}

	internal static void record_inputs(LlvmModuleArtifact artifact, CApi.ValueRef callee, uint second_position) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_owned_inputs (callee) && CApi.count_params (callee) == 3);
		var release_function = CApi.named_function (artifact.module, "astra_context17_release_origin_checked");
		var retirements = new GenericArray<void*> ();
		for (var block = CApi.first_block (callee); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) release_function) {
					retirements.add ((void*) instruction);
				}
			}
		}
		assert (retirements.length == 2);
		var pointer = CApi.type_of (CApi.get_param (callee, 0));
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (void* item in retirements) {
			var retirement = (CApi.ValueRef) item;
			var original = CApi.operand (retirement, 0);
			CApi.set_operand (retirement, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
			CApi.set_operand (retirement, 0, original);
			var other = (void*) original == (void*) CApi.get_param (callee, 0) ? CApi.get_param (callee, second_position) : CApi.get_param (callee, 0);
			CApi.set_operand (retirement, 0, other);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
			CApi.set_operand (retirement, 0, original);
		}
		var retired = (CApi.ValueRef) retirements[0];
		CApi.position_builder_before (builder, CApi.next_instruction (retired));
		CApi.ValueRef[] repeated = {
			CApi.operand (retired, 0), CApi.operand (retired, 1)
		};
		var duplicate = CApi.build_call (builder, CApi.global_value_type (release_function), release_function, repeated, 2, "invalid.record.field.retire");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.erase_instruction (duplicate);
		artifact.verify ();
		var fixture = new ScopedLlvmFixture (4, artifact);
		var function = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_allocate_mode")) {
					allocation = instruction;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					release = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var first = CApi.operand (release, 0);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		CApi.set_operand (allocation, 2, CApi.const_int (size, 1, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (word, 1, 0));
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 0, CApi.const_null (pointer));
		CApi.set_operand (release, 1, tag);
		CApi.position_builder_before (builder, release);
		CApi.ValueRef[] extent = new CApi.ValueRef[6];
		for (uint p = 0; p < 6; p++) {
			extent[p] = CApi.operand (allocation, p);
		}
		var second = CApi.build_call (builder, CApi.called_function_type (allocation), CApi.called_value (allocation), extent, 6, "second.record.field");
		CApi.set_instruction_call_conv (second, CApi.CallConv.C);
		CApi.ValueRef[] arguments = new CApi.ValueRef[3];
		arguments[0] = first;
		arguments[second_position] = second;
		arguments[second_position == 1 ? 2 : 1] = CApi.const_int (word, 17, 0);
		var call = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, 3, "record.consumed");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (call, second_position, first);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "duplicates one allocation");
		CApi.set_operand (call, second_position, second);
		foreach (uint position in new uint[] { 0, second_position }) {
			var original = CApi.operand (call, position);
			CApi.set_operand (call, position, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.set_operand (release, 0, original);
			valid_ir (artifact.module);
			artifact.verify_scoped_allocations ();
			CApi.set_operand (release, 0, CApi.const_null (pointer));
			CApi.set_operand (call, position, original);
		}
		uint convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "type, extent, alignment");
		CApi.set_instruction_call_conv (call, convention);
		var missing = declaration (artifact, "invalid.record.same.abi", word, second_position == 1 ? new CApi.TypeRef[] { pointer, pointer, word } : new CApi.TypeRef[] { pointer, word, pointer });
		CApi.set_function_call_conv (missing, convention);
		uint target = CApi.operand_count (call) - 1;
		CApi.set_operand (call, target, missing);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact ownership effect");
		CApi.set_operand (call, target, callee);
		foreach (uint position in new uint[] { 2, 3, 4 }) {
			var original = CApi.operand (allocation, position);
			CApi.set_operand (allocation, position, CApi.const_int (CApi.type_of (original), position == 4 ? 77 : 8, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "type, extent, alignment");
			CApi.set_operand (allocation, position, original);
		}
		CApi.position_builder_before (builder, release);
		var stale = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), first, "invalid.consumed.record.field");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner");
		CApi.erase_instruction (stale);
		CApi.position_builder_before (builder, call);
		var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
		CApi.ValueRef[] context = {
			CApi.operand (allocation, 0)
		};
		var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, context, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
		CApi.erase_instruction (early);
		CApi.position_builder_before (builder, release);
		duplicate = CApi.build_call (builder, CApi.global_value_type (callee), callee, arguments, 3, "invalid.record.reuse");
		CApi.set_instruction_call_conv (duplicate, convention);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live owner");
		CApi.erase_instruction (duplicate);
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		artifact.verify ();
	}

	internal static void scalar_field_loan(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.ValueRef caller, bool child) throws GLib.Error {
		artifact.verify ();
		assert (artifact.has_scoped_class_loans (function));
		CApi.ValueRef address = (CApi.ValueRef) null;
		CApi.ValueRef read = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.LOAD && CApi.opcode (CApi.operand (instruction, 0)) == CApi.Opcode.GEP) {
					read = instruction;
					address = CApi.operand (instruction, 0);
				}
			}
		}
		assert ((void*) address != null && (void*) read != null);
		var layout = CApi.gep_source_type (address);
		var view = CApi.get_param (function, 0);
		var pointer = CApi.type_of (view);
		var word = CApi.type_of (read);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, read);
		var write = CApi.build_store (builder, CApi.const_null (word), address);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.erase_instruction (write);
		CApi.position_builder_before (builder, read);
		var local = CApi.build_alloca (builder, pointer, "invalid.field.address.slot");
		write = CApi.build_store (builder, address, local);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.erase_instruction (write);
		CApi.erase_instruction (local);
		CApi.position_builder_before (builder, read);
		var opaque = declaration (artifact, "invalid.field.address.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.ValueRef[] arguments = {
			address
		};
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.erase_instruction (escaped);
		CApi.position_builder_before (builder, read);
		var wrong_read = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 64), address, "invalid.field.width");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.erase_instruction (wrong_read);
		CApi.set_volatile (read, 1);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.set_volatile (read, 0);
		CApi.set_ordering (read, 2);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.set_ordering (read, 0);
		uint alignment = CApi.get_alignment (read);
		CApi.set_alignment (read, 4096);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.set_alignment (read, 1);
		artifact.verify_scoped_allocations ();
		CApi.set_alignment (read, alignment);
		CApi.position_builder_before (builder, read);
		var other_member = CApi.build_struct_gep (builder, layout, view, 1, "invalid.borrowed.member");
		CApi.set_operand (read, 0, other_member);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scalar field loan");
		CApi.set_operand (read, 0, address);
		CApi.erase_instruction (other_member);
		var base_index = CApi.operand (address, 1);
		CApi.set_operand (address, 1, CApi.const_int (CApi.type_of (base_index), 1, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.set_operand (address, 1, CApi.get_param (function, 1));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.set_operand (address, 1, base_index);
		CApi.position_builder_before (builder, read);
		var wrong_layout = CApi.struct_create_named (artifact.context, "invalid.borrowed.layout");
		CApi.TypeRef[] fields = {
			word
		};
		CApi.struct_set_body (wrong_layout, fields, 1, 0);
		var projection = CApi.build_struct_gep (builder, wrong_layout, view, 0, "invalid.borrowed.projection");
		CApi.set_operand (read, 0, projection);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.set_operand (read, 0, address);
		CApi.erase_instruction (projection);
		CApi.position_builder_before (builder, read);
		projection = CApi.build_struct_gep (builder, layout, view, 1, "ordinary.wide.projection");
		var wide_read = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 64), projection, "ordinary.wide.read");
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.erase_instruction (wide_read);
		CApi.erase_instruction (projection);
		if (child) {
			CApi.position_builder_before (builder, read);
			projection = CApi.build_struct_gep (builder, layout, view, 2, "invalid.borrowed.owned.field");
			var owner_read = CApi.build_load (builder, pointer, projection, "invalid.borrowed.owned.read");
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (owner_read);
			CApi.erase_instruction (projection);
			CApi.dispose_builder (builder);
			artifact.verify ();
			return;
		}
		var release = CApi.named_function (artifact.module, "astra_context17_release_origin_checked");
		var disposals = new GenericArray<void*> ();
		CApi.ValueRef lent = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if ((void*) CApi.called_value (instruction) == (void*) function) {
					lent = instruction;
				}
				if ((void*) CApi.called_value (instruction) == (void*) release) {
					disposals.add ((void*) instruction);
				}
			}
		}
		assert ((void*) lent != null && disposals.length > 0);
		foreach (void* item in disposals) {
			var disposal = (CApi.ValueRef) item;
			var owner = CApi.operand (disposal, 0);
			CApi.set_operand (disposal, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
			CApi.set_operand (disposal, 0, owner);
		}
		CApi.position_builder_before (builder, lent);
		var disposal = (CApi.ValueRef) disposals[0];
		CApi.ValueRef[] retired = {
			CApi.operand (lent, 0), CApi.operand (disposal, 1)
		};
		var premature = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "invalid.borrowed.retirement");
		CApi.set_instruction_call_conv (premature, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (premature);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void exception_repeat(LlvmModuleArtifact artifact, CApi.ValueRef callee, CApi.ValueRef destructor, CApi.ValueRef tag) throws GLib.Error {
		artifact.verify ();
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var function = declaration (artifact, "exception.repeat", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { word, word });
		var builder = CApi.create_builder_in_context (artifact.context);
		var entry = CApi.append_basic_block_in_context (artifact.context, function, "entry");
		var loop = CApi.append_basic_block_in_context (artifact.context, function, "loop");
		var body = CApi.append_basic_block_in_context (artifact.context, function, "body");
		var failure = CApi.append_basic_block_in_context (artifact.context, function, "failure");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "done");
		var end = CApi.append_basic_block_in_context (artifact.context, function, "end");
		CApi.position_builder_at_end (builder, entry);
		var open = declaration (artifact, "astra_context17_open_scoped", pointer, new CApi.TypeRef[] { pointer, word, word, word });
		CApi.ValueRef[] backing = {
			CApi.const_null (pointer), CApi.const_int (word, 4097, 0), CApi.const_int (word, 1, 0), CApi.const_int (word, 7, 0)
		};
		var context = CApi.build_call (builder, CApi.global_value_type (open), open, backing, 4, "context");
		CApi.set_instruction_call_conv (context, CApi.CallConv.C);
		CApi.build_br (builder, loop);
		CApi.position_builder_at_end (builder, loop);
		var remaining = CApi.build_phi (builder, word, "remaining");
		var zero = CApi.const_int (word, 0, 0);
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.SGT, remaining, zero, "more"), body, end);
		CApi.position_builder_at_end (builder, body);
		var allocate = declaration (artifact, "astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
		CApi.ValueRef[] extent = {
			context, CApi.const_int (size, 1, 0), CApi.const_int (size, 4, 0), CApi.const_int (word, 4, 0), tag, CApi.const_int (word, 3, 0)
		};
		var owner = CApi.build_call (builder, CApi.global_value_type (allocate), allocate, extent, 6, "fresh.owner");
		CApi.set_instruction_call_conv (owner, CApi.CallConv.C);
		CApi.ValueRef[] inputs = {
			owner, CApi.get_param (function, 1)
		};
		var called = CApi.build_call (builder, CApi.global_value_type (callee), callee, inputs, 2, "checked.error");
		CApi.set_instruction_call_conv (called, LlvmLowering.CALL_CONVENTION);
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, called, CApi.const_null (pointer), "succeeded"), done, failure);
		CApi.position_builder_at_end (builder, failure);
		CApi.ValueRef[] payload = {
			called
		};
		var cleaned = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, payload, 1, "");
		CApi.set_instruction_call_conv (cleaned, LlvmLowering.CALL_CONVENTION);
		var free = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		var released = CApi.build_call (builder, CApi.global_value_type (free), free, payload, 1, "");
		CApi.set_instruction_call_conv (released, CApi.CallConv.C);
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		var next = CApi.build_sub (builder, remaining, CApi.const_int (word, 1, 0), "next");
		CApi.build_br (builder, loop);
		var count = CApi.get_param (function, 0);
		CApi.add_incoming (remaining, &count, &entry, 1);
		CApi.add_incoming (remaining, &next, &done, 1);
		CApi.position_builder_at_end (builder, end);
		var destroy = declaration (artifact, "astra_context17_destroy", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.ValueRef[] loan = {
			context
		};
		var retired = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, loan, 1, "");
		CApi.set_instruction_call_conv (retired, CApi.CallConv.C);
		CApi.build_ret_void (builder);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (cleaned, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "retire");
		CApi.set_operand (cleaned, 0, called);
		CApi.set_operand (released, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "retire");
		CApi.set_operand (released, 0, called);
		CApi.position_builder_before (builder, CApi.next_instruction (released));
		var duplicate = CApi.build_call (builder, CApi.global_value_type (free), free, payload, 1, "");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing or nonnull allocation guard");
		CApi.erase_instruction (duplicate);
		CApi.position_builder_before (builder, owner);
		var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, loan, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live");
		CApi.erase_instruction (early);
		var release = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		CApi.position_builder_before (builder, CApi.next_instruction (called));
		CApi.ValueRef[] stale = {
			owner, tag
		};
		var reused = CApi.build_call (builder, CApi.global_value_type (release), release, stale, 2, "invalid.old.input");
		CApi.set_instruction_call_conv (reused, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
		CApi.erase_instruction (reused);
		var alignment = CApi.operand (owner, 3);
		CApi.set_operand (owner, 3, CApi.const_int (word, 8, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "type, extent, alignment");
		CApi.set_operand (owner, 3, alignment);
		CApi.dispose_builder (builder);
		artifact.verify_scoped_allocations ();
		CApi.delete_function (function);
		artifact.verify ();
	}

	internal static void exception_empty(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.ValueRef callee, uint retained_position, uint empty_position, bool consumed, bool success) throws GLib.Error {
		artifact.verify ();
		var retained = CApi.get_param (function, retained_position);
		CApi.ValueRef call = (CApi.ValueRef) null;
		var releases = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if ((void*) CApi.called_value (instruction) == (void*) callee) {
					call = instruction;
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked") && (void*) CApi.operand (instruction, 0) == (void*) retained) {
					releases.add ((void*) instruction);
				}
			}
		}
		assert ((void*) call != null);
		var empty = CApi.operand (call, empty_position);
		assert ((void*) CApi.is_constant_pointer_null (empty) != null);
		CApi.set_operand (call, empty_position, retained);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), consumed ? "duplicates one allocation across consuming inputs" : "exact live owner");
		CApi.set_operand (call, empty_position, empty);
		var convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), success ? "type, extent, alignment" : "exact physical ABI");
		CApi.set_instruction_call_conv (call, convention);
		if (!consumed) {
			assert (releases.length != 0);
			foreach (void* value in releases) {
				var release = (CApi.ValueRef) value;
				CApi.set_operand (release, 0, empty);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
				CApi.set_operand (release, 0, retained);
				var tag = CApi.operand (release, 1);
				CApi.set_operand (release, 1, CApi.const_int (CApi.type_of (tag), 7, 0));
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation tag");
				CApi.set_operand (release, 1, tag);
			}
		}
		artifact.verify ();
	}

	internal static void exception_success(LlvmModuleArtifact artifact, CApi.ValueRef function, uint input_position) throws GLib.Error {
		artifact.verify ();
		var input = CApi.get_param (function, input_position);
		var output = CApi.get_param (function, 0);
		var pointer = CApi.type_of (input);
		var empty = CApi.const_null (pointer);
		CApi.ValueRef published = (CApi.ValueRef) null, failure = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) output) {
					published = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.RET && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					failure = instruction;
				}
			}
		}
		assert ((void*) published != null && (void*) failure != null);
		var builder = CApi.create_builder_in_context (artifact.context);
		var root = CApi.operand (failure, 0);
		CApi.set_operand (published, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "null success retains its input owner");
		CApi.set_operand (published, 0, input);
		CApi.position_builder_before (builder, published);
		var local = CApi.build_alloca (builder, pointer, "invalid.dual.success.slot");
		CApi.set_operand (published, 1, local);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "normal return lost its exact success publication");
		CApi.set_operand (published, 1, output);
		CApi.erase_instruction (local);
		CApi.position_builder_before (builder, CApi.next_instruction (published));
		var duplicate = CApi.build_store (builder, empty, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "published more than once");
		CApi.erase_instruction (duplicate);
		CApi.set_operand (failure, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "normal return lost its exact success publication");
		CApi.set_operand (failure, 0, root);
		CApi.set_operand (failure, 0, input);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.set_operand (failure, 0, root);
		CApi.set_operand (failure, 0, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "success output escaped");
		CApi.set_operand (failure, 0, root);
		var opaque = declaration (artifact, "invalid.dual.output.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, published);
		CApi.ValueRef[] inputs = {
			output
		};
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, inputs, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "success output escaped");
		CApi.erase_instruction (escaped);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void exception_forward(LlvmModuleArtifact artifact, CApi.ValueRef function, uint input_position = 0) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef returned = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) == CApi.Opcode.RET && (void*) CApi.is_constant_pointer_null (CApi.operand (end, 0)) == null) {
				returned = end;
			}
		}
		assert ((void*) returned != null);
		var root = CApi.operand (returned, 0);
		var pointer = CApi.type_of (root);
		var empty = CApi.const_null (pointer);
		var input = CApi.get_param (function, input_position);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.set_operand (returned, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (returned, 0, root);
		CApi.set_operand (returned, 0, input);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
		CApi.set_operand (returned, 0, root);
		var free = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, returned);
		CApi.ValueRef[] inputs = {
			root
		};
		var early = CApi.build_call (builder, CApi.global_value_type (free), free, inputs, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "retired before its owned field cleanup");
		CApi.erase_instruction (early);
		var opaque = declaration (artifact, "invalid.exception.forward.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, returned);
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, inputs, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "address escaped its local frame");
		CApi.erase_instruction (escaped);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void exception_null_handles(LlvmModuleArtifact artifact, CApi.ValueRef function) throws GLib.Error {
		artifact.verify ();
		var input = CApi.get_param (function, 0);
		uint count = 0;
		var phis = new GenericArray<void*> ();
		for (var use = CApi.first_use (input); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) != null && CApi.opcode (user) == CApi.Opcode.PHI && CApi.incoming_count (user) == 2) {
				phis.add ((void*) user);
			}
		}
		foreach (void* value in phis) {
			var phi = (CApi.ValueRef) value;
			for (uint i = 0; i < 2; i++) {
				var empty = CApi.incoming_value (phi, i);
				if ((void*) CApi.is_constant_pointer_null (empty) == null || (void*) CApi.incoming_value (phi, 1 - i) != (void*) input) {
					continue;
				}
				CApi.set_operand (phi, i, input);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
				CApi.set_operand (phi, i, empty);
				CApi.set_operand (phi, 1 - i, empty);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation", "scoped receiver requires its exact allocation or borrowed origin");
				CApi.set_operand (phi, 1 - i, input);
				count++;
			}
		}
		assert (count != 0);
		artifact.verify ();
		Test.message ("conditional input PHIs: %u", count);
	}

	internal static void exception_catch(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.ValueRef callee, bool generation, CApi.ValueRef constructor = (CApi.ValueRef) null, bool require_alias = true) throws GLib.Error {
		artifact.verify ();
		var destructors = new GenericArray<void*> ();
		var frees = new GenericArray<void*> ();
		CApi.ValueRef called = (CApi.ValueRef) null, alias = (CApi.ValueRef) null, release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if ((void*) CApi.called_value (instruction) == (void*) callee) {
					called = instruction;
				}
				if ((void*) constructor != null && (void*) CApi.called_value (instruction) == (void*) constructor) {
					called = CApi.operand (instruction, 0);
				}
				if (LlvmScopedHeapCarrier.named_call (instruction, "free") && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					frees.add ((void*) instruction);
				}
				if ((void*) CApi.is_instruction (CApi.called_value (instruction)) != null && CApi.opcode (CApi.called_value (instruction)) == CApi.Opcode.LOAD && CApi.argument_count (instruction) == 1 && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null && CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.VOID) {
					destructors.add ((void*) instruction);
				}
			}
		}
		assert ((void*) called != null && destructors.length != 0 && frees.length != 0);
		for (var use = CApi.first_use (called); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) == null || CApi.opcode (user) != CApi.Opcode.PHI || CApi.incoming_count (user) != 2) {
				continue;
			}
			for (uint i = 0; i < 2; i++) {
				if ((void*) CApi.is_constant_pointer_null (CApi.incoming_value (user, i)) != null) {
					alias = user;
				}
			}
		}
		assert ((void*) alias != null || !require_alias);
		for (var block = CApi.first_block (callee); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					release = instruction;
				}
			}
		}
		assert (!generation || (void*) release != null);
		var pointer = CApi.type_of (called);
		var empty = CApi.const_null (pointer);
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (void* item in destructors) {
			var call = (CApi.ValueRef) item;
			var root = CApi.operand (call, 0);
			var target = CApi.called_value (call);
			var address = CApi.operand (target, 0);
			var index = CApi.operand (address, 2);
			CApi.set_operand (call, 0, empty);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), (void*) constructor == null && require_alias ? "unretired scoped allocation" : "retired before its owned field cleanup");
			CApi.set_operand (call, 0, root);
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact dynamic destructor ABI");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			CApi.set_operand (address, 2, CApi.const_int (CApi.type_of (index), 2, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "address escaped its local frame");
			CApi.set_operand (address, 2, index);
			CApi.position_builder_before (builder, CApi.next_instruction (call));
			CApi.ValueRef[] inputs = {
				root
			};
			var duplicate = CApi.build_call (builder, CApi.called_function_type (call), target, inputs, 1, "");
			CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact occupied live carrier");
			CApi.erase_instruction (duplicate);
			CApi.ValueRef branch = (CApi.ValueRef) null;
			for (var use = CApi.first_use (target); (void*) use != null; use = CApi.next_use (use)) {
				var comparison = CApi.user (use);
				if ((void*) CApi.is_instruction (comparison) == null || CApi.opcode (comparison) != CApi.Opcode.ICMP) {
					continue;
				}
				for (var test = CApi.first_use (comparison); (void*) test != null; test = CApi.next_use (test)) {
					var user = CApi.user (test);
					if (CApi.opcode (user) == CApi.Opcode.COND_BR) {
						branch = user;
					}
				}
			}
			assert ((void*) branch != null);
			var condition = CApi.operand (branch, 0);
			CApi.set_operand (branch, 0, CApi.const_int (CApi.type_of (condition), 0, 0));
			valid_ir (artifact.module);
			artifact.verify_scoped_allocations ();
			CApi.set_operand (branch, 0, CApi.const_int (CApi.type_of (condition), 1, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), (void*) constructor == null && require_alias ? "unretired scoped allocation" : "retired before its owned field cleanup");
			CApi.set_operand (branch, 0, condition);
		}
		foreach (void* item in frees) {
			var call = (CApi.ValueRef) item;
			var root = CApi.operand (call, 0);
			CApi.set_operand (call, 0, empty);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired heap carrier");
			CApi.set_operand (call, 0, root);
			CApi.position_builder_before (builder, CApi.next_instruction (call));
			CApi.ValueRef[] inputs = {
				root
			};
			var duplicate = CApi.build_call (builder, CApi.called_function_type (call), CApi.called_value (call), inputs, 1, "");
			CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing or nonnull allocation guard");
			CApi.erase_instruction (duplicate);
			CApi.position_builder_before (builder, CApi.next_instruction (call));
			CApi.TypeRef[] fields = {
				pointer, pointer
			};
			var header = CApi.struct_type_in_context (artifact.context, fields, 2, 0);
			var projection = CApi.build_struct_gep (builder, header, root, 0, "invalid.retired.exception.header");
			var loaded = CApi.build_load (builder, pointer, projection, "invalid.retired.exception.descriptor");
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing or nonnull allocation guard");
			CApi.erase_instruction (loaded);
			CApi.erase_instruction (projection);
		}
		if ((void*) constructor == null && (void*) alias != null) {
			var first = CApi.incoming_value (alias, 0);
			var second = CApi.incoming_value (alias, 1);
			CApi.set_operand (alias, 0, second);
			CApi.set_operand (alias, 1, first);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nullable exception alias discards");
			CApi.set_operand (alias, 0, first);
			CApi.set_operand (alias, 1, second);
		}
		CApi.dispose_builder (builder);
		artifact.verify ();
		if (generation) {
			exception_generation (artifact, callee, CApi.operand (release, 1));
		}
		Test.message ("catch cleanup sites: %u destructors, %u backing releases", destructors.length, frees.length);
	}

	private static void exception_generation(LlvmModuleArtifact artifact, CApi.ValueRef callee, CApi.ValueRef tag) throws GLib.Error {
		for (int mode = 0; mode < 2; mode++) {
			var pointer = CApi.pointer_type_in_context (artifact.context, 0);
			var word = CApi.int32_type_in_context (artifact.context);
			var size = CApi.int_type_in_context (artifact.context, 64);
			var boolean = CApi.int1_type_in_context (artifact.context);
			var function = declaration (artifact, "invalid.exception.carrier.%d".printf (mode), CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { boolean });
			var builder = CApi.create_builder_in_context (artifact.context);
			var entry = CApi.append_basic_block_in_context (artifact.context, function, "entry");
			var loop = CApi.append_basic_block_in_context (artifact.context, function, "loop");
			var back = CApi.append_basic_block_in_context (artifact.context, function, "back");
			var end = CApi.append_basic_block_in_context (artifact.context, function, "end");
			CApi.position_builder_at_end (builder, entry);
			var open = declaration (artifact, "astra_context17_open_scoped", pointer, new CApi.TypeRef[] { pointer, word, word, word });
			CApi.ValueRef[] backing = {
				CApi.const_null (pointer), CApi.const_int (word, 4097, 0), CApi.const_int (word, 1, 0), CApi.const_int (word, 7, 0)
			};
			var context = CApi.build_call (builder, CApi.global_value_type (open), open, backing, 4, "context");
			CApi.set_instruction_call_conv (context, CApi.CallConv.C);
			var allocate = declaration (artifact, "astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
			CApi.ValueRef[] extent = {
				context, CApi.const_int (size, 1, 0), CApi.const_int (size, 4, 0), CApi.const_int (word, 4, 0), tag, CApi.const_int (word, 3, 0)
			};
			var owner = CApi.build_call (builder, CApi.global_value_type (allocate), allocate, extent, 6, "owner");
			CApi.set_instruction_call_conv (owner, CApi.CallConv.C);
			if (mode == 0) {
				CApi.build_br (builder, loop);
				CApi.position_builder_at_end (builder, loop);
				var prior = CApi.build_phi (builder, pointer, "invalid.prior.exception");
				CApi.ValueRef[] inputs = {
					owner, CApi.const_int (word, 1, 0)
				};
				var called = CApi.build_call (builder, CApi.global_value_type (callee), callee, inputs, 2, "next.exception");
				CApi.set_instruction_call_conv (called, LlvmLowering.CALL_CONVENTION);
				CApi.build_cond_br (builder, CApi.get_param (function, 0), back, end);
				CApi.position_builder_at_end (builder, back);
				CApi.build_br (builder, loop);
				CApi.position_builder_at_end (builder, end);
				CApi.build_ret_void (builder);
				var empty = CApi.const_null (pointer);
				CApi.add_incoming (prior, &empty, &entry, 1);
				CApi.add_incoming (prior, &called, &back, 1);
			} else {
				CApi.ValueRef[] inputs = {
					owner, CApi.const_int (word, 1, 0)
				};
				var called = CApi.build_call (builder, CApi.global_value_type (callee), callee, inputs, 2, "next.exception");
				CApi.set_instruction_call_conv (called, LlvmLowering.CALL_CONVENTION);
				var empty = CApi.const_null (pointer);
				var success = CApi.build_icmp (builder, CApi.IntPredicate.EQ, called, empty, "observed.success");
				CApi.build_cond_br (builder, success, loop, back);
				CApi.position_builder_at_end (builder, loop);
				CApi.build_br (builder, end);
				CApi.position_builder_at_end (builder, back);
				CApi.build_br (builder, end);
				CApi.position_builder_at_end (builder, end);
				var discarded = CApi.build_phi (builder, pointer, "invalid.discarded.exception");
				CApi.add_incoming (discarded, &called, &loop, 1);
				CApi.add_incoming (discarded, &empty, &back, 1);
				CApi.build_unreachable (builder);
			} CApi.dispose_builder (builder);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), mode == 0 ? "predates its backing generation" : "nullable exception alias discards");
			CApi.delete_function (function);
			artifact.verify ();
		}
	}

	internal static void exception_caller(LlvmModuleArtifact artifact, CApi.ValueRef caller, CApi.ValueRef callee, uint input_position, CApi.ValueRef constructor, bool multiple = false) throws GLib.Error {
		artifact.verify ();
		var input = CApi.get_param (caller, input_position);
		var pointer = CApi.type_of (input);
		var empty = CApi.const_null (pointer);
		CApi.ValueRef called = (CApi.ValueRef) null, returned = (CApi.ValueRef) null, branch = (CApi.ValueRef) null, release = (CApi.ValueRef) null, field = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) callee) {
					called = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.RET && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					returned = instruction;
				}
			}
		}
		assert ((void*) called != null && (void*) returned != null && (void*) CApi.operand (returned, 0) == (void*) called);
		for (var use = CApi.first_use (called); (void*) use != null; use = CApi.next_use (use)) {
			var comparison = CApi.user (use);
			if ((void*) CApi.is_instruction (comparison) == null || CApi.opcode (comparison) != CApi.Opcode.ICMP) {
				continue;
			}
			for (var test = CApi.first_use (comparison); (void*) test != null; test = CApi.next_use (test)) {
				var user = CApi.user (test);
				if (CApi.opcode (user) == CApi.Opcode.COND_BR && CApi.successor_count (user) == 2) {
					branch = user;
				}
			}
		}
		assert ((void*) branch != null);
		for (var block = CApi.first_block (callee); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked") && (void*) CApi.operand (instruction, 0) == (void*) CApi.get_param (callee, input_position)) {
					release = instruction;
				}
			}
		}
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if ((void*) field == null && CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.POINTER) {
					field = CApi.operand (instruction, 1);
				}
			}
		}
		assert ((void*) release != null && (void*) field != null && CApi.opcode (field) == CApi.Opcode.GEP);
		var layout = CApi.gep_source_type (field);
		uint member = (uint) CApi.const_int_zext (CApi.operand (field, 2));
		var builder = CApi.create_builder_in_context (artifact.context);
		var condition = CApi.operand (branch, 0);
		for (uint selected = 0; selected < 2; selected++) {
			CApi.set_operand (branch, 0, CApi.const_int (CApi.type_of (condition), selected, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), selected == 0 ? "exact live backing or nonnull allocation guard" : "unobserved call outcome");
			CApi.set_operand (branch, 0, condition);
		}
		CApi.set_operand (returned, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (returned, 0, called);
		CApi.set_operand (returned, 0, input);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
		CApi.set_operand (returned, 0, called);
		CApi.position_builder_before (builder, CApi.next_instruction (called));
		CApi.ValueRef[] old_owner = {
			input, CApi.operand (release, 1)
		};
		var old_release = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), old_owner, 2, "invalid.exception.old.owner");
		CApi.set_instruction_call_conv (old_release, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
		CApi.erase_instruction (old_release);
		var free = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, CApi.next_instruction (called));
		CApi.ValueRef[] root = {
			called
		};
		var early = CApi.build_call (builder, CApi.global_value_type (free), free, root, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing or nonnull allocation guard");
		CApi.erase_instruction (early);
		CApi.position_builder_before (builder, CApi.next_instruction (called));
		var projection = CApi.build_struct_gep (builder, layout, called, member, "invalid.unobserved.exception.payload");
		var loaded = CApi.build_load (builder, pointer, projection, "invalid.unobserved.payload.owner");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing or nonnull allocation guard");
		CApi.erase_instruction (loaded);
		CApi.erase_instruction (projection);
		CApi.position_builder_before (builder, returned);
		projection = CApi.build_struct_gep (builder, layout, called, member, "observed.exception.payload");
		loaded = CApi.build_load (builder, pointer, projection, "observed.payload.owner");
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.ValueRef[] payload = {
			loaded, CApi.operand (release, 1)
		};
		var child_release = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), payload, 2, "invalid.exception.payload.retirement");
		CApi.set_instruction_call_conv (child_release, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live payload field");
		CApi.erase_instruction (child_release);
		CApi.erase_instruction (loaded);
		CApi.erase_instruction (projection);
		CApi.position_builder_before (builder, returned);
		CApi.TypeRef[] header_fields = {
			pointer, pointer
		};
		var header = CApi.struct_type_in_context (artifact.context, header_fields, 2, 0);
		projection = CApi.build_struct_gep (builder, header, called, 0, "invalid.inherited.exception.descriptor");
		var overwrite = CApi.build_store (builder, empty, projection);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "cannot overwrite its inherited descriptor");
		CApi.erase_instruction (overwrite);
		CApi.erase_instruction (projection);
		var opaque = declaration (artifact, "invalid.exception.caller.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, returned);
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, root, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "address escaped its local frame");
		CApi.erase_instruction (escaped);
		CApi.set_instruction_call_conv (called, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact type, extent, alignment, tag or transfer channel");
		CApi.set_instruction_call_conv (called, LlvmLowering.CALL_CONVENTION);
		var other = CApi.add_function (artifact.module, "invalid.exception.caller.target", CApi.global_value_type (callee));
		CApi.set_function_call_conv (other, LlvmLowering.CALL_CONVENTION);
		CApi.set_operand (called, CApi.operand_count (called) - 1, other);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "transport requires its exact ownership effect");
		CApi.set_operand (called, CApi.operand_count (called) - 1, callee);
		if (multiple) {
			var original = CApi.operand (called, 1);
			CApi.set_operand (called, 1, input);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "duplicates one allocation across consuming inputs");
			CApi.set_operand (called, 1, original);
		}
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void exception_payload(LlvmModuleArtifact artifact, CApi.ValueRef function, uint input_position) throws GLib.Error {
		artifact.verify ();
		var input = CApi.get_param (function, input_position);
		var pointer = CApi.type_of (input);
		var empty = CApi.const_null (pointer);
		CApi.ValueRef returned = (CApi.ValueRef) null, constructed = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.RET && (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					returned = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.CALL) {
					for (uint p = 0; p < CApi.argument_count (instruction); p++) {
						if ((void*) CApi.operand (instruction, p) == (void*) input && CApi.type_kind (CApi.type_of (instruction)) == CApi.TypeKind.VOID) {
							constructed = instruction;
						}
					}
				}
			}
		}
		assert ((void*) returned != null && (void*) constructed != null);
		var root = CApi.operand (returned, 0);
		assert (CApi.opcode (root) == CApi.Opcode.PHI);
		uint live = (void*) CApi.is_constant_pointer_null (CApi.incoming_value (root, 0)) != null ? 1 : 0;
		var backing = CApi.incoming_value (root, live);
		uint child = 0;
		for (uint p = 1; p < CApi.argument_count (constructed); p++) {
			if ((void*) CApi.operand (constructed, p) == (void*) input) {
				child = p;
			}
		}
		assert (child != 0);
		CApi.ValueRef header_store = (CApi.ValueRef) null;
		for (var use = CApi.first_use (root); (void*) use != null; use = CApi.next_use (use)) {
			var address = CApi.user (use);
			if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.GEP || CApi.operand_count (address) != 3 || (void*) CApi.is_constant_int (CApi.operand (address, 2)) == null || CApi.const_int_zext (CApi.operand (address, 2)) != 0) {
				continue;
			}
			for (var access = CApi.first_use (address); (void*) access != null; access = CApi.next_use (access)) {
				var user = CApi.user (access);
				if (CApi.opcode (user) == CApi.Opcode.STORE && (void*) CApi.operand (user, 1) == (void*) address) {
					header_store = user;
				}
			}
		}
		assert ((void*) header_store != null);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.set_operand (returned, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (returned, 0, root);
		CApi.set_operand (returned, 0, input);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
		CApi.set_operand (returned, 0, root);
		var raw_escape = declaration (artifact, "invalid.exception.raw.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, CApi.next_instruction (backing));
		CApi.ValueRef[] raw_arguments = {
			backing
		};
		var raw_call = CApi.build_call (builder, CApi.global_value_type (raw_escape), raw_escape, raw_arguments, 1, "");
		CApi.set_instruction_call_conv (raw_call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "raw allocation escaped");
		CApi.erase_instruction (raw_call);
		CApi.set_operand (constructed, child, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live heap carrier", "exact live payload field");
		CApi.set_operand (constructed, child, input);
		var descriptor = CApi.operand (header_store, 0);
		var address = CApi.operand (header_store, 1);
		CApi.set_operand (header_store, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact descriptor initialization");
		CApi.set_operand (header_store, 0, descriptor);
		CApi.position_builder_before (builder, header_store);
		var local = CApi.build_alloca (builder, pointer, "invalid.exception.descriptor.slot");
		CApi.set_operand (header_store, 1, local);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "initialized before publication");
		CApi.set_operand (header_store, 1, address);
		CApi.erase_instruction (local);
		CApi.position_builder_before (builder, CApi.next_instruction (header_store));
		var duplicate = CApi.build_store (builder, descriptor, address);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact descriptor initialization");
		CApi.erase_instruction (duplicate);
		CApi.set_global_constant (descriptor, 0);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "immutable native descriptor");
		CApi.set_global_constant (descriptor, 1);
		var free = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, returned);
		CApi.ValueRef[] arguments = {
			root
		};
		var retired = CApi.build_call (builder, CApi.global_value_type (free), free, arguments, 1, "");
		CApi.set_instruction_call_conv (retired, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "retired before its owned field cleanup");
		CApi.erase_instruction (retired);
		var opaque = declaration (artifact, "invalid.exception.payload.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, returned);
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "address escaped its local frame");
		CApi.erase_instruction (escaped);
		for (uint p = 0; p < 2; p++) {
			var original = CApi.operand (backing, p);
			CApi.set_operand (backing, p, CApi.const_int (CApi.type_of (original), p == 0 ? 2 : 1, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact Class extent");
			CApi.set_operand (backing, p, original);
		}
		CApi.set_instruction_call_conv (constructed, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact physical signature");
		CApi.set_instruction_call_conv (constructed, LlvmLowering.CALL_CONVENTION);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void exception_fields(LlvmModuleArtifact artifact, CApi.ValueRef constructor, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var input = CApi.get_param (constructor, 2);
		CApi.ValueRef publication = (CApi.ValueRef) null, projection = (CApi.ValueRef) null, load = (CApi.ValueRef) null, release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 0) == (void*) input) {
					publication = instruction;
					projection = CApi.operand (instruction, 1);
				}
			}
		}
		for (var block = CApi.first_block (destructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					release = instruction;
					load = CApi.operand (instruction, 0);
				}
			}
		}
		assert ((void*) publication != null && (void*) projection != null && CApi.opcode (projection) == CApi.Opcode.GEP && CApi.const_int_zext (CApi.operand (projection, 2)) == 3);
		assert ((void*) load != null && CApi.opcode (load) == CApi.Opcode.LOAD && CApi.const_int_zext (CApi.operand (CApi.operand (load, 0), 2)) == 3);
		var builder = CApi.create_builder_in_context (artifact.context);
		var empty = CApi.const_null (pointer);
		var member = CApi.operand (projection, 2);
		for (uint field = 0; field < 2; field++) {
			CApi.set_operand (projection, 2, CApi.const_int (CApi.type_of (member), field, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live field transfer");
			CApi.set_operand (projection, 2, member);
		}
		CApi.set_operand (publication, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live field transfer");
		CApi.set_operand (publication, 0, input);
		CApi.position_builder_before (builder, publication);
		var repeated = CApi.build_store (builder, input, projection);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "one exact allocation transfer");
		CApi.erase_instruction (repeated);
		var child_address = CApi.operand (load, 0);
		var original = CApi.operand (child_address, 2);
		for (uint field = 0; field < 2; field++) {
			CApi.set_operand (child_address, 2, CApi.const_int (CApi.type_of (original), field, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact original owner load");
			CApi.set_operand (child_address, 2, original);
		}
		CApi.set_operand (release, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (release, 0, load);
		CApi.position_builder_before (builder, CApi.next_instruction (release));
		CApi.ValueRef[] arguments = {
			load, CApi.operand (release, 1)
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), arguments, 2, "duplicate.exception.child.retirement");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (duplicate);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	private static void valid_ir(CApi.ModuleRef module) {
		char* message;
		int failed = CApi.verify_module (module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
		string detail = message == null ? "" : (string) message;
		if (message != null) {
			CApi.dispose_message (message);
		}
		if (failed != 0) {
			error ("invalid LLVM control: %s", detail);
		}
	}

	internal static void owner_storage() {
		for (int mode = 32; mode <= 52; mode++) {
			var fixture = new ScopedLlvmFixture (mode);
			fixture.verify_ir ();
			bool rejected = false;
			try {
				LlvmScopedAllocationVerifier.verify (fixture.module);
			} catch (LlvmError failure) {
				rejected = true;
				Test.message ("storage mode %d: %s", mode, failure.message);
			}
			assert (rejected == (mode >= 37 && mode != 51));
		}
	}

	internal static void field_effects(LlvmModuleArtifact artifact) throws GLib.Error {
		var constructor = CApi.named_function (artifact.module, "astra.ctor.1");
		var destructor = CApi.named_function (artifact.module, "astra.dtor.1");
		assert (artifact.has_scoped_owned_inputs (constructor) && artifact.has_scoped_owned_inputs (destructor));
		artifact.verify ();
		var stores = new GenericArray<void*> ();
		var releases = new GenericArray<void*> ();
		var branches = new GenericArray<void*> ();
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.type_kind (CApi.type_of (CApi.operand (instruction, 0))) == CApi.TypeKind.POINTER) {
					stores.add ((void*) instruction);
				}
			}
		}
		for (var block = CApi.first_block (destructor); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) == CApi.Opcode.COND_BR && CApi.successor_count (end) == 2 && CApi.opcode (CApi.operand (end, 0)) == CApi.Opcode.ICMP && CApi.type_kind (CApi.type_of (CApi.operand (CApi.operand (end, 0), 0))) == CApi.TypeKind.POINTER) {
				branches.add ((void*) end);
			}
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t length;
				if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_context17_release_origin_checked") {
					releases.add ((void*) instruction);
				}
			}
		}
		assert (stores.length == 2 && releases.length == 2 && branches.length == 2);
		var first = (CApi.ValueRef) stores[0];
		var incoming = CApi.operand (first, 0);
		var second = (CApi.ValueRef) stores[1];
		var pointer = CApi.type_of (incoming);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.set_operand (first, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "constructor return lost", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		refusal_text (() => artifact.verify_scoped_owned_inputs (), "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		CApi.set_operand (first, 0, incoming);
		CApi.set_operand (first, 0, CApi.operand (second, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		CApi.set_operand (first, 0, incoming);
		var address = CApi.operand (first, 1);
		var member = CApi.operand (address, 2);
		CApi.set_operand (address, 2, CApi.operand (CApi.operand (second, 1), 2));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "physical slot", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		CApi.set_operand (address, 2, member);
		CApi.position_builder_before (builder, CApi.next_instruction (first));
		var stale = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), incoming, "invalid.stored.input");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		CApi.erase_instruction (stale);
		var escape = declaration (artifact, "invalid.field.receiver.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, CApi.first_instruction (CApi.first_block (constructor)));
		CApi.ValueRef[] receiver = {
			CApi.get_param (constructor, 0)
		};
		var escaped = CApi.build_call (builder, CApi.global_value_type (escape), escape, receiver, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "address escaped", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		CApi.erase_instruction (escaped);
		foreach (void* value in releases) {
			var release = (CApi.ValueRef) value;
			var owner = CApi.operand (release, 0);
			CApi.set_operand (release, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
			CApi.set_operand (release, 0, owner);
			var tag = CApi.operand (release, 1);
			CApi.set_operand (release, 1, CApi.const_int (CApi.type_of (tag), 77, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation tag", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
			CApi.set_operand (release, 1, tag);
		}
		foreach (void* value in branches) {
			var branch = (CApi.ValueRef) value;
			var condition = CApi.operand (branch, 0);
			CApi.set_operand (branch, 0, CApi.const_int (CApi.type_of (condition), CApi.predicate (condition) == CApi.IntPredicate.EQ ? 1 : 0, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
			CApi.set_operand (branch, 0, condition);
		}
		CApi.dispose_builder (builder);
		artifact.verify ();
		// A typed field channel still refuses a caller allocation with the
		// wrong original tag, extent or alignment.
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef retirement = (CApi.ValueRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (caller)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (CApi.called_value (instruction), out length);
			if (name == "astra_context17_allocate_mode") {
				allocation = instruction;
			}
			if (name == "astra_context17_release_origin_checked") {
				retirement = instruction;
			}
		}
		assert ((void*) allocation != null && (void*) retirement != null);
		builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, retirement);
		var carrier = CApi.build_alloca (builder, CApi.gep_source_type (address), "carrier");
		CApi.ValueRef[] arguments = {
			carrier, CApi.const_int (CApi.int32_type_in_context (artifact.context), 9, 0), allocation, CApi.const_null (pointer)
		};
		var stored = CApi.build_call (builder, CApi.global_value_type (constructor), constructor, arguments, 4, "");
		CApi.set_instruction_call_conv (stored, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "extent", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		artifact.verify ();
		// Delete the original field read after replacing every live use. Check
		// membership before dereferencing its now-invalid retained LLVM handle.
		var old_load = CApi.operand ((CApi.ValueRef) releases[0], 0);
		assert (CApi.opcode (old_load) == CApi.Opcode.LOAD);
		builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, old_load);
		var new_load = CApi.build_load (builder, pointer, CApi.operand (old_load, 0), "replaced.field.read");
		var users = new GenericArray<void*> ();
		for (var use = CApi.first_use (old_load); (void*) use != null; use = CApi.next_use (use)) {
			users.add ((void*) CApi.user (use));
		}
		foreach (void* value in users) {
			var user = (CApi.ValueRef) value;
			for (uint p = 0; p < CApi.operand_count (user); p++) {
				if ((void*) CApi.operand (user, p) == (void*) old_load) {
					CApi.set_operand (user, p, new_load);
				}
			}
		}
		CApi.erase_instruction (old_load);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact original owner load", "owning sum effect changed", "sum storage lost exact producer/store/call/read publication order or predecessor block");
		CApi.dispose_builder (builder);
	}

	internal static void field_loans(LlvmModuleArtifact artifact, bool prescribed = false) throws GLib.Error {
		var constructor = CApi.named_function (artifact.module, "astra.ctor.1");
		var destructor = CApi.named_function (artifact.module, "astra.dtor.1");
		CApi.TypeRef layout = (CApi.TypeRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (constructor)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) == CApi.Opcode.GEP) {
				layout = CApi.gep_source_type (instruction);
				break;
			}
		}
		assert ((void*) layout != null);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		for (int mode = 0; mode <= (prescribed ? 0 : 15); mode++) {
			var fixture = new ScopedLlvmFixture (4, artifact);
			var caller = CApi.named_function (artifact.module, "exercise");
			CApi.ValueRef allocation = (CApi.ValueRef) null;
			CApi.ValueRef release = (CApi.ValueRef) null;
			CApi.ValueRef destroy = (CApi.ValueRef) null;
			for (var instruction = CApi.first_instruction (CApi.first_block (caller)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t length;
				string name = CApi.value_name (CApi.called_value (instruction), out length);
				if (name == "astra_context17_allocate_mode") {
					allocation = instruction;
				}
				if (name == "astra_context17_release_origin_checked") {
					release = instruction;
				}
				if (name == "astra_context17_destroy") {
					destroy = instruction;
				}
			}
			assert ((void*) allocation != null && (void*) release != null && (void*) destroy != null);
			CApi.set_operand (allocation, 2, CApi.const_int (size, 1, 0));
			CApi.set_operand (allocation, 3, CApi.const_int (word, 1, 0));
			CApi.set_operand (allocation, 4, mode == 14 ? CApi.const_int (size, 77, 0) : tag);
			CApi.set_operand (release, 0, CApi.const_null (pointer));
			CApi.set_operand (release, 1, tag);
			var builder = CApi.create_builder_in_context (artifact.context);
			CApi.position_builder_before (builder, release);
			var carrier = CApi.build_alloca (builder, mode == 15 ? pointer : layout, "field.carrier");
			CApi.ValueRef[] receiver = {
				carrier
			};
			if (mode == 8) {
				var early = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, receiver, 1, "");
				CApi.set_instruction_call_conv (early, LlvmLowering.CALL_CONVENTION);
			}
			var second = CApi.const_null (pointer);
			if (mode == 1) {
				var arguments = new CApi.ValueRef[6];
				for (uint p = 0; p < 6; p++) {
					arguments[p] = CApi.operand (allocation, p);
				}
				second = CApi.build_call (builder, CApi.called_function_type (allocation), CApi.called_value (allocation), arguments, 6, "second.allocation");
				CApi.set_instruction_call_conv (second, CApi.CallConv.C);
			}
			CApi.ValueRef[] inputs = {
				carrier, CApi.const_int (word, 9, 0), allocation, second
			};
			var stored = CApi.build_call (builder, CApi.global_value_type (constructor), constructor, inputs, 4, "");
			CApi.set_instruction_call_conv (stored, LlvmLowering.CALL_CONVENTION);
			if (mode == 6) {
				CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), allocation, "invalid.moved.input");
			}
			if (mode == 5) {
				CApi.ValueRef[] context = {
					CApi.operand (allocation, 0)
				};
				var early = CApi.build_call (builder, CApi.called_function_type (destroy), CApi.called_value (destroy), context, 1, "");
				CApi.set_instruction_call_conv (early, CApi.CallConv.C);
			}
			if (mode == 2 || mode == 3 || mode == 12 || mode == 13) {
				var field = CApi.build_struct_gep (builder, layout, carrier, 1, "owned.field");
				CApi.ValueRef loaded = (CApi.ValueRef) null;
				if (mode != 12) {
					loaded = CApi.build_load (builder, pointer, field, "extracted.owner");
				}
				if (mode != 13) {
					CApi.build_store (builder, CApi.const_null (pointer), field);
				}
				if (mode == 2) {
					CApi.set_operand (release, 0, loaded);
				}
				if (mode == 3) {
					var slot = CApi.build_alloca (builder, pointer, "extracted.storage");
					CApi.build_store (builder, loaded, slot);
					CApi.set_operand (release, 0, CApi.build_load (builder, pointer, slot, "relocated.owner"));
				}
				if (mode == 13) {
					CApi.ValueRef[] owner = {
						loaded, tag
					};
					var retired = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), owner, 2, "invalid.early.field.release");
					CApi.set_instruction_call_conv (retired, CApi.CallConv.C);
				}
			}
			if (mode == 9) {
				receiver[0] = CApi.build_alloca (builder, layout, "different.carrier");
			}
			if (mode == 10) {
				var escape = declaration (artifact, "invalid.carrier.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
				var escaped = CApi.build_call (builder, CApi.global_value_type (escape), escape, receiver, 1, "");
				CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
			}
			if (mode != 4) {
				var retired = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, receiver, 1, "");
				CApi.set_instruction_call_conv (retired, LlvmLowering.CALL_CONVENTION);
			}
			if (mode == 11) {
				var escape = declaration (artifact, "invalid.carrier.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
				var escaped = CApi.build_call (builder, CApi.global_value_type (escape), escape, receiver, 1, "");
				CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
			}
			if (mode == 7) {
				var again = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, receiver, 1, "");
				CApi.set_instruction_call_conv (again, LlvmLowering.CALL_CONVENTION);
			}
			valid_ir (artifact.module);
			bool rejected = false;
			try {
				artifact.verify_scoped_allocations ();
			} catch (LlvmError failure) {
				rejected = true;
				Test.message ("field loan mode %d: %s", mode, failure.message);
			}
			assert (rejected == (prescribed || mode >= 4));
			CApi.dispose_builder (builder);
			fixture.remove_function ();
			artifact.verify ();
		}
	}

	internal static void heap_fields(LlvmModuleArtifact artifact, bool contextual = false, bool fallible = false) throws GLib.Error {
		artifact.verify ();
		var function = CApi.named_function (artifact.module, "astra.fn.0");
		var constructor = CApi.named_function (artifact.module, "astra.ctor.1");
		CApi.ValueRef context = (CApi.ValueRef) null;
		CApi.ValueRef constructed = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if ((void*) CApi.called_value (instruction) == (void*) constructor) {
					constructed = instruction;
				}
				size_t length;
				if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_context17_open_scoped") {
					context = instruction;
				}
			}
		}
		assert ((void*) context != null && (void*) constructed != null);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var provider = declaration (artifact, "astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, constructed);
		CApi.ValueRef[] inputs = {
			context, CApi.const_int (size, 1, 0), CApi.const_int (size, 1, 0), CApi.const_int (word, 1, 0), tag, CApi.const_int (word, 3, 0)
		};
		var allocation = CApi.build_call (builder, CApi.global_value_type (provider), provider, inputs, 6, "heap.field.child");
		CApi.set_instruction_call_conv (allocation, CApi.CallConv.C);
		var original = CApi.operand (constructed, 2);
		assert ((void*) CApi.is_constant_pointer_null (original) != null);
		CApi.set_operand (constructed, 2, allocation);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, constructed);
		var second = CApi.build_call (builder, CApi.global_value_type (provider), provider, inputs, 6, "second.heap.field.child");
		CApi.set_instruction_call_conv (second, CApi.CallConv.C);
		var original_second = CApi.operand (constructed, 3);
		assert ((void*) CApi.is_constant_pointer_null (original_second) != null);
		CApi.set_operand (constructed, 3, second);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var observation = CApi.named_function (artifact.module, "astra.class.method.1.0");
		assert ((void*) observation != null);
		CApi.position_builder_before (builder, CApi.next_instruction (constructed));
		CApi.ValueRef[] observed = {
			CApi.operand (constructed, 0)
		};
		var observation_call = CApi.build_call (builder, CApi.global_value_type (observation), observation, observed, 1, "heap.carrier.observation");
		CApi.set_instruction_call_conv (observation_call, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var foreign_class = CApi.named_function (artifact.module, "astra.class.method.2.0");
		assert ((void*) foreign_class != null && (void*) CApi.global_value_type (foreign_class) == (void*) CApi.global_value_type (observation));
		CApi.set_operand (observation_call, CApi.operand_count (observation_call) - 1, foreign_class);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "address escaped");
		CApi.set_operand (observation_call, CApi.operand_count (observation_call) - 1, observation);
		var clear = CApi.named_function (artifact.module, "astra.class.method.1.1");
		assert ((void*) clear != null);
		CApi.position_builder_before (builder, CApi.next_instruction (observation_call));
		var changed = CApi.build_call (builder, CApi.global_value_type (clear), clear, observed, 1, "");
		CApi.set_instruction_call_conv (changed, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "address escaped");
		CApi.erase_instruction (changed);
		CApi.set_instruction_call_conv (observation_call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "address escaped");
		CApi.set_instruction_call_conv (observation_call, LlvmLowering.CALL_CONVENTION);
		var destructor = CApi.named_function (artifact.module, "astra.dtor.1");
		CApi.position_builder_before (builder, CApi.first_instruction (CApi.first_block (observation)));
		CApi.ValueRef[] mutated_receiver = {
			CApi.get_param (observation, 0)
		};
		var hidden_cleanup = CApi.build_call (builder, CApi.global_value_type (destructor), destructor, mutated_receiver, 1, "");
		CApi.set_instruction_call_conv (hidden_cleanup, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "sum storage lost");
		CApi.erase_instruction (hidden_cleanup);
		artifact.verify_scoped_allocations ();
		var root = CApi.operand (constructed, 0);
		assert (CApi.opcode (root) == CApi.Opcode.PHI);
		uint live = (void*) CApi.is_constant_pointer_null (CApi.incoming_value (root, 0)) != null ? 1 : 0;
		var heap = CApi.incoming_value (root, live);
		var frees = new GenericArray<void*> ();
		var destructors = new GenericArray<void*> ();
		CApi.ValueRef guard = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) == CApi.Opcode.COND_BR && CApi.successor_count (end) == 2 && (void*) CApi.successor (end, 1) == (void*) (fallible ? CApi.instruction_parent (constructed) : CApi.incoming_block (root, live))) {
				guard = end;
			}
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != (contextual ? 2 : 1) && (void*) CApi.called_value (instruction) != (void*) CApi.named_function (artifact.module, "astra.dtor.1") || (void*) CApi.operand (instruction, 0) != (void*) root) {
					continue;
				}
				size_t length;
				if (CApi.value_name (CApi.called_value (instruction), out length) == (contextual ? "astra_context17_release_origin_checked" : "free")) {
					frees.add ((void*) instruction);
				}
				if ((void*) CApi.called_value (instruction) == (void*) CApi.named_function (artifact.module, "astra.dtor.1")) {
					destructors.add ((void*) instruction);
				}
			}
		}
		assert (frees.length == 2 && destructors.length == 2 && (void*) guard != null);
		foreach (void* value in frees) {
			var free = (CApi.ValueRef) value;
			CApi.set_operand (free, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired heap carrier");
			CApi.set_operand (free, 0, root);
		}
		foreach (void* value in destructors) {
			var destroy = (CApi.ValueRef) value;
			CApi.set_operand (destroy, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "retired before");
			CApi.set_operand (destroy, 0, root);
		}
		var first_free = (CApi.ValueRef) frees[0];
		CApi.ValueRef[] receiver = contextual ? new CApi.ValueRef[] {
			root, CApi.operand (first_free, 1)
		} : new CApi.ValueRef[] {
			root
		};
		CApi.position_builder_before (builder, CApi.next_instruction (constructed));
		var early = CApi.build_call (builder, CApi.called_function_type (first_free), CApi.called_value (first_free), receiver, receiver.length, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "heap carrier");
		CApi.erase_instruction (early);
		CApi.position_builder_before (builder, CApi.next_instruction (first_free));
		var duplicate = CApi.build_call (builder, CApi.called_function_type (first_free), CApi.called_value (first_free), receiver, receiver.length, "");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing");
		CApi.erase_instruction (duplicate);
		CApi.TypeRef layout = (CApi.TypeRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (constructor)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) == CApi.Opcode.GEP) {
				layout = CApi.gep_source_type (instruction);
				break;
			}
		}
		assert ((void*) layout != null);
		CApi.position_builder_before (builder, CApi.next_instruction (first_free));
		var field = CApi.build_struct_gep (builder, layout, root, 0, "invalid.retired.carrier.field");
		var read = CApi.build_load (builder, word, field, "invalid.retired.carrier.read");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live backing");
		CApi.erase_instruction (read);
		CApi.erase_instruction (field);
		for (uint p = 0; p < 2; p++) {
			uint index = p + (contextual ? 1 : 0);
			var operand = CApi.operand (heap, index);
			CApi.set_operand (heap, index, CApi.const_int (size, p == 0 ? 2 : 1, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "Class extent");
			CApi.set_operand (heap, index, operand);
		}
		if (contextual) {
			for (uint p = 3; p < 6; p++) {
				var operand = CApi.operand (heap, p);
				CApi.set_operand (heap, p, CApi.const_int (CApi.type_of (operand), p == 5 ? (CApi.const_int_zext (operand) + 1) % 3 : 7, 0));
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "prescribed context mode");
				CApi.set_operand (heap, p, operand);
			}
			foreach (void* value in frees) {
				var release = (CApi.ValueRef) value;
				var original_tag = CApi.operand (release, 1);
				CApi.set_operand (release, 1, CApi.const_int (size, 7, 0));
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "context retirement ABI or allocation tag");
				CApi.set_operand (release, 1, original_tag);
			}
			CApi.set_instruction_call_conv (first_free, CApi.CallConv.FAST);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "context retirement ABI or allocation tag");
			CApi.set_instruction_call_conv (first_free, CApi.CallConv.C);
			var wrong_release = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
			CApi.position_builder_before (builder, first_free);
			var freed = CApi.build_call (builder, CApi.global_value_type (wrong_release), wrong_release, observed, 1, "");
			CApi.set_instruction_call_conv (freed, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "address escaped");
			CApi.erase_instruction (freed);
			var calloc = declaration (artifact, "calloc", pointer, new CApi.TypeRef[] { size, size });
			CApi.position_builder_before (builder, heap);
			CApi.ValueRef[] default_inputs = {
				CApi.const_int (size, 1, 0), CApi.operand (heap, 2)
			};
			var substituted = CApi.build_call (builder, CApi.global_value_type (calloc), calloc, default_inputs, 2, "invalid.default.carrier");
			CApi.set_instruction_call_conv (substituted, CApi.CallConv.C);
			var nonnull = CApi.operand (guard, 0);
			CApi.set_operand (root, live, substituted);
			if (!fallible) {
				CApi.set_operand (nonnull, 0, substituted);
			}
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "prescribed allocation");
			if (!fallible) {
				CApi.set_operand (nonnull, 0, heap);
			}
			CApi.set_operand (root, live, heap);
			CApi.erase_instruction (substituted);
		}

		var condition = CApi.operand (guard, 0);
		CApi.set_operand (guard, 0, CApi.const_int (CApi.type_of (condition), 0, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonnull allocation guard");
		CApi.set_operand (guard, 0, condition);
		var empty_edge = CApi.block_terminator (CApi.incoming_block (root, 1 - live));
		var absent_condition = CApi.operand (empty_edge, 0);
		CApi.set_operand (empty_edge, 0, CApi.const_int (CApi.type_of (absent_condition), 1, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unreachable empty edge");
		CApi.set_operand (empty_edge, 0, absent_condition);
		var opaque = declaration (artifact, "invalid.heap.raw.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, CApi.next_instruction (heap));
		CApi.ValueRef[] raw = {
			heap
		};
		var escape = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, raw, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "raw allocation escaped");
		CApi.erase_instruction (escape);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.erase_instruction (observation_call);
		CApi.set_operand (constructed, 2, original);
		CApi.set_operand (constructed, 3, original_second);
		CApi.erase_instruction (second);
		CApi.erase_instruction (allocation);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void fallible_input(LlvmModuleArtifact artifact, string constructor_name = "astra.ctor.1", uint child_position = 1, uint input_parameter = 1) throws GLib.Error {
		var function = CApi.named_function (artifact.module, "astra.fn.1");
		assert (artifact.has_scoped_owned_inputs (function));
		CApi.ValueRef restored = (CApi.ValueRef) null;
		CApi.ValueRef constructed = (CApi.ValueRef) null;
		CApi.ValueRef refused_return = (CApi.ValueRef) null;
		CApi.ValueRef admitted_return = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.SELECT && (void*) CApi.operand (instruction, 1) == (void*) CApi.get_param (function, input_parameter)) {
					assert ((void*) restored == null);
					restored = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) CApi.named_function (artifact.module, constructor_name)) {
					constructed = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.RET) {
					if ((void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) != null) {
						admitted_return = instruction;
					} else {
						refused_return = instruction;
					}
				}
			}
		}
		assert ((void*) restored != null && (void*) constructed != null && (void*) refused_return != null && (void*) admitted_return != null);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var condition = CApi.operand (restored, 0);
		var input = CApi.operand (restored, 1);
		var empty = CApi.operand (restored, 2);
		assert ((void*) input == (void*) CApi.get_param (function, input_parameter) && (void*) CApi.is_constant_pointer_null (empty) != null);
		for (int mode = 0; mode < 2; mode++) {
			CApi.set_operand (restored, 0, CApi.const_int (CApi.type_of (condition), mode, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
			CApi.set_operand (restored, 0, condition);
		}
		CApi.set_operand (restored, 1, empty);
		CApi.set_operand (restored, 2, input);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (restored, 1, input);
		CApi.set_operand (restored, 2, empty);
		CApi.set_operand (restored, 2, CApi.get_param (function, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "complete allocation identity");
		CApi.set_operand (restored, 2, empty);
		var returned = CApi.operand (refused_return, 0);
		CApi.set_operand (refused_return, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (refused_return, 0, returned);
		CApi.set_operand (admitted_return, 0, input);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.set_operand (admitted_return, 0, empty);
		CApi.set_operand (constructed, child_position, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (constructed, child_position, input);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, admitted_return);
		var stale = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), restored, "invalid.restored.null.read");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (stale);
		CApi.position_builder_before (builder, constructed);
		var unexpected = declaration (artifact, "invalid.restore.opaque", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { CApi.type_of (empty) });
		CApi.ValueRef[] arguments = {
			restored
		};
		var escape = CApi.build_call (builder, CApi.global_value_type (unexpected), unexpected, arguments, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "ownership effect");
		CApi.erase_instruction (escape);
		if (child_position > 1) {
			var constructor = CApi.called_value (constructed);
			CApi.ValueRef ordinary_store = (CApi.ValueRef) null;
			for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 0) == (void*) CApi.get_param (constructor, child_position - 1)) {
						ordinary_store = instruction;
					}
				}
			}
			assert ((void*) ordinary_store != null);
			var ordinary = CApi.operand (ordinary_store, 0);
			CApi.set_operand (ordinary_store, 0, CApi.get_param (constructor, child_position));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "owning sum effect changed");
			CApi.set_operand (ordinary_store, 0, ordinary);
		}

		CApi.dispose_builder (builder);
		valid_ir (artifact.module);
		artifact.verify ();
	}

	internal static void checked_heap_result(LlvmModuleArtifact artifact, CApi.ValueRef function, uint input_position = 1) throws GLib.Error {
		assert (artifact.has_scoped_owned_inputs (function));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var output = CApi.get_param (function, 0);
		var input = CApi.get_param (function, input_position);
		var pointer = CApi.type_of (input);
		CApi.ValueRef published = (CApi.ValueRef) null, normal = (CApi.ValueRef) null, failure = (CApi.ValueRef) null, release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) output) {
					assert ((void*) published == null);
					published = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.RET) {
					if ((void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) != null) {
						normal = instruction;
					} else {
						failure = instruction;
					}
				}
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked") && (void*) CApi.operand (instruction, 0) == (void*) input) {
					assert ((void*) release == null);
					release = instruction;
				}
			}
		}
		assert ((void*) published != null && (void*) normal != null && (void*) failure != null && (void*) release != null && (void*) CApi.operand (published, 0) == (void*) input);
		var builder = CApi.create_builder_in_context (artifact.context);
		var empty = CApi.const_null (pointer);
		var tag = CApi.operand (release, 1);
		CApi.set_operand (published, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "null success retains its input owner");
		CApi.set_operand (published, 0, input);
		CApi.position_builder_before (builder, published);
		var local = CApi.build_alloca (builder, pointer, "invalid.checked.success.local");
		CApi.set_operand (published, 1, local);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "normal return lost its exact success publication");
		CApi.set_operand (published, 1, output);
		CApi.erase_instruction (local);
		CApi.position_builder_before (builder, CApi.next_instruction (published));
		var repeated = CApi.build_store (builder, empty, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "published more than once");
		CApi.erase_instruction (repeated);
		CApi.position_builder_before (builder, CApi.next_instruction (published));
		repeated = CApi.build_store (builder, input, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (repeated);
		var opaque = declaration (artifact, "invalid.checked.success.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, published);
		CApi.ValueRef[] arguments = {
			output
		};
		var escape = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "success output escaped");
		CApi.erase_instruction (escape);
		var error = CApi.operand (failure, 0);
		CApi.set_operand (failure, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "normal return lost its exact success publication");
		CApi.set_operand (failure, 0, error);
		CApi.set_operand (failure, 0, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "success output escaped");
		CApi.set_operand (failure, 0, error);
		foreach (void* item in new void*[] { (void*) normal, (void*) failure }) {
			var returned = (CApi.ValueRef) item;
			var value = CApi.operand (returned, 0);
			CApi.set_operand (returned, 0, input);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
			CApi.set_operand (returned, 0, value);
		}
		CApi.set_operand (release, 0, empty);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "error return retains a success owner");
		CApi.set_operand (release, 0, input);
		CApi.set_operand (release, 1, CApi.const_int (CApi.type_of (tag), CApi.const_int_zext (tag) ^ 1, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation tag");
		CApi.set_operand (release, 1, tag);
		foreach (bool before in new bool[] { true, false }) {
			CApi.position_builder_before (builder, before ? published : CApi.next_instruction (published));
			CApi.ValueRef[] retirement = {
				input, tag
			};
			var premature = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), retirement, 2, "invalid.checked.success.retirement");
			CApi.set_instruction_call_conv (premature, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
			CApi.erase_instruction (premature);
		}
		CApi.dispose_builder (builder);
		valid_ir (artifact.module);
		artifact.verify ();
	}

	internal static void checked_heap_caller(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.ValueRef target, uint input_position = 1, bool exceptional_payload = false) throws GLib.Error {
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.ValueRef call = (CApi.ValueRef) null, loaded = (CApi.ValueRef) null, guard = (CApi.ValueRef) null;
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) target) {
					assert ((void*) call == null);
					call = instruction;
				}
			}
		}
		assert ((void*) call != null);
		var slot = CApi.operand (call, 0);
		var input = CApi.operand (call, input_position);
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.LOAD && (void*) CApi.operand (instruction, 0) == (void*) slot) {
					assert ((void*) loaded == null);
					loaded = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.COND_BR && CApi.successor_count (instruction) == 2) {
					var condition = CApi.operand (instruction, 0);
					if ((void*) CApi.is_instruction (condition) != null && CApi.opcode (condition) == CApi.Opcode.ICMP && ((void*) CApi.operand (condition, 0) == (void*) call || (void*) CApi.operand (condition, 1) == (void*) call)) {
						guard = instruction;
					}
				}
			}
		}
		assert ((void*) loaded != null && (void*) guard != null);
		var builder = CApi.create_builder_in_context (artifact.context);
		var output = CApi.get_param (function, 0);
		CApi.set_operand (call, 0, input);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unique local success slot");
		CApi.set_operand (call, 0, slot);
		CApi.set_operand (call, 0, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "success output escaped");
		CApi.set_operand (call, 0, slot);
		CApi.set_operand (loaded, 0, output);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "success output escaped");
		CApi.set_operand (loaded, 0, slot);
		CApi.position_builder_before (builder, call);
		var overwritten = CApi.build_store (builder, CApi.const_null (pointer), slot);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "caller success slot escaped");
		CApi.erase_instruction (overwritten);
		var opaque = declaration (artifact, "invalid.checked.caller.slot", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.ValueRef[] arguments = {
			slot
		};
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "caller success slot escaped");
		CApi.erase_instruction (escaped);
		for (int mode = 0; mode < 3; mode++) {
			CApi.position_builder_before (builder, mode == 0 ? call : mode == 1 ? CApi.next_instruction (call) : CApi.next_instruction (loaded));
			var early = CApi.build_load (builder, pointer, slot, "invalid.checked.caller.read");
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "success read lacks its observed successful target");
			CApi.erase_instruction (early);
		}
		var condition = CApi.operand (guard, 0);
		for (int mode = 0; mode < 2; mode++) {
			CApi.set_operand (guard, 0, CApi.const_int (CApi.type_of (condition), mode, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), exceptional_payload && mode == 0 ? "exact live backing or nonnull allocation guard" : "checked scoped");
			CApi.set_operand (guard, 0, condition);
		}
		CApi.set_operand (call, input_position, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "checked scoped");
		CApi.set_operand (call, input_position, input);
		uint convention = CApi.instruction_call_conv (call);
		var missing = CApi.add_function (artifact.module, "invalid.checked.caller.same.abi", CApi.called_function_type (call));
		CApi.set_function_call_conv (missing, convention);
		uint callee = CApi.operand_count (call) - 1;
		CApi.set_operand (call, callee, missing);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), artifact.has_scoped_class_loans (function) ? "nonretaining live borrow effect" : artifact.has_scoped_context_inputs (function) ? "pointer-result lifetime effect" : "ownership effect");
		CApi.set_operand (call, callee, target);
		CApi.set_instruction_call_conv (call, convention == CApi.CallConv.C ? CApi.CallConv.FAST : CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), artifact.has_scoped_class_loans (function) ? "nonretaining live borrow effect" : "type, extent, alignment");
		CApi.set_instruction_call_conv (call, convention);
		CApi.dispose_builder (builder);
		valid_ir (artifact.module);
		artifact.verify ();
	}

	internal static void class_loan(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.ValueRef relay, CApi.ValueRef lender, int ordinal) throws GLib.Error {
		assert (artifact.has_scoped_class_loans (function) && artifact.has_scoped_class_loans (relay));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var view = CApi.get_param (function, 2);
		var pointer = CApi.type_of (view);
		var builder = CApi.create_builder_in_context (artifact.context);
		var first = CApi.first_instruction (CApi.first_block (function));
		CApi.position_builder_before (builder, first);
		var local = CApi.build_alloca (builder, pointer, "invalid.class.loan.local");
		var stored = CApi.build_store (builder, view, local);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.erase_instruction (stored);
		CApi.erase_instruction (local);
		var opaque = declaration (artifact, "invalid.class.loan.opaque", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.ValueRef[] arguments = {
			view
		};
		var call = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.erase_instruction (call);
		var release = CApi.named_function (artifact.module, "astra_context17_release_origin_checked");
		assert ((void*) release != null);
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedView", "object");
		CApi.ValueRef[] released = {
			view, tag
		};
		call = CApi.build_call (builder, CApi.global_value_type (release), release, released, 2, "invalid.class.loan.retire");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.erase_instruction (call);
		var freed = declaration (artifact, "free", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		call = CApi.build_call (builder, CApi.global_value_type (freed), freed, arguments, 1, "");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.erase_instruction (call);
		foreach (string role in new string[] { "ctor", "dtor" }) {
			var target = CApi.named_function (artifact.module, "astra.%s.%d".printf (role, ordinal));
			assert ((void*) target != null && CApi.count_params (target) == 1);
			call = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, 1, "");
			CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
			CApi.erase_instruction (call);
		}
		CApi.ValueRef returned = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			if (CApi.opcode (CApi.block_terminator (block)) == CApi.Opcode.RET) {
				returned = CApi.block_terminator (block);
				break;
			}
		}
		assert ((void*) returned != null);
		var result = CApi.operand (returned, 0);
		CApi.set_operand (returned, 0, view);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.set_operand (returned, 0, result);
		CApi.ValueRef forwarded = (CApi.ValueRef) null;
		for (var block = CApi.first_block (relay); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) function) {
					forwarded = instruction;
				}
			}
		}
		assert ((void*) forwarded != null);
		var owner = CApi.operand (forwarded, 1);
		CApi.set_operand (forwarded, 1, CApi.operand (forwarded, 2));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.set_operand (forwarded, 1, owner);
		CApi.ValueRef read = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.argument_count (instruction) == 1 && (void*) CApi.operand (instruction, 0) == (void*) view) {
					read = instruction;
				}
			}
		}
		assert ((void*) read != null);
		var wrong = CApi.named_function (artifact.module, "astra.class.method.1.0");
		assert ((void*) wrong != null && (void*) CApi.global_value_type (wrong) == (void*) CApi.called_function_type (read));
		var original = CApi.called_value (read);
		uint called = CApi.operand_count (read) - 1;
		CApi.set_operand (read, called, wrong);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonretaining live borrow effect");
		CApi.set_operand (read, called, original);
		assert (artifact.has_scoped_owned_inputs (lender));
		CApi.ValueRef lent = (CApi.ValueRef) null;
		for (var block = CApi.first_block (lender); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) function) {
					lent = instruction;
				}
			}
		}
		assert ((void*) lent != null);
		var kept = CApi.operand (lent, 2);
		CApi.set_operand (lent, 2, CApi.operand (lent, 1));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact Class allocation shape");
		CApi.set_operand (lent, 2, kept);
		CApi.position_builder_before (builder, lent);
		CApi.ValueRef[] retired_lender = {
			kept, tag
		};
		var premature = CApi.build_call (builder, CApi.global_value_type (release), release, retired_lender, 2, "invalid.class.lender.retire");
		CApi.set_instruction_call_conv (premature, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
		CApi.erase_instruction (premature);
		var disposals = new GenericArray<void*> ();
		for (var block = CApi.first_block (lender); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) release && (void*) CApi.operand (instruction, 0) == (void*) kept) {
					disposals.add ((void*) instruction);
				}
			}
		}
		assert (disposals.length == 2);
		foreach (void* item in disposals) {
			var disposal = (CApi.ValueRef) item;
			CApi.set_operand (disposal, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
			CApi.set_operand (disposal, 0, kept);
		}
		CApi.dispose_builder (builder);
		valid_ir (artifact.module);
		artifact.verify ();
	}

	internal static void checked_context(LlvmModuleArtifact artifact, CApi.ValueRef target, CApi.ValueRef relay, bool owned, uint context_position = 1, bool exceptional_payload = false) throws GLib.Error {
		assert (artifact.has_scoped_context_inputs (target) && artifact.has_scoped_context_inputs (relay));
		if (owned) {
			assert (artifact.has_scoped_owned_inputs (target) && artifact.has_scoped_owned_inputs (relay));
		}
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var context = CApi.get_param (target, context_position);
		var pointer = CApi.type_of (context);
		var builder = CApi.create_builder_in_context (artifact.context);
		var first = CApi.first_instruction (CApi.first_block (target));
		CApi.position_builder_before (builder, first);
		var read = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), context, "invalid.checked.context.read");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped through an emitted alias");
		CApi.erase_instruction (read);
		var slot = CApi.build_alloca (builder, pointer, "invalid.checked.context.slot");
		var stored = CApi.build_store (builder, context, slot);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped through an emitted alias");
		CApi.erase_instruction (stored);
		CApi.erase_instruction (slot);
		var destroy = declaration (artifact, "astra_context17_destroy", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.ValueRef[] arguments = {
			context
		};
		var retired = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, arguments, 1, "");
		CApi.set_instruction_call_conv (retired, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "cannot be retired by its callee");
		CApi.erase_instruction (retired);
		var opaque = declaration (artifact, "invalid.checked.context.opaque", pointer, new CApi.TypeRef[] { pointer });
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "invalid.context.escape");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "pointer-result lifetime effect");
		CApi.erase_instruction (escaped);
		CApi.ValueRef call = (CApi.ValueRef) null;
		for (var block = CApi.first_block (relay); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) target) {
					assert ((void*) call == null);
					call = instruction;
				}
			}
		}
		assert ((void*) call != null);
		uint convention = CApi.instruction_call_conv (call);
		CApi.set_instruction_call_conv (call, convention == CApi.CallConv.C ? CApi.CallConv.FAST : CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), owned ? "type, extent, alignment" : "physical signature/parameter");
		CApi.set_instruction_call_conv (call, convention);
		var missing = CApi.add_function (artifact.module, "invalid.checked.context.same.abi", CApi.called_function_type (call));
		CApi.set_function_call_conv (missing, convention);
		uint callee = CApi.operand_count (call) - 1;
		CApi.set_operand (call, callee, missing);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "pointer-result lifetime effect");
		CApi.set_operand (call, callee, target);
		if (owned) {
			var borrowed = CApi.operand (call, context_position);
			var owner = CApi.operand (call, context_position + 1);
			CApi.set_operand (call, context_position, owner);
			CApi.set_operand (call, context_position + 1, borrowed);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), exceptional_payload ? "caller payload transport" : "pointer-result lifetime effect");
			CApi.set_operand (call, context_position, borrowed);
			CApi.set_operand (call, context_position + 1, owner);
		}
		CApi.dispose_builder (builder);
		valid_ir (artifact.module);
		artifact.verify ();
	}

	internal static void checked_input(LlvmModuleArtifact artifact, CApi.ValueRef function, uint input_position = 0) throws GLib.Error {
		assert (artifact.has_scoped_owned_inputs (function));
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var releases = new GenericArray<void*> ();
		var returns = new GenericArray<void*> ();
		var input = CApi.get_param (function, input_position);
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked") && (void*) CApi.operand (instruction, 0) == (void*) input) {
					releases.add ((void*) instruction);
				}
				if (CApi.opcode (instruction) == CApi.Opcode.RET) {
					returns.add ((void*) instruction);
				}
			}
		}
		assert (releases.length == 2 && returns.length == 2);
		foreach (void* item in releases) {
			var release = (CApi.ValueRef) item;
			CApi.set_operand (release, 0, CApi.const_null (CApi.type_of (input)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
			CApi.set_operand (release, 0, input);
		}
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (void* item in releases) {
			var release = (CApi.ValueRef) item;
			var tag = CApi.operand (release, 1);
			CApi.set_operand (release, 1, CApi.const_int (CApi.type_of (tag), CApi.const_int_zext (tag) ^ 1, 0));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "allocation tag");
			CApi.set_operand (release, 1, tag);
			CApi.position_builder_before (builder, CApi.next_instruction (release));
			CApi.ValueRef[] arguments = {
				input, tag
			};
			var duplicate = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), arguments, 2, "invalid.checked.double.release");
			CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
			CApi.erase_instruction (duplicate);
		}
		var opaque = declaration (artifact, "invalid.checked.opaque", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { CApi.type_of (input) });
		CApi.position_builder_before (builder, (CApi.ValueRef) releases[0]);
		CApi.ValueRef[] arguments = {
			input
		};
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, arguments, 1, "");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "ownership effect");
		CApi.erase_instruction (escaped);
		CApi.dispose_builder (builder);
		foreach (void* item in returns) {
			var returned = (CApi.ValueRef) item;
			var original = CApi.operand (returned, 0);
			CApi.set_operand (returned, 0, input);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
			CApi.set_operand (returned, 0, original);
		}
		valid_ir (artifact.module);
		artifact.verify ();
	}

	internal static void multiple_heap_fields(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		var function = CApi.named_function (artifact.module, "astra.fn.0");
		var constructor = CApi.named_function (artifact.module, "astra.ctor.1");
		CApi.ValueRef context = (CApi.ValueRef) null;
		var calls = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				if ((void*) CApi.called_value (instruction) == (void*) constructor) {
					calls.add ((void*) instruction);
				}
				size_t length;
				if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_context17_open_scoped") {
					context = instruction;
				}
			}
		}
		assert ((void*) context != null && calls.length == 2);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var provider = declaration (artifact, "astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
		var tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		var builder = CApi.create_builder_in_context (artifact.context);
		var allocations = new GenericArray<void*> ();
		CApi.ValueRef[] inputs = {
			context, CApi.const_int (size, 1, 0), CApi.const_int (size, 1, 0), CApi.const_int (word, 1, 0), tag, CApi.const_int (word, 3, 0)
		};
		foreach (void* value in calls) {
			var call = (CApi.ValueRef) value;
			assert ((void*) CApi.is_constant_pointer_null (CApi.operand (call, 2)) != null);
			CApi.position_builder_before (builder, call);
			var allocation = CApi.build_call (builder, CApi.global_value_type (provider), provider, inputs, 6, "independent.heap.field.child");
			CApi.set_instruction_call_conv (allocation, CApi.CallConv.C);
			allocations.add ((void*) allocation);
			CApi.set_operand (call, 2, allocation);
		}
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		var first_root = CApi.operand ((CApi.ValueRef) calls[0], 0);
		var second_root = CApi.operand ((CApi.ValueRef) calls[1], 0);
		var releases = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.argument_count (instruction) == 2 && ((void*) CApi.operand (instruction, 0) == (void*) first_root || (void*) CApi.operand (instruction, 0) == (void*) second_root) && LlvmScopedHeapCarrier.named_call (instruction, "astra_context17_release_origin_checked")) {
					releases.add ((void*) instruction);
				}
			}
		}
		assert (releases.length == 4);
		foreach (void* value in releases) {
			var release = (CApi.ValueRef) value;
			var original = CApi.operand (release, 0);
			CApi.set_operand (release, 0, CApi.const_null (pointer));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "unretired heap carrier");
			CApi.set_operand (release, 0, original);
			if ((void*) original == (void*) second_root) {
				CApi.set_operand (release, 0, first_root);
				valid_ir (artifact.module);
				refusal_text (() => artifact.verify_scoped_allocations (), "heap carrier");
				CApi.set_operand (release, 0, original);
			}
		}
		artifact.verify_scoped_allocations ();
		for (int p = 0; p < calls.length; p++) {
			CApi.set_operand ((CApi.ValueRef) calls[p], 2, CApi.const_null (pointer));
			CApi.erase_instruction ((CApi.ValueRef) allocations[p]);
		}
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	private static CApi.ValueRef declaration(LlvmModuleArtifact artifact, string name, CApi.TypeRef result, CApi.TypeRef[] parameters) {
		var type = CApi.function_type (result, parameters, parameters.length, 0);
		var target = CApi.named_function (artifact.module, name);
		if ((void*) target == null) {
			target = CApi.add_function (artifact.module, name, type);
		}
		assert ((void*) CApi.global_value_type (target) == (void*) type);
		return target;
	}

	internal static void short_circuit_owners() {
		for (int mode = 53; mode <= 57; mode++) {
			var fixture = new ScopedLlvmFixture (mode);
			fixture.verify_ir ();
			bool rejected = false;
			try {
				LlvmScopedAllocationVerifier.verify (fixture.module);
			} catch (LlvmError failure) {
				rejected = true;
				Test.message ("mode %d: %s", mode, failure.message);
			}
			assert (rejected == (mode != 53));
		}
	}

	private static void replace_uses(CApi.ValueRef original, CApi.ValueRef replacement) {
		var users = new GenericArray<void*> ();
		for (var use = CApi.first_use (original); (void*) use != null; use = CApi.next_use (use)) {
			users.add ((void*) CApi.user (use));
		}
		foreach (void* item in users) {
			var user = (CApi.ValueRef) item;
			for (uint operand = 0; operand < CApi.operand_count (user); operand++) {
				if ((void*) CApi.operand (user, operand) == (void*) original) {
					CApi.set_operand (user, operand, replacement);
				}
			}
		}
	}

	private static void heap_catch_slots(LlvmModuleArtifact artifact, CApi.ValueRef function, CApi.ValueRef choice, CApi.ValueRef peek, CApi.ValueRef cleanup) throws GLib.Error {
		var builder = CApi.create_builder_in_context (artifact.context);
		var pointer = CApi.type_of (choice);
		CApi.position_builder_before (builder, CApi.first_instruction (CApi.first_block (function)));
		var slot = CApi.build_alloca (builder, pointer, "chosen.error.slot");
		var stores = new GenericArray<void*> ();
		for (uint origin = 0; origin < CApi.incoming_count (choice); origin++) {
			CApi.position_builder_before (builder, CApi.block_terminator (CApi.incoming_block (choice, origin)));
			stores.add ((void*) CApi.build_store (builder, CApi.incoming_value (choice, origin), slot));
		}
		var insertion = CApi.first_instruction (CApi.instruction_parent (choice));
		while (CApi.opcode (insertion) == CApi.Opcode.PHI) {
			insertion = CApi.next_instruction (insertion);
		}
		CApi.position_builder_before (builder, insertion);
		var loaded = CApi.build_load (builder, pointer, slot, "chosen.error.snapshot");
		replace_uses (choice, loaded);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		// Overwriting storage cannot retarget a value already loaded from it.
		var cleared = CApi.build_store (builder, CApi.const_null (pointer), slot);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, peek);
		var absent = CApi.build_load (builder, pointer, slot, "empty.error.snapshot");
		CApi.set_operand (peek, 0, absent);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nullable heap choice");
		CApi.set_operand (peek, 0, loaded);
		CApi.erase_instruction (absent);
		artifact.verify_scoped_allocations ();
		CApi.erase_instruction (cleared);
		CApi.erase_instruction ((CApi.ValueRef) stores[0]);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "heap slot read requires an initialized");
		CApi.position_builder_before (builder, CApi.block_terminator (CApi.incoming_block (choice, 0)));
		stores[0] = (void*) CApi.build_store (builder, CApi.incoming_value (choice, 0), slot);
		artifact.verify_scoped_allocations ();
		var stored = (CApi.ValueRef) stores[0];
		var original = CApi.operand (stored, 0);
		CApi.set_operand (stored, 0, slot);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped its local frame");
		CApi.set_operand (stored, 0, original);
		artifact.verify_scoped_allocations ();
		CApi.set_volatile (loaded, 1);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped its local frame");
		CApi.set_volatile (loaded, 0);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, peek);
		var live = CApi.build_icmp (builder, CApi.IntPredicate.NE, loaded, CApi.const_null (pointer), "proved.heap.snapshot.live");
		var exact = CApi.build_select (builder, live, loaded, CApi.const_null (pointer), "proved.heap.snapshot.selection");
		CApi.set_operand (peek, 0, exact);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (peek, 0, loaded);
		CApi.erase_instruction (exact);
		CApi.erase_instruction (live);
		artifact.verify_scoped_allocations ();
		var escape_target = declaration (artifact, "invalid.heap.slot.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, peek);
		CApi.ValueRef[] arguments = {
			slot
		};
		var escape = CApi.build_call (builder, CApi.global_value_type (escape_target), escape_target, arguments, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped its local frame");
		CApi.erase_instruction (escape);
		CApi.delete_function (escape_target);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (cleanup));
		CApi.ValueRef[] retired_arguments = {
			loaded
		};
		var stale = CApi.build_call (builder, CApi.called_function_type (peek), CApi.called_value (peek), retired_arguments, 1, "invalid.retired.error.snapshot");
		CApi.set_instruction_call_conv (stale, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live backing", "live owner", "occupied live");
		CApi.erase_instruction (stale);
		artifact.verify_scoped_allocations ();
		replace_uses (loaded, choice);
		CApi.erase_instruction (loaded);
		foreach (void* store in stores) {
			CApi.erase_instruction ((CApi.ValueRef) store);
		}
		CApi.erase_instruction (slot);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void heap_catch_choices(LlvmModuleArtifact artifact, CApi.ValueRef function) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef choice = (CApi.ValueRef) null;
		CApi.ValueRef peek = (CApi.ValueRef) null;
		CApi.ValueRef cleanup = (CApi.ValueRef) null;
		var destroys = new GenericArray<void*> ();
		var contexts = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.PHI && CApi.incoming_count (i) == 2 && CApi.type_kind (CApi.type_of (i)) == CApi.TypeKind.POINTER) {
					var left = CApi.incoming_value (i, 0);
					var right = CApi.incoming_value (i, 1);
					if ((void*) CApi.is_instruction (left) != null && (void*) CApi.is_instruction (right) != null && CApi.opcode (left) == CApi.Opcode.CALL && CApi.opcode (right) == CApi.Opcode.CALL && (void*) CApi.called_value (left) == (void*) CApi.called_value (right)) {
						choice = i;
					}
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_context17_destroy") && !contexts.find ((void*) CApi.operand (i, 0))) {
					contexts.add ((void*) CApi.operand (i, 0));
					destroys.add ((void*) i);
				}
			}
		}
		assert ((void*) choice != null && destroys.length == 2);
		for (var use = CApi.first_use (choice); (void*) use != null; use = CApi.next_use (use)) {
			var call = CApi.user (use);
			if ((void*) CApi.is_instruction (call) == null || CApi.opcode (call) != CApi.Opcode.CALL || CApi.argument_count (call) != 1 || (void*) CApi.operand (call, 0) != (void*) choice) {
				continue;
			}
			if (CApi.type_kind (CApi.type_of (call)) == CApi.TypeKind.INTEGER) {
				peek = call;
			} else if (CApi.type_kind (CApi.type_of (call)) == CApi.TypeKind.VOID && (void*) CApi.is_instruction (CApi.called_value (call)) != null) {
				cleanup = call;
			}
		}
		assert ((void*) peek != null && (void*) cleanup != null);
		var incoming = CApi.operand (choice, 0);
		CApi.set_operand (choice, 0, CApi.operand ((CApi.ValueRef) destroys[0], 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped its local frame");
		CApi.set_operand (choice, 0, incoming);
		artifact.verify_scoped_allocations ();
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, peek);
		var flag = CApi.build_icmp (builder, CApi.IntPredicate.EQ, CApi.get_param (function, 0), CApi.const_null (CApi.type_of (CApi.get_param (function, 0))), "invalid.heap.selection");
		var selected = CApi.build_select (builder, flag, choice, CApi.const_null (CApi.type_of (choice)), "invalid.heap.choice");
		CApi.set_operand (peek, 0, selected);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual predecessor or selected origin");
		CApi.set_operand (peek, 0, choice);
		CApi.erase_instruction (selected);
		CApi.erase_instruction (flag);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, peek);
		var pointer = CApi.type_of (choice);
		CApi.TypeRef[] header_fields = {
			pointer, pointer
		};
		var header = CApi.struct_type_in_context (artifact.context, header_fields, 2, 0);
		var projection = CApi.build_struct_gep (builder, header, choice, 0, "invalid.chosen.exception.descriptor");
		var overwrite = CApi.build_store (builder, CApi.const_null (pointer), projection);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "cannot overwrite its inherited descriptor");
		CApi.erase_instruction (overwrite);
		CApi.erase_instruction (projection);
		artifact.verify_scoped_allocations ();
		// The source producer always throws. Terminate its ABI's theoretical
		// null-success alternatives so moving cleanup cannot create an
		// unrelated missing-cleanup path that skips the catch entirely.
		CApi.BasicBlockRef trap = (CApi.BasicBlockRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			var i = CApi.first_instruction (block);
			if ((void*) i != null && LlvmScopedHeapCarrier.named_call (i, "llvm.trap") && CApi.opcode (CApi.block_terminator (block)) == CApi.Opcode.UNREACHABLE) {
				trap = block;
				break;
			}
		}
		assert ((void*) trap != null);
		var guards = new GenericArray<void*> ();
		var successors = new GenericArray<void*> ();
		var positions = new GenericArray<uint> ();
		for (uint origin = 0; origin < 2; origin++) {
			var value = CApi.incoming_value (choice, origin);
			for (var use = CApi.first_use (value); (void*) use != null; use = CApi.next_use (use)) {
				var test = CApi.user (use);
				if ((void*) CApi.is_instruction (test) == null || CApi.opcode (test) != CApi.Opcode.ICMP || (CApi.predicate (test) != CApi.IntPredicate.EQ && CApi.predicate (test) != CApi.IntPredicate.NE) || (void*) CApi.is_constant_pointer_null (CApi.operand (test, 1)) == null) {
					continue;
				}
				var branch = CApi.block_terminator (CApi.instruction_parent (test));
				if (CApi.opcode (branch) == CApi.Opcode.COND_BR && CApi.successor_count (branch) == 2 && (void*) CApi.operand (branch, 0) == (void*) test) {
					uint position = CApi.predicate (test) == CApi.IntPredicate.EQ ? 0U : 1U;
					guards.add ((void*) branch);
					successors.add ((void*) CApi.successor (branch, position));
					positions.add (position);
					CApi.set_successor (branch, position, trap);
				}
			}
		}
		assert (guards.length == 2);
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		foreach (void* item in destroys) {
			var original = (CApi.ValueRef) item;
			var context = CApi.operand (original, 0);
			var cleanups = new GenericArray<void*> ();
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
					if (LlvmScopedHeapCarrier.named_call (i, "astra_context17_destroy") && (void*) CApi.operand (i, 0) == (void*) context) {
						cleanups.add ((void*) i);
					}
				}
			}
			foreach (void* cleanup_site in cleanups) {
				CApi.set_operand ((CApi.ValueRef) cleanup_site, 0, CApi.const_null (CApi.type_of (context)));
			}
			CApi.position_builder_before (builder, peek);
			CApi.ValueRef[] arguments = {
				context
			};
			var early = CApi.build_call (builder, CApi.called_function_type (original), CApi.called_value (original), arguments, 1, "");
			CApi.set_instruction_call_conv (early, CApi.CallConv.C);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
			CApi.erase_instruction (early);
			foreach (void* cleanup_site in cleanups) {
				CApi.set_operand ((CApi.ValueRef) cleanup_site, 0, context);
			}
			artifact.verify_scoped_allocations ();
		}
		for (int g = 0; g < guards.length; g++) {
			CApi.set_successor ((CApi.ValueRef) guards[g], positions[g], (CApi.BasicBlockRef) successors[g]);
		}
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (cleanup));
		CApi.ValueRef[] payload = {
			choice
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (cleanup), CApi.called_value (cleanup), payload, 1, "");
		CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "occupied live carrier");
		CApi.erase_instruction (duplicate);
		CApi.dispose_builder (builder);
		artifact.verify ();
		heap_catch_slots (artifact, function, choice, peek, cleanup);
	}

	internal static void imported_scoped_tasks(LlvmModuleArtifact artifact, LlvmAsyncFrameBinding frame, CApi.ValueRef host, CApi.ValueRef factory, CApi.ValueRef make, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		assert (CApi.count_basic_blocks (factory) == 0 && CApi.count_basic_blocks (make) == 0 && CApi.count_basic_blocks (destructor) == 0);
		CApi.ValueRef creation = (CApi.ValueRef) null;
		CApi.ValueRef data = (CApi.ValueRef) null;
		CApi.ValueRef read = (CApi.ValueRef) null;
		CApi.ValueRef phase = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		CApi.ValueRef fresh = (CApi.ValueRef) null;
		CApi.ValueRef run = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) factory) {
					creation = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_data") && (void*) CApi.operand (i, 0) != (void*) frame.task) {
					data = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_phase")) {
					phase = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_release_wait") && (void*) CApi.is_constant_int (CApi.operand (i, 1)) != null && CApi.const_int_zext (CApi.operand (i, 1)) == 1) {
					release = i;
				}
			}
		}
		assert ((void*) creation != null && (void*) data != null && (void*) phase != null && (void*) release != null);
		for (var use = CApi.first_use (data); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) != null && CApi.opcode (user) == CApi.Opcode.LOAD) {
				assert ((void*) read == null);
				read = user;
			}
		}
		assert ((void*) read != null);
		for (var block = CApi.first_block (host); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) make) {
					fresh = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_run")) {
					run = i;
				}
			}
		}
		assert ((void*) fresh != null && (void*) run != null);
		var builder = CApi.create_builder_in_context (artifact.context);
		var pointer = CApi.type_of (creation);
		var word = CApi.type_of (read);
		var body = CApi.append_basic_block_in_context (artifact.context, factory, "invalid.opaque.factory.body");
		CApi.position_builder_at_end (builder, body);
		CApi.build_ret (builder, CApi.const_null (pointer));
		valid_ir (artifact.module);
		Test.message ("opaque control: factory acquired a body");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.delete_basic_block (body);
		artifact.verify_scoped_allocations ();
		size_t length;
		var checked = CApi.named_function (artifact.module, CApi.value_name (factory, out length) + "_checked");
		assert ((void*) checked != null);
		uint target = CApi.operand_count (creation) - 1;
		CApi.set_operand (creation, target, checked);
		valid_ir (artifact.module);
		Test.message ("opaque control: changed ordinary factory to checked role");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (creation, target, factory);
		artifact.verify_scoped_allocations ();
		var input = CApi.operand (creation, 0);
		CApi.set_operand (creation, 0, frame.task);
		valid_ir (artifact.module);
		Test.message ("opaque control: changed original captured allocation");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (creation, 0, input);
		artifact.verify_scoped_allocations ();
		CApi.set_instruction_call_conv (creation, CApi.CallConv.C);
		valid_ir (artifact.module);
		Test.message ("opaque control: changed factory calling convention");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_instruction_call_conv (creation, LlvmLowering.CALL_CONVENTION);
		artifact.verify_scoped_allocations ();
		CApi.set_volatile (read, 1);
		valid_ir (artifact.module);
		Test.message ("opaque control: volatile scalar result read");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_volatile (read, 0);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (read));
		var duplicate = CApi.build_load (builder, word, data, "invalid.duplicate.scalar.result");
		valid_ir (artifact.module);
		Test.message ("opaque control: repeated scalar observation");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.erase_instruction (duplicate);
		artifact.verify_scoped_allocations ();
		var child = CApi.operand (phase, 0);
		CApi.set_operand (phase, 0, frame.task);
		valid_ir (artifact.module);
		Test.message ("opaque control: scalar phase belongs to a different task");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (phase, 0, child);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (release));
		CApi.ValueRef[] observed = {
			CApi.operand (data, 0)
		};
		var stale_data = CApi.build_call (builder, CApi.called_function_type (data), CApi.called_value (data), observed, 1, "invalid.retired.child.data");
		CApi.set_instruction_call_conv (stale_data, CApi.CallConv.C);
		var stale_read = CApi.build_load (builder, word, stale_data, "invalid.retired.child.result");
		valid_ir (artifact.module);
		Test.message ("opaque control: scalar storage read after child retirement");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.erase_instruction (stale_read);
		CApi.erase_instruction (stale_data);
		artifact.verify_scoped_allocations ();
		var escape_target = declaration (artifact, "invalid.opaque.child.data.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, read);
		CApi.ValueRef[] escaped = {
			data
		};
		var escape = CApi.build_call (builder, CApi.global_value_type (escape_target), escape_target, escaped, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		Test.message ("opaque control: scalar storage address escaped");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.erase_instruction (escape);
		CApi.delete_function (escape_target);
		artifact.verify_scoped_allocations ();
		var context = CApi.operand (fresh, 0);
		CApi.set_operand (fresh, 0, CApi.const_null (CApi.type_of (context)));
		valid_ir (artifact.module);
		Test.message ("opaque control: fresh result lost caller context");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (fresh, 0, context);
		artifact.verify_scoped_allocations ();
		var destroy_context = CApi.named_function (artifact.module, "astra_context17_destroy");
		assert ((void*) destroy_context != null);
		CApi.position_builder_before (builder, run);
		CApi.ValueRef[] retired_context = {
			context
		};
		var early = CApi.build_call (builder, CApi.global_value_type (destroy_context), destroy_context, retired_context, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		Test.message ("opaque control: caller context retired before held allocation");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.erase_instruction (early);
		artifact.verify_scoped_allocations ();
		body = CApi.append_basic_block_in_context (artifact.context, destructor, "invalid.opaque.destructor.body");
		CApi.position_builder_at_end (builder, body);
		CApi.build_ret_void (builder);
		valid_ir (artifact.module);
		Test.message ("opaque control: destructor acquired a body");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.delete_basic_block (body);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void await_scoped_errors(LlvmModuleArtifact artifact, LlvmAsyncFrameBinding frame) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef acquisition = (CApi.ValueRef) null;
		CApi.ValueRef phase = (CApi.ValueRef) null;
		CApi.ValueRef copied = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_exception")) {
					assert ((void*) acquisition == null);
					acquisition = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_phase")) {
					assert ((void*) phase == null);
					phase = i;
				}
			}
		}
		assert ((void*) acquisition != null && (void*) phase != null);
		for (var use = CApi.first_use (acquisition); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) != null && CApi.opcode (user) == CApi.Opcode.STORE && (void*) CApi.operand (user, 0) == (void*) acquisition) {
				assert ((void*) copied == null);
				copied = user;
			}
		}
		assert ((void*) copied != null);
		int field = frame.lifetime_field (CApi.operand (copied, 1));
		assert (field >= 0);
		CApi.ValueRef snapshot = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.LOAD && frame.lifetime_field (CApi.operand (i, 0)) == field && (void*) snapshot == null) {
					snapshot = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_release_wait") && (void*) CApi.is_constant_int (CApi.operand (i, 1)) != null && CApi.const_int_zext (CApi.operand (i, 1)) == 1 && (void*) release == null) {
					release = i;
				}
			}
		}
		assert ((void*) snapshot != null && (void*) release != null);
		var pointer = CApi.type_of (acquisition);
		var waited = CApi.operand (acquisition, 0);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.set_operand (acquisition, 0, frame.task);
		valid_ir (artifact.module);
		Test.message ("await control: wrong waited child");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (acquisition, 0, waited);
		artifact.verify_scoped_allocations ();
		CApi.set_instruction_call_conv (acquisition, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		Test.message ("await control: wrong runtime calling convention");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_instruction_call_conv (acquisition, CApi.CallConv.C);
		artifact.verify_scoped_allocations ();
		var original_phase = CApi.operand (phase, 0);
		CApi.set_operand (phase, 0, frame.task);
		valid_ir (artifact.module);
		Test.message ("await control: phase read from a different task");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (phase, 0, original_phase);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (acquisition));
		CApi.ValueRef[] arguments = {
			waited
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (acquisition), CApi.called_value (acquisition), arguments, 1, "invalid.second.child.exception");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		valid_ir (artifact.module);
		Test.message ("await control: duplicate exception acquisition");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.erase_instruction (duplicate);
		artifact.verify_scoped_allocations ();
		var transfer = CApi.operand (release, 1);
		CApi.set_operand (release, 1, CApi.const_null (CApi.type_of (transfer)));
		valid_ir (artifact.module);
		Test.message ("await control: discard after exception acquisition");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (release, 1, transfer);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (copied, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		Test.message ("await control: missing physical frame publication");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (copied, 0, acquisition);
		artifact.verify_scoped_allocations ();
		CApi.set_volatile (snapshot, 1);
		valid_ir (artifact.module);
		Test.message ("await control: volatile frame read");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_volatile (snapshot, 0);
		artifact.verify_scoped_allocations ();
		var escape_target = declaration (artifact, "invalid.coroutine.error.address.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.position_builder_before (builder, CApi.next_instruction (copied));
		CApi.ValueRef[] escaped = {
			CApi.operand (copied, 1)
		};
		var escape = CApi.build_call (builder, CApi.global_value_type (escape_target), escape_target, escaped, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		Test.message ("await control: escaping frame field address");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.erase_instruction (escape);
		CApi.delete_function (escape_target);
		artifact.verify_scoped_allocations ();
		// Cold origin cells rely on the actual factory's aggregate zero store.
		CApi.ValueRef initialized = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.factory); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.STORE && (void*) CApi.type_of (CApi.operand (i, 0)) == (void*) frame.frame_type) {
					initialized = i;
				}
			}
		}
		assert ((void*) initialized != null);
		var environment = CApi.operand (initialized, 1);
		CApi.set_operand (initialized, 1, CApi.const_null (pointer));
		valid_ir (artifact.module);
		Test.message ("await control: missing cold frame zero initialization");
		refused (() => artifact.verify_scoped_allocations ());
		CApi.set_operand (initialized, 1, environment);
		artifact.verify_scoped_allocations ();
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void same_nominal_errors(LlvmModuleArtifact artifact, LlvmAsyncFrameBinding frame) throws GLib.Error {
		artifact.verify ();
		var constructor = artifact.class_constructor (1);
		var mutation = CApi.named_function (artifact.module, "astra.class.method.1.0");
		CApi.ValueRef admission_init = (CApi.ValueRef) null;
		CApi.ValueRef put = (CApi.ValueRef) null;
		CApi.ValueRef complete = (CApi.ValueRef) null;
		CApi.ValueRef descriptor_store = (CApi.ValueRef) null;
		CApi.ValueRef frame_null = (CApi.ValueRef) null;
		int runtime_field = -1;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) constructor && CApi.opcode (CApi.operand (i, 0)) == CApi.Opcode.PHI) {
					admission_init = i;
				}
				if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) mutation) {
					put = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_complete") && CApi.argument_count (i) == 3 && (void*) CApi.is_constant_int (CApi.operand (i, 1)) != null && CApi.const_int_zext (CApi.operand (i, 1)) == 6) {
					complete = i;
				}
				if (CApi.opcode (i) == CApi.Opcode.STORE && (void*) CApi.operand (i, 0) == (void*) artifact.scoped_descriptors.lookup (1).value) {
					descriptor_store = i;
				}
			}
		}
		assert ((void*) admission_init != null && (void*) put != null && (void*) complete != null && (void*) descriptor_store != null);
		var root = CApi.operand (admission_init, 0);
		for (var use = CApi.first_use (root); (void*) use != null; use = CApi.next_use (use)) {
			var store = CApi.user (use);
			if ((void*) CApi.is_instruction (store) != null && CApi.opcode (store) == CApi.Opcode.STORE && (void*) CApi.operand (store, 0) == (void*) root) {
				int field = frame.lifetime_field (CApi.operand (store, 1));
				if (field >= 0) {
					runtime_field = field;
				}
			}
		}
		assert (runtime_field >= 0);
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.STORE && frame.lifetime_field (CApi.operand (i, 1)) == runtime_field && (void*) CApi.is_constant_pointer_null (CApi.operand (i, 0)) != null) {
					frame_null = i;
				}
			}
		}
		assert ((void*) frame_null != null);
		CApi.set_operand (admission_init, 0, CApi.const_null (CApi.type_of (root)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "constructor initialization", "initialized carrier", "local carrier");
		CApi.set_operand (admission_init, 0, root);
		artifact.verify_scoped_allocations ();
		var input = CApi.operand (put, 1);
		CApi.set_operand (put, 1, CApi.const_null (CApi.type_of (input)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired captured owner", "retained scoped owner", "live payload field");
		CApi.set_operand (put, 1, input);
		artifact.verify_scoped_allocations ();
		var receiver = CApi.operand (put, 0);
		CApi.set_operand (put, 0, CApi.const_null (CApi.type_of (receiver)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "local carrier", "receiver cell", "initialized carrier");
		CApi.set_operand (put, 0, receiver);
		artifact.verify_scoped_allocations ();
		var parent = CApi.operand (complete, 0);
		CApi.set_operand (complete, 0, CApi.const_null (CApi.type_of (parent)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live publication carrier", "actual completion");
		CApi.set_operand (complete, 0, parent);
		artifact.verify_scoped_allocations ();
		var phase = CApi.operand (complete, 1);
		CApi.set_operand (complete, 1, CApi.const_int (CApi.type_of (phase), 5, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual exception completion phase", "actual completion");
		CApi.set_operand (complete, 1, phase);
		artifact.verify_scoped_allocations ();
		var descriptor = CApi.operand (descriptor_store, 0);
		CApi.set_operand (descriptor_store, 0, CApi.const_null (CApi.type_of (descriptor)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "descriptor initialization");
		CApi.set_operand (descriptor_store, 0, descriptor);
		artifact.verify_scoped_allocations ();
		var absent = CApi.operand (frame_null, 0);
		CApi.set_operand (frame_null, 0, frame.task);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "frame", "carrier", "payload store");
		CApi.set_operand (frame_null, 0, absent);
		artifact.verify_scoped_allocations ();
		CApi.ValueRef make_null = (CApi.ValueRef) null;
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.CALL && CApi.type_kind (CApi.type_of (i)) == CApi.TypeKind.POINTER && CApi.argument_count (i) == 0) {
					make_null = CApi.called_value (i);
				}
			}
		}
		assert ((void*) make_null != null);
		var end = CApi.block_terminator (CApi.first_block (make_null));
		var zero = CApi.operand (end, 0);
		CApi.set_operand (end, 0, make_null);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "literal-null return publication");
		CApi.set_operand (end, 0, zero);
		artifact.verify ();
	}

	internal static void host_scoped_errors(LlvmModuleArtifact artifact, CApi.ValueRef function) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef call = (CApi.ValueRef) null;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_run")) {
					assert ((void*) call == null);
					call = i;
				}
			}
		}
		assert ((void*) call != null);
		var slot = CApi.operand (call, 2);
		CApi.ValueRef read = (CApi.ValueRef) null;
		for (var use = CApi.first_use (slot); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) != null && CApi.opcode (user) == CApi.Opcode.LOAD) {
				assert ((void*) read == null);
				read = user;
			}
		}
		assert ((void*) read != null);
		var pointer = CApi.type_of (read);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.set_operand (call, 2, CApi.operand (call, 1));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact private output slot");
		CApi.set_operand (call, 2, slot);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, read);
		var extra = CApi.build_load (builder, pointer, slot, "invalid.duplicate.host.error.read");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unique actual read");
		CApi.erase_instruction (extra);
		artifact.verify_scoped_allocations ();
		var next = CApi.next_instruction (read);
		CApi.remove_instruction (read);
		CApi.position_builder_before (builder, call);
		CApi.insert_instruction (builder, read);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unique actual read");
		CApi.remove_instruction (read);
		CApi.position_builder_before (builder, next);
		CApi.insert_instruction (builder, read);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, read);
		var overwrite = CApi.build_store (builder, CApi.const_null (pointer), slot);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unique actual read");
		CApi.erase_instruction (overwrite);
		artifact.verify_scoped_allocations ();
		var escape_target = declaration (artifact, "invalid.host.error.slot.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.ValueRef[] escaped = {
			slot
		};
		var escape = CApi.build_call (builder, CApi.global_value_type (escape_target), escape_target, escaped, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unique actual read");
		CApi.erase_instruction (escape);
		CApi.delete_function (escape_target);
		artifact.verify_scoped_allocations ();
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact runtime ABI");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.verify_scoped_allocations ();
		CApi.ValueRef copied = (CApi.ValueRef) null;
		for (var use = CApi.first_use (read); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			if ((void*) CApi.is_instruction (user) != null && CApi.opcode (user) == CApi.Opcode.STORE && (void*) CApi.operand (user, 0) == (void*) read) {
				copied = user;
			}
		}
		assert ((void*) copied != null);
		CApi.set_operand (copied, 0, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation", "unretired heap carrier", "before its derived allocation");
		CApi.set_operand (copied, 0, read);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, call);
		var other_slot = CApi.build_alloca (builder, pointer, "invalid.second.host.error.slot");
		CApi.position_builder_before (builder, CApi.next_instruction (read));
		CApi.ValueRef[] arguments = {
			CApi.operand (call, 0), CApi.operand (call, 1), other_slot
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (call), CApi.called_value (call), arguments, 3, "invalid.second.host.observation");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		extra = CApi.build_load (builder, pointer, other_slot, "invalid.second.host.error");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact retained ownership", "original task observation");
		CApi.erase_instruction (extra);
		CApi.erase_instruction (duplicate);
		CApi.erase_instruction (other_slot);
		artifact.verify_scoped_allocations ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		CApi.ValueRef publication = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (LlvmScopedHeapCarrier.named_call (i, "astra_async_complete") && CApi.argument_count (i) == 3 && (void*) CApi.is_constant_int (CApi.operand (i, 1)) != null && CApi.const_int_zext (CApi.operand (i, 1)) == 6 && (void*) CApi.is_constant_pointer_null (CApi.operand (i, 2)) == null) {
					publication = i;
				}
			}
		}
		assert ((void*) publication != null);
		var payload = CApi.operand (publication, 2);
		CApi.set_operand (publication, 2, CApi.const_null (CApi.type_of (payload)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "deferred scoped exception");
		CApi.set_operand (publication, 2, payload);
		artifact.verify_scoped_allocations ();
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void mixed_error_choices(LlvmModuleArtifact artifact, CApi.ValueRef function) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef choice = (CApi.ValueRef) null;
		CApi.ValueRef construction = (CApi.ValueRef) null;
		CApi.ValueRef descriptor = (CApi.ValueRef) null;
		CApi.ValueRef peek = (CApi.ValueRef) null;
		CApi.ValueRef cleanup = (CApi.ValueRef) null;
		var constructor = CApi.named_function (artifact.module, "astra.ctor.2");
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) constructor) {
					construction = i;
				}
				if (CApi.opcode (i) == CApi.Opcode.STORE) {
					size_t length;
					if (CApi.value_name (CApi.operand (i, 0), out length) == "astra.class.descriptor.2") {
						descriptor = i;
					}
				}
				if (CApi.opcode (i) == CApi.Opcode.PHI && CApi.incoming_count (i) == 2 && CApi.type_kind (CApi.type_of (i)) == CApi.TypeKind.POINTER) {
					var left = CApi.incoming_value (i, 0);
					var right = CApi.incoming_value (i, 1);
					if ((void*) CApi.is_instruction (left) != null && (void*) CApi.is_instruction (right) != null && CApi.opcode (left) == CApi.Opcode.CALL && CApi.opcode (right) == CApi.Opcode.LOAD) {
						choice = i;
					}
				}
			}
		}
		assert ((void*) choice != null && (void*) construction != null && (void*) descriptor != null);
		for (var use = CApi.first_use (choice); (void*) use != null; use = CApi.next_use (use)) {
			var call = CApi.user (use);
			if ((void*) CApi.is_instruction (call) == null || CApi.opcode (call) != CApi.Opcode.CALL || CApi.argument_count (call) != 1 || (void*) CApi.operand (call, 0) != (void*) choice) {
				continue;
			}
			if (CApi.type_kind (CApi.type_of (call)) == CApi.TypeKind.INTEGER) {
				peek = call;
			} else if (CApi.type_kind (CApi.type_of (call)) == CApi.TypeKind.VOID && (void*) CApi.is_instruction (CApi.called_value (call)) != null) {
				cleanup = call;
			}
		}
		assert ((void*) peek != null && (void*) cleanup != null);
		var input = CApi.operand (construction, 0);
		CApi.set_operand (construction, 0, CApi.const_null (CApi.type_of (input)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped its local frame");
		CApi.set_operand (construction, 0, input);
		artifact.verify_scoped_allocations ();
		var identity = CApi.operand (descriptor, 0);
		CApi.set_operand (descriptor, 0, CApi.const_null (CApi.type_of (identity)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "descriptor initialization");
		CApi.set_operand (descriptor, 0, identity);
		artifact.verify_scoped_allocations ();
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, peek);
		CApi.ValueRef address = (CApi.ValueRef) null;
		CApi.TypeRef parent = (CApi.TypeRef) null;
		for (var block = CApi.first_block (CApi.named_function (artifact.module, "astra.ctor.1")); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.GEP && CApi.operand_count (i) == 3 && (void*) CApi.operand (i, 0) == (void*) CApi.get_param (CApi.named_function (artifact.module, "astra.ctor.1"), 0)) {
					parent = CApi.gep_source_type (i);
				}
			}
		}
		assert ((void*) parent != null);
		address = CApi.build_struct_gep (builder, parent, choice, 2, "invalid.empty.error.payload");
		var overwrite = CApi.build_store (builder, CApi.const_null (CApi.type_of (choice)), address);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "cannot acquire a payload store");
		CApi.erase_instruction (overwrite);
		CApi.erase_instruction (address);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (cleanup, 0, CApi.const_null (CApi.type_of (choice)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its checked cleanup", "before its owned field cleanup", "before its derived allocation");
		CApi.set_operand (cleanup, 0, choice);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, construction);
		var pointer = CApi.type_of (choice);
		CApi.TypeRef[] header_fields = {
			pointer, pointer
		};
		var header = CApi.struct_type_in_context (artifact.context, header_fields, 2, 0);
		var header_address = CApi.build_struct_gep (builder, header, input, 0, "invalid.early.empty.header");
		var header_value = CApi.build_load (builder, pointer, header_address, "invalid.early.empty.descriptor");
		CApi.TypeRef[] descriptor_fields = {
			pointer, pointer, pointer
		};
		var descriptor_layout = CApi.struct_type_in_context (artifact.context, descriptor_fields, 3, 0);
		var target_address = CApi.build_struct_gep (builder, descriptor_layout, header_value, 1, "invalid.early.empty.cleanup.slot");
		var target = CApi.build_load (builder, pointer, target_address, "invalid.early.empty.cleanup");
		CApi.ValueRef[] early_payload = {
			input
		};
		var early = CApi.build_call (builder, CApi.called_function_type (cleanup), target, early_payload, 1, "");
		CApi.set_instruction_call_conv (early, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "initialized original carrier", "live uninitialized carrier");
		CApi.erase_instruction (early);
		CApi.erase_instruction (target);
		CApi.erase_instruction (target_address);
		CApi.erase_instruction (header_value);
		CApi.erase_instruction (header_address);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (construction));
		CApi.ValueRef[] arguments = {
			input, CApi.operand (construction, 1), CApi.operand (construction, 2)
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (construction), constructor, arguments, 3, "");
		CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live uninitialized carrier");
		CApi.erase_instruction (duplicate);
		artifact.verify_scoped_allocations ();
		var base_cleanup = CApi.first_instruction (CApi.first_block (CApi.named_function (artifact.module, "astra.dtor.2")));
		assert (CApi.opcode (base_cleanup) == CApi.Opcode.CALL);
		var receiver = CApi.operand (base_cleanup, 0);
		CApi.set_operand (base_cleanup, 0, CApi.const_null (CApi.type_of (receiver)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact base cleanup");
		CApi.set_operand (base_cleanup, 0, receiver);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (cleanup));
		CApi.ValueRef[] payload = {
			choice
		};
		duplicate = CApi.build_call (builder, CApi.called_function_type (cleanup), CApi.called_value (cleanup), payload, 1, "");
		CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "occupied live carrier", "initialized original carrier");
		CApi.erase_instruction (duplicate);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void mutating_scoped_fields(LlvmModuleArtifact artifact, CApi.ValueRef caller, bool empty) throws GLib.Error {
		artifact.verify ();
		var mutation = CApi.named_function (artifact.module, "astra.class.method.1.0");
		var read = CApi.named_function (artifact.module, "astra.class.method.0.0");
		var constructor = artifact.class_constructor (1);
		CApi.TypeRef layout = (CApi.TypeRef) null;
		for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.GEP) {
					layout = CApi.gep_source_type (i);
				}
			}
		}
		assert ((void*) layout != null);
		CApi.ValueRef call = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) mutation) {
					call = i;
				}
				if (LlvmScopedHeapCarrier.named_call (i, "astra_context17_destroy")) {
					release = i;
				}
			}
		}
		assert ((void*) call != null && (void*) release != null);
		var root = CApi.operand (call, 0);
		var incoming = CApi.operand (call, 1);
		CApi.set_operand (call, 1, root);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "incoming owner", "consuming and borrowed", "address escaped");
		CApi.set_operand (call, 1, incoming);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (root)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "receiver cell", "local carrier", "exact occupied");
		CApi.set_operand (call, 0, root);
		artifact.verify_scoped_allocations ();
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, call);
		var field = CApi.build_struct_gep (builder, layout, root, 0, "old.field.address");
		var snapshot = CApi.build_load (builder, CApi.type_of (incoming), field, "old.field.snapshot");
		valid_ir (artifact.module);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (call));
		CApi.ValueRef[] args = {
			snapshot
		};
		var stale = CApi.build_call (builder, CApi.global_value_type (read), read, args, 1, "stale.field.read");
		CApi.set_instruction_call_conv (stale, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "snapshot outlived", "exact live owner");
		CApi.erase_instruction (stale);
		artifact.verify_scoped_allocations ();
		CApi.set_volatile (snapshot, 1);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "ordinary pointer load", "ordinary scalar accesses");
		CApi.set_volatile (snapshot, 0);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, call);
		CApi.ValueRef[] context_args = {
			CApi.operand (release, 0)
		};
		var early = CApi.build_call (builder, CApi.called_function_type (release), CApi.called_value (release), context_args, 1, "");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "retired before its derived allocation", "exact live loan");
		CApi.erase_instruction (early);
		artifact.verify_scoped_allocations ();
		if (empty) {
			CApi.ValueRef make_null = (CApi.ValueRef) null;
			for (var block = CApi.first_block (constructor); (void*) block != null; block = CApi.next_block (block)) {
				for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
					if (CApi.opcode (i) == CApi.Opcode.CALL && CApi.type_kind (CApi.type_of (i)) == CApi.TypeKind.POINTER && CApi.argument_count (i) == 0) {
						make_null = CApi.called_value (i);
					}
				}
			}
			assert ((void*) make_null != null);
			var end = CApi.block_terminator (CApi.first_block (make_null));
			var absent = CApi.operand (end, 0);
			CApi.set_operand (end, 0, make_null);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "literal-null return publication");
			CApi.set_operand (end, 0, absent);
			artifact.verify_scoped_allocations ();
		}
		CApi.erase_instruction (snapshot);
		CApi.erase_instruction (field);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void imported_scoped_errors(LlvmModuleArtifact artifact, CApi.ValueRef constructor, CApi.ValueRef destructor) throws GLib.Error {
		artifact.verify ();
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (var target in new CApi.ValueRef[] { constructor, destructor }) {
			assert ((void*) target != null && CApi.count_basic_blocks (target) == 0);
			var body = CApi.append_basic_block_in_context (artifact.context, target, "invalid.native.empty.body");
			CApi.position_builder_at_end (builder, body);
			CApi.build_ret_void (builder);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "native module function");
			CApi.delete_basic_block (body);
			artifact.verify_scoped_allocations ();
		}
		int descriptors = 0;
		foreach (var authority in artifact.scoped_descriptors.get_values ()) {
			var descriptor = authority.value;
			assert ((void*) CApi.get_initializer (descriptor) == null);
			descriptors++;
			CApi.set_global_constant (descriptor, 0);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "immutable native descriptor", "exact immutable publication correspondence");
			CApi.set_global_constant (descriptor, 1);
			artifact.verify_scoped_allocations ();
			CApi.set_initializer (descriptor, CApi.const_null (CApi.global_value_type (descriptor)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "immutable native descriptor", "exact immutable publication correspondence");
			CApi.set_initializer (descriptor, (CApi.ValueRef) null);
			artifact.verify_scoped_allocations ();
			size_t length;
			string symbol = CApi.value_name (descriptor, out length);
			CApi.set_value_name (descriptor, "invalid.native.descriptor", 25);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "original external symbol");
			CApi.set_value_name (descriptor, symbol, symbol.length);
			artifact.verify_scoped_allocations ();
		}
		assert (descriptors == 2);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void empty_deferred_errors(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		assert (frame.scoped_captures != null && frame.scoped_captures.deferred_error);
		var target = artifact.class_constructor (2);
		var destructor = artifact.class_destructor (2);
		CApi.ValueRef initialized = (CApi.ValueRef) null;
		CApi.ValueRef descriptor = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		int error_field = -1;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) target) {
					initialized = i;
				}
				if (CApi.opcode (i) == CApi.Opcode.CALL && LlvmScopedHeapCarrier.named_call (i, "astra_context17_release_origin_checked") && (void*) CApi.is_constant_pointer_null (CApi.operand (i, 0)) == null) {
					release = i;
				}
				if (CApi.opcode (i) == CApi.Opcode.STORE) {
					if ((void*) CApi.operand (i, 0) == (void*) artifact.scoped_descriptors.lookup (2).value) {
						descriptor = i;
					}
				}
			}
		}
		assert ((void*) initialized != null && (void*) descriptor != null && (void*) release != null);
		for (var use = CApi.first_use (CApi.operand (initialized, 0)); (void*) use != null; use = CApi.next_use (use)) {
			var store = CApi.user (use);
			if ((void*) CApi.is_instruction (store) != null && CApi.opcode (store) == CApi.Opcode.STORE && (void*) CApi.operand (store, 0) == (void*) CApi.operand (initialized, 0)) {
				int field = frame.lifetime_field (CApi.operand (store, 1));
				if (field >= 0) {
					error_field = field;
				}
			}
		}
		assert (error_field >= 0);
		CApi.ValueRef complete = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (!LlvmScopedHeapCarrier.named_call (i, "astra_async_complete")) {
					continue;
				}
				var value = CApi.operand (i, 2);
				if ((void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.LOAD && frame.lifetime_field (CApi.operand (value, 0)) == error_field) {
					complete = i;
				}
			}
		}
		assert ((void*) complete != null);
		var root = CApi.operand (initialized, 0);
		CApi.set_operand (initialized, 0, CApi.const_null (CApi.type_of (root)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live publication carrier");
		CApi.set_operand (initialized, 0, root);
		artifact.verify_scoped_allocations ();
		var identity = CApi.operand (descriptor, 0);
		CApi.set_operand (descriptor, 0, CApi.const_null (CApi.type_of (identity)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "descriptor initialization");
		CApi.set_operand (descriptor, 0, identity);
		artifact.verify_scoped_allocations ();
		var base_cleanup = CApi.first_instruction (CApi.first_block (destructor));
		assert (CApi.opcode (base_cleanup) == CApi.Opcode.CALL);
		var receiver = CApi.operand (base_cleanup, 0);
		CApi.set_operand (base_cleanup, 0, CApi.const_null (CApi.type_of (receiver)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact base cleanup");
		CApi.set_operand (base_cleanup, 0, receiver);
		artifact.verify_scoped_allocations ();
		var replacement = declaration (artifact, "invalid.empty.error.constructor", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { CApi.type_of (CApi.operand (initialized, 0)), CApi.type_of (CApi.operand (initialized, 1)), CApi.type_of (CApi.operand (initialized, 2)) });
		CApi.set_function_call_conv (replacement, LlvmLowering.CALL_CONVENTION);
		CApi.set_operand (initialized, CApi.argument_count (initialized), replacement);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live publication carrier");
		CApi.set_operand (initialized, CApi.argument_count (initialized), target);
		CApi.delete_function (replacement);
		artifact.verify_scoped_allocations ();
		var input = CApi.operand (release, 0);
		CApi.set_operand (release, 0, CApi.const_null (CApi.type_of (input)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired captured owner");
		CApi.set_operand (release, 0, input);
		artifact.verify_scoped_allocations ();
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, complete);
		CApi.ValueRef[] arguments = {
			CApi.operand (complete, 2), CApi.operand (initialized, 1), CApi.operand (initialized, 2)
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (initialized), target, arguments, 3, "");
		CApi.set_instruction_call_conv (duplicate, LlvmLowering.CALL_CONVENTION);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "live uninitialized carrier");
		CApi.erase_instruction (duplicate);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void deferred_error_publication(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		assert (frame.scoped_captures != null && frame.scoped_captures.deferred_error && frame.scoped_captures.error_count == 1);
		CApi.ValueRef complete = (CApi.ValueRef) null;
		CApi.ValueRef callback = (CApi.ValueRef) null;
		CApi.ValueRef construction = (CApi.ValueRef) null;
		CApi.ValueRef descriptor = (CApi.ValueRef) null;
		CApi.ValueRef backing_store = (CApi.ValueRef) null;
		foreach (var function in new CApi.ValueRef[] { frame.resume, frame.destroy }) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
					if (CApi.opcode (i) == CApi.Opcode.CALL) {
						size_t n;
						string name = CApi.value_name (CApi.called_value (i), out n);
						if (name == "astra_async_complete" && (void*) CApi.is_constant_int (CApi.operand (i, 1)) != null && CApi.const_int_zext (CApi.operand (i, 1)) == 6) {
							complete = i;
						}
						if (name == "astra_async_discarded_exception") {
							callback = i;
						}
						if (name.has_prefix ("astra.ctor.")) {
							construction = i;
						}
					}
					if (CApi.opcode (i) == CApi.Opcode.STORE) {
						var value = CApi.operand (i, 0);
						size_t n;
						if (CApi.value_name (value, out n).has_prefix ("astra.class.descriptor.")) {
							descriptor = i;
						}
						if ((void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.PHI && frame.lifetime_field (CApi.operand (i, 1)) >= 0) {
							backing_store = i;
						}
					}
				}
			}
		}
		assert ((void*) complete != null && (void*) callback != null && (void*) construction != null && (void*) descriptor != null && (void*) backing_store != null);
		var escape_target = declaration (artifact, "invalid.scoped.exception.escape", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { CApi.type_of (CApi.operand (complete, 2)) });
		var escape_builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (escape_builder, complete);
		CApi.ValueRef[] escaped_arguments = {
			CApi.operand (complete, 2)
		};
		var escape = CApi.build_call (escape_builder, CApi.global_value_type (escape_target), escape_target, escaped_arguments, 1, "");
		CApi.set_instruction_call_conv (escape, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped its local frame");
		CApi.erase_instruction (escape);
		CApi.delete_function (escape_target);
		CApi.dispose_builder (escape_builder);
		artifact.verify_scoped_allocations ();
		var payload = CApi.operand (complete, 2);
		CApi.set_operand (complete, 2, CApi.const_null (CApi.type_of (payload)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "deferred scoped exception");
		CApi.set_operand (complete, 2, payload);
		artifact.verify_scoped_allocations ();
		var phase = CApi.operand (complete, 1);
		CApi.set_operand (complete, 1, CApi.const_int (CApi.type_of (phase), 5, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "retained scoped owner", "unretired scoped allocation");
		CApi.set_operand (complete, 1, phase);
		artifact.verify_scoped_allocations ();
		for (uint p = 0; p < 2; p++) {
			var original = CApi.operand (callback, p);
			CApi.set_operand (callback, p, CApi.const_null (CApi.type_of (original)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "retirement callback ABI");
			CApi.set_operand (callback, p, original);
			artifact.verify_scoped_allocations ();
		}
		var identity = CApi.operand (descriptor, 0);
		CApi.set_operand (descriptor, 0, CApi.const_null (CApi.type_of (identity)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "descriptor initialization");
		CApi.set_operand (descriptor, 0, identity);
		artifact.verify_scoped_allocations ();
		var input = CApi.operand (construction, 1);
		CApi.set_operand (construction, 1, CApi.const_null (CApi.type_of (input)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "original live payload field", "retained scoped owner");
		CApi.set_operand (construction, 1, input);
		artifact.verify_scoped_allocations ();
		var backing = CApi.operand (backing_store, 0);
		CApi.set_operand (backing_store, 0, CApi.const_null (CApi.type_of (backing)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "nonescaping local carrier");
		CApi.set_operand (backing_store, 0, backing);
		artifact.verify_scoped_allocations ();
		var receiver = CApi.operand (construction, 0);
		assert (CApi.opcode (receiver) == CApi.Opcode.LOAD);
		CApi.set_volatile (receiver, 1);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "ordinary pointer accesses", "nonescaping local carrier");
		CApi.set_volatile (receiver, 0);
		artifact.verify_scoped_allocations ();
		CApi.ValueRef empty_base = (CApi.ValueRef) null;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			if (CApi.count_params (function) < 2) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
					if (CApi.opcode (i) == CApi.Opcode.CALL && (void*) CApi.called_value (i) == (void*) CApi.called_value (construction) && (void*) CApi.operand (i, 0) == (void*) CApi.get_param (function, 0)) {
						empty_base = i;
					}
				}
			}
		}
		assert ((void*) empty_base != null);
		var empty = CApi.operand (empty_base, 1);
		var constructor = CApi.block_parent (CApi.instruction_parent (empty_base));
		CApi.set_operand (empty_base, 1, CApi.get_param (constructor, 1));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "cannot acquire a base payload");
		CApi.set_operand (empty_base, 1, empty);
		artifact.verify ();
	}

	internal static void pure_empty_result(LlvmModuleArtifact artifact, bool captures, bool single) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		assert (frame.scoped_captures != null && frame.scoped_captures.count == (captures ? 1 : 0) && frame.scoped_result != null && frame.scoped_result.owner_count == 0 && frame.scoped_result.empty_count == 1 && frame.scoped_result.empty_field (0) && frame.scoped_result.field_count == (single ? 1 : 2));
		CApi.ValueRef published = (CApi.ValueRef) null;
		CApi.ValueRef initialized = (CApi.ValueRef) null;
		CApi.ValueRef original_input = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.STORE) {
					int field = frame.lifetime_field (CApi.operand (i, 1));
					if (field == 0) {
						published = i;
					}
					if (field == frame.result_live_field ()) {
						initialized = i;
					}
				}
				if (captures && (void*) original_input == null && CApi.opcode (i) == CApi.Opcode.LOAD && frame.lifetime_field (CApi.operand (i, 0)) == 1) {
					original_input = i;
				}
			}
		}
		assert ((void*) published != null && (void*) initialized != null);
		var marked = CApi.operand (initialized, 0);
		CApi.set_operand (initialized, 0, CApi.const_null (CApi.type_of (marked)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "initialized flag");
		CApi.set_operand (initialized, 0, marked);
		artifact.verify_scoped_allocations ();
		if (captures) {
			assert ((void*) original_input != null);
			var publication = published;
			uint operand = 0;
			if (!single) {
				publication = CApi.operand (published, 0);
				while (CApi.indices (publication)[0] != 0) {
					publication = CApi.operand (publication, 0);
				}
				operand = 1;
			}
			var empty = CApi.operand (publication, operand);
			CApi.set_operand (publication, operand, original_input);
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
			CApi.set_operand (publication, operand, empty);
			artifact.verify_scoped_allocations ();
		}
		artifact.verify ();
	}

	internal static void empty_result_access(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		CApi.ValueRef leaf = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.destroy); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) == CApi.Opcode.EXTRACT_VALUE && CApi.index_count (i) == 1 && CApi.indices (i)[0] == 0 && (void*) CApi.type_of (i) == (void*) CApi.pointer_type_in_context (artifact.context, 0)) {
					leaf = i;
				}
			}
		}
		assert ((void*) leaf != null);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, CApi.next_instruction (leaf));
		var word = CApi.int32_type_in_context (artifact.context);
		var zero = CApi.const_int (word, 0, 0);
		var address = CApi.build_gep (builder, word, leaf, &zero, 1, "invalid.empty.result.address");
		var read = CApi.build_load (builder, word, address, "invalid.empty.result.read");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.erase_instruction (read);
		CApi.erase_instruction (address);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void result_callers(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 2);
		var frame = artifact.async_frames[1];
		CApi.ValueRef phase = (CApi.ValueRef) null;
		CApi.ValueRef data = (CApi.ValueRef) null;
		CApi.ValueRef read = (CApi.ValueRef) null;
		CApi.ValueRef observed = (CApi.ValueRef) null;
		CApi.ValueRef success_switch = (CApi.ValueRef) null;
		var releases = new GenericArray<void*> ();
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) == CApi.Opcode.SWITCH) {
				var condition = CApi.operand (end, 0);
				if (CApi.opcode (condition) == CApi.Opcode.CALL && LlvmScopedHeapCarrier.named_call (condition, "astra_async_phase")) {
					phase = condition;
					success_switch = end;
				}
			}
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				size_t length;
				if (CApi.opcode (i) == CApi.Opcode.LOAD && (void*) CApi.type_of (i) == (void*) artifact.async_frames[0].scoped_result.result_type ()) {
					read = i;
					data = CApi.operand (i, 0);
				}
				if (CApi.opcode (i) == CApi.Opcode.CALL) {
					string name = CApi.value_name (CApi.called_value (i), out length);
					if (name == "astra_async_release_wait" && CApi.const_int_zext (CApi.operand (i, 1)) == 1) {
						observed = i;
					}
					if (name == "astra_context17_release_origin_checked" && (void*) CApi.is_constant_pointer_null (CApi.operand (i, 0)) == null) {
						releases.add ((void*) i);
					}
				}
			}
		}
		assert ((void*) phase != null && (void*) data != null && (void*) read != null && (void*) observed != null && (void*) success_switch != null && releases.length >= 2);
		var builder = CApi.create_builder_in_context (artifact.context);
		var original = CApi.operand (phase, 0);
		CApi.set_operand (phase, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (phase, 0, original);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (success_switch, 0);
		CApi.set_operand (success_switch, 0, CApi.const_int (CApi.type_of (original), 5, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (success_switch, 0, original);
		artifact.verify_scoped_allocations ();
		var success = CApi.successor (success_switch, 1);
		var failed = CApi.successor (success_switch, 2);
		CApi.set_successor (success_switch, 1, failed);
		CApi.set_successor (success_switch, 2, success);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_successor (success_switch, 1, success);
		CApi.set_successor (success_switch, 2, failed);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (data, 0);
		CApi.set_operand (data, 0, frame.task);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (data, 0, original);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (observed, 1);
		CApi.set_operand (observed, 1, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (observed, 1, original);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, read);
		var duplicate = CApi.build_load (builder, CApi.type_of (read), data, "invalid.duplicate.result.read");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.erase_instruction (duplicate);
		artifact.verify_scoped_allocations ();
		foreach (void* address in releases) {
			var release = (CApi.ValueRef) address;
			original = CApi.operand (release, 0);
			CApi.set_operand (release, 0, CApi.const_null (CApi.type_of (original)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
			CApi.set_operand (release, 0, original);
			artifact.verify_scoped_allocations ();
		}
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void result_publication(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		assert (frame.scoped_result != null && frame.scoped_result.owner_count == 2);
		CApi.ValueRef published = (CApi.ValueRef) null;
		CApi.ValueRef initialized = (CApi.ValueRef) null;
		CApi.ValueRef discard = (CApi.ValueRef) null;
		var releases = new GenericArray<void*> ();
		for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				if (CApi.opcode (i) != CApi.Opcode.STORE) {
					continue;
				}
				int field = frame.lifetime_field (CApi.operand (i, 1));
				if (field == 0) {
					published = i;
				}
				if (field == frame.result_live_field ()) {
					initialized = i;
				}
			}
		}
		for (var block = CApi.first_block (frame.destroy); (void*) block != null; block = CApi.next_block (block)) {
			for (var i = CApi.first_instruction (block); (void*) i != null; i = CApi.next_instruction (i)) {
				size_t length;
				if (CApi.opcode (i) == CApi.Opcode.ICMP && (void*) CApi.operand (i, 0) == (void*) CApi.get_param (frame.destroy, 1)) {
					discard = i;
				}
				if (CApi.opcode (i) == CApi.Opcode.CALL && CApi.value_name (CApi.called_value (i), out length) == "astra_context17_release_origin_checked") {
					releases.add ((void*) i);
				}
			}
		}
		assert ((void*) published != null && (void*) initialized != null && (void*) discard != null && releases.length == 4);
		var builder = CApi.create_builder_in_context (artifact.context);
		var original = CApi.operand (published, 0);
		CApi.set_operand (published, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (published, 0, original);
		artifact.verify_scoped_allocations ();
		var insertion = original;
		while (CApi.indices (insertion)[0] != 1) {
			insertion = CApi.operand (insertion, 0);
		}
		var second = CApi.operand (insertion, 1);
		var first = frame.scoped_result.publication_value (published, 0);
		CApi.set_operand (insertion, 1, first);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (insertion, 1, second);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (initialized, 0);
		CApi.set_operand (initialized, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (initialized, 0, original);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (discard, 0);
		CApi.set_operand (discard, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (discard, 0, original);
		artifact.verify_scoped_allocations ();
		CApi.ValueRef discard_guard = (CApi.ValueRef) null;
		for (var use = CApi.first_use (discard); (void*) use != null; use = CApi.next_use (use)) {
			if (CApi.opcode (CApi.user (use)) == CApi.Opcode.AND) {
				discard_guard = CApi.user (use);
			}
		}
		assert ((void*) discard_guard != null);
		uint initialized_term = (void*) CApi.operand (discard_guard, 0) == (void*) discard ? 1U : 0U;
		original = CApi.operand (discard_guard, initialized_term);
		CApi.set_operand (discard_guard, initialized_term, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.set_operand (discard_guard, initialized_term, original);
		artifact.verify_scoped_allocations ();
		foreach (void* address in releases) {
			var release = (CApi.ValueRef) address;
			original = CApi.operand (release, 0);
			CApi.set_operand (release, 0, CApi.const_null (CApi.type_of (original)));
			valid_ir (artifact.module);
			refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
			CApi.set_operand (release, 0, original);
			artifact.verify_scoped_allocations ();
		}
		CApi.position_builder_before (builder, initialized);
		var repeated = CApi.build_store (builder, CApi.operand (published, 0), CApi.operand (published, 1));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.erase_instruction (repeated);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, published);
		var early = CApi.build_load (builder, frame.scoped_result.result_type (), CApi.operand (published, 1), "invalid.early.result");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped");
		CApi.erase_instruction (early);
		artifact.verify_scoped_allocations ();
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void checked_captures(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		CApi.ValueRef task = (CApi.ValueRef) null;
		CApi.ValueRef run = (CApi.ValueRef) null;
		CApi.ValueRef restored = (CApi.ValueRef) null;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) == CApi.Opcode.SELECT && CApi.value_name (instruction, out length) == "frame.input.owner") {
						restored = instruction;
					}
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					if ((void*) CApi.called_value (instruction) == (void*) frame.checked_factory) {
						task = instruction;
					}
					if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_async_run") {
						run = instruction;
					}
				}
			}
		}
		assert ((void*) task != null && (void*) run != null && (void*) restored != null);
		var branch = CApi.block_terminator (CApi.instruction_parent (task));
		var condition = CApi.operand (branch, 0);
		var original = CApi.operand (condition, 0);
		CApi.set_operand (condition, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual nullable factory result");
		CApi.set_operand (condition, 0, original);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (condition, 1);
		CApi.set_operand (condition, 1, CApi.operand (task, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual nullable factory result");
		CApi.set_operand (condition, 1, original);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (branch, 0, CApi.const_null (CApi.type_of (condition)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "actual nullable factory result");
		CApi.set_operand (branch, 0, condition);
		artifact.verify_scoped_allocations ();
		var refused = CApi.successor (branch, 0);
		var accepted = CApi.successor (branch, 1);
		CApi.set_successor (branch, 0, accepted);
		CApi.set_successor (branch, 1, refused);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "original refusal/admission edges");
		CApi.set_successor (branch, 0, refused);
		CApi.set_successor (branch, 1, accepted);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (task, 0);
		CApi.set_operand (task, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped captured task original factory", "scoped task frame factory");
		CApi.set_operand (task, 0, original);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (restored, 1);
		CApi.set_operand (restored, 1, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation", "lost its complete allocation identity");
		CApi.set_operand (restored, 1, original);
		artifact.verify_scoped_allocations ();
		original = CApi.operand (run, 1);
		CApi.set_operand (run, 1, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unobserved scoped captured task");
		CApi.set_operand (run, 1, original);
		artifact.verify_scoped_allocations ();
		CApi.ValueRef captured_store = (CApi.ValueRef) null;
		for (var block = CApi.first_block (frame.checked_factory); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 0) == (void*) CApi.get_param (frame.checked_factory, 0)) {
					captured_store = instruction;
					break;
				}
			}
		}
		assert ((void*) captured_store != null);
		original = CApi.operand (captured_store, 0);
		CApi.set_operand (captured_store, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		bool rejected = false;
		try {
			frame.verify_captured_factory (true);
		} catch (LlvmError failure) {
			Test.message ("%s", failure.message);
			rejected = true;
		}
		assert (rejected);
		CApi.set_operand (captured_store, 0, original);
		artifact.verify_scoped_allocations ();
		artifact.verify ();
	}

	internal static void nested_captures(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 2);
		var builder = CApi.create_builder_in_context (artifact.context);
		uint count = 0;
		foreach (var frame in artifact.async_frames) {
			assert (frame.scoped_captures != null);
			for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
				for (var call = CApi.first_instruction (block); (void*) call != null; call = CApi.next_instruction (call)) {
					size_t length;
					if (CApi.opcode (call) != CApi.Opcode.CALL || CApi.value_name (CApi.called_value (call), out length) != "astra_async_release_wait") {
						continue;
					}
					count++;
					var parent = CApi.operand (call, 0);
					CApi.set_operand (call, 0, CApi.const_null (CApi.type_of (parent)));
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "exact parent and observation ABI");
					CApi.set_operand (call, 0, parent);
					artifact.verify_scoped_allocations ();
					CApi.position_builder_before (builder, CApi.next_instruction (call));
					CApi.ValueRef[] args = {
						parent, CApi.operand (call, 1)
					};
					var duplicate = CApi.build_call (builder, CApi.called_function_type (call), CApi.called_value (call), args, 2, "invalid.duplicate.child.observation");
					CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "lacks its actual admitted observation");
					CApi.erase_instruction (duplicate);
					artifact.verify_scoped_allocations ();
					if (CApi.const_int_zext (args[1]) == 1) {
						var opaque = declaration (artifact, "invalid.unobserved.child", CApi.type_of (call), new CApi.TypeRef[] { CApi.type_of (parent), CApi.type_of (args[1]) });
						var target = CApi.called_value (call);
						CApi.set_operand (call, 2, opaque);
						valid_ir (artifact.module);
						refusal_text (() => artifact.verify_scoped_allocations (), "unobserved scoped captured task");
						CApi.set_operand (call, 2, target);
						artifact.verify_scoped_allocations ();
					}
				}
			}
		}
		assert (count == 2);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void captured_task_callers(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		assert (artifact.async_frames.length == 1);
		var frame = artifact.async_frames[0];
		CApi.ValueRef task = (CApi.ValueRef) null;
		CApi.ValueRef run = (CApi.ValueRef) null;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					size_t length;
					if ((void*) CApi.called_value (instruction) == (void*) frame.factory) {
						task = instruction;
					}
					if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_async_run") {
						run = instruction;
					}
				}
			}
		}
		assert ((void*) task != null && (void*) run != null && (void*) CApi.operand (run, 1) == (void*) task);
		var builder = CApi.create_builder_in_context (artifact.context);
		var original = CApi.operand (run, 1);
		CApi.set_operand (run, 1, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unobserved scoped captured task", "before its derived allocation");
		CApi.set_operand (run, 1, original);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (run));
		CApi.ValueRef[] run_args = {
			CApi.operand (run, 0), task, CApi.operand (run, 2)
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (run), CApi.called_value (run), run_args, 3, "invalid.double.observation");
		CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact retained ownership");
		CApi.erase_instruction (duplicate);
		artifact.verify_scoped_allocations ();
		var start = declaration (artifact, "astra_async_start", CApi.type_of (run), new CApi.TypeRef[] { CApi.type_of (run_args[0]), CApi.type_of (task), CApi.type_of (run_args[2]) });
		var target = CApi.called_value (run);
		CApi.set_operand (run, 3, start);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unobserved scoped captured task", "before its derived allocation");
		CApi.set_operand (run, 3, target);
		artifact.verify_scoped_allocations ();
		var captured = CApi.operand (task, 0);
		var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
		CApi.ValueRef context = (CApi.ValueRef) null;
		var caller = CApi.block_parent (CApi.instruction_parent (task));
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) destroy) {
					context = CApi.operand (instruction, 0);
				}
			}
		}
		assert ((void*) destroy != null && (void*) context != null);
		CApi.position_builder_before (builder, CApi.next_instruction (task));
		CApi.ValueRef[] destroy_args = {
			context
		};
		var early = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, destroy_args, 1, "");
		CApi.set_instruction_call_conv (early, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "before its derived allocation");
		CApi.erase_instruction (early);
		artifact.verify_scoped_allocations ();
		CApi.position_builder_before (builder, CApi.next_instruction (task));
		var slot = CApi.build_alloca (builder, CApi.type_of (task), "invalid.task.escape");
		var escaped = CApi.build_store (builder, task, slot);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "escaped its exact observation");
		CApi.erase_instruction (escaped);
		CApi.erase_instruction (slot);
		artifact.verify_scoped_allocations ();
		var release = CApi.named_function (artifact.module, "astra_context17_release_origin_checked");
		assert ((void*) release != null);
		CApi.position_builder_before (builder, CApi.next_instruction (task));
		CApi.ValueRef[] release_args = {
			captured, frame.scoped_captures.tag (0)
		};
		var stale = CApi.build_call (builder, CApi.global_value_type (release), release, release_args, 2, "invalid.caller.retirement");
		CApi.set_instruction_call_conv (stale, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner handle");
		CApi.erase_instruction (stale);
		artifact.verify_scoped_allocations ();
		CApi.set_operand (task, 0, CApi.const_null (CApi.type_of (captured)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "scoped captured task original factory");
		CApi.set_operand (task, 0, captured);
		artifact.verify_scoped_allocations ();
		artifact.async_frames.remove_index (0);
		refusal_text (() => artifact.verify_scoped_allocations (), "original complete frame inventory");
		artifact.async_frames.add (frame);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void coroutine_captures(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		var frame = artifact.async_frames[0];
		uint retired = 0;
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (var code in new CApi.ValueRef[] { frame.resume, frame.destroy }) {
			for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.value_name (CApi.called_value (instruction), out length) != "astra_context17_release_origin_checked") {
						continue;
					}
					retired++;
					var tag = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (tag), 19, 0));
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "exact allocation tag");
					CApi.set_operand (instruction, 1, tag);
					artifact.verify_scoped_allocations ();
					var original = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (original)));
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "retained scoped owner", "unretired scoped allocation");
					CApi.set_operand (instruction, 0, original);
					artifact.verify_scoped_allocations ();
					CApi.position_builder_before (builder, CApi.next_instruction (instruction));
					CApi.ValueRef[] args = {
						original, tag
					};
					var duplicate = CApi.build_call (builder, CApi.called_function_type (instruction), CApi.called_value (instruction), args, 2, "invalid.duplicate.retirement");
					CApi.set_instruction_call_conv (duplicate, CApi.CallConv.C);
					valid_ir (artifact.module);
					refusal_text (() => artifact.verify_scoped_allocations (), "exact live owner");
					CApi.erase_instruction (duplicate);
					artifact.verify_scoped_allocations ();
				}
			}
		}
		assert (retired == 3);
		var branch = CApi.block_terminator (CApi.first_block (frame.destroy));
		var original = CApi.operand (branch, 0);
		CApi.set_operand (branch, 0, CApi.const_null (CApi.type_of (original)));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (branch, 0, original);
		artifact.verify_scoped_allocations ();
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void coroutine_continuations(LlvmModuleArtifact artifact) throws GLib.Error {
		artifact.verify ();
		uint count = 0;
		var builder = CApi.create_builder_in_context (artifact.context);
		foreach (var frame in artifact.async_frames) {
			frame.verify_continuations ();
			var entries = frame.lifetime_entries ();
			assert (entries.length == 2 && (void*) entries[0] == (void*) CApi.first_block (frame.resume) && (void*) entries[1] == (void*) CApi.first_block (frame.destroy));
			refusal_text (() => frame.seal_effects (), "binds once");
			var other = artifact.async_frames[0] == frame ? artifact.async_frames[1] : artifact.async_frames[0];
			var original_function = frame.resume;
			frame.resume = other.resume;
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "immutable coroutine identity");
			frame.resume = original_function;
			original_function = frame.destroy;
			frame.destroy = other.destroy;
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "immutable coroutine identity");
			frame.destroy = original_function;
			var original_task = frame.task;
			frame.task = other.task;
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "immutable coroutine identity");
			frame.task = original_task;
			var original_cancel = frame.cancel_entry;
			frame.cancel_entry = CApi.first_block (frame.resume);
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "immutable coroutine identity");
			frame.cancel_entry = original_cancel;
			frame.verify_continuations ();
			var drained = frame.drained_children ();
			var drain_branch = CApi.block_terminator (CApi.instruction_parent (drained));
			var drain_condition = CApi.operand (drain_branch, 0);
			var original_parent = CApi.operand (drained, 0);
			CApi.set_operand (drained, 0, CApi.const_null (CApi.type_of (original_parent)));
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "actual child-drain guard");
			CApi.set_operand (drained, 0, original_parent);
			var original_check = CApi.operand (drain_condition, 0);
			CApi.set_operand (drain_condition, 0, CApi.const_int (CApi.type_of (original_check), 1, 0));
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "actual child-drain guard");
			CApi.set_operand (drain_condition, 0, original_check);
			frame.verify_continuations ();
			CApi.ValueRef completed = (CApi.ValueRef) null;
			for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.value_name (CApi.called_value (instruction), out length) == "astra_async_complete" && CApi.const_int_zext (CApi.operand (instruction, 1)) == 5) {
						completed = instruction;
					}
				}
			}
			assert ((void*) completed != null);
			var original_phase = CApi.operand (completed, 1);
			CApi.set_operand (completed, 1, CApi.const_int (CApi.type_of (original_phase), 4, 0));
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "lacks actual completion");
			CApi.set_operand (completed, 1, original_phase);
			original_parent = CApi.operand (completed, 0);
			CApi.set_operand (completed, 0, CApi.const_null (CApi.type_of (original_parent)));
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "lacks actual completion");
			CApi.set_operand (completed, 0, original_parent);
			frame.verify_continuations ();
			var unregistered = CApi.append_basic_block_in_context (artifact.context, frame.resume, "invalid.retained.return");
			CApi.position_builder_at_end (builder, unregistered);
			CApi.build_ret_void (builder);
			valid_ir (artifact.module);
			refusal_text (() => frame.verify_continuations (), "lacks actual completion");
			CApi.delete_basic_block (unregistered);
			frame.verify_continuations ();

			for (var block = CApi.first_block (frame.resume); (void*) block != null; block = CApi.next_block (block)) {
				var end = CApi.block_terminator (block);
				var successors = frame.lifetime_successors (block);
				if (CApi.opcode (end) == CApi.Opcode.RET) {
					assert (successors.length >= 1);
				}
			}
			for (var block = CApi.first_block (frame.destroy); (void*) block != null; block = CApi.next_block (block)) {
				if (CApi.opcode (CApi.block_terminator (block)) == CApi.Opcode.RET) {
					assert (frame.lifetime_successors (block).length == 0);
				}
			}
			for (uint index = 0; index < frame.continuation_count; index++) {
				var edge = frame.continuation (index);
				count++;
				var successors = frame.lifetime_successors (CApi.instruction_parent (edge.suspension_return ()));
				assert (successors.length == 2 && (void*) successors[0] == (void*) edge.next_state () && (void*) successors[1] == (void*) frame.cancel_entry);
				var setter = edge.saved_pc ();
				var operation = edge.admission ();
				var returned = edge.suspension_return ();
				var suspended = CApi.instruction_parent (returned);
				var parent = CApi.instruction_parent (operation);
				var branch = CApi.block_terminator (parent);
				var condition = CApi.operand (branch, 0);
				var original = CApi.operand (setter, 1);
				CApi.set_operand (setter, 1, CApi.const_int (CApi.type_of (original), edge.state () + 1, 0));
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "coroutine");
				CApi.set_operand (setter, 1, original);
				frame.verify_continuations ();
				original = CApi.operand (setter, 0);
				CApi.set_operand (setter, 0, CApi.const_null (CApi.type_of (original)));
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "coroutine");
				CApi.set_operand (setter, 0, original);
				frame.verify_continuations ();
				original = CApi.operand (operation, 0);
				CApi.set_operand (operation, 0, CApi.const_null (CApi.type_of (original)));
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "coroutine");
				CApi.set_operand (operation, 0, original);
				frame.verify_continuations ();
				original = CApi.operand (condition, 0);
				CApi.set_operand (condition, 0, CApi.const_null (CApi.type_of (original)));
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "actual accepted admission");
				CApi.set_operand (condition, 0, original);
				frame.verify_continuations ();
				original = CApi.operand (condition, 1);
				CApi.set_operand (condition, 1, CApi.const_int (CApi.type_of (original), 1, 0));
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "actual accepted admission");
				CApi.set_operand (condition, 1, original);
				frame.verify_continuations ();
				CApi.set_operand (branch, 0, CApi.const_int (CApi.type_of (condition), 1, 0));
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "actual accepted admission");
				CApi.set_operand (branch, 0, condition);
				frame.verify_continuations ();
				CApi.position_builder_before (builder, returned);
				var extra = CApi.build_alloca (builder, CApi.int32_type_in_context (artifact.context), "invalid.suspended.effect");
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "accepted return edge");
				CApi.erase_instruction (extra);
				frame.verify_continuations ();
				var bypass = CApi.append_basic_block_in_context (artifact.context, frame.resume, "invalid.unadmitted.resume");
				CApi.position_builder_at_end (builder, bypass);
				CApi.build_br (builder, suspended);
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "unadmitted predecessor");
				CApi.delete_basic_block (bypass);
				frame.verify_continuations ();
				CApi.position_builder_before (builder, branch);
				CApi.ValueRef[] arguments = {
					CApi.operand (setter, 0), CApi.operand (setter, 1)
				};
				var overwritten = CApi.build_call (builder, CApi.called_function_type (setter), CApi.called_value (setter), arguments, 2, "");
				CApi.set_instruction_call_conv (overwritten, CApi.CallConv.C);
				valid_ir (artifact.module);
				refusal_text (() => frame.verify_continuations (), "overwritten before suspension");
				CApi.erase_instruction (overwritten);
				frame.verify_continuations ();
			}
		}
		assert (count == 3);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void emitted_task_frames(LlvmModuleArtifact artifact, CApi.ValueRef helper) throws GLib.Error {
		artifact.verify ();
		CApi.ValueRef descriptor = (CApi.ValueRef) null;
		CApi.ValueRef task = (CApi.ValueRef) null;
		CApi.ValueRef run = (CApi.ValueRef) null;
		CApi.ValueRef error = (CApi.ValueRef) null;
		for (var block = CApi.first_block (helper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				size_t length;
				string name = CApi.value_name (instruction, out length);
				if (name == "frame.admission.exception") {
					error = instruction;
				}
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				var target = CApi.called_value (instruction);
				if ((void*) CApi.is_function (target) == null) {
					continue;
				}
				string called = CApi.value_name (target, out length);
				if (called == "astra_context17_frame_descriptor") {
					descriptor = instruction;
				}
				if (called == "astra_async_run") {
					run = instruction;
					task = CApi.operand (instruction, 1);
				}
			}
		}
		assert ((void*) descriptor != null && (void*) task != null && (void*) run != null && (void*) error != null);
		var inputs = new CApi.ValueRef[CApi.argument_count (task)];
		for (uint i = 0; i < inputs.length; i++) {
			inputs[i] = CApi.operand (task, i);
		}
		refusal_text (() => artifact.bind_scoped_task_frame (task, CApi.called_value (task), CApi.called_function_type (task), inputs), "binds once before scope sealing");
		var mode = CApi.operand (descriptor, 0);
		CApi.set_operand (descriptor, 0, CApi.const_int (CApi.type_of (mode), 2, 0));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "affine caller-backing descriptor");
		CApi.set_operand (descriptor, 0, mode);
		uint count = CApi.argument_count (task);
		var context = CApi.operand (task, count - 1);
		var pointer = CApi.type_of (context);
		CApi.set_operand (task, count - 1, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "intended receiver/input/success/cleanup channel");
		CApi.set_operand (task, count - 1, context);
		CApi.set_operand (run, 1, CApi.const_null (pointer));
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (run, 1, task);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, run);
		var loaded = CApi.build_load (builder, CApi.int32_type_in_context (artifact.context), task, "unproved.task.header.read");
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "exact task observation operations");
		CApi.erase_instruction (loaded);
		var drop = declaration (artifact, "astra_async_drop", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		CApi.ValueRef[] values = {
			task
		};
		var retired = CApi.build_call (builder, CApi.global_value_type (drop), drop, values, 1, "");
		CApi.set_instruction_call_conv (retired, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "use lacks its exact live owner");
		CApi.erase_instruction (retired);
		assert (CApi.incoming_count (error) == 2);
		var success = CApi.incoming_value (error, 0);
		var wrong = CApi.const_int_to_ptr (CApi.const_int (CApi.int_type_in_context (artifact.context, 64), 1, 0), pointer);
		CApi.set_operand (error, 0, wrong);
		valid_ir (artifact.module);
		refusal_text (() => artifact.verify_scoped_allocations (), "unretired scoped allocation");
		CApi.set_operand (error, 0, success);
		artifact.verify ();
		assert (artifact.scoped_backings.length == 1);
		var backing = artifact.scoped_backings[0].actual_factory ();
		var caller = CApi.block_parent (CApi.instruction_parent (backing));
		CApi.ValueRef use = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) helper) {
					use = instruction;
				}
			}
		}
		assert ((void*) use != null);
		CApi.position_builder_before (builder, use);
		var close = CApi.named_function (artifact.module, "astra_context17_destroy");
		CApi.ValueRef[] controller = {
			backing
		};
		var closed = CApi.build_call (builder, CApi.global_value_type (close), close, controller, 1, "");
		CApi.set_instruction_call_conv (closed, CApi.CallConv.C);
		valid_ir (artifact.module);
		refusal_text (() => artifact.scoped_backings[0].verify (), "unregistered emitted retirement");
		CApi.erase_instruction (closed);
		CApi.dispose_builder (builder);
		artifact.verify ();
	}

	internal static void scoped_task_frames() {
		for (int mode = 58; mode <= 80; mode++) {
			var fixture = new ScopedLlvmFixture (mode);
			fixture.verify_ir ();
			bool rejected = false;
			try {
				LlvmScopedAllocationVerifier.verify (fixture.module, null, null, null, null, null, fixture.task_frames);
			} catch (LlvmError failure) {
				rejected = true;
				Test.message ("mode %d: %s", mode, failure.message);
			}
			assert (rejected == !(mode == 58 || mode == 59 || mode == 69 || mode == 70 || mode == 71 || mode == 75));
		}
	}

	internal static void local_allocations() {
		for (int mode = 0; mode <= 31; mode++) {
			if (mode == 26) {
				continue;
			}
			var fixture = new ScopedLlvmFixture (mode);
			fixture.verify_ir ();
			bool rejected = false;
			try {
				LlvmScopedAllocationVerifier.verify (fixture.module);
			} catch (LlvmError failure) {
				rejected = true;
				Test.message ("mode %d: %s", mode, failure.message);
			}
			assert (rejected == (mode >= 5 && mode != 27 && mode != 28 && mode != 31));
		}
	}

	internal static void artifact(LlvmModuleArtifact artifact) {
		assert (artifact.scoped_backings.length > 0);
		var binding = artifact.scoped_backings[0];
		artifact.scoped_backings.remove_index (0);
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("unregistered emitted scoped factory");
		}
		assert (rejected);
		artifact.scoped_backings.insert (0, binding);
		int storage = binding.storage_ordinal;
		binding.storage_ordinal++;
		rejected = false;
		try {
			binding.verify ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("original storage identity");
		}
		assert (rejected);
		binding.storage_ordinal = storage;
		rejected = false;
		try {
			artifact.bind_scoped_backing (binding);
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("already sealed");
		}
		assert (rejected);
		var factory = binding.actual_factory ();
		var function = CApi.block_parent (CApi.instruction_parent (factory));
		var ends = new GenericArray<void*> ();
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 1 || (void*) CApi.operand (instruction, 0) != (void*) factory) {
					continue;
				}
				size_t length;
				if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_context17_destroy") {
					ends.add ((void*) instruction);
				}
			}
		}
		var replacement = new LlvmScopedBackingBinding (function, storage, ends.length);
		try {
			replacement.acquire (factory);
			foreach (void* end in ends) {
				replacement.retire ((CApi.ValueRef) end);
			}
			replacement.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		artifact.scoped_backings[0] = replacement;
		rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("original admitted backing-loan identity");
		}
		assert (rejected);
		artifact.scoped_backings[0] = binding;
		artifact.scoped_backings.add (binding);
		rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("unique backing-loan authority");
		}
		assert (rejected);
		artifact.scoped_backings.remove_index (artifact.scoped_backings.length - 1);
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		var fixture = new ScopedLlvmFixture (0, artifact);
		fixture.verify_ir ();
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("unregistered emitted scoped factory");
		}
		assert (rejected);
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef retirement = (CApi.ValueRef) null;
		var target = CApi.named_function (artifact.module, "exercise");
		for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t length;
				string name = CApi.value_name (CApi.called_value (instruction), out length);
				if (name == "astra_context17_allocate_mode") {
					allocation = instruction;
				}
				if (name == "astra_context17_release_origin_checked") {
					retirement = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) retirement != null);
		var tag = CApi.operand (retirement, 1);
		CApi.set_operand (retirement, 1, CApi.const_int (CApi.type_of (tag), 78, 0));
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("exact allocation tag");
		}
		assert (rejected);
		CApi.set_operand (retirement, 1, tag);
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		fixture.remove_function ();
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
	}

	internal static void native_borrow(LlvmModuleArtifact artifact) {
		var fixture = new ScopedLlvmFixture (26, artifact);
		fixture.verify_ir ();
		var constructor = CApi.named_function (artifact.module, "astra.ctor.0");
		assert (artifact.scoped_borrow (constructor));
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		bool rejected = false;
		try {
			LlvmScopedAllocationVerifier.verify (artifact.module);
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("ownership effect");
		}
		assert (rejected);
		fixture.remove_function ();
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		var receiver = CApi.get_param (constructor, 0);
		var global = CApi.add_global (artifact.module, CApi.type_of (receiver), "invalid.borrow.capture");
		CApi.set_initializer (global, CApi.const_null (CApi.type_of (receiver)));
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, CApi.first_instruction (CApi.first_block (constructor)));
		var escaped = CApi.build_store (builder, receiver, global);
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_borrows ();
		} catch (LlvmError failure) {
			rejected = true;
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			rejected = true;
		}
		assert (rejected);
		CApi.erase_instruction (escaped);
		CApi.delete_global (global);
		CApi.dispose_builder (builder);
		try {
			artifact.verify_scoped_borrows ();
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
	}

	internal static void forwarded_owner(LlvmModuleArtifact artifact, CApi.ValueRef target) {
		assert ((void*) target != null && CApi.count_params (target) == 2);
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (caller)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (CApi.called_value (instruction), out length);
			if (name == "astra_context17_allocate_mode") {
				allocation = instruction;
			}
			if (name == "astra_context17_release_origin_checked") {
				release = instruction;
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, release);
		var marker = CApi.const_int (CApi.int32_type_in_context (artifact.context), 7, 0);
		CApi.ValueRef[] arguments = {
			marker, allocation
		};
		var returned = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, 2, "returned.owner");
		CApi.set_instruction_call_conv (returned, LlvmLowering.CALL_CONVENTION);
		CApi.set_operand (release, 0, returned);
		CApi.ValueRef tag;
		try {
			tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 1, tag);
		CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (tag), 1, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0));
		fixture.verify_ir ();
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		CApi.position_builder_before (builder, release);
		CApi.ValueRef[] forwarded = {
			marker, returned
		};
		var again = CApi.build_call (builder, CApi.global_value_type (target), target, forwarded, 2, "returned.again");
		CApi.set_instruction_call_conv (again, LlvmLowering.CALL_CONVENTION);
		CApi.set_operand (release, 0, again);
		fixture.verify_ir ();
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		foreach (var stale_owner in new CApi.ValueRef[] { allocation, returned }) {
			CApi.position_builder_before (builder, release);
			var stale = CApi.build_load (builder, CApi.int_type_in_context (artifact.context, 8), stale_owner, "stale.forwarded.owner");
			fixture.verify_ir ();
			bool rejected = false;
			try {
				artifact.verify_scoped_allocations ();
			} catch (LlvmError failure) {
				rejected = failure.message.contains ("exact live owner handle");
			}
			assert (rejected);
			CApi.erase_instruction (stale);
		}
		CApi.set_operand (release, 0, CApi.const_null (CApi.type_of (again)));
		fixture.verify_ir ();
		bool rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("context retired before its derived allocation");
		}
		assert (rejected);
		CApi.set_operand (release, 0, again);
		CApi.ValueRef end = (CApi.ValueRef) null;
		for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
			var terminator = CApi.block_terminator (block);
			if (CApi.opcode (terminator) == CApi.Opcode.RET && CApi.operand_count (terminator) == 1 && (void*) CApi.is_constant_pointer_null (CApi.operand (terminator, 0)) == null) {
				assert ((void*) end == null);
				end = terminator;
			}
		}
		assert ((void*) end != null);
		var original = CApi.operand (end, 0);
		CApi.set_operand (end, 0, CApi.const_null (CApi.type_of (original)));
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("return lost its exact live input allocation");
		}
		assert (rejected);
		rejected = false;
		try {
			artifact.verify_scoped_owned_inputs ();
		} catch (LlvmError failure) {
			rejected = true;
		}
		assert (rejected);
		CApi.set_operand (end, 0, original);
		CApi.set_instruction_call_conv (again, CApi.CallConv.C);
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("type, extent, alignment");
		}
		assert (rejected);
		CApi.set_instruction_call_conv (again, LlvmLowering.CALL_CONVENTION);
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		var nullable = new ScopedLlvmFixture (1, artifact);
		caller = CApi.named_function (artifact.module, "exercise");
		allocation = (CApi.ValueRef) null;
		release = (CApi.ValueRef) null;
		CApi.ValueRef condition = (CApi.ValueRef) null;
		for (var block = CApi.first_block (caller); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.ICMP) {
					condition = instruction;
				}
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t length;
				string name = CApi.value_name (CApi.called_value (instruction), out length);
				if (name == "astra_context17_allocate_mode") {
					allocation = instruction;
				}
				if (name == "astra_context17_release_origin_checked") {
					release = instruction;
				}
			}
		}
		assert ((void*) allocation != null && (void*) release != null && (void*) condition != null);
		builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, condition);
		CApi.ValueRef[] maybe = {
			marker, allocation
		};
		var result = CApi.build_call (builder, CApi.global_value_type (target), target, maybe, 2, "nullable.returned");
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		CApi.set_operand (condition, 0, result);
		CApi.set_operand (release, 0, result);
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (release, 1, tag);
		CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (tag), 1, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0));
		nullable.verify_ir ();
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		CApi.dispose_builder (builder);
		nullable.remove_function ();
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
	}

	internal static void owned_inputs(LlvmModuleArtifact artifact) {
		CApi.ValueRef target = (CApi.ValueRef) null;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			if (artifact.has_scoped_owned_inputs (function)) {
				assert ((void*) target == null);
				target = function;
			}
		}
		assert ((void*) target != null && CApi.count_params (target) == 2);
		try {
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		var fixture = new ScopedLlvmFixture (4, artifact);
		var caller = CApi.named_function (artifact.module, "exercise");
		CApi.ValueRef allocation = (CApi.ValueRef) null;
		CApi.ValueRef release = (CApi.ValueRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (caller)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (CApi.called_value (instruction), out length);
			if (name == "astra_context17_allocate_mode") {
				allocation = instruction;
			}
			if (name == "astra_context17_release_origin_checked") {
				release = instruction;
			}
		}
		assert ((void*) allocation != null && (void*) release != null);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, release);
		CApi.ValueRef[] arguments = {
			allocation, CApi.const_null (CApi.type_of (allocation))
		};
		var transferred = CApi.build_call (builder, CApi.global_value_type (target), target, arguments, 2, "consumed");
		CApi.set_instruction_call_conv (transferred, LlvmLowering.CALL_CONVENTION);
		CApi.erase_instruction (release);
		CApi.ValueRef tag;
		try {
			tag = new LlvmPolicyAllocation (artifact).tag ("ScopedLeaf", "object");
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (tag), 1, 0));
		var alignment = CApi.const_int (CApi.int32_type_in_context (artifact.context), 1, 0);
		CApi.set_operand (allocation, 3, alignment);
		fixture.verify_ir ();
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		bool rejected = false;
		try {
			LlvmScopedAllocationVerifier.verify (artifact.module);
		} catch (LlvmError failure) {
			rejected = true;
		}
		assert (rejected);
		CApi.set_operand (transferred, 1, allocation);
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("duplicates one allocation");
		}
		assert (rejected);
		CApi.set_operand (transferred, 1, arguments[1]);
		CApi.set_operand (allocation, 4, CApi.const_int (CApi.type_of (tag), 77, 0));
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("type, extent, alignment, tag or transfer channel");
		}
		assert (rejected);
		CApi.set_operand (allocation, 4, tag);
		CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (tag), 37, 0));
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("extent, alignment");
		}
		assert (rejected);
		CApi.set_operand (allocation, 2, CApi.const_int (CApi.type_of (tag), 1, 0));
		CApi.set_operand (allocation, 3, CApi.const_int (CApi.type_of (alignment), 8, 0));
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("extent, alignment");
		}
		assert (rejected);
		CApi.set_operand (allocation, 3, alignment);
		CApi.position_builder_before (builder, CApi.next_instruction (transferred));
		var stale = CApi.build_load (builder, CApi.int32_type_in_context (artifact.context), allocation, "stale.owner");
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("exact live owner");
		}
		assert (rejected);
		CApi.erase_instruction (stale);
		CApi.set_instruction_call_conv (transferred, CApi.CallConv.C);
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("type, extent, alignment, tag or transfer channel");
		}
		assert (rejected);
		CApi.set_instruction_call_conv (transferred, LlvmLowering.CALL_CONVENTION);
		var branch = CApi.block_terminator (CApi.first_block (target));
		assert (CApi.opcode (branch) == CApi.Opcode.COND_BR && CApi.successor_count (branch) == 2);
		var condition = CApi.operand (branch, 0);
		assert (CApi.opcode (condition) == CApi.Opcode.ICMP && (CApi.predicate (condition) == CApi.IntPredicate.EQ || CApi.predicate (condition) == CApi.IntPredicate.NE));
		CApi.set_operand (branch, 0, CApi.const_int (CApi.type_of (condition), CApi.predicate (condition) == CApi.IntPredicate.EQ ? 1 : 0, 0));
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("unretired scoped allocation");
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		CApi.set_operand (branch, 0, condition);
		CApi.ValueRef cleanup = (CApi.ValueRef) null;
		for (var block = CApi.first_block (target); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t length;
				if (CApi.value_name (CApi.called_value (instruction), out length) == "astra_context17_release_origin_checked") {
					cleanup = instruction;
				}
			}
		}
		assert ((void*) cleanup != null);
		var original = CApi.operand (cleanup, 1);
		CApi.set_operand (cleanup, 1, CApi.const_int (CApi.type_of (original), 77, 0));
		fixture.verify_ir ();
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("exact allocation tag");
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		rejected = false;
		try {
			artifact.verify_scoped_owned_inputs ();
		} catch (LlvmError failure) {
			rejected = true;
		}
		assert (rejected);
		CApi.set_operand (cleanup, 1, original);
		CApi.dispose_builder (builder);
		fixture.remove_function ();
		try {
			artifact.verify_scoped_allocations ();
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
	}

	internal static void context_inputs(LlvmModuleArtifact artifact) {
		CApi.ValueRef target = (CApi.ValueRef) null;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			if (artifact.has_scoped_context_inputs (function)) {
				assert ((void*) target == null);
				target = function;
			}
		}
		assert ((void*) target != null && CApi.count_params (target) == 1);
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var word = CApi.int32_type_in_context (artifact.context);
		var size = CApi.int_type_in_context (artifact.context, 64);
		var allocate = declaration (artifact, "astra_context17_allocate_mode", pointer, new CApi.TypeRef[] { pointer, size, size, word, size, word });
		var release = declaration (artifact, "astra_context17_release_origin_checked", word, new CApi.TypeRef[] { pointer, size });
		var destroy = CApi.named_function (artifact.module, "astra_context17_destroy");
		var parameter = CApi.get_param (target, 0);
		var end = CApi.block_terminator (CApi.first_block (target));
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (builder, end);
		var tag = CApi.const_int (size, 77, 0);
		CApi.ValueRef[] arguments = {
			parameter, CApi.const_int (size, 1, 0), CApi.const_int (size, 37, 0), CApi.const_int (word, 8, 0), tag, CApi.const_int (word, 3, 0)
		};
		var allocation = CApi.build_call (builder, CApi.global_value_type (allocate), allocate, arguments, 6, "borrowed.allocation");
		CApi.set_instruction_call_conv (allocation, CApi.CallConv.C);
		CApi.ValueRef[] retired = {
			allocation, tag
		};
		var retirement = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "borrowed.retirement");
		CApi.set_instruction_call_conv (retirement, CApi.CallConv.C);
		valid_ir (artifact.module);
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		bool rejected = false;
		try {
			LlvmScopedAllocationVerifier.verify (artifact.module);
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("context-input contract");
		}
		assert (rejected);
		rejected = false;
		try {
			artifact.verify_scoped_context_inputs ();
		} catch (LlvmError failure) {
			rejected = true;
		}
		assert (rejected);
		CApi.erase_instruction (retirement);
		valid_ir (artifact.module);
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("unretired scoped allocation");
		}
		assert (rejected);
		CApi.position_builder_before (builder, end);
		retirement = CApi.build_call (builder, CApi.global_value_type (release), release, retired, 2, "borrowed.retirement");
		CApi.set_instruction_call_conv (retirement, CApi.CallConv.C);
		CApi.set_operand (retirement, 1, CApi.const_int (size, 78, 0));
		valid_ir (artifact.module);
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("exact allocation tag");
		}
		assert (rejected);
		CApi.set_operand (retirement, 1, tag);
		CApi.position_builder_before (builder, end);
		CApi.ValueRef[] context = {
			parameter
		};
		var close = CApi.build_call (builder, CApi.global_value_type (destroy), destroy, context, 1, "");
		CApi.set_instruction_call_conv (close, CApi.CallConv.C);
		valid_ir (artifact.module);
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("cannot be retired by its callee");
		}
		assert (rejected);
		CApi.erase_instruction (close);
		CApi.position_builder_before (builder, end);
		var slot = CApi.build_alloca (builder, pointer, "invalid.borrowed.alias");
		var stored = CApi.build_store (builder, parameter, slot);
		valid_ir (artifact.module);
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("emitted alias");
		}
		assert (rejected);
		CApi.erase_instruction (stored);
		CApi.erase_instruction (slot);
		CApi.position_builder_before (builder, end);
		var opaque = declaration (artifact, "invalid.borrowed.opaque", word, new CApi.TypeRef[] { pointer });
		var escaped = CApi.build_call (builder, CApi.global_value_type (opaque), opaque, context, 1, "opaque.retire");
		CApi.set_instruction_call_conv (escaped, CApi.CallConv.C);
		valid_ir (artifact.module);
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = true;
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		CApi.erase_instruction (escaped);
		CApi.set_operand (allocation, 5, CApi.const_int (word, 2, 0));
		valid_ir (artifact.module);
		rejected = false;
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			rejected = failure.message.contains ("exact affine mode");
		}
		assert (rejected);
		CApi.set_operand (allocation, 5, CApi.const_int (word, 3, 0));
		try {
			artifact.verify_scoped_allocations ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
		CApi.erase_instruction (retirement);
		CApi.erase_instruction (allocation);
		CApi.dispose_builder (builder);
		try {
			artifact.verify_scoped_context_inputs ();
			artifact.verify ();
		} catch (LlvmError failure) {
			error ("%s", failure.message);
		}
	}

}
}
