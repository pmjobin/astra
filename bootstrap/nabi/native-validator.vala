// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;

namespace Astra.NativeAbi {
// Construction-time compatibility checks, separate from model verification.
// Only SsaCallInstruction is native; SsaCCallInstruction never enters NABI.
// Inputs are verified SSA/NABI and the builder's exact temporary identity map.
internal class NativeAbiValidator : Object {
	// Projection belongs to the SSA-to-physical boundary; detached plans
	// retain only primitive tokens and never depend on an SSA definition.
	internal static string scoped_backing_value_identity(SsaValue value) {
		var definition = value as SsaDefinition;
		var constant = value as SsaIntegerConstant;
		return definition != null ? "ssa=%d".printf (definition.ordinal) : constant != null ? "int=%s".printf (constant.value.bits.to_string ()) : "invalid";
	}
	private static void validate_callable_record_result(SsaStructCallResults? group, NativeStructValuePlan? plan) throws NativeAbiError {
		if (group == null ? plan != null : plan == null || group.shape.semantic_type.display_name () != plan.struct_name || NativeAbiBuilder.record_mode (group.shape.mode) != plan.mode) {
			fail ("native callable record result", "complete result group differs from its native declaration");
		}
		if (group == null) {
			return;
		}
		var expected = new NativeCallableRecordResult (group.shape.semantic_type.display_name (), NativeTypeMapper.map_record_leaves (group.shape), NativeAbiBuilder.record_mode (group.shape.mode));
		if (group.leaves.length != group.shape.leaves.length || !expected.matches (plan.struct_name, plan.mode, plan.leaves)) {
			fail ("native callable record result", "ordered result leaves differ from exact native declaration");
		}
		for (int l = 0; l < group.leaves.length; l++) {
			if (group.leaves[l].semantic_type != group.shape.leaves[l].semantic_type) {
				fail ("native callable record result", "result definition changed its exact leaf type");
			}
		}
	}

	private static void validate_callable_result(SsaCallableInvocation call, NativeScalarOwner? owner) throws NativeAbiError {
		var cleanup = call.result_cleanup ();
		var value = call.owned_result_value ();
		if (cleanup == null ? owner != null : owner == null || value == null || owner.type_name != value.semantic_type.display_name () || owner.cleanup_symbol != cleanup.external_symbol || owner.class_ordinal != (cleanup.is_heap_object ? cleanup.object_class.ordinal : -1)) {
			fail ("native callable result", "owned result plan differs from its exact SSA acquisition and cleanup");
		}
	}

	private static void fail(string path, string message) throws NativeAbiError {
		throw new NativeAbiError.INCOMPATIBLE_CALL ("internal native ABI compatibility error at %s: %s", path, message);
	}

	private static void validate_callable_transfers(SsaCallableInvocation invocation, GenericArray<NativeCallableOwnedArgument> carried, string path) throws NativeAbiError {
		if (invocation.owned_arguments.length != carried.length) {
			fail (path, "owned argument inventory differs from its original SSA channels");
		}
		for (int p = 0; p < carried.length; p++) {
			var original = invocation.owned_arguments[p];
			var transfer = carried[p];
			if (original.ordinal != transfer.ordinal || original.value.semantic_type.display_name () != transfer.resource.type_name || original.cleanup.external_symbol != transfer.resource.cleanup_symbol || (original.cleanup.is_heap_object ? original.cleanup.object_class.ordinal : -1) != transfer.resource.class_ordinal || original.source_ordinal != transfer.source_ordinal || (original.value is SsaNullPointerConstant) != transfer.null_argument || (original.source_after_commit != null) != transfer.committed_null) {
				fail (path, "owned argument lost original nominal destructor or source commit correspondence");
			}
		}
	}

	private static void validate_struct_leaves(Semantic.StructValueShape shape, NativeStructValuePlan plan, string path) throws NativeAbiError {
		if (plan.mode != (shape.mode == Semantic.StructValueMode.COPY_VALUE ? NativeStructValueMode.COPY_VALUE : NativeStructValueMode.MOVE_VALUE)) {
			fail (path, "struct boundary changed its original copy/move authority");
		}
		if (shape.leaves.length != plan.leaves.length || plan.result_carrier != (shape.leaves.length == 1 ? NativeStructResultCarrier.SINGLE_LEAF : NativeStructResultCarrier.LEAF_AGGREGATE)) {
			fail (path, "struct result carrier or leaf count mismatch");
		}
		for (int i = 0; i < shape.leaves.length; i++) {
			var leaf = shape.leaves[i];
			NativeAbiType expected;
			if (leaf.semantic_type is Semantic.ClassType) {
				int matches = 0;
				foreach (var owner in plan.ownership) {
					if (owner.field_path == leaf.spelling () && owner.type_name == leaf.semantic_type.display_name () && owner.cleanup_class_ordinal >= 0 && owner.cleanup_symbol == "" && owner.buffer_cleanup == null) {
						matches++;
					}
				}
				if (shape.mode == Semantic.StructValueMode.COPY_VALUE || matches != 1) {
					fail (path, "record Class channel requires its exact original heap cleanup");
				}
				expected = new NativeScalarAbiType (NativeScalarType.PTR);
			} else {
				expected = NativeTypeMapper.map_type (leaf.semantic_type);
			}
			var buffer = leaf as Semantic.StructBufferLeafPath;
			if (leaf.spelling () != plan.leaves[i].field_path || leaf.storage_path ().spelling () != plan.leaves[i].storage_path || plan.leaves[i].buffer_component != (buffer == null ? -1 : buffer.component) || !expected.same_type (plan.leaves[i].abi_type)) {
				fail (path, "struct leaf path, order or physical channel mismatch");
			}
		}
	}

	internal static void validate_struct_association(Semantic.StructValueShape? shape, NativeStructValuePlan? plan, SsaProgram source, string path) throws NativeAbiError {
		if ((shape == null) != (plan == null)) {
			fail (path, "struct boundary lost its physical grouping plan");
		}
		if (shape == null) {
			return;
		}
		if (plan.struct_ordinal < 0 || plan.struct_ordinal >= source.structs.length || source.structs[plan.struct_ordinal].semantic_type != shape.semantic_type || source.structs[plan.struct_ordinal].name != plan.struct_name) {
			fail (path, "struct plan must associate the exact source StructType declaration");
		}
		var foreign_record = SsaForeignApi.record (source, shape.semantic_type);
		if (foreign_record == null ? plan.foreign_record != null : plan.foreign_record == null || !foreign_record.equal (plan.foreign_record)) {
			fail (path, "foreign POD field declaration differs from actual SSA scalar fields");
		}
		validate_struct_leaves (shape, plan, path);
		var expected = NativeAbiBuilder.struct_value_plan (NativeAbiBuilder.record_storage_shape (shape.semantic_type, source), source);
		if (plan.ownership_field_count != expected.ownership_field_count || plan.ownership.length != expected.ownership.length) {
			fail (path, "MOVE_VALUE must retain every original field cleanup obligation");
		}
		for (int i = 0; i < expected.ownership.length; i++) {
			var field = plan.ownership[i];
			var original = expected.ownership[i];
			if (field.compare_path (original) != 0 || field.type_name != original.type_name || field.cleanup_symbol != original.cleanup_symbol || field.cleanup_class_ordinal != original.cleanup_class_ordinal || (field.buffer_cleanup == null) != (original.buffer_cleanup == null) || field.acquisition_rank != original.acquisition_rank) {
				fail (path, "MOVE_VALUE changed an original field cleanup identity or order");
			}
			if (field.buffer_cleanup != null) {
				var buffer = field.buffer_cleanup;
				var expected_buffer = original.buffer_cleanup;
				if ((buffer.context_origin == null) != (expected_buffer.context_origin == null) || buffer.context_origin != null && !buffer.context_origin.same_type (expected_buffer.context_origin)) {
					fail (path, "MOVE_VALUE changed its original buffer allocation/release origin");
				}
				if ((buffer.record_element == null) != (expected_buffer.record_element == null) || (buffer.record_element != null ? buffer.record_element.struct_ordinal != expected_buffer.record_element.struct_ordinal : buffer.element_type == null || expected_buffer.element_type == null || !buffer.element_type.same_type (expected_buffer.element_type))) {
					fail (path, "MOVE_VALUE changed its original buffer element cleanup layout");
				}
			}
		}
	}

	private static NativeRecordElement? collection_record(Semantic.SemanticType type, HashTable<Semantic.SemanticType, NativeRecordElement>? records) {
		return records == null || !(type is Semantic.SliceType) ? null : records.lookup (((Semantic.SliceType) type).element_type);
	}

