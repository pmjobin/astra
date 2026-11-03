// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.GenericBorrow {
private const string SOURCE = "class C{init(){}}int borrow<T>(borrowed T v,int n) where T:Ownable{return n;}int consume<T>(owned T v) where T:Ownable{return 0;}void use<T>(owned T v) where T:Ownable{borrow<T>(v,0);consume<T>(move v);}int main(){owned C c=C.init();use<C>(move c);return 42;}";
private CoreProgram core(string source = SOURCE) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("generic-borrow-control", source));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	var result = CoreBuilder.build (checked.program);
	CoreVerifier.verify (result);
	return result;
}

private void rejected(CoreProgram program, string text) {
	bool failed = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		failed = error.message.contains (text);
		if (!failed) {
			GLib.error ("unexpected Core rejection: %s", error.message);
		}
	}
	assert (failed);
}

private void interval(bool nested) throws GLib.Error {
	var program = core ();
	var body = program.generic_functions[2].body;
	var loan = (CoreGenericCallStatement) body.statements[1];
	var consume = (CoreGenericCallStatement) body.statements[2];
	if (nested) {
		var original = loan.arguments[1];
		loan.arguments[1] = new CoreGenericCall (consume.span, consume.target.return_type, (CoreGenericFunction) consume.target, consume.type_arguments, consume.arguments);
		rejected (program, "use of moved owned value");
		loan.arguments[1] = original;
	} else {
		body.statements[1] = consume;
		body.statements[2] = loan;
		rejected (program, "use of moved owned value");
		body.statements[1] = loan;
		body.statements[2] = consume;
	}
	CoreVerifier.verify (program);
}

private void boundary() throws GLib.Error {
	var program = core ();
	var call = (CoreGenericCallStatement) program.generic_functions[2].body.statements[1];
	var original = (CoreOwnedBorrowValue) call.arguments[0];
	var parameter = original.parameter;
	call.arguments[0] = new CoreOwnedBorrowValue (call.span, original.source, new CoreParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal, PointerParameterContract.BORROWED_NOESCAPE));
	rejected (program, "owner borrow requires exact");
	call.arguments[0] = original;
	CoreVerifier.verify (program);
}

private void escape() throws GLib.Error {
	var program = core ();
	var function = program.generic_functions[0];
	var original = function.body.statements[0];
	function.body.statements[0] = new CoreReturn (function.span, new CoreParameterValue (function.span, function.parameters[0]));
	rejected (program, "plain Ownable T values");
	function.body.statements[0] = original;
	CoreVerifier.verify (program);
}

private void acquire() throws GLib.Error {
	var program = core ();
	var function = program.generic_functions[0];
	var parameter = function.parameters[0];
	var cleanup = new CoreCleanupContract.for_parameter ((TypeParameterType) parameter.semantic_type, function.span, program.cleanups.length);
	program.cleanups.add (cleanup);
	var place = new CoreLocalPlace (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, function.locals.length, false, parameter);
	function.locals.add (place);
	var owner = new CoreOwnedLocal (function.span, place, cleanup, function.body);
	function.owned_locals.add (owner);
	function.body.statements.insert (0, new CoreAcquireParameter (function.span, owner, parameter));
	rejected (program, "owned");
	function.body.statements.remove_index (0);
	function.owned_locals.remove_index (function.owned_locals.length - 1);
	function.locals.remove_index (function.locals.length - 1);
	program.cleanups.remove_index (program.cleanups.length - 1);
	CoreVerifier.verify (program);
}

private void signature() throws GLib.Error {
	var program = core ();
	var function = program.generic_functions[0];
	function.parameters.add (new CoreParameter (function.span, function.span, "other", function.parameters[0].semantic_type, function.parameters.length, PointerParameterContract.BORROWED_NOESCAPE));
	rejected (program, "requires one borrowed T");
	function.parameters.remove_index (function.parameters.length - 1);
	CoreVerifier.verify (program);
}

private void concrete_flow() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (core ()));
	CfgVerifier.verify (cfg);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	bool tested = false;
	foreach (var function in cfg.functions) {
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var call = block.instructions[i] as CfgCallInstruction;
				if (call == null || !call.target.name.has_prefix ("astra.gen.0.")) {
					continue;
				}
				block.instructions.remove_index (i);
				int moved = -1;
				for (int j = i; j < block.instructions.length; j++) {
					if (block.instructions[j] is CfgCleanupInstruction) {
						moved = j;
						break;
					}
				}
				assert (moved >= 0);
				block.instructions.insert (moved, call);
				CfgVerifier.verify (cfg);
				var result = CfgFlowChecker.check (cfg);
				assert (result.diagnostic != null && result.diagnostic.message.contains ("cannot borrow moved"));
				block.instructions.remove_index (moved);
				block.instructions.insert (i, call);
				CfgVerifier.verify (cfg);
				assert (CfgFlowChecker.check (cfg).diagnostic == null);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		if (tested) {
			break;
		}
	}
	assert (tested);
}

