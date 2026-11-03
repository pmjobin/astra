// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
// A finite declared C storage layout, independent of semantic or IR nodes.
// Natural scalar POD only; no pointers, ownership, bool or nested records.
public class PodRepresentation : Object {
	private string identifier;
	public string name { get { return identifier; } }
	public GenericArray<string> field_names { get; private set; default = new GenericArray<string> (); }
	public GenericArray<string> field_types { get; private set; default = new GenericArray<string> (); }
	public uint minimum_alignment { get; internal set; }
	private string member_list;
	private string selected_member;
	public string union_members { get { return member_list; } internal set { member_list = value; } }
	public string active_member { get { return selected_member; } internal set { selected_member = value; } }
	public bool tagged_union { get; internal set; }
	public int64 union_tag { get; internal set; }
	public bool is_union { get { return union_members != ""; } }
	private string origin;
	public string identity { get { return origin; } }
	public PodRepresentation (string name, string[] names, string[] types, uint alignment, string union_members = "", string active_member = "", bool tagged_union = false, int64 union_tag = 0) {
		this.union_members = union_members;
		this.active_member = active_member;
		this.tagged_union = tagged_union;
		this.union_tag = union_tag;
		identifier = name;
		minimum_alignment = alignment;
		foreach (string field in names) {
			field_names.add (field);
		}
		foreach (string type in types) {
			field_types.add (type);
		}
		origin = canonical ();
	}

	private PodRepresentation.snapshot (PodRepresentation other) {
		union_members = other.union_members;
		active_member = other.active_member;
		tagged_union = other.tagged_union;
		union_tag = other.union_tag;
		identifier = other.name;
		minimum_alignment = other.minimum_alignment;
		origin = other.origin;
		foreach (string field in other.field_names) {
			field_names.add (field);
		}
		foreach (string type in other.field_types) {
			field_types.add (type);
		}
	}
	public PodRepresentation copy() {
		return new PodRepresentation.snapshot (this);
	}

	private string canonical() {
		var text = new StringBuilder (name + ";%u;".printf (minimum_alignment));
		if (is_union || active_member != "" || tagged_union || union_tag != 0) {
			text.append (("union;%d:%s;%d:%s;%s;%" + int64.FORMAT + ";").printf (union_members.length, union_members, active_member.length, active_member, tagged_union.to_string (), union_tag));
		}
		foreach (string field in field_names) {
			text.append ("%d:%s;".printf (field.length, field));
		}
		foreach (string type in field_types) {
			text.append ("%d:%s;".printf (type.length, type));
		}
		return Checksum.compute_for_string (ChecksumType.SHA256, text.str);
	}

	public static uint width(string type) {
		switch (type) {
		case "i8":
		case "u8":
			return 1;
		case "i16":
		case "u16":
			return 2;
		case "int":
		case "u32":
		case "f32":
			return 4;
		case "i64":
		case "u64":
		case "isize":
		case "usize":
		case "f64":
			return 8;
		default:
			return 0;
		}
	}

	public uint alignment() {
		uint value = 1;
		foreach (string type in field_types) {
			value = uint.max (value, width (type));
		}
		return value;
	}

	public uint offset(uint ordinal) {
		uint position = 0;
		for (uint i = 0; i <= ordinal; i++) {
			uint bytes = width (field_types[i]);
			if (bytes == 0) {
				return uint.MAX;
			}
			position = (position + bytes - 1) & ~(bytes - 1);
			if (i == ordinal) {
				return position;
			}
			position += bytes;
		}
		return uint.MAX;
	}

	public uint size() {
		if (field_types.length == 0) {
			return 0;
		}
		uint end = offset (field_types.length - 1) + width (field_types[field_types.length - 1]);
		uint align = alignment ();
		return (end + align - 1) & ~(align - 1);
	}

	public bool valid() {
		if (origin != canonical () || name == "" || field_names.length == 0 || field_names.length > 32 || field_names.length != field_types.length || !AllocationPolicy.power_of_two (minimum_alignment) || minimum_alignment > alignment ()) {
			return false;
		}
		var names = new HashTable<string, bool> (str_hash, str_equal);
		for (int i = 0; i < field_names.length; i++) {
			if (field_names[i] == "" || names.contains (field_names[i]) || width (field_types[i]) == 0) {
				return false;
			}
			names.insert (field_names[i], true);
		}
		if (is_union) {
			int selected = tagged_union ? 1 : 0;
			if (field_names.length != selected + 1 || field_names[selected] != active_member || tagged_union && (field_names[0] != "tag" || field_types[0] != "i64" || union_tag < 0 || union_tag > int.MAX) || !tagged_union && union_tag != 0) {
				return false;
			}
			var members = union_members.split (",");
			var seen = new HashTable<string, bool> (str_hash, str_equal);
			bool found = false;
			if (members.length < 2 || members.length > 8) {
				return false;
			}
			foreach (string member in members) {
				var parts = member.split (":");
				if (parts.length != 2 || !member_identifier (parts[0]) || seen.contains (parts[0]) || parts[1] != "i64" && parts[1] != "u64") {
					return false;
				}
				seen.insert (parts[0], true);
				if (parts[0] == active_member) {
					found = parts[1] == field_types[selected];
				}
			}
			if (!found) {
				return false;
			}
		} else if (active_member != "" || tagged_union || union_tag != 0) {
			return false;
		}
		return true;
	}

	private static bool member_identifier(string name) {
		if (name == "") {
			return false;
		}
		for (int i = 0; i < name.length; i++) {
			char c = name[i];
			if (c != '_' && !(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(i > 0 && c >= '0' && c <= '9')) {
				return false;
			}
		}
		return true;
	}

	public bool matches(string identity, string name, string[] names, string[] types) {
		if (!valid () || origin != identity || this.name != name || names.length != field_names.length || types.length != field_types.length) {
			return false;
		}
		for (int i = 0; i < names.length; i++) {
			if (names[i] != field_names[i] || types[i] != field_types[i]) {
				return false;
			}
		}
		return true;
	}

	public string dump() {
		if (is_union) {
			return ("(repr %s members=\"%s\" active=\"%s\" tag=%" + int64.FORMAT + " size=%u alignment=%u identity=%s)").printf (tagged_union ? "C-tagged-union" : "C-union", union_members, active_member, union_tag, size (), alignment (), identity);
		}
		return "(repr C natural-lp64 size=%u alignment=%u identity=%s)".printf (size (), alignment (), identity);
	}

}
}
