// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
public enum ForeignValueKind {
	VOID, I32, U32, I64, U64, F32, F64, BOOL,
	BYTES, TEXT, RECORD, NATIVE_OBJECT, COM_OBJECT, GOBJECT, CALLBACK;
}

public enum ForeignDirection {
	IN, OUT, INOUT
}

public enum ForeignTransfer {
	COPY, BORROW, OWN
}

public enum ForeignMemberKind {
	CONSTRUCTOR, METHOD, GETTER, SETTER, SIGNAL
}

public enum ForeignLifetime{
	UNIQUE,SHARED
}

public enum ForeignTextEncoding{
	NONE,BYTES,UTF8_COUNTED,UTF8_NUL
}

// Logical contracts contain no syntax, stage graph, executable body, physical
// pointer, or target layout. Collections are copied on admission and expose
// only immutable elements. Detached stages can retain this authority safely.
public class ForeignRecordField: Object {
	private string name_identifier;
	public string name { get { return name_identifier; } }
	public ForeignValueKind kind { get; private set; }
	public ForeignRecordField (string name,ForeignValueKind kind) {
		name_identifier = name;
		this.kind = kind;
	}

	public bool valid() {
		return ForeignClassPolicy.identifier (name) && kind >= ForeignValueKind.I32 && kind <= ForeignValueKind.BOOL;
	}

	public bool equal(ForeignRecordField other) {
		return name == other.name && kind == other.kind;
	}

	public string identity() {
		return "%d:%s:%u;".printf (name.length,name,(uint) kind);
	}

}

public class ForeignValueType: Object {
	public ForeignValueKind kind { get; private set; }
	private string nominal_identifier;
	public string nominal_origin { get { return nominal_identifier; } }
	private GenericArray<ForeignRecordField> fields = new GenericArray<ForeignRecordField> ();
	private GenericArray<ForeignValueType> callback_parameters = new GenericArray<ForeignValueType> ();
	public ForeignValueType? callback_result { get; private set; }
	public uint field_count { get { return fields.length; } }
	public ForeignRecordField field(uint index) {
		return fields[index];
	}

	public uint callback_parameter_count { get { return callback_parameters.length; } }
	public ForeignValueType callback_parameter(uint index) {
		return callback_parameters[index];
	}

	public ForeignValueType (ForeignValueKind kind,string nominal_origin = "",
	                         GenericArray<ForeignRecordField>? fields = null,
	                         GenericArray<ForeignValueType>? callback_parameters = null,ForeignValueType? callback_result = null) {
		this.kind = kind;
		nominal_identifier = nominal_origin;
		this.callback_result = callback_result;
		if (fields != null) {
			foreach (var field in fields) {
				this.fields.add (field);
			}
		}
		if (callback_parameters != null) {
			foreach (var parameter in callback_parameters) {
				this.callback_parameters.add (parameter);
			}
		}
	}

	public bool scalar() {
		return kind >= ForeignValueKind.I32 && kind <= ForeignValueKind.BOOL;
	}

	public bool object_handle() {
		return kind >= ForeignValueKind.NATIVE_OBJECT && kind <= ForeignValueKind.GOBJECT;
	}

	public bool valid(int remaining = 32) {
		if (kind < ForeignValueKind.VOID || kind > ForeignValueKind.CALLBACK || remaining <= 0) {
			return false;
		}
		if (kind == ForeignValueKind.RECORD) {
			if (nominal_origin == "" || fields.length == 0 || fields.length > 1024) {
				return false;
			}
			var names = new HashTable<string,bool> (str_hash,str_equal);
			foreach (var field in fields) {
				if (!field.valid () || names.contains (field.name)) {
					return false;
				}
				names.insert (field.name,true);
			}
		} else if (fields.length != 0 || (object_handle () ? nominal_origin == "" : nominal_origin != "")) {
			return false;
		}
		if (kind == ForeignValueKind.CALLBACK) {
			if (callback_result == null || !callback_result.valid (remaining - 1) || callback_parameters.length > 256) {
				return false;
			}
			foreach (var parameter in callback_parameters) {
				if (parameter.kind == ForeignValueKind.VOID || !parameter.valid (remaining - 1)) {
					return false;
				}
			}
		} else if (callback_result != null || callback_parameters.length != 0) {
			return false;
		}
		return true;
	}

	public bool equal(ForeignValueType other) {
		if (kind != other.kind || nominal_origin != other.nominal_origin || fields.length != other.fields.length || callback_parameters.length != other.callback_parameters.length || (callback_result == null) != (other.callback_result == null)) {
			return false;
		}
		for (uint i = 0; i < fields.length; i++) {
			if (!fields[i].equal (other.fields[i])) {
				return false;
			}
		}
		for (uint i = 0; i < callback_parameters.length; i++) {
			if (!callback_parameters[i].equal (other.callback_parameters[i])) {
				return false;
			}
		}
		return callback_result == null || callback_result.equal (other.callback_result);
	}

	public string identity() {
		var text = new StringBuilder ("%u:%d:%s:%u:".printf ((uint) kind,nominal_origin.length,nominal_origin,fields.length));
		foreach (var field in fields) {
			text.append (field.identity ());
		}
		text.append_printf ("%u:",callback_parameters.length);
		foreach (var parameter in callback_parameters) {
			text.append (parameter.identity ());
		}
		text.append (callback_result == null ? "-;" : callback_result.identity ());
		return text.str;
	}

}

// Windows COM storage is separate from both native storage and C99 storage.
// In particular BOOL fields occupy four bytes even inside copied PODs.
public class ForeignComRecordLayout: Object {
	public ForeignValueType value_type { get; private set; }
	public ForeignComRecordLayout (ForeignValueType type) {
		value_type = type;
	}

	public static uint scalar_size(ForeignValueKind kind) {
		if (kind == ForeignValueKind.I64 || kind == ForeignValueKind.U64 || kind == ForeignValueKind.F64) {
			return 8;
		}
		return kind >= ForeignValueKind.I32 && kind <= ForeignValueKind.BOOL ? 4 : 0;
	}

	public bool valid() {
		return value_type.kind == ForeignValueKind.RECORD && value_type.valid ();
	}

