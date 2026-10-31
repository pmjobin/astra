// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
namespace Astra.Tests.GenericBufferCore {
private CoreProgram sample() {
	var span = SourceSpan (new SourceFile.from_text ("independent-buffer-model", "x"), 0, 1);
	var types = new BuiltinTypes ();
	var t = new TypeParameterType ("T");
	var symbolic = types.slice_of (t);
	var concrete = types.slice_of (types.int_type);
	var cleanup = new CoreCleanupContract.for_buffer (new BufferValueShape (symbolic, types.raw_pointer_type, types.i32_type), span, 0);
	var realized = new CoreCleanupContract.for_buffer (new BufferValueShape (concrete, types.raw_pointer_type, types.i32_type), span, 1);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (cleanup);
	cleanups.add (realized);
	var parameters = new GenericArray<CoreParameter> ();
	var count = new CoreParameter (span, span, "count", types.int_type, 0);
	parameters.add (count);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var place = new CoreLocalPlace (span, span, "values", symbolic, 0);
	var saved = new CoreLocalPlace (span, span, "saved", t, 1);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (place);
	locals.add (saved);
	var owner = new CoreOwnedLocal (span, place, cleanup, body);
	body.statements.add (new CoreInitialize (span, place, new CoreOwnedBufferAllocate (span, symbolic, new CoreParameterValue (span, count), cleanup), owner));
	var index = new CoreIntegerValue.typed (span, types.int_type, AstraIntegerValue.from_int64 ((IntegerType) types.int_type, 0));
	var element = new CoreSliceElementPlace (span, new CoreOwnedBufferBorrow (span, owner, null), symbolic, index, new DataPointerProvenance (DataPointerOrigin.LOCAL, 0, 0));
	body.statements.add (new CoreInitialize (span, saved, new CoreLoadValue (span, element)));
	body.statements.add (new CoreOwnershipReturn (span, symbolic, cleanup, owner));
	var type_parameters = new GenericArray<CoreTypeParameter> ();
	type_parameters.add (new CoreTypeParameter (span, t, 0));
	var factory = new CoreGenericFunction (span, span, "make", symbolic, parameters, locals, body, cleanup, type_parameters, 0);
	factory.element_obligations.require (t);
	factory.owned_locals.add (owner);
	var root_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var root_place = new CoreLocalPlace (span, span, "received", concrete, 0);
	var root_owner = new CoreOwnedLocal (span, root_place, realized, root_body);
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreIntegerValue.typed (span, types.int_type, AstraIntegerValue.from_int64 ((IntegerType) types.int_type, 2)));
	var types_list = new GenericArray<SemanticType> ();
	types_list.add (types.int_type);
	var call = new CoreGenericCall (span, concrete, factory, types_list, arguments);
	root_body.statements.add (new CoreInitialize (span, root_place, call, root_owner));
	root_body.statements.add (new CoreReturn (span, index));
	var root_locals = new GenericArray<CoreLocalPlace> ();
	root_locals.add (root_place);
	var root = new CoreFunction (span, span, "root", types.int_type, new GenericArray<CoreParameter> (), root_locals, root_body);
	root.owned_locals.add (root_owner);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (root);
	var program = new CoreProgram (span, functions, null, null, null, cleanups);
	program.generic_functions.add (factory);
	return program;
}
}
