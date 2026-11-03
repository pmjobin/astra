// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenericSliceCore {
private GenericArray<SemanticType> arguments(SemanticType type) {
	var result = new GenericArray<SemanticType> ();
	result.add (type);
	return result;
}

private CoreProgram sample() {
	var s = SourceSpan (new SourceFile.from_text ("independent-slice-model", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var record = new CoreStruct (s, s, "Record", new StructType ("Record"), 0);
	record.fields.add (new CoreStructField (s, s, "x", record, types.int_type, 0));
	var t = new TypeParameterType ("T");
	var tparams = new GenericArray<CoreTypeParameter> ();
	tparams.add (new CoreTypeParameter (s, t, 0));
	var slice = types.slice_of (t);
	var params = new GenericArray<CoreParameter> ();
	var value = new CoreParameter (s, s, "value", t, 0);
	var view = new CoreParameter (s, s, "view", slice, 1, PointerParameterContract.BORROWED_NOESCAPE);
	params.add (value);
	params.add (view);
	var alias = new CoreLocalPlace (s, s, "alias", slice, 0);
	var saved = new CoreLocalPlace (s, s, "saved", t, 1);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (alias);
	locals.add (saved);
	var index = new CoreIntegerValue.typed (s, types.int_type, AstraIntegerValue.from_int64 ((IntegerType) types.int_type, 0));
	var place = new CoreSliceElementPlace (s, new CoreLoadValue (s, alias), slice, index, new DataPointerProvenance (DataPointerOrigin.PARAMETER, 1, 0));
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreInitialize (s, alias, new CoreParameterValue (s, view)));
	body.statements.add (new CoreInitialize (s, saved, new CoreLoadValue (s, place)));
	body.statements.add (new CoreStore (s, place, new CoreParameterValue (s, value)));
	body.statements.add (new CoreReturn (s, new CoreLoadValue (s, saved)));
	var generic = new CoreGenericFunction (s, s, "exchange", t, params, locals, body, null, tparams, 0);
	generic.element_obligations.require (t);
	var root_parameters = new GenericArray<CoreParameter> ();
	var incoming = new CoreParameter (s, s, "incoming", types.slice_of (record.semantic_type), 0, PointerParameterContract.BORROWED_NOESCAPE);
	root_parameters.add (incoming);
	var root_locals = new GenericArray<CoreLocalPlace> ();
	var source = new CoreLocalPlace (s, s, "source", record.semantic_type, 0);
	var target = new CoreLocalPlace (s, s, "target", record.semantic_type, 1);
	root_locals.add (source);
	root_locals.add (target);
	var sf = new CoreFieldPlace (s, source, record.fields[0]);
	var tf = new CoreFieldPlace (s, target, record.fields[0]);
	var root_body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	root_body.statements.add (new CoreInitialize (s, sf, new CoreIntegerValue.typed (s, types.int_type, AstraIntegerValue.from_int64 ((IntegerType) types.int_type, 42))));
	var values = new GenericArray<CoreValue> ();
	values.add (new CoreStructArgument (s, value, new CoreStructSnapshot (s, source)));
	values.add (new CoreParameterValue (s, incoming));
	root_body.statements.add (new CoreStructResultStore (s, target, new CoreStructCallResult (s, record.semantic_type, generic, values, null, arguments (record.semantic_type)), true));
	root_body.statements.add (new CoreReturn (s, new CoreLoadValue (s, tf)));
	var root = new CoreFunction (s, s, "root", types.int_type, root_parameters, root_locals, root_body);
	root.field_places.add (sf);
	root.field_places.add (tf);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (root);
	var records = new GenericArray<CoreStruct> ();
	records.add (record);
	var program = new CoreProgram (s, functions, null, null, records);
	program.generic_functions.add (generic);
	return program;
}

}
