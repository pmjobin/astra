// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Backend.LLVM {
// LLVM caches StructLayout by Type* in TargetData. Keep each cache inside the
// module that owns those types, and destroy it before that module's context.
internal class LlvmTypeLayout : Object {
	internal CApi.TargetDataRef data;
	internal LlvmTypeLayout (CApi.TargetMachineRef machine) {
		data = CApi.create_target_data_layout (machine);
	}
	~LlvmTypeLayout () {
		CApi.dispose_target_data (data);
	}
}

public class LlvmTargetMachineArtifact : Object {
	private static size_t initialization;
	private static size_t cross_initialization;
	private CApi.TargetMachineRef machine;
	private CApi.TargetDataRef data;
	internal CApi.TargetDataRef enum_target_data(LlvmModuleArtifact artifact) {
		var cached = artifact.type_layouts.lookup (layout);
		if (cached == null) {
			cached = new LlvmTypeLayout (machine);
			artifact.type_layouts.insert (layout, cached);
		}
		return cached.data;
	}
	public uint pointer_bytes { get { return CApi.pointer_size (data); } }
	private string host_triple;
	private string layout;
	private int optimization_level;
	public string triple { get { return host_triple; } }
	public string data_layout { get { return layout; } }
	public const string PC_BARE_METAL = "x86_64-none-elf";
	public const string WINDOWS_INTEROP = "x86_64-w64-windows-gnu";
	public bool pc_bare_metal { get { return triple == PC_BARE_METAL; } }
	// Empty CPU selects LLVM's target default, without host feature tuning.
	public const string CPU = "";
	public const string FEATURES = "";

	private static void initialize_native() throws LlvmError {
		if (Once.init_enter (&initialization)) {
			size_t result = CApi.initialize_native_target () != 0 ? 2 : CApi.initialize_native_asm_printer () != 0 ? 3 : CApi.initialize_native_asm_parser () != 0 ? 4 : 1;
			Once.init_leave (&initialization, result);
		}
		if (initialization != 1) {
			throw new LlvmError.TARGET ("error: LLVM native %s initialization failed", initialization == 2 ? "target" : initialization == 3 ? "assembly printer" : "assembly parser");
		}
	}

	internal static CApi.TargetRef lookup_target(string triple) throws LlvmError {
		CApi.TargetRef target;
		char* message = null;
		int failed = CApi.target_from_triple (triple, out target, out message);
		string diagnostic = take_message (message);
		if (failed != 0) {
			throw new LlvmError.TARGET ("error: LLVM host target lookup failed for '%s': %s", triple, diagnostic);
		}
		return target;
	}

	internal static string take_message(char* message) {
		string result = message == null ? "no diagnostic" : (string) message;
		if (message != null) {
			CApi.dispose_message (message);
		}
		return result;
	}

	public LlvmTargetMachineArtifact (int optimization_level = 0, string? selected_target = null) throws LlvmError {
		if (optimization_level < 0 || optimization_level > 2) {
			throw new LlvmError.INVALID_INPUT ("optimization level must be 0, 1 or 2");
		}
		this.optimization_level = optimization_level;
		initialize_native ();
		host_triple = take_message (CApi.default_target_triple ());
		if (selected_target != null && selected_target != "host" && selected_target != host_triple) {
			if (selected_target != "aarch64-none-elf" && selected_target != PC_BARE_METAL && selected_target != WINDOWS_INTEROP) {
				throw new LlvmError.TARGET ("unsupported target '%s'; supported selections are host, x86_64-none-elf, aarch64-none-elf and x86_64-w64-windows-gnu object-only", selected_target);
			}
			if (Once.init_enter (&cross_initialization)) {
				CApi.initialize_all_target_infos ();
				CApi.initialize_all_targets ();
				CApi.initialize_all_target_mcs ();
				CApi.initialize_all_asm_printers ();
				CApi.initialize_all_asm_parsers ();
				Once.init_leave (&cross_initialization, 1);
			}
			host_triple = selected_target;
		}
		var target = lookup_target (triple);
		var level = optimization_level == 0 ? CApi.CodeGenOptLevel.NONE : optimization_level == 1 ? CApi.CodeGenOptLevel.LESS : CApi.CodeGenOptLevel.DEFAULT;
		machine = CApi.create_target_machine (target, triple, CPU, FEATURES, level, CApi.RelocMode.PIC, CApi.CodeModel.DEFAULT);
		if ((void*) machine == null) {
			throw new LlvmError.TARGET ("error: LLVM host target-machine creation failed for '%s'", triple);
		}
		data = CApi.create_target_data_layout (machine);
		layout = take_message (CApi.copy_target_data_string (data));
	}

