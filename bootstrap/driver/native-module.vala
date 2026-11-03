// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Backend.LLVM;

namespace Astra.Driver {
public errordomain NativeModuleError {
	CONTRACT
}

internal class NativeModuleRecord : Object {
	internal KeyFile data = new KeyFile ();
	internal SourceFile? declarations;
	internal GenericArray<SourceFile> foreign_declarations = new GenericArray<SourceFile> ();
	internal string name;
	internal string path;
	internal string? object_path;
	internal bool imported;
	internal bool windows;
	internal bool legacy;
	internal string interface_hash = "";
	internal GenericArray<NativeModuleRecord> dependencies = new GenericArray<NativeModuleRecord> ();
	internal int dependency_depth;
	internal GenericArray<string> keys = new GenericArray<string> ();
	internal GenericArray<string> type_names = new GenericArray<string> ();
	internal HashTable<string, NativeOptimizerSpec> optimizer_specs = new HashTable<string, NativeOptimizerSpec> (str_hash, str_equal);
	internal HashTable<string, SsaFunction> optimizer_functions = new HashTable<string, SsaFunction> (str_hash, str_equal);
	internal HashTable<string, string> optimizer_overrides = new HashTable<string, string> (str_hash, str_equal);
	internal NativeModuleRecord (string name, string path, bool imported) {
		this.name = name;
		this.path = path;
		this.imported = imported;
	}

}

// Explicit finite interfaces contain declaration models, never producer bodies.
// The models pass ordinary source/ownership/IR checks; LLVM emits only native
// external declarations for their exact verified function identities.
public class NativeModuleContext : Object {
	private const string FORMAT = "astra-native-module/2";
	private const string SCHEMA = "gnu-x86_64-lp64-runtime-units/6";
	private const string FOREIGN_SCHEMA = "gnu-x86_64-lp64-runtime-units/6";
	private const string LEGACY_SCHEMA = "gnu-x86_64-lp64-typed-units/3";
	private const string LEGACY_FOREIGN_SCHEMA = "gnu-x86_64-lp64-foreign-units/4";
	private const string RUNTIME_CONTRACT = "runtime-contexts/1;tasks/17;endpoints/1;effects/1";
	private const string WINDOWS_FOREIGN_SCHEMA = "windows-x64-llp64-foreign-units/4";
	private static string foreign_schema(NativeModuleRecord record) {
		return record.windows ? WINDOWS_FOREIGN_SCHEMA : FOREIGN_SCHEMA;
	}

	private static bool foreign_schema_matches(NativeModuleRecord record, string schema) {
		return schema == foreign_schema (record) || record.legacy && schema == LEGACY_FOREIGN_SCHEMA;
	}

	private const int MAX_INTERFACES = GenericResourceLimits.NATIVE_UNITS;
	private const int MAX_DEPTH = GenericResourceLimits.NATIVE_DEPTH;
	private const int MAX_CALLABLES = GenericResourceLimits.NATIVE_CALLABLES;
	private const int MAX_TYPES = GenericResourceLimits.NATIVE_TYPES;
	private const int MAX_EDGES = MAX_INTERFACES * MAX_INTERFACES;
	private const int MAX_INTERFACE_PATHS = MAX_EDGES + MAX_INTERFACES;
	private const int MAX_INTERFACE_BYTES = 32 * 1024 * 1024;
	private GenericArray<NativeModuleRecord> records = new GenericArray<NativeModuleRecord> ();
	private HashTable<string, NativeModuleRecord> modules = new HashTable<string, NativeModuleRecord> (str_hash, str_equal);
	private HashTable<string, NativeModuleRecord> paths = new HashTable<string, NativeModuleRecord> (str_hash, str_equal);
	private HashTable<string, bool> active_paths = new HashTable<string, bool> (str_hash, str_equal);
	private HashTable<string, bool> active_modules = new HashTable<string, bool> (str_hash, str_equal);
	private int interface_bytes;
	private int interface_count;
	private int edge_count;
	private NativeModuleRecord? producer;
	private string[] requested;
	private string compiler_identity;
	private LlvmTargetMachineArtifact target;
	public GenericArray<SourceFile> inputs { get; private set; default = new GenericArray<SourceFile> (); }
	public NativeDeclarationRegistry declaration_registry { get; private set; default = new NativeDeclarationRegistry (); }
	// Typed units publish heap owner channels. Bind that ABI requirement to
	// exact selected declarations, independently of generic Class admission.
	public GenericArray<FunctionDeclarationSyntax> heap_boundaries { get; private set; default = new GenericArray<FunctionDeclarationSyntax> (); }
	private LinkInput[] dependencies = {};
	public LinkInput[] link_dependencies() {
		return dependencies;
	}

	public bool optimizer_exports { get { return producer != null && !producer.windows; } }
	public string[] required_types() {
		string[] result = {};
		foreach (var record in records) {
			foreach (string name in record.type_names) {
				result += name;
			}
		}
		return result;
	}

	private static string hash(string text) {
		return Checksum.compute_for_string (ChecksumType.SHA256, text);
	}

	private static string[] sorted(string[] values) {
		var list = new GLib.List<string> ();
		foreach (string value in values) {
			list.append (value);
		}
		list.sort ((a, b) => strcmp (a, b));
		string[] result = {};
		foreach (string value in list) {
			result += value;
		}
		return result;
	}

	private static string[] sorted_names(GLib.List<unowned string> names) {
		string[] values = {};
		foreach (string name in names) {
			values += name;
		}
		return sorted (values);
	}

	private static bool identifier(string value) {
		if (value.length == 0) {
			return false;
		}
		foreach (string component in value.split (".")) {
			if (component.length == 0 || !(component[0].isalpha () || component[0] == '_')) {
				return false;
			}
			for (int i = 1; i < component.length; i++) {
				if (!(component[i].isalnum () || component[i] == '_')) {
					return false;
				}
			}
		}
		return true;
	}

	private static bool nominal_selector(string value) {
		if (value.length > 512) {
			return false;
		}
		if (identifier (value)) {
			return true;
		}
		// Use the language's type grammar for ordered and nested applications.
		// This checks spelling only; nominal identity and supported channels
		// remain the responsibility of semantic and native declaration checks.
		var source = new SourceFile.from_text ("<native-export-selector>", "struct Selector { " + value + " value; }");
		var parsed = Parser.parse (source);
		if (parsed.diagnostic != null || parsed.unit.structs.length != 1 || parsed.unit.classes.length != 0 || parsed.unit.functions.length != 0) {
			return false;
		}
		var structure = parsed.unit.structs[0];
		if (structure.fields.length != 1 || structure.members.length != 1) {
			return false;
		}
		var type = structure.fields[0].type_name;
		return type is GenericTypeApplicationSyntax && type.spelling () == value;
	}

	private NativeMethodRequest? method_selector(string value, GenericArray<CompilationUnitSyntax> units, string module_name, bool is_export = false) throws NativeModuleError {
		int separator = value.index_of ("::");
		if (separator < 0) {
			return null;
		}
		string owner = value.substring (0, separator);
		string member = value.substring (separator + 2);
		if (!nominal_selector (owner) || !nominal_selector (member)) {
			reject ("astrac", "invalid closed native method selector");
		}
		var parsed = Parser.parse (new SourceFile.from_text ("<native-method-selector-" + hash (value).substring (0, 16) + ">",
			"namespace " + module_name + "; struct Selection { " + owner + " owner; " + member + " member; }"));
		if (parsed.diagnostic != null || parsed.unit.structs.length != 1 || parsed.unit.structs[0].fields.length != 2) {
			reject ("astrac", "invalid closed native method selector");
		}
		var fields = parsed.unit.structs[0].fields;
		var application = fields[1].type_name as GenericTypeApplicationSyntax;
		if (application == null || !identifier (application.lookup_name ()) || application.lookup_name ().contains (".")) {
			reject ("astrac", "native method selector requires one member name and explicit type arguments");
		}
		var result = new NativeMethodRequest (value, fields[0].type_name, application, is_export);
		// Retain the request's normal namespace scope, without introducing a
		// source storage declaration or a synthetic callable implementation.
		parsed.unit.structs.remove_range (0, parsed.unit.structs.length);
		units.add (parsed.unit);
		return result;
	}

	private static bool artifact_basename(string name) {
		if (name == "" || name == "." || name == ".." || name.length > 255 || Path.get_basename (name) != name) {
			return false;
		}
		for (int i = 0; i < name.length; i++) {
			if (!(name[i].isalnum () || name[i] == '_' || name[i] == '-' || name[i] == '.')) {
				return false;
			}
		}
		return true;
	}

	private static void reject(string path, string message) throws NativeModuleError {
		throw new NativeModuleError.CONTRACT ("%s: error: native module: %s", path, message);
	}

	private static void source_reject(SourceSpan span, string message) throws NativeModuleError {
		throw new NativeModuleError.CONTRACT ("%s", new Diagnostic (span, "native module: " + message).format ());
	}

	private static uint8[] read_artifact(string path, int limit) throws NativeModuleError {
		if (!FileUtils.test (path, FileTest.IS_REGULAR)) {
			reject (path, "cannot read a regular artifact file");
		}
		var stream = FileStream.open (path, "rb");
		if (stream == null) {
			reject (path, "cannot read artifact");
		}
		if (stream.seek (0, FileSeek.END) != 0) {
			reject (path, "artifact must be a finite seekable file");
		}
		long length = stream.tell ();
		if (length < 0 || length > limit) {
			reject (path, "artifact exceeds finite size limit");
		}
		if (stream.seek (0, FileSeek.SET) != 0) {
			reject (path, "cannot rewind artifact");
		}
		var bytes = new uint8[(int) length];
		int offset = 0;
		while (offset < bytes.length) {
			size_t count = stream.read (bytes[offset:]);
			if (count == 0) {
				reject (path, "artifact changed or failed during bounded read");
			}
			offset += (int) count;
		}
		if (stream.getc () != -1 || stream.error () != 0) {
			reject (path, "artifact changed or failed during bounded read");
		}
		return bytes;
	}

	private static string bytes_hash(string path, bool object = false, bool windows = false) throws NativeModuleError {
		uint8[] bytes = read_artifact (path, 128 * 1024 * 1024);
		if (object && windows) {
			if (bytes.length < 20 || bytes[0] != 0x64 || bytes[1] != 0x86 || bytes[16] != 0 || bytes[17] != 0 || bytes[2] == 0 && bytes[3] == 0 || 20U + 40U * ((uint) bytes[2] + 256U * bytes[3]) > bytes.length) {
				reject (path, "expected a bounded Windows x64 COFF relocatable object");
			}
		} else if (object && (bytes.length < 64 || bytes[0] != 0x7f || bytes[1] != 'E' || bytes[2] != 'L' || bytes[3] != 'F' || bytes[4] != 2 || bytes[5] != 1 || bytes[16] != 1 || bytes[17] != 0 || bytes[18] != 62 || bytes[19] != 0)) {
			reject (path, "expected a little-endian ELF64 x86-64 relocatable object");
		}
		return Checksum.compute_for_data (ChecksumType.SHA256, bytes);
	}

	private static string digest(KeyFile data, bool include_object) throws KeyFileError {
		var result = new StringBuilder ();
		foreach (string group in sorted (data.get_groups ())) {
			if (group == "receipt" || (!include_object && group == "object")) {
				continue;
			}
			result.append_printf ("%d:%s", group.length, group);
			foreach (string key in sorted (data.get_keys (group))) {
				if (!include_object && (key == "identity" || key == "symbol" || key == "declarations" || key == "declarations_sha256" || group.has_prefix ("foreign-import ") && key == "declaration")) {
					continue;
				}
				string value = data.get_value (group, key);
				result.append_printf ("%d:%s%d:%s", key.length, key, value.length, value);
			}
		}
		return hash (result.str);
	}

	private static string symbol(string identity, string key) {
		return "astra_mod_" + identity + "_" + hash (key);
	}

