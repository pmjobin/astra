// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra {
private Source.SourceFile? read_file (string path, string kind) {
	string contents;
	size_t byte_count;
	try {
		FileUtils.get_contents (path, out contents, out byte_count);
	} catch (FileError error) {
		stderr.printf ("%s: error: cannot read %s file\n", path, kind);
		return null;
	}
	if (byte_count >= int.MAX) {
		stderr.printf ("%s: error: %s exceeds the Stage-0 byte limit\n", path, kind);
		return null;
	}
	// Transfer the complete allocation, including bytes beyond any NUL.
	// Explicit length avoids string/array casts making strlen authoritative.
	uint8[] bytes = (uint8[]) (owned) contents;
	bytes.length = (int) byte_count;
	return new Source.SourceFile (path, (owned) bytes);
}

private GenericArray<Semantic.ForeignDeclarationInput>? read_vapi(string[] paths, out GenericArray<Semantic.ForeignHandleInput> handles) {
	var declarations = new GenericArray<Semantic.ForeignDeclarationInput> ();
	handles = new GenericArray<Semantic.ForeignHandleInput> ();
	foreach (string path in paths) {
		var source = read_file (path, "VAPI");
		if (source == null) {
			return null;
		}
		var parsed = Vapi.VapiParser.parse (source);
		if (parsed.diagnostic != null) {
			stderr.printf ("%s\n", parsed.diagnostic.format ());
			return null;
		}
		var normalized = Vapi.VapiNormalizer.normalize (parsed.file);
		foreach (var handle in Vapi.VapiNormalizer.normalize_handles (parsed.file)) {
			handles.add (handle);
		}
		for (int i = 0; i < normalized.length; i++) {
			declarations.add (normalized[i]);
		}
	}
	return declarations;
}

private Syntax.SyntaxProgramResult? read_sources (string[] paths, GenericArray<Source.SourceFile>? imported = null) throws Source.SourceSetError {
	var files = new GenericArray<Source.SourceFile> ();
	foreach (string path in Source.SourceSet.canonical_paths (paths)) {
		var source = read_file (path, "source");
		if (source == null) {
			return null;
		}
		files.add (source);
	}
	if (imported != null) {
		foreach (var source in imported) {
			files.add (source);
		}
	}
	return Syntax.SyntaxProgram.parse (new Source.SourceSet (files));
}

// Parse-only modes report the syntactic declaration inventory without
// granting the declarations a semantic or ABI admission.
private void report_syntax_personalities(Syntax.SyntaxProgram program, int selection) {
	foreach (var unit in program.units) {
		foreach (var owner in unit.classes) {
			uint declared = (owner.foreign_export == null ? 0U : Source.ForeignClassPolicy.C) | (owner.com_export == null ? 0U : Source.ForeignClassPolicy.COM) | (owner.gobject_export == null ? 0U : Source.ForeignClassPolicy.GOBJECT);
			if (declared == 0) {
				continue;
			}
			uint active = declared & (uint) selection;
			stderr.printf ("foreign-personalities class=%s declared=%s active=%s unselected=%s\n", owner.name.spelling (), Source.ForeignClassPolicy.personality_names (declared), Source.ForeignClassPolicy.personality_names (active), Source.ForeignClassPolicy.personality_names (declared & ~active));
		}
	}
	foreach (var imported in program.c_classes) {
		var policy = imported.foreign_import;
		if (policy == null) {
			continue;
		}
		uint declared = policy.kind == Source.DeclarationPolicyId.GOBJECT_IMPORT ? Source.ForeignClassPolicy.GOBJECT : policy.kind == Source.DeclarationPolicyId.COM_IMPORT ? Source.ForeignClassPolicy.COM : Source.ForeignClassPolicy.C;
		uint active = declared & (uint) selection;
		stderr.printf ("foreign-personalities import=%s declared=%s active=%s unselected=%s\n", imported.name.spelling (), Source.ForeignClassPolicy.personality_names (declared), Source.ForeignClassPolicy.personality_names (active), Source.ForeignClassPolicy.personality_names (declared & ~active));
	}
	foreach (var imported in program.com_interfaces) {
		uint active = Source.ForeignClassPolicy.COM & (uint) selection;
		stderr.printf ("foreign-personalities import=%s declared=com active=%s unselected=%s\n", imported.name.spelling (), Source.ForeignClassPolicy.personality_names (active), Source.ForeignClassPolicy.personality_names (Source.ForeignClassPolicy.COM & ~active));
	}
}

