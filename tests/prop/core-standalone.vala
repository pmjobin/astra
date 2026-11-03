// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.PropCore {
private CoreProgram sample(int shape = 0, int variant = 0) throws CoreError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("prop", "S"), 0, 1);
	var type = new StructType ("S");
	var owner = new CoreStruct (span, span, "S", type);
	owner.fields.add (new CoreStructField (span, span, "raw", owner, t.int_type, 0));
	SemanticType value_type = shape == 1 ? (SemanticType) t.bool_type : shape == 2 ? (SemanticType) t.f32_type : shape == 3 ? (SemanticType) t.f64_type : shape == 4 ? (SemanticType) t.vector_of (t.i16_type, 8) : shape == 5 ? (SemanticType) t.raw_pointer_type : shape == 6 ? (SemanticType) t.vector_of (t.bool_type, 4) : t.int_type;
	var contract = new ReceiverType (variant == 2 ? new StructType ("Other") : type, variant == 3 ? ReceiverMode.INITIALIZING : ReceiverMode.LIVE);
	var property = new CoreProperty (span, span, variant == 4 ? "raw" : "value", owner, variant == 5 ? t.void_type : value_type, variant == 6 ? 1 : 0, variant == 7 ? 9 : 1);
	var other = new CoreProperty (span, span, "other", owner, value_type, 1, 2);
	owner.properties.add (property);
	var get_receiver = new CoreReceiver (span, contract);
	var set_receiver = new CoreReceiver (span, contract);
	var get_parameters = new GenericArray<CoreParameter> ();
	var set_parameters = new GenericArray<CoreParameter> ();
	var parameter = new CoreParameter (span, span, "next", variant == 8 ? t.u32_type : value_type, 0, variant == 9 ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED);
	set_parameters.add (parameter);
	if (variant == 10) {
		get_parameters.add (parameter);
	}
	var get_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var set_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var getter = new CorePropertyGetter (span, span, "get", variant == 1 ? other : property, get_receiver, value_type, get_parameters, new GenericArray<CoreLocalPlace> (), get_body);
	var setter = new CorePropertySetter (span, span, "set", property, set_receiver, variant == 11 ? value_type : t.void_type, set_parameters, new GenericArray<CoreLocalPlace> (), set_body);
	if (variant != 13) {
		property.getter = getter;
	}
	property.setter = setter;
	var get_arguments = new GenericArray<CoreValue> ();
	var set_arguments = new GenericArray<CoreValue> ();
	if (variant != 14) {
		set_arguments.add (new CoreParameterValue (span, parameter));
	}
	CoreValue? self = variant == 15 ? null : new CoreReceiverValue (span, get_receiver);
	get_body.statements.add (new CoreReturn (span, new CoreCallValue (span, variant == 12 ? t.u32_type : value_type, getter, get_arguments, self)));
	set_body.statements.add (new CoreCallStatement (span, setter, set_arguments, new CoreReceiverValue (span, set_receiver)));
	set_body.statements.add (new CoreReturn (span, null));
	var functions = new GenericArray<CoreFunction> ();
	functions.add (getter);
	functions.add (setter);
	if (variant == 16) {
		owner.properties.add (property);
	}
	var structures = new GenericArray<CoreStruct> ();
	structures.add (owner);
	return new CoreProgram (span, functions, null, null, structures);
}

private void model() {
	try {
		for (int shape = 0; shape < 7; shape++) {
			CoreProgram? program = sample (shape);
			CoreVerifier.verify (program);
			assert (program.structs[0].properties[0].getter == program.functions[0]);
			assert (!(program.functions[0] is CoreMethod) && program.functions[0].kind == CallableKind.PROPERTY_GETTER);
			string dump = CoreDump.format (program);
			assert (dump.contains ("property-get") && dump.contains ("property-set") && dump.contains ("effectful"));
			var property = WeakRef (program.structs[0].properties[0]);
			var getter = WeakRef (program.functions[0]);
			var setter = WeakRef (program.functions[1]);
			program = null;
			assert (property.get () == null && getter.get () == null && setter.get () == null);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void malformed() {
	for (int variant = 1; variant <= 16; variant++) {
		try {
			CoreVerifier.verify (sample (0, variant));
		} catch (GLib.Error error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed property variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/prop/core/exact-property-accessors-calls-types-recursion-lifetime", model);
	Test.add_func ("/prop/core/malformed-owner-member-receiver-value-and-call", malformed);
	return Test.run ();
}

}