	public NativeModuleContext (string? module_name, string? interface_path, string[] exports, string[] imports, string selected_target = "host", string[]? legacy_imports = null) throws NativeModuleError {
		requested = exports;
		try {
			target = new LlvmTargetMachineArtifact (0, selected_target);
			if (target.triple != LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
				LlvmTargetMachineArtifact.qualify_c_systems (target.triple, target.pointer_bytes);
			}
			compiler_identity = bytes_hash (FileUtils.read_link ("/proc/self/exe"));
			if (module_name != null) {
				if (!identifier (module_name) || interface_path == null || exports.length == 0) {
					reject ("astrac", "producer requires a valid module, explicit exports and an interface path");
				}
				producer = new NativeModuleRecord (module_name, interface_path, false);
				producer.windows = target.triple == LlvmTargetMachineArtifact.WINDOWS_INTEROP;
			}
			var names = new HashTable<string, bool> (str_hash, str_equal);
			var legacy_paths = new HashTable<string, bool> (str_hash, str_equal);
			foreach (string path in legacy_imports ?? new string[0]) {
				legacy_paths.insert (Filename.canonicalize (path), true);
			}
			foreach (string path in sorted (imports)) {
				var record = resolve (path, 0, legacy_paths.contains (Filename.canonicalize (path)));
				if (names.contains (record.name)) {
					reject (path, "duplicate imported module identity");
				}
				names.insert (record.name, true);
				if (producer != null) {
					producer.dependencies.add (record);
				}
			}
			if (producer != null) {
				if (modules.contains (producer.name)) {
					reject (producer.path, "producer module conflicts with an imported nominal origin");
				}
				foreach (var dependency in producer.dependencies) {
					producer.dependency_depth = int.max (producer.dependency_depth, dependency.dependency_depth + 1);
				}
				if (producer.dependency_depth > MAX_DEPTH) {
					reject (producer.path, "dependency depth exceeds %d edges for producer %s".printf (MAX_DEPTH, producer.name));
				}
				if (modules.size () >= MAX_INTERFACES) {
					reject (producer.path, "dependency graph exceeds %d native units including producer".printf (MAX_INTERFACES));
				}
				foreach (var record in records) {
					verify_adjacent_artifacts (record, Path.get_dirname (Filename.canonicalize (producer.path)));
				}
				records.add (producer);
			}
		} catch (LlvmError error) {
			reject ("astrac", error.message);
		} catch (FileError error) {
			reject ("astrac", error.message);
		}
	}

	// A bounded postorder traversal publishes each nominal module once. Aliased
	// artifact copies are still validated beside their own referring interface.
	private NativeModuleRecord resolve(string input_path, int depth, bool legacy = false) throws NativeModuleError {
		string path = Filename.canonicalize (input_path);
		if (depth > MAX_DEPTH) {
			reject (path, "dependency depth exceeds %d edges".printf (MAX_DEPTH));
		}
		if (active_paths.contains (path)) {
			reject (path, "dependency cycle at interface path");
		}
		var cached = paths.lookup (path);
		if (cached != null) {
			if (depth + cached.dependency_depth > MAX_DEPTH) {
				reject (path, "dependency depth exceeds %d edges through cached module %s".printf (MAX_DEPTH, cached.name));
			}
			return cached;
		}
		if (++interface_count > MAX_INTERFACE_PATHS) {
			reject (path, "dependency graph exceeds %d interface paths".printf (MAX_INTERFACE_PATHS));
		}
		active_paths.insert (path, true);
		var record = load (path, legacy);
		if (active_modules.contains (record.name)) {
			reject (path, "dependency cycle at nominal module " + record.name);
		}
		active_modules.insert (record.name, true);
		try {
			foreach (string group in sorted (record.data.get_groups ())) {
				if (!group.has_prefix ("dependency ")) {
					continue;
				}
				if (++edge_count > MAX_EDGES) {
					reject (path, "dependency graph exceeds %d edges".printf (MAX_EDGES));
				}
				string name = group.substring (11);
				string filename = record.data.get_string (group, "interface");
				if (!identifier (name) || !artifact_basename (filename)) {
					reject (path, "dependency requires a nominal module and safe adjacent interface basename");
				}
				string adjacent = Path.build_filename (Path.get_dirname (path), filename);
				bool legacy_dependency = record.legacy;
				if (!record.windows && !record.legacy) {
					// A current-schema edge is strict by default. Only an explicit
					// legacy marker can waive the current compiler/schema identity.
					string compatibility = record.data.has_key (group, "compatibility") ? record.data.get_string (group, "compatibility") : "runtime/5";
					if (compatibility != "runtime/5" && compatibility != "legacy-unchanged/1") {
						reject (path, "unknown dependency compatibility contract");
					}
					legacy_dependency = compatibility == "legacy-unchanged/1";
				}
				var dependency = resolve (adjacent, depth + 1, legacy_dependency);
				if (dependency.name != name || dependency.interface_hash != record.data.get_string (group, "interface_sha256") || dependency.data.get_string ("object", "sha256") != record.data.get_string (group, "object_sha256") || dependency.data.get_string ("abi", "identity") != record.data.get_string (group, "abi_identity")) {
					reject (path, "dependency module/interface/object/ABI identity mismatch: " + name);
				}
				record.dependencies.add (dependency);
				record.dependency_depth = int.max (record.dependency_depth, dependency.dependency_depth + 1);
			}
			check_symbols (record);
			var prior = modules.lookup (record.name);
			if (prior != null) {
				if (prior.interface_hash != record.interface_hash || prior.data.get_string ("object", "sha256") != record.data.get_string ("object", "sha256") || prior.data.get_string ("abi", "identity") != record.data.get_string ("abi", "identity")) {
					reject (path, "conflicting imported nominal module origin: " + record.name);
				}
				record = prior;
			} else {
				if (modules.size () >= MAX_INTERFACES) {
					reject (path, "dependency graph exceeds %d native units".printf (MAX_INTERFACES));
				}
				modules.insert (record.name, record);
				records.add (record);
				inputs.add (record.declarations);
				foreach (var declaration in record.foreign_declarations) {
					inputs.add (declaration);
				}
				declaration_registry.add_types (record.declarations, record.type_names);
				foreach (string key in record.keys) {
					declaration_registry.add (record.declarations, new NativeDeclarationIdentity (
						record.data.get_string ("abi", "identity"), key,
						record.data.get_string ("function " + key, "symbol"), record.data.get_string ("function " + key, "signature"), record.data.get_string ("function " + key, "receiver_field"), record.data.get_boolean ("function " + key, "readonly"),
						record.data.get_string ("function " + key, "readonly_inputs"), record.data.get_string ("function " + key, "callback_inputs"), record.windows || record.legacy ? "" : record.data.get_string ("function " + key, "lifetimes"), record.data.has_group ("task " + key) ? 1 : 0));
				}
				dependencies += new LinkInput.object_file (record.object_path);
			}
		} catch (KeyFileError error) {
			reject (path, "malformed dependency: " + error.message);
		}
		active_modules.remove (record.name);
		active_paths.remove (path);
		paths.insert (path, record);
		return record;
	}

	private NativeModuleRecord load(string path, bool legacy) throws NativeModuleError {
		try {
			if (FileUtils.test (path, FileTest.IS_SYMLINK)) {
				reject (path, "interface symlinks are not admitted");
			}
			uint8[] bytes = read_artifact (path, 2 * 1024 * 1024);
			interface_bytes += bytes.length;
			if (interface_bytes > MAX_INTERFACE_BYTES) {
				reject (path, "dependency interfaces exceed 32 MiB aggregate limit");
			}
			var input = new SourceFile (path, (owned) bytes);
			if (input.validate_encoding () != null) {
				reject (path, "interface must contain valid UTF-8 without NUL");
			}
			string text = input.slice (0, input.length);
			var record = new NativeModuleRecord ("", path, true);
			record.legacy = legacy;
			record.windows = target.triple == LlvmTargetMachineArtifact.WINDOWS_INTEROP;
			record.interface_hash = hash (text);
			record.data.load_from_data (text, text.length, KeyFileFlags.NONE);
			var data = record.data;
			if (data.to_data () != text) {
				reject (path, "interface is not in its canonical unique-field form");
			}
			string schema = data.get_string ("abi", "schema");
			// Declared legacy schemas still have their original group grammar,
			// including when a caller has not opted into legacy compatibility.
			if (schema == LEGACY_SCHEMA) {
				foreach (string group in data.get_groups ()) {
					if (group.has_prefix ("foreign ") || group.has_prefix ("foreign-import ")) {
						reject (path, "unknown interface group");
					}
				}
			}
			if (data.get_string ("abi", "format") != FORMAT || (legacy ? record.windows || schema != LEGACY_SCHEMA && schema != LEGACY_FOREIGN_SCHEMA : (record.windows ? schema != WINDOWS_FOREIGN_SCHEMA : schema != SCHEMA) || data.get_string ("abi", "compiler") != compiler_identity)) {
				reject (path, "interface version/schema/compiler fingerprint mismatch; rebuild all native units or explicitly select compatible legacy import");
			}
			if (!record.windows && !legacy && data.get_string ("abi", "runtime") != RUNTIME_CONTRACT) {
				reject (path, "runtime context/task/endpoint/effect ABI version mismatch; rebuild native unit");
			}
			if (data.get_string ("abi", "target") != target.triple || data.get_string ("abi", "data_layout") != target.data_layout) {
				reject (path, "target triple/data layout mismatch");
			}
			record.name = data.get_string ("abi", "module");
			if (!identifier (record.name)) {
				reject (path, "invalid nominal module identity");
			}
			foreach (string group in data.get_groups ()) {
				string[] allowed;
				if (group == "abi") {
					allowed = {
						"format", "schema", "module", "compiler", "target", "data_layout", "declarations", "declarations_sha256", "identity"
					};
					if (!record.windows && !legacy) {
						allowed += "runtime";
					}
				} else if (group == "object") {
					allowed = {
						"file", "sha256"
					};
				} else if (group == "receipt") {
					allowed = {
						"fingerprint"
					};
				} else if (group.has_prefix ("function ")) {
					allowed = {
						"receiver_field", "signature", "symbol", "readonly", "readonly_inputs", "callback_inputs"
					};
					if (!record.windows && !legacy) {
						allowed += "lifetimes";
						allowed += "optimizer";
					}
					record.keys.add (group.substring (9));
				} else if (group.has_prefix ("type ")) {
					allowed = {
						"layout", "symbol"
					};
					record.type_names.add (group.substring (5));
				} else if (group.has_prefix ("task ")) {
					if (legacy) {
						reject (path, "legacy task/frame ABI changed; rebuild native unit for runtime schema /6");
					}
					allowed = {
						"contract", "frame"
					};
				} else if (group.has_prefix ("allocator ")) {
					allowed = {
						"kind"
					};
				} else if (foreign_schema_matches (record, schema) && group.has_prefix ("foreign ")) {
					allowed = {
						"contract", "symbols"
					};
				} else if (foreign_schema_matches (record, schema) && group.has_prefix ("foreign-import ")) {
					allowed = {
						"contract", "declaration"
					};
				} else if (group.has_prefix ("dependency ")) {
					allowed = {
						"interface", "interface_sha256", "object_sha256", "abi_identity"
					};
					if (!record.windows && !legacy && data.has_key (group, "compatibility")) {
						allowed += "compatibility";
					}
				} else {
					reject (path, "unknown interface group");
					return record;
				}
				var actual = sorted (data.get_keys (group));
				var expected = sorted (allowed);
				if (actual.length != expected.length) {
					reject (path, "missing/unknown interface field");
				}
				for (int i = 0; i < actual.length; i++) {
					if (actual[i] != expected[i]) {
						reject (path, "missing/unknown interface field");
					}
				}
			}
			if (record.keys.length == 0 && record.type_names.length == 0 || record.keys.length > MAX_CALLABLES || record.type_names.length > MAX_TYPES || digest (data, false) != data.get_string ("abi", "identity") || digest (data, true) != data.get_string ("receipt", "fingerprint")) {
				reject (path, "interface fingerprint/inventory mismatch");
			}
			foreach (string group in data.get_groups ()) {
				if (!group.has_prefix ("foreign ")) {
					continue;
				}
				bool found = false;
				foreach (string name in record.type_names) {
					found |= group == "foreign " + name;
				}
				if (!found || data.get_string (group, "contract") == "") {
					reject (path, "foreign metadata requires its exact exported nominal Class");
				}
			}
			foreach (string key in record.keys) {
				if (!record.windows && !legacy) {
					try {
						OptimizerSummary.decode (data.get_string ("function " + key, "optimizer"));
					} catch (OptimizerSummaryError failure) {
						reject (path, "invalid optimizer summary: " + failure.message);
					}
				}
				if (!record.windows && !legacy) {
					try {
						RuntimeLifetimeSummary.decode (data.get_string ("function " + key, "lifetimes"));
					} catch (RuntimeLifetimeError failure) {
						reject (path, "invalid versioned lifetime contract: " + failure.message);
					}
				}
				string effect = data.get_string ("function " + key, "readonly");
				if (effect != "true" && effect != "false") {
					reject (path, "readonly effect requires canonical true/false");
				}
				string readonly_inputs = data.get_string ("function " + key, "readonly_inputs");
				string callback_inputs = data.get_string ("function " + key, "callback_inputs");
				if (!Astra.Code.CodeInputSet.valid (readonly_inputs, int.MAX) || !Astra.Code.CodeInputSet.valid (callback_inputs, int.MAX) ||
				    effect == "false" && readonly_inputs != "") {
					reject (path, "callback effects require canonical Fn input ordinals and readonly eligibility");
				}
			}
			foreach (string group in data.get_groups ()) {
				if (!group.has_prefix ("task ")) {
					continue;
				}
				bool declared = false;
				foreach (string key in record.keys) {
					declared |= group == "task " + key;
				}
				string frame = data.get_string (group, "frame");
				if (!declared || frame.length != 64 || data.get_string (group, "contract") == "") {
					reject (path, "task contract requires its exact declared callable and frame identity");
				}
				for (int i = 0; i < frame.length; i++) {
					char value = frame[i];
					if (!(value >= '0' && value <= '9' || value >= 'a' && value <= 'f')) {
						reject (path, "invalid private task frame fingerprint");
					}
				}
			}
			foreach (string key in record.keys) {
				if (!key.has_prefix ("F:" + record.name + ".") && !key.has_prefix ("C:" + record.name + ".")) {
					reject (path, "callable is outside exact module namespace");
				}
			}
			foreach (string name in record.type_names) {
				if (!nominal_selector (name) || !name.has_prefix (record.name + ".")) {
					reject (path, "type is outside exact module namespace");
				}
			}
			string declarations = data.get_string ("abi", "declarations");
			if (hash (declarations) != data.get_string ("abi", "declarations_sha256")) {
				reject (path, "declaration identity mismatch");
			}
			record.declarations = new SourceFile.from_text (path + ".declarations.astra", declarations, true);
			if (record.declarations.validate_encoding () != null) {
				reject (path, "invalid declaration bytes");
			}
			foreach (string group in data.get_groups ()) {
				if (!group.has_prefix ("foreign-import ")) {
					continue;
				}
				string name = group.substring (15);
				if (!ForeignClassPolicy.identifier (name) || data.get_string (group, "contract") == "") {
					reject (path, "foreign import requires an exact nominal declaration");
				}
				var foreign = new SourceFile.from_text (path + ".foreign-" + name + ".astra", data.get_string (group, "declaration"));
				if (foreign.validate_encoding () != null) {
					reject (path, "invalid foreign declaration bytes");
				}
				var parsed = Parser.parse (foreign);
				if (parsed.diagnostic != null || parsed.unit.functions.length != 0 || parsed.unit.structs.length != 0 || parsed.unit.classes.length != 0 || parsed.unit.enums.length != 0 || parsed.unit.constants.length != 0 || parsed.unit.imports.length != 0 || parsed.unit.async_runtimes.length != 0 || !foreign_import_unit (parsed.unit, name)) {
					reject (path, "foreign import metadata admits one bodyless typed COM declaration");
				}
				record.foreign_declarations.add (foreign);
			}
			string filename = data.get_string ("object", "file");
			if (!artifact_basename (filename)) {
				reject (path, "object must reside beside interface with a safe basename");
			}
			record.object_path = Path.build_filename (Path.get_dirname (Filename.canonicalize (path)), filename);
			if (FileUtils.test (record.object_path, FileTest.IS_SYMLINK) || bytes_hash (record.object_path, true, record.windows) != data.get_string ("object", "sha256")) {
				reject (path, "implementation object identity mismatch");
			}
			return record;
		} catch (KeyFileError error) {
			reject (path, "malformed interface: " + error.message);
		}
		assert_not_reached ();
	}

