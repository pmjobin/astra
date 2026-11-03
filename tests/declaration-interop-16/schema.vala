// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace ForeignSchemaTests {
private ForeignValueType scalar(ForeignValueKind kind = ForeignValueKind.I32) {
	return new ForeignValueType (kind);
}

private ForeignChannel result(ForeignValueKind kind = ForeignValueKind.VOID) {
	return new ForeignChannel ("result", scalar (kind), ForeignDirection.OUT);
}

private ForeignMemberContract method(GenericArray<ForeignChannel> parameters, string key = "sdk@closed/Service.process", string error = "") {
	return new ForeignMemberContract (ForeignMemberKind.METHOD, "process", key, parameters, result (), error);
}

private void scalar_and_record_domain() {
	var fields = new GenericArray<ForeignRecordField> ();
	for (int value = (int) ForeignValueKind.I32; value <= (int) ForeignValueKind.BOOL; value++) {
		var kind = (ForeignValueKind) value;
		assert_true (scalar (kind).valid ());
		fields.add (new ForeignRecordField ("field%d".printf ((int) kind), kind));
	}
	var record = new ForeignValueType (ForeignValueKind.RECORD, "sdk@closed/Statistics<int>", fields);
	assert_true (record.valid ());
	// Caller mutation must not change admitted field order or count.
	fields.add (new ForeignRecordField ("late", ForeignValueKind.TEXT));
	assert_true (record.valid ());
	assert (record.field_count == 7);
	assert_false (new ForeignValueType (ForeignValueKind.RECORD, "sdk@closed/Statistics<int>", fields).valid ());
	var duplicate = new GenericArray<ForeignRecordField> ();
	duplicate.add (new ForeignRecordField ("x", ForeignValueKind.I64));
	duplicate.add (new ForeignRecordField ("x", ForeignValueKind.F64));
	assert_false (new ForeignValueType (ForeignValueKind.RECORD, "sdk/Record", duplicate).valid ());
}

private void nominal_identity() {
	var left = new ForeignValueType (ForeignValueKind.NATIVE_OBJECT, "first@closed/Item<int>");
	var right = new ForeignValueType (ForeignValueKind.NATIVE_OBJECT, "second@closed/Item<int>");
	var other_argument = new ForeignValueType (ForeignValueKind.NATIVE_OBJECT, "first@closed/Item<f64>");
	assert_true (left.valid ());
	assert_true (right.valid ());
	assert_false (left.equal (right));
	assert_false (left.equal (other_argument));
	assert_false (scalar (ForeignValueKind.COM_OBJECT).valid ());
	assert_false (new ForeignValueType (ForeignValueKind.I64, "forged-owner").valid ());
}

private void counted_output() {
	var parameters = new GenericArray<ForeignChannel> ();
	var bytes = new ForeignValueType (ForeignValueKind.BYTES);
	parameters.add (new ForeignChannel ("output", bytes, ForeignDirection.OUT, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.BYTES, 2, 1, 2, "", true));
	parameters.add (new ForeignChannel ("capacity", scalar ()));
	parameters.add (new ForeignChannel ("produced", scalar (), ForeignDirection.OUT, ForeignTransfer.COPY, false, ForeignTextEncoding.NONE, -1, -1, -1, "", true, -1, -1, false, false, false, true));
	assert_true (method (parameters).valid ());
	var wrong_count = new GenericArray<ForeignChannel> ();
	wrong_count.add (parameters[0]);
	wrong_count.add (parameters[1]);
	wrong_count.add (new ForeignChannel ("produced", scalar ()));
	assert_false (method (wrong_count).valid ());
	var missing_capacity = new ForeignChannel ("output", bytes, ForeignDirection.OUT, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.BYTES, 2, -1, 2, "", true);
	assert_false (missing_capacity.valid ());
	var self_count = new GenericArray<ForeignChannel> ();
	self_count.add (new ForeignChannel ("input", bytes, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.BYTES, 0, -1, -1, "", true));
	assert_false (method (self_count).valid ());
	assert_false (new ForeignChannel ("input", bytes, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.BYTES, 1).valid ());
	var intrinsic = new GenericArray<ForeignChannel> ();
	intrinsic.add (new ForeignChannel ("output", bytes, ForeignDirection.OUT, ForeignTransfer.BORROW,
		true, ForeignTextEncoding.BYTES, -1, -1, -1, "", true, -1, -1, true, true));
	assert_true (new ForeignMemberContract (ForeignMemberKind.METHOD, "transform", "Service.transform", intrinsic, result (ForeignValueKind.I32)).valid ());
	assert_false (method (intrinsic).valid ());
	assert_false (new ForeignChannel ("input", bytes, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.BYTES, 1, -1, -1, "", true, -1, -1, true).valid ());
}

