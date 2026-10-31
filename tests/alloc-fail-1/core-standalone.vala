// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;

namespace Astra.Tests.AllocationFailureCore {
private CoreProgram sample(int variant = 0) {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("independent-allocation-action", "x"), 0, 1);
	var parameter = new TypeParameterType ("T");
	var slice = types.slice_of (parameter);
	var concrete = types.slice_of (types.int_type);
	var symbolic_cleanup = new CoreCleanupContract.for_buffer (new BufferValueShape (slice, types.raw_pointer_type, types.i32_type), span, 0);
	var concrete_cleanup = new CoreCleanupContract.for_buffer (new BufferValueShape (concrete, types.raw_pointer_type, types.i32_type), span, 1);
	var cleanups = new GenericArray<CoreCleanupContract> ();
	cleanups.add (symbolic_cleanup);
	cleanups.add (concrete_cleanup);
	var report_parameters = new GenericArray<CoreParameter> ();
	report_parameters.add (new CoreParameter (span, span, "code", types.int_type, 0));
	report_parameters.add (new CoreParameter (span, span, "count", types.int_type, 1));
	var report_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var zero = new CoreIntegerValue.typed (span, types.int_type, AstraIntegerValue.from_int64 (types.i32_type, 0));
	report_body.statements.add (new CoreReturn (span, variant == 3 ? zero : null));
	var reporter = new CoreFunction (span, span, "report", variant == 3 ? types.int_type : types.void_type, report_parameters, new GenericArray<CoreLocalPlace> (), report_body);
	var arguments = new GenericArray<CoreValue> ();
	var parameters = new GenericArray<CoreParameter> ();
	var count = new CoreParameter (span, span, "count", types.int_type, 0);
	var code = new CoreParameter (span, span, "code", types.int_type, 1);
	parameters.add (count);
	parameters.add (code);
	arguments.add (new CoreParameterValue (span, variant == 4 ? report_parameters[0] : code));
	if (variant != 1) {
		arguments.add (variant == 2 ? (CoreValue) new CoreBooleanValue (span, types.bool_type, BooleanLiteral.TRUE) : new CoreParameterValue (span, count));
	}
	CoreStatement action = variant == 5 ? (CoreStatement) new CoreReturn (span, null) : new CoreCallStatement (span, reporter, arguments);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	body.statements.add (new CoreOwnershipReturn (span, slice, symbolic_cleanup, null, new CoreOwnedBufferAllocate (span, slice, new CoreParameterValue (span, count), symbolic_cleanup, action)));
	var formals = new GenericArray<CoreTypeParameter> ();
	formals.add (new CoreTypeParameter (span, parameter, 0));
	var factory = new CoreGenericFunction (span, span, "make", slice, parameters, new GenericArray<CoreLocalPlace> (), body, symbolic_cleanup, formals, 0);
	factory.element_obligations.require (parameter);
	var functions = new GenericArray<CoreFunction> ();
	functions.add (reporter);
	for (int i = 0; i < 2; i++) {
		var values = new GenericArray<CoreValue> ();
		values.add (zero);
		values.add (new CoreIntegerValue.typed (span, types.int_type, AstraIntegerValue.from_int64 (types.i32_type, 17 + i)));
		var actual_types = new GenericArray<SemanticType> ();
		actual_types.add (types.int_type);
		var root_body = new CoreBlock (span, new GenericArray<CoreStatement> ());
		root_body.statements.add (new CoreOwnershipReturn (span, concrete, concrete_cleanup, null, new CoreGenericCall (span, concrete, factory, actual_types, values)));
		functions.add (new CoreFunction (span, span, "root" + i.to_string (), concrete, new GenericArray<CoreParameter> (), new GenericArray<CoreLocalPlace> (), root_body, concrete_cleanup));
	}
	var result = new CoreProgram (span, functions, null, null, null, cleanups);
	result.generic_functions.add (factory);
	return result;
}
private void qualify() {
	try {
		CoreProgram? symbolic = sample ();
		CoreVerifier.verify (symbolic);
		var definition = WeakRef (symbolic.generic_functions[0]);
		var parameter = WeakRef (symbolic.generic_functions[0].parameters[0]);
		var universe = WeakRef (symbolic.generic_functions[0].element_obligations);
		var concrete = CoreGenericMonomorphizer.build (symbolic);
		symbolic = null;
		assert (definition.get () == null && parameter.get () == null && universe.get () == null);
		CoreVerifier.verify_concrete (concrete);
		assert (concrete.functions.length == 4); // Both dynamic codes share one exact specialization.
		var instance = concrete.functions[3];
		var allocation = (CoreOwnedBufferAllocate) ((CoreOwnershipReturn) instance.body.statements[0]).producer;
		var action = (CoreCallStatement) allocation.failure_call;
		assert (((CoreParameterValue) action.arguments[0]).parameter == instance.parameters[1]);
		assert (((CoreParameterValue) action.arguments[1]).parameter == instance.parameters[0]);
		action.arguments[0] = new CoreParameterValue (action.span, concrete.functions[0].parameters[0]);
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (concrete);
		} catch (CoreError error) {
			Test.message ("remap: %s", error.message);
			rejected = true;
		}
		assert (rejected);
	} catch (CoreError error) {
		GLib.error ("%s", error.message);
	}
	for (int variant = 1; variant <= 5; variant++) {
		bool rejected = false;
		try {
			CoreVerifier.verify (sample (variant));
		} catch (CoreError error) {
			Test.message ("variant %d: %s", variant, error.message);
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/alloc-fail/core/independent-call-remapping-lifetimes-and-keys", qualify);
	return Test.run ();
}
}