	private static HashTable<string, bool> allocator_symbols(NativeModuleRecord record) throws NativeModuleError, KeyFileError {
		var result = new HashTable<string, bool> (str_hash, str_equal);
		foreach (string group in record.data.get_groups ()) {
			if (!group.has_prefix ("allocator ")) {
				continue;
			}
			string identity = group.substring (10);
			if (identity.length != 64) {
				reject (record.path, "invalid compiler allocation domain identity");
			}
			for (int i = 0; i < identity.length; i++) {
				char value = identity[i];
				if (!(value >= '0' && value <= '9' || value >= 'a' && value <= 'f')) {
					reject (record.path, "invalid compiler allocation domain identity");
				}
			}
			var kind = AllocationKind.parse (record.data.get_string (group, "kind"));
			if (kind == AllocationKind.INVALID || kind == AllocationKind.CUSTOM) {
				reject (record.path, "unsupported native module allocation domain");
			}
			string prefix = "astra_alloc12_domain_" + identity;
			result.insert (prefix, true);
			if (kind != AllocationKind.HEAP) {
				result.insert (prefix + "_bytes", true);
				result.insert (prefix + "_blocks", true);
			}
		}
		return result;
	}

	private static void check_symbols(NativeModuleRecord record) throws NativeModuleError, KeyFileError {
		string output, diagnostic;
		int status;
		try {
			Process.spawn_sync (null, new string[] { "nm", "-g", "--defined-only", record.object_path }, null, SpawnFlags.SEARCH_PATH, null, out output, out diagnostic, out status);
		} catch (SpawnError error) {
			reject (record.path, "ELF symbol inspection unavailable: " + error.message);
			return;
		}
		if (status != 0) {
			reject (record.path, "implementation symbol inspection failed: " + diagnostic);
		}
		var expected = new HashTable<string, bool> (str_hash, str_equal);
		var domains = allocator_symbols (record);
		string identity = record.data.get_string ("abi", "identity");
		foreach (string key in record.keys) {
			string name = symbol (identity, key);
			if (record.data.get_string ("function " + key, "symbol") != name) {
				reject (record.path, "exported symbol fingerprint mismatch");
			}
			expected.insert (name, true);
			if (record.data.has_group ("task " + key)) {
				expected.insert (name + "_resume", true);
				expected.insert (name + "_destroy", true);
				expected.insert (name + "_checked", true);
			}
		}
		foreach (string type in record.type_names) {
			string name = record.data.get_string ("type " + type, "symbol");
			if (name == "") {
				continue;
			}
			if (name != symbol (identity, "D:" + type)) {
				reject (record.path, "exported descriptor fingerprint mismatch");
			}
			expected.insert (name, true);
		}
		foreach (string group in record.data.get_groups ()) {
			if (!group.has_prefix ("foreign ")) {
				continue;
			}
			string names = record.data.get_string (group, "symbols");
			if (names == "") {
				continue;
			}
			foreach (string name in names.split (",")) {
				if (!ForeignClassPolicy.identifier (name) || expected.contains (name)) {
					reject (record.path, "invalid or duplicate foreign bridge symbol");
				}
				expected.insert (name, true);
			}
		}
		foreach (string raw in output.split ("\n")) {
			string line = raw.strip ();
			if (line == "") {
				continue;
			}
			string[] parts = line.split_set (" \t");
			string name = parts[parts.length - 1];
			if (!expected.remove (name) && !domains.remove (name)) {
				reject (record.path, "unexpected public implementation symbol: " + name);
			}
		}
		if (expected.size () != 0) {
			reject (record.path, "implementation is missing exact declared native exports");
		}
	}

	private static string foreign_attributes(SyntaxNode node) {
		var text = new StringBuilder ();
		if (node.foreign_member != null) {
			text.append (foreign_attribute (node.foreign_member));
		}
		foreach (var channel in node.foreign_channels) {
			text.append (foreign_attribute (channel));
		}
		return text.str;
	}

	private static string foreign_attribute(ForeignPolicySyntax policy) {
		var text = new StringBuilder ("[" + policy.name.spelling ());
		if (policy.entries.length != 0) {
			text.append ("(");
			for (int e = 0; e < policy.entries.length; e++) {
				var entry = policy.entries[e];
				if (e != 0) {
					text.append (",");
				}
				text.append (entry.key.spelling () + "=\"" + entry.decoded_value.escape () + "\"");
			}
			text.append (")");
		}
		text.append ("]\n");
		return text.str;
	}

	private string storage_attributes(NativeInstanceDeclarationSyntax type) throws NativeModuleError {
		var text = new StringBuilder ();
		var object = type as ClassDeclarationSyntax;
		if (object != null && object.foreign_export != null) {
			if (!ForeignApiAdmission.selected (object)) {
				source_reject (type.span, "foreign personality roots require one checked compilation unit");
			}
			text.append (foreign_attribute (object.foreign_export));
			if (object.com_export != null) {
				text.append (foreign_attribute (object.com_export));
			}
			if (object.gobject_export != null) {
				text.append (foreign_attribute (object.gobject_export));
			}
		}
		if (type is ClassDeclarationSyntax && ((ClassDeclarationSyntax) type).exception_root != null) {
			text.append ("[ExceptionRoot]\n");
		}
		if (type.concurrency_policy != null) {
			var policy = type.concurrency_policy;
			if (policy.actor) {
				source_reject (type.span, "Actor callback identities currently require one checked compilation unit");
			}
			if (policy.singleton) {
				source_reject (type.span, "process Singleton roots currently require one checked compilation unit");
			}
			if (!policy.valid ()) {
				source_reject (type.span, "invalid concurrency policy in native declaration export");
			}
			if (policy.shared) {
				text.append ("[Shared]\n");
			}
			if (policy.monitor) {
				text.append ("[Monitor]\n");
			}
			if (policy.singleton) {
				text.append ("[Singleton]\n");
			}
			if (policy.thread_bound) {
				text.append ("[ThreadBound]\n");
			}
			if (policy.actor) {
				text.append ("[Actor]\n");
			}
		}
		if (type.allocator != null) {
			foreach (var entry in type.allocator) {
				if (entry.key.spelling () == "kind" && entry.decoded_value == "custom") {
					source_reject (type.span, "custom allocator code exports must remain in one checked compilation unit");
				}
			}
			text.append ("[Allocator(");
			int rank = 0;
			foreach (var entry in type.allocator) {
				if (rank++ != 0) {
					text.append (",");
				}
				text.append (entry.key.spelling () + "=\"" + entry.decoded_value.escape () + "\"");
			}
			text.append (")]\n");
		}
		if (type.representation != null) {
			text.append ("[Repr(");
			int rank = 0;
			foreach (var entry in type.representation) {
				if (rank++ != 0) {
					text.append (",");
				}
				text.append (entry.key.spelling () + "=\"" + entry.decoded_value.escape () + "\"");
			}
			text.append (")]\n");
		}
		if (type.alignment != null) {
			text.append ("[Align(");
			int rank = 0;
			foreach (var entry in type.alignment) {
				if (rank++ != 0) {
					text.append (",");
				}
				text.append (entry.key.spelling () + "=\"" + entry.decoded_value.escape () + "\"");
			}
			text.append (")]\n");
		}
		return text.str;
	}

