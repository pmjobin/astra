// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenCore {
private SourceSpan span() {
	return SourceSpan (new SourceFile.from_text ("generic", "x"), 0, 1);
}
private CoreGenericFunction definition(SourceSpan s, string name, int ordinal) {
	var t = new TypeParameterType ("T");
	var tp = new GenericArray<CoreTypeParameter> ();
	tp.add (new CoreTypeParameter (s, t, 0));
	var p = new CoreParameter (s, s, "x", t, 0);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (p);
	var local = new CoreLocalPlace (s, s, "copy", t, 0);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreInitialize (s, local, new CoreParameterValue (s, p)));
	body.statements.add (new CoreReturn (s, new CoreLoadValue (s, local)));
	return new CoreGenericFunction (s, s, name, t, parameters, locals, body, null, tp, ordinal);
}
private CoreValue constant(SourceSpan s, SemanticType t) {
	if (t is IntegerType) {
		return new CoreIntegerValue.typed (s, t, AstraIntegerValue.from_int64 ((IntegerType) t, 42));
	}
	if (t is FloatingType) {
		return new CoreFloatValue (s, t, BinaryFloatValue.from_decimal (((FloatingType) t).format, "1.25"));
	}
	if (t.kind == TypeKind.BOOL) {
		return new CoreBooleanValue (s, t, BooleanLiteral.TRUE);
	}
	if (t is VectorType) {
		var lanes = new GenericArray<CoreValue> ();
		for (int i = 0; i < ((VectorType) t).lane_count; i++) {
			lanes.add (constant (s, ((VectorType) t).element_type));
		}
		return new CoreVectorConstructValue (s, t, lanes);
	}
	return new CoreNullPointerValue (s, t);
}
private CoreGenericCall call(SourceSpan s, CoreGenericFunction definition, SemanticType t, CoreValue value) {
	var types = new GenericArray<SemanticType> ();
	types.add (t);
	var values = new GenericArray<CoreValue> ();
	values.add (value);
	return new CoreGenericCall (s, t, definition, types, values);
}
private CoreProgram sample(int recursion = 0, bool unused = false) {
	var s = span ();
	var types = new BuiltinTypes ();
	var identity = definition (s, "id", 0);
	var root_body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	var roots = new GenericArray<CoreFunction> ();
	roots.add (new CoreFunction (s, s, "root", types.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), root_body));
	var result = new CoreProgram (s, roots);
	result.generic_functions.add (identity);
	if (recursion != 0) {
		var other = recursion == 1 ? identity : definition (s, "other", 1);
		if (recursion == 2) {
			result.generic_functions.add (other);
		}
		foreach (var origin in result.generic_functions) {
			var callee = origin == identity ? other : identity;
			origin.body.statements.remove_index (1);
			origin.body.statements.add (new CoreReturn (s, call (s, callee, origin.return_type, new CoreLoadValue (s, origin.locals[0]))));
		}
	}
	if (!unused) {
		foreach (var type in new SemanticType[] {types.int_type, types.i32_type, types.i8_type, types.u8_type, types.i16_type, types.u16_type, types.u32_type, types.f32_type, types.f64_type, types.raw_pointer_type, types.vector_of (types.i16_type, 8), types.vector_of (types.u16_type, 8), types.vector_of (types.bool_type, 16), types.bool_type}) {
			var c = call (s, identity, type, constant (s, type));
			root_body.statements.add (new CoreGenericCallStatement (s, identity, c.type_arguments, c.arguments));
		}
	}
	root_body.statements.add (new CoreReturn (s, null));
	return result;
}
}