	~LlvmTargetMachineArtifact () {
		if ((void*) data != null) {
			CApi.dispose_target_data (data);
		}
		if ((void*) machine != null) {
			CApi.dispose_target_machine (machine);
		}
	}

	// Explicit C representation qualification, separate from native execution.
	// LLVM metadata describes LLVM floats, not every platform C float/double.
	// Extend this gate only with evidence for the platform C binary32/binary64 ABI.
	internal static void qualify_c_floating(string target_triple) throws LlvmError {
		if (!(target_triple.has_prefix ("x86_64-") && target_triple.contains ("-linux-"))) {
			throw new LlvmError.TARGET ("error: C float/double binary32/binary64 representations are not qualified for target '%s'", target_triple);
		}
	}

	internal static void qualify_c_text(string target_triple) throws LlvmError {
		if (!(target_triple.has_prefix ("x86_64-") && target_triple.contains ("-linux-"))) {
			throw new LlvmError.TARGET ("error: C utf8-i32 text views are not qualified for target '%s'", target_triple);
		}
	}

	internal static void qualify_c_systems(string target_triple, uint pointer_bytes) throws LlvmError {
		if (!(target_triple.has_prefix ("x86_64-") && target_triple.has_suffix ("-linux-gnu")) || pointer_bytes != 8) {
			throw new LlvmError.TARGET ("C counted bytes and wide integers require the qualified x86-64 Linux LP64 target");
		}
	}

	internal static void qualify_record_elements(string target_triple, uint pointer_bytes) throws LlvmError {
		if (!(target_triple.has_prefix ("x86_64-") && target_triple.contains ("-linux-")) || pointer_bytes != 8) {
			throw new LlvmError.TARGET ("record collection storage is qualified only for x86-64 Linux with 64-bit addresses");
		}
	}

	private void qualify_record_layouts(LlvmModuleArtifact artifact) throws LlvmError {
		var data = enum_target_data (artifact);
		if (artifact.record_layouts.length == 0) {
			return;
		}
		if (!(triple == WINDOWS_INTEROP && artifact.windows_declarations && CApi.pointer_size (data) == 8)) {
			qualify_record_elements (triple, CApi.pointer_size (data));
		}
		var layouts = new HashTable<NativeAbi.NativeRecordElement, NativeAbi.NativeRecordLayout> (direct_hash, direct_equal);
		foreach (var binding in artifact.record_layouts) {
			try {
				binding.layout = NativeAbi.NativeRecordLayout.x86_64 (binding.element, layouts);
			} catch (NativeAbi.NativeAbiError error) {
				throw new LlvmError.TARGET ("unqualified record layout: %s", error.message);
			}
			var expected = binding.layout;
			if (CApi.abi_size_of_type (data, binding.type) != expected.stride || CApi.abi_alignment_of_type (data, binding.type) != expected.alignment || !expected.fits_count (binding.fixed_count) || (binding.allocated && expected.alignment > 16)) {
				throw new LlvmError.TARGET ("record stride/alignment does not satisfy qualified storage, address-range or allocator requirements");
			}
			foreach (var field in expected.fields) {
				var type = CApi.struct_type_at_index (binding.type, field.field.ordinal);
				if (CApi.offset_of_element (data, binding.type, field.field.ordinal) != field.offset || CApi.abi_size_of_type (data, type) != field.size || CApi.abi_alignment_of_type (data, type) != field.alignment) {
					throw new LlvmError.TARGET ("record field #%d layout differs from the qualified recursive storage shape", field.field.ordinal);
				}
			}
		}
	}