	// Foreign nominal declarations keep their original source authority. They
	// are not native Classes and never acquire implementation symbols here.
	private static bool foreign_import_unit(CompilationUnitSyntax unit, string name) {
		if (unit.c_classes.length == 1 && unit.com_interfaces.length == 0) {
			var declaration = unit.c_classes[0];
			return declaration.foreign_import != null && declaration.name.spelling () == name;
		}
		return unit.c_classes.length == 0 && unit.com_interfaces.length == 1 && unit.com_interfaces[0].declaration != null && unit.com_interfaces[0].name.spelling () == name;
	}

	private void capture_foreign_import(ClassDeclarationSyntax declaration) throws NativeModuleError {
		if (declaration.foreign_import == null || declaration.span.file.native_interface || inherited_foreign_source (declaration.span.file)) {
			return;
		}
		string text = foreign_attribute (declaration.foreign_import) + (declaration.foreign_import.kind == DeclarationPolicyId.COM_IMPORT ? "interface " : "class ") + declaration.name.spelling () + (declaration.parent_class == null ? "" : " : " + declaration.parent_class.spelling ()) + " {\n";
		foreach (var member in declaration.members) {
			var property = member as PropertyDeclarationSyntax;
			var function = member as FunctionDeclarationSyntax;
			if (property != null) {
				text += property_prototype (property, true, true);
			} else if (function != null) {
				text += prototype (function, false, true);
			} else {
				source_reject (member.span, "foreign import requires a bodyless callable declaration");
			}
		}
		text += "}\n";
		producer.data.set_string ("abi", "schema", foreign_schema (producer));
		producer.data.set_string ("foreign-import " + declaration.name.spelling (), "declaration", text);
	}

	private bool inherited_foreign_source(SourceFile file) {
		foreach (var record in records) {
			foreach (var declaration in record.foreign_declarations) {
				if (declaration == file) {
					return true;
				}
			}
		}
		return false;
	}

	public SyntaxProgram capture_exports(SyntaxProgram program) throws NativeModuleError {
		foreach (var record in records) {
			if (!record.imported) {
				continue;
			}
			foreach (var unit in program.units) {
				if (unit.span.file != record.declarations) {
					continue;
				}
				foreach (var function in unit.functions) {
					require_declaration_body (function);
					heap_boundaries.add (function);
				}
				foreach (var type in unit.native_instances ()) {
					bool interface_declaration = type is ClassDeclarationSyntax && ((ClassDeclarationSyntax) type).is_interface;
					foreach (var member in type.members) {
						var function = member as FunctionDeclarationSyntax;
						// The interface grammar permits only bodyless operations.
						// Its parser-generated abstract placeholder is not an
						// implementation distributed in the interface artifact.
						if (function != null) {
							if (!interface_declaration) {
								require_declaration_body (function);
							}
							heap_boundaries.add (function);
						}
						var property = member as PropertyDeclarationSyntax;
						if (!interface_declaration && property != null && (property.getter.body.statements.length != 0 || property.setter != null && property.setter.body.statements.length != 0)) {
							source_reject (property.span, "native interface cannot contain executable property bodies");
						}
					}
				}
			}
		}
		var method_units = new GenericArray<CompilationUnitSyntax> ();
		foreach (var record in records) {
			if (!record.imported) {
				continue;
			}
			foreach (string key in record.keys) {
				if (!key.has_prefix ("C:")) {
					continue;
				}
				int separator = key.index_of ("::");
				if (separator < 0 || !key.substring (separator + 2).contains ("<")) {
					continue;
				}
				var request = method_selector (key.substring (2), method_units, record.name);
				if (request == null) {
					reject (record.path, "closed member declaration lost its exact method tuple");
				}
				declaration_registry.method_requests.add (request);
			}
		}
		if (producer == null) {
			if (method_units.length == 0) {
				return program;
			}
			var units = new GenericArray<CompilationUnitSyntax> ();
			foreach (var unit in program.units) {
				units.add (unit);
			}
			foreach (var unit in method_units) {
				units.add (unit);
			}
			try {
				return new SyntaxProgram (units);
			} catch (SourceSetError error) {
				reject ("astrac", "closed imported method requests: " + error.message);
			}
		}
		foreach (var unit in program.units) {
			foreach (var declaration in unit.c_classes) {
				capture_foreign_import (declaration);
			}
			foreach (var imported in unit.com_interfaces) {
				if (imported.declaration != null) {
					capture_foreign_import (imported.declaration);
				}
			}
		}
		foreach (var imported in program.com_interfaces) {
			if (imported.declaration == null) {
				source_reject (imported.span, "selected COMImport interfaces require one checked compilation unit");
			}
		}
		var wanted = new HashTable<string, bool> (str_hash, str_equal);
		var explicit_selectors = new HashTable<string, bool> (str_hash, str_equal);
		var selected_methods = new HashTable<string, bool> (str_hash, str_equal);
		foreach (string name in requested) {
			if (explicit_selectors.contains (name)) {
				reject ("astrac", "invalid/duplicate native export selector");
			}
			explicit_selectors.insert (name, true);
			var method = method_selector (name, method_units, producer.name, true);
			if (method != null) {
				if (selected_methods.contains (name)) {
					reject ("astrac", "invalid/duplicate native export selector");
				}
				selected_methods.insert (name, true);
				declaration_registry.method_requests.add (method);
				wanted.insert (method.owner.spelling (), true);
				continue;
			}
			if (!nominal_selector (name)) {
				reject ("astrac", "invalid/duplicate native export selector");
			}
			wanted.insert (name, true);
		}
		var types = new HashTable<string, NativeInstanceDeclarationSyntax> (str_hash, str_equal);
		var functions = new HashTable<string, FunctionDeclarationSyntax> (str_hash, str_equal);
		foreach (var unit in program.units) {
			if (unit.namespace_name == null || unit.namespace_name.spelling () != producer.name) {
				continue;
			}
			foreach (var type in unit.native_instances ()) {
				string name = producer.name + "." + type.name.spelling ();
				bool selected = wanted.contains (name);
				foreach (string selector in requested) {
					if (selector.has_prefix (name + "<")) {
						selected = true;
					}
				}
				if (!selected) {
					continue;
				}
				if (type.module_internal) {
					source_reject (type.span, "internal type cannot be exported");
				}
				types.insert (name, type);
			}
			foreach (var function in unit.functions) {
				string name = producer.name + "." + function.name.spelling ();
				if (wanted.contains (name)) {
					if (function.module_internal) {
						source_reject (function.span, "internal function cannot be exported");
					}
					functions.insert (name, function);
				}
			}
		}
		var header = new StringBuilder ("namespace " + producer.name + ";\n");
		// Unqualified nominal names in exported prototypes keep the selected
		// source files' namespace imports. Typed binding below still requires
		// exact dependency origins and signatures; a using is no proof itself.
		var imported_namespaces = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var unit in program.units) {
			if (unit.namespace_name == null || unit.namespace_name.spelling () != producer.name) {
				continue;
			}
			bool selected_file = false;
			foreach (var type in types.get_values ()) {
				selected_file |= type.span.file == unit.span.file;
			}
			foreach (var function in functions.get_values ()) {
				selected_file |= function.span.file == unit.span.file;
			}
			if (!selected_file) {
				continue;
			}
			foreach (var name in unit.imports) {
				imported_namespaces.insert (name.spelling (), true);
			}
		}
		foreach (string name in sorted_names (imported_namespaces.get_keys ())) {
			header.append ("using " + name + ";\n");
		}
		var requests = new StringBuilder ("namespace " + producer.name + ";\n");
		bool closed_requests = method_units.length != 0;
		foreach (string name in sorted_names (types.get_keys ())) {
			var type = types.lookup (name);
			foreach (var member in type.members) {
				if (member is FunctionDeclarationSyntax) {
					heap_boundaries.add ((FunctionDeclarationSyntax) member);
				}
			}
			var object = type as ClassDeclarationSyntax;
			var parameters = object == null ? ((StructDeclarationSyntax) type).type_parameters : object.type_parameters;
			header.append (storage_attributes (type));
			if (parameters.length != 0) {
				if (wanted.contains (name)) {
					source_reject (type.span, "generic native export requires explicit closed type arguments");
				}
				if (object != null && (object.is_interface || object.parent_class != null || object.exception_root != null)) {
					source_reject (type.span, "native dispatch and exception metadata are not complete for this declaration");
				}
				header.append_printf ("%s %s<", object == null ? "struct" : "class", type.name.spelling ());
				for (int p = 0; p < parameters.length; p++) {
					header.append ((p == 0 ? "" : ",") + parameters[p].spelling ());
				}
				header.append (">");
				if (object != null) {
					foreach (var clause in object.where_clauses) {
						header.append (" " + clause.span.text ());
					}
				} else {
					foreach (var clause in ((StructDeclarationSyntax) type).where_clauses) {
						header.append (" " + clause.span.text ());
					}
				}
				header.append (" {\n");
				foreach (var field in type.fields) {
					header.append ("\t" + (field.private_keyword == null ? "" : "private ") + (field.readonly_keyword == null ? "" : "readonly ") + (field.owned_keyword == null ? "" : "owned ") + field.type_name.spelling () + " " + field.name.spelling () + ";\n");
				}
				foreach (var member in type.members) {
					if (member is StructFieldDeclarationSyntax) {
						continue;
					}
					if (member is PropertyDeclarationSyntax) {
						header.append (property_prototype ((PropertyDeclarationSyntax) member));
						continue;
					}
					var function = member as FunctionDeclarationSyntax;
					if (function == null || function.dispatch != MemberDispatchSyntax.DIRECT) {
						source_reject (member.span, "generic unit properties and virtual members are outside the selected profile");
					}
					header.append ("\t" + prototype (function, true));
				}
				header.append ("}\n");
				foreach (string selector in sorted_names (wanted.get_keys ())) {
					if (!selector.has_prefix (name + "<")) {
						continue;
					}
					producer.type_names.add (selector);
					wanted.remove (selector);
					string anchor = "__astra_unit_type_" + hash (selector).substring (0, 16);
					if (types.contains (producer.name + "." + anchor)) {
						source_reject (type.span, "native unit declaration witness name conflicts with an exported type");
					}
					string ownership = object == null ? "" : "owned ";
					header.append_printf ("internal struct %s { %s%s value; }\n", anchor, ownership, selector);
					requests.append_printf ("internal struct %s { %s%s value; }\n", anchor, ownership, selector);
					closed_requests = true;
				}
				continue;
			}
			if (object != null) {
				int constructors = 0;
				foreach (var member in object.members) {
					var lifecycle = member as LifecycleDeclarationSyntax;
					if (lifecycle != null && lifecycle.is_constructor) {
						constructors++;
					}
				}
				if (!object.is_interface && constructors != 1) {
					source_reject (type.span, "Class interface requires an explicit constructor");
				}
			}
			header.append_printf ("%s %s%s {\n", object == null ? "struct" : object.is_interface ? "interface" : "class",
				type.name.spelling (), object == null || object.parent_class == null ? "" : " : " + object.parent_class.spelling ());
			bool foreign_root = object != null && object.foreign_export != null;
			foreach (var field in type.fields) {
				if (foreign_root) {
					continue;
				}
				header.append ("\t" + (field.private_keyword == null ? "" : "private ") + (field.readonly_keyword == null ? "" : "readonly ") + (field.owned_keyword == null ? "" : "owned ") + field.type_name.spelling () + " " + field.name.spelling () + ";\n");
			}
			if (object == null && type.members.length != type.fields.length) {
				source_reject (type.span, "record module types cannot have methods or properties");
			}
			foreach (var member in type.members) {
				if (member is StructFieldDeclarationSyntax) {
					if (foreign_root) {
						var field = (StructFieldDeclarationSyntax) member;
						header.append ("\t" + (field.private_keyword == null ? "" : "private ") + (field.readonly_keyword == null ? "" : "readonly ") + (field.owned_keyword == null ? "" : "owned ") + field.type_name.spelling () + " " + field.name.spelling () + ";\n");
					}
					continue;
				}
				if (object != null && object.is_interface && member is LifecycleDeclarationSyntax) {
					continue;
				}
				if (member is PropertyDeclarationSyntax) {
					header.append (property_prototype ((PropertyDeclarationSyntax) member, object != null && object.is_interface));
					continue;
				}
				var function = member as FunctionDeclarationSyntax;
				if (function == null) {
					source_reject (member.span, "native member requires its exact callable declaration");
				}
				header.append ("\t" + prototype (function, false, object != null && object.is_interface));
			}
			header.append ("}\n");
			producer.type_names.add (name);
			wanted.remove (name);
		}
		foreach (string name in sorted_names (functions.get_keys ())) {
			heap_boundaries.add (functions.lookup (name));
			header.append (prototype (functions.lookup (name)));
			producer.keys.add ("F:" + name);
			wanted.remove (name);
		}
		if (wanted.size () != 0 || producer.keys.length == 0 && producer.type_names.length == 0) {
			reject ("astrac", "native export selector missing or surface is empty");
		}
		if (producer.keys.length > MAX_CALLABLES || producer.type_names.length > MAX_TYPES) {
			reject ("astrac", "native export inventory exceeds %d callables or %d types".printf (MAX_CALLABLES, MAX_TYPES));
		}
		var data = producer.data;
		data.set_string ("abi", "format", FORMAT);
		bool foreign_imports = false;
		foreach (string group in data.get_groups ()) {
			foreign_imports |= group.has_prefix ("foreign-import ");
		}
		data.set_string ("abi", "schema", producer.windows ? WINDOWS_FOREIGN_SCHEMA : foreign_imports ? FOREIGN_SCHEMA : SCHEMA);
		if (!producer.windows) {
			data.set_string ("abi", "runtime", RUNTIME_CONTRACT);
		}
		data.set_string ("abi", "module", producer.name);
		data.set_string ("abi", "compiler", compiler_identity);
		data.set_string ("abi", "target", target.triple);
		data.set_string ("abi", "data_layout", target.data_layout);
		data.set_string ("abi", "declarations", header.str);
		data.set_string ("abi", "declarations_sha256", hash (header.str));
		try {
			var direct = new HashTable<string, NativeModuleRecord> (str_hash, str_equal);
			foreach (var dependency in producer.dependencies) {
				direct.insert (dependency.name, dependency);
			}
			foreach (string name in sorted_names (direct.get_keys ())) {
				var dependency = direct.lookup (name);
				string group = "dependency " + name;
				data.set_string (group, "interface", Path.get_basename (dependency.path));
				data.set_string (group, "interface_sha256", dependency.interface_hash);
				data.set_string (group, "object_sha256", dependency.data.get_string ("object", "sha256"));
				data.set_string (group, "abi_identity", dependency.data.get_string ("abi", "identity"));
				if (!producer.windows) {
					data.set_string (group, "compatibility", dependency.legacy ? "legacy-unchanged/1" : "runtime/5");
				}
			}
		} catch (KeyFileError error) {
			reject (producer.path, "invalid producer dependency: " + error.message);
		}
		if (!closed_requests) {
			return program;
		}
		var parsed = Parser.parse (new SourceFile.from_text ("<native-module-requests-" + producer.name + ">", requests.str));
		if (parsed.diagnostic != null) {
			source_reject (parsed.diagnostic.span, "invalid closed module request model: " + parsed.diagnostic.message);
		}
		var units = new GenericArray<CompilationUnitSyntax> ();
		foreach (var unit in program.units) {
			units.add (unit);
		}
		foreach (var unit in method_units) {
			units.add (unit);
		}
		units.add (parsed.unit);
		try {
			return new SyntaxProgram (units);
		} catch (SourceSetError error) {
			reject ("astrac", "closed module request sources: " + error.message);
		}
		return program;
	}