private void ownership_and_text() {
	var text = new ForeignValueType (ForeignValueKind.TEXT);
	var owner = new ForeignChannel ("snapshot", text, ForeignDirection.OUT, ForeignTransfer.OWN,
		false, ForeignTextEncoding.UTF8_COUNTED, 0, -1, -1, "sdk_text_release");
	assert_true (owner.valid ());
	assert_false (new ForeignChannel ("snapshot", text, ForeignDirection.OUT, ForeignTransfer.OWN,
		false, ForeignTextEncoding.UTF8_COUNTED, 0).valid ());
	assert_false (new ForeignChannel ("text", text, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.UTF8_NUL, 0, -1, -1, "", true).valid ());
	assert_true (new ForeignChannel ("text", text, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.UTF8_NUL, -1, -1, -1, "", true).valid ());
	assert_false (new ForeignChannel ("flag", scalar (ForeignValueKind.BOOL), ForeignDirection.IN,
		ForeignTransfer.OWN, false, ForeignTextEncoding.NONE, -1, -1, -1, "sdk_release").valid ());
	assert_false (new ForeignChannel ("count", scalar (), ForeignDirection.IN, ForeignTransfer.COPY, true).valid ());
	var handle = new ForeignValueType (ForeignValueKind.NATIVE_OBJECT, "sdk/Item");
	assert_true (new ForeignChannel ("item", handle, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.NONE, -1, -1, -1, "", true, -1, -1, false, false, true).valid ());
	assert_false (new ForeignChannel ("item", handle, ForeignDirection.IN, ForeignTransfer.BORROW,
		true, ForeignTextEncoding.NONE, -1, -1, -1, "", true, -1, -1, false, false, true).valid ());
}

private void lifetime_and_member_binding() {
	var parameters = new GenericArray<ForeignChannel> ();
	parameters.add (new ForeignChannel ("word", scalar ()));
	var selected = method (parameters);
	var members = new GenericArray<ForeignMemberContract> ();
	members.add (selected);
	var unique = new ForeignApiContract ("sdk/Session", "session", ForeignLifetime.UNIQUE, ForeignClassPolicy.C, members);
	assert_true (unique.valid ());
	assert_false (new ForeignApiContract ("sdk/Session", "session", ForeignLifetime.UNIQUE, ForeignClassPolicy.C | ForeignClassPolicy.COM, members).valid ());
	assert_true (new ForeignApiContract ("sdk/Session", "session", ForeignLifetime.SHARED, 7, members).valid ());
	// A legal but stale binding/effect is still a different contract. A stage
	// must compare its actual callable facts, not merely accept valid syntax.
	assert_false (selected.equal (method (parameters, "sdk@closed/Service.other")));
	assert_false (selected.equal (method (parameters, "sdk@closed/Service.process", "sdk/Failure")));
	members.add (selected);
	assert_true (unique.valid ());
	assert_false (new ForeignApiContract ("sdk/Session", "session", ForeignLifetime.UNIQUE, ForeignClassPolicy.C, members).valid ());
	parameters.add (new ForeignChannel ("late", scalar ()));
	assert (selected.parameter_count == 1);
}