	// Also usable for an internal object without any process-entry wrapper.
	public void configure(LlvmModuleArtifact artifact) throws LlvmError {
		var data = enum_target_data (artifact);
		if ((triple == WINDOWS_INTEROP && (!artifact.windows_interop_validated || artifact.selected_target != WINDOWS_INTEROP)) || (artifact.windows_interop_validated && triple != WINDOWS_INTEROP)) {
			throw new LlvmError.TARGET ("Windows interop object lost its checked source/SSA target admission");
		}
		bool windows_declared = triple == WINDOWS_INTEROP && artifact.windows_declarations;
		if (artifact.windows_declarations && (!windows_declared || CApi.pointer_size (data) != 8)) {
			throw new LlvmError.TARGET ("declarations-v1 Windows object requires its exact admitted x64 target and 64-bit pointers");
		}
		if (artifact.requires_policy_heap && pc_bare_metal) {
			throw new LlvmError.TARGET ("system heap allocation policy is unavailable in the selected no-OS profile");
		}
		if (artifact.requires_pc_devices && !pc_bare_metal) {
			throw new LlvmError.TARGET ("PC device operations require the qualified x86_64-none-elf target");
		}
		if (pc_bare_metal) {
			if (artifact.runtime_profile == null || artifact.runtime_profile.target != triple) {
				throw new LlvmError.TARGET ("x86_64-none-elf requires an explicit runtime-none target profile");
			}
			// The exception entry ABI owns the entire interrupted stack. No
			// generated function may use the SysV area below its stack pointer.
			var attribute = CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("noredzone", 9), 0);
			for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
				CApi.add_attribute (function, uint.MAX, attribute);
			}
		}
		if (artifact.volatile_accesses.length != 0 && !pc_bare_metal && !(triple.has_prefix ("x86_64-") && triple.has_suffix ("-linux-gnu"))) {
			throw new LlvmError.TARGET ("volatile memory operations require qualified x86-64 GNU Linux or the selected no-OS PC profile");
		}
		if (artifact.runtime_profile != null && artifact.runtime_profile.target != triple) {
			throw new LlvmError.TARGET ("runtime profile target identity mismatch");
		}
		if (triple == "aarch64-none-elf" && (artifact.runtime_profile == null || !artifact.runtime_profile.cross_object)) {
			throw new LlvmError.TARGET ("aarch64-none-elf requires runtime none and the closed object-only source profile");
		}
		if (artifact.c_record_target != null && (artifact.c_record_target.triple != triple || artifact.c_record_target.data_layout != data_layout)) {
			throw new LlvmError.TARGET ("C record target differs from exact natural LP64 layout witness");
		}
		if (artifact.class_target != null && (artifact.class_target.triple != triple || artifact.class_target.data_layout != data_layout)) {
			throw new LlvmError.TARGET ("class allocation target differs from its complete extent/alignment witness");
		}
		if (artifact.sum_layouts.length != 0 && (artifact.sum_target_triple != triple || artifact.sum_data_layout != data_layout)) {
			throw new LlvmError.TARGET ("sum carrier target differs from its recorded physical layout witness");
		}
		qualify_record_layouts (artifact);
		if (artifact.requires_text_slices) {
			if (!windows_declared) {
				LlvmArguments.qualify (triple);
			}
			var descriptor = new LlvmTypeMapper (artifact.context).text_descriptor ();
			var witness = new NativeAbi.NativeTextSliceLayout (CApi.offset_of_element (data, descriptor, 0), CApi.offset_of_element (data, descriptor, 1), CApi.abi_size_of_type (data, descriptor), CApi.abi_alignment_of_type (data, descriptor), CApi.pointer_size (data));
			if (!witness.qualified ()) {
				throw new LlvmError.TARGET ("text descriptor layout is not qualified: expected pointer/I32 natural record with offsets 0/8, stride 16, alignment 8");
			}
			artifact.text_slice_layout = witness;
		}
		if (artifact.requires_hosted_buffers) {
			LlvmBufferAllocation.qualify (triple);
		}
		if (artifact.requires_c_text && !windows_declared) {
			qualify_c_text (triple);
		}
		if (artifact.requires_c_floating && !windows_declared) {
			qualify_c_floating (triple);
		}
		if (artifact.requires_c_bool && !windows_declared) {
			qualify_c_systems (triple, CApi.pointer_size (data));
		}
		// The explicit declaration profile adds Windows LLP64 channels. Legacy
		// Windows source admission continues to reject wide source/C values.
		if (!windows_declared && (artifact.requires_c_buffer || artifact.requires_c_wide || artifact.requires_native_wide && !pc_bare_metal && triple != WINDOWS_INTEROP)) {
			qualify_c_systems (triple, CApi.pointer_size (data));
		}
		// F32-1 qualifies the default x86-64 Linux SSE/SSE2 execution path.
		// Other targets need an explicit binary32/denormal qualification;
		// they must not silently fall back to excess precision or FTZ/DAZ.
		if (artifact.requires_vectors && !(triple.has_prefix ("x86_64-") && triple.contains ("-linux-"))) {
			throw new LlvmError.TARGET ("error: vector native execution is not qualified for target '%s'", triple);
		}
		if (artifact.requires_binary32 && !windows_declared && !pc_bare_metal && !(triple.has_prefix ("x86_64-") && triple.contains ("-linux-"))) {
			throw new LlvmError.TARGET ("error: f32 native execution is not qualified for target '%s'", triple);
		}
		if (artifact.requires_binary64 && !windows_declared && !pc_bare_metal && !(triple.has_prefix ("x86_64-") && triple.contains ("-linux-"))) {
			throw new LlvmError.TARGET ("error: f64 native execution is not qualified for target '%s'", triple);
		}
		CApi.set_target (artifact.module, triple);
		CApi.set_module_data_layout (artifact.module, data);
		artifact.verify ();
	}

	// Verify all Astra identity/lifetime witnesses before cloning. LLVM passes
	// may delete those instructions; the original proof graph stays intact.
	internal void run_pipeline(CApi.ModuleRef module, string pipeline) throws LlvmError {
		var options = CApi.create_pass_builder_options ();
		CApi.pass_builder_verify_each (options, 1);
		var error = CApi.run_passes (module, pipeline, machine, options);
		CApi.dispose_pass_builder_options (options);
		if ((void*) error != null) {
			char* message = CApi.get_error_message (error);
			string diagnostic = (string) message;
			CApi.dispose_error_message (message);
			throw new LlvmError.EMISSION ("LLVM optimization failed: %s", diagnostic);
		}
	}

	private CApi.ModuleRef optimized_copy(LlvmModuleArtifact artifact) throws LlvmError {
		if (CApi.get_target (artifact.module) != triple || CApi.get_data_layout (artifact.module) != data_layout) {
			throw new LlvmError.INVALID_INPUT ("internal LLVM emission error: module is not configured for this host target machine");
		}
		artifact.verify ();
		var copy = CApi.clone_module (artifact.module);
		try {
			if (optimization_level != 0) {
				foreach (var imported in artifact.c_imports) {
					imported.preserve_foreign_effects (copy);
				}
				run_pipeline (copy, "default<O%d>".printf (optimization_level));
			}
			if (artifact.runtime_profile != null) {
				LlvmRuntimeProfile.verify_module (copy, artifact.requires_policy_runtime);
			}
			LlvmStrictFloating.verify (copy, artifact.floating_permissions);
			char* message = null;
			int failed = CApi.verify_module (copy, CApi.VerifierFailureAction.RETURN_STATUS, out message);
			string diagnostic = take_message (message);
			if (failed != 0) {
				throw new LlvmError.VERIFICATION ("optimized LLVM verification failed: %s", diagnostic);
			}
		} catch (LlvmError error) {
			CApi.dispose_module (copy);
			throw error;
		}
		return copy;
	}

	public string optimized_dump(LlvmModuleArtifact artifact) throws LlvmError {
		var copy = optimized_copy (artifact);
		string result = take_message (CApi.print_module_to_string (copy));
		CApi.dispose_module (copy);
		return result;
	}

	// The driver owns a private temporary output until emission succeeds.
	public uint8[] object_bytes(LlvmModuleArtifact artifact) throws LlvmError {
		var copy = optimized_copy (artifact);
		char* message = null;
		CApi.MemoryBufferRef buffer;
		int failed = CApi.target_machine_emit_to_buffer (machine, copy, CApi.CodeGenFileType.OBJECT, out message, out buffer);
		CApi.dispose_module (copy);
		string diagnostic = take_message (message);
		if (failed != 0) {
			throw new LlvmError.EMISSION ("error: LLVM object proof emission failed: %s", diagnostic.strip ());
		}
		size_t length = CApi.buffer_size (buffer);
		if (length > 128 * 1024 * 1024) {
			CApi.dispose_memory_buffer (buffer);
			throw new LlvmError.EMISSION ("native unit exceeds existing 128 MiB object limit");
		}
		var bytes = new uint8[(int) length];
		unowned string start = CApi.buffer_start (buffer);
		for (int i = 0; i < bytes.length; i++) {
			bytes[i] = (uint8) start[i];
		}
		CApi.dispose_memory_buffer (buffer);
		return bytes;
	}

	public void emit_object(LlvmModuleArtifact artifact, string path) throws LlvmError {
		var copy = optimized_copy (artifact);
		char* message = null;
		int failed = CApi.target_machine_emit_to_file (machine, copy, path, CApi.CodeGenFileType.OBJECT, out message);
		CApi.dispose_module (copy);
		string diagnostic = take_message (message);
		if (failed != 0) {
			FileUtils.unlink (path);
			throw new LlvmError.EMISSION ("error: LLVM object emission failed: %s", diagnostic.strip ());
		}
	}
}
}