	private static void require_declaration_body(FunctionDeclarationSyntax function) throws NativeModuleError {
		if (function.body == null || function.body.statements.length != 0) {
			source_reject (function.span, "native interface cannot contain executable implementation bodies");
		}
	}

	private string property_prototype(PropertyDeclarationSyntax property, bool interface_member = false, bool foreign_import = false) throws NativeModuleError {
		if (property.is_lazy) {
			source_reject (property.span, "property requires its complete effect/cache declaration contract");
		}
		string dispatch = interface_member ? "" : property.dispatch == MemberDispatchSyntax.VIRTUAL ? "virtual " : property.dispatch == MemberDispatchSyntax.OVERRIDE ? "override " : "";
		var text = new StringBuilder (foreign_attributes (property) + "\t" + dispatch + "property " + (property.owned_keyword != null ? "owned " : property.is_borrowed ? "borrowed " : "") + property.type_name.spelling () + " " + property.name.spelling () + (property.throws_class == null ? "" : " throws " + property.throws_class.spelling ()) + (interface_member ? " { get; " : " { get {} "));
		if (property.setter != null) {
			if (interface_member) {
				if (!foreign_import) {
					return text.str + "set; }\n";
				}
				var parameter = property.setter.parameter;
				if (parameter == null) {
					source_reject (property.setter.span, "foreign property setter requires its exact named input");
				}
				return text.str + "set(" + (parameter.owned_keyword == null ? "" : "owned ") + parameter.type_name.spelling () + " " + parameter.name.spelling () + "); }\n";
			}
			var parameter = property.setter.parameter;
			if (parameter == null || property.is_borrowed != (parameter.owned_keyword != null) || parameter.borrowed_keyword != null || parameter.caller_information != null) {
				source_reject (property.setter.span, "property setter requires its exact value/owner parameter");
			}
			text.append ("set(" + (parameter.owned_keyword == null ? "" : "owned ") + parameter.type_name.spelling () + " " + parameter.name.spelling () + ") {} ");
		}
		text.append ("}\n");
		return text.str;
	}

	// Resolve selectors through the same checked request fields that demand
	// the specialization, so aliases never become a second nominal identity.
	public void bind_type_requests(CheckedProgram program) throws NativeModuleError {
		if (producer == null) {
			return;
		}
		var selected = new HashTable<string, bool> (str_hash, str_equal);
		for (int i = 0; i < producer.type_names.length; i++) {
			string name = producer.type_names[i];
			if (name.contains ("<")) {
				string anchor = producer.name + ".__astra_unit_type_" + hash (name).substring (0, 16);
				StructSymbol? request = null;
				foreach (var structure in program.structs) {
					if (structure.name == anchor) {
						request = structure;
					}
				}
				if (request == null || request.fields.length != 1) {
					reject (producer.path, "closed type request lost its checked declaration");
				}
				name = request.fields[0].semantic_type.nominal_name ();
			}
			if (selected.contains (name)) {
				reject (producer.path, "duplicate native export selectors resolve to the same nominal type: " + name);
			}
			selected.insert (name, true);
			producer.type_names[i] = name;
		}
		var methods = new HashTable<string, bool> (str_hash, str_equal);
		foreach (var request in declaration_registry.method_requests) {
			if (!request.is_export) {
				continue;
			}
			if (request.key == null) {
				reject (producer.path, "native method request lost its resolved closed identity");
			}
			if (methods.contains (request.key)) {
				reject (producer.path, "duplicate native method selectors resolve to the same closed member: " + request.selector);
			}
			methods.insert (request.key, true);
			producer.keys.add (request.key);
		}
	}