	private static bool buffer_matches(Semantic.SliceType type, NativeBufferValuePlan plan, HashTable<Semantic.SemanticType, NativeRecordElement>? records) throws NativeAbiError {
		var element = type.element_type;
		var origin = NativeTypeMapper.context_buffer_type (type);
		if ((origin == null) != (plan.context_origin == null) || origin != null && !origin.same_type (plan.context_origin)) {
			return false;
		}
		if (element is Semantic.StructType) {
			return records != null && records.lookup (element) != null && plan.record_element == records.lookup (element) && plan.element_type == null;
		}
		return plan.record_element == null && plan.element_type != null && NativeTypeMapper.map_type (element).same_type (plan.element_type);
	}

	private static HashTable<Semantic.SemanticType, NativeRecordElement> validate_records(SsaProgram source, NativeAbiProgram program) throws NativeAbiError {
		var records = new HashTable<Semantic.SemanticType, NativeRecordElement> (direct_hash, direct_equal);
		foreach (var record in program.record_elements) {
			if (record.struct_ordinal < 0 || record.struct_ordinal >= source.structs.length) {
				fail ("record-element", "element declaration is absent from SSA");
			}
			var structure = source.structs[record.struct_ordinal];
			if (structure.name != record.struct_name || structure.fields.length != record.fields.length || records.contains (structure.semantic_type)) {
				fail ("record-element", "element identity or complete field shape disagrees with SSA");
			}
			records.insert (structure.semantic_type, record);
		}
		foreach (var record in program.record_elements) {
			var structure = source.structs[record.struct_ordinal];
			for (int i = 0; i < structure.fields.length; i++) {
				var field = structure.fields[i];
				var planned = record.fields[i];
				if (field.ordinal != planned.ordinal || field.name != planned.name) {
					fail ("record-element", "declared field identity/order mismatch");
				}
				if (field.semantic_type is Semantic.StructType) {
					if (planned.record == null || planned.leaf != null || planned.record != records.lookup (field.semantic_type)) {
						fail ("record-element", "nested field must preserve exact nominal element identity");
					}
				} else if (planned.record != null || planned.leaf == null || !NativeTypeMapper.map_type (field.semantic_type).same_type (planned.leaf)) {
					fail ("record-element", "storage field type mismatch");
				}
			}
		}
		foreach (var cleanup in source.cleanups) {
			if (cleanup.is_buffer && cleanup.buffer_type.element_type is Semantic.StructType && !records.contains (cleanup.buffer_type.element_type)) {
				fail ("record-element", "owned array lost its required storage shape");
			}
		}
		foreach (var function in source.functions) {
			foreach (var storage in function.storage) {
				var array = storage.semantic_type as Semantic.ArrayType;
				if (array != null && array.element_type is Semantic.StructType && !records.contains (array.element_type)) {
					fail ("record-element", "fixed array lost its required storage shape");
				}
			}
		}
		return records;
	}

	internal static void validate_ssa_calls(SsaProgram source, NativeAbiProgram program, HashTable<SsaFunction, NativeFunction> callees) throws NativeAbiError {
		var records = validate_records (source, program);
		int projection = 0;
		for (int f = 0; f < source.functions.length; f++) {
			foreach (var block in source.functions[f].blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					var direct = instruction as SsaCallInstruction;
					var foreign = instruction as SsaCCallInstruction;
					var indirect = instruction as SsaCallableInvocation;
					var arguments = direct != null ? direct.arguments : foreign != null ? foreign.arguments : indirect != null ? indirect.arguments : null;
					if (arguments == null) {
						continue;
					}
					for (int a = 0; a < arguments.length; a++) {
						var view = arguments[a] as SsaCallbackView;
						if (view == null) {
							continue;
						}
						if (projection >= program.callback_views.length) {
							fail ("captured callback", "missing exact scoped projection");
						}
						var plan = program.callback_views[projection++];
						if (!plan.valid () || plan.caller != f || plan.block != block.ordinal || plan.instruction != i || plan.argument != a || !plan.closure.same_type (NativeTypeMapper.map_type (view.closure.semantic_type)) || !plan.callback.same_type (NativeTypeMapper.map_type (view.semantic_type))) {
							fail ("captured callback", "source Closure and callback ABI projection differ");
						}
					}
				}
			}
		}
		if (projection != program.callback_views.length) {
			fail ("captured callback", "extra or reordered projection");
		}