	public uint alignment {
		get {
			uint result = 1;
			for (uint f = 0;
			     f < value_type.field_count;
			     f++) {
				result = uint.max (result,scalar_size (value_type.field (f).kind));
			}
			return result;
		}
	}
	public uint offset(uint field) {
		uint position = 0;
		for (uint f = 0; f <= field && f < value_type.field_count; f++) {
			uint width = scalar_size (value_type.field (f).kind);
			if (width == 0) {
				return uint.MAX;
			}
			position = (position + width - 1) / width * width;
			if (f == field) {
				return position;
			}
			position += width;
		}
		return uint.MAX;
	}

	public uint size {
		get {
			if (!valid ()) {
				return 0;
			}
			uint last = value_type.field_count - 1;
			uint end = offset (last) + scalar_size (value_type.field (last).kind);
			return (end + alignment - 1) / alignment * alignment;
		}
	}
	public string identity() {
		var text = new StringBuilder ("windows-x64;COM-POD;BOOL32;" + value_type.identity ());
		text.append_printf ("%u:%u;",size,alignment);
		for (uint f = 0; f < value_type.field_count; f++) {
			text.append_printf ("%u;",offset (f));
		}
		return text.str;
	}

}

// GLib boxed layout is a separate physical plan from COM and C99.
public class ForeignGObjectRecordLayout: Object {
	public ForeignValueType value_type { get; private set; }
	public ForeignGObjectRecordLayout (ForeignValueType type) {
		value_type = type;
	}

	public static uint scalar_size(ForeignValueKind kind) {
		if (kind == ForeignValueKind.I64 || kind == ForeignValueKind.U64 || kind == ForeignValueKind.F64) {
			return 8;
		}
		return kind >= ForeignValueKind.I32 && kind <= ForeignValueKind.BOOL ? 4 : 0;
	}

	public bool valid() {
		return value_type.kind == ForeignValueKind.RECORD && value_type.valid ();
	}

	public uint alignment {
		get {
			uint result = 1;
			for (uint f = 0;
			     f < value_type.field_count;
			     f++) {
				result = uint.max (result,scalar_size (value_type.field (f).kind));
			}
			return result;
		}
	}
	public uint offset(uint field) {
		uint position = 0;
		for (uint f = 0; f <= field && f < value_type.field_count; f++) {
			uint width = scalar_size (value_type.field (f).kind);
			if (width == 0) {
				return uint.MAX;
			}
			position = (position + width - 1) / width * width;
			if (f == field) {
				return position;
			}
			position += width;
		}
		return uint.MAX;
	}

	public uint size {
		get {
			if (!valid ()) {
				return 0;
			}
			uint last = value_type.field_count - 1;
			uint end = offset (last) + scalar_size (value_type.field (last).kind);
			return (end + alignment - 1) / alignment * alignment;
		}
	}
	public string identity() {
		var text = new StringBuilder ("linux-x64;GObject-boxed-POD;gboolean32;" + value_type.identity ());
		text.append_printf ("%u:%u;",size,alignment);
		for (uint f = 0; f < value_type.field_count; f++) {
			text.append_printf ("%u;",offset (f));
		}
		return text.str;
	}

}

public class ForeignChannel: Object {
	private string name_identifier;
	public string name { get { return name_identifier; } }
	public ForeignValueType value_type { get; private set; }
	public ForeignDirection direction { get; private set; }
	public ForeignTransfer transfer { get; private set; }
	public bool nullable { get; private set; }
	public ForeignTextEncoding encoding { get; private set; }
	public int length_index { get; private set; }
	public int capacity_index { get; private set; }
	public int produced_index { get; private set; }
	private string release_identifier;
	public string release_symbol { get { return release_identifier; } }
	public bool call_scoped { get; private set; }
	public int closure_index { get; private set; }
	public int destroy_index { get; private set; }
	public bool intrinsic_length { get; private set; }
	public bool produced_by_result { get; private set; }
	public bool native_nonnull { get; private set; }
	public bool by_reference { get; private set; }
	public bool intrinsic_context { get; private set; }

	public ForeignChannel (string name,ForeignValueType value_type,
	                       ForeignDirection direction = ForeignDirection.IN,ForeignTransfer transfer = ForeignTransfer.COPY,
	                       bool nullable = false,ForeignTextEncoding encoding = ForeignTextEncoding.NONE,
	                       int length_index = -1,int capacity_index = -1,int produced_index = -1,
	                       string release_symbol = "",bool call_scoped = false,int closure_index = -1,int destroy_index = -1,
	                       bool intrinsic_length = false,bool produced_by_result = false,bool native_nonnull = false,bool by_reference = false,bool intrinsic_context = false) {
		name_identifier = name;
		this.value_type = value_type;
		this.direction = direction;
		this.transfer = transfer;
		this.nullable = nullable;
		this.encoding = encoding;
		this.length_index = length_index;
		this.capacity_index = capacity_index;
		this.produced_index = produced_index;
		release_identifier = release_symbol;
		this.call_scoped = call_scoped;
		this.closure_index = closure_index;
		this.destroy_index = destroy_index;
		this.intrinsic_length = intrinsic_length;
		this.produced_by_result = produced_by_result;
		this.native_nonnull = native_nonnull;
		this.by_reference = by_reference;
		this.intrinsic_context = intrinsic_context;
	}