private void callback_and_signal_scope() {
	var values = new GenericArray<ForeignValueType> ();
	values.add (scalar (ForeignValueKind.F64));
	var callback = new ForeignValueType (ForeignValueKind.CALLBACK, "", null, values, scalar ());
	var parameters = new GenericArray<ForeignChannel> ();
	parameters.add (new ForeignChannel ("visit", callback, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.NONE, -1, -1, -1, "", true, 1));
	parameters.add (new ForeignChannel ("environment", new ForeignValueType (ForeignValueKind.NATIVE_OBJECT, "sdk/Environment"),
		ForeignDirection.IN, ForeignTransfer.BORROW, false, ForeignTextEncoding.NONE, -1, -1, -1, "", true));
	assert_true (method (parameters).valid ());
	assert_false (new ForeignChannel ("visit", callback, ForeignDirection.IN, ForeignTransfer.BORROW,
		false, ForeignTextEncoding.NONE, -1, -1, -1, "", false, 1).valid ());
	assert_true (new ForeignMemberContract (ForeignMemberKind.SIGNAL,"updated","sdk/Service.updated",parameters,result ()).valid ());
	assert_false (new ForeignMemberContract (ForeignMemberKind.SIGNAL,"updated","sdk/Service.updated",parameters,result (ForeignValueKind.I32)).valid ());
	assert_false (new ForeignMemberContract (ForeignMemberKind.SIGNAL,"updated","sdk/Service.updated",parameters,result (),"sdk/Error").valid ());
	ForeignValueType nested = scalar ();
	for (int i = 0; i < 33; i++) {
		nested = new ForeignValueType (ForeignValueKind.CALLBACK,"",null,null,nested);
	}
	assert_false (nested.valid ());
}

private void com_protocol_identity_and_slots() {
	var parameters = new GenericArray<ForeignChannel> ();
	parameters.add (new ForeignChannel ("input",scalar (ForeignValueKind.BOOL)));
	var first = new ForeignMemberContract (ForeignMemberKind.METHOD,"inspect","IBase/0",parameters,result (ForeignValueKind.I64),"",ForeignClassPolicy.COM,0);
	var members = new GenericArray<ForeignMemberContract> ();
	members.add (first);
	string[] native_names = {
		"native_inspect"
	};
	var base_interface = new ForeignComInterface ("IBase","base16","2c2d4a08-a483-4ace-9e01-f6793e47f001",members,native_names);
	assert_true (base_interface.valid ());
	members.remove_index (0);
	native_names[0] = "changed";
	assert (base_interface.own_count == 1 && base_interface.native_name (0) == "native_inspect");
	var next = new ForeignMemberContract (ForeignMemberKind.METHOD,"measure","IDerived/0",parameters,result (ForeignValueKind.F64),"",ForeignClassPolicy.COM,0);
	members.add (next);
	var derived = new ForeignComInterface ("IDerived","derived16","2c2d4a08-a483-4ace-9e01-f6793e47f002",members,new string[] { "native_measure" },base_interface);
	assert_true (derived.valid ());
	assert (derived.requirement_count == 2 && derived.inherited_count == 1 && derived.slot (0) == 3 && derived.slot (1) == 4 && derived.requirement (0) == first && derived.native_name (1) == "native_measure");
	assert (derived.bool_bits == 32 && derived.pointer_bits == 64 && derived.status_bits == 32 && derived.query_slot == 0 && derived.acquire_slot == 1 && derived.release_slot == 2);
	assert_false (new ForeignComInterface ("IDerived","derived16",base_interface.iid,members,new string[] { "native_measure" },base_interface).valid ());
	assert_false (new ForeignComInterface ("IDerived","derived16","00000000-0000-0000-c000-000000000046",members,new string[] { "native_measure" }).valid ());
	assert_false (new ForeignComInterface ("IDerived","derived16",derived.iid,members,new string[] { "native_measure" },derived).valid ());
	members[0] = first;
	assert_false (new ForeignComInterface ("IDerived","derived16",derived.iid,members,new string[] { "native_inspect" },base_interface).valid ());
	var renamed = new GenericArray<ForeignChannel> ();
	renamed.add (new ForeignChannel ("argument",scalar (ForeignValueKind.BOOL)));
	var alternate = new ForeignMemberContract (ForeignMemberKind.METHOD,"renamed","Native/7",renamed,result (ForeignValueKind.I64),"",ForeignClassPolicy.C,7);
	assert_true (first.same_signature (alternate));
	assert_false (first.equal (alternate));
	assert_false (next.same_signature (alternate));
	assert (base_interface.identity () != derived.identity ());
}

