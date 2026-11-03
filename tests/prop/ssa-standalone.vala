// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Tests.PropSsa {
private SsaProgram sample(int shape = 0, int variant = 0) throws SsaError {
	var t = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("prop", "S"), 0, 1);
	var type = new StructType ("S");
	var owner = new SsaStruct (span, span, "S", type);
	owner.fields.add (new SsaStructField (span, span, "raw", owner, t.int_type, 0));
	SemanticType value_type = shape == 1 ? (SemanticType) t.bool_type : shape == 2 ? (SemanticType) t.f32_type : shape == 3 ? (SemanticType) t.f64_type : shape == 4 ? (SemanticType) t.vector_of (t.i16_type, 8) : shape == 5 ? (SemanticType) t.raw_pointer_type : shape == 6 ? (SemanticType) t.vector_of (t.bool_type, 4) : t.int_type;
	var contract = new ReceiverType (variant == 2 ? new StructType ("Other") : type, variant == 3 ? ReceiverMode.INITIALIZING : ReceiverMode.LIVE);
	var property = new SsaProperty (span, span, variant == 4 ? "raw" : "value", owner, variant == 5 ? t.void_type : value_type, variant == 6 ? 1 : 0, variant == 7 ? 9 : 1);
	var other = new SsaProperty (span, span, "other", owner, value_type, 1, 2);
	owner.properties.add (property);
	var get_receiver = new SsaReceiver (span, contract, 0);
	var set_receiver = new SsaReceiver (span, contract, 0);
	var get_parameters = new GenericArray<SsaFunctionParameter> ();
	var set_parameters = new GenericArray<SsaFunctionParameter> ();
	var parameter = new SsaFunctionParameter (span, span, "next", variant == 8 ? t.u32_type : value_type, 1, variant == 9 ? PointerParameterContract.BORROWED_NOESCAPE : PointerParameterContract.UNMANAGED);
	set_parameters.add (parameter);
	if (variant == 10) {
		get_parameters.add (parameter);
	}
	var get_body = new SsaBlock (span, 0, 0);
	var set_body = new SsaBlock (span, 0, 0);
	var get_blocks = new GenericArray<SsaBlock> ();
	get_blocks.add (get_body);
	var set_blocks = new GenericArray<SsaBlock> ();
	set_blocks.add (set_body);
	var getter = new SsaPropertyGetter (span, span, "get", variant == 1 ? other : property, get_receiver, value_type, 0, get_parameters, get_blocks, get_body);
	var setter = new SsaPropertySetter (span, span, "set", property, set_receiver, variant == 11 ? value_type : t.void_type, 1, set_parameters, set_blocks, set_body);
	if (variant != 13) {
		property.getter = getter;
	}
	property.setter = setter;
	var get_arguments = new GenericArray<SsaValue> ();
	var set_arguments = new GenericArray<SsaValue> ();
	if (variant != 14) {
		set_arguments.add (parameter);
	}
	SsaValue? self = variant == 15 ? null : get_receiver;
	var call = new SsaCallInstruction (span, variant == 12 ? t.u32_type : value_type, 2, getter, get_arguments, self);
	get_body.instructions.add (call);
	get_body.complete (new SsaReturn (span, call.result));
	set_body.instructions.add (new SsaCallInstruction (span, null, -1, setter, set_arguments, set_receiver));
	set_body.complete (new SsaReturn (span, null));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (getter);
	functions.add (setter);
	if (variant == 16) {
		owner.properties.add (property);
	}
	var structures = new GenericArray<SsaStruct> ();
	structures.add (owner);
	return new SsaProgram (span, functions, null, null, structures);
}

private void model() {
	try {
		for (int shape = 0; shape < 7; shape++) {
			SsaProgram? program = sample (shape);
			SsaVerifier.verify (program);
			assert (program.structs[0].properties[0].getter == program.functions[0]);
			assert (!(program.functions[0] is SsaMethod) && program.functions[0].kind == CallableKind.PROPERTY_GETTER);
			string dump = SsaDump.format (program);
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
			SsaVerifier.verify (sample (0, variant));
		} catch (GLib.Error error) {
			Test.message ("variant %d: %s", variant, error.message);
			continue;
		}
		GLib.error ("accepted malformed property variant %d", variant);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/prop/ssa/exact-property-accessors-calls-types-recursion-lifetime", model);
	Test.add_func ("/prop/ssa/malformed-owner-member-receiver-value-and-call", malformed);
	return Test.run ();
}

}