	public bool valid() {
		if (!ForeignClassPolicy.identifier (name) || !value_type.valid () || direction < ForeignDirection.IN || direction > ForeignDirection.INOUT || transfer < ForeignTransfer.COPY || transfer > ForeignTransfer.OWN) {
			return false;
		}
		var kind = value_type.kind;
		if (intrinsic_context && kind != ForeignValueKind.CALLBACK) {
			return false;
		}
		if (by_reference) {
			return value_type.scalar () && transfer == ForeignTransfer.COPY && !nullable && encoding == ForeignTextEncoding.NONE && length_index == -1 && capacity_index == -1 && produced_index == -1 && release_symbol == "" && call_scoped && closure_index == -1 && destroy_index == -1 && !intrinsic_length && !produced_by_result && !native_nonnull;
		}
		if (kind == ForeignValueKind.VOID || value_type.scalar () || kind == ForeignValueKind.RECORD) {
			return transfer == ForeignTransfer.COPY && !nullable && encoding == ForeignTextEncoding.NONE && length_index == -1 && capacity_index == -1 && produced_index == -1 && release_symbol == "" && !call_scoped && closure_index == -1 && destroy_index == -1 && !intrinsic_length && !produced_by_result && !native_nonnull;
		}
		if (transfer == ForeignTransfer.COPY || (transfer == ForeignTransfer.OWN ? !ForeignClassPolicy.identifier (release_symbol) : release_symbol != "")) {
			return false;
		}
		if (kind == ForeignValueKind.BYTES || kind == ForeignValueKind.TEXT) {
			if (native_nonnull) {
				return false;
			}
			if (kind == ForeignValueKind.BYTES ? encoding != ForeignTextEncoding.BYTES : encoding != ForeignTextEncoding.UTF8_COUNTED && encoding != ForeignTextEncoding.UTF8_NUL) {
				return false;
			}
			if (encoding == ForeignTextEncoding.UTF8_NUL ? length_index != -1 || intrinsic_length : !intrinsic_length && length_index < 0 && (direction == ForeignDirection.IN || capacity_index < 0)) {
				return false;
			}
			if (intrinsic_length && (length_index != -1 || capacity_index != -1)) {
				return false;
			}
			if (direction == ForeignDirection.IN && (capacity_index != -1 || produced_index != -1 || produced_by_result)) {
				return false;
			}
			if (direction != ForeignDirection.IN && transfer == ForeignTransfer.BORROW && ((!intrinsic_length && capacity_index < 0) || produced_index < 0 && !produced_by_result)) {
				return false;
			}
			if (produced_by_result && produced_index != -1) {
				return false;
			}
			return closure_index == -1 && destroy_index == -1 && (transfer != ForeignTransfer.BORROW || call_scoped);
		}
		if (encoding != ForeignTextEncoding.NONE || length_index != -1 || capacity_index != -1 || produced_index != -1 || intrinsic_length || produced_by_result) {
			return false;
		}
		if (kind == ForeignValueKind.CALLBACK) {
			return !native_nonnull && direction == ForeignDirection.IN && transfer == ForeignTransfer.BORROW && call_scoped && (intrinsic_context ? closure_index == -1 : closure_index >= 0) && destroy_index == -1;
		}
		return value_type.object_handle () && !(native_nonnull && nullable) && closure_index == -1 && destroy_index == -1 && (transfer == ForeignTransfer.BORROW ? call_scoped : !call_scoped);
	}

	public bool equal(ForeignChannel other) {
		return name == other.name && same_transport (other);
	}

	public bool same_transport(ForeignChannel other,bool exact_release = true,bool exact_value = true) {
		return (!exact_value || value_type.equal (other.value_type)) && direction == other.direction && transfer == other.transfer && nullable == other.nullable && encoding == other.encoding && length_index == other.length_index && capacity_index == other.capacity_index && produced_index == other.produced_index && (!exact_release || release_symbol == other.release_symbol) && call_scoped == other.call_scoped && closure_index == other.closure_index && destroy_index == other.destroy_index && intrinsic_length == other.intrinsic_length && produced_by_result == other.produced_by_result && native_nonnull == other.native_nonnull && by_reference == other.by_reference && intrinsic_context == other.intrinsic_context;
	}

	public string identity() {
		return "%d:%s:%s:%u:%u:%d:%u:%d:%d:%d:%d:%s:%d:%d:%d:%d:%d:%d:%d;".printf (name.length,name,value_type.identity (),(uint) direction,(uint) transfer,(int) nullable,(uint) encoding,length_index,capacity_index,produced_index,release_symbol.length,release_symbol,(int) call_scoped,closure_index,destroy_index,(int) intrinsic_length,(int) produced_by_result,(int) native_nonnull,(int) by_reference) + (intrinsic_context ? "context=intrinsic;" : "");
	}

}

public class ForeignErrorCase: Object {
	private string identifier;
	public string native_origin { get { return identifier; } }
	public int32 status { get; private set; }
	public ForeignErrorCase (string native_origin,int32 status) {
		identifier = native_origin;
		this.status = status;
	}

	public string c_identifier() {
		return native_origin.contains (".") ? "qualified_" + Checksum.compute_for_string (ChecksumType.SHA256,native_origin) : native_origin;
	}

	public string identity() {
		return "%d:%s:%d;".printf (native_origin.length,native_origin,status);
	}

}
public class ForeignErrorMap: Object {
	public int32 domain { get; private set; }
	private GenericArray<ForeignErrorCase> cases = new GenericArray<ForeignErrorCase> ();
	public uint case_count { get { return cases.length; } }
	public ForeignErrorCase at(uint index) {
		return cases[index];
	}

	public ForeignErrorMap (int32 domain,GenericArray<ForeignErrorCase> cases) {
		this.domain = domain;
		foreach (var entry in cases) {
			this.cases.add (entry);
		}
	}

	public bool valid(string bound) {
		if (domain <= 0 || cases.length == 0 || cases.length > 256 || cases[cases.length - 1].native_origin != bound) {
			return false;
		}
		var names = new HashTable<string,bool> (str_hash,str_equal);
		var statuses = new HashTable<int,bool> (direct_hash,direct_equal);
		foreach (var entry in cases) {
			if (!ForeignClassPolicy.nominal_identifier (entry.native_origin) || entry.status >= 0 || names.contains (entry.native_origin) || statuses.contains (entry.status)) {
				return false;
			}
			names.insert (entry.native_origin,true);
			statuses.insert (entry.status,true);
		}
		return true;
	}

	public string identity() {
		var text = new StringBuilder ("%d:%u:".printf (domain,cases.length));
		foreach (var entry in cases) {
			text.append (entry.identity ());
		}
		return text.str;
	}

}
public class ForeignMemberContract: Object {
	public ForeignMemberKind kind { get; private set; }
	private string name_identifier;
	public string name { get { return name_identifier; } }
	private string binding_identifier;
	public string native_key { get { return binding_identifier; } }
	public ForeignChannel result { get; private set; }
	private string error_identifier;
	public string error_origin { get { return error_identifier; } }
	public uint personalities { get; private set; }
	public int native_member_ordinal { get; private set; }
	public ForeignErrorMap? error_map { get; private set; }
	public int32 null_status { get; private set; }
	private GenericArray<ForeignChannel> parameters = new GenericArray<ForeignChannel> ();
	public uint parameter_count { get { return parameters.length; } }
	public ForeignChannel parameter(uint index) {
		return parameters[index];
	}