private int process_files(string[] paths, string mode, string output_path = "a.out", Driver.LinkInput[]? link_inputs = null, string[]? vapi_paths = null, int optimization_level = 0, bool object_only = false, bool debug = false, string? module_name = null, string? module_interface = null, string[]? native_exports = null, string[]? native_imports = null, bool entry_object = false, string runtime = "hosted", string selected_target = "host", string? descriptor_module = null, string[]? descriptor_types = null, int foreign_selection = -1, string[]? legacy_imports = null) {
	Syntax.SyntaxProgramResult? result;
	Syntax.SyntaxProgram? module_program = null;
	Driver.NativeModuleContext? modules = null;
	try {
		if (module_name != null) {
			string object_absolute = Filename.canonicalize (output_path);
			string interface_absolute = Filename.canonicalize (module_interface);
			if (Path.get_dirname (object_absolute) != Path.get_dirname (interface_absolute) || object_absolute == interface_absolute) {
				stderr.printf ("astrac: error: native interface and distinct object must reside in the same directory.\n");
				return 2;
			}
			foreach (string input in paths) {
				string original = Filename.canonicalize (input);
				if (object_absolute == original || interface_absolute == original) {
					stderr.printf ("astrac: error: native module outputs cannot overwrite source inputs.\n");
					return 2;
				}
			}
		}
		if (module_name != null || (native_imports != null && native_imports.length != 0)) {
			modules = new Driver.NativeModuleContext (module_name, module_interface, native_exports ?? new string[0], native_imports ?? new string[0], selected_target, legacy_imports);
		}
		result = read_sources (paths, modules == null ? null : modules.inputs);
		if (result != null && result.diagnostic == null && modules != null) {
			module_program = modules.capture_exports (result.program);
		}
	} catch (Source.SourceSetError error) {
		stderr.printf ("astrac: error: %s\n", error.message);
		return 2;
	} catch (Driver.NativeModuleError error) {
		stderr.printf ("%s\n", error.message);
		return 1;
	}
	if (result == null) {
		return 1;
	}
	if (result.diagnostic != null) {
		if (mode == "--tooling-index") {
			stdout.printf ("%s", Semantic.ToolingIndex.diagnostic_json (result.diagnostic));
			return 1;
		}
		stderr.printf ("%s\n", result.diagnostic.format ());
		return 1;
	}
	if (mode == "--dump-syntax") {
		if (foreign_selection >= 0) {
			report_syntax_personalities (result.program, foreign_selection);
		}
		stdout.printf ("%s", Syntax.SyntaxDump.format_program (result.program));
		return 0;
	}
	if (mode == "--parse") {
		if (foreign_selection >= 0) {
			report_syntax_personalities (result.program, foreign_selection);
		}
		return 0;
	}
	GenericArray<Semantic.ForeignHandleInput> handles;
	var declarations = read_vapi (vapi_paths ?? new string[0], out handles);
	if (declarations == null) {
		return 1;
	}
	var tooling = mode == "--tooling-index" ? new Semantic.ToolingIndex () : null;
	Semantic.SemanticResult? semantic_result = Semantic.SemanticAnalyzer.analyze_program (module_program ?? result.program, declarations, handles, tooling, modules == null ? null : modules.heap_boundaries, modules == null ? null : modules.declaration_registry, foreign_selection);
	result = null;
	module_program = null;
	if (semantic_result.diagnostic != null) {
		if (mode == "--tooling-index") {
			stdout.printf ("%s", Semantic.ToolingIndex.diagnostic_json (semantic_result.diagnostic));
			return 1;
		}
		stderr.printf ("%s\n", semantic_result.diagnostic.format ());
		return 1;
	}
	if (foreign_selection >= 0) {
		foreach (var owner in semantic_result.program.classes) {
			var policy = owner.foreign_export;
			if (policy != null) {
				stderr.printf ("foreign-personalities class=%s declared=%s active=%s unselected=%s\n", owner.name, Source.ForeignClassPolicy.personality_names (policy.personalities), Source.ForeignClassPolicy.personality_names (policy.active_personalities), Source.ForeignClassPolicy.personality_names (policy.personalities & ~policy.active_personalities));
			}
		}
		foreach (var handle in semantic_result.program.handles) {
			var root = handle.c_import;
			if (root != null) {
				stderr.printf ("foreign-personalities import=%s declared=%s active=%s unselected=%s\n", handle.name, Source.ForeignClassPolicy.personality_names (root.api.declared_personalities), Source.ForeignClassPolicy.personality_names (root.api.active_personalities), Source.ForeignClassPolicy.personality_names (root.api.declared_personalities & ~root.api.active_personalities));
			}
		}
	}
	if (mode == "--tooling-index" || mode == "--explain-semantics") {
		stdout.printf ("%s", (tooling ?? new Semantic.ToolingIndex ()).format (semantic_result.program, mode == "--explain-semantics"));
		return 0;
	}
	try {
		if (modules != null) {
			modules.bind_type_requests (semantic_result.program);
		}
		Backend.LLVM.LlvmRuntimeProfile? runtime_profile = null;
		if (selected_target != "host" || runtime != "hosted") {
			foreach (var imported in semantic_result.program.c_functions) {
				if (imported.metadata.bool_abi == Foreign.CBoolAbi.C99) {
					throw new Backend.LLVM.LlvmError.TARGET ("C99 bool requires the selected hosted Linux x64 C ABI profile");
				}
			}
			foreach (var exported in semantic_result.program.c_exports) {
				if (exported.bool_abi == Foreign.CBoolAbi.C99) {
					throw new Backend.LLVM.LlvmError.TARGET ("C99 bool requires the selected hosted Linux x64 C ABI profile");
				}
			}
		}
		if (selected_target == Backend.LLVM.LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
			Driver.RuntimeProfileAdmission.windows (semantic_result.program, foreign_selection >= 0);
		}
		foreach (var owner in semantic_result.program.classes) {
			if (owner.foreign_export != null && owner.foreign_export.active (Source.ForeignClassPolicy.COM) && selected_target != Backend.LLVM.LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
				throw new Backend.LLVM.LlvmError.TARGET ("selected COMExport requires --target=x86_64-w64-windows-gnu");
			}
		}
		foreach (var owner in semantic_result.program.classes) {
			if (owner.foreign_export != null && owner.foreign_export.active (Source.ForeignClassPolicy.GOBJECT) && (selected_target != "host" || runtime != "hosted")) {
				throw new Backend.LLVM.LlvmError.TARGET ("selected GObjectExport requires the hosted Linux x64 profile");
			}
		}
		foreach (var handle in semantic_result.program.handles) {
			if (handle.com_import != null && selected_target != Backend.LLVM.LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
				throw new Backend.LLVM.LlvmError.TARGET ("selected COMImport requires --target=x86_64-w64-windows-gnu");
			}
		}
		foreach (var imported in semantic_result.program.c_functions) {
			if (imported.metadata.import_policy == Source.DeclarationPolicyId.GOBJECT_IMPORT && (selected_target != "host" || runtime != "hosted")) {
				throw new Backend.LLVM.LlvmError.TARGET ("selected GObjectImport requires the hosted Linux x64 profile");
			}
		}
		foreach (var imported in semantic_result.program.c_functions) {
			if (imported.metadata.device != null && (selected_target != Backend.LLVM.LlvmTargetMachineArtifact.PC_BARE_METAL || runtime != "none")) {
				throw new Backend.LLVM.LlvmError.TARGET ("PC device policies require --target=x86_64-none-elf --runtime=none");
			}
		}
		if (runtime == "none") {
			var selected = new Backend.LLVM.LlvmTargetMachineArtifact (optimization_level, selected_target);
			if (selected.triple != "aarch64-none-elf" && !selected.pc_bare_metal && !(selected.triple.has_prefix ("x86_64-") && selected.triple.has_suffix ("-linux-gnu"))) {
				throw new Backend.LLVM.LlvmError.TARGET ("runtime none requires qualified x86-64 GNU Linux, x86_64-none-elf or aarch64-none-elf object-only");
			}
			runtime_profile = new Backend.LLVM.LlvmRuntimeProfile (selected.triple, selected.triple == "aarch64-none-elf");
			Driver.RuntimeProfileAdmission.none (runtime_profile, semantic_result.program);
		}
		if (mode == "--dump-semantics") {
			stdout.printf ("%s", Semantic.SemanticDump.format (semantic_result.program));
			return 0;
		}
		string? descriptor_source = null;
		string? foreign_header = mode == "--emit-class-header" ? Driver.ForeignAdapters.header (semantic_result.program) : null;
		if (mode == "--emit-class-source") {
			foreign_header = Driver.ForeignAdapters.source (semantic_result.program);
		}
		if (mode == "--emit-com-header" || mode == "--emit-com-source") {
			foreign_header = Driver.ComAdapters.generate (semantic_result.program, mode == "--emit-com-source");
		}
		if (mode == "--emit-gobject-header" || mode == "--emit-gobject-source") {
			foreign_header = Driver.GObjectAdapters.generate (semantic_result.program, mode == "--emit-gobject-source");
		}
		if (mode == "--emit-native-descriptors") {
			foreach (string input in paths) {
				if (Filename.canonicalize (input) == Filename.canonicalize (output_path)) {
					throw new Driver.NativeDescriptorError.OUTPUT ("descriptor output cannot overwrite a source input");
				}
			}
			foreach (string input in vapi_paths ?? new string[0]) {
				if (Filename.canonicalize (input) == Filename.canonicalize (output_path)) {
					throw new Driver.NativeDescriptorError.OUTPUT ("descriptor output cannot overwrite a VAPI input");
				}
			}
			descriptor_source = Driver.NativeDescriptors.generate (semantic_result.program, descriptor_module, descriptor_types ?? new string[0]);
		}
		var core = Core.CoreBuilder.build (semantic_result.program);
		semantic_result = null;
		if (mode == "--dump-core") {
			stdout.printf ("%s", Core.CoreDump.format (core));
			return 0;
		}
		// The builder verifies Core; flow checking verifies CFG before
		// reachability. Only the complete, flow-valid dump reaches stdout.
		core = Core.CoreGenericMonomorphizer.build (core);
		if (mode == "--dump-instances") {
			stdout.printf ("%s", Core.CoreDump.format (core));
			return 0;
		}
		var cfg = Cfg.CfgBuilder.build (core);
		var flow = Cfg.CfgFlowChecker.check (cfg);
		if (flow.diagnostic != null) {
			stderr.printf ("%s\n", flow.diagnostic.format ());
			return 1;
		}
		if (mode == "--dump-cfg") {
			stdout.printf ("%s", Cfg.CfgDump.format (cfg));
			return 0;
		}
		var ssa = Ssa.SsaBuilder.build (cfg, modules == null ? null : modules.required_types ());
		if (runtime_profile != null) {
			runtime_profile.validate_source (ssa);
		}
		if (mode == "--dump-ssa" && modules == null) {
			stdout.printf ("%s", Ssa.SsaDump.format (ssa, Environment.get_variable ("ASTRA_EXPLAIN_OPTIMIZATIONS") == "1"));
			return 0;
		}
		var nabi = NativeAbi.NativeAbiBuilder.build (ssa);
		var module_plan = modules == null ? null : modules.bind (ssa, nabi);
		if (modules != null && modules.validate_optimizer_imports ()) {
			Ssa.SsaBuilder.reanalyze_optimizations (ssa);
			nabi = NativeAbi.NativeAbiBuilder.build (ssa);
			module_plan = modules.bind (ssa, nabi);
		}
		if (mode == "--dump-ssa") {
			stdout.printf ("%s", Ssa.SsaDump.format (ssa, Environment.get_variable ("ASTRA_EXPLAIN_OPTIMIZATIONS") == "1"));
			return 0;
		}
		if (module_name != null && ssa.c_exports.length != 0) {
			stderr.printf ("astrac: error: selected native unit profile excludes simultaneous C exports.\n");
			return 1;
		}
		if (mode == "--dump-nabi") {
			stdout.printf ("%s", NativeAbi.NativeAbiDump.format (nabi));
			return 0;
		}
		var cabi = CAbi.CAbiBuilder.build (ssa, nabi);
		if (mode == "--dump-cabi") {
			stdout.printf ("%s", CAbi.CAbiDump.format (cabi));
			return 0;
		}
		var entry = mode == "compile" && (!object_only || entry_object) ? Driver.ProgramEntry.resolve (ssa) : null;
		// Optimized executable dumps need the same live entry root as an
		// executable. Otherwise global DCE can erase every internal function.
		if (mode == "--dump-llvm" && module_name == null && optimization_level != 0 && runtime == "hosted" && selected_target != Backend.LLVM.LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
			foreach (var function in ssa.functions) {
				if (function.name == "main" && function.kind == Semantic.CallableKind.FUNCTION) {
					entry = Driver.ProgramEntry.resolve (ssa);
					break;
				}
			}
		}
		var llvm = Backend.LLVM.LlvmLowering.lower (ssa, nabi, cabi, entry, null, debug, optimization_level != 0, module_plan, selected_target);
		llvm.runtime_profile = runtime_profile;
		llvm.verify ();
		if (foreign_header != null) {
			stdout.printf ("%s", foreign_header);
			return 0;
		}
		if (descriptor_source != null) {
			Driver.NativeDescriptors.write (output_path, descriptor_source);
			return 0;
		}
		if (mode == "--dump-llvm") {
			if (optimization_level == 0 && runtime_profile == null && selected_target != Backend.LLVM.LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
				stdout.printf ("%s", llvm.dump ());
			} else {
				var target = new Backend.LLVM.LlvmTargetMachineArtifact (optimization_level, selected_target);
				if (entry != null) {
					llvm.configure_executable (target);
				} else {
					target.configure (llvm);
				}
				stdout.printf ("%s", target.optimized_dump (llvm));
			}
		} else if (mode == "compile") {
			if (modules != null && modules.has_optimizer_export_claims ()) {
				var proof_target = new Backend.LLVM.LlvmTargetMachineArtifact (optimization_level, selected_target);
				proof_target.configure (llvm);
				if (modules.refine_optimizer_exports (proof_target.object_bytes (llvm))) {
					module_plan = modules.bind (ssa, nabi);
					llvm = Backend.LLVM.LlvmLowering.lower (ssa, nabi, cabi, entry, null, debug, optimization_level != 0, module_plan, selected_target);
					llvm.runtime_profile = runtime_profile;
					llvm.verify ();
				}
			}
			if (modules != null) {
				modules.revalidate_dependencies ();
			}
			Driver.LinkInput[] selected_inputs = {};
			if (modules != null && !object_only) {
				foreach (var dependency in modules.link_dependencies ()) {
					selected_inputs += dependency;
				}
			}
			foreach (var input in link_inputs ?? new Driver.LinkInput[0]) {
				selected_inputs += input;
			}
			Driver.NativeCompilation.emit (llvm, output_path, selected_inputs, optimization_level, object_only, entry_object, selected_target);
			if (modules != null && module_name != null) {
				modules.publish (output_path);
			}
		}
	} catch (Driver.ForeignAdapterError error) {
		stderr.printf ("astrac: foreign adapter: %s\n", error.message);
		return 1;
	} catch (Driver.NativeDescriptorError error) {
		stderr.printf ("astrac: error: native descriptors: %s\n", error.message);
		return 1;
	} catch (Driver.NativeModuleError error) {
		stderr.printf ("%s\n", error.message);
		return 1;
	} catch (Core.CoreError error) {
		stderr.printf ("astrac: %s\n", error.message);
		return 1;
	} catch (Cfg.CfgError error) {
		stderr.printf ("astrac: %s\n", error.message);
		return 1;
	} catch (Ssa.SsaError error) {
		stderr.printf ("astrac: %s\n", error.message);
		return 1;
	} catch (CAbi.CAbiError error) {
		stderr.printf ("%s%s\n", (error is CAbi.CAbiError.DUPLICATE_SYMBOL) ? "" : "astrac: ", error.message);
		return 1;
	} catch (NativeAbi.NativeAbiError error) {
		stderr.printf ("astrac: %s\n", error.message);
		return 1;
	} catch (Backend.LLVM.LlvmError error) {
		stderr.printf ("astrac: %s\n", error.message);
		return 1;
	} catch (Driver.ExecutionError error) {
		stderr.printf ("%s\n", error.message);
		return 1;
	}
	return 0;
}