private void com_record_storage() {
	var fields = new GenericArray<ForeignRecordField> ();
	fields.add (new ForeignRecordField ("first",ForeignValueKind.BOOL));
	fields.add (new ForeignRecordField ("second",ForeignValueKind.BOOL));
	fields.add (new ForeignRecordField ("count",ForeignValueKind.I32));
	fields.add (new ForeignRecordField ("scale",ForeignValueKind.F64));
	var type = new ForeignValueType (ForeignValueKind.RECORD,"Pair",fields);
	var layout = new ForeignComRecordLayout (type);
	assert_true (layout.valid ());
	assert (layout.offset (0) == 0 && layout.offset (1) == 4 && layout.offset (2) == 8 && layout.offset (3) == 16 && layout.size == 24 && layout.alignment == 8);
	fields[0] = new ForeignRecordField ("first",ForeignValueKind.F64);
	assert (layout.offset (1) == 4 && layout.value_type.field (0).kind == ForeignValueKind.BOOL);
	assert_false (new ForeignComRecordLayout (scalar ()).valid ());
	var parameters = new GenericArray<ForeignChannel> ();
	parameters.add (new ForeignChannel ("input",type));
	var selected = new ForeignMemberContract (ForeignMemberKind.METHOD,"adjust","Native/0",parameters,new ForeignChannel ("result",type,ForeignDirection.OUT),"",ForeignClassPolicy.C,0);
	var required = new ForeignMemberContract (ForeignMemberKind.METHOD,"amend","Interface/0",parameters,new ForeignChannel ("result",type,ForeignDirection.OUT),"",ForeignClassPolicy.COM,0);
	var native_members = new GenericArray<ForeignMemberContract> ();
	native_members.add (selected);
	var required_members = new GenericArray<ForeignMemberContract> ();
	required_members.add (required);
	var api = new ForeignApiContract ("Native","native",ForeignLifetime.SHARED,ForeignClassPolicy.C | ForeignClassPolicy.COM,native_members);
	var protocol = new ForeignComInterface ("IRecord","irecord","2c2d4a08-a483-4ace-9e01-f6793e47f004",required_members,new string[] {"adjust"});
	uint[] targets = {
		0
	};
	var binding = new ForeignComExportBinding (protocol,api,targets);
	targets[0] = 7;
	assert_true (binding.valid ());
	assert (binding.target (0) == 0);
	assert_false (new ForeignComExportBinding (protocol,api,targets).valid ());
	var bindings = new GenericArray<ForeignComExportBinding> ();
	bindings.add (binding);
	var policy = new ForeignClassPolicy.declared (api,bindings);
	assert_true (policy.valid ());
	assert (policy.copy ().identity () == policy.identity ());
	bindings.remove_index (0);
	assert (policy.com_count == 1);

}