	public ForeignMemberContract (ForeignMemberKind kind,string name,string native_key,
	                              GenericArray<ForeignChannel> parameters,ForeignChannel result,string error_origin = "",uint personalities = ForeignClassPolicy.C,int native_member_ordinal = -1,ForeignErrorMap? error_map = null,int32 null_status = 0) {
		this.kind = kind;
		name_identifier = name;
		binding_identifier = native_key;
		this.result = result;
		error_identifier = error_origin;
		this.personalities = personalities;
		this.native_member_ordinal = native_member_ordinal;
		this.error_map = error_map;
		this.null_status = null_status;
		foreach (var parameter in parameters) {
			this.parameters.add (parameter);
		}
	}

	private bool count(int index,ForeignDirection direction) {
		return index >= 0 && index < parameters.length && parameters[index].value_type.kind == ForeignValueKind.I32 && parameters[index].direction == direction && parameters[index].transfer == ForeignTransfer.COPY && parameters[index].by_reference == (direction == ForeignDirection.OUT);
	}

	private bool links(ForeignChannel channel,int ordinal) {
		if (channel.produced_by_result && (result.value_type.kind != ForeignValueKind.I32 || result.transfer != ForeignTransfer.COPY || ordinal < 0)) {
			return false;
		}
		if (channel.length_index == ordinal || channel.capacity_index == ordinal || channel.produced_index == ordinal || channel.closure_index == ordinal) {
			return false;
		}
		if (channel.length_index >= 0 && !count (channel.length_index,channel.direction == ForeignDirection.IN ? ForeignDirection.IN : ForeignDirection.OUT)) {
			return false;
		}
		if (channel.capacity_index >= 0 && !count (channel.capacity_index,ForeignDirection.IN)) {
			return false;
		}
		if (channel.produced_index >= 0 && !count (channel.produced_index,ForeignDirection.OUT)) {
			return false;
		}
		if (channel.closure_index >= 0 && (channel.closure_index >= parameters.length || !parameters[channel.closure_index].value_type.object_handle () || parameters[channel.closure_index].direction != ForeignDirection.IN || parameters[channel.closure_index].transfer != ForeignTransfer.BORROW || !parameters[channel.closure_index].call_scoped)) {
			return false;
		}
		return true;
	}

	public bool valid() {
		if (error_origin == "" ? error_map != null : error_map == null || !error_map.valid (error_origin)) {
			return false;
		}
		if (result.by_reference) {
			return false;
		}
		if (null_status < 0 || null_status != 0 && (kind == ForeignMemberKind.CONSTRUCTOR || !result.value_type.object_handle () || !result.nullable || result.transfer != ForeignTransfer.OWN)) {
			return false;
		}
		if (kind < ForeignMemberKind.CONSTRUCTOR || kind > ForeignMemberKind.SIGNAL || !ForeignClassPolicy.identifier (name) || native_key == "" || parameters.length > 256 || !result.valid () || result.direction != ForeignDirection.OUT || !links (result,-2) || personalities == 0 || (personalities & ~7U) != 0) {
			return false;
		}
		if (kind == ForeignMemberKind.SIGNAL && (result.value_type.kind != ForeignValueKind.VOID || error_origin != "")) {
			return false;
		}
		if (kind == ForeignMemberKind.GETTER && (parameters.length != 0 || result.value_type.kind == ForeignValueKind.VOID) || kind == ForeignMemberKind.SETTER && (parameters.length != 1 || result.value_type.kind != ForeignValueKind.VOID)) {
			return false;
		}
		var names = new HashTable<string,bool> (str_hash,str_equal);
		for (int p = 0; p < parameters.length; p++) {
			var parameter = parameters[p];
			if (!parameter.valid () || parameter.value_type.kind == ForeignValueKind.VOID || names.contains (parameter.name) || !links (parameter,p)) {
				return false;
			}
			if (kind == ForeignMemberKind.SIGNAL && (parameter.direction != ForeignDirection.IN || parameter.transfer == ForeignTransfer.OWN)) {
				return false;
			}
			names.insert (parameter.name,true);
		}
		return true;
	}

	public bool equal(ForeignMemberContract other) {
		if (kind != other.kind || name != other.name || native_key != other.native_key || native_member_ordinal != other.native_member_ordinal || !result.equal (other.result) || error_origin != other.error_origin || (error_map == null ? other.error_map != null : other.error_map == null || error_map.identity () != other.error_map.identity ()) || null_status != other.null_status || personalities != other.personalities || parameters.length != other.parameters.length) {
			return false;
		}
		for (uint p = 0; p < parameters.length; p++) {
			if (!parameters[p].equal (other.parameters[p])) {
				return false;
			}
		}
		return true;
	}

	public bool same_signature(ForeignMemberContract other) {
		if (kind != other.kind || !result.same_transport (other.result) || error_origin != other.error_origin || (error_map == null ? other.error_map != null : other.error_map == null || error_map.identity () != other.error_map.identity ()) || null_status != other.null_status || parameters.length != other.parameters.length) {
			return false;
		}
		for (uint p = 0; p < parameters.length; p++) {
			if (!parameters[p].same_transport (other.parameters[p])) {
				return false;
			}
		}
		return true;
	}

	public string identity() {
		var text = new StringBuilder ("%u:%d:%s:%d:%s:%d:%u:%d:%s:%u:".printf ((uint) kind,name.length,name,native_key.length,native_key,native_member_ordinal,personalities,error_origin.length,error_origin,parameters.length));
		foreach (var parameter in parameters) {
			text.append (parameter.identity ());
		}
		text.append (result.identity ());
		text.append_printf ("%d:%s",null_status,error_map == null ? "-" : error_map.identity ());
		return text.str;
	}

}

