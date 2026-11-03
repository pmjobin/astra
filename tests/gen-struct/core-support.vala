// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenStructCore {
private SourceSpan span() {
	return SourceSpan (new SourceFile.from_text ("generic-struct", "x"), 0, 1);
}

private GenericArray<SemanticType> arguments(SemanticType first, SemanticType? second = null) {
	var result = new GenericArray<SemanticType> ();
	result.add (first);
	if (second != null) {
		result.add (second);
	}
	return result;
}

private CoreGenericStruct definition(string name, int arity, int ordinal) {
	var s = span ();
	var parameters = new GenericArray<CoreTypeParameter> ();
	for (int i = 0; i < arity; i++) {
		parameters.add (new CoreTypeParameter (s, new TypeParameterType ("T%d".printf (i)), i));
	}
	return new CoreGenericStruct (s, s, name, parameters, ordinal);
}

private void field(CoreGenericStruct owner, string name, SemanticType type) {
	owner.fields.add (new CoreGenericStructField (owner.span, owner.name_span, name, owner, type, owner.fields.length));
}

private CoreFunction root(BuiltinTypes types) {
	var s = span ();
	return new CoreFunction (s, s, "root", types.void_type, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), new CoreBlock (s, new GenericArray<CoreStatement> ()));
}

private CoreValue constant(SemanticType type) {
	var s = span ();
	if (type is IntegerType) {
		return new CoreIntegerValue.typed (s, type, AstraIntegerValue.from_int64 ((IntegerType) type, 7));
	}
	if (type is FloatingType) {
		return new CoreFloatValue (s, type, BinaryFloatValue.from_decimal (((FloatingType) type).format, "1.25"));
	}
	if (type.kind == TypeKind.BOOL) {
		return new CoreBooleanValue (s, type, BooleanLiteral.TRUE);
	}
	if (type is VectorType) {
		var lanes = new GenericArray<CoreValue> ();
		for (int i = 0; i < ((VectorType) type).lane_count; i++) {
			lanes.add (constant (((VectorType) type).element_type));
		}
		return new CoreVectorConstructValue (s, type, lanes);
	}
	return new CoreNullPointerValue (s, type);
}

private CoreProgram sample(bool addressed = false, bool unused = false) {
	var types = new BuiltinTypes ();
	var s = span ();
	var pair = definition ("Pair", 2, 0);
	field (pair, "first", pair.type_parameters[0].semantic_type);
	field (pair, "second", pair.type_parameters[1].semantic_type);
	var bundle = definition ("Bundle", 1, 1);
	var bt = bundle.type_parameters[0].semantic_type;
	field (bundle, "pair", pair.application (arguments (bt, bt)));
	field (bundle, "tag", types.int_type);
	var ft = new TypeParameterType ("F");
	var type_parameters = new GenericArray<CoreTypeParameter> ();
	type_parameters.add (new CoreTypeParameter (s, ft, 0));
	var parameters = new GenericArray<CoreParameter> ();
	var parameter = new CoreParameter (s, s, "value", ft, 0);
	parameters.add (parameter);
	var locals = new GenericArray<CoreLocalPlace> ();
	var local = new CoreLocalPlace (s, s, "bundle", bundle.application (arguments (ft)), 0);
	locals.add (local);
	var nested = new CoreGenericStructFieldPlace (s, local, bundle.fields[0]);
	var first = new CoreGenericStructFieldPlace (s, nested, pair.fields[0]);
	var second = new CoreGenericStructFieldPlace (s, nested, pair.fields[1]);
	var tag = new CoreGenericStructFieldPlace (s, local, bundle.fields[1]);
	var children = new GenericArray<CoreStatement> ();
	children.add (new CoreInitialize (s, first, new CoreParameterValue (s, parameter)));
	children.add (new CoreInitialize (s, second, new CoreParameterValue (s, parameter)));
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreStructInitialize (s, nested, children));
	body.statements.add (new CoreInitialize (s, tag, constant (types.int_type)));
	var direct = new CoreLocalPlace (s, s, "direct", pair.application (arguments (ft, ft)), 1);
	locals.add (direct);
	foreach (var member in pair.fields) {
		body.statements.add (new CoreInitialize (s, new CoreGenericStructFieldPlace (s, direct, member), new CoreParameterValue (s, parameter)));
	}
	body.statements.add (new CoreReturn (s, new CoreLoadValue (s, second)));
	var function = new CoreGenericFunction (s, s, "nested", ft, parameters, locals, body, null, type_parameters, 0);
	var root = root (types);
	var roots = new GenericArray<CoreFunction> ();
	roots.add (root);
	var program = new CoreProgram (s, roots);
	program.generic_structs.add (pair);
	program.generic_structs.add (bundle);
	program.generic_functions.add (function);
	if (!unused) {
		var application = pair.application (arguments (types.f64_type, types.f64_type));
		var storage = new CoreLocalPlace (s, s, "shared", application, 0, addressed);
		root.locals.add (storage);
		foreach (var member in pair.fields) {
			root.body.statements.add (new CoreInitialize (s, new CoreGenericStructFieldPlace (s, storage, member), constant (types.f64_type)));
		}
		if (addressed) {
			var pointer = new CoreLocalPlace (s, s, "pointer", types.pointer_to (application), 1);
			root.locals.add (pointer);
			var provenance = new DataPointerProvenance (DataPointerOrigin.LOCAL, 0, 0);
			root.body.statements.add (new CoreInitialize (s, pointer, new CoreAddressOfValue (s, pointer.semantic_type, storage, provenance)));
			var dereference = new CoreDereferencePlace (s, new CoreLoadValue (s, pointer), application, provenance);
			root.body.statements.add (new CoreStore (s, new CoreGenericStructFieldPlace (s, dereference, pair.fields[0]), constant (types.f64_type)));
		}
		foreach (var type in new SemanticType[] {types.int_type, types.i32_type, types.i8_type, types.u8_type, types.f64_type, types.vector_of (types.i16_type, 8), types.vector_of (types.bool_type, 4)}) {
			var values = new GenericArray<CoreValue> ();
			values.add (constant (type));
			root.body.statements.add (new CoreGenericCallStatement (s, function, arguments (type), values));
		}
	}
	root.body.statements.add (new CoreReturn (s, null));
	return program;
}

}
