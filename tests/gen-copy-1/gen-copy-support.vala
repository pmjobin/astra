// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenericCopyCore {
private GenericArray<SemanticType> arguments(SemanticType type) {
	var result = new GenericArray<SemanticType> ();
	result.add (type);
	return result;
}
private CoreProgram sample() {
	var s = SourceSpan (new SourceFile.from_text ("independent-copy-model", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var record = new CoreStruct (s, s, "Record", new StructType ("Record"), 0);
	record.fields.add (new CoreStructField (s, s, "x", record, types.int_type, 0));
	var bt = new TypeParameterType ("B");
	var bparams = new GenericArray<CoreTypeParameter> ();
	bparams.add (new CoreTypeParameter (s, bt, 0));
	var box = new CoreGenericStruct (s, s, "Box", bparams, 0);
	box.fields.add (new CoreGenericStructField (s, s, "value", box, bt, 0));
	var t = new TypeParameterType ("T");
	var tparams = new GenericArray<CoreTypeParameter> ();
	tparams.add (new CoreTypeParameter (s, t, 0));
	var params = new GenericArray<CoreParameter> ();
	var input = new CoreParameter (s, s, "input", t, 0);
	params.add (input);
	var local = new CoreLocalPlace (s, s, "first", box.application (arguments (t)), 0);
	var copy = new CoreLocalPlace (s, s, "second", local.semantic_type, 1);
	var saved = new CoreLocalPlace (s, s, "saved", t, 2);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (local);
	locals.add (copy);
	locals.add (saved);
	var first = new CoreGenericStructFieldPlace (s, local, box.fields[0]);
	var second = new CoreGenericStructFieldPlace (s, copy, box.fields[0]);
	var body = new CoreBlock (s, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreInitialize (s, first, new CoreParameterValue (s, input)));
	body.statements.add (new CoreStructCopy (s, copy, local, local.semantic_type, true));
	body.statements.add (new CoreInitialize (s, saved, new CoreLoadValue (s, second)));
	body.statements.add (new CoreStore (s, second, new CoreParameterValue (s, input)));
	body.statements.add (new CoreReturn (s, new CoreLoadValue (s, saved)));
	var generic = new CoreGenericFunction (s, s, "through_box", t, params, locals, body, null, tparams, 0);
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
	values.add (new CoreStructArgument (s, input, new CoreStructSnapshot (s, source)));
	root_body.statements.add (new CoreStructResultStore (s, target, new CoreStructCallResult (s, record.semantic_type, generic, values, null, arguments (record.semantic_type)), true));
	root_body.statements.add (new CoreReturn (s, new CoreLoadValue (s, tf)));
	var root = new CoreFunction (s, s, "root", types.int_type, new GenericArray<CoreParameter> (), root_locals, root_body);
	root.field_places.add (sf);
	root.field_places.add (tf);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (root);
	var records = new GenericArray<CoreStruct> ();
	records.add (record);
	var program = new CoreProgram (s, functions, null, null, records);
	program.generic_structs.add (box);
	program.generic_functions.add (generic);
	return program;
}
}