public class ForeignApiContract: Object {
	private string native_identifier;
	public string native_origin { get { return native_identifier; } }
	private string prefix_identifier;
	public string prefix { get { return prefix_identifier; } }
	public ForeignLifetime lifetime { get; private set; }
	public uint declared_personalities { get; private set; }
	public int personality_selection { get; private set; }
	public uint active_personalities { get { return personality_selection < 0 ? declared_personalities : declared_personalities & (uint) personality_selection; } }
	private GenericArray<ForeignMemberContract> members = new GenericArray<ForeignMemberContract> ();
	public uint member_count { get { return members.length; } }
	public ForeignMemberContract member(uint index) {
		return members[index];
	}

	public ForeignApiContract (string native_origin,string prefix,ForeignLifetime lifetime,
	                           uint declared_personalities,GenericArray<ForeignMemberContract> members,int personality_selection = -1) {
		this.personality_selection = personality_selection;
		native_identifier = native_origin;
		prefix_identifier = prefix;
		this.lifetime = lifetime;
		this.declared_personalities = declared_personalities;
		foreach (var member in members) {
			this.members.add (member);
		}
	}

	public bool valid() {
		if (native_origin == "" || !ForeignClassPolicy.identifier (prefix) || prefix.has_prefix ("astra_") || lifetime < ForeignLifetime.UNIQUE || lifetime > ForeignLifetime.SHARED || declared_personalities == 0 || (declared_personalities & ~7U) != 0 || personality_selection < -1 || personality_selection > 7 || members.length > 4096) {
			return false;
		}
		if (lifetime == ForeignLifetime.UNIQUE && declared_personalities != ForeignClassPolicy.C) {
			return false;
		}
		var names = new HashTable<string,bool> (str_hash,str_equal);
		bool bytes_release = false;
		bool text_release = false;
		foreach (var member in members) {
			bytes_release |= member.result.value_type.kind == ForeignValueKind.BYTES && member.result.transfer == ForeignTransfer.OWN;
		}
		foreach (var member in members) {
			text_release |= member.result.value_type.kind == ForeignValueKind.TEXT && member.result.transfer == ForeignTransfer.OWN;
		}
		foreach (var member in members) {
			if (bytes_release && member.name == "bytes_release" || text_release && member.name == "text_release") {
				return false;
			}
			if (member.name == "root_identity" || (lifetime == ForeignLifetime.UNIQUE ? member.name == "destroy" : member.name == "acquire" && !(declared_personalities == ForeignClassPolicy.COM && member.kind == ForeignMemberKind.CONSTRUCTOR) || member.name == "release" || member.name == "weak" || member.name == "weak_clone" || member.name == "weak_upgrade" || member.name == "weak_release")) {
				return false;
			}
			if (!member.valid () || (member.personalities & declared_personalities) != member.personalities || names.contains (member.name)) {
				return false;
			}
			names.insert (member.name,true);
		}
		return true;
	}

	public bool equal(ForeignApiContract other) {
		if (native_origin != other.native_origin || prefix != other.prefix || lifetime != other.lifetime || declared_personalities != other.declared_personalities || personality_selection != other.personality_selection || members.length != other.members.length) {
			return false;
		}
		for (uint i = 0; i < members.length; i++) {
			if (!members[i].equal (other.members[i])) {
				return false;
			}
		}
		return true;
	}

	public string identity() {
		var text = new StringBuilder ("declarations-v1;%d:%s:%d:%s:%u:%u:%u:".printf (native_origin.length,native_origin,prefix.length,prefix,(uint) lifetime,declared_personalities,members.length));
		if (personality_selection >= 0) {
			text.append_printf ("selected=%d;active=%u;",personality_selection,active_personalities);
		}
		foreach (var member in members) {
			text.append (member.identity ());
		}
		return text.str;
	}

}
// One declared COM protocol, independent of an imported owner or an exported
// native Class. IUnknown is the implicit root; inherited requirements retain
// their original declaration and physical slot. No implementation is stored.
public class ForeignComInterface: Object {
	private string name_identifier;
	private string prefix_identifier;
	private string iid_identifier;
	public string name { get { return name_identifier; } }
	public string prefix { get { return prefix_identifier; } }
	public string iid { get { return iid_identifier; } }
	public ForeignComInterface? parent { get; private set; }
	private GenericArray<ForeignMemberContract> declared_members = new GenericArray<ForeignMemberContract> ();
	private string[] declared_native_names;
	public uint own_count { get { return declared_members.length; } }
	public uint inherited_count { get { return parent == null ? 0 : parent.requirement_count; } }
	public uint requirement_count { get { return inherited_count + own_count; } }
	public uint query_slot { get { return 0; } }
	public uint acquire_slot { get { return 1; } }
	public uint release_slot { get { return 2; } }
	public uint bool_bits { get { return 32; } }
	public uint pointer_bits { get { return 64; } }
	public uint status_bits { get { return 32; } }
	public uint slot(uint requirement) {
		return 3 + requirement;
	}

	public ForeignMemberContract requirement(uint index) {
		return index < inherited_count? parent.requirement(index) : declared_members[index - inherited_count];
	}

	public string native_name(uint index) {
		return index < inherited_count? parent.native_name(index) : declared_native_names[index - inherited_count];
	}

	public ForeignComInterface (string name,string prefix,string iid,GenericArray<ForeignMemberContract> members,string[] native_names,ForeignComInterface? parent = null) {
		name_identifier = name;
		prefix_identifier = prefix;
		iid_identifier = iid.ascii_down ();
		this.parent = parent;
		declared_native_names = native_names.copy ();
		foreach (var member in members) {
			declared_members.add (member);
		}
	}

