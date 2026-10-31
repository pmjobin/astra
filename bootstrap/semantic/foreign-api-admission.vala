// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;

namespace Astra.Semantic {
internal delegate bool ForeignRootLookup(SemanticType type, out string prefix, out bool shared, out ForeignValueKind kind);
// One frontend channel normalizer for declarations in either direction.
// Callbacks resolve exact checked types; the resulting schema retains none.
internal class ForeignParameterAdmission : Object {
	public Diagnostic? diagnostic;
	private ForeignRecordLookup? records;
	private ForeignRootLookup? roots;
	public ForeignParameterAdmission (owned ForeignRecordLookup? records = null, owned ForeignRootLookup? roots = null) {
		this.records = (owned) records;
		this.roots = (owned) roots;
	}
	private bool fail(SourceSpan span, string message) {
		diagnostic = new Diagnostic (span, message);
		return false;
	}
	public static int parameter_index(FunctionSymbol function, string name) {
		for (int p = 0; p < function.parameters.length; p++) {
			if (function.parameters[p].name == name) {
				return p;
			}
		}
		return -1;
	}
	public ForeignChannel? parameter_channel(FunctionSymbol function, ParameterSymbol parameter, SyntaxNode source, ForeignPolicySyntax? annotation) {
		if (parameter.semantic_type is CallbackType) {
			var value = ForeignApiTypes.callback (parameter.semantic_type);
			bool nullable = false;
			if (value == null || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
				fail (parameter.span, "foreign Callback requires its exact borrowed scalar signature");
				return null;
			}
			if (annotation != null) {
				foreach (var entry in annotation.entries) {
					string key = entry.key.spelling (), fact = entry.decoded_value;
					if (key == "parameter" || key == "direction" && fact == "in" || key == "scope" && fact == "call" || key == "transfer" && fact == "none") {
						continue;
					}
					if (key == "nullable" && (fact == "true" || fact == "false")) {
						nullable = fact == "true";
						continue;
					}
					fail (entry.span, "Callback carries intrinsic userdata and requires an input call-only borrow");
					return null;
				}
			}
			return new ForeignChannel (parameter.name, value, ForeignDirection.IN, ForeignTransfer.BORROW, nullable, ForeignTextEncoding.NONE, -1, -1, -1, "", true, -1, -1, false, false, false, false, true);
		}
		var copied = ForeignApiTypes.copied (parameter.semantic_type, records);
		var pointee = ForeignApiTypes.scalar_pointee (parameter.semantic_type);
		bool scalar_reference = pointee != null && parameter.pointer_contract == PointerParameterContract.BORROWED_NOESCAPE;
		if (scalar_reference) {
			return ForeignApiAdmission.reference_channel (parameter, annotation, out diagnostic);
		}
		bool bytes = ForeignApiTypes.byte_view (parameter.semantic_type);
		bool text = parameter.semantic_type is StringType;
		bool object = parameter.semantic_type is ClassType || parameter.semantic_type is HandleType;
		bool owned_object = object && parameter.pointer_contract == PointerParameterContract.OWNED_TRANSFER;
		if (!scalar_reference && !owned_object && ((!(bytes || text || object) || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) && (copied == null || parameter.pointer_contract != PointerParameterContract.UNMANAGED))) {
			fail (parameter.span, "declarations-v1 parameter channel lowering is not implemented for this native type");
			return null;
		}
		var direction = ForeignDirection.IN;
		bool nullable = false, result_count = false;
		var encoding = text ? ForeignTextEncoding.UTF8_COUNTED : ForeignTextEncoding.BYTES;
		int length = -1, capacity = -1, produced = -1;
		if (annotation != null) {
			foreach (var entry in annotation.entries) {
				string key = entry.key.spelling (), value = entry.decoded_value;
				switch (key) {
				case "parameter": break;
				case "direction":
					if (value == "in") {
						direction = ForeignDirection.IN;
					} else if (value == "out") {
						direction = ForeignDirection.OUT;
					} else if (value == "inout") {
						direction = ForeignDirection.INOUT;
					} else {
						fail (entry.span, "ForeignChannel direction requires in/out/inout");
						return null;
					} break;
				case "nullable": if (value != "true" && value != "false") {
						fail (entry.span, "ForeignChannel nullable requires true/false");
						return null;
				}
					nullable = value == "true";
					break;
				case "encoding":
					if (text && value == "utf8-nul") {
						encoding = ForeignTextEncoding.UTF8_NUL;
					} else if (!(bytes || text) || value != (text ? "utf8-counted" : "bytes")) {
						fail (entry.span, "ForeignChannel encoding must match its actual native counted value");
						return null;
					}
					break;
				case "scope": if (owned_object || !(bytes || text || object || scalar_reference) || value != "call") {
						fail (entry.span, "ForeignChannel scope requires an actual call-scoped borrowed channel");
						return null;
				}
					break;
				case "transfer": if (value != (owned_object ? "full" : "none")) {
						fail (entry.span, "ForeignChannel transfer differs from its checked native parameter ownership");
						return null;
				}
					break;
				case "length": case "capacity": case "produced":
					if (!(bytes || text)) {
						fail (entry.span, "ForeignChannel count facts require a counted native value");
						return null;
					}
					if (key == "produced" && value == "result") {
						result_count = true;
						break;
					}
					int index = ForeignParameterAdmission.parameter_index (function, value);
					if (index < 0) {
						fail (entry.span, "ForeignChannel count must name an actual parameter or the produced result");
						return null;
					}
					if (key == "length") {
						length = index;
					} else if (key == "capacity") {
						capacity = index;
					} else {
						produced = index;
					} break;
				default:
					fail (entry.span, "ForeignChannel fact is incompatible with this native parameter");
					return null;
				}
			}
		}

		if (object) {
			string object_prefix = "";
			bool shared = false;
			ForeignValueKind object_kind = ForeignValueKind.NATIVE_OBJECT;
			if (direction != ForeignDirection.IN || parameter.requires_nonnull && nullable || (roots == null || !roots (parameter.semantic_type, out object_prefix, out shared, out object_kind))) {
				fail (source.span, "native object input requires its exact declared C root, borrow direction and checked nullability");
				return null;
			}
			return new ForeignChannel (parameter.name, new ForeignValueType (object_kind, parameter.semantic_type.nominal_name ()), ForeignDirection.IN, owned_object ? ForeignTransfer.OWN : ForeignTransfer.BORROW,
				nullable, ForeignTextEncoding.NONE, -1, -1, -1, owned_object ? object_prefix + (shared ? "_release" : "_destroy") : "", !owned_object, -1, -1, false, false, parameter.requires_nonnull);
		}
		if (!(bytes || text)) {
			if (direction != ForeignDirection.IN || nullable) {
				fail (source.span, "copied scalar input cannot acquire out-direction or nullability");
				return null;
			}
			return new ForeignChannel (parameter.name, copied);
		}
		if (text && direction != ForeignDirection.IN) {
			fail (source.span, "native string input requires an immutable call-scoped input channel");
			return null;
		}
		var channel = new ForeignChannel (parameter.name, new ForeignValueType (text ? ForeignValueKind.TEXT : ForeignValueKind.BYTES), direction, ForeignTransfer.BORROW,
			nullable, encoding, length, capacity, produced, "", true, -1, -1, encoding != ForeignTextEncoding.UTF8_NUL && length < 0 && capacity < 0, result_count);
		if (!channel.valid ()) {
			fail (source.span, "byte channel requires exact count/capacity and produced-result authority");
			return null;
		}
		return channel;
	}
}
internal class ForeignApiAdmission : Object {
	private Diagnostic? diagnostic;
	private ClassSymbol owner;
	private string prefix;
	private GenericArray<ForeignMemberContract> members = new GenericArray<ForeignMemberContract> ();
	private bool has_bool;
	private uint default_personalities = ForeignClassPolicy.C;
	private uint member_personalities = ForeignClassPolicy.C;
	private GenericArray<NativeInstanceSymbol> instances;
	private GenericArray<NativeInstanceDeclarationSyntax> declarations;
	private ForeignRootLookup? imported_roots;
	private ForeignApiAdmission (ClassSymbol owner, string prefix, GenericArray<NativeInstanceSymbol> instances, GenericArray<NativeInstanceDeclarationSyntax> declarations, owned ForeignRootLookup? imported_roots) {
		this.owner = owner;
		this.prefix = prefix;
		this.instances = instances;
		this.declarations = declarations;
		this.imported_roots = (owned) imported_roots;
	}
	private bool native_root(SemanticType type, out string prefix, out bool shared, out ForeignValueKind kind) {
		prefix = "";
		shared = false;
		kind = ForeignValueKind.NATIVE_OBJECT;
		if (type is HandleType) {
			return imported_roots != null && imported_roots (type, out prefix, out shared, out kind);
		}
		for (uint i = 0; i < instances.length; i++) {
			var root = instances[i] as ClassSymbol;
			if (root == null || root.semantic_type != type || i >= declarations.length) {
				continue;
			}
			var syntax = declarations[i] as ClassDeclarationSyntax;
			if (!selected (syntax)) {
				return false;
			}
			foreach (var entry in syntax.foreign_export.entries) {
				if (entry.key.spelling () == "name") {
					prefix = entry.decoded_value;
				}
			}
			shared = root.concurrency_policy != null;
			return ForeignClassPolicy.identifier (prefix) && !prefix.has_prefix ("astra_");
		}
		return false;
	}
	internal static ForeignValueType? record_for(SemanticType type, GenericArray<NativeInstanceSymbol> instances) {
		var names = new GenericArray<string> ();
		var fields = new GenericArray<SemanticType> ();
		if (type is GenericStructApplicationType) {
			var application = (GenericStructApplicationType) type;
			if (application.definition == null) {
				return null;
			}
			foreach (var field in application.definition.fields) {
				names.add (field.name);
				fields.add (application.field_type (field));
			}
		} else {
			foreach (var instance in instances) {
				var structure = instance as StructSymbol;
				if (structure == null || structure.semantic_type != type) {
					continue;
				}
				if (structure.representation != null && structure.representation.is_union) {
					return null;
				}
				foreach (var field in structure.fields) {
					if (field.is_private) {
						return null;
					}
					names.add (field.name);
					fields.add (field.semantic_type);
				}
				break;
			}
		}
		return ForeignApiTypes.record (type, names, fields);
	}
	private ForeignValueType? record(SemanticType type) {
		return record_for (type, instances);
	}
	public static bool selected(ClassDeclarationSyntax? syntax) {
		if (syntax != null && syntax.foreign_export != null) {
			foreach (var entry in syntax.foreign_export.entries) {
				if (entry.key.spelling () == "profile" && entry.decoded_value == "declarations-v1") {
					return true;
				}
			}
		}
		return false;
	}
	private bool fail(SourceSpan span, string message) {
		diagnostic = new Diagnostic (span, message);
		return false;
	}
	public static ForeignChannel? reference_channel(ParameterSymbol parameter, ForeignPolicySyntax? annotation, out Diagnostic? diagnostic) {
		diagnostic = null;
		var value = ForeignApiTypes.scalar_pointee (parameter.semantic_type);
		var direction = ForeignDirection.IN;
		if (value == null || parameter.pointer_contract != PointerParameterContract.BORROWED_NOESCAPE) {
			diagnostic = new Diagnostic (parameter.span, "scalar reference requires an actual borrowed noescape native pointer");
			return null;
		}
		if (annotation != null) {
			foreach (var entry in annotation.entries) {
				string key = entry.key.spelling (), fact = entry.decoded_value;
				if (key == "nullable" && fact == "true") {
					diagnostic = new Diagnostic (annotation.span, "scalar reference channel requires a mandatory typed value place");
					return null;
				}
				if (key == "parameter" || key == "scope" && fact == "call" || key == "transfer" && fact == "none" || key == "nullable" && fact == "false") {
					continue;
				}
				if (key == "direction" && (fact == "in" || fact == "out" || fact == "inout")) {
					direction = fact == "out" ? ForeignDirection.OUT : fact == "inout" ? ForeignDirection.INOUT : ForeignDirection.IN;
					continue;
				}
				diagnostic = new Diagnostic (entry.span, "scalar reference channel requires a mandatory call-scoped value place with in/out/inout direction");
				return null;
			}
		}
		return new ForeignChannel (parameter.name, value, direction, ForeignTransfer.COPY, false, ForeignTextEncoding.NONE, -1, -1, -1, "", true, -1, -1, false, false, false, true);
	}
	private ForeignChannel? parameter_channel(FunctionSymbol function, ParameterSymbol parameter, SyntaxNode source, ForeignPolicySyntax? annotation) {
		var normalizer = new ForeignParameterAdmission (record, native_root);
		var result = normalizer.parameter_channel (function, parameter, source, annotation);
		if (result == null) {
			diagnostic = normalizer.diagnostic;
		}
		return result;
	}
	private bool callable(FunctionSymbol function, ForeignMemberKind kind, int ordinal, string name, SyntaxNode source) {
		var span = source.span;
		if (function.async_body != null) {
			return fail (span, "declarations-v1 async native bridge lowering is not implemented yet");
		}
		var annotations = new HashTable<string, ForeignPolicySyntax> (str_hash, str_equal);
		foreach (var annotation in source.foreign_channels) {
			string parameter = "";
			foreach (var entry in annotation.entries) {
				if (entry.key.spelling () == "parameter") {
					parameter = entry.decoded_value;
				}
			}
			if (parameter == "result" && ForeignParameterAdmission.parameter_index (function, parameter) >= 0) {
				return fail (annotation.span, "ForeignChannel result is ambiguous with an actual parameter named result");
			}
			if (parameter != "result" && ForeignParameterAdmission.parameter_index (function, parameter) < 0 || annotations.contains (parameter)) {
				return fail (annotation.span, "ForeignChannel requires one unique actual native parameter or result");
			}
			annotations.insert (parameter, annotation);
		}
		var parameters = new GenericArray<ForeignChannel> ();
		foreach (var parameter in function.parameters) {
			var channel = parameter_channel (function, parameter, source, annotations.lookup (parameter.name));
			if (channel == null) {
				return false;
			}
			has_bool |= ForeignApiTypes.uses_bool (channel.value_type);
			parameters.add (channel);
		}
		var result_annotation = annotations.lookup ("result");
		var result_encoding = ForeignTextEncoding.UTF8_COUNTED;
		bool nullable_result = false;
		if (function.return_type is StringType && result_annotation != null) {
			foreach (var entry in result_annotation.entries) {
				if (entry.key.spelling () == "encoding" && entry.decoded_value == "utf8-nul") {
					result_encoding = ForeignTextEncoding.UTF8_NUL;
				}
			}
		}
		if ((function.return_type is ClassType || function.return_type is HandleType) && result_annotation != null) {
			foreach (var entry in result_annotation.entries) {
				if (entry.key.spelling () == "nullable" && entry.decoded_value == "true") {
					nullable_result = true;
				}
			}
		}
		ForeignChannel result;
		if (kind == ForeignMemberKind.CONSTRUCTOR) {
			result = new ForeignChannel ("result", new ForeignValueType (ForeignValueKind.NATIVE_OBJECT, owner.name),
				ForeignDirection.OUT, ForeignTransfer.OWN, false, ForeignTextEncoding.NONE, -1, -1, -1,
				prefix + (owner.concurrency_policy == null ? "_destroy" : "_release"));
		} else if (function.return_type is ClassType || function.return_type is HandleType) {
			string result_prefix = "";
			bool shared = false;
			ForeignValueKind object_kind = ForeignValueKind.NATIVE_OBJECT;
			if (function.result_contract != ResultOwnershipContract.OWNED_TRANSFER || nullable_result && function.nonnull_result || !native_root (function.return_type, out result_prefix, out shared, out object_kind)) {
				return fail (span, "native object result requires an exact declared root and compatible owned/nullability contract");
			}
			result = new ForeignChannel ("result", new ForeignValueType (object_kind, function.return_type.nominal_name ()), ForeignDirection.OUT, ForeignTransfer.OWN,
				nullable_result, ForeignTextEncoding.NONE, -1, -1, -1, result_prefix + (shared ? "_release" : "_destroy"), false, -1, -1, false, false, function.nonnull_result);
		} else if (function.return_type is StringType) {
			result = new ForeignChannel ("result", new ForeignValueType (ForeignValueKind.TEXT), ForeignDirection.OUT, ForeignTransfer.OWN,
				false, result_encoding, -1, -1, -1, prefix + "_text_release", false, -1, -1, result_encoding == ForeignTextEncoding.UTF8_COUNTED);
		} else if (ForeignApiTypes.byte_view (function.return_type) && function.result_contract == ResultOwnershipContract.OWNED_TRANSFER) {
			result = new ForeignChannel ("result", new ForeignValueType (ForeignValueKind.BYTES), ForeignDirection.OUT, ForeignTransfer.OWN,
				false, ForeignTextEncoding.BYTES, -1, -1, -1, prefix + "_bytes_release", false, -1, -1, true);
		} else {
			var type = ForeignApiTypes.copied (function.return_type, record);
			if (type == null) {
				return fail (span, "declarations-v1 non-scalar native result lowering is not implemented yet");
			}
			has_bool |= ForeignApiTypes.uses_bool (type);
			result = new ForeignChannel ("result", type, ForeignDirection.OUT);
		}
		if (result_annotation != null) {
			foreach (var entry in result_annotation.entries) {
				string key = entry.key.spelling (), value = entry.decoded_value;
				if (key == "parameter" || key == "direction" && value == "out" || key == "transfer" && value == (result.transfer == ForeignTransfer.OWN ? "full" : "none") || key == "nullable" && value == (result.nullable ? "true" : "false") || key == "encoding" && (result.value_type.kind == ForeignValueKind.BYTES && value == "bytes" || result.value_type.kind == ForeignValueKind.TEXT && (value == "utf8-counted" || value == "utf8-nul"))) {
					continue;
				}
				return fail (entry.span, "ForeignChannel result facts differ from its actual result ownership or representation");
			}
		}
		int32 domain = 0, null_status = 0;
		string errors_text = "";
		foreach (var entry in source.foreign_member.entries) {
			string key = entry.key.spelling ();
			if (key == "errors") {
				errors_text = entry.decoded_value;
			}
			if (key == "error_domain" || key == "null_status") {
				int64 value;
				if (!int64.try_parse (entry.decoded_value, out value) || value <= 0 || value > int32.MAX) {
					return fail (entry.span, "Foreign error_domain/null_status requires a positive signed 32-bit integer");
				}
				if (key == "error_domain") {
					domain = (int32) value;
				} else {
					null_status = (int32) value;
				}
			}
		}
		ForeignErrorMap? mapping = null;
		string error_origin = function.throws_type == null ? "" : function.throws_type.nominal_name ();
		if (error_origin == "") {
			if (domain != 0 || errors_text != "") {
				return fail (span, "Foreign error mapping requires an actual native throws contract");
			}
		} else {
			var cases = new GenericArray<ForeignErrorCase> ();
			foreach (string item in errors_text.split (",")) {
				string[] pair = item.strip ().split ("=");
				int64 value = 0;
				if (pair.length != 2 || !int64.try_parse (pair[1].strip (), out value) || value < int32.MIN || value >= 0) {
					return fail (span, "Foreign errors requires named negative signed 32-bit status mappings");
				}
				cases.add (new ForeignErrorCase (pair[0].strip (), (int32) value));
			}
			mapping = new ForeignErrorMap (domain, cases);
		}
		var member = new ForeignMemberContract (kind, name, ForeignApiTypes.member_key (owner.name, kind, ordinal), parameters, result, error_origin, member_personalities, ordinal, mapping, null_status);
		var roots = new ForeignRootCatalog ();
		foreach (var instance in instances) {
			if (instance is ClassSymbol) {
				roots.add (instance.semantic_type, null);
			}
		}
		if (!member.valid () || !ForeignApiTypes.errors (member, function.throws_type, roots.lookup_class)) {
			return fail (span, "Foreign member requires consistent channel/count relationships, exact native exception types, specific-before-base ordering and an exhaustive final throws-bound mapping; null_status requires a nullable owned object result");
		}
		members.add (member);
		function.bind_foreign_heap_boundary ();
		return true;
	}
	private bool collect(ClassDeclarationSyntax syntax) {
		for (int ordinal = 0; ordinal < syntax.members.length; ordinal++) {
			var source = syntax.members[ordinal];
			var selection = source.foreign_member;
			if (selection == null) {
				if (source.foreign_channels.length != 0) {
					return fail (source.span, "ForeignChannel requires an explicitly selected Foreign member");
				}
				continue;
			}
			string name = "";
			member_personalities = default_personalities;
			foreach (var entry in selection.entries) {
				if (entry.key.spelling () == "name") {
					name = entry.decoded_value;
				} else if (entry.key.spelling () == "errors" || entry.key.spelling () == "error_domain" || entry.key.spelling () == "null_status") {
					continue;
				} else if (entry.key.spelling () == "personalities") {
					member_personalities = 0;
					foreach (string item in entry.decoded_value.split (",")) {
						string selected = item.strip ();
						uint bit = selected == "c" ? ForeignClassPolicy.C : selected == "gobject" ? ForeignClassPolicy.GOBJECT : 0;
						if (bit == 0 || (bit & default_personalities) == 0 || (member_personalities & bit) != 0) {
							return fail (entry.span, "Foreign member personality must be a distinct selected Class surface");
						}
						member_personalities |= bit;
					}
				} else {
					return fail (entry.span, "Class Foreign selection requires its member name, effects and selected personalities; native bindings belong to interface requirements");
				}
			}
			var lifecycle = source as LifecycleDeclarationSyntax;
			if (lifecycle != null) {
				if (!lifecycle.is_constructor || owner.constructor == null) {
					return fail (source.span, "Foreign selects construction; destruction follows the declared unique/shared owner contract");
				}
				if (!callable (owner.constructor, ForeignMemberKind.CONSTRUCTOR, ordinal, name == "" ? "create" : name, source)) {
					return false;
				}
				continue;
			}
			var property = source as PropertyDeclarationSyntax;
			if (property != null) {
				var symbol = owner.find_property (property.name.spelling ());
				if (name == "") {
					name = symbol.name;
				}
				if (!callable (symbol.getter, ForeignMemberKind.GETTER, ordinal, "get_" + name, source)) {
					return false;
				}
				if (symbol.setter != null && !callable (symbol.setter, ForeignMemberKind.SETTER, ordinal, "set_" + name, source)) {
					return false;
				}
				continue;
			}
			var method = source as FunctionDeclarationSyntax;
			if (method == null) {
				return fail (source.span, "Foreign requires a resolved constructor, method or property");
			}
			var target = owner.find_method (method.name.spelling ());
			if (method.is_signal) {
				if (owner.concurrency_policy == null || owner.concurrency_policy.identity != 1 || syntax.gobject_export == null || target == null || target.throws_type != null || target.return_type.kind != TypeKind.VOID || member_personalities != default_personalities && member_personalities != ForeignClassPolicy.GOBJECT) {
					return fail (source.span, "native signals require a plain Shared GObject root and nonthrowing void call-scoped signature");
				}
				member_personalities = ForeignClassPolicy.GOBJECT;
			}
			if (target == null || !callable (target, method.is_signal ? ForeignMemberKind.SIGNAL : ForeignMemberKind.METHOD,ordinal,name == "" ? target.name : name,source)) {
				return false;
			}
		}
		return true;
	}
	public static ForeignClassPolicy? admit(ClassSymbol owner,ClassDeclarationSyntax syntax,GenericArray<NativeInstanceSymbol> instances,GenericArray<NativeInstanceDeclarationSyntax> declarations,out Diagnostic? diagnostic,owned ForeignRootLookup? imported_roots = null,GenericArray<ForeignComInterface>? com_protocols = null,int foreign_selection = -1) {
		diagnostic = null;
		if (syntax.com_export != null && syntax.gobject_export != null && foreign_selection < 0) {
			diagnostic = new Diagnostic (syntax.span,"combined declarations-v1 personalities require explicit --foreign-personalities selection");
			return null;
		}
		string prefix = "",bool_abi = "";
		foreach (var entry in syntax.foreign_export.entries) {
			switch (entry.key.spelling ()) {
			case "name": prefix = entry.decoded_value;
				break;
			case "bool_abi": bool_abi = entry.decoded_value;
				break;
			case "profile": break;
				default: diagnostic = new Diagnostic (entry.span,"declarations-v1 selects declared members; legacy property selectors cannot be mixed");
				return null;
			}
		}
		if (owner.parent_class != null || owner.polymorphic || owner.exception_root || owner.generic_instance != null || owner.allocation_policy != null || owner.concurrency_policy != null && owner.concurrency_policy.identity != 1 && owner.concurrency_policy.identity != 3) {
			diagnostic = new Diagnostic (syntax.span,"declarations-v1 requires an ordinary unique or intrusive Shared root");
			return null;
		}

		var admission = new ForeignApiAdmission (owner,prefix,instances,declarations,(owned) imported_roots);
		admission.default_personalities = ForeignClassPolicy.C | (syntax.gobject_export == null ? 0 : ForeignClassPolicy.GOBJECT);
		if (!admission.collect (syntax)) {
			diagnostic = admission.diagnostic;
			return null;
		}
		if (owner.constructor != null && owner.constructor.throws_type != null) {
			int owned_fields = 0;
			foreach (var field in owner.fields) {
				if (field.is_owned_field || field.text_snapshot || field.semantic_type is OwnerSlotsType) {
					owned_fields++;
				}
			}
			if (owned_fields > 4096) {
				diagnostic = new Diagnostic (syntax.span,"checked constructor supports at most 4096 owned field retirement entries");
				return null;
			}
		}
		bool public_c_bool = false;
		foreach (var member in admission.members) {
			if ((member.personalities & ForeignClassPolicy.C) == 0) {
				continue;
			}
			public_c_bool |= ForeignApiTypes.uses_bool (member.result.value_type);
			for (uint p = 0; p < member.parameter_count; p++) {
				public_c_bool |= ForeignApiTypes.uses_bool (member.parameter (p).value_type);
			}
		}
		if (public_c_bool ? bool_abi != "c99" : bool_abi != "" && (!admission.has_bool || bool_abi != "c99")) {
			diagnostic = new Diagnostic (syntax.span,"declarations-v1 copied C bool channels require explicit bool_abi=c99");
			return null;
		}
		uint personalities = ForeignClassPolicy.C;
		var protocols = new GenericArray<ForeignComInterface> ();
		if (syntax.com_export != null) {
			string profile = "",threading = "",selected = "";
			foreach (var entry in syntax.com_export.entries) {
				switch (entry.key.spelling ()) {
				case "profile": profile = entry.decoded_value;
					break;
				case "threading": threading = entry.decoded_value;
					break;
				case "interfaces": selected = entry.decoded_value;
					break;
					default: diagnostic = new Diagnostic (entry.span,"declared COM export selects interface declarations, profile and constructing context");
					return null;
				}
			}
			if (profile != "declarations-v1" || threading != "constructing" || owner.concurrency_policy == null || owner.concurrency_policy.identity != 1 || selected == "") {
				diagnostic = new Diagnostic (syntax.com_export.span,"declared COM export requires a plain Shared root and explicit constructing-context interfaces");
				return null;
			}
			foreach (string item in selected.split (",")) {
				string name = item.strip ();
				ForeignComInterface? found = null;
				if (com_protocols != null) {
					foreach (var candidate in com_protocols) {
						if (candidate.name == name) {
							found = candidate;
							break;
						}
					}
				}
				if (found == null) {
					diagnostic = new Diagnostic (syntax.com_export.span,"COM export interface requires an exact typed declaration: " + name);
					return null;
				}
				protocols.add (found);
			}
			personalities |= ForeignClassPolicy.COM;
		}
		GObjectExportContract? gobject = null;
		if (syntax.gobject_export != null) {
			string type_name = "",space = "",version = "",profile = "";
			foreach (var entry in syntax.gobject_export.entries) {
				switch (entry.key.spelling ()) {
				case "type": type_name = entry.decoded_value;
					break;
				case "namespace": space = entry.decoded_value;
					break;
				case "version": version = entry.decoded_value;
					break;
				case "profile": profile = entry.decoded_value;
					break;
					default: diagnostic = new Diagnostic (entry.span,"declared GObject export requires explicit type, namespace, version and profile");
					return null;
				}
			}
			gobject = new GObjectExportContract (type_name,space,version,true);
			if (profile != "declarations-v1" || !gobject.valid () || owner.concurrency_policy == null || owner.concurrency_policy.identity != 1) {
				diagnostic = new Diagnostic (syntax.gobject_export.span,"declared GObject export requires a plain Shared root, exact type/namespace and numeric major.minor version");
				return null;
			}
			personalities |= ForeignClassPolicy.GOBJECT;
		}

		var contract = new ForeignApiContract (owner.name,prefix,owner.concurrency_policy == null ? ForeignLifetime.UNIQUE : ForeignLifetime.SHARED,personalities,admission.members,foreign_selection);
		var bindings = new GenericArray<ForeignComExportBinding> ();
		foreach (var protocol in protocols) {
			uint[] targets = {};
			for (uint r = 0; r < protocol.requirement_count; r++) {
				var requirement = protocol.requirement (r);
				string native_name = protocol.native_name (r);
				int target = -1;
				for (uint m = 0; m < contract.member_count; m++) {
					var member = contract.member (m);
					if (member.kind != requirement.kind || member.native_member_ordinal < 0 || member.native_member_ordinal >= syntax.members.length) {
						continue;
					}
					var source = syntax.members[member.native_member_ordinal];
					var method = source as FunctionDeclarationSyntax;
					var property = source as PropertyDeclarationSyntax;
					string source_name = method != null? method.name.spelling() : property != null? property.name.spelling() : "";
					if (source_name == native_name && ForeignComExportBinding.signature_matches (member,requirement)) {
						if (target != -1) {
							diagnostic = new Diagnostic (source.span,"ambiguous native COM requirement mapping");
							return null;
						}
						target = (int) m;
					}
				}
				if (target < 0) {
					diagnostic = new Diagnostic (syntax.com_export.span,"COM requirement lost its exact selected native member/signature: " + native_name);
					return null;
				}
				targets += (uint) target;
			}
			bindings.add (new ForeignComExportBinding (protocol,contract,targets));
		}
		var policy = new ForeignClassPolicy.declared (contract,bindings,gobject);
		if (!policy.valid ()) {
			diagnostic = new Diagnostic (syntax.span,"invalid declarations-v1 nominal identity, prefix, member selection or channel contract");
			return null;
		}
		return policy;
	}
}
}