	private string prototype(FunctionDeclarationSyntax function, bool generic_member = false, bool interface_member = false) throws NativeModuleError {
		if (function.body == null || function.is_c_import || function.is_c_export || !generic_member && function.type_parameters.length != 0 || function.ccode != null || function.utf8_factory || !generic_member && function.where_clauses.length != 0) {
			source_reject (function.span, "callable is outside the finite native interface profile");
		}
		var attributes = new StringBuilder (foreign_attributes (function));
		if (function.floating_point != null) {
			attributes.append ("[FloatingPoint(");
			for (int i = 0; i < function.floating_point.length; i++) {
				var entry = function.floating_point[i];
				if (i != 0) {
					attributes.append (",");
				}
				attributes.append_printf ("%s=\"%s\"", entry.key.spelling (), entry.decoded_value.escape ());
			}
			attributes.append (")]\n");
		}
		string dispatch = interface_member ? "" : function.dispatch == MemberDispatchSyntax.VIRTUAL ? "virtual " : function.dispatch == MemberDispatchSyntax.OVERRIDE ? "override " : "";
		var signature = new StringBuilder (attributes.str + dispatch + (function.is_signal ? "signal " : "") + (function.is_async ? "async " : "") + (function.owned_keyword == null ? "" : "owned ") + (function.return_type == null ? "" : function.return_type.spelling () + " ") + function.name.spelling ());
		if (function.type_parameters.length != 0) {
			signature.append ("<");
			for (int i = 0; i < function.type_parameters.length; i++) {
				signature.append ((i == 0 ? "" : ",") + function.type_parameters[i].spelling ());
			}
			signature.append (">");
		}
		signature.append ("(");
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			if (parameter.caller_information != null) {
				source_reject (parameter.span, "caller metadata is outside the module profile");
			}
			if (p != 0) {
				signature.append (", ");
			}
			signature.append ((parameter.owned_keyword != null ? "owned " : parameter.borrowed_keyword != null ? "borrowed " : "") + parameter.type_name.spelling () + " " + parameter.name.spelling ());
		}
		signature.append (")");
		if (function.throws_class != null) {
			signature.append (" throws " + function.throws_class.spelling ());
		}
		foreach (var clause in function.where_clauses) {
			signature.append (" " + clause.span.text ());
		}
		return signature.str + (interface_member || function.is_signal ? ";\n" : " {}\n");
	}

	private static bool scalar(SemanticType type) {
		return type is IntegerType || type is FloatingType || type.kind == TypeKind.BOOL;
	}

	private static string foreign_symbols(ForeignClassPolicy policy, NativeClassPlan owner) {
		if (policy.active_personalities == 0) {
			return "";
		}
		var adapter = new Astra.CAbi.CAbiClassAdapter (policy, owner.span, 0, owner.ordinal, -1, -1, -1, owner.foreign_targets ());
		var names = adapter.declared_symbols ();
		string result = "";
		foreach (string name in names) {
			bool forwarded = false;
			var api = policy.declared_api;
			for (uint m = 0; m < api.member_count; m++) {
				var member = api.member (m);
				forwarded |= Astra.CAbi.CAbiClassAdapter.record_forwarder (member) && name == api.prefix + "_" + member.name;
			}
			if (!forwarded) {
				result += (result == "" ? "" : ",") + name;
			}
		}
		return result;
	}

	private static bool declared_nominal(NativeModuleRecord record, string name, HashTable<NativeModuleRecord, bool>? visited = null) {
		var seen = visited ?? new HashTable<NativeModuleRecord, bool> (direct_hash, direct_equal);
		if (seen.contains (record)) {
			return false;
		}
		seen.insert (record, true);
		foreach (string declared in record.type_names) {
			if (declared == name) {
				return true;
			}
		}
		foreach (var dependency in record.dependencies) {
			if (declared_nominal (dependency, name, seen)) {
				return true;
			}
		}
		return false;
	}

	private static void require_nominal(NativeModuleRecord record, SemanticType type, SourceSpan span) throws NativeModuleError {
		if (type is ContextBytesType) {
			if (record.legacy || record.windows) {
				reject (record.path, "context byte ownership requires the qualified Linux runtime schema /6");
			}
			require_nominal (record, ((ContextBytesType) type).allocator_type, span);
			return;
		}
		if (record.legacy && type is HandleType && ((HandleType) type).context_mode != "") {
			reject (record.path, "legacy allocator context ABI changed; rebuild native unit for runtime schema /6");
		}
		if (record.windows && type is HandleType && ((HandleType) type).context_mode != "") {
			reject (record.path, "allocator context native transport requires the qualified Linux runtime schema /6");
		}
		var closure = type as ClosureHandleType;
		if (closure != null) {
			require_nominal (record, closure.environment_type, span);
			if (closure.throws_type != null) {
				require_nominal (record, closure.throws_type, span);
			}
			require_nominal (record, closure.result_type, span);
			foreach (var parameter in closure.parameter_types) {
				require_nominal (record, parameter, span);
			}
			return;
		}
		var callable = type as FunctionValueType;
		if (callable != null) {
			require_nominal (record, callable.result_type, span);
			foreach (var parameter in callable.parameter_types) {
				require_nominal (record, parameter, span);
			}
			return;
		}
		if (!(type is ClassType) && !(type is StructType)) {
			return;
		}
		if (declared_nominal (record, type.nominal_name ())) {
			return;
		}
		source_reject (span, "public nominal type requires its exact exported module declaration");
	}

	private static void check_profile(SsaFunction function, NativeSignature signature, bool foreign_member = false) throws NativeModuleError {
		var buffer = signature.buffer_result;
		var element = buffer == null ? null : buffer.element_type as NativeScalarAbiType;
		bool owned_context_bytes = buffer != null && function.return_type is ContextBytesType && buffer.context_origin != null && buffer.context_origin.valid () && function.return_type.display_name () == buffer.context_origin.name;
		bool owned_bytes = foreign_member && buffer != null && buffer.context_origin == null && function.return_type is SliceType && function.result_contract == ResultOwnershipContract.OWNED_TRANSFER && element != null && element.scalar_type == NativeScalarType.U8 && buffer.record_element == null && buffer.transfers_ownership && buffer.base_type == NativeScalarType.PTR && buffer.length_type == NativeScalarType.I32;
		if (function.utf8_factory || signature.object_result != null || buffer != null && !owned_bytes && !owned_context_bytes || signature.sum_result != null) {
			source_reject (function.span, "unsupported result/error/async ABI channel");
		}
		if ((function.throws_type == null) != (signature.exception_plan == null) ||
		    function.throws_type != null && signature.exception_plan.bound_name != function.throws_type.nominal_name ()) {
			source_reject (function.span, "checked native callable requires its exact bound and root exception plan");
		}
		if (owned_bytes || owned_context_bytes) { /* The exact unique pair is serialized below with its full physical shape. */
		} else if (function.return_type is ClassType) {
			bool receiver_borrow = function is SsaPropertyGetter && function.result_contract == ResultOwnershipContract.RECEIVER_BORROW && !function.heap_result && signature.heap_result == null && function.owned_cleanup == null;
			if (!receiver_borrow && (!function.heap_result || signature.heap_result == null || !signature.heap_result.heap)) {
				source_reject (function.span, "Class result requires exact independent heap origin or its bounded property receiver");
			}
		} else if (function.return_type.get_type () == typeof (HandleType)) {
			var resource = signature.resource_result;
			if (function.result_contract != ResultOwnershipContract.OWNED_TRANSFER || resource == null || resource.type_name != function.return_type.display_name () || resource.cleanup_symbol == "") {
				source_reject (function.span, "Resource result requires its exact owned native destructor contract");
			}
		} else if (function.return_type is FunctionValueType) {
			if (function.result_contract != ResultOwnershipContract.UNMANAGED || signature.result == null || !(signature.result.abi_type is NativeFunctionPointerType)) {
				source_reject (function.span, "native function value result requires its exact copied code signature");
			}
		} else if (function.return_type is StringType) {
			var text = signature.result == null ? null : signature.result.abi_type as NativeTextType;
			if (text == null || (function.result_contract != ResultOwnershipContract.STATIC_TEXT && function.result_contract != ResultOwnershipContract.RECEIVER_TEXT)) {
				source_reject (function.span, "native text result requires its exact static or receiver-bounded descriptor");
			}
		} else if (!scalar (function.return_type) && function.return_type.kind != TypeKind.VOID && !(function.return_type is StructType)) {
			source_reject (function.span, "unsupported public result type");
		}
		for (int p = 0; p < function.parameters.length; p++) {
			var parameter = function.parameters[p];
			bool record_leaf = false;
			foreach (var group in function.struct_parameters) {
				if (p >= group.first_leaf && p < group.first_leaf + group.shape.leaves.length) {
					record_leaf = true;
				}
			}
			if (record_leaf) {
				continue;
			}
			bool buffer_leaf = false;
			foreach (var group in signature.buffer_parameters) {
				buffer_leaf |= p >= group.first_leaf && p < group.first_leaf + 2;
			}
			if (buffer_leaf) {
				continue;
			}
			if (parameter.semantic_type is SliceType) {
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || !(signature.parameters[p].abi_type is NativeSliceType)) {
					source_reject (parameter.span, "native slice parameter requires its exact bounded borrow descriptor");
				}
			} else if (parameter.semantic_type is TypedPointerType) {
				var pointee = ForeignApiTypes.scalar_pointee (parameter.semantic_type);
				var physical = signature.parameters[p];
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || pointee == null || physical.abi_type.get_type () != typeof (NativeScalarAbiType) || physical.scalar_type != NativeScalarType.PTR || physical.scalar_pointee == null || physical.scalar_pointee.scalar_type != NativeForeignApi.scalar (pointee.kind)) {
					source_reject (parameter.span, "native scalar reference requires its exact borrowed scalar pointee contract");
				}
			} else if (parameter.semantic_type is ClassType) {
				var origin = signature.parameters[p].object_origin;
				bool owned_heap = parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER && parameter.heap_object && origin != null && origin.heap && origin.class_name == parameter.semantic_type.display_name ();
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE && !owned_heap) {
					source_reject (parameter.span, "Class parameters require bounded borrow or an exact native heap owner origin");
				}
			} else if (parameter.semantic_type.get_type () == typeof (HandleType)) {
				var resource = signature.parameters[p].resource;
				if ((parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE && parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER) || resource == null || resource.type_name != parameter.semantic_type.display_name () || resource.cleanup_symbol == "" || signature.parameters[p].owns_resource != (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER)) {
					source_reject (parameter.span, "Resource parameter requires its exact native borrow or transfer and destructor contract");
				}
			} else if (parameter.semantic_type is ClosureHandleType) {
				var declared = (ClosureHandleType) parameter.semantic_type;
				var closure = signature.parameters[p].abi_type as NativeClosureHandleType;
				if (closure == null || declared.actor || declared.threaded || closure.actor || closure.threaded ||
				    closure.environment != declared.environment_type.nominal_name () ||
				    closure.checked_error != (declared.throws_type == null ? null : declared.throws_type.nominal_name ()) ||
				    (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE && parameter.pointer_contract != PointerParameterContract.OWNED_TRANSFER)) {
					source_reject (parameter.span, "native closure parameter requires its exact environment, checked signature and borrow/transfer channel");
				}
			} else if (parameter.semantic_type is CallbackType) {
				if (parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE || !(signature.parameters[p].abi_type is NativeCallbackType)) {
					source_reject (parameter.span, "native Callback requires its exact borrowed code/context signature");
				}
			} else if (parameter.semantic_type is FunctionValueType) {
				if (parameter.pointer_contract != PointerParameterContract.UNMANAGED || !(signature.parameters[p].abi_type is NativeFunctionPointerType)) {
					source_reject (parameter.span, "native function value parameter requires its exact copied code signature");
				}
			} else if (parameter.semantic_type is StringType) {
				var text = signature.parameters[p].abi_type as NativeTextType;
				if (text == null || text.contract != NativeTextContract.BORROWED_NOESCAPE) {
					source_reject (parameter.span, "native text parameter requires its exact borrowed descriptor");
				}
			} else if (!scalar (parameter.semantic_type)) {
				source_reject (parameter.span, "unsupported public parameter channel");
			}
		}
	}

	// Only this digest is published. The private frame plan and all resume
	// states remain producer-side; the object receipt binds their actual code.
	private static string task_frame_fingerprint(NativeAbiProgram program, int ordinal) throws NativeAbiError {
		var text = new StringBuilder (NativeAbiDump.format (program));
		bool found = false;
		foreach (var frame in program.async_frames) {
			if (frame.function_ordinal != ordinal) {
				continue;
			}
			found = true;
			text.append_printf ("task=%d;objects=%u;provider=%d;", ordinal, frame.object_count, (int) frame.provider);
			for (uint s = 0; s < frame.storage_count; s++) {
				var slot = frame.storage_slot (s);
				text.append_printf ("storage=%d:%d:%s;", slot.ordinal, slot.array_count,
					slot.record == null ? slot.leaf.spelling () : slot.record.spelling ());
			}
			for (uint o = 0; o < frame.owner_count; o++) {
				var owner = frame.owner (o);
				text.append_printf ("owner=%d:%d:%d:%s:%d:%d;", owner.ordinal, owner.source_ordinal,
					owner.class_ordinal, owner.cleanup_symbol, owner.capture_first_leaf, owner.cleanup_position);
				if (owner.closure != null) {
					text.append ("closure-owner=" + owner.closure.spelling () + ";");
				}
			}
			for (uint b = 0; b < frame.buffer_count; b++) {
				var buffer = frame.buffer (b);
				text.append_printf ("buffer=%d:%d:%s:%d:%d;", buffer.ordinal, buffer.owner_ordinal,
					buffer.record_element == null ? buffer.element.spelling () : buffer.record_element.spelling (),
					buffer.capture_first_leaf, buffer.cleanup_position);
				if (buffer.context_origin != null) {
					text.append ("context-buffer-origin=" + buffer.context_origin.spelling () + ";");
				}
			}
			for (uint e = 0; e < frame.enum_count; e++) {
				var item = frame.enum_slot (e);
				text.append_printf ("enum=%d:%d:%d:%d:%d:%d;", item.ordinal, item.source_ordinal,
					item.capture_first_leaf, item.owning ? 1 : 0, item.inspection_root, item.reservation_source);
			}
			for (uint c = 0; c < frame.cleanup_count; c++) {
				text.append_printf ("cleanup=%d:%d;", frame.cleanup_domain (c), frame.cleanup_ordinal (c));
			}
		}
		assert (found);
		return hash (text.str);
	}

	public LlvmNativeModulePlan bind(SsaProgram source, NativeAbiProgram native) throws NativeModuleError, LlvmError, NativeAbiError {
		// A plain native Fn does not carry an invocation-dependent callback
		// precondition. Keep these callables on their checked direct boundary
		// until code-value effect transport has its own declaration contract.
		if (producer != null || records.length != 0) {
			foreach (var target in new SsaCodeOrigins (source).addressed_functions ()) {
				if (native.functions[target.ordinal].callback_inputs != "") {
					source_reject (target.span, "native Fn transport requires a callable without callback preconditions");
				}
			}
		}
		// Publish declaration obligations, never the producer's observed Fn
		// targets. A protected inspector and its enclosing required inputs
		// must both have independently checked native effect plans.
		if (producer != null) {
			foreach (var function in source.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var loan = instruction as SsaSlotsValueInstruction;
						if (loan == null || loan.action != OwnerSlotsAction.BORROW || loan.borrower == null) {
							continue;
						}
						foreach (var consumer in source.functions) {
							if ((consumer.kind != CallableKind.METHOD && !loan.readonly_required) || !consumer.parameters.find (loan.borrower)) {
								continue;
							}
							if (!native.functions[consumer.ordinal].scoped_readonly || !native.functions[function.ordinal].callback_contract_supported) {
								source_reject (function.span, "readonly scoped inspector native export requires a declarative callback effect contract");
							}
						}
					}
				}
			}
		}
		var result = new LlvmNativeModulePlan ();
		string[] required = {};
		foreach (var record in records) {
			foreach (string name in record.type_names) {
				required += name;
			}
		}
		var scratch = new LlvmModuleArtifact ();
		var registry = new LlvmStructRegistry (scratch, new LlvmTypeMapper (scratch.context), source, native, required);
		try {
			foreach (var record in records) {
				foreach (string group in record.data.get_groups ()) {
					if (!group.has_prefix ("foreign-import ")) {
						continue;
					}
					string name = group.substring (15);
					ForeignImportContract? selected = null;
					foreach (var handle in source.handles) {
						if (handle.name != name || handle.c_import == null) {
							continue;
						}
						bool origin = !record.imported && !handle.name_span.file.native_interface;
						foreach (var declaration in record.foreign_declarations) {
							origin |= handle.name_span.file == declaration;
						}
						if (origin) {
							selected = handle.c_import;
						}
					}
					if (selected == null) {
						reject (record.path, "foreign import lost its checked declaration origin: " + name);
					}
					string identity = selected.declaration_identity ();
					if (record.imported && record.data.get_string (group, "contract") != identity) {
						reject (record.path, "foreign import declaration/selection/factory identity mismatch: " + name);
					}
					if (!record.imported) {
						record.data.set_string (group, "contract", identity);
					}
				}
				if (!record.imported) {
					foreach (var owner in source.classes) {
						var policy = owner.allocation_policy;
						if (policy == null) {
							continue;
						}
						if (policy.kind == AllocationKind.CUSTOM) {
							source_reject (owner.span, "custom allocator code must remain in one checked compilation unit");
						}
						record.data.set_string ("allocator " + policy.domain_identity, "kind", policy.kind.spelling ());
					}
				}
				if (!record.imported) {
					foreach (var function in source.functions) {
						if (function.implicit_receiver == null) {
							continue;
						}
						var generic_method = function as SsaMethod;
						if (generic_method != null && generic_method.generic_method_instance != null) {
							continue;
						}
						string owner = function.implicit_receiver.contract.instance_type.display_name ();
						foreach (string selected in record.type_names) {
							if (selected == owner) {
								string key = LlvmNativeModulePlan.function_key (function);
								bool present = false;
								foreach (string prior in record.keys) {
									present |= prior == key;
								}
								if (!present) {
									record.keys.add (key);
								}
							}
						}
					}
					if (record.keys.length > MAX_CALLABLES) {
						reject (record.path, "native export inventory exceeds %d callables".printf (MAX_CALLABLES));
					}
				}
				var found = new HashTable<string, SsaFunction> (str_hash, str_equal);
				foreach (var function in source.functions) {
					string key = LlvmNativeModulePlan.function_key (function);
					bool selected = false;
					foreach (string expected in record.keys) {
						selected |= key == expected;
					}
					if (record.imported && function.name_span.file == record.declarations && !selected) {
						reject (record.path, "unexpected imported native callable");
					}
					if (!selected) {
						continue;
					}
					var lifecycle = function as SsaLifecycle;
					var declaration_file = lifecycle == null ? function.name_span.file : lifecycle.declaring_class.name_span.file;
					if (record.imported && declaration_file != record.declarations) {
						reject (record.path, "imported callable lost declaration identity");
					}
					bool foreign_member = false;
					if (function.implicit_receiver != null) {
						foreach (var owner in source.classes) {
							foreign_member |= owner.semantic_type == function.implicit_receiver.contract.instance_type && owner.foreign_export != null && owner.foreign_export.declared_api != null;
						}
					}
					check_profile (function, native.functions[function.ordinal].signature, foreign_member);
					bool readonly_effect = native.functions[function.ordinal].scoped_readonly;
					var effects = native.functions[function.ordinal];
					if (!record.windows && !record.legacy) {
						var spec = new NativeOptimizerSpec (function, source, effects.signature, registry, target.enum_target_data (scratch));
						record.optimizer_specs.insert (key, spec);
						record.optimizer_functions.insert (key, function);
						if (!record.imported) {
							record.data.set_string ("function " + key, "optimizer", record.optimizer_overrides.lookup (key) ?? spec.propose (function.effect_facts).encode ());
						}
					}
					if (!record.windows && !record.legacy) {
						try {
							if (record.imported && SsaRuntimeLifetimes.import_summary (function, RuntimeLifetimeSummary.decode (record.data.get_string ("function " + key, "lifetimes"))).encode () != effects.runtime_lifetimes) {
								reject (record.path, "native lifetime contract differs from its original immutable declaration");
							}
							if (!record.imported) {
								record.data.set_string ("function " + key, "lifetimes", SsaRuntimeLifetimes.export_summary (function, effects.runtime_lifetimes));
							}
						} catch (RuntimeLifetimeError failure) {
							reject (record.path, "native lifetime coordinate correspondence: " + failure.message);
						}
					}
					if (!effects.callback_contract_supported) {
						source_reject (function.span, "native export requires a declarative callback effect contract");
					}
					if (record.imported && (record.data.get_boolean ("function " + key, "readonly") != readonly_effect ||
					                        record.data.get_string ("function " + key, "readonly_inputs") != effects.readonly_inputs ||
					                        record.data.get_string ("function " + key, "callback_inputs") != effects.callback_inputs)) {
						reject (record.path, "native readonly effect differs from its original declaration");
					}
					if (!record.imported) {
						record.data.set_boolean ("function " + key, "readonly", readonly_effect);
						record.data.set_string ("function " + key, "readonly_inputs", effects.readonly_inputs);
						record.data.set_string ("function " + key, "callback_inputs", effects.callback_inputs);
					}
					var async_plan = native.functions[function.ordinal].async_callable;
					string task_group = "task " + key;
					if (record.imported && (async_plan != null) != record.data.has_group (task_group)) {
						reject (record.path, "native task declaration/metadata inventory mismatch");
					}
					if (async_plan != null) {
						require_nominal (record, function.async_body.runtime.error_type, function.name_span);
						if (record.imported && record.data.get_string (task_group, "contract") != async_plan.contract ()) {
							reject (record.path, "native task runtime/result/capture contract mismatch");
						}
						if (!record.imported) {
							record.data.set_string (task_group, "contract", async_plan.contract ());
							record.data.set_string (task_group, "frame", task_frame_fingerprint (native, function.ordinal));
						}
					}

					var closed_method = function as SsaMethod;
					if (closed_method != null && closed_method.generic_method_instance != null) {
						foreach (var argument in closed_method.generic_method_instance.arguments.copy_values ()) {
							require_nominal (record, argument, function.name_span);
						}
					}
					require_nominal (record, function.return_type, function.name_span);
					if (function.throws_type != null) {
						require_nominal (record, function.throws_type, function.name_span);
					}
					if (function.implicit_receiver != null) {
						require_nominal (record, function.implicit_receiver.contract.instance_type, function.name_span);
					}
					foreach (var parameter in function.parameters) {
						require_nominal (record, parameter.semantic_type, parameter.name_span);
					}
					foreach (var group in function.struct_parameters) {
						require_nominal (record, group.shape.semantic_type, function.name_span);
					}
					var observation = native.functions[function.ordinal].record_observation;
					string receiver_field = observation == null ? "" : native.classes[observation.class_ordinal].fields[observation.field_ordinal].name;
					if (record.imported && record.data.get_string ("function " + key, "receiver_field") != receiver_field) {
						reject (record.path, "exact receiver record field contract mismatch: " + key);
					}
					if (!record.imported) {
						record.data.set_string ("function " + key, "receiver_field", receiver_field);
					}
					string shape = LlvmNativeModulePlan.signature_shape (function, native.functions[function.ordinal].signature, native);
					if (record.imported && record.data.get_string ("function " + key, "signature") != shape) {
						reject (record.path, "exact type/ownership/native ABI signature mismatch: " + key);
					}
					if (!record.imported) {
						record.data.set_string ("function " + key, "signature", shape);
					}
					found.insert (key, function);
				}
				if (found.size () != record.keys.length) {
					reject (record.path, "native callable inventory mismatch");
				}
				var descriptor_types = new HashTable<string, SsaClass> (str_hash, str_equal);
				foreach (string name in record.type_names) {
					SsaNativeInstance? declaration = null;
					foreach (var structure in source.structs) {
						if (structure.semantic_type.nominal_name () == name) {
							declaration = structure;
						}
					}
					foreach (var owner in source.classes) {
						if (owner.name != name) {
							continue;
						}
						if (owner.parent_class != null) {
							require_nominal (record, owner.parent_class.semantic_type, owner.span);
						}
						var key = owner.generic_instance;
						if (key != null) {
							if (!key.definition.general_bodies) {
								source_reject (owner.span, "generic unit requires complete declared members");
							}
							foreach (var argument in key.arguments.copy_values ()) {
								require_nominal (record, argument, owner.span);
							}
						}
						declaration = owner;
					}
					if (declaration == null) {
						reject (record.path, "native type declaration missing");
					}
					var object_class = declaration as SsaClass;
					if (record.legacy && object_class != null && object_class.allocation_policy != null && object_class.allocation_policy.kind == AllocationKind.CONTEXT) {
						reject (record.path, "legacy context-backed Class ABI changed; rebuild native unit for runtime schema /6");
					}
					if (record.windows && object_class != null && object_class.allocation_policy != null && object_class.allocation_policy.kind == AllocationKind.CONTEXT) {
						reject (record.path, "context-backed Class native transport requires the qualified Linux runtime schema /6");
					}
					if (object_class != null && object_class.foreign_export != null) {
						var policy = object_class.foreign_export;
						string group = "foreign " + name;
						string symbols = foreign_symbols (policy, native.classes[declaration.ordinal]);
						if (record.imported) {
							if (!foreign_schema_matches (record, record.data.get_string ("abi", "schema")) || !record.data.has_group (group) || record.data.get_string (group, "contract") != policy.identity () || record.data.get_string (group, "symbols") != symbols) {
								reject (record.path, "foreign declaration/selection/member/bridge identity mismatch: " + name);
							}
						} else {
							record.data.set_string ("abi", "schema", foreign_schema (record));
							record.data.set_string (group, "contract", policy.identity ());
							record.data.set_string (group, "symbols", symbols);
						}
					} else if (record.imported && record.data.has_group ("foreign " + name)) {
						reject (record.path, "foreign metadata requires its exact declared native Class");
					}
					if (object_class != null && object_class.polymorphic) {
						descriptor_types.insert (name, object_class);
					}
					if (record.imported && declaration.name_span.file != record.declarations) {
						reject (record.path, "native type lost imported nominal declaration authority");
					}
					var type = registry.lookup (declaration);
					var layout = new StringBuilder ();
					layout.append ((declaration is SsaClass) ? "kind=class;" : "kind=record;");
					if (declaration is SsaClass) {
						var concurrency = ((SsaClass) declaration).concurrency_policy;
						if (concurrency != null) {
							layout.append_printf ("concurrency=%u;", concurrency.identity);
						}
						var policy = ((SsaClass) declaration).allocation_policy;
						layout.append ("allocation=" + (policy == null ? "" : policy.identity) + ";");
						if (record.imported && policy != null && record.data.get_string ("allocator " + policy.domain_identity, "kind") != policy.kind.spelling ()) {
							reject (record.path, "allocation domain differs from the admitted type policy");
						}
					} else {
						var policy = ((SsaStruct) declaration).representation;
						layout.append ("representation=" + (policy == null ? "" : policy.identity) + ";");
					}
					if (declaration is SsaClass) {
						var owner = (SsaClass) declaration;
						layout.append (LlvmNativeModulePlan.class_shape (native.classes[declaration.ordinal], native));
						for (int slot = 0; slot < owner.virtual_entries.length; slot++) {
							layout.append_printf ("slot=%d:%s;", slot, LlvmNativeModulePlan.function_key (owner.virtual_entries[slot]));
						}
					}
					uint64 size = CApi.abi_size_of_type (target.enum_target_data (scratch), type);
					layout.append_printf ("size=%" + uint64.FORMAT + ";align=%u;", size, CApi.abi_alignment_of_type (target.enum_target_data (scratch), type));
					foreach (var field in declaration.fields) {
						var slice = field.semantic_type as SliceType;
						var slots = field.semantic_type as OwnerSlotsType;
						bool owned_slots = declaration is SsaClass && slots != null;
						bool composite = field.semantic_type is StructType || field.semantic_type is ClassType && field.owned_cleanup != null && field.owned_cleanup.is_heap_object || slice != null && field.owned_cleanup != null && field.owned_cleanup.is_buffer && scalar (slice.element_type);
						bool copied_storage = CopyabilityAuthority.of (field.semantic_type, (type) => { return null;
						}) == Copyability.COPYABLE;
						bool resource_storage = field.semantic_type.get_type () == typeof (HandleType) && field.owned_cleanup != null && !field.owned_cleanup.is_object && !field.owned_cleanup.is_buffer && field.owned_cleanup.external_symbol != "";
						bool text_storage = field.semantic_type is StringType && field.text_snapshot;
						if (!copied_storage && !composite && !owned_slots && !resource_storage && !text_storage) {
							source_reject (field.span, "native module fields require copied storage or exact nested record/Class/buffer/slot/text ownership");
						}
						require_nominal (record, field.semantic_type, field.span);
						if (owned_slots) {
							require_nominal (record, slots.element, field.span);
						}
						uint64 offset = CApi.offset_of_element (target.enum_target_data (scratch), type, registry.field_index (field));
						layout.append_printf ("%s:%s:%d@%" + uint64.FORMAT + ";", field.name, field.semantic_type.nominal_name (), field.is_private ? 1 : 0, offset);
						layout.append_printf ("owned=%d;nonnull=%d;", owned_slots || field.owned_cleanup != null ? 1 : 0, field.requires_nonnull ? 1 : 0);
						layout.append_printf ("text-snapshot=%d;", text_storage ? 1 : 0);
						if (resource_storage) {
							layout.append ("resource-cleanup=" + field.owned_cleanup.external_symbol + ";");
						}
						if (resource_storage && ((HandleType) field.semantic_type).context_mode != "") {
							layout.append ("context-field=" + NativeTypeMapper.map_type (field.semantic_type).spelling () + ";");
						}
						if (field.semantic_type is ContextBytesType) {
							layout.append ("context-buffer-field=" + NativeTypeMapper.map_type (field.semantic_type).spelling () + ";");
						}
						if (copied_storage) {
							layout.append ("abi=" + LlvmNativeModulePlan.callable_shape (NativeTypeMapper.map_type (field.semantic_type), native) + ";");
						}
					}
					if (record.imported && record.data.get_string ("type " + name, "layout") != layout.str) {
						reject (record.path, "native type layout/visibility mismatch: " + name);
					}
					if (!record.imported) {
						record.data.set_string ("type " + name, "layout", layout.str);
					}
					if (!record.imported) {
						record.data.set_string ("type " + name, "symbol", "");
					} else if (!descriptor_types.contains (name) && record.data.get_string ("type " + name, "symbol") != "") {
						reject (record.path, "nonpolymorphic storage cannot publish a type descriptor");
					}
				}
				string identity = digest (record.data, false);
				if (record.imported && record.data.get_string ("abi", "identity") != identity) {
					reject (record.path, "native interface identity drift");
				}
				record.data.set_string ("abi", "identity", identity);
				foreach (string name in sorted_names (descriptor_types.get_keys ())) {
					string descriptor_symbol = symbol (identity, "D:" + name);
					if (record.imported && record.data.get_string ("type " + name, "symbol") != descriptor_symbol) {
						reject (record.path, "native descriptor symbol differs from its exact class origin");
					}
					if (!record.imported) {
						record.data.set_string ("type " + name, "symbol", descriptor_symbol);
					}
					result.bind_descriptor (descriptor_types.lookup (name), native, descriptor_symbol, record.imported);
				}
				foreach (string key in sorted_names (found.get_keys ())) {
					var function = found.lookup (key);
					string name = symbol (identity, key);
					if (!record.imported) {
						record.data.set_string ("function " + key, "symbol", name);
					}
					result.bind (function, native.functions[function.ordinal].signature, native, name, record.imported);
				}
			}
		} catch (KeyFileError error) {
			reject ("astrac", "malformed native module: " + error.message);
		} catch (OptimizerSummaryError error) {
			reject ("astrac", "invalid derived optimizer summary: " + error.message);
		}
		return result;
	}

	// Typed signature/layout binding above precedes every object claim check.
	// Grant facts to declarations only after validation, then the caller must
	// rebuild SSA optimizer annotations and independently sealed native plans.
	private static bool optimizer_dependency(NativeModuleRecord root, NativeModuleRecord target) {
		var pending = new GenericArray<NativeModuleRecord> ();
		var seen = new HashTable<NativeModuleRecord, bool> (direct_hash, direct_equal);
		pending.add (root);
		for (int p = 0; p < pending.length; p++) {
			var current = pending[p];
			if (seen.contains (current)) {
				continue;
			}
			seen.insert (current, true);
			foreach (var dependency in current.dependencies) {
				if (dependency == target) {
					return true;
				}
				pending.add (dependency);
			}
		}
		return false;
	}

	private bool accepts_optimizer(NativeModuleRecord record, string key, OptimizerSummary summary, uint8[] bytes) throws KeyFileError, OptimizerSummaryError {
		var spec = record.optimizer_specs.lookup (key);
		if (spec == null) {
			return false;
		}
		// Typed binding is already complete. An unknown summary consumes no
		// fact, so it needs neither a callee table nor an instruction proof.
		if (!summary.memory_none && summary.count == 0) {
			return true;
		}
		string[] symbols = {};
		string[] contracts = {};
		foreach (var candidate in records) {
			if (candidate.windows || candidate.legacy || candidate != record && !optimizer_dependency (record, candidate)) {
				continue;
			}
			foreach (string callee in candidate.keys) {
				var target = candidate.optimizer_specs.lookup (callee);
				if (target == null) {
					continue;
				}
				var facts = OptimizerSummary.decode (candidate.data.get_string ("function " + callee, "optimizer"));
				if (candidate != record) {
					var function = candidate.optimizer_functions.lookup (callee);
					var evidence = function == null ? null : function.checked_native_optimizer;
					if (evidence == null || evidence.object_hash != candidate.data.get_string ("object", "sha256") || !evidence.permits (target.facts (facts))) {
						continue;
					}
				}
				string? contract = target.call_contract (facts, candidate == record, spec);
				if (contract != null) {
					symbols += candidate.data.get_string ("function " + callee, "symbol");
					contracts += contract;
				}
			}
		}
		return spec.accepts (summary, bytes, record.data.get_string ("function " + key, "symbol"), symbols, contracts);
	}

	public bool validate_optimizer_imports() throws NativeModuleError {
		bool changed = false;
		try {
			foreach (var record in records) {
				if (!record.imported || record.windows || record.legacy) {
					continue;
				}
				uint8[] bytes = read_artifact (record.object_path, 128 * 1024 * 1024);
				if (Checksum.compute_for_data (ChecksumType.SHA256, bytes) != record.data.get_string ("object", "sha256")) {
					reject (record.path, "native optimizer object changed during typed binding");
				}
				foreach (string key in record.keys) {
					var summary = OptimizerSummary.decode (record.data.get_string ("function " + key, "optimizer"));
					var spec = record.optimizer_specs.lookup (key);
					var function = record.optimizer_functions.lookup (key);
					if (spec == null || function == null || !accepts_optimizer (record, key, summary, bytes)) {
						reject (record.path, "optimizer claim is not proved by the exact supplied native object: " + key);
					}
					if (!summary.memory_none && summary.count == 0) {
						continue;
					}
					var facts = spec.facts (summary);
					if (function.checked_native_optimizer != null) {
						if (!function.checked_native_optimizer.permits (facts)) {
							reject (record.path, "checked optimizer evidence changed");
						}
						continue;
					}
					function.bind_native_optimizer (new NativeOptimizerEvidence (function.native_declaration.identity.symbol, function.native_declaration.identity.signature_shape, record.data.get_string ("object", "sha256"), facts));
					changed = true;
				}
			}
		} catch (KeyFileError error) {
			reject ("astrac", error.message);
		} catch (OptimizerSummaryError error) {
			reject ("astrac", error.message);
		} catch (SsaError error) {
			reject ("astrac", error.message);
		}
		return changed;
	}

	public bool has_optimizer_export_claims() throws NativeModuleError {
		if (!optimizer_exports) {
			return false;
		}
		try {
			foreach (string key in producer.keys) {
				var summary = OptimizerSummary.decode (producer.data.get_string ("function " + key, "optimizer"));
				if (summary.memory_none || summary.count != 0) {
					return true;
				}
			}
		} catch (KeyFileError error) {
			reject (producer.path, error.message);
		} catch (OptimizerSummaryError error) {
			reject (producer.path, error.message);
		}
		return false;
	}

	public bool refine_optimizer_exports(uint8[] object_bytes) throws NativeModuleError {
		if (!optimizer_exports) {
			return false;
		}
		bool changed = false;
		try {
			foreach (string key in producer.keys) {
				var summary = OptimizerSummary.decode (producer.data.get_string ("function " + key, "optimizer"));
				if (!accepts_optimizer (producer, key, summary, object_bytes)) {
					producer.optimizer_overrides.insert (key, new OptimizerSummary ().encode ());
					changed = true;
				}
			}
		} catch (KeyFileError error) {
			reject (producer.path, error.message);
		} catch (OptimizerSummaryError error) {
			reject (producer.path, error.message);
		}
		return changed;
	}

	public void publish(string object_path) throws NativeModuleError {
		if (producer == null) {
			return;
		}
		try {
			string object_absolute = Filename.canonicalize (object_path);
			string interface_absolute = Filename.canonicalize (producer.path);
			if (Path.get_dirname (object_absolute) != Path.get_dirname (interface_absolute) || object_absolute == interface_absolute) {
				reject (producer.path, "interface and distinct object must reside in the same directory");
			}
			foreach (var record in records) {
				if (record.imported) {
					verify_adjacent_artifacts (record, Path.get_dirname (interface_absolute));
				}
			}
			producer.object_path = object_absolute;
			producer.data.set_string ("object", "file", Path.get_basename (object_absolute));
			producer.data.set_string ("object", "sha256", bytes_hash (object_absolute, true, producer.windows));
			if (optimizer_exports) {
				uint8[] bytes = read_artifact (object_absolute, 128 * 1024 * 1024);
				foreach (string key in producer.keys) {
					var summary = OptimizerSummary.decode (producer.data.get_string ("function " + key, "optimizer"));
					if (!accepts_optimizer (producer, key, summary, bytes)) {
						reject (producer.path, "final native object differs from independently checked optimizer proof: " + key);
					}
				}
			}
			producer.data.set_string ("receipt", "fingerprint", digest (producer.data, true));
			check_symbols (producer);
			FileUtils.set_contents (producer.path, producer.data.to_data ());
		} catch (KeyFileError error) {
			reject (producer.path, error.message);
		} catch (OptimizerSummaryError error) {
			reject (producer.path, error.message);
		} catch (FileError error) {
			reject (producer.path, error.message);
		}
	}

	private static void verify_adjacent_artifacts(NativeModuleRecord record, string directory) throws NativeModuleError {
		try {
			string interface_path = Path.build_filename (directory, Path.get_basename (record.path));
			string object_path = Path.build_filename (directory, record.data.get_string ("object", "file"));
			if (FileUtils.test (interface_path, FileTest.IS_SYMLINK) || bytes_hash (interface_path) != record.interface_hash) {
				reject (interface_path, "dependency interface must be staged unchanged beside the producer interface");
			}
			if (FileUtils.test (object_path, FileTest.IS_SYMLINK) || bytes_hash (object_path, true, record.windows) != record.data.get_string ("object", "sha256")) {
				reject (object_path, "dependency object must be staged unchanged beside the producer interface");
			}
		} catch (KeyFileError error) {
			reject (record.path, "malformed staged dependency: " + error.message);
		}
	}

	public void revalidate_dependencies() throws NativeModuleError {
		try {
			foreach (var record in records) {
				if (!record.imported) {
					continue;
				}
				if (FileUtils.test (record.path, FileTest.IS_SYMLINK) || bytes_hash (record.path) != record.interface_hash) {
					reject (record.path, "interface changed during compilation");
				}
				if (FileUtils.test (record.object_path, FileTest.IS_SYMLINK) || bytes_hash (record.object_path, true, record.windows) != record.data.get_string ("object", "sha256")) {
					reject (record.path, "implementation changed during compilation");
				}
				check_symbols (record);
			}
		} catch (KeyFileError error) {
			reject ("astrac", error.message);
		}
	}

}
}