	public bool valid(uint remaining = 32) {
		if (remaining == 0 || !ForeignClassPolicy.identifier (name) || !ForeignClassPolicy.identifier (prefix) || prefix.has_prefix ("astra_") || !ComExportContract.guid (iid) || declared_members.length != declared_native_names.length || declared_members.length > 4096 || parent != null && !parent.valid (remaining - 1)) {
			return false;
		}
		if (requirement_count == 0 || requirement_count > 4096) {
			return false;
		}
		for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
			if (ancestor.name == name || ancestor.prefix == prefix || ancestor.iid == iid) {
				return false;
			}
		}
		var names = new HashTable<string,bool> (str_hash,str_equal);
		for (uint index = 0; index < requirement_count; index++) {
			var member = requirement (index);
			if (!member.valid () || member.kind == ForeignMemberKind.CONSTRUCTOR || member.kind == ForeignMemberKind.SIGNAL || member.personalities != ForeignClassPolicy.COM || !ForeignClassPolicy.identifier (native_name (index)) || member.name == "QueryInterface" || member.name == "AddRef" || member.name == "Release" || names.contains (member.name)) {
				return false;
			}
			names.insert (member.name,true);
		}
		return true;
	}

	public string identity() {
		var text = new StringBuilder ("COMImport;declarations-v1;windows-x64;IUnknown=0,1,2;BOOL32;HRESULT32;%d:%s;%d:%s;%s;%s;%u:".printf (name.length,name,prefix.length,prefix,iid,parent == null ? "IUnknown" : parent.identity (),own_count));
		for (uint index = 0; index < own_count; index++) {
			text.append_printf ("%d:%s;%s",declared_native_names[index].length,declared_native_names[index],declared_members[index].identity ());
		}
		return text.str;
	}

}
// An export resolves each protocol requirement once to a selected native
// member. Detached stages retain exact member keys rather than repeating a
// name lookup or inferring compatibility from pointer widths.
public class ForeignComExportBinding: Object {
	public ForeignComInterface protocol { get; private set; }
	public ForeignApiContract api { get; private set; }
	private uint[] targets;
	public uint target(uint index) {
		return targets[index];
	}

	public ForeignComExportBinding (ForeignComInterface protocol,ForeignApiContract api,uint[] targets) {
		this.protocol = protocol;
		this.api = api;
		this.targets = targets.copy ();
	}

	public static bool native_view(ForeignChannel native_channel,ForeignChannel required) {
		return native_channel.value_type.kind == ForeignValueKind.NATIVE_OBJECT && required.value_type.kind == ForeignValueKind.COM_OBJECT;
	}

	private static bool channel_matches(ForeignChannel native_channel,ForeignChannel required) {
		bool projection = native_view (native_channel,required);
		bool sequence = required.value_type.kind == ForeignValueKind.BYTES || required.value_type.kind == ForeignValueKind.TEXT;
		return native_channel.same_transport (required,!projection && !sequence,!projection);
	}

	public static bool signature_matches(ForeignMemberContract native_member,ForeignMemberContract requirement) {
		if (native_member.kind != requirement.kind || native_member.parameter_count != requirement.parameter_count || native_member.null_status != requirement.null_status || native_member.error_origin != "" && (native_member.error_origin != requirement.error_origin || native_member.error_map == null || requirement.error_map == null || native_member.error_map.identity () != requirement.error_map.identity ())) {
			return false;
		}
		if (!channel_matches (native_member.result,requirement.result)) {
			return false;
		}
		for (uint p = 0; p < requirement.parameter_count; p++) {
			if (!channel_matches (native_member.parameter (p),requirement.parameter (p))) {
				return false;
			}
		}
		return true;
	}

	public bool valid() {
		if (!protocol.valid () || !api.valid () || api.lifetime != ForeignLifetime.SHARED || targets.length != protocol.requirement_count) {
			return false;
		}
		for (uint r = 0; r < targets.length; r++) {
			if (targets[r] >= api.member_count || !signature_matches (api.member (targets[r]),protocol.requirement (r))) {
				return false;
			}
		}
		return true;
	}

	public string identity() {
		var text = new StringBuilder (protocol.identity ());
		for (uint r = 0; r < targets.length; r++) {
			text.append_printf ("target=%u:%s;",targets[r],targets[r] < api.member_count ? api.member (targets[r]).native_key : "invalid");
		}
		return text.str;
	}

}
// Explicit SDK boxed names belong to the imported physical contract. Native
// nominal identity and scalar fields remain in ForeignValueType.
public class ForeignGObjectRecordBinding: Object {
	private string origin_identifier;
	private string type_identifier;
	private string symbol_identifier;
	public string native_origin { get { return origin_identifier; } }
	public string type_name { get { return type_identifier; } }
	public string symbol_prefix { get { return symbol_identifier; } }
	public ForeignGObjectRecordBinding (string origin,string name,string prefix) {
		origin_identifier = origin;
		type_identifier = name;
		symbol_identifier = prefix;
	}

	public bool valid() {
		if (native_origin.length == 0 || native_origin.length > 4096 || !ForeignClassPolicy.identifier (type_name) || type_name.length == 0 || type_name[0] < 'A' || type_name[0] > 'Z' || !ForeignClassPolicy.identifier (symbol_prefix)) {
			return false;
		}
		for (int i = 0; i < native_origin.length; i++) {
			char c = native_origin[i];
			if (c < 32 || c == '=' || c == ':' || c == '|') {
				return false;
			}
		}
		return true;
	}

	public string identity() {
		return "%d:%s;%d:%s;%d:%s;".printf (native_origin.length,native_origin,type_name.length,type_name,symbol_prefix.length,symbol_prefix);
	}

}
public class ForeignGObjectImport: Object {
	private string type_identifier;
	private string namespace_identifier;
	private string version_identifier;
	private string symbol_identifier;
	private string header_identifier;
	private string record_identifier;
	private GenericArray<ForeignGObjectRecordBinding> records = new GenericArray<ForeignGObjectRecordBinding> ();
	public string type_name { get { return type_identifier; } }
	public string namespace_name { get { return namespace_identifier; } }
	public string version { get { return version_identifier; } }
	public string symbol_prefix { get { return symbol_identifier; } }
	public string header { get { return header_identifier; } }
	public string record_bindings { get { return record_identifier; } }
	public ForeignGObjectImport (string type_name,string namespace_name,string version,string symbol_prefix,string header,string record_bindings = "") {
		record_identifier = record_bindings;
		foreach (string entry in record_bindings.split ("|")) {
			if (entry == "") {
				continue;
			}
			string[] pair = entry.split ("=");
			string[] sdk = pair.length == 2 ? pair[1].split (":") : new string[0];
			records.add (new ForeignGObjectRecordBinding (pair[0],sdk.length == 2 ? sdk[0] : "",sdk.length == 2 ? sdk[1] : ""));
		}
		type_identifier = type_name;
		namespace_identifier = namespace_name;
		version_identifier = version;
		symbol_identifier = symbol_prefix;
		header_identifier = header;
	}

