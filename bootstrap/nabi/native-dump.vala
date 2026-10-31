// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.NativeAbi {
// Verified internal inspection format, not a serialization/linker contract.
public class NativeAbiDump : Object {
	private StringBuilder output = new StringBuilder ();

	public static string format(NativeAbiProgram program) throws NativeAbiError {
		NativeAbiVerifier.verify (program);
		string header = "(native-abi " + program.abi_version.spelling ();
		if (program.functions.length == 0 && program.sum_values.length == 0 && program.com_imports.length == 0 && program.gobject_imports.length == 0 && program.c_bool_policies.length == 0) {
			return header + ")\n";
		}
		var dump = new NativeAbiDump ();
		dump.line (0, header);
		foreach (string policy in program.c_bool_policies) {
			dump.line (1, "(C99-bool " + policy + ")");
		}
		foreach (var policy in program.pod_layouts) {
			if (policy.is_union) {
				dump.line (1, policy.dump ());
			}
		}
		foreach (var root in program.class_imports) {
			dump.line (1, "(" + (root.com == null ? "CImport" : "COMImport") + " declarations-v1 " + root.api.identity () + (root.com == null ? "" : " " + root.com.identity ()) + ")");
		}
		foreach (string identity in program.gobject_imports) {
			dump.line (1, "(GObjectImport typed-C-bridge origin=" + identity + ")");
		}
		foreach (var contract in program.com_imports) {
			dump.line (1, "(" + contract.identity () + ")");
		}
		foreach (var plan in program.function_values) {
			dump.line (1, "(function-value-call caller=%d block=%d instruction=%d %s)".printf (plan.caller, plan.block, plan.instruction, plan.signature.spelling ()));
		}
		foreach (var plan in program.shared_operations) {
			dump.line (1, "(shared-lifecycle action=%d caller=%d block=%d instruction=%d %s)".printf (plan.action, plan.caller, plan.block, plan.instruction, plan.handle.spelling ()));
		}
		foreach (var plan in program.actor_operations) {
			dump.line (1, "(actor-operation action=%d caller=%d block=%d instruction=%d error-class=%d %s)".printf ((int) plan.action, plan.caller, plan.block, plan.instruction, plan.error_class, plan.sender.spelling ()));
		}
		foreach (var plan in program.retained_operations) {
			dump.line (1, "(retained-callback action=%d caller=%d block=%d instruction=%d %s)".printf (plan.action, plan.caller, plan.block, plan.instruction, plan.handle.spelling ()));
		}
		foreach (var plan in program.callback_views) {
			dump.line (1, "(captured-callback-view " + plan.identity () + ")");
		}
		foreach (var plan in program.closures) {
			dump.line (1, "(closure-%s caller=%d block=%d instruction=%d target=%d destructor=%d %s)".printf (plan.binding ? "bind" : "invoke", plan.caller, plan.block, plan.instruction, plan.target, plan.destructor, plan.handle.spelling () + (plan.actor_binding == null ? "" : " " + plan.actor_binding.dump ())));
		}
		foreach (var owner in program.classes) {
			if (owner.allocation_policy != null) {
				dump.line (1, owner.allocation_policy.dump ());
			}
		}
		foreach (var owner in program.classes) {
			if (owner.foreign_export != null) {
				dump.line (1, owner.foreign_export.dump ());
			}
		}
		foreach (var owner in program.classes) {
			if (owner.generic_instance != null) {
				var key = owner.generic_instance;
				if (key.declared_structure != null) {
					dump.line (1, "(generic-class-plan #%d \"%s\" (origin \"%s\") (type-arguments %d) (fields %u))".printf (owner.ordinal, owner.name, key.definition.name, key.declared_structure.argument_count, owner.fields.length));
					continue;
				}
				string argument = key.record_argument != null ? "record:%s".printf (key.record_argument.struct_name) : key.resource_argument == null ? "class#%d".printf (key.argument_ordinal) : "resource:%s".printf (key.resource_argument.type_name);
				dump.line (1, "(generic-class-plan #%d \"%s\" (origin \"%s\") (exact-argument %s) (field \"%s\" %s))".printf (owner.ordinal, owner.name, key.definition.name, argument, owner.fields[0].name, owner.fields[0].storage_type.spelling ()));
			}
		}
		foreach (var function in program.functions) {
			var method = function.generic_method_instance;
			if (method != null) {
				dump.line (1, "(generic-method-plan class#%d member#%d target#%d %s arguments=%d)".printf (method.class_ordinal, method.member, method.target_ordinal, method.name, method.argument_count));
			}
		}
		foreach (var plan in program.sum_values) {
			dump.line (1, "(sum-value-plan %s tag=I32 max-active-payload target-layout stack-copy".printf (plan.identity.name));
			foreach (var variant in plan.variants) {
				dump.line (2, "(variant #%d %s".printf (variant.identity.ordinal, variant.identity.name));
				foreach (var field in variant.fields) {
					dump.line (3, "(payload #%d %s %s)".printf (field.identity.ordinal, field.identity.name, field.record_value != null ? "OWNED_RECORD(" + field.record_value.struct_name + ")" : field.scalar_owner != null ? "OWNED_PTR(" + field.scalar_owner.type_name + "," + (field.scalar_owner.class_ordinal < 0 ? field.scalar_owner.cleanup_symbol : "class#%d".printf (field.scalar_owner.class_ordinal)) + ")" : field.sum != null ? "SUM(" + field.sum.identity.name + ")" : field.record != null ? field.record.spelling () : field.buffer != null ? "OWNED_BUFFER(PTR,I32," + field.buffer.element_spelling () + ")" : field.leaf.spelling ()));
				}
				dump.line (2, ")");
			}
			dump.line (1, ")");
		}
		foreach (var record in program.record_elements) {
			dump.line (1, "(record-element #%d \"%s\" natural-storage structural-zero trivial-destruction".printf (record.struct_ordinal, record.struct_name.escape ()));
			foreach (var field in record.fields) {
				dump.line (2, "(field #%d \"%s\" %s)".printf (field.ordinal, field.name.escape (), field.record == null ? field.leaf.spelling () : field.record.spelling ()));
			}
			dump.line (1, ")");
		}
		foreach (var plan in program.struct_values) {
			dump.line (1, "(struct-value-plan #%d \"%s\" (carrier %s)".printf (plan.struct_ordinal, plan.struct_name.escape (), plan.result_carrier == NativeStructResultCarrier.SINGLE_LEAF ? "single-leaf" : "leaf-aggregate"));
			if (plan.mode == NativeStructValueMode.MOVE_VALUE) {
				dump.line (2, "(mode MOVE_VALUE)");
			}
			for (int i = 0; i < plan.leaves.length; i++) {
				dump.line (2, "(leaf #%d (field %s) %s)".printf (i, plan.leaves[i].field_path, plan.leaves[i].abi_type.spelling ()));
			}
			foreach (var owner in plan.ownership) {
				dump.line (2, "(owner path=%s rank=%d type=%s cleanup=%s class=%d)".printf (owner.field_path, owner.acquisition_rank, owner.type_name, owner.cleanup_symbol, owner.cleanup_class_ordinal));
			}
			dump.line (1, ")");
		}
		for (int i = 0; i < program.functions.length; i++) {
			dump.write_function (program.functions[i]);
		}
		foreach (var owner in program.classes) {
			if (owner.is_interface) {
				dump.line (1, "(interface-contract class=#%d name=\"%s\" abstract borrowed-noescape slots=%u)".printf (owner.ordinal, owner.name.escape (), owner.virtual_targets.length));
			}
			foreach (var cache in owner.lazy_caches) {
				if (cache.is_owned) {
					dump.line (1, "(lazy-cache v2 class=#%d property=#%d getter=#%d factory=#%d owned-class=#%d rank=%d name=\"%s\" state-member=%d value-member=%d value=PTR receiver-borrow owned-factory empty=0 evaluating=1 ready=2 first-success-after-cleanup reverse-ready-retirement)".printf (cache.class_ordinal, cache.property_ordinal, cache.getter_ordinal, cache.factory_ordinal, cache.owned_class_ordinal, cache.cache_ordinal, cache.name.escape (), cache.state_member, cache.value_member));
				} else {
					dump.line (1, "(lazy-cache v1 class=#%d property=#%d getter=#%d rank=%d name=\"%s\" state-member=%d value-member=%d value=%s empty=0 evaluating=1 ready=2 first-success-after-cleanup)".printf (cache.class_ordinal, cache.property_ordinal, cache.getter_ordinal, cache.cache_ordinal, cache.name.escape (), cache.state_member, cache.value_member, cache.value_type.spelling ()));
				}
			}
		}
		foreach (var frame in program.async_frames) {
			for (uint w = 0; w < frame.wait_count; w++) {
				var wait = frame.wait (w);
				if (wait.bridge_definition >= 0) {
					dump.line (1, "(worker-bridge function=%d block=%d position=%d pool-definition=%d pool-owner=%d target-provider=%d submission-through-observation)".printf (frame.function_ordinal, wait.block, wait.position, wait.bridge_definition, wait.bridge_owner, (int) wait.target_provider));
				}
			}
			dump.line (1, "(native-task-frame #%d capability=%s (source \"%s\" %d %d) (success %s)".printf (frame.function_ordinal, NativeAsyncFramePlan.CAPABILITY, frame.declaration.file.path.escape (), frame.declaration.start, frame.declaration.end, frame.result == null ? "void" : frame.result.spelling ()));
			if (frame.provider == Astra.Source.AsyncProviderKind.LINUX_IO_URING) {
				dump.line (2, "(provider capability=%s units=milliseconds)".printf (NativeAsyncFramePlan.LINUX_CAPABILITY));
			}
			for (uint f = 0; f < frame.field_count; f++) {
				var field = frame.field (f);
				dump.line (2, "(field #%u definition=%d block=%d position=%d %s)".printf (f, field.definition, field.block, field.position, field.abi_type.spelling ()));
			}
			for (uint s = 0; s < frame.state_count; s++) {
				var state = frame.state (s);
				if (state.payload_definition >= 0) {
					dump.line (2, "(linux-payload-hold pc=%d definition=%d owner=%d observed-target-and-cancel-release)".printf (state.pc, state.payload_definition, state.payload_owner));
				}
				var initialized = new StringBuilder ();
				for (uint f = 0; f < state.initialized_count; f++) {
					initialized.append_printf (" %d", state.initialized_field (f));
				}
				dump.line (2, "(resume pc=%d block=%d position=%d initialized%s)".printf (state.pc, state.block, state.position, initialized.str));
			}
			for (uint o = 0; o < frame.owner_count; o++) {
				var owner = frame.owner (o);
				dump.line (2, "(owner #%d source=%d class=%d catch=%s)".printf (owner.ordinal, owner.source_ordinal, owner.class_ordinal, owner.catch_owner.to_string ()));
			}
			for (uint b = 0; b < frame.buffer_count; b++) {
				var buffer = frame.buffer (b);
				dump.line (2, "(buffer #%d owner=%d element=%s)".printf (buffer.ordinal, buffer.owner_ordinal, buffer.element.spelling ()));
			}
			dump.line (1, ")");
		}
		dump.line (0, ")");
		return dump.output.str;
	}