private int format_file(string[] args) {
	string? path = null;
	string? destination = null;
	bool check = false, in_place = false, positional = false;
	if (args.length == 3 && args[2] == "--version") {
		stdout.printf ("astrac format %d\n", Syntax.SourceFormatter.VERSION);
		return 0;
	}
	if (args.length == 3 && args[2] == "--help") {
		stdout.printf ("Usage: astrac --format [--check | --in-place | -o NEW_FILE] FILE\nDefault: formatted source to stdout. Existing output files require --in-place.\nVersion 1 normalizes indentation to hard TABs and preserves intra-line layout.\n");
		return 0;
	}
	for (int i = 2; i < args.length; i++) {
		if (!positional && args[i] == "--") {
			positional = true;
		} else if (!positional && args[i] == "--check" && !check) {
			check = true;
		} else if (!positional && args[i] == "--in-place" && !in_place) {
			in_place = true;
		} else if (!positional && args[i] == "-o" && destination == null && i + 1 < args.length) {
			destination = args[++i];
		} else if ((!positional && args[i].has_prefix ("-")) || path != null) {
			stderr.printf ("astrac format: error: expected one source and one output mode; use --format --help\n");
			return 2;
		} else {
			path = args[i];
		}
	}
	if (path == null || (check && (in_place || destination != null)) || (in_place && destination != null)) {
		stderr.printf ("astrac format: error: expected one source and one output mode; use --format --help\n");
		return 2;
	}
	var source = read_file (path, "source");
	if (source == null) {
		return 1;
	}
	Source.Diagnostic? diagnostic;
	var formatted = Syntax.SourceFormatter.format (source, out diagnostic);
	if (formatted == null) {
		stderr.printf ("%s\n", diagnostic.format ());
		return 1;
	}
	if (check) {
		if (formatted == source.slice (0, source.length)) {
			return 0;
		}
		stderr.printf ("%s: formatting differs\n", path);
		return 1;
	}
	if (in_place) {
		if (formatted == source.slice (0, source.length)) {
			return 0;
		}
		try {
			FileUtils.set_contents (path, formatted);
		} catch (FileError error) {
			stderr.printf ("%s: error: cannot write formatted source: %s\n", path, error.message);
			return 2;
		}
	} else if (destination != null) {
		// Exclusive creation makes -o safe even for aliases of the input.
		var output = FileStream.open (destination, "wx");
		if (output == null) {
			stderr.printf ("%s: error: cannot create new formatter output\n", destination);
			return 2;
		}
		if (output.puts (formatted) < 0 || output.flush () != 0) {
			stderr.printf ("%s: error: cannot write formatter output\n", destination);
			return 2;
		}
	} else if (stdout.puts (formatted) < 0 || stdout.flush () != 0) {
		return 2;
	}
	return 0;
}