	public ForeignGObjectRecordBinding? record(ForeignValueType type) {
		if (type.kind != ForeignValueKind.RECORD) {
			return null;
		}
		foreach (var binding in records) {
			if (binding.native_origin == type.nominal_origin) {
				return binding;
			}
		}
		return null;
	}

	public bool records_valid(ForeignApiContract api) {
		for (uint m = 0; m < api.member_count; m++) {
			var member = api.member (m);
			for (uint v = 0; v <= member.parameter_count; v++) {
				var type = v == member.parameter_count ? member.result.value_type : member.parameter (v).value_type;
				if (type.kind == ForeignValueKind.RECORD && (record (type) == null || !new ForeignGObjectRecordLayout (type).valid ())) {
					return false;
				}
			}
		}
		return true;
	}

	public bool valid() {
		if (record_identifier.length > 65536 || records.length > 1024 || record_identifier != "" && (record_identifier.has_prefix ("|") || record_identifier.has_suffix ("|") || record_identifier.contains ("||"))) {
			return false;
		}
		var origins = new HashTable<string,bool> (str_hash,str_equal);
		var types = new HashTable<string,bool> (str_hash,str_equal);
		var prefixes = new HashTable<string,bool> (str_hash,str_equal);
		foreach (var binding in records) {
			if (!binding.valid () || origins.contains (binding.native_origin) || types.contains (binding.type_name) || prefixes.contains (binding.symbol_prefix)) {
				return false;
			}
			origins.insert (binding.native_origin,true);
			types.insert (binding.type_name,true);
			prefixes.insert (binding.symbol_prefix,true);
		}
		var name = new GObjectExportContract (namespace_name + "Type",namespace_name,version,true);
		if (!name.valid () || !ForeignClassPolicy.identifier (type_name) || type_name.length == 0 || !(type_name[0] >= 'A' && type_name[0] <= 'Z') || !ForeignClassPolicy.identifier (symbol_prefix) || header.length == 0 || header.length > 1024 || !header.has_suffix (".h") || header.has_prefix ("/") || header.contains ("..")) {
			return false;
		}
		for (int c = 0; c < header.length; c++) {
			char value = header[c];
			if (!(value >= 'a' && value <= 'z') && !(value >= 'A' && value <= 'Z') && !(value >= '0' && value <= '9') && value != '_' && value != '-' && value != '/' && value != '.') {
				return false;
			}
		}
		return true;
	}

	public string identity() {
		return "GObjectImport;declarations-v1;linux-x64;checked-out;gboolean32;GError;constructing;GType-is-a;nonfloating;owned-reference;%d:%s;%d:%s;%d:%s;%d:%s;%d:%s;".printf (type_name.length,type_name,namespace_name.length,namespace_name,version.length,version,symbol_prefix.length,symbol_prefix,header.length,header) + "%d:%s;".printf (record_identifier.length,record_identifier);
	}

	public bool equal(ForeignGObjectImport other) {
		return type_name == other.type_name && namespace_name == other.namespace_name && version == other.version && symbol_prefix == other.symbol_prefix && header == other.header && record_identifier == other.record_identifier;
	}

}
// Declaration-derived imported roots keep the provider's own lifetime.
// The native carrier is the exact opaque provider handle, with no proxy RC.
public class ForeignImportContract: Object {
	public ForeignApiContract api { get; private set; }
	public ForeignComInterface? com { get; private set; }
	public ForeignGObjectImport? gobject { get; private set; }
	public ForeignValueKind object_kind { get { return gobject != null ? ForeignValueKind.GOBJECT : com == null ? ForeignValueKind.NATIVE_OBJECT : ForeignValueKind.COM_OBJECT; } }
	private string[] factories;
	private string[] native_names;
	public string native_name(uint member) {
		return native_names[member];
	}

	public string factory(uint member) {
		return factories[member];
	}

	public ForeignImportContract (ForeignApiContract api,string[] factories,string[] native_names,ForeignComInterface? com = null,ForeignGObjectImport? gobject = null) {
		this.gobject = gobject;
		this.api = api;
		this.factories = factories.copy ();
		this.native_names = native_names.copy ();
		this.com = com;
	}

	public static string root_identity(string name,string prefix,ForeignLifetime lifetime,string com_iid = "",ForeignGObjectImport? gobject = null,int personality_selection = -1) {
		string selection = personality_selection < 0 ? "" : ";selected=%d".printf (personality_selection);
		if (gobject != null) {
			return "GObjectImport;declarations-v1;%s;%s;%s".printf (name,prefix,gobject.identity ()) + selection;
		}
		return (com_iid == "" ? "CImport;declarations-v1;%s;%s;%u".printf (name,prefix,(uint) lifetime) : "COMImport;declarations-v1;%s;%s;%s".printf (name,prefix,com_iid.ascii_down ())) + selection;
	}

	public string identity() {
		return root_identity (api.native_origin,api.prefix,api.lifetime,com == null ? "" : com.iid,gobject,api.personality_selection);
	}

	public string declaration_identity() {
		var text = new StringBuilder (api.identity ());
		if (com != null) {
			text.append (com.identity ());
		}
		if (gobject != null) {
			text.append (gobject.identity ());
		}
		for (uint m = 0; m < api.member_count; m++) {
			text.append_printf ("factory=%d:%s;native=%d:%s;",factories[m].length,factories[m],native_names[m].length,native_names[m]);
		}
		return text.str;
	}

	public bool equal(ForeignImportContract other) {
		if (!api.equal (other.api) || (gobject == null ? other.gobject != null : other.gobject == null || !gobject.equal (other.gobject)) || (com == null ? other.com != null : other.com == null || com.identity () != other.com.identity ()) || factories.length != other.factories.length || native_names.length != other.native_names.length) {
			return false;
		}
		for (uint index = 0; index < factories.length; index++) {
			if (factories[index] != other.factories[index] || native_names[index] != other.native_names[index]) {
				return false;
			}
		}
		return true;
	}

