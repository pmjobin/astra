// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
public class GObjectExportContract : Object {
	private string type_identifier;
	private string namespace_identifier;
	private string version_identifier;
	public string type_name { get { return type_identifier; } }
	public string namespace_name { get { return namespace_identifier; } }
	public string version { get { return version_identifier; } }
	public bool declarations { get; private set; }
	// GI input scalar references are copied values at the public boundary.
	// Native lowering still receives a construction-local noescape reference.
	public static bool indirect_reference(ForeignChannel channel) {
		return channel.by_reference && channel.direction != ForeignDirection.IN;
	}
	public bool weak_cache { get; internal set; default = true; }
	public bool checked_context { get; internal set; default = true; }
	public bool native_owner { get; internal set; default = true; }
	public bool floating { get; internal set; default = false; }
	public GObjectExportContract (string type_name, string namespace_name, string version, bool declarations = false) {
		type_identifier = type_name;
		namespace_identifier = namespace_name;
		version_identifier = version;
		this.declarations = declarations;
	}
	private static bool version_valid(string version) {
		string[] pair = version.split (".");
		if (pair.length != 2) {
			return false;
		}
		foreach (string part in pair) {
			if (part.length == 0) {
				return false;
			}
			for (int c = 0; c < part.length; c++) {
				if (part[c] < '0' || part[c] > '9') {
					return false;
				}
			}
		}
		return true;
	}
	private static bool type_identifier_valid(string name) {
		if (name.length == 0 || !(name[0] >= 'A' && name[0] <= 'Z')) {
			return false;
		}
		for (int i = 0; i < name.length; i++) {
			char c = name[i];
			if (!(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9')) {
				return false;
			}
		}
		return true;
	}
	public bool valid() {
		return type_identifier_valid (type_name) && type_identifier_valid (namespace_name) && type_name.has_prefix (namespace_name) && type_name.length > namespace_name.length && (declarations ? version_valid (version) : version == "1.0") && weak_cache && checked_context && native_owner && !floating;
	}
	public string symbol_prefix() {
		var output = new StringBuilder ();
		for (int i = 0; i < type_name.length; i++) {
			char c = type_name[i];
			if (c >= 'A' && c <= 'Z') {
				if (i > 0 && (type_name[i - 1] >= 'a' && type_name[i - 1] <= 'z' || type_name[i - 1] >= '0' && type_name[i - 1] <= '9' || i + 1 < type_name.length && type_name[i + 1] >= 'a' && type_name[i + 1] <= 'z')) {
					output.append_c ('_');
				}
				output.append_c ((char) (c + 'a' - 'A'));
			} else {
				output.append_c (c);
			}
		}
		return output.str;
	}
	public string identity() {
		return (declarations ? "GObjectExport;declarations-v1;linux-x64;final-GType;gboolean32;gint32;pointer64;inref=value;outref=pointer;counted=GBytes;bounded=caller-array-slot+capacity-slot;owned=GLib-copy;POD=boxed-gboolean32;" : "GObjectExport;linux-x64-v1;") + "%s;%s;%s;%d,%d,%d,%d".printf (type_name, namespace_name, version, (int) weak_cache, (int) checked_context, (int) native_owner, (int) floating);
	}
	public GObjectExportContract copy() {
		var result = new GObjectExportContract (type_name, namespace_name, version, declarations);
		result.weak_cache = weak_cache;
		result.checked_context = checked_context;
		result.native_owner = native_owner;
		result.floating = floating;
		return result;
	}
}
public enum ComImportRole {
	NONE, ACQUIRE, CLONE, GET, SET, SCALE
}
public class ComImportContract : Object {
	private string declared_name;
	private string external_prefix;
	private string interface_identity;
	private string selected_view;
	public string native_name { get { return declared_name; } }
	public string prefix { get { return external_prefix; } }
	public string iid { get { return interface_identity; } }
	public string view { get { return selected_view; } }
	public int query_slot { get; internal set; default = 0; }
	public int acquire_slot { get; internal set; default = 1; }
	public int release_slot { get; internal set; default = 2; }
	public int method_slot { get; internal set; default = 3; }
	public bool checked_context { get; internal set; default = true; }
	public ComImportContract (string native_name, string prefix, string iid, string view) {
		declared_name = native_name;
		external_prefix = prefix;
		interface_identity = iid.ascii_down ();
		selected_view = view;
	}
	public bool valid() {
		return ForeignClassPolicy.identifier (native_name) && ForeignClassPolicy.identifier (prefix) && !prefix.has_prefix ("astra_") && ComExportContract.guid (iid) && (view == "value" || view == "scale") && query_slot == 0 && acquire_slot == 1 && release_slot == 2 && method_slot == 3 && checked_context;
	}
	public string identity() {
		return "COMImport;windows-x64-v1;%s;%s;%s;%s;%d,%d,%d,%d;%d".printf (native_name, prefix, iid, view, query_slot, acquire_slot, release_slot, method_slot, (int) checked_context);
	}
	public ComImportContract copy() {
		var result = new ComImportContract (native_name, prefix, iid, view);
		result.query_slot = query_slot;
		result.acquire_slot = acquire_slot;
		result.release_slot = release_slot;
		result.method_slot = method_slot;
		result.checked_context = checked_context;
		return result;
	}
	public static bool matches(ComImportContract? contract, string identity, string name, string cleanup) {
		return contract == null ? identity == "" : contract.valid () && contract.identity () == identity && contract.native_name == name && cleanup == contract.prefix + "_release";
	}
	public bool admits(ComImportRole role) {
		return role == ComImportRole.ACQUIRE || role == ComImportRole.CLONE || view == "value" && (role == ComImportRole.GET || role == ComImportRole.SET) || view == "scale" && role == ComImportRole.SCALE;
	}
	public static string suffix(ComImportRole role) {
		switch (role) {
		case ComImportRole.ACQUIRE: return "acquire";
		case ComImportRole.CLONE:
			return "clone";
		case ComImportRole.GET:
			return "get";
		case ComImportRole.SET:
			return "set";
		case ComImportRole.SCALE:
			return "scale";
		default:
			return "<invalid>";
		}
	}
}
public class ComExportContract : Object {
	private string value_identity;
	private string scale_identity;
	public string value_iid { get { return value_identity; } }
	public string scale_iid { get { return scale_identity; } }
	public int query_slot { get; internal set; default = 0; }
	public int acquire_slot { get; internal set; default = 1; }
	public int release_slot { get; internal set; default = 2; }
	public int get_slot { get; internal set; default = 3; }
	public int set_slot { get; internal set; default = 4; }
	public int scale_slot { get; internal set; default = 3; }
	public bool query_acquires { get; internal set; default = true; }
	public bool checked_context { get; internal set; default = true; }
	public bool windows_x64 { get; internal set; default = true; }
	public ComExportContract (string value_iid, string scale_iid) {
		value_identity = value_iid.ascii_down ();
		scale_identity = scale_iid.ascii_down ();
	}
	public static bool guid(string value) {
		if (value.length != 36 || value == "00000000-0000-0000-0000-000000000000" || value == "00000000-0000-0000-c000-000000000046") {
			return false;
		}
		for (int i = 0; i < value.length; i++) {
			if (i == 8 || i == 13 || i == 18 || i == 23) {
				if (value[i] != '-') {
					return false;
				}
			} else if (!(value[i] >= '0' && value[i] <= '9') && !(value[i] >= 'a' && value[i] <= 'f')) {
				return false;
			}
		}
		return true;
	}
	public bool valid() {
		return guid (value_iid) && guid (scale_iid) && value_iid != scale_iid && query_slot == 0 && acquire_slot == 1 && release_slot == 2 && get_slot == 3 && set_slot == 4 && scale_slot == 3 && query_acquires && checked_context && windows_x64;
	}
	public string identity() {
		return "com-windows-x64-v1;%s;%s;%d,%d,%d,%d,%d,%d;%d,%d,%d".printf (value_iid, scale_iid, query_slot, acquire_slot, release_slot, get_slot, set_slot, scale_slot, (int) query_acquires, (int) checked_context, (int) windows_x64);
	}
	public ComExportContract copy() {
		var result = new ComExportContract (value_iid, scale_iid);
		result.query_slot = query_slot;
		result.acquire_slot = acquire_slot;
		result.release_slot = release_slot;
		result.get_slot = get_slot;
		result.set_slot = set_slot;
		result.scale_slot = scale_slot;
		result.query_acquires = query_acquires;
		result.checked_context = checked_context;
		result.windows_x64 = windows_x64;
		return result;
	}
}
// Immutable declaration authority, independent of syntax, semantic symbols,
// IR graphs and foreign/native physical layout. Stages copy the value and
// compare it with the nominal type's admitted identity.
public class ForeignClassPolicy : Object {
	public ForeignApiContract? declared_api { get; private set; }
	private GenericArray<ForeignComExportBinding> com_bindings = new GenericArray<ForeignComExportBinding> ();
	public uint com_count { get { return com_bindings.length; } }
	public ForeignComExportBinding com_binding(uint index) {
		return com_bindings[index];
	}
	private bool com_names_valid() {
		var names = new HashTable<string, string> (str_hash, str_equal);
		foreach (var binding in com_bindings) {
			for (uint r = 0; r < binding.protocol.requirement_count; r++) {
				string name = binding.protocol.requirement (r).name, target = binding.api.member (binding.target (r)).native_key;
				if (names.contains (name) && names.lookup (name) != target) {
					return false;
				}
				names.insert (name, target);
			}
		}
		return true;
	}
	private bool gobject_members_valid() {
		if (gobject == null || declared_api == null) {
			return true;
		}
		var properties = new HashTable<string, bool> (str_hash, str_equal);
		var signals = new HashTable<string, bool> (str_hash, str_equal);
		for (uint m = 0; m < declared_api.member_count; m++) {
			var member = declared_api.member (m);
			if (member.kind != ForeignMemberKind.SIGNAL) {
				continue;
			}
			string name = member.name.replace ("_","-");
			if (member.personalities != GOBJECT || !(name[0] >= 'a' && name[0] <= 'z') && !(name[0] >= 'A' && name[0] <= 'Z') || name == "notify" || signals.contains (name)) {
				return false;
			}
			signals.insert (name,true);
			for (uint a = 0; a < member.parameter_count; a++) {
				var type = member.parameter (a).value_type;
				if (type.kind == ForeignValueKind.CALLBACK || type.kind == ForeignValueKind.COM_OBJECT) {
					return false;
				}
			}
		}
		for (uint m = 0; m < declared_api.member_count; m++) {
			var member = declared_api.member (m);
			if ((member.personalities & GOBJECT) == 0 || member.kind != ForeignMemberKind.GETTER) {
				continue;
			}
			if (!member.name.has_prefix ("get_") || member.name.length <= 4) {
				return false;
			}
			string name = member.name.substring (4).replace ("_","-");
			if (!(name[0] >= 'a' && name[0] <= 'z') && !(name[0] >= 'A' && name[0] <= 'Z') || properties.contains (name)) {
				return false;
			}
			properties.insert (name,true);
		}
		return true;
	}
	public static bool distinct_gobjects(GenericArray<ForeignClassPolicy> roots) {
		var types = new HashTable<string,bool> (str_hash,str_equal);
		var prefixes = new HashTable<string,bool> (str_hash,str_equal);
		foreach (var root in roots) {
			if (root.gobject == null) {
				continue;
			}
			string name = root.gobject.type_name,prefix = root.gobject.symbol_prefix ();
			if (types.contains (name) || prefixes.contains (prefix)) {
				return false;
			}
			types.insert (name,true);
			prefixes.insert (prefix,true);
		}
		return true;
	}
	private static ForeignComInterface? protocol_named(GenericArray<ForeignComInterface> protocols,string name) {
		foreach (var protocol in protocols) {
			if (protocol.name == name) {
				return protocol;
			}
		}
		return null;
	}
	private static bool com_channel_root_valid(ForeignChannel native_channel,ForeignChannel required,GenericArray<ForeignClassPolicy> roots,GenericArray<ForeignComInterface> protocols) {
		if (!ForeignComExportBinding.native_view (native_channel,required)) {
			return true;
		}
		var protocol = protocol_named (protocols,required.value_type.nominal_origin);
		if (protocol == null) {
			return false;
		}
		foreach (var root in roots) {
			var api = root.declared_api;
			if (api == null || api.native_origin != native_channel.value_type.nominal_origin || api.lifetime != ForeignLifetime.SHARED || !root.valid ()) {
				continue;
			}
			foreach (var binding in root.com_bindings) {
				for (var view = binding.protocol; view != null; view = view.parent) {
					if (view.identity () == protocol.identity ()) {
						return true;
					}
				}
			}
		}
		return false;
	}
	private static bool gobject_channel_root_valid(ForeignChannel channel,GenericArray<ForeignClassPolicy> roots) {
		if (channel.value_type.kind != ForeignValueKind.NATIVE_OBJECT) {
			return true;
		}
		foreach (var root in roots) {
			if (root.declared_api != null && root.native_name == channel.value_type.nominal_origin && root.declared_api.lifetime == ForeignLifetime.SHARED && root.gobject != null && root.gobject.declarations && root.valid ()) {
				return true;
			}
		}
		return false;
	}
	public static bool com_roots_valid(ForeignClassPolicy policy,GenericArray<ForeignClassPolicy> roots,GenericArray<ForeignComInterface> protocols) {
		if (!policy.valid () || !distinct_gobjects (roots)) {
			return false;
		}
		if (policy.gobject != null && policy.declared_api != null) {
			for (uint m = 0; m < policy.declared_api.member_count; m++) {
				var member = policy.declared_api.member (m);
				if ((member.personalities & GOBJECT) == 0) {
					continue;
				}
				if (!gobject_channel_root_valid (member.result,roots)) {
					return false;
				}
				for (uint a = 0; a < member.parameter_count; a++) {
					if (!gobject_channel_root_valid (member.parameter (a),roots)) {
						return false;
					}
				}
			}
		}
		foreach (var binding in policy.com_bindings) {
			var declared = protocol_named (protocols,binding.protocol.name);
			if (declared == null || declared.identity () != binding.protocol.identity ()) {
				return false;
			}
			for (uint r = 0; r < binding.protocol.requirement_count; r++) {
				var required = binding.protocol.requirement (r);
				var target = binding.api.member (binding.target (r));
				if (!com_channel_root_valid (target.result, required.result, roots, protocols)) {
					return false;
				}
				for (uint p = 0; p < required.parameter_count; p++) {
					if (!com_channel_root_valid (target.parameter (p), required.parameter (p), roots, protocols)) {
						return false;
					}
				}
			}
		}
		return true;
	}
	public const uint C = 1;
	public const uint COM = 2;
	public const uint GOBJECT = 4;
	public uint personalities { get; private set; }
	public uint active_personalities { get { return declared_api == null ? personalities : declared_api.active_personalities; } }
	public static string personality_names(uint mask) {
		string names = "";
		foreach (uint bit in new uint[] { C, COM, GOBJECT }) {
			if ((mask & bit) != 0) {
				names += (names == "" ? "" : ",") + (bit == C ? "c" : bit == COM ? "com" : "gobject");
			}
		}
		return names == "" ? "none" : names;
	}
	public bool active(uint personality) {
		return (active_personalities & personality) != 0;
	}
	public ComExportContract? com { get; internal set; }
	public GObjectExportContract? gobject { get; internal set; }
	private string native_identifier;
	private string external_prefix;
	private string property_identifier;
	public string native_name { get { return native_identifier; } }
	public string prefix { get { return external_prefix; } }
	public string property_name { get { return property_identifier; } }
	public int property_ordinal { get; private set; }
	public ForeignClassPolicy.declared (ForeignApiContract contract, GenericArray<ForeignComExportBinding>? bindings = null, GObjectExportContract? gobject = null) {
		declared_api = contract;
		native_identifier = contract.native_origin;
		external_prefix = contract.prefix;
		property_identifier = "";
		property_ordinal = -1;
		personalities = contract.declared_personalities;
		if (bindings != null) {
			foreach (var binding in bindings) {
				com_bindings.add (binding);
			}
		}
		this.gobject = gobject == null ? null : gobject.copy ();
	}
	public ForeignClassPolicy (string native_name, string prefix, string property_name, int property_ordinal, uint personalities = C, ComExportContract? com = null, GObjectExportContract? gobject = null) {
		this.native_identifier = native_name;
		this.external_prefix = prefix;
		this.property_identifier = property_name;
		this.property_ordinal = property_ordinal;
		this.personalities = personalities;
		this.com = com == null ? null : com.copy ();
		this.gobject = gobject == null ? null : gobject.copy ();
	}
	public static bool identifier(string name) {
		if (name.length == 0) {
			return false;
		}
		for (int i = 0; i < name.length; i++) {
			char c = name[i];
			if (c != '_' && !(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(i != 0 && c >= '0' && c <= '9')) {
				return false;
			}
		}
		return true;
	}
	public static bool nominal_identifier(string name) {
		foreach (string part in name.split (".")) {
			if (!identifier (part)) {
				return false;
			}
		}
		return true;
	}
	public bool valid() {
		if (declared_api != null) {
			var seen = new HashTable<string, bool> (str_hash, str_equal);
			foreach (var binding in com_bindings) {
				if (!binding.valid () || !binding.api.equal (declared_api) || seen.contains (binding.protocol.iid)) {
					return false;
				}
				seen.insert (binding.protocol.iid, true);
			}
			if (!com_names_valid () || !gobject_members_valid () || (com_count != 0) != ((personalities & COM) != 0)) {
				return false;
			}
			return declared_api.valid () && native_name == declared_api.native_origin && prefix == declared_api.prefix && personalities == declared_api.declared_personalities && property_ordinal == -1 && property_name == "" && com == null && ((personalities & GOBJECT) == 0 ? gobject == null : gobject != null && gobject.declarations && gobject.valid () && declared_api.lifetime == ForeignLifetime.SHARED);
		}
		return (personalities == C && com == null && gobject == null || personalities == (C | COM) && com != null && com.valid () && gobject == null || personalities == (C | GOBJECT) && com == null && gobject != null && gobject.valid () && gobject.symbol_prefix () == prefix && property_name == "value") && native_name != "" && identifier (prefix) && !prefix.has_prefix ("astra_") && identifier (property_name) && property_ordinal >= 0;
	}
	public string identity() {
		if (declared_api != null) {
			var text = new StringBuilder (declared_api.identity ());
			foreach (var binding in com_bindings) {
				text.append (binding.identity ());
			}
			if (gobject != null) {
				text.append (gobject.identity ());
			}
			return text.str;
		}
		return "%u;%d:%s;%d:%s;%d:%s;%d%s%s".printf (personalities, native_name.length, native_name, prefix.length, prefix, property_name.length, property_name, property_ordinal, com == null ? "" : ";" + com.identity (), gobject == null ? "" : ";" + gobject.identity ());
	}
	public ForeignClassPolicy copy() {
		return declared_api != null ? new ForeignClassPolicy.declared (declared_api, com_bindings, gobject) : new ForeignClassPolicy (native_name, prefix, property_name, property_ordinal, personalities, com, gobject);
	}
	public string dump() {
		if (declared_api != null) {
			return "(foreign-class CExport declarations-v1 name=%s native=%s lifetime=%s members=%u)".printf (prefix, native_name, declared_api.lifetime == ForeignLifetime.UNIQUE ? "unique" : "shared", declared_api.member_count);
		}
		return "(foreign-class CExport name=%s native=%s property=%s ordinal=%d native-strong-weak separate-wrapper constructing-thread-data%s%s)".printf (prefix, native_name, property_name, property_ordinal, com == null ? "" : " COMExport " + com.identity (), gobject == null ? "" : " " + gobject.identity ());
	}
	public static bool matches(ForeignClassPolicy? policy, string identity, string name) {
		return policy == null ? identity == "" : policy.valid () && policy.identity () == identity && policy.native_name == name;
	}
	public static bool reserved_symbol(string name) {
		return name.has_prefix ("astra_foreign14_");
	}
}
}
