// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Ssa;

namespace Astra.Backend.LLVM {
// Temporary construction record. It never escapes into the artifact.
internal class LlvmFunctionBinding : Object {
	internal NativeConstructorUnwindPlan? constructor_unwind;
	internal NativeLazyCache? lazy_cache;
	internal LlvmFunctionBinding? lazy_body;
	internal LlvmAsyncFrameBinding? async_frame;
	internal LlvmScopedImportedTask? scoped_task_import;
	internal CApi.TypeRef task_factory_type;
	internal CApi.ValueRef task_factory;
	internal CApi.ValueRef task_checked_factory;
	internal NativeSignature signature;
	internal CApi.TypeRef type;
	internal CApi.ValueRef value;

	internal LlvmFunctionBinding (NativeSignature signature, CApi.TypeRef type, CApi.ValueRef value) {
		this.signature = signature;
		this.type = type;
		this.value = value;
	}
}

public class LlvmLowering : Object {
	// fastcc is a backend realization, not a lasting native ABI promise.
	internal const uint CALL_CONVENTION = CApi.CallConv.FAST;

	private static void record_c_floating(LlvmModuleArtifact artifact, CAbiSignature signature) {
		artifact.requires_c_text |= signature.has_text;
		artifact.requires_c_buffer |= signature.has_buffer;
		artifact.requires_c_wide |= signature.has_wide;
		artifact.requires_c_bool |= signature.has_bool;
		if (signature.result != null && (signature.result.scalar_type == CAbiScalarType.F32 || signature.result.scalar_type == CAbiScalarType.F64)) {
			artifact.requires_c_floating = true;
		}
		foreach (var parameter in signature.parameters) {
			if (parameter.text == null && (parameter.scalar_type == CAbiScalarType.F32 || parameter.scalar_type == CAbiScalarType.F64)) {
				artifact.requires_c_floating = true;
			}
		}
	}