	public static bool distinct(GenericArray<ForeignImportContract> roots) {
		var names = new HashTable<string,bool> (str_hash,str_equal);
		var prefixes = new HashTable<string,bool> (str_hash,str_equal);
		var iids = new HashTable<string,bool> (str_hash,str_equal);
		foreach (var root in roots) {
			if (!root.valid () || names.contains (root.api.native_origin) || prefixes.contains (root.api.prefix)) {
				return false;
			}
			names.insert (root.api.native_origin,true);
			prefixes.insert (root.api.prefix,true);
			if (root.com == null) {
				continue;
			}
			if (iids.contains (root.com.iid)) {
				return false;
			}
			iids.insert (root.com.iid,true);
			if (root.com.parent != null) {
				bool found = false;
				foreach (var parent in roots) {
					found |= parent.com != null && parent.com.identity () == root.com.parent.identity ();
				}
				if (!found) {
					return false;
				}
			}
		}
		return true;
	}

	public string cleanup_symbol() {
		return "astra_foreign16_import_cleanup_" + api.prefix;
	}

	public bool valid() {
		if (!api.valid () || api.declared_personalities != (gobject != null ? ForeignClassPolicy.GOBJECT : com == null ? ForeignClassPolicy.C : ForeignClassPolicy.COM) || factories.length != api.member_count || native_names.length != api.member_count) {
			return false;
		}
		if (gobject != null && (com != null || !gobject.valid () || !gobject.records_valid (api) || api.lifetime != ForeignLifetime.SHARED)) {
			return false;
		}
		if (com != null && (!com.valid () || com.name != api.native_origin || com.prefix != api.prefix || api.lifetime != ForeignLifetime.SHARED)) {
			return false;
		}
		var names = new HashTable<string,bool> (str_hash,str_equal);
		uint requirement = 0;
		for (uint m = 0; m < api.member_count; m++) {
			if (!ForeignClassPolicy.nominal_identifier (factories[m]) || !ForeignClassPolicy.identifier (native_names[m]) || names.contains (native_names[m])) {
				return false;
			}
			names.insert (native_names[m],true);
			var member = api.member (m);
			if (gobject != null && member.kind == ForeignMemberKind.CONSTRUCTOR && (member.result.value_type.kind != ForeignValueKind.GOBJECT || member.result.value_type.nominal_origin != api.native_origin || member.result.transfer != ForeignTransfer.OWN || member.result.nullable || member.result.release_symbol != api.prefix + "_release")) {
				return false;
			}
			if (com != null && member.kind == ForeignMemberKind.CONSTRUCTOR && (member.name != "acquire" || member.parameter_count != 1 || member.parameter (0).value_type.kind != ForeignValueKind.COM_OBJECT || member.parameter (0).value_type.nominal_origin != "IUnknown" || member.parameter (0).direction != ForeignDirection.IN || member.parameter (0).transfer != ForeignTransfer.BORROW || !member.parameter (0).call_scoped || member.parameter (0).nullable || member.result.value_type.kind != ForeignValueKind.COM_OBJECT || member.result.value_type.nominal_origin != api.native_origin || member.result.transfer != ForeignTransfer.OWN || member.result.nullable || member.result.release_symbol != api.prefix + "_release")) {
				return false;
			}
			if (com != null && member.kind != ForeignMemberKind.CONSTRUCTOR) {
				if (requirement >= com.requirement_count || member.name != com.requirement (requirement).name || !member.same_signature (com.requirement (requirement++))) {
					return false;
				}
			}
			if (member.kind == ForeignMemberKind.SETTER) {
				if (m == 0) {
					return false;
				}
				var getter = api.member (m - 1);
				if (getter.kind != ForeignMemberKind.GETTER || getter.native_member_ordinal != member.native_member_ordinal || !getter.result.value_type.equal (member.parameter (0).value_type) || getter.error_origin != member.error_origin || (getter.error_map == null ? member.error_map != null : member.error_map == null || getter.error_map.identity () != member.error_map.identity ()) || factories[m - 1] != factories[m]) {
					return false;
				}
			}
		}
		return com == null || requirement == com.requirement_count;
	}

	public static bool matches(ForeignImportContract? contract,string identity,string name,string cleanup) {
		return contract != null && contract.valid () && contract.identity () == identity && contract.api.native_origin == name && contract.cleanup_symbol () == cleanup;
	}

}
public class ForeignImportBinding: Object {
	public ForeignImportContract root { get; private set; }
	public uint member_index { get; private set; }
	public ForeignMemberContract member { owned get { return root.api.member (member_index); } }
	public ForeignImportBinding (ForeignImportContract root,uint member_index) {
		this.root = root;
		this.member_index = member_index;
	}

	public bool valid() {
		return root.valid () && member_index < root.api.member_count && member.valid ();
	}

	public string identity() {
		return root.api.identity () + (root.com == null ? "" : ";protocol=" + root.com.identity ()) + ";import-member=" + member_index.to_string () + ";factory=" + root.factory (member_index) + ";native=" + root.native_name (member_index);
	}

}
public class ForeignSignalBinding: Object {
	public ForeignClassPolicy root { get; private set; }
	public uint member_index { get; private set; }
	public ForeignMemberContract member { owned get { return root.declared_api.member (member_index); } }
	public ForeignSignalBinding (ForeignClassPolicy root,uint index) {
		this.root = root.copy ();
		member_index = index;
	}

	public bool valid() {
		return root.valid () && root.declared_api != null && root.declared_api.lifetime == ForeignLifetime.SHARED && root.gobject != null && root.gobject.declarations && member_index < root.declared_api.member_count && member.kind == ForeignMemberKind.SIGNAL && member.personalities == ForeignClassPolicy.GOBJECT && member.valid ();
	}

	public string identity() {
		return root.identity () + ";signal=" + member_index.to_string ();
	}

	public string symbol() {
		return "astra_foreign16_signal_" + root.prefix + "_" + member_index.to_string ();
	}

}

}
