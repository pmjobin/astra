// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Driver {
public errordomain NativeDescriptorError {
	INVALID, OUTPUT
}

// A selected declaration snapshot, never an object-layout or owner cast.
private class DescriptorMember : Object {
	internal string name;
	internal string kind;
	internal string type_name;
	internal int position;
	internal string? read_int;
	internal string? call_int;
	internal DescriptorMember (Symbol symbol, string kind, string type_name) {
		name = symbol.name;
		this.kind = kind;
		this.type_name = type_name;
		position = symbol.name_span.start;
	}
}
private class DescriptorType : Object {
	internal string name;
	internal string alias;
	internal string kind;
	internal int id;
	internal bool readable;
	internal bool reference;
	internal GenericArray<DescriptorMember> members = new GenericArray<DescriptorMember> ();
}

private class DescriptorFields : Object {
	private CheckedProgram program;
	internal DescriptorFields (CheckedProgram program) {
		this.program = program;
	}
	internal GenericArray<SemanticType>? lookup(SemanticType type) {
		foreach (var record in program.structs) {
			if (record.semantic_type != type) {
				continue;
			}
			var fields = new GenericArray<SemanticType> ();
			foreach (var field in record.fields) {
				fields.add (field.semantic_type);
			}
			return fields;
		}
		foreach (var enumeration in program.enums) {
			if (enumeration.semantic_type == type) {
				return enumeration.value_fields ();
			}
		}
		return null;
	}
}
public class NativeDescriptors : Object {
	public const int VERSION = 1;
	private static string quoted(string text) {
		return "\"" + text.replace ("\\", "\\\\").replace ("\"", "\\\"").replace ("\n", "\\n").replace ("\r", "\\r").replace ("\t", "\\t") + "\"";
	}
	private static bool identifier(string text) {
		if (text.length == 0 || text.length > 64) {
			return false;
		}
		for (int i = 0; i < text.length; i++) {
			char c = text[i];
			if (!(c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || i > 0 && c >= '0' && c <= '9')) {
				return false;
			}
		}
		return true;
	}
	private static int identity(string text) {
		uint hash = 2166136261u;
		for (int i = 0; i < text.length; i++) {
			hash = (hash ^ (uint8) text[i]) * 16777619u;
		}
		int result = (int) (hash & 0x7fffffffu);
		return result == 0 ? 1 : result;
	}
	private static bool factory(NativeInstanceSymbol owner, MethodSymbol method) {
		foreach (var property in owner.properties) {
			if (property.factory == method) {
				return true;
			}
		}
		return false;
	}
	private static bool copied_record(CheckedProgram program, SemanticType type) {
		var fields = new DescriptorFields (program);
		return CopyabilityAuthority.value_copy (type, fields.lookup) == Copyability.COPYABLE;
	}
	private static string signature(MethodSymbol method) {
		var text = new StringBuilder (method.result_contract == ResultOwnershipContract.OWNED_TRANSFER ? "owned " : "");
		if (method.async_body != null) {
			text.append ("async ");
		}
		if (method.nonnull_result) {
			text.append ("nonnull ");
		}
		text.append (method.return_type.display_name ());
		text.append ("(");
		for (int p = 0; p < method.parameters.length; p++) {
			if (p != 0) {
				text.append (", ");
			}
			var parameter = method.parameters[p];
			if (parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER) {
				text.append ("owned ");
			} else if (parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE) {
				text.append ("borrowed ");
			}
			if (parameter.requires_nonnull) {
				text.append ("nonnull ");
			}
			text.append (parameter.semantic_type.display_name ());
		}
		text.append (")");
		if (method.throws_type != null) {
			text.append (" throws " + method.throws_type.display_name ());
		}
		return text.str;
	}
	private static DescriptorType snapshot(CheckedProgram program, NativeInstanceSymbol owner, string alias, string module) throws NativeDescriptorError {
		if (owner.semantic_type.is_parameterized () || owner.semantic_type is ExactGenericClassType) {
			throw new NativeDescriptorError.INVALID ("descriptor selection currently requires a nongeneric native Class, record or interface");
		}
		var type = new DescriptorType ();
		type.name = owner.name;
		type.alias = alias;
		var klass = owner as ClassSymbol;
		type.reference = klass != null;
		type.kind = klass == null ? "record" : ((ClassType) klass.semantic_type).is_interface ? "interface" : "class";
		type.id = identity (module + "::" + type.kind + "::" + type.name);
		type.readable = klass != null || copied_record (program, owner.semantic_type);
		foreach (var field in owner.fields) {
			if (field.is_private) {
				continue;
			}
			string name = (field.is_owned_field ? "owned " : "") + (field.requires_nonnull ? "nonnull " : "") + field.semantic_type.display_name ();
			var member = new DescriptorMember (field, "field", name);
			if (field.semantic_type == program.types.int_type && !field.is_owned_field) {
				member.read_int = "value." + field.name;
			}
			type.members.add (member);
		}
		foreach (var property in owner.properties) {
			string name = (property.is_borrowed ? "borrowed " : "") + (property.getter.nonnull_result ? "nonnull " : "") + property.semantic_type.display_name ();
			if (property.getter.throws_type != null) {
				name += " throws " + property.getter.throws_type.display_name ();
			}
			var member = new DescriptorMember (property, "property", name);
			if (property.semantic_type == program.types.int_type) {
				member.read_int = "value." + property.name;
			}
			type.members.add (member);
		}
		foreach (var method in owner.methods) {
			if (factory (owner, method) || method.generic_method_instance != null) {
				continue;
			}
			var member = new DescriptorMember (method, "method", signature (method));
			bool callable = method.async_body == null && method.return_type == program.types.int_type && method.result_contract == ResultOwnershipContract.UNMANAGED && method.parameters.length <= 1;
			foreach (var parameter in method.parameters) {
				callable = callable && parameter.semantic_type == program.types.int_type && parameter.pointer_contract == PointerParameterContract.UNMANAGED;
			}
			if (callable) {
				member.call_int = "value." + method.name + (method.parameters.length == 0 ? "()" : "(argument)");
			}
			type.members.add (member);
		}
		if (type.members.length > 256) {
			throw new NativeDescriptorError.INVALID ("selected descriptor exceeds 256 public declared members");
		}
		var ordered = new GLib.List<DescriptorMember> ();
		foreach (var member in type.members) {
			ordered.append (member);
		}
		ordered.sort ((a, b) => a.position < b.position ? -1 : a.position > b.position ? 1 : 0);
		type.members = new GenericArray<DescriptorMember> ();
		foreach (var member in ordered) {
			type.members.add (member);
		}
		return type;
	}
	private static void type_queries(StringBuilder text, GenericArray<DescriptorType> types) {
		foreach (string query in new string[] {"name", "kind", "member_count"}) {
			text.append_printf ("%s type_%s(TypeDescriptor descriptor) throws Error {\n\tvalidate_type(descriptor);\n", query == "member_count" ? "int" : "string", query);
			foreach (var type in types) {
				text.append_printf ("\tif (descriptor.id == %d) { return %s; }\n", type.id, query == "member_count" ? type.members.length.to_string () : quoted (query == "name" ? type.name : type.kind));
			}
			text.append ("\tthrow new Error(\"unknown native type descriptor\");\n}\n");
		}
	}
	private static void member_queries(StringBuilder text, GenericArray<DescriptorType> types) {
		text.append ("MemberDescriptor member(TypeDescriptor owner, int ordinal) throws Error {\n\tint count = type_member_count(owner);\n\tif (ordinal < 0 || ordinal >= count) { throw new Error(\"native member index out of bounds\"); }\n\tMemberDescriptor result = {owner = owner, ordinal = ordinal};\n\treturn result;\n}\n");
		text.append ("void validate_member(MemberDescriptor descriptor) throws Error {\n\tint count = type_member_count(descriptor.owner);\n\tif (descriptor.ordinal < 0 || descriptor.ordinal >= count) { throw new Error(\"native member index out of bounds\"); }\n}\n");
		foreach (string query in new string[] {"name", "kind", "type"}) {
			text.append_printf ("string member_%s(MemberDescriptor descriptor) throws Error {\n\tvalidate_member(descriptor);\n", query);
			foreach (var type in types) {
				text.append_printf ("\tif (descriptor.owner.id == %d) {\n", type.id);
				for (int m = 0; m < type.members.length; m++) {
					var member = type.members[m];
					text.append_printf ("\t\tif (descriptor.ordinal == %d) { return %s; }\n", m, quoted (query == "name" ? member.name : query == "kind" ? member.kind : member.type_name));
				}
				text.append ("\t}\n");
			}
			text.append ("\tthrow new Error(\"unknown native member descriptor\");\n}\n");
		}
	}
	private static void readers(StringBuilder text, GenericArray<DescriptorType> types) {
		foreach (var type in types) {
			if (!type.readable) {
				continue;
			}
			foreach (string action in new string[] {"read", "call"}) {
				if (action == "call" && !type.reference) {
					continue;
				}
				text.append_printf ("int %s_%s_int(%s value, MemberDescriptor descriptor%s) throws Error {\n\tvalidate_member(descriptor);\n\tif (descriptor.owner.id != %d) { throw new Error(\"descriptor receiver type mismatch\"); }\n", action, type.alias, type.name, action == "call" ? ", int argument" : "", type.id);
				if (type.reference) {
					text.append ("\tif (value == null) { throw new Error(\"null native descriptor receiver\"); }\n");
				}
				for (int m = 0; m < type.members.length; m++) {
					var member = type.members[m];
					string? expression = action == "read" ? member.read_int : member.call_int;
					if (expression != null) {
						text.append_printf ("\tif (descriptor.ordinal == %d) { return %s; }\n", m, expression);
					}
				}
				text.append ("\tthrow new Error(\"member has no selected copied int operation\");\n}\n");
			}
		}
	}
	public static string generate(CheckedProgram program, string module, string[] nominations) throws NativeDescriptorError {
		if (!identifier (module) || nominations.length == 0 || nominations.length > 32) {
			throw new NativeDescriptorError.INVALID ("requires one identifier module and 1..32 explicit type selections");
		}
		string prefix = "NativeMetadata_" + module + ".";
		bool error_root = false;
		foreach (var owner in program.classes) {
			if (owner.name == "Error" && owner.exception_root && owner.constructor != null && owner.constructor.parameters.length == 1 && owner.constructor.parameters[0].semantic_type is StringType) {
				error_root = true;
			}
		}
		if (!error_root) {
			throw new NativeDescriptorError.INVALID ("checked descriptor queries require the explicitly selected standard Error root");
		}
		foreach (var owner in program.native_instances ()) {
			if (owner.name.has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains native declarations");
			}
		}
		foreach (var function in program.all_definitions ()) {
			if (function.symbol.name.has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains functions");
			}
		}
		foreach (var constant in program.constants) {
			if (constant.region == null && constant.name.has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains constants");
			}
		}
		foreach (var enumeration in program.enums) {
			if (enumeration.semantic_type.display_name ().has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains enums");
			}
		}
		foreach (var handle in program.handles) {
			if (handle.name.has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains handles");
			}
		}
		foreach (var function in program.c_functions) {
			if (function.name.has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains foreign functions");
			}
		}
		foreach (var definition in program.generic_classes) {
			if (definition.name.has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains generic Classes");
			}
		}
		foreach (var definition in program.generic_structs) {
			if (definition.definition.name.has_prefix (prefix)) {
				throw new NativeDescriptorError.INVALID ("descriptor module namespace already contains generic records");
			}
		}
		var types = new GenericArray<DescriptorType> ();
		var aliases = new HashTable<string, bool> (str_hash, str_equal);
		var ids = new HashTable<int, string> (direct_hash, direct_equal);
		foreach (string nomination in nominations) {
			int equals = nomination.index_of ("=");
			string name = equals < 0 ? nomination : nomination.substring (equals + 1);
			string alias = equals < 0 ? name.substring (name.last_index_of (".") + 1) : nomination.substring (0, equals);
			if (!identifier (alias) || aliases.contains (alias)) {
				throw new NativeDescriptorError.INVALID ("descriptor aliases must be distinct identifiers; use Alias=Qualified.Type");
			}
			NativeInstanceSymbol? selected = null;
			foreach (var owner in program.native_instances ()) {
				if (owner.name == name) {
					selected = owner;
				}
			}
			if (selected == null) {
				throw new NativeDescriptorError.INVALID ("unknown native descriptor type '%s'", name);
			}
			var type = snapshot (program, selected, alias, module);
			if (ids.contains (type.id)) {
				throw new NativeDescriptorError.INVALID ("duplicate selection or nominal descriptor ID collision");
			}
			aliases.insert (alias, true);
			ids.insert (type.id, type.name);
			types.add (type);
		}
		var ordered = new GLib.List<DescriptorType> ();
		foreach (var type in types) {
			ordered.append (type);
		}
		ordered.sort ((a, b) => strcmp (a.name, b.name));
		types = new GenericArray<DescriptorType> ();
		foreach (var type in ordered) {
			types.add (type);
		}
		int unit = identity ("astra-native-descriptors/1::" + module);
		var text = new StringBuilder ("// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception\n// astra-native-descriptors/1; selected declarations only; no object layout access.\n");
		text.append_printf ("namespace NativeMetadata_%s;\nstruct TypeDescriptor { int unit_tag; int version; int id; }\nstruct MemberDescriptor { TypeDescriptor owner; int ordinal; }\n", module);
		text.append_printf ("void validate_type(TypeDescriptor descriptor) throws Error {\n\tif (descriptor.unit_tag != %d || descriptor.version != 1) { throw new Error(\"descriptor module/version mismatch\"); }\n", unit);
		text.append ("\tif (");
		for (int t = 0; t < types.length; t++) {
			if (t != 0) {
				text.append (" || ");
			}
			text.append_printf ("descriptor.id == %d", types[t].id);
		}
		text.append (") { return; }\n\tthrow new Error(\"unknown native type descriptor\");\n}\n");
		text.append_printf ("TypeDescriptor from_id(int id) throws Error {\n\tTypeDescriptor result = {unit_tag = %d, version = 1, id = id};\n\tvalidate_type(result);\n\treturn result;\n}\n", unit);
		text.append ("TypeDescriptor lookup(string name) throws Error {\n");
		foreach (var type in types) {
			text.append_printf ("\tif (name == %s) { return from_id(%d); }\n", quoted (type.name), type.id);
		}
		text.append ("\tthrow new Error(\"unknown native type name\");\n}\n");
		type_queries (text, types);
		member_queries (text, types);
		readers (text, types);
		var files = new GenericArray<Source.SourceFile> ();
		files.add (new Source.SourceFile.from_text ("<native-descriptors>", text.str));
		try {
			var syntax = Syntax.SyntaxProgram.parse (new Source.SourceSet (files));
			if (syntax.diagnostic != null) {
				throw new NativeDescriptorError.INVALID ("descriptor module identifier or generated syntax is unsupported: %s", syntax.diagnostic.format ());
			}
		} catch (Source.SourceSetError error) {
			throw new NativeDescriptorError.INVALID ("descriptor source set is invalid: %s", error.message);
		}
		return text.str;
	}
	public static void write(string path, string source) throws NativeDescriptorError {
		try {
			FileUtils.set_contents (path, source);
		} catch (FileError error) {
			throw new NativeDescriptorError.OUTPUT ("cannot write descriptor source '%s': %s", path, error.message);
		}
	}
}
}