private void gobject_contract_profiles() {
	var modern = new GObjectExportContract ("SdkSession","Sdk","2.3",true);
	assert_true (modern.valid ());
	assert (modern.declarations && modern.symbol_prefix () == "sdk_session");
	var go_fields = new GenericArray<ForeignRecordField> ();
	go_fields.add (new ForeignRecordField ("flag",ForeignValueKind.BOOL));
	go_fields.add (new ForeignRecordField ("value",ForeignValueKind.F64));
	var go_layout = new ForeignGObjectRecordLayout (new ForeignValueType (ForeignValueKind.RECORD,"Sdk.Record",go_fields));
	assert_true (go_layout.valid ());
	assert (go_layout.offset (1) == 8 && go_layout.size == 16);
	assert_true (go_layout.identity ().has_prefix ("linux-x64;GObject-boxed-POD;gboolean32;"));
	var gi = new ForeignGObjectImport ("GFile","Gio","2.0","g_file","gio/gio.h");
	assert_true (gi.valid ());
	assert_false (new ForeignGObjectImport ("GFile","Gio","2.0","g_file","../gio.h").valid ());
	assert_false (gi.equal (new ForeignGObjectImport ("GFile","Gio","3.0","g_file","gio/gio.h")));
	var boxed = new ForeignGObjectImport ("GFile","Gio","2.0","g_file","gio/gio.h","Sdk.Record=GRecord:g_record");
	assert_true (boxed.valid ());
	assert (boxed.record (go_layout.value_type).type_name == "GRecord");
	assert_false (boxed.equal (gi));
	foreach (string binding in new string[] { "broken","R=Bad-Type:x","R=Good:bad-prefix","R=Good:r|R=Other:s","R=Good:r|S=Good:s","R=Good:r|S=Other:r","|R=Good:r","R=Good:r|" }) {
		assert_false (new ForeignGObjectImport ("GFile","Gio","2.0","g_file","gio/gio.h",binding).valid ());
	}
	var input_reference = new ForeignChannel ("value",scalar (ForeignValueKind.I64),ForeignDirection.IN,ForeignTransfer.COPY,false,ForeignTextEncoding.NONE,-1,-1,-1,"",true,-1,-1,false,false,false,true);
	assert_true (input_reference.valid ());
	assert_false (GObjectExportContract.indirect_reference (input_reference));
	assert_false (new GObjectExportContract ("SdkSession","Sdk","2.3").valid ());
	assert_true (new GObjectExportContract ("SdkSession","Sdk","1.0").valid ());
	foreach (string version in new string[] { "","1","1.",".1","1..2","a.1","1.-2" }) {
		assert_false (new GObjectExportContract ("SdkSession","Sdk",version,true).valid ());
	}
	var parameters = new GenericArray<ForeignChannel> ();
	parameters.add (new ForeignChannel ("input",scalar (ForeignValueKind.BOOL)));
	var members = new GenericArray<ForeignMemberContract> ();
	members.add (new ForeignMemberContract (ForeignMemberKind.METHOD,"choose","Service/0",parameters,result (ForeignValueKind.BOOL),"",ForeignClassPolicy.GOBJECT,0));
	var api = new ForeignApiContract ("Service","native_session",ForeignLifetime.SHARED,ForeignClassPolicy.C | ForeignClassPolicy.GOBJECT,members);
	var policy = new ForeignClassPolicy.declared (api,null,modern);
	assert_true (policy.valid ());
	var copy = policy.copy ();
	assert (copy.identity () == policy.identity () && copy.gobject != policy.gobject);
	copy.gobject.floating = true;
	assert_false (copy.valid ());
	assert_true (policy.valid ());
	var roots = new GenericArray<ForeignClassPolicy> ();
	roots.add (policy);
	roots.add (policy.copy ());
	assert_false (ForeignClassPolicy.distinct_gobjects (roots));
	roots.remove_index (1);
	assert_true (ForeignClassPolicy.distinct_gobjects (roots));
	assert_false (new ForeignClassPolicy.declared (new ForeignApiContract ("Service","native_session",ForeignLifetime.UNIQUE,ForeignClassPolicy.C | ForeignClassPolicy.GOBJECT,members),null,modern).valid ());
}

public static int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/foreign-schema/gobject-profile-version-selection-and-weak-native-owner",gobject_contract_profiles);
	Test.add_func ("/foreign-schema/com-record-distinct-bool32-storage",com_record_storage);
	Test.add_func ("/foreign-schema/com-iid-inheritance-slot-and-binding-identity",com_protocol_identity_and_slots);
	Test.add_func ("/foreign-schema/scalar-record-domain-and-immutable-fields",scalar_and_record_domain);
	Test.add_func ("/foreign-schema/nominal-origin-and-closed-arguments",nominal_identity);
	Test.add_func ("/foreign-schema/counted-output-direction-capacity-publication",counted_output);
	Test.add_func ("/foreign-schema/ownership-cleanup-and-text-representation",ownership_and_text);
	Test.add_func ("/foreign-schema/unique-shared-and-native-member-effect-identity",lifetime_and_member_binding);
	Test.add_func ("/foreign-schema/callback-signal-scope-and-depth",callback_and_signal_scope);
	return Test.run ();
}

}