		// Every subsequent inventory uses these exact program-owned mappings.
		// Reject missing/foreign entries before inspecting any derived plans.
		if (source.functions.length != program.functions.length || callees.size () != source.functions.length) {
			fail ("program", "function correspondence must be one-to-one");
		}
		for (int f = 0; f < source.functions.length; f++) {
			var native_function = callees.lookup (source.functions[f]);
			if (native_function == null || native_function != program.functions[f] || native_function.owner != program) {
				fail ("function #%d".printf (f), "function correspondence must preserve exact identity and source order");
			}
		}
		int class_imports = 0;
		foreach (var handle in source.handles) {
			if (handle.c_import == null) {
				continue;
			}
			if (class_imports >= program.class_imports.length || !program.class_imports[class_imports++].api.equal (handle.c_import.api)) {
				fail ("CImport", "native root differs from SSA nominal declaration");
			}
		}
		if (class_imports != program.class_imports.length) {
			fail ("CImport", "unassociated native import root");
		}
		foreach (var function in source.functions) {
			var imported = function.entry.terminator as SsaForeignReturn;
			var plan = program.functions[function.ordinal].foreign_import;
			if ((imported == null) != (plan == null) || imported != null && (plan.binding.identity () != imported.binding.identity () || plan.error_factory != imported.factory.ordinal || !plan.valid (program, program.functions[function.ordinal]))) {
				fail ("CImport", "native member differs from exact SSA binding or factory");
			}
		}
		int bool_count = 0;
		for (int f = 0; f < source.c_functions.length; f++) {
			if (source.c_functions[f].metadata.bool_abi != Astra.Foreign.CBoolAbi.C99) {
				continue;
			}
			if (bool_count >= program.c_bool_policies.length || program.c_bool_policies[bool_count++] != "c99;import;%d;%s".printf (f, source.c_functions[f].metadata.policy_identity ())) {
				fail ("C99 bool", "native import policy differs from its admitted SSA origin");
			}
		}
		foreach (var exported in source.c_exports) {
			if (exported.bool_abi != Astra.Foreign.CBoolAbi.C99) {
				continue;
			}
			if (bool_count >= program.c_bool_policies.length || program.c_bool_policies[bool_count++] != "c99;export;%d;%d;%s".printf (exported.ordinal, exported.target.ordinal, exported.external_symbol)) {
				fail ("C99 bool", "native export policy differs from its admitted SSA origin");
			}
		}
		if (bool_count != program.c_bool_policies.length) {
			fail ("C99 bool", "missing or unrelated foreign boolean policy");
		}
		int gobject_imports = 0;
		for (int f = 0; f < source.c_functions.length; f++) {
			var metadata = source.c_functions[f].metadata;
			if (metadata.import_policy != Astra.Source.DeclarationPolicyId.GOBJECT_IMPORT) {
				continue;
			}
			if (gobject_imports >= program.gobject_imports.length || program.gobject_imports[gobject_imports] != "%d;%s".printf (f, metadata.policy_identity ())) {
				fail ("GObjectImport", "native bridge origin differs from its admitted SSA declaration");
			}
			gobject_imports++;
		}
		if (gobject_imports != program.gobject_imports.length) {
			fail ("GObjectImport", "unrelated native bridge origin");
		}
		int imported_com = 0;
		foreach (var handle in source.handles) {
			if (handle.com_import == null) {
				continue;
			}
			if (imported_com >= program.com_imports.length || program.com_imports[imported_com].identity () != handle.semantic_type.foreign_policy_identity || program.com_imports[imported_com].identity () != handle.com_import.identity ()) {
				fail ("COMImport", "native import identity differs from its exact SSA nominal contract");
			}
			imported_com++;
		}
		if (imported_com != program.com_imports.length) {
			fail ("COMImport", "native import inventory differs from SSA declarations");
		}
		int pod_count = 0;
		foreach (var structure in source.structs) {
			if (structure.representation != null) {
				if (pod_count >= program.pod_layouts.length || structure.representation.identity != program.pod_layouts[pod_count++].identity) {
					fail ("POD correspondence", "native record lost its original C layout identity");
				}
			}
		}
		if (pod_count != program.pod_layouts.length) {
			fail ("POD correspondence", "unrelated C layout plan");
		}
		foreach (var function in source.functions) {
			var native = callees.lookup (function);
			int count = 0;
			foreach (var storage in function.object_storage) {
				if (!storage.fallible) {
					continue;
				}
				if (count >= native.allocation_sites.length) {
					fail ("allocation correspondence", "missing nullable admission plan");
				}
				var site = native.allocation_sites[count++];
				if (!site.valid () || site.storage_ordinal != storage.ordinal || site.class_ordinal != storage.object_class.ordinal || site.constructor_ordinal != storage.object_class.constructor.ordinal || site.fallible != storage.fallible || site.heap != storage.heap_allocated) {
					fail ("allocation correspondence", "storage or constructor changed its original failure authority");
				}
				int inputs = 0;
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaLifecycleCallInstruction;
						if (call == null || !call.constructs || call.storage != storage) {
							continue;
						}
						foreach (var argument in call.owned_arguments) {
							if (inputs >= site.inputs.length) {
								fail ("allocation correspondence", "missing caller input restoration");
							}
							var input = site.inputs[inputs++];
							var cleanup = argument.cleanup;
							int parameter_index = -1;
							for (int p = 0; p < call.target.parameters.length; p++) {
								if (call.target.parameters[p] == argument.parameter) {
									parameter_index = p;
								}
							}
							if (input.parameter_ordinal != parameter_index || input.source_ordinal != argument.source_ordinal || input.class_ordinal != (cleanup.is_object ? cleanup.object_class.ordinal : -1) || input.heap != cleanup.is_heap_object || input.resource_name != (cleanup.is_object ? "" : argument.value.semantic_type.nominal_name ()) || input.cleanup_symbol != (cleanup.is_object ? "" : cleanup.external_symbol)) {
								fail ("allocation correspondence", "caller restoration differs from the exact SSA ownership transfer");
							}
						}
					}
				}
				if (inputs != site.inputs.length) {
					fail ("allocation correspondence", "unrelated caller input restoration");
				}
			}
			if (count != native.allocation_sites.length) {
				fail ("allocation correspondence", "unrelated nullable admission plan");
			}
			int frames = 0;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var creation = block.instructions[i] as SsaTaskCreate;
					if (creation == null || !creation.checked_admission) {
						continue;
					}
					if (frames >= native.frame_admissions.length) {
						fail ("frame admission correspondence", "missing original checked factory admission");
					}
					var site = native.frame_admissions[frames++];
					if (!site.valid () || site.block_ordinal != block.ordinal || site.position != i || site.task_ordinal != creation.result.ordinal || site.factory_ordinal != creation.target.ordinal || site.exception_ordinal != creation.exception_result.ordinal || site.context_mode != ((Semantic.HandleType) creation.allocation_context.semantic_type).context_mode || site.inputs.length != creation.owned_arguments.length || site.buffers.length != creation.buffer_arguments.length) {
						fail ("frame admission correspondence", "checked factory, error, context or inputs differ from SSA authority");
					}
					for (int a = 0; a < site.inputs.length; a++) {
						var input = site.inputs[a];
						var argument = creation.owned_arguments[a];
						var cleanup = argument.cleanup;
						int parameter = -1;
						for (int p = 0; p < creation.target.parameters.length; p++) {
							if (creation.target.parameters[p] == argument.parameter) {
								parameter = p;
							}
						}
						if (input.parameter_ordinal != parameter || input.source_ordinal != argument.source_ordinal || input.class_ordinal != (cleanup.is_object ? cleanup.object_class.ordinal : -1) || input.heap != cleanup.is_heap_object || input.resource_name != (cleanup.is_object ? "" : argument.value.semantic_type.nominal_name ()) || input.cleanup_symbol != (cleanup.is_object ? "" : cleanup.external_symbol)) {
							fail ("frame admission correspondence", "restoration differs from the original capture and caller owner");
						}
					}
					for (int b = 0; b < site.buffers.length; b++) {
						var input = site.buffers[b];
						var argument = creation.buffer_arguments[b];
						if (input.first_leaf != argument.parameter.first_leaf || input.source_ordinal != argument.disarm.place.storage.owner_ordinal || !buffer_matches (argument.pair.shape.slice_type, input.value_plan, records)) {
							fail ("frame admission correspondence", "conditional buffer restoration differs from exact original caller and complete pair");
						}
					}
				}
			}
			if (frames != native.frame_admissions.length) {
				fail ("frame admission correspondence", "unrelated checked factory admission");
			}
			int scoped_count = 0;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var scoped = block.instructions[i] as SsaScopedAllocator;
					if (scoped == null) {
						continue;
					}
					if (scoped_count >= native.scoped_backings.length) {
						fail ("scoped backing correspondence", "missing exact lexical backing plan");
					}
					var plan = native.scoped_backings[scoped_count++];
					if (!plan.valid () || plan.block_ordinal != block.ordinal || plan.position != i || plan.result_ordinal != scoped.result.ordinal || plan.context_ordinal != scoped.owner.source_ordinal || plan.owner_ordinal != scoped.owner.ordinal || plan.backing_ordinal != scoped.backing.owner_ordinal || plan.storage_ordinal != scoped.backing.ordinal || plan.base_ordinal != ((SsaDefinition) scoped.pair.base_value).ordinal || plan.length_ordinal != ((SsaDefinition) scoped.pair.length_value).ordinal || plan.region_ordinal != scoped.loan.region_ordinal || plan.handle_name != scoped.result.semantic_type.nominal_name () || plan.kind_identity != NativeAbiValidator.scoped_backing_value_identity (scoped.kind) || plan.slots_identity != NativeAbiValidator.scoped_backing_value_identity (scoped.slots)) {
						fail ("scoped backing correspondence", "native context, complete buffer pair or configuration differs from SSA authority");
					}
					int ends = 0;
					foreach (var candidate in function.blocks) {
						for (int e = 0; e < candidate.instructions.length; e++) {
							var event = candidate.instructions[e] as SsaHeapOwnerEvent;
							if (event == null || event.owner != scoped.owner || event.action != SsaHeapOwnerAction.END) {
								continue;
							}
							if (ends + 1 >= plan.retirements.length || plan.retirements[ends++] != candidate.ordinal || plan.retirements[ends++] != e - 1 || e < 1 || candidate.instructions[e - 1] != event.effect || !(event.effect is SsaCleanupInstruction)) {
								fail ("scoped backing correspondence", "native loan lost its exact actual lexical context cleanup");
							}
						}
					}
					if (ends != plan.retirements.length) {
						fail ("scoped backing correspondence", "unrelated lexical retirement sites");
					}
				}
			}
			if (scoped_count != native.scoped_backings.length) {
				fail ("scoped backing correspondence", "unrelated lexical backing plans");
			}
		}
		int function_values = 0;
		int shared_operations = 0;
		int closures = 0;
		int retained_count = 0;
		int actor_count = 0;
		foreach (var function in source.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaActorSend) {
						actor_count++;
					}
					if (instruction is SsaRetainedOperation) {
						retained_count++;
					}
					if (instruction is SsaFunctionValueCall) {
						function_values++;
					}
					if (instruction is SsaSharedOperation) {
						shared_operations++;
					}
					if (instruction is SsaClosureBind || instruction is SsaClosureCall) {
						closures++;
					}
				}
			}
		}
		if (actor_count != program.actor_operations.length || retained_count != program.retained_operations.length || function_values != program.function_values.length || shared_operations != program.shared_operations.length || closures != program.closures.length) {
			fail ("native lifetime/callable inventory", "missing or unrelated operation plan");
		}

		if (source.classes.length != program.classes.length) {
			fail ("classes", "class correspondence must be one-to-one");
		}
		for (int c = 0; c < source.classes.length; c++) {
			var owner = source.classes[c];
			var plan = program.classes[c];
			if (!Astra.Source.AllocationPolicy.matches (plan.allocation_policy, ((Semantic.ClassType) owner.semantic_type).allocation_policy_identity)) {
				fail ("allocation correspondence", "native Class lost its exact source policy identity");
			}
			if (plan.is_interface != ((Semantic.ClassType) owner.semantic_type).is_interface) {
				fail ("interface correspondence", "requires the exact nominal abstract contract identity");
			}
			if ((owner.generic_instance != null) != (plan.generic_instance != null)) {
				fail ("generic Class correspondence", "missing or additional exact specialization");
			}
			if (owner.generic_instance != null) {
				var key = owner.generic_instance;
				var native_key = plan.generic_instance;
				if (key.definition.structure != null) {
					if (native_key.definition != key.definition || native_key.declared_structure == null || !NativeAbiBuilder.declared_class (owner, source, program.struct_values, callees).same_arguments (native_key.declared_structure)) {
						fail ("generic Class correspondence", "declared definition/type-argument identities changed");
					}
				} else {
					var argument = NativeAbiBuilder.slots_type (owner.fields[0], callees, source, program.struct_values);
					if (native_key.definition != key.definition || native_key.argument_ordinal != argument.element_ordinal || native_key.record_argument != argument.record_value || (argument.resource == null ? native_key.resource_argument != null : !argument.resource.same_owner (native_key.resource_argument))) {
						fail ("generic Class correspondence", "definition/argument identity changed");
					}
				}
				for (int i = 0; i < key.definition.member_count; i++) {
					int target = -1;
					if (key.definition.operation (i) == Astra.Source.ExactClassOperation.INITIALIZE) {
						target = callees.lookup (owner.constructor).ordinal;
					} else {
						foreach (var method in owner.methods) {
							if (method.name == key.definition.member_name (i)) {
								target = callees.lookup (method).ordinal;
							}
						}
					} if (native_key.member_target (i) != target) {
						fail ("generic Class correspondence", "exact member target changed");
					}
				}
			}
			if (owner.name != plan.name || owner.span.file.path != plan.span.file.path || owner.span.start != plan.span.start || owner.span.end != plan.span.end || plan.ordinal != owner.ordinal || plan.parent_ordinal != (owner.parent_class == null ? -1 : owner.parent_class.ordinal) || plan.polymorphic != owner.polymorphic || plan.exception_root != owner.exception_root || plan.destructor_ordinal != (owner.destructor == null ? -1 : callees.lookup (owner.destructor).ordinal) || plan.fields.length != owner.fields.length || plan.virtual_targets.length != owner.virtual_entries.length) {
				fail ("class correspondence", "requires exact nominal declaration, parent, header, destructor and field/slot grouping");
			}
			for (int f = 0; f < owner.fields.length; f++) {
				var field = owner.fields[f];
				var planned = plan.fields[f];
				var resource = field.owned_cleanup == null ? null : NativeAbiBuilder.resource_owner (field.semantic_type, source);
				if (planned.owns_record != (field.record_owner != null) || (resource == null ? planned.resource_owner != null : !resource.same_owner (planned.resource_owner))) {
					fail ("class correspondence", "field Resource cleanup lost exact nominal origin");
				}
				int record_ordinal = -1;
				for (int r = 0; r < source.structs.length; r++) {
					if (source.structs[r].semantic_type == field.semantic_type) {
						record_ordinal = r;
					}
				}
				NativeAbiType? storage_type = null;
				if (record_ordinal < 0) {
					storage_type = (field.semantic_type is Semantic.OwnerSlotsType) ? (NativeAbiType) NativeAbiBuilder.slots_type (field, callees, source, program.struct_values) : (field.semantic_type is Semantic.StringType) ? (NativeAbiType) new NativeTextType (NativeTextContract.RECEIVER_TEXT) : (field.semantic_type is Semantic.ContextBytesType) ? NativeTypeMapper.map_type (field.semantic_type) : (field.semantic_type is Semantic.SliceType) ? (NativeAbiType) new NativeSliceType () : (field.semantic_type is Semantic.ClassType) ? (NativeAbiType) new NativeScalarAbiType (NativeScalarType.PTR) : NativeTypeMapper.map_type (field.semantic_type);
				}
				if (planned.ordinal != field.ordinal || planned.span.file.path != field.span.file.path || planned.span.start != field.span.start || planned.span.end != field.span.end || planned.record_ordinal != record_ordinal || (storage_type == null) != (planned.storage_type == null) || (storage_type != null && !storage_type.same_type (planned.storage_type)) || planned.name != field.name || planned.type_name != field.semantic_type.display_name () || planned.text_snapshot != field.text_snapshot || planned.is_private != field.is_private) {
					fail ("class correspondence", "declared field origin, physical channel or storage lifetime mismatch");
				}
			}
			int cache_rank = 0;
			foreach (var property in owner.properties) {
				var getter = callees.lookup (property.getter);
				if (property.is_lazy != (getter.lazy_cache != null)) {
					fail ("lazy correspondence", "initializer cache intent differs from the source property");
				}
				if (!property.is_lazy) {
					continue;
				}
				if (cache_rank >= plan.lazy_caches.length) {
					fail ("lazy correspondence", "missing declared cache");
				}
				var cache = plan.lazy_caches[cache_rank++];
				if (getter.lazy_cache != cache || cache.name != property.name || cache.span.file.path != property.span.file.path || cache.span.start != property.span.start || cache.span.end != property.span.end || cache.property_ordinal != property.ordinal || cache.getter_ordinal != getter.ordinal || cache.class_ordinal != owner.ordinal || !(property.is_owned_lazy ? (NativeAbiType) new NativeScalarAbiType (NativeScalarType.PTR) : NativeTypeMapper.map_type (property.semantic_type)).same_type (cache.value_type) || cache.is_owned != property.is_owned_lazy || cache.factory_ordinal != (property.factory == null ? -1 : callees.lookup (property.factory).ordinal)) {
					fail ("lazy correspondence", "requires exact source property, receiver layout, initializer and copied result channel");
				}
			}
			if (cache_rank != plan.lazy_caches.length) {
				fail ("lazy correspondence", "undeclared cache in native layout");
			}
			for (int v = 0; v < owner.virtual_entries.length; v++) {
				if (plan.virtual_targets[v] != callees.lookup (owner.virtual_entries[v]).ordinal) {
					fail ("class correspondence", "virtual slot must select exact declared implementation");
				}
			}
		}

		var readonly_effects = new SsaReadonlyInference (source);
		var lifetime_contracts = NativeAbiBuilder.lifetime_descriptors (source);
		var callback_effects = new SsaCallbackPreconditions (source, readonly_effects);
		NativeSumValidator.validate (source, program, records);
		for (int f = 0; f < source.functions.length; f++) {
			var function = source.functions[f];
			string path = "function #%d".printf (f);
			var native_function = callees.lookup (function);
			if (native_function.runtime_lifetimes != lifetime_contracts.lookup (function)) {
				fail (path, "runtime lifetime equations/effects differ from actual SSA operations");
			}
			var signature = native_function.signature;
			var constructor = function as SsaConstructor;
			bool checked_constructor = constructor != null && Semantic.ConstructorContracts.admitted (constructor.declaring_class.foreign_export, constructor.declaring_class.allocation_policy, constructor.member_ordinal, function.throws_type);
			var unwind = native_function.constructor_unwind;
			if (checked_constructor != (unwind != null)) {
				fail (path, "checked constructor lost native partial-retirement authority");
			}
			if (checked_constructor) {
				if (unwind.class_ordinal != constructor.declaring_class.ordinal || !unwind.valid (program, native_function)) {
					fail (path, "constructor unwind lost exact native root");
				}
				int cursor = 0;
				var root = constructor.declaring_class;
				for (int i = root.fields.length - 1; i >= 0; i--) {
					var field = root.fields[i];
					if (field.owned_cleanup == null && field.record_owner == null && !field.text_snapshot && !(field.semantic_type is Semantic.OwnerSlotsType)) {
						continue;
					}
					if (cursor >= unwind.field_count || unwind.field (cursor++) != i) {
						fail (path, "constructor unwind differs from actual SSA owned fields");
					}
				}
				if (cursor != unwind.field_count) {
					fail (path, "constructor unwind contains extra fields");
				}
				cursor = 0;
				for (int p = root.properties.length - 1; p >= 0; p--) {
					if (!root.properties[p].is_owned_lazy) {
						continue;
					}
					if (cursor >= unwind.lazy_count || unwind.lazy_property (cursor++) != p) {
						fail (path, "constructor unwind differs from actual SSA lazy caches");
					}
				}
				if (cursor != unwind.lazy_count) {
					fail (path, "constructor unwind contains extra lazy caches");
				}
			}
			if (signature.nonnull_result != function.nonnull_result) {
				fail (path, "native result lost its checked nonnull fact");
			}
			var readonly_summary = readonly_effects.summary (function);
			var callback_summary = callback_effects.summary (function);
			var code_inputs = SsaReadonlyInference.code_inputs (function);
			if (native_function.scoped_readonly != readonly_summary.eligible ||
			    native_function.readonly_inputs != (readonly_summary.eligible ? Astra.Code.CodeInputSet.encode (readonly_summary, code_inputs) : "") ||
			    native_function.callback_inputs != (callback_summary.eligible ? Astra.Code.CodeInputSet.encode (callback_summary, code_inputs) : "") ||
			    native_function.callback_input_count != code_inputs.length || native_function.callback_contract_supported != callback_summary.eligible) {
				fail (path, "callback effects differ from the original SSA definition or native declaration");
			}
			var async_plan = native_function.async_callable;
			if ((function.async_body == null) != (async_plan == null) || async_plan != null &&
			    (async_plan.imported != (function.native_declaration != null) || async_plan.composable != function.async_body.runtime.composable || async_plan.provider != function.async_body.runtime.provider || async_plan.runtime_error != function.async_body.runtime.error_type.nominal_name () ||
			     async_plan.success_name != function.return_type.nominal_name () || async_plan.success_mode != (int) function.result_contract || !async_plan.matches (signature))) {
				fail (path, "async callable lost exact SSA/native runtime, success or capture correspondence");
			}

			int memory_index = 0;
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var memory = instruction as SsaVectorMemoryInstruction;
					if (memory == null) {
						continue;
					}
					if (memory_index >= native_function.vector_memory.length || !NativeTypeMapper.map_type (memory.contract.vector_type).same_type (native_function.vector_memory[memory_index].vector_type) || memory.contract.alignment != native_function.vector_memory[memory_index].alignment || memory.contract.store != native_function.vector_memory[memory_index].store) {
						fail (path, "vector memory lost its exact SSA/native contract");
					}
					memory_index++;
				}
			}
			if (memory_index != native_function.vector_memory.length) {
				fail (path, "extra native vector memory contract");
			}
			if ((function.effect_facts == null) != (native_function.effect_facts == null) || (function.effect_facts != null && !function.effect_facts.same (native_function.effect_facts))) {
				fail (path, "derived effects lost exact SSA/native correspondence");
			}
			if (function.stack_objects.length != native_function.stack_objects.length) {
				fail (path, "stack objects lost exact SSA/native count");
			}
			if (function.shared_elisions.length != native_function.shared_elisions.length) {
				fail (path, "shared elisions lost exact SSA/native extent");
			}
			for (int s = 0; s < function.shared_elisions.length; s++) {
				if (function.shared_elisions[s].acquisition.result.ordinal != native_function.shared_elisions[s]) {
					fail (path, "shared elisions lost exact SSA/native identity");
				}
			}
			for (int s = 0; s < function.stack_objects.length; s++) {
				if (function.stack_objects[s].ordinal != native_function.stack_objects[s]) {
					fail (path, "stack objects lost exact SSA/native storage identity");
				}
			}
			int exact = 0;
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var call = block.instructions[i] as SsaCallInstruction;
					if (call == null || call.exact_target == null) {
						continue;
					}
					if (exact + 3 > native_function.exact_calls.length || native_function.exact_calls[exact] != block.ordinal || native_function.exact_calls[exact + 1] != i || native_function.exact_calls[exact + 2] != call.exact_target.ordinal) {
						fail (path, "exact calls lost SSA/native identity");
					}
					exact += 3;
				}
			}
			if (exact != native_function.exact_calls.length) {
				fail (path, "exact calls lost SSA/native extent");
			}
			if (function.floating_policy != native_function.floating_policy) {
				fail (path, "floating policy lost exact SSA/native authority");
			}
			if (function.utf8_factory != native_function.utf8_factory) {
				fail (path, "UTF-8 factory lost exact source/native validation authority");
			}
			validate_struct_association (function.struct_result, signature.struct_result, source, path + "/struct-result");
			if (function.struct_result != null && signature.struct_result_mode != NativeAbiBuilder.record_mode (function.struct_result.mode)) {
				fail (path, "record result changed its original copy, move or bounded observation operation");
			}
			if ((signature.buffer_result != null) != (function.owned_cleanup != null && function.owned_cleanup.is_buffer) || signature.buffer_parameters.length != function.buffer_parameters.length) {
				fail (path, "buffer ownership boundary lost its exact physical group");
			}
			if (signature.buffer_result != null && !buffer_matches (function.owned_cleanup.buffer_type, signature.buffer_result, records)) {
				fail (path, "buffer result element layout mismatch");
			}
			for (int i = 0; i < function.buffer_parameters.length; i++) {
				var group = function.buffer_parameters[i];
				var plan = signature.buffer_parameters[i];
				if (group.first_leaf != plan.first_leaf || group.source_ordinal != plan.source_ordinal || !buffer_matches (group.cleanup.buffer_type, plan.value_plan, records)) {
					fail (path, "buffer parameter exact group/layout mismatch");
				}
			}
			if (function.struct_parameters.length != signature.struct_parameters.length) {
				fail (path, "struct parameter group count mismatch");
			}
			for (int g = 0; g < function.struct_parameters.length; g++) {
				var group = function.struct_parameters[g];
				var plan = signature.struct_parameters[g];
				if (group.source_ordinal != plan.source_ordinal || group.first_leaf != plan.first_leaf || plan.mode != NativeAbiBuilder.record_mode (group.shape.mode)) {
					fail (path, "struct parameter grouping lost source position");
				}
				validate_struct_association (group.shape, plan.value_plan, source, path + "/struct-parameter");
			}
			if ((function.result_storage == null) != (signature.object_result == null)) {
				fail (path, "owned object result requires exact hidden PTR storage plan");
			}
			if (function.result_storage != null) {
				var origin = signature.object_result.object_origin;
				var owner = function.result_storage.object_class;
				if (origin == null || origin.heap || origin.class_ordinal != owner.ordinal || origin.class_name != owner.name) {
					fail (path, "caller-backed result lost its exact Class storage origin");
				}
			}
			if (function.heap_result != (signature.heap_result != null)) {
				fail (path, "heap result origin correspondence changed");
			}
			if (signature.heap_result != null) {
				var plan = signature.heap_result;
				if (!plan.heap || plan.class_ordinal >= source.classes.length || source.classes[plan.class_ordinal].semantic_type != function.return_type || source.classes[plan.class_ordinal].name != plan.class_name) {
					fail (path, "heap result requires its exact source class and origin correspondence");
				}
			}

			if ((function.throws_type == null) != (signature.exception_plan == null)) {
				fail (path, "throws declaration requires exact private exception plan");
			}
			if (signature.exception_plan != null) {
				var plan = signature.exception_plan;
				if (plan.bound_ordinal >= source.classes.length || plan.root_ordinal >= source.classes.length || source.classes[plan.bound_ordinal].semantic_type != function.throws_type || source.classes[plan.bound_ordinal].name != plan.bound_name || !source.classes[plan.root_ordinal].exception_root || source.classes[plan.root_ordinal].name != plan.root_name || !function.throws_type.derives_from ((Semantic.ClassType) source.classes[plan.root_ordinal].semantic_type)) {
					fail (path, "exception plan requires exact nominated root and declared class bound correspondence");
				}
			}
			int generic_result = -1;
			Astra.Source.ExactClassDefinitionIdentity? generic_result_origin = null;
			if (Semantic.GenericClassTypes.general (function.return_type) && function.result_contract == Semantic.ResultOwnershipContract.OWNED_TRANSFER) {
				foreach (var owner in source.classes) {
					if (owner.semantic_type == function.return_type) {
						generic_result = owner.ordinal;
						generic_result_origin = owner.generic_instance.definition;
					}
				}
			}
			if (signature.generic_owner_result_class != generic_result || signature.generic_owner_result_origin != generic_result_origin || generic_result >= 0 && signature.generic_owner_result_heap != function.heap_result) {
				fail (path, "owned generic Class result correspondence changed");
			}
			var method = function as SsaMethod;
			var request = method == null ? null : method.generic_method_instance;
			var binding = native_function.generic_method_instance;
			if ((request == null) != (binding == null)) {
				fail (path, "generic method specialization correspondence changed");
			}
			if (request != null) {
				if (binding.definition != request.class_instance.definition || binding.member != request.member || binding.class_ordinal != method.declaring_type.ordinal || binding.target_ordinal != native_function.ordinal || binding.argument_count != request.arguments.length) {
					fail (path, "generic method exact argument/declaration correspondence changed");
				}
				if (request.class_instance.definition.structure == null) {
					if (!NativeAbiBuilder.copy_type (request.argument, source, program.struct_values).same_type (binding.argument)) {
						fail (path, "generic method legacy copied argument correspondence changed");
					}
				} else {
					for (int a = 0; a < request.arguments.length; a++) {
						if (!NativeAbiBuilder.declared_type (request.arguments.at (a), source, program.struct_values, callees).same_type (binding.argument_type (a))) {
							fail (path, "generic method ordered argument correspondence changed");
						}
					}
				}
			}

			if ((function.implicit_receiver == null) != (signature.receiver == null) || (method != null && (native_function.declaring_type_ordinal != method.declaring_type.ordinal || native_function.method_ordinal != method.method_ordinal || native_function.declaring_type_is_class != (method.declaring_type is SsaClass) || signature.receiver.scalar_type != NativeScalarType.PTR))) {
				fail (path, "method receiver and member correspondence must be exact");
			}

			var accessor = function as SsaPropertyAccessor;
			if (accessor != null) {
				var property = accessor.property_member;
				if (native_function.declaring_type_ordinal != property.declaring_type.ordinal || native_function.declaring_type_is_class != (property.declaring_type is SsaClass) || native_function.property_ordinal != property.ordinal || native_function.method_ordinal != -1 || native_function.kind != ((function is SsaPropertyGetter) ? NativeCallableKind.PROPERTY_GETTER : NativeCallableKind.PROPERTY_SETTER)) {
					fail (path, "accessor correspondence requires exact property, owner and accessor kind");
				}
			}
			var lifecycle = function as SsaLifecycle;
			if (lifecycle != null && (native_function.declaring_type_ordinal != lifecycle.declaring_class.ordinal || native_function.kind != ((function is SsaConstructor) ? NativeCallableKind.CONSTRUCTOR : NativeCallableKind.DESTRUCTOR) || signature.receiver.scalar_type != NativeScalarType.PTR || signature.result != null)) {
				fail (path, "lifecycle signature requires exact kind/class, receiver PTR and void result");
			}
			var resource_result = NativeAbiBuilder.resource_owner (function.return_type, source);
			if (function.result_contract != Semantic.ResultOwnershipContract.OWNED_TRANSFER) {
				resource_result = null;
			}
			if (resource_result == null ? signature.resource_result != null : !resource_result.same_owner (signature.resource_result)) {
				fail (path, "Resource result lost exact nominal owned cleanup correspondence");
			}
			if (function.parameters.length != signature.parameters.length) {
				fail (path, "parameter channel count does not match SSA function");
			}
			for (int p = 0; p < function.parameters.length; p++) {
				int borrowed_class = -1;
				Astra.Source.ExactClassDefinitionIdentity? borrowed_origin = null;
				if (function.parameters[p].semantic_type is Semantic.ExactGenericClassType && function.parameters[p].pointer_contract == Semantic.PointerParameterContract.BORROWED_NOESCAPE) {
					foreach (var owner in source.classes) {
						if (owner.semantic_type == function.parameters[p].semantic_type) {
							borrowed_class = owner.ordinal;
							borrowed_origin = owner.generic_instance.definition;
						}
					}
				}
				if (signature.parameters[p].generic_borrow_class != borrowed_class || signature.parameters[p].generic_borrow_origin != borrowed_origin) {
					fail (path, "borrowed generic Class exact instance correspondence changed");
				}
				int generic_owned = -1;
				Astra.Source.ExactClassDefinitionIdentity? generic_owned_origin = null;
				if (Semantic.GenericClassTypes.general (function.parameters[p].semantic_type) && function.parameters[p].pointer_contract == Semantic.PointerParameterContract.OWNED_TRANSFER) {
					foreach (var owner in source.classes) {
						if (owner.semantic_type == function.parameters[p].semantic_type) {
							generic_owned = owner.ordinal;
							generic_owned_origin = owner.generic_instance.definition;
						}
					}
				}
				if (signature.parameters[p].generic_owner_class != generic_owned || signature.parameters[p].generic_owner_origin != generic_owned_origin) {
					fail (path, "owned generic Class parameter correspondence changed");
				}
				int exact_borrowed_class = -1;
				if (function.parameters[p].semantic_type is Semantic.ClassType && function.parameters[p].pointer_contract == Semantic.PointerParameterContract.BORROWED_NOESCAPE) {
					foreach (var owner in source.classes) {
						if (owner.semantic_type == function.parameters[p].semantic_type) {
							exact_borrowed_class = owner.ordinal;
						}
					}
				}
				var resource = NativeAbiBuilder.resource_owner (function.parameters[p].semantic_type, source);
				if (resource == null ? signature.parameters[p].resource != null : !resource.same_owner (signature.parameters[p].resource) || signature.parameters[p].owns_resource != (function.parameters[p].pointer_contract == Semantic.PointerParameterContract.OWNED_TRANSFER)) {
					fail (path, "Resource parameter lost exact nominal cleanup and transfer correspondence");
				}
				var parameter = function.parameters[p];
				NativeAbiType expected = NativeTypeMapper.map_parameter (parameter.semantic_type, parameter.pointer_contract, collection_record (parameter.semantic_type, records), NativeAbiBuilder.move_class_parameter (function, p));
				if (parameter.semantic_type is Semantic.EnumType) {
					foreach (var plan in program.sum_values) {
						if (plan.identity == ((Semantic.EnumType) parameter.semantic_type).identity && plan.owning) {
							expected = new NativeSumType (plan.identity, NativeSumRole.OWNED_TRANSFER);
						}
					}
				}
				var origin = signature.parameters[p].object_origin;
				bool owns_object = parameter.semantic_type is Semantic.ClassType && parameter.pointer_contract == Semantic.PointerParameterContract.OWNED_TRANSFER;
				if (owns_object != (origin != null) || (origin != null && (origin.heap != parameter.heap_object || origin.class_ordinal >= source.classes.length || source.classes[origin.class_ordinal].semantic_type != parameter.semantic_type || source.classes[origin.class_ordinal].name != origin.class_name))) {
					fail (path, "owned parameter exact class and allocation origin correspondence changed");
				}
				if (!expected.same_type (signature.parameters[p].abi_type)) {
					fail (path + "/parameter #%d".printf (p), "parameter channel type does not match SSA function");
				}
				var pointee = signature.parameters[p].scalar_pointee;
				bool scalar_reference = parameter.pointer_contract == Semantic.PointerParameterContract.BORROWED_NOESCAPE && Semantic.ForeignApiTypes.scalar_pointee (parameter.semantic_type) != null;
				if (scalar_reference != (pointee != null) || scalar_reference && pointee.scalar_type != NativeTypeMapper.map_scalar (((Semantic.TypedPointerType) parameter.semantic_type).pointee)) {
					fail (path, "scalar reference lost its exact native pointee type");
				}
				if (signature.parameters[p].borrowed_class_ordinal != exact_borrowed_class || signature.parameters[p].requires_nonnull != parameter.requires_nonnull) {
					fail (path, "borrowed Class exact nominal or nonnull correspondence changed");
				}
			}
			int record_leaves = 0;
			foreach (var owner in function.heap_owners) {
				if (owner.record_type == null) {
					continue;
				}
				record_leaves++;
				int matched = 0;
				foreach (var plan in program.functions[f].record_owners) {
					if (plan.source_ordinal != owner.source_ordinal || plan.record_name != owner.record_type.name) {
						continue;
					}
					foreach (var field in plan.obligations) {
						if (owner.record_path != null && field.field_path == owner.record_path.spelling () && field.type_name == owner.record_field.semantic_type.display_name () && field.buffer_cleanup == null && field.cleanup_symbol == owner.cleanup.external_symbol && field.cleanup_class_ordinal == (owner.cleanup.is_heap_object ? owner.cleanup.object_class.ordinal : -1) && field.acquisition_rank == owner.record_rank) {
							matched++;
						}
					}
				}
				if (matched != 1) {
					fail (path, "local record field lost its exact native cleanup obligation");
				}
			}
			foreach (var slot in function.buffer_storage) {
				if (slot.record_type == null) {
					continue;
				}
				record_leaves++;
				int matched = 0;
				foreach (var plan in program.functions[f].record_owners) {
					if (plan.source_ordinal != slot.record_source_ordinal || plan.record_name != slot.record_type.name) {
						continue;
					}
					foreach (var field in plan.obligations) {
						if (slot.record_path != null && field.field_path == slot.record_path.spelling () && field.type_name == slot.cleanup.buffer_type.display_name () && field.buffer_cleanup != null && field.acquisition_rank == slot.record_rank && buffer_matches (slot.cleanup.buffer_type, field.buffer_cleanup, records)) {
							matched++;
						}
					}
				}
				if (matched != 1) {
					fail (path, "record buffer lost its exact complete native pair responsibility");
				}
			}
			int planned_leaves = 0;
			foreach (var plan in program.functions[f].record_owners) {
				planned_leaves += (int) plan.obligations.length;
			}
			if (planned_leaves != record_leaves) {
				fail (path, "native record obligations gained or lost a field responsibility");
			}
			if (program.functions[f].receiver_borrow != (function.result_contract == Semantic.ResultOwnershipContract.RECEIVER_BORROW)) {
				fail (path, "receiver borrow property authority changed");
			}
			var observation = native_function.record_observation;
			bool observes_record = function.struct_result != null && function.struct_result.mode == Semantic.StructValueMode.BORROW_VALUE;
			if ((observation != null) != observes_record) {
				fail (path, "record observation lost its exact source receiver-field contract");
			}
			if (observation != null) {
				SsaStructField? origin = null;
				if (function.native_declaration != null) {
					var imported_getter = function as SsaPropertyGetter;
					if (imported_getter != null) {
						foreach (var candidate in imported_getter.property_member.declaring_type.fields) {
							if (candidate.name == function.native_declaration.identity.record_field && candidate.semantic_type == function.return_type && candidate.record_owner != null) {
								origin = candidate;
							}
						}
					}
				} else {
					var validation = function.entry.instructions.length == 0 ? null : function.entry.instructions[0] as SsaValidatePlaceInstruction;
					var field = validation == null ? null : validation.place as SsaIndirectFieldPlace;
					if (field != null && field.pointer == function.implicit_receiver) {
						origin = field.field;
					}
				}
				if (origin == null || !(origin.containing_type is SsaClass) || observation.class_ordinal != ((SsaClass) origin.containing_type).ordinal || observation.field_ordinal != origin.ordinal || observation.value_plan != signature.struct_result) {
					fail (path, "record observation changed its original exact nominal field binding");
				}
			}
			var result = function.struct_result == null && !(function.owned_cleanup != null && function.owned_cleanup.is_buffer) ? NativeTypeMapper.map_result (function.return_type, function.result_contract) : null;
			if ((result == null) != (signature.result == null) || (result != null && !result.abi_type.same_type (signature.result.abi_type))) {
				fail (path + "/result", "result channel does not match SSA function");
			}
		}
		for (int f = 0; f < source.functions.length; f++) {
			var function = source.functions[f];
			for (int b = 0; b < function.blocks.length; b++) {
				var block = function.blocks[b];
				for (int i = 0; i < block.instructions.length; i++) {
					var actor = block.instructions[i] as SsaActorSend;
					if (actor != null) {
						NativeActorPlan? plan = null;
						foreach (var candidate in program.actor_operations) {
							if (candidate.caller == f && candidate.block == b && candidate.instruction == i) {
								plan = candidate;
							}
						}
						if (plan == null || plan.action != actor.action || !plan.sender.same_type (NativeTypeMapper.map_type (actor.sender.semantic_type)) || plan.error_class < 0 || plan.error_class >= source.classes.length || source.classes[plan.error_class].semantic_type != actor.error_type || actor.result == null || actor.result.semantic_type != actor.error_type || (actor.action == Astra.Source.ActorAction.SEND ? actor.message == null || actor.message.semantic_type != ((Semantic.ClosureHandleType) actor.sender.semantic_type).actor_message : actor.message != null)) {
							fail ("native Actor", "missing exact sender, message disposition or checked Error operation correspondence");
						}
					}
					var closure_bind = block.instructions[i] as SsaClosureBind;
					var closure_call = block.instructions[i] as SsaClosureCall;
					if (closure_bind != null || closure_call != null) {
						NativeClosurePlan? plan = null;
						foreach (var candidate in program.closures) {
							if (candidate.caller == f && candidate.block == b && candidate.instruction == i) {
								plan = candidate;
							}
						}
						var type = closure_bind != null ? closure_bind.result.semantic_type : closure_call.callee.semantic_type;
						if (plan == null || plan.binding != (closure_bind != null) || !plan.handle.same_type (NativeTypeMapper.map_type (type))) {
							fail ("native closure", "missing exact carried environment/code call plan");
						}
						if (closure_bind != null && (closure_bind.target == null || plan.target != callees.lookup (closure_bind.target).ordinal || closure_bind.environment.semantic_type != ((Semantic.ClosureHandleType) type).environment_type || closure_bind.cleanup.closure_type != type || (closure_bind.actor_binding == null ? plan.actor_binding != null : plan.actor_binding == null || !plan.actor_binding.valid () || !closure_bind.actor_binding.valid () || plan.actor_binding.name != closure_bind.actor_binding.name || plan.actor_binding.capacity != closure_bind.actor_binding.capacity))) {
							fail ("native closure", "bound code or environment cleanup differs from exact source identity");
						}
						if (closure_call != null) {
							validate_callable_result (closure_call, plan.result_owner);
							validate_callable_record_result (closure_call.struct_result != null ? closure_call.struct_result : closure_call.owned_success == null ? null : closure_call.owned_success.struct_result, plan.record_result);

							var signature = (Semantic.ClosureHandleType) type;
							if ((signature.throws_type == null ? ((signature.result_type.kind == Semantic.TypeKind.VOID || signature.result_type.is_struct_storage ()) ? closure_call.result != null : closure_call.result == null || closure_call.result.semantic_type != signature.result_type) : closure_call.result == null || !(closure_call.result.semantic_type is Semantic.ClassType) || !signature.throws_type.derives_from ((Semantic.ClassType) closure_call.result.semantic_type)) || closure_call.arguments.length != Semantic.CallableRecordGroups.physical_parameters (signature, closure_call.struct_arguments).length) {
								fail ("native closure", "invoke result/arity differs from carried signature");
							}
							for (int a = 0; a < closure_call.arguments.length; a++) {
								if (closure_call.arguments[a].semantic_type != Semantic.CallableRecordGroups.physical_parameters (signature, closure_call.struct_arguments)[a]) {
									fail ("native closure", "invoke argument differs from exact carried code signature");
								}
							}
							var record_groups = NativeTypeMapper.map_function_records (closure_call.struct_arguments);
							if (plan.record_arguments.length != record_groups.length) {
								fail ("native closure", "lost original record argument inventory");
							}
							for (int g = 0; g < record_groups.length; g++) {
								if (!plan.record_arguments[g].same_type (record_groups[g])) {
									fail ("native closure", "record argument differs from original SSA group");
								}
							}
							validate_callable_transfers (closure_call, plan.owned_arguments, "native closure");
							if (plan.borrowed_arguments.length != closure_call.borrowed_arguments.length) {
								fail ("native closure", "lost original borrowed argument inventory");
							}
							for (int a = 0; a < closure_call.borrowed_arguments.length; a++) {
								var loan = closure_call.borrowed_arguments[a];
								var carried = plan.borrowed_arguments[a];
								if (loan.ordinal != carried.ordinal || loan.value.semantic_type.display_name () != carried.type_name || (loan.value.semantic_type is Semantic.ClassType) != carried.is_class) {
									fail ("native closure", "borrowed argument differs from original SSA nominal channel");
								}
							}
						}
					}
					var retained = block.instructions[i] as SsaRetainedOperation;
					if (retained != null) {
						NativeRetainedPlan? plan = null;
						foreach (var candidate in program.retained_operations) {
							if (candidate.caller == f && candidate.block == b && candidate.instruction == i) {
								plan = candidate;
							}
						}
						if (plan == null || plan.action != (int) retained.action || !plan.handle.same_type (NativeTypeMapper.map_type (retained.callee.semantic_type)) || !Semantic.RetainedContracts.accepts (retained.action, retained.callee.semantic_type) || !Semantic.RetainedContracts.valid_action (retained.action) || retained.arguments.length != Semantic.RetainedContracts.arity (retained.action) || retained.result.semantic_type.kind != Semantic.TypeKind.INT) {
							fail ("native retained callback", "missing exact C adapter action, carrier or quiescence operation");
						}
					}
					var shared = block.instructions[i] as SsaSharedOperation;
					if (shared != null) {
						NativeSharedOperationPlan? plan = null;
						foreach (var candidate in program.shared_operations) {
							if (candidate.caller == f && candidate.block == b && candidate.instruction == i) {
								plan = candidate;
							}
						}
						var handle = shared.action == Semantic.SharedAction.ACQUIRE ? shared.result.semantic_type : shared.operand.semantic_type;
						if (plan == null || plan.action != (int) shared.action || !plan.handle.same_type (NativeTypeMapper.map_shared_operation (handle)) || !Semantic.SharedContracts.matches (shared.action, shared.operand.semantic_type, shared.result.semantic_type)) {
							fail ("native shared operation", "missing or mismatched exact retain/upgrade/borrow lifecycle plan");
						}
					}
					var invocation = block.instructions[i] as SsaFunctionValueCall;
					if (invocation != null) {
						NativeFunctionValuePlan? plan = null;
						foreach (var candidate in program.function_values) {
							if (candidate.caller == f && candidate.block == b && candidate.instruction == i) {
								plan = candidate;
							}
						}
						validate_callable_result (invocation, plan == null ? null : plan.result_owner);
						validate_callable_record_result (invocation.struct_result, plan == null ? null : plan.record_result);
						var signature = invocation.callee.semantic_type as Semantic.FunctionValueType;
						if (plan == null || signature == null || !plan.signature.same_type (NativeTypeMapper.map_type (signature)) || ((signature.result_type.kind == Semantic.TypeKind.VOID || signature.result_type.is_struct_storage ()) ? invocation.result != null : invocation.result == null || invocation.result.semantic_type != signature.result_type) || invocation.arguments.length != Semantic.CallableRecordGroups.physical_parameters (signature, invocation.struct_arguments).length) {
							fail ("native function value", "missing or mismatched exact typed indirect-call plan");
						}
						for (int a = 0; a < invocation.arguments.length; a++) {
							if (invocation.arguments[a].semantic_type != Semantic.CallableRecordGroups.physical_parameters (signature, invocation.struct_arguments)[a]) {
								fail ("native function value", "indirect call argument channel differs from exact code signature");
							}
						}
						validate_callable_transfers (invocation, plan.owned_arguments, "native function value");
						if (plan.borrowed_arguments.length != invocation.borrowed_arguments.length) {
							fail ("native function value", "lost exact borrowed argument inventory");
						}
						for (int a = 0; a < invocation.borrowed_arguments.length; a++) {
							var loan = invocation.borrowed_arguments[a];
							var carried = plan.borrowed_arguments[a];
							if (loan.ordinal != carried.ordinal || loan.value.semantic_type.display_name () != carried.type_name || (loan.value.semantic_type is Semantic.ClassType) != carried.is_class) {
								fail ("native function value", "borrowed argument differs from its original SSA nominal channel");
							}
						}
					}
					var call = block.instructions[i] as SsaCallInstruction;
					if (call != null) {
						validate_call (call, program, callees, "function #%d/block #%d/instruction #%d".printf (f, b, i), records);
					}
				}
			}
		}
		// Preserve existing independent native signature/call refusals first.
		// Only opted-in private declarations need the additional access inventory.
		bool has_private = false;
		foreach (var owner in source.classes) {
			foreach (var field in owner.fields) {
				has_private |= field.is_private;
			}
		}
		if (has_private || program.private_accesses.length != 0 || program.private_access_count != 0) {
			var accesses = new GenericArray<SsaPrivateFieldAccess> ();
			try {
				SsaVerifier.verify (source, accesses);
			} catch (SsaError e) {
				fail ("private field correspondence", e.message);
			}
			if (accesses.length != program.private_accesses.length) {
				fail ("private field correspondence", "incomplete access inventory");
			}
			for (int a = 0; a < accesses.length; a++) {
				var source_access = accesses[a];
				var planned = program.private_accesses[a];
				if (source_access.class_ordinal != planned.class_ordinal || source_access.field_ordinal != planned.field_ordinal || source_access.function_ordinal != planned.function_ordinal) {
					fail ("private field correspondence", "exact field/caller access changed");
				}
			}
		}

	}

	private static NativeAbiType argument_type(SsaCallInstruction call, int ordinal, NativeAbiProgram program, HashTable<Semantic.SemanticType, NativeRecordElement>? records) throws NativeAbiError {
		var type = call.arguments[ordinal].semantic_type;
		var result = NativeTypeMapper.map_parameter (type, call.target.parameters[ordinal].pointer_contract, collection_record (type, records), NativeAbiBuilder.move_class_parameter (call.target, ordinal));
		if (call.arguments[ordinal] is SsaEnumArgument) {
			foreach (var plan in program.sum_values) {
				if (plan.identity == ((Semantic.EnumType) type).identity && plan.owning) {
					return new NativeSumType (plan.identity, NativeSumRole.OWNED_TRANSFER);
				}
			}
		}
		return result;
	}

	internal static NativeFunction validate_call(SsaCallInstruction call, NativeAbiProgram program, HashTable<SsaFunction, NativeFunction> callees, string path, HashTable<Semantic.SemanticType, NativeRecordElement>? records = null) throws NativeAbiError {
		var target = call.target;
		var native_function = target == null ? null : callees.lookup (target);
		if (native_function == null || native_function.owner != program) {
			fail (path, "call target has no exact native function in the program");
		}
		var signature = native_function.signature;
		if (call is SsaTaskCreate) {
			if (target.async_body == null || call.result == null || call.result.semantic_type != target.async_body.task_type || call.arguments.length != target.parameters.length || ((SsaTaskCreate) call).checked_admission != (call.exception_result != null) || signature.parameters.length != call.arguments.length) {
				fail (path, "task factory lost exact original body/capture/logical contract");
			}
			for (int a = 0; a < call.arguments.length; a++) {
				if (call.arguments[a].semantic_type != target.parameters[a].semantic_type || !argument_type (call, a, program, records).same_type (signature.parameters[a].abi_type)) {
					fail (path, "task factory capture lost exact physical and semantic channel");
				}
			}
			return native_function;
		}
		if ((signature.exception_plan == null) != (call.exception_result == null)) {
			fail (path, "throwing call requires exact private exception result channel");
		}
		if ((call.enum_result == null) != (signature.sum_result == null) || (call.enum_result != null && (call.result != null || call.enum_result.definition.semantic_type != target.return_type || ((Semantic.EnumType) target.return_type).identity != signature.sum_result.identity))) {
			fail (path, "enum call result lost its exact hidden caller storage destination");
		}
		if ((call.buffer_result == null) != (signature.buffer_result == null) || call.buffer_arguments.length != signature.buffer_parameters.length) {
			fail (path, "buffer call lost its ownership boundary group");
		}
		if (call.buffer_result != null && (call.buffer_result.shape != target.owned_cleanup.buffer_shape || !buffer_matches (call.buffer_result.shape.slice_type, signature.buffer_result, records))) {
			fail (path, "buffer call result element and ownership identity mismatch");
		}
		for (int i = 0; i < call.buffer_arguments.length; i++) {
			var argument = call.buffer_arguments[i];
			var plan = signature.buffer_parameters[i];
			if (argument.parameter != target.buffer_parameters[i] || argument.parameter.first_leaf != plan.first_leaf || argument.pair.shape != argument.parameter.cleanup.buffer_shape) {
				fail (path, "buffer call argument requires exact owner contract");
			}
		}
		if (call.struct_arguments.length != target.struct_parameters.length || signature.struct_parameters.length != target.struct_parameters.length) {
			fail (path, "call requires exact struct argument groups");
		}
		for (int i = 0; i < call.struct_arguments.length; i++) {
			var argument = call.struct_arguments[i];
			var parameter = target.struct_parameters[i];
			var plan = signature.struct_parameters[i];
			if (argument.shape.semantic_type != parameter.shape.semantic_type || argument.source_ordinal != plan.source_ordinal || argument.first_leaf != plan.first_leaf || plan.mode != NativeAbiBuilder.record_mode (argument.shape.mode)) {
				fail (path, "struct call argument requires exact nominal type and physical source grouping");
			}
			validate_struct_leaves (argument.shape, plan.value_plan, path);
		}
		if ((call.struct_result == null) != (signature.struct_result == null) || (call.struct_result == null) != (target.struct_result == null)) {
			fail (path, "struct call result requires exact physical grouping");
		}
		if (call.struct_result != null) {
			if (call.result != null || call.struct_result.shape.semantic_type != target.return_type || call.struct_result.leaves.length != signature.struct_result.leaves.length || signature.struct_result_mode != NativeAbiBuilder.record_mode (call.struct_result.shape.mode)) {
				fail (path, "struct call result lost exact nominal type or complete leaf set");
			}
			validate_struct_leaves (call.struct_result.shape, signature.struct_result, path);
			for (int i = 0; i < call.struct_result.leaves.length; i++) {
				if (call.struct_result.leaves[i].semantic_type != call.struct_result.shape.leaves[i].semantic_type) {
					fail (path, "struct call result leaf changed its exact semantic type");
				}
			}
		}
		if ((signature.object_result == null) != (call.candidate_storage == null && call.result_storage == null) || (call.candidate_storage != null && call.result_storage != null)) {
			fail (path, "owned result call requires exactly one candidate storage channel");
		}
		var receiver = target.implicit_receiver;
		if ((receiver == null) != (signature.receiver == null) || (receiver == null) != (call.receiver == null) || (receiver != null && (call.receiver.semantic_type != receiver.contract || signature.receiver.scalar_type != NativeScalarType.PTR))) {
			fail (path, "method call requires exact semantic receiver and physical first PTR channel");
		}
		if (call.arguments.length != signature.parameters.length || call.arguments.length != target.parameters.length) {
			fail (path, "call argument count does not match native parameter channels");
		}
		for (int a = 0; a < call.arguments.length; a++) {
			// Pointer erasure cannot turn distinct classes (or other PTR types) into compatible arguments.
			if ((target.parameters[a].semantic_type is Semantic.ClassType || call.arguments[a].semantic_type is Semantic.ClassType) && call.arguments[a].semantic_type != target.parameters[a].semantic_type) {
				fail (path + "/argument #%d".printf (a), "object argument requires the exact semantic ClassType parameter");
			}
			if ((target.parameters[a].semantic_type is Semantic.StringType || call.arguments[a].semantic_type is Semantic.StringType) && call.arguments[a].semantic_type != target.parameters[a].semantic_type) {
				fail (path, "text argument requires exact canonical StringType identity");
			}
			// Slice groups deliberately erase element identity physically.
			// Exact compatibility still comes from the semantic signature.
			if ((target.parameters[a].semantic_type is Semantic.SliceType || call.arguments[a].semantic_type is Semantic.SliceType) && call.arguments[a].semantic_type != target.parameters[a].semantic_type) {
				fail (path + "/argument #%d".printf (a), "slice argument requires the exact semantic parameter type");
			}
			NativeAbiType expected = argument_type (call, a, program, records);
			if (!expected.same_type (signature.parameters[a].abi_type)) {
				fail (path + "/argument #%d".printf (a), "call argument type does not match native parameter channel");
			}
		}
		if ((call.result == null) != (signature.result == null)) {
			fail (path + "/result", "call result presence does not match native result channel");
		}
		if (call.result != null && !NativeTypeMapper.map_result (call.result.semantic_type, target.result_contract).abi_type.same_type (signature.result.abi_type)) {
			fail (path + "/result", "call result type does not match native result channel");
		}
		return native_function;
	}
}
}