	public static LlvmModuleArtifact lower(SsaProgram ssa, NativeAbiProgram nabi, CAbiProgram cabi, SsaFunction? entry = null, NativeProgramEntryPlan? entry_plan = null, bool debug = false, bool optimized = false, LlvmNativeModulePlan? modules = null, string selected_target = "host") throws LlvmError {
		if (nabi.c_bool_policies.length != 0 && selected_target != "host") {
			throw new LlvmError.TARGET ("C99 bool requires the selected Linux x64 C ABI target");
		}
		foreach (var owner in ssa.classes) {
			if (owner.foreign_export != null && owner.foreign_export.active (Astra.Source.ForeignClassPolicy.GOBJECT) && selected_target != "host") {
				throw new LlvmError.TARGET ("GObject export requires its admitted hosted Linux x64 target");
			}
		}
		foreach (var handle in ssa.handles) {
			if (handle.c_import != null && handle.c_import.gobject != null && handle.c_import.api.active_personalities != 0 && selected_target != "host") {
				throw new LlvmError.TARGET ("GObject import requires its admitted hosted Linux x64 target");
			}
		}
		foreach (var imported in ssa.c_functions) {
			if (imported.metadata.import_policy == Astra.Source.DeclarationPolicyId.GOBJECT_IMPORT && selected_target != "host") {
				throw new LlvmError.TARGET ("GObject import requires its admitted hosted Linux x64 target");
			}
		}
		if (selected_target != LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
			foreach (var handle in ssa.handles) {
				if (handle.com_import != null || handle.c_import != null && handle.c_import.com != null && handle.c_import.api.active_personalities != 0) {
					throw new LlvmError.TARGET ("COM import requires the admitted Windows x64 target");
				}
			}
			foreach (var owner in ssa.classes) {
				if (owner.foreign_export != null && owner.foreign_export.active (Astra.Source.ForeignClassPolicy.COM)) {
					throw new LlvmError.TARGET ("COM export requires the admitted Windows x64 target");
				}
			}
		}
		try {
			SsaVerifier.verify (ssa);
			NativeAbiVerifier.verify (nabi);
			CAbiVerifier.verify (cabi);
			if (modules != null) {
				modules.validate (ssa, nabi);
			} else {
				foreach (var function in ssa.functions) {
					if (function.module_import_symbol != null || function.native_declaration != null || function.name_span.file.native_interface) {
						throw new LlvmError.INVALID_INPUT ("native imports require their exact external module plan");
					}
				}
			}
			if (ssa.functions.length != nabi.functions.length) {
				throw new LlvmError.INVALID_INPUT ("internal LLVM input error: SSA/NABI function counts differ");
			}
			var correspondence = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
			for (int f = 0; f < ssa.functions.length; f++) {
				correspondence.insert (ssa.functions[f], nabi.functions[f]);
			}
			// Verified ordinals supply correspondence; debug names never do.
			NativeAbiValidator.validate_ssa_calls (ssa, nabi, correspondence);
			if (ssa.c_functions.length != cabi.functions.length) {
				throw new LlvmError.INVALID_INPUT ("internal LLVM input error: SSA/CABI import counts differ");
			}
			var c_correspondence = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
			for (int c = 0; c < ssa.c_functions.length; c++) {
				c_correspondence.insert (ssa.c_functions[c], cabi.functions[c]);
			}
			CAbiValidator.validate_ssa_calls (ssa, cabi, c_correspondence);
			uint foreign_cleanup_count = 0;
			foreach (var cleanup in ssa.cleanups) {
				if (!cleanup.is_object && !cleanup.is_buffer && cleanup.shared_type == null && cleanup.closure_type == null) {
					foreign_cleanup_count++;
				}
			}
			if (foreign_cleanup_count != cabi.cleanups.length) {
				throw new LlvmError.INVALID_INPUT ("internal LLVM input error: SSA/CABI cleanup counts differ");
			}
			var cleanup_correspondence = new HashTable<SsaCleanupContract, CAbiCleanupFunction> (direct_hash, direct_equal);
			int foreign_ordinal = 0;
			for (int c = 0; c < ssa.cleanups.length; c++) {
				if (!ssa.cleanups[c].is_object && !ssa.cleanups[c].is_buffer && ssa.cleanups[c].shared_type == null && ssa.cleanups[c].closure_type == null) {
					cleanup_correspondence.insert (ssa.cleanups[c], cabi.cleanups[foreign_ordinal++]);
				}
			}
			CAbiValidator.validate_cleanups (ssa, cabi, cleanup_correspondence);
			CAbiValidator.validate_exports (ssa, nabi, cabi, correspondence);
			var continuation_plans = new HashTable<SsaContinuationRegion, NativeContinuationRegionPlan> (direct_hash, direct_equal);
			int continuation_index = 0;
			for (int f = 0; f < ssa.functions.length; f++) {
				foreach (var block in ssa.functions[f].blocks) {
					for (int i = 0; i < block.instructions.length; i++) {
						var region = block.instructions[i] as SsaContinuationRegion;
						if (region == null) {
							continue;
						}
						if (continuation_index >= nabi.continuations.length) {
							throw new LlvmError.INVALID_INPUT ("missing native continuation plan");
						}
						var plan = nabi.continuations[continuation_index++];
						NativeContinuationBuilder.validate (plan, ssa, nabi, f, block.ordinal, i);
						continuation_plans.insert (region, plan);
					}
				}
			}
			if (continuation_index != nabi.continuations.length) {
				throw new LlvmError.INVALID_INPUT ("stale native continuation region plan");
			}
			NativeProgramEntryPlan? selected_plan = entry_plan;
			if (entry == null && selected_plan != null) {
				throw new LlvmError.INVALID_INPUT ("entry plan requires an exact selected source identity");
			}
			if (entry != null) {
				if (selected_plan == null) {
					selected_plan = NativeEntryBuilder.build (ssa, nabi, entry);
				} else {
					NativeEntryBuilder.validate (selected_plan, ssa, nabi, entry);
				}
			}
			var artifact = new LlvmModuleArtifact ();
			artifact.selected_target = selected_target;
			if (selected_target == LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
				if (entry != null || entry_plan != null) {
					throw new LlvmError.INVALID_INPUT ("Windows interop requires a separately linked object without entry adaptation");
				}
				artifact.admit_windows_interop (ssa, modules != null);
			}
			artifact.semantic_optimizations = LlvmSemanticOptimizations.enabled (optimized);
			if (debug) {
				artifact.debug_info = new LlvmDebugInfo (artifact, optimized);
			}
			artifact.entry_kind = selected_plan == null ? NativeEntryKind.ZERO_ARGUMENTS : selected_plan.kind;
			var types = new LlvmTypeMapper (artifact.context);
			var text = new LlvmTextLowering (artifact, types);
			var structs = new LlvmStructRegistry (artifact, types, ssa, nabi);
			var c_records = new GenericArray<CAbiRecordPlan> ();
			foreach (var imported in cabi.functions) {
				foreach (var parameter in imported.signature.parameters) {
					if (parameter.record != null) {
						c_records.add (parameter.record);
					}
				}
				if (imported.signature.result != null && imported.signature.result.record != null) {
					c_records.add (imported.signature.result.record);
				}
			}
			foreach (var exported in cabi.exports) {
				foreach (var parameter in exported.signature.parameters) {
					if (parameter.record != null) {
						c_records.add (parameter.record);
					}
				}
				if (exported.signature.result != null && exported.signature.result.record != null) {
					c_records.add (exported.signature.result.record);
				}
			}
			foreach (var record in c_records) {
				if (artifact.c_record_target == null) {
					artifact.c_record_target = new LlvmTargetMachineArtifact ();
					LlvmTargetMachineArtifact.qualify_c_systems (artifact.c_record_target.triple, CApi.pointer_size (artifact.c_record_target.enum_target_data (artifact)));
				}
				SsaStruct? declaration = null;
				foreach (var structure in ssa.structs) {
					if (structure.name == record.name) {
						declaration = structure;
						break;
					}
				}
				if (declaration == null) {
					throw new LlvmError.INVALID_INPUT ("C record lost exact SSA declaration");
				}
				var binding = new LlvmCRecordLayoutBinding (record, structs.lookup (declaration), artifact.context);
				binding.verify (artifact.c_record_target.enum_target_data (artifact));
				artifact.c_records.add (binding);
			}
			foreach (var element in nabi.record_elements) {
				var structure = ssa.structs[element.struct_ordinal];
				var binding = new LlvmRecordLayoutBinding (element, structs.lookup (structure));
				foreach (var cleanup in ssa.cleanups) {
					if (cleanup.is_buffer && cleanup.buffer_type.element_type == structure.semantic_type) {
						binding.allocated = true;
					}
				}
				foreach (var function in ssa.functions) {
					foreach (var storage in function.storage) {
						var array = storage.semantic_type as Semantic.ArrayType;
						if (array != null && array.element_type == structure.semantic_type) {
							binding.fixed_count = uint.max (binding.fixed_count, (uint) array.length);
						}
					}
				}
				artifact.record_layouts.add (binding);
			}
			var sums = nabi.sum_values.length == 0 ? null : new LlvmSumRegistry (artifact, types, nabi.sum_values);
			var functions = new HashTable<SsaFunction, LlvmFunctionBinding> (direct_hash, direct_equal);
			var lazy_bodies = new HashTable<SsaFunction, LlvmFunctionBinding> (direct_hash, direct_equal);
			var native_functions = new HashTable<NativeFunction, LlvmFunctionBinding> (direct_hash, direct_equal);
			var continuation_targets = new GenericArray<LlvmFunctionBinding> ();
			var async_plans = new HashTable<SsaFunction, NativeAsyncFramePlan> (direct_hash, direct_equal);
			foreach (var plan in nabi.async_frames) {
				if (plan.function_ordinal >= ssa.functions.length) {
					throw new LlvmError.INVALID_INPUT ("async plan has no exact source function");
				}
				var source = ssa.functions[plan.function_ordinal];
				NativeAsyncFrameBuilder.validate (plan, source, ssa);
				async_plans.insert (source, plan);
			}
			foreach (var source in ssa.functions) {
				if ((source.async_body == null || source.native_declaration != null) != !async_plans.contains (source)) {
					throw new LlvmError.INVALID_INPUT ("async declaration/frame-plan membership mismatch");
				}
			}
			for (int f = 0; f < nabi.functions.length; f++) {
				var function = nabi.functions[f];
				var type = types.signature (function.signature);
				string symbol = (function.kind == NativeCallableKind.PROPERTY_GETTER || function.kind == NativeCallableKind.PROPERTY_SETTER) ? "astra.prop%s.%s.%d.%d".printf (function.kind == NativeCallableKind.PROPERTY_GETTER ? "get" : "set", function.declaring_type_is_class ? "class" : "struct", function.declaring_type_ordinal, function.property_ordinal) : function.kind == NativeCallableKind.CONSTRUCTOR ? "astra.ctor.%d".printf (function.declaring_type_ordinal) : function.kind == NativeCallableKind.DESTRUCTOR ? "astra.dtor.%d".printf (function.declaring_type_ordinal) : function.signature.receiver == null ? "astra.fn.%d".printf (f) : "astra.%smethod.%d.%d".printf (function.declaring_type_is_class ? "class." : "", function.declaring_type_ordinal, function.method_ordinal);
				var async_plan = async_plans.lookup (ssa.functions[f]);
				string? module_symbol = modules == null ? null : modules.symbol_for (ssa.functions[f]);
				if (module_symbol != null) {
					symbol = module_symbol;
				}
				var storage_types = new CApi.TypeRef[ssa.functions[f].storage.length];
				for (int s = 0; s < storage_types.length; s++) {
					var slot = ssa.functions[f].storage[s];
					storage_types[s] = slot.structure == null ? types.storage_type(slot.semantic_type) : structs.lookup (slot.structure);
				}
				LlvmAsyncFrameBinding? frame = async_plan == null ? null : new LlvmAsyncFrameBinding (artifact, types, async_plan, function.signature, storage_types, sums, module_symbol);
				if (frame != null) {
					frame.bind_scoped_captures (function, nabi, structs);
					if (frame.scoped_captures != null) {
						artifact.bind_scoped_coroutine (frame);
					}
				}
				bool imported_task = ssa.functions[f].async_body != null && ssa.functions[f].native_declaration != null;
				if (imported_task) {
					type = LlvmAsyncFrameBinding.factory_signature (types, function.signature);
				}
				var value = frame == null ? CApi.add_function(artifact.module, symbol, type) : frame.resume;
				if (frame == null) {
					CApi.set_linkage (value, module_symbol == null ? CApi.Linkage.INTERNAL : CApi.Linkage.EXTERNAL);
					CApi.set_function_call_conv (value, CALL_CONVENTION);
				} else {
					type = frame.resume_type;
					artifact.async_frames.add (frame);
				}
				if (module_symbol != null) {
					artifact.native_modules.add (new LlvmNativeModuleBinding (frame == null ? value : frame.factory, frame == null ? type : frame.factory_type, module_symbol, modules.is_import (ssa.functions[f])));
				}
				var binding = new LlvmFunctionBinding (function.signature, type, value);
				binding.async_frame = frame;
				binding.lazy_cache = function.lazy_cache;
				binding.constructor_unwind = function.constructor_unwind;
				if (frame != null) {
					binding.task_factory = frame.factory;
					binding.task_checked_factory = frame.checked_factory;
					binding.task_factory_type = frame.factory_type;
				} else if (imported_task) {
					binding.task_factory = value;
					binding.task_factory_type = type;
					binding.task_checked_factory = CApi.add_function (artifact.module, symbol + "_checked", type);
					CApi.set_linkage (binding.task_checked_factory, CApi.Linkage.EXTERNAL);
					CApi.set_function_call_conv (binding.task_checked_factory, CALL_CONVENTION);
					artifact.native_modules.add (new LlvmNativeModuleBinding (binding.task_checked_factory, type, symbol + "_checked", true));
					binding.scoped_task_import = artifact.bind_scoped_imported_task (function, nabi, structs, value, binding.task_checked_factory, type, symbol);
				}
				continuation_targets.add (binding);
				native_functions.insert (function, binding);
				functions.insert (ssa.functions[f], binding);
				artifact.bind_class_lifecycle (function, value);
				if (function.lazy_cache != null && !function.lazy_cache.is_owned) {
					binding.lazy_body = LlvmLazyProperties.declare_body (artifact, binding, function.lazy_cache);
					lazy_bodies.insert (ssa.functions[f], binding.lazy_body);
				}
			}
			// Resolve lifecycle roles only after all actual declarations exist. Native
			// module symbols need not have the private local spelling or source order.
			for (int f = 0; f < nabi.functions.length; f++) {
				var function = nabi.functions[f];
				var binding = functions.lookup (ssa.functions[f]);
				if (binding.async_frame != null || ssa.functions[f].async_body != null) {
					continue;
				}
				if (ssa.functions[f].native_declaration == null && function.lazy_cache == null) {
					artifact.bind_scoped_borrow (binding.value, binding.type, function, nabi, structs);
					artifact.bind_scoped_owned_inputs (binding.value, binding.type, function, nabi, structs);
				} else if (ssa.functions[f].native_declaration != null) {
					artifact.bind_scoped_imported_values (binding.value, binding.type, function, nabi, structs, modules.symbol_for (ssa.functions[f]));
				}
			}
			var classes = new LlvmClassRuntime (artifact, types, ssa, functions, structs, nabi, modules);
			// Never let LLVM silently rename a boundary symbol on collision.
			foreach (var imported in cabi.functions) {
				validate_external_symbol (artifact, imported.external_symbol, entry != null);
			}
			foreach (var exported in cabi.exports) {
				validate_external_symbol (artifact, exported.external_symbol, entry != null);
			}
			foreach (var cleanup in cabi.cleanups) {
				validate_external_symbol (artifact, cleanup.external_symbol, entry != null);
			}
			var c_types = new LlvmCTypeMapper (artifact.context);
			var cleanup_functions = new HashTable<CAbiCleanupFunction, LlvmCFunctionBinding> (direct_hash, direct_equal);
			foreach (var cleanup in cabi.cleanups) {
				var type = c_types.signature (cleanup.signature);
				var value = CApi.add_function (artifact.module, cleanup.external_symbol, type);
				CApi.set_linkage (value, CApi.Linkage.EXTERNAL);
				CApi.set_function_call_conv (value, CApi.CallConv.C);
				var binding = new LlvmCFunctionBinding (type, value, cleanup.external_symbol);
				foreach (var root in nabi.class_imports) {
					if (root.cleanup_symbol () == cleanup.external_symbol) {
						binding.define_class_import (artifact, types, root);
					}
				}
				cleanup_functions.insert (cleanup, binding);
				artifact.c_imports.add (binding);
			}
			var c_functions = new HashTable<CAbiFunction, LlvmCFunctionBinding> (direct_hash, direct_equal);
			foreach (var imported in cabi.functions) {
				var type = c_types.signature (imported.signature);
				var value = CApi.add_function (artifact.module, imported.external_symbol, type);
				CApi.set_linkage (value, CApi.Linkage.EXTERNAL);
				CApi.set_function_call_conv (value, CApi.CallConv.C);
				c_types.attributes (imported.signature, value);
				var binding = new LlvmCFunctionBinding (type, value, imported.external_symbol);
				if (imported.metadata.device != null) {
					binding.define_device (artifact, imported.metadata.device);
				}
				binding.record_record_attributes (imported.signature, c_types, value);
				if (imported.signature.callback != null) {
					int ordinal = imported.signature.callback.native_function_ordinal;
					if (ordinal < 0 || ordinal >= nabi.functions.length) {
						throw new LlvmError.INVALID_INPUT ("C callback lost exact native function ordinal");
					}
					var callback = new LlvmCCallbackBinding (artifact, native_functions.lookup (nabi.functions[ordinal]), imported.ordinal);
					binding.callback_value = callback.value;
					artifact.c_callbacks.add (callback);
				}
				c_functions.insert (imported, binding);
				artifact.c_imports.add (binding);
			}
			foreach (var exported in cabi.exports) {
				var target = native_functions.lookup (nabi.functions[exported.native_function_ordinal]);
				artifact.c_exports.add (LlvmCExportBinding.create (artifact, c_types, exported, target));
			}
			if (entry != null) {
				var binding = functions.lookup (entry);
				if (binding == null) {
					throw new LlvmError.INVALID_INPUT ("internal LLVM entry error: selected identity must belong to this program and have signature int ()");
				}
				artifact.entry_function = binding.value;
				artifact.entry_type = binding.type;
				if (artifact.debug_info != null) {
					artifact.debug_info.prepare_launch (entry);
				}
			}
			// All callees exist before any body, including recursive callees.
			bool policy_functions = false;
			foreach (var owner in nabi.classes) {
				policy_functions = policy_functions || owner.allocation_policy != null || owner.foreign_export != null;
			}
			for (int f = 0; f < ssa.functions.length; f++) {
				if (modules != null && modules.is_import (ssa.functions[f])) {
					continue;
				}
				if (nabi.functions[f].foreign_signal != null) {
					var signal = nabi.functions[f].foreign_signal;
					int signal_plans = 0;
					foreach (var physical_signal in cabi.foreign_signals) {
						if (physical_signal.native_function == f && physical_signal.binding.identity () == signal.binding.identity () && physical_signal.valid (cabi)) {
							signal_plans++;
						}
					}
					if (signal_plans != 1) {
						throw new LlvmError.LOWERING ("native signal lost its exact independent C ABI plan");
					}
					if (!(ssa.functions[f].entry.terminator is SsaForeignSignalReturn) || ((SsaForeignSignalReturn) ssa.functions[f].entry.terminator).binding.identity () != signal.binding.identity ()) {
						throw new LlvmError.LOWERING ("native signal lost exact Source/native member correspondence");
					}
					LlvmForeignSignals.lower (artifact, types, signal, native_functions.lookup (nabi.functions[f]), structs, nabi, ((SsaMethod) ssa.functions[f]).declaring_type as SsaClass);
					continue;
				}
				if (nabi.functions[f].foreign_import != null) {
					CAbiForeignImport? physical = null;
					foreach (var plan in cabi.class_imports) {
						if (plan.native_function == f) {
							physical = plan;
						}
					}
					var imported = nabi.functions[f].foreign_import;
					if (physical == null || physical.binding.identity () != imported.binding.identity () || physical.error_factory != imported.error_factory || !(ssa.functions[f].entry.terminator is SsaForeignReturn)) {
						throw new LlvmError.LOWERING ("CImport lost exact source/native/physical correspondence");
					}
					var resource = nabi.functions[f].signature.resource_result;
					LlvmCFunctionBinding? cleanup = null;
					foreach (var plan in cabi.cleanups) {
						if (resource != null && plan.external_symbol == resource.cleanup_symbol) {
							cleanup = cleanup_functions.lookup (plan);
						}
					}
					var parameter_cleanups = new LlvmCFunctionBinding?[imported.binding.member.parameter_count];
					for (uint p = 0; p < imported.binding.member.parameter_count; p++) {
						var channel = imported.binding.member.parameter (p);
						if (!channel.value_type.object_handle () || channel.transfer != Source.ForeignTransfer.OWN) {
							continue;
						}
						foreach (var root in nabi.class_imports) {
							if (root.api.native_origin != channel.value_type.nominal_origin || root.object_kind != channel.value_type.kind) {
								continue;
							}
							foreach (var plan in cabi.cleanups) {
								if (plan.external_symbol == root.cleanup_symbol ()) {
									parameter_cleanups[p] = cleanup_functions.lookup (plan);
								}
							}
						}
					}
					LlvmForeignImports.lower (artifact, types, text, nabi.functions[f].span, physical, native_functions.lookup (nabi.functions[f]), native_functions.lookup (nabi.functions[imported.error_factory]), cleanup, parameter_cleanups);
					continue;
				}
				var body_binding = lazy_bodies.lookup (ssa.functions[f]) ?? native_functions.lookup (correspondence.lookup (ssa.functions[f]));
				var lowering = new LlvmFunctionLowering (artifact, types, body_binding, functions, c_correspondence, c_functions, structs, cleanup_correspondence, cleanup_functions, text, classes);
				lowering.sum_registry = sums;
				lowering.scoped_plans = nabi.functions[f].scoped_backings;
				lowering.continuations = continuation_plans;
				lowering.continuation_targets = continuation_targets;
				var cache = nabi.functions[f].lazy_cache;
				if (cache == null || !cache.is_owned) {
					lowering.lower (ssa.functions[f]);
				}
				if (cache != null) {
					LlvmLazyProperties.lower_gate (artifact, types, structs, ssa.classes[cache.class_ordinal], cache, functions.lookup (ssa.functions[f]), cache.is_owned ? functions.lookup (ssa.functions[cache.factory_ordinal]) : body_binding);
				}
				if ((policy_functions || nabi.shared_operations.length != 0 || nabi.closures.length != 0 || nabi.abi_version == NativeAbiVersion.NATIVE_EXCEPTIONS_V14 || nabi.abi_version == NativeAbiVersion.OWNER_SLOTS_V15) && ssa.functions[f].async_body == null) {
					var binding = native_functions.lookup (correspondence.lookup (ssa.functions[f]));
					artifact.class_functions.add (new LlvmClassFunctionBinding (binding.value, binding.type));
				}
				if (ssa.functions[f].enum_slots.length != 0) {
					bool owning = false;
					foreach (var slot in ssa.functions[f].enum_slots) {
						if (sums.lookup (slot.definition.semantic_type.identity).plan.owning) {
							owning = true;
						}
					}
					artifact.sum_sequences.add (new LlvmSumSequence (native_functions.lookup (correspondence.lookup (ssa.functions[f])).value, owning));
				}
			}
			foreach (var adapter in cabi.class_adapters) {
				if (adapter.policy.active_personalities == 0) {
					continue;
				}
				var owner = ssa.classes[adapter.native_class];
				if (owner.name_span.file.native_interface) {
					continue;
				}
				new LlvmForeignClasses (artifact, types, structs, classes, text, owner, nabi.classes[owner.ordinal], adapter, functions, cleanup_functions).lower (nabi);
			}
			LlvmLazyProperties.retain_construction_order (artifact);
			artifact.requires_text_slices = types.uses_text_slices || (selected_plan != null && selected_plan.kind == NativeEntryKind.TEXT_ARGUMENTS);
			artifact.requires_binary32 = types.uses_f32;
			artifact.requires_binary64 = types.uses_f64;
			artifact.requires_native_wide = types.uses_wide;
			// Profiles are supersets; qualify each actual channel independently.
			foreach (var imported in cabi.functions) {
				record_c_floating (artifact, imported.signature);
			}
			foreach (var exported in cabi.exports) {
				record_c_floating (artifact, exported.signature);
			}
			artifact.requires_vectors = types.uses_vectors;
			if (artifact.debug_info != null) {
				artifact.debug_info.finish ();
			}
			artifact.seal_scoped_borrows ();
			for (int f = 0; f < nabi.functions.length; f++) {
				var source = nabi.functions[f];
				var binding = native_functions.lookup (source);
				uint flags = artifact.semantic_optimizations && source.lazy_cache == null && source.effect_facts != null ? source.effect_facts.flags & 7 : 0;
				artifact.effects.add (new LlvmEffectBinding (artifact, binding.value, flags, source.scoped_backings.length != 0 || artifact.semantic_optimizations && (source.stack_objects.length != 0 || source.exact_calls.length != 0 || source.shared_elisions.length != 0), artifact.semantic_optimizations && source.lazy_cache == null ? source.effect_facts : null, source.signature.receiver != null));
			}
			artifact.verify ();
			return artifact;
		} catch (SsaError error) {
			throw new LlvmError.INVALID_INPUT ("internal LLVM input error: %s", error.message);
		} catch (CAbiError error) {
			throw new LlvmError.INVALID_INPUT ("internal LLVM input error: %s", error.message);
		} catch (NativeAbiError error) {
			throw new LlvmError.INVALID_INPUT ("internal LLVM input error: %s", error.message);
		}
	}

	private static void validate_external_symbol(LlvmModuleArtifact artifact, string symbol, bool executable) throws LlvmError {
		if (executable && symbol == "main") {
			throw new LlvmError.INVALID_INPUT ("C boundary symbol `main` conflicts with the executable entry wrapper");
		}
		if ((void*) CApi.named_function (artifact.module, symbol) != null) {
			throw new LlvmError.INVALID_INPUT ("internal LLVM input error: C external symbol '%s' conflicts with a native implementation", symbol);
		}
	}
}
}