int main(string[] args) {
	if (args.length == 2 && args[1] == "--policy-registry") {
		stdout.printf ("%s", Source.DeclarationPolicyRegistry.format ());
		return 0;
	}
	if (args.length >= 2 && args[1] == "--format") {
		return format_file (args);
	}
	if (args.length == 2 && (args[1] == "--parse" || args[1] == "--dump-syntax")) {
		stderr.printf ("astrac: error: expected exactly one file after %s.\n", args[1]);
		return 2;
	}

	bool help = false;
	bool version = false;
	bool positional = false;
	string[] source_paths = {};
	string? output_path = null;
	Driver.LinkInput[] link_inputs = {};
	string[] vapi_paths = {};
	string mode = "compile";
	int optimization_level = 0;
	bool selected_optimization = false;
	bool object_only = false;
	bool debug = false;
	bool entry_object = false;
	string runtime = "hosted";
	string selected_target = "host";
	bool selected_runtime = false;
	bool selected_target_option = false;
	int foreign_selection = -1;
	bool target_info = false;
	string? module_name = null;
	string? module_interface = null;
	string[] native_exports = {};
	string[] native_imports = {};
	string[] native_legacy_imports = {};
	string? descriptor_module = null;
	string[] descriptor_types = {};

	for (int i = 1; i < args.length; i++) {
		string argument = args[i];
		if (positional || !argument.has_prefix ("-") || argument == "-") {
			source_paths += argument;
			continue;
		}
		if (argument == "--link-library" || argument.has_prefix ("--link-library=")) {
			string name = argument.has_prefix ("--link-library=") ? argument.substring (15) : i + 1 < args.length ? args[++i] : "";
			if (!Driver.LinkInput.valid_library_name (name)) {
				stderr.printf ("astrac: error: --link-library requires a bare name matching [A-Za-z0-9][A-Za-z0-9_.-]*.\n");
				return 2;
			}
			link_inputs += new Driver.LinkInput.named_library (name);
			continue;
		}
		if (argument == "--foreign-personalities" || argument.has_prefix ("--foreign-personalities=")) {
			string choice = argument.has_prefix ("--foreign-personalities=") ? argument.substring (24) : i + 1 < args.length ? args[++i] : "";
			if (foreign_selection >= 0 || choice == "") {
				stderr.printf ("astrac: error: --foreign-personalities requires one explicit nonempty selection.\n");
				return 2;
			}
			foreign_selection = 0;
			if (choice != "none") {
				foreach (string item in choice.split (",")) {
					string name = item.strip ();
					int bit = name == "c" ? 1 : name == "com" ? 2 : name == "gobject" ? 4 : 0;
					if (bit == 0 || (foreign_selection & bit) != 0) {
						stderr.printf ("astrac: error: foreign personalities require distinct c,com,gobject, or none alone.\n");
						return 2;
					}
					foreign_selection |= bit;
				}
			}
			continue;
		}
		if (argument == "--runtime" || argument.has_prefix ("--runtime=") || argument == "--target" || argument.has_prefix ("--target=")) {
			bool is_runtime = argument == "--runtime" || argument.has_prefix ("--runtime=");
			int separator = argument.index_of ("=");
			string selection = separator >= 0 ? argument.substring (separator + 1) : i + 1 < args.length ? args[++i] : "";
			if (selection == "" || selection.has_prefix ("-") || (is_runtime ? selected_runtime : selected_target_option)) {
				stderr.printf ("astrac: error: runtime/target selection requires one nonempty value without duplicates.\n");
				return 2;
			}
			if (is_runtime) {
				runtime = selection;
				selected_runtime = true;
			} else {
				selected_target = selection;
				selected_target_option = true;
			}
			continue;
		}

		switch (argument) {
		case "--target-info":
			target_info = true;
			break;
		case "--entry-object":
			entry_object = true;
			object_only = true;
			break;
		case "--descriptor-module": case "--describe":
			if (i + 1 >= args.length || args[i + 1] == "" || args[i + 1].has_prefix ("-")) {
				stderr.printf ("astrac: error: %s requires a nonempty value.\n", argument);
				return 2;
			}
			string descriptor_value = args[++i];
			if (argument == "--describe") {
				descriptor_types += descriptor_value;
			} else {
				if (descriptor_module != null) {
					stderr.printf ("astrac: error: duplicate --descriptor-module.\n");
					return 2;
				}
				descriptor_module = descriptor_value;
			}
			break;
		case "--module": case "--emit-interface": case "--native-export": case "--import-module": case "--import-legacy-module":
			if (i + 1 >= args.length || args[i + 1] == "" || args[i + 1].has_prefix ("-")) {
				stderr.printf ("astrac: error: %s requires a nonempty value.\n", argument);
				return 2;
			}
			string value = args[++i];
			if (argument == "--module") {
				if (module_name != null) {
					stderr.printf ("astrac: error: duplicate --module.\n");
					return 2;
				}
				module_name = value;
			} else if (argument == "--emit-interface") {
				if (module_interface != null) {
					stderr.printf ("astrac: error: duplicate --emit-interface.\n");
					return 2;
				}
				module_interface = value;
			} else if (argument == "--native-export") {
				native_exports += value;
			} else {
				native_imports += value;
				if (argument == "--import-legacy-module") {
					native_legacy_imports += value;
				}
			}
			break;
		case "-O0": case "-O1": case "-O2":
			optimization_level = argument == "-O0" ? 0 : argument == "-O1" ? 1 : 2;
			selected_optimization = true;
			break;
		case "-c":
			object_only = true;
			break;
		case "-g":
			debug = true;
			break;
		case "--parse":
		case "--dump-syntax":
		case "--check":
		case "--dump-semantics":
		case "--tooling-index":
		case "--explain-semantics":
		case "--dump-core":
		case "--dump-instances":
		case "--dump-cfg":
		case "--dump-ssa":
		case "--dump-nabi":
		case "--dump-cabi":
		case "--dump-llvm":
		case "--emit-native-descriptors":
		case "--emit-class-header":
		case "--emit-class-source":
		case "--emit-com-header":
		case "--emit-com-source":
		case "--emit-gobject-header":
		case "--emit-gobject-source":
			if (mode != "compile") {
				stderr.printf ("astrac: error: expected only one check/dump mode.\n");
				return 2;
			}
			mode = argument;
			break;
		case "--help":
			help = true;
			break;
		case "--version":
			version = true;
			break;
		case "--":
			positional = true;
			break;
		case "--link-object":
		case "--vapi":
			if (i + 1 >= args.length || args[i + 1] == "" || args[i + 1].has_prefix ("-")) {
				stderr.printf ("astrac: error: %s requires a nonempty %s path (use ./ for a leading '-').\n", argument, argument == "--vapi" ? "VAPI" : "object");
				return 2;
			}
			if (argument == "--vapi") {
				vapi_paths += args[++i];
			} else {
				link_inputs += new Driver.LinkInput.object_file (args[++i]);
			}
			break;
		case "-o":
			if (output_path != null || i + 1 >= args.length || args[i + 1] == "") {
				stderr.printf ("astrac: error: -o requires one nonempty output path and may occur only once.\n");
				return 2;
			}
			output_path = args[++i];
			break;
		default:
			stderr.printf ("astrac: error: unknown option '%s'; use --help.\n", argument);
			return 2;
		}
	}

	if ((help || version || target_info) && (source_paths.length != 0 || output_path != null || link_inputs.length != 0 || vapi_paths.length != 0 || mode != "compile" || selected_optimization || object_only || debug || module_name != null || module_interface != null || native_exports.length != 0 || native_imports.length != 0 || descriptor_module != null || descriptor_types.length != 0 || foreign_selection >= 0 || ((help || version) && (selected_runtime || selected_target_option || target_info)))) {
		stderr.printf ("astrac: error: --help/--version cannot be combined with compilation.\n");
		return 2;
	}
	if (runtime != "hosted" && runtime != "none") {
		stderr.printf ("astrac: error: unsupported runtime '%s'; select hosted or none.\n", runtime);
		return 2;
	}
	if ((mode == "--tooling-index" || mode == "--explain-semantics") && (selected_runtime || selected_target_option)) {
		stderr.printf ("astrac: error: source-policy inspection does not accept runtime or target selections.\n");
		return 2;
	}
	if (target_info) {
		try {
			var target = new Backend.LLVM.LlvmTargetMachineArtifact (0, selected_target);
			if (target.triple == Backend.LLVM.LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
				stdout.printf ("target=%s\ndata-layout=%s\ncpu=generic\nfeatures=baseline\npointer-bits=%u\nruntimes=hosted\nprofile=windows-interop-object-v1; copied words/pointers and native intrusive Shared/Weak\nlink=explicit Windows C toolchain; no executable entry or native module adapter\nnone=unsupported\n", target.triple, target.data_layout, target.pointer_bytes * 8);
				return 0;
			}
			stdout.printf ("target=%s\ndata-layout=%s\ncpu=generic\nfeatures=baseline\npointer-bits=%u\nruntimes=%s\nnone=closed-numeric-object; explicit external startup/link\ncross-object=aarch64-none-elf (integer<=32; runtime none)\nbare-metal=x86_64-none-elf (explicit PC startup/link; no red zone)\n", target.triple, target.data_layout, target.pointer_bytes * 8, target.triple == "aarch64-none-elf" || target.pc_bare_metal ? "none" : "hosted,none");
			return 0;
		} catch (Backend.LLVM.LlvmError error) {
			stderr.printf ("astrac: %s\n", error.message);
			return 2;
		}
	}
	if (selected_target != "host") {
		try {
			var target = new Backend.LLVM.LlvmTargetMachineArtifact (0, selected_target);
			if ((target.triple == "aarch64-none-elf" || target.pc_bare_metal) && runtime != "none") {
				stderr.printf ("astrac: error: %s requires runtime none.\n", target.triple);
				return 2;
			}
		} catch (Backend.LLVM.LlvmError error) {
			stderr.printf ("astrac: %s\n", error.message);
			return 2;
		}
	}
	if (selected_target == Backend.LLVM.LlvmTargetMachineArtifact.WINDOWS_INTEROP && (runtime != "hosted" || (mode == "compile" && !object_only) || entry_object || (module_name != null || native_imports.length != 0) && foreign_selection < 0 || link_inputs.length != 0)) {
		stderr.printf ("astrac: error: Windows interop requires hosted source checking/dumps or -c; link the object with an explicit Windows toolchain.\n");
		return 2;
	}
	if (runtime == "none" && ((mode == "compile" && !object_only) || entry_object || module_name != null || native_imports.length != 0 || link_inputs.length != 0 || vapi_paths.length != 0 || mode == "--parse" || mode == "--dump-syntax")) {
		stderr.printf ("astrac: error: runtime none requires numeric source checking/dumps or -c, without entry wrappers, providers or native module interfaces. Link an explicit startup separately.\n");
		return 2;
	}

	bool native_llvm_dump = mode == "--dump-llvm" && module_name != null && module_interface != null && native_exports.length != 0 && object_only && !entry_object;
	if (mode != "compile" && mode != "--emit-native-descriptors" && (output_path != null && !native_llvm_dump || link_inputs.length != 0)) {
		stderr.printf ("astrac: error: -o/--link-object/--link-library require executable compilation.\n");
		return 2;
	}
	if ((object_only && (mode != "compile" && !native_llvm_dump || link_inputs.length != 0)) || (selected_optimization && mode != "compile" && mode != "--dump-llvm")) {
		stderr.printf ("astrac: error: -c requires compilation without link inputs; -O0/-O1/-O2 require compilation or --dump-llvm.\n");
		return 2;
	}
	if ((mode == "--parse" || mode == "--dump-syntax") && vapi_paths.length != 0) {
		stderr.printf ("astrac: error: --vapi requires semantic checking or executable compilation.\n");
		return 2;
	}
	if (debug && mode != "compile" && mode != "--dump-llvm" && mode != "--check") {
		stderr.printf ("astrac: error: -g requires compilation, --check or --dump-llvm.\n");
		return 2;
	}
	if ((module_name != null || module_interface != null || native_exports.length != 0) && (module_name == null || module_interface == null || native_exports.length == 0 || !object_only || entry_object || mode != "compile" && !native_llvm_dump)) {
		stderr.printf ("astrac: error: native producer requires --module, --emit-interface, --native-export and -c.\n");
		return 2;
	}
	if (native_imports.length != 0 && (mode == "--parse" || mode == "--dump-syntax")) {
		stderr.printf ("astrac: error: --import-module requires semantic checking or compilation.\n");
		return 2;
	}

	if (mode == "--emit-native-descriptors") {
		if (descriptor_module == null || descriptor_types.length == 0 || output_path == null || object_only || debug || selected_optimization || runtime != "hosted" || selected_target != "host" || link_inputs.length != 0 || module_name != null || native_imports.length != 0) {
			stderr.printf ("astrac: error: descriptor emission requires --descriptor-module NAME, --describe TYPE... and -o SOURCE, without target, linking or native-unit options.\n");
			return 2;
		}
	} else if (descriptor_module != null || descriptor_types.length != 0) {
		stderr.printf ("astrac: error: descriptor selections require --emit-native-descriptors.\n");
		return 2;
	}

	if (help) {
		stdout.printf ("  --policy-registry     Inspect registered policy IDs, availability and current forms\n");
		stdout.printf ("  --foreign-personalities=c,com|c,gobject|none  Select declared modern foreign surfaces\n");
		stdout.printf ("  --emit-class-header   Emit the verified opaque C Class export header to stdout\n");
		stdout.printf ("  --emit-class-source   Emit mechanical target-C POD member forwarding source\n");
		stdout.printf ("  --emit-com-header     Emit the verified selected Windows COM declarations\n");
		stdout.printf ("  --emit-com-source     Emit the selected Windows C++17 COM adapter on stdout\n");
		stdout.printf ("  --emit-gobject-header Emit verified selected GObject declarations\n");
		stdout.printf ("  --emit-gobject-source Emit the selected C11 GType/property/signal adapter\n");
		stdout.printf ("  --tooling-index       Emit versioned checked symbols/references/diagnostics JSON\n  --explain-semantics   Explain checked ownership, synchronization and ABI policies\n");
		stdout.printf ("  --emit-native-descriptors --descriptor-module NAME --describe TYPE... -o SOURCE\n                        Generate opt-in checked native metadata and typed readers\n                        TYPE may be Alias=Qualified.Type; select standard Error explicitly\n");
		stdout.printf ("  --runtime hosted|none  Select default hosted or closed runtime-free object profile\n  --target TARGET        Select host, x86_64-none-elf, aarch64-none-elf,\n                         or x86_64-w64-windows-gnu (selected interop object profile)\n  --target-info          Print exact target/layout/runtime profile identity\n");
		stdout.printf ("  --module NAME --emit-interface FILE --native-export NAME... -c\n                        Emit a finite independently compiled native library\n  --import-module FILE  Verify and import a native library interface and object\n  --import-legacy-module FILE\n                        Check unchanged Linux /3 or /4 ABI; task/context units require rebuild\n  --entry-object        Emit a relocatable program object including its C entry\n");
		stdout.printf ("  -g                    Emit source DWARF and bounded scalar variable identities\n");
		stdout.printf ("  -O0 / -O1 / -O2       Select LLVM IR and machine optimization (default: -O0)\n  -c                    Emit one host relocatable object without an entry wrapper\n                        Default output: a.o; accepts explicit whole-program sources\n\n");
		stdout.printf ("Usage: astrac FILE... [--vapi PATH]... [--link-object OBJECT | --link-library NAME]... [-o OUTPUT]\n       astrac -o OUTPUT FILE...\n       astrac [--help] [--version]\n       astrac --parse FILE...\n       astrac --dump-syntax FILE...\n       astrac --check FILE...\n       astrac --dump-semantics FILE...\n       astrac --dump-core FILE...\n       astrac --dump-cfg FILE...\n       astrac --dump-ssa FILE...\n       astrac --dump-nabi FILE...\n       astrac --dump-cabi FILE...\n       astrac --dump-llvm FILE...\n\n");
		stdout.printf ("Astra Stage 0 (%s)\n\n", Config.MILESTONE);
		stdout.printf ("  --help                 Show this help\n  --version              Show the compiler version\n");
		stdout.printf ("  --format [MODE] FILE   Format source with hard TAB indentation; --format --help for modes\n");
		stdout.printf ("  --parse FILE           Validate source syntax only\n  --dump-syntax FILE     Print the internal syntax tree\n");
		stdout.printf ("  --check FILE           Validate through LLVM lowering and verification\n  --dump-semantics FILE  Print the internal checked model\n");
		stdout.printf ("  --dump-core FILE       Build, verify, and print semantic Core IR\n  --dump-instances FILE  Monomorphize and print concrete Core with instance inventory\n  --dump-cfg FILE        Validate and print explicit control flow\n  --dump-ssa FILE        Promote and print reachable scalar SSA\n  --dump-nabi FILE       Plan, verify, and print native ABI signatures\n  --dump-cabi FILE       Plan, verify, and print C import/export ABI signatures\n\n");
		stdout.printf ("  --dump-llvm FILE       Lower, verify, and print LLVM IR\n  Native producer -c/--module/--emit-interface/--native-export/-o also work with --dump-llvm; checked output paths are not written.\n\n");
		stdout.printf ("  FILE... [-o OUTPUT]      Compile a host-native executable (default: a.out)\n  -o OUTPUT FILE...        Equivalent output-first option order\n\n  --vapi PATH           Read C declarations; repeat in declaration order\n                        Works with --check, semantic/IR/ABI/LLVM dumps, and compile\n                        Declaration-only; independent from --link-object\n  --link-object OBJECT  Link a relocatable object; repeat in desired order\n  --link-library NAME   Link a bare named library (also --link-library=NAME)\n                       Object/library occurrences retain order and repetitions\n                       Names: [A-Za-z0-9][A-Za-z0-9_.-]*; no paths or raw flags\n\nExplicit source files form one program; namespace/using directives are opt-in.\nExecutable entry must be global native int main() or int main(string[] args).\nText arguments require an explicit --link-object args-posix.o provider.\n");
		return 0;
	}

	if (version) {
		stdout.printf ("astrac %s (%s)\n", Config.VERSION, Config.MILESTONE);
		return 0;
	}

	if (source_paths.length != 0) {
		return process_files (source_paths, mode, output_path ?? (object_only ? "a.o" : "a.out"), link_inputs, vapi_paths, optimization_level, object_only, debug, module_name, module_interface, native_exports, native_imports, entry_object, runtime, selected_target, descriptor_module, descriptor_types, foreign_selection, native_legacy_imports);
	}

	stderr.printf ("astrac: error: no action specified; use --help.\n");
	return 2;
}
}