private void nominal() throws GLib.Error {
	var program = core ("class C{init(){}}class D{init(){}}void borrow<T>(borrowed T v) where T:Ownable{}int main(){owned C c=C.init();owned D d=D.init();borrow<C>(c);borrow<D>(d);return 42;}");
	var ssa = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (program)));
	SsaVerifier.verify (ssa);
	var native = NativeAbiBuilder.build (ssa);
	var correspondence = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	for (int i = 0; i < ssa.functions.length; i++) {
		correspondence.insert (ssa.functions[i], native.functions[i]);
	}
	NativeAbiValidator.validate_ssa_calls (ssa, native, correspondence);
	SsaCallInstruction? first = null;
	SsaCallInstruction? second = null;
	foreach (var block in ssa.functions[0].blocks) {
		foreach (var instruction in block.instructions) {
			var call = instruction as SsaCallInstruction;
			if (call == null || !call.target.name.has_prefix ("astra.gen.0.")) {
				continue;
			}
			if (first == null) {
				first = call;
			} else {
				second = call;
			}
		}
	}
	assert (first != null && second != null && first.arguments[0].semantic_type != second.arguments[0].semantic_type);
	var original = first.arguments[0];
	first.arguments[0] = second.arguments[0];
	bool failed = false;
	try {
		SsaVerifier.verify (ssa);
	} catch (SsaError error) {
		failed = error.message.contains ("argument");
	}
	assert (failed);
	failed = false;
	try {
		NativeAbiValidator.validate_ssa_calls (ssa, native, correspondence);
	} catch (NativeAbiError error) {
		failed = error.message.contains ("exact semantic ClassType");
	}
	assert (failed);
	first.arguments[0] = original;
	SsaVerifier.verify (ssa);
	NativeAbiValidator.validate_ssa_calls (ssa, native, correspondence);
	var signature = correspondence.lookup (first.target).signature;
	var channel = signature.parameters[0];
	signature.parameters[0] = new NativeParameter (channel.span, channel.name_span, channel.name, channel.ordinal, NativeScalarType.I32);
	NativeAbiVerifier.verify (native);
	failed = false;
	try {
		NativeAbiValidator.validate_ssa_calls (ssa, native, correspondence);
	} catch (NativeAbiError error) {
		failed = error.message.contains ("parameter channel type");
	}
	assert (failed);
	signature.parameters[0] = channel;
	NativeAbiValidator.validate_ssa_calls (ssa, native, correspondence);
}

private void async_context() throws GLib.Error {
	var program = core ("[ExceptionRoot]class Error{readonly string text;init(string s){this.text=s;}virtual property string message{get{return this.text;}}}class AsyncError:Error{init(string s):base(s){}}enum RunStatus{Completed,Cancelled}async runtime VirtualExecutor throws AsyncError returns RunStatus;class C{init(){}}int borrow<T>(borrowed T v,int n) where T:Ownable{return n;}async int work(){return 0;}int main(){return 42;}");
	var function = program.functions[0];
	assert (function.async_body != null);
	var loan = program.generic_functions[0];
	var types = new GenericArray<SemanticType> ();
	types.add (program.classes[2].semantic_type);
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreNullPointerValue (function.span, program.classes[2].semantic_type));
	arguments.add (((CoreReturn) function.body.statements[0]).value);
	function.body.statements.insert (0, new CoreGenericCallStatement (function.span, loan, types, arguments));
	rejected (program, "requires a synchronous caller");
	function.body.statements.remove_index (0);
	CoreVerifier.verify (program);
}

private delegate void Check() throws GLib.Error;
private void run(Check check) {
	try {
		check ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-borrow-1/core/owner-read-after-move", () => { run (() => { interval (false);
	});
	});
	Test.add_func ("/gen-borrow-1/core/nested-consume-during-loan", () => { run (() => { interval (true);
	});
	});
	Test.add_func ("/gen-borrow-1/core/exact-boundary", () => { run (boundary);
	});
	Test.add_func ("/gen-borrow-1/core/no-escape", () => { run (escape);
	});
	Test.add_func ("/gen-borrow-1/core/no-acquisition", () => { run (acquire);
	});
	Test.add_func ("/gen-borrow-1/core/bounded-signature", () => { run (signature);
	});
	Test.add_func ("/gen-borrow-1/cfg/through-invocation-liveness", () => { run (concrete_flow);
	});
	Test.add_func ("/gen-borrow-1/ssa-native/nominal-and-physical-identity", () => { run (nominal);
	});
	Test.add_func ("/gen-borrow-1/core/no-coroutine-loans", () => { run (async_context);
	});
	return Test.run ();
}

}