	private void line(int indentation, string text) {
		for (int i = 0; i < indentation; i++) {
			output.append_c ('\t');
		}
		output.append (text);
		output.append_c ('\n');
	}

	private void write_function(NativeFunction function) {
		if (function.async_callable != null) {
			line (1, "(async-callable #%d imported=%s %s)".printf (function.ordinal, function.async_callable.imported.to_string (), function.async_callable.contract ()));
		}
		foreach (var memory in function.vector_memory) {
			line (1, "(vector-memory shape=%s alignment=%u bounded noescape)".printf (memory.vector_type.spelling (), memory.alignment));
		}
		if (function.floating_policy != 0) {
			line (1, "(floating-policy permissions=%u checked-domain=bounded)".printf (function.floating_policy));
		}
		line (1, "(function #%d \"%s\"".printf (function.ordinal, function.name.escape ()));
		foreach (var owner in function.record_owners) {
			line (2, "(record-owner source=%d type=\"%s\" reverse-written-prefix".printf (owner.source_ordinal, owner.record_name.escape ()));
			foreach (var field in owner.obligations) {
				line (3, "(resource-field #%s rank=%d type=\"%s\" cleanup=\"%s\")".printf (field.field_path, field.acquisition_rank, field.type_name.escape (), field.buffer_cleanup != null ? "buffer-ptr-i32<%s>".printf (field.buffer_cleanup.element_spelling ()) : field.cleanup_class_ordinal < 0 ? field.cleanup_symbol.escape () : "heap-class#%d".printf (field.cleanup_class_ordinal)));
			}
			line (2, ")");
		}
		if (function.receiver_borrow) {
			line (2, "(result-provenance receiver-borrow noescape)");
		}
		if (function.utf8_factory) {
			line (2, "(utf8-message-factory validate-before-copy checked-error unique-heap-result)");
		}
		line (2, "(linkage native-internal)");
		line (2, "(signature");
		var signature = function.signature;
		foreach (var group in signature.struct_parameters) {
			line (3, "(struct-parameter #%d (type #%d) (channels %d %u))".printf (group.source_ordinal, group.value_plan.struct_ordinal, group.first_leaf, group.value_plan.leaves.length));
		}
		foreach (var group in signature.buffer_parameters) {
			line (3, "(buffer-parameter #%d (channels %d 2) PTR I32 owned-transfer static-buffer-deallocate element=%s)".printf (group.source_ordinal, group.first_leaf, group.value_plan.element_spelling ()));
		}
		if (signature.sum_result != null) {
			line (3, "(sum-result-storage PTR first caller-provided %s)".printf (signature.sum_result.identity.name));
		}
		if (signature.object_result != null) {
			line (3, "(result-storage PTR first caller-provided)");
		}
		if (function.kind == NativeCallableKind.PROPERTY_GETTER || function.kind == NativeCallableKind.PROPERTY_SETTER) {
			line (3, "(receiver PTR (%s #%d) (property #%d) (%s) first)".printf (function.declaring_type_is_class ? "class" : "struct", function.declaring_type_ordinal, function.property_ordinal, function.kind == NativeCallableKind.PROPERTY_GETTER ? "getter" : "setter"));
		} else if (function.kind == NativeCallableKind.CONSTRUCTOR || function.kind == NativeCallableKind.DESTRUCTOR) {
			line (3, "(receiver PTR (class #%d) (%s) first)".printf (function.declaring_type_ordinal, function.kind == NativeCallableKind.CONSTRUCTOR ? "constructor initializing" : "destructor live"));
		} else if (signature.receiver != null) {
			line (3, "(receiver %s (%s #%d) (method #%d) %s)".printf (signature.receiver.spelling (), function.declaring_type_is_class ? "class" : "struct", function.declaring_type_ordinal, function.method_ordinal, signature.object_result == null ? "first" : "after-result-storage"));
		}
		if (signature.parameters.length == 0) {
			line (3, "(parameters)");
		} else {
			line (3, "(parameters");
			for (int i = 0; i < signature.parameters.length; i++) {
				var parameter = signature.parameters[i];
				line (4, "(parameter #%d %s)".printf (parameter.ordinal, parameter.abi_type.spelling ()));
				if (parameter.generic_borrow_class >= 0) {
					line (4, "(borrowed-generic-class #%d exact-instance call-scoped-noescape)".printf (parameter.generic_borrow_class));
				}
			}
			line (3, ")");
		}
		if (signature.buffer_result != null) {
			line (3, "(buffer-result PTR I32 owned-transfer static-buffer-deallocate element=%s (carrier backend-pair))".printf (signature.buffer_result.element_spelling ()));
		} else if (signature.struct_result != null) {
			line (3, "(struct-result (type #%d) (carrier %s)".printf (signature.struct_result.struct_ordinal, signature.struct_result.result_carrier == NativeStructResultCarrier.SINGLE_LEAF ? "single-leaf" : "leaf-aggregate"));
			if (signature.struct_result_mode == NativeStructValueMode.BORROW_VALUE) {
				line (4, "(transport BORROW_VALUE receiver-borrow noescape)");
			}
			foreach (var leaf in signature.struct_result.leaves) {
				line (4, "(result-leaf %s)".printf (leaf.abi_type.spelling ()));
			}
			line (3, ")");
		} else {
			line (3, "(result %s)".printf (signature.result == null ? "void" : signature.result.abi_type.spelling ()));
		}
		line (2, ")");
		line (1, ")");
	}
}
}
