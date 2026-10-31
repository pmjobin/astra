// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.GenericHeapForward {
private const string SOURCE = "class C{init(){}}void sink<T>(owned T value,int n) where T:Ownable{}void loan<T>(borrowed T value) where T:Ownable{}void relay<T>(owned T value,int n) where T:Ownable{loan<T>(value);sink<T>(move value,n);}void outer<T>(int n,owned T value) where T:Ownable{relay<T>(move value,n);}int main(){owned C lexical=C.init();var heap=new C();outer<C>(1,move lexical);outer<C>(2,move heap);return 42;}";
private CheckedProgram checked() {
	var parsed = Parser.parse (new SourceFile.from_text ("heap-forward-control", SOURCE));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.diagnostic == null);
	return result.program;
}
private CoreProgram core() throws GLib.Error {
	var result = CoreBuilder.build (checked ());
	CoreVerifier.verify (result);
	return result;
}
private void rejects(CoreProgram program, string text) {
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
private CoreFunction function(CoreProgram program, string name, bool heap = false) {
	foreach (var candidate in program.generic_functions) {
		if (candidate.name == name) {
			return candidate;
		}
	}
	foreach (var candidate in program.functions) {
		if (candidate.generic_instance != null && candidate.generic_instance.origin.name == name && (candidate.generic_instance.heap_owned_parameter >= 0) == heap) {
			return candidate;
		}
	}
	assert_not_reached ();
}
private CoreCallStatement outgoing(CoreFunction function) {
	foreach (var statement in function.body.statements) {
		var call = statement as CoreCallStatement;
		if (call != null) {
			foreach (var argument in call.arguments) {
				if (argument is CoreOwnedArgumentValue) {
					return call;
				}
			}
		}
	}
	assert_not_reached ();
}
private void semantic_owner() {
	var parsed = Parser.parse (new SourceFile.from_text ("forged-source-owner", "class C{init(){}}void sink<T>(owned T v) where T:Ownable{}void relay<T>(owned T v) where T:Ownable{sink<T>(move v);}void bad(C alias){relay<C>(move alias);}int main(){return 42;}"));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.diagnostic != null && result.diagnostic.message.contains ("nontransferable"));
	assert (checked () != null);
}
private void checked_eligibility() throws GLib.Error {
	var program = checked ();
	CheckedGenericFunction? relay = null;
	foreach (var candidate in program.generic_functions) {
		if (candidate.definition.name == "relay") {
			relay = candidate;
		}
	}
	assert (relay != null);
	var original = relay.body.statements[1] as CheckedGenericCallStatement;
	assert (original != null);
	var owned = original.arguments[0] as CheckedOwnedArgument;
	assert (owned != null);
	var arguments = new GenericArray<CheckedExpression> ();
	arguments.add (new CheckedOwnedArgument (owned.span, relay.definition.parameters[0], null, owned.transfer));
	arguments.add (original.arguments[1]);
	relay.body.statements[1] = new CheckedGenericCallStatement (original.span, relay.definition, original.type_arguments, arguments);
	// Core reconstructs the valid recursive transfer independently of this flag.
	int ordinal = relay.definition.heap_consumer_parameter;
	relay.definition.heap_consumer_parameter = 0;
	CoreVerifier.verify (CoreBuilder.build (program));
	relay.body.statements[1] = original;
	relay.definition.heap_consumer_parameter = ordinal;
	CoreVerifier.verify (CoreBuilder.build (program));
}
private void core_parameter(bool source) throws GLib.Error {
	var program = core ();
	var relay = function (program, "relay");
	var call = outgoing (relay);
	var original = (CoreOwnedArgumentValue) call.arguments[0];
	call.arguments[0] = new CoreOwnedArgumentValue (original.span, source ? original.parameter : call.target.parameters[1], original.cleanup, source ? function (program, "outer").owned_locals[0] : original.source, original.semantic_type);
	rejects (program, source ? "local" : "exact target parameter");
	call.arguments[0] = original;
	CoreVerifier.verify (program);
}
private void core_acquisition() throws GLib.Error {
	var program = core ();
	var relay = function (program, "relay");
	var acquire = relay.body.statements[0];
	relay.body.statements.remove_index (0);
	rejects (program, "owned-parameter");
	relay.body.statements.insert (0, acquire);
	CoreVerifier.verify (program);
}
private void core_dead_second_site() throws GLib.Error {
	var program = core ();
	var relay = function (program, "relay");
	var call = (CoreGenericCallStatement) outgoing (relay);
	var original = (CoreOwnedArgumentValue) call.arguments[0];
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (original.span, original.parameter, original.cleanup, original.source, original.semantic_type));
	arguments.add (call.arguments[1]);
	relay.body.statements.add (new CoreReturn (relay.span, null));
	relay.body.statements.add (new CoreGenericCallStatement (call.span, (CoreGenericFunction) call.target, call.type_arguments, arguments));
	// The second call is unreachable after return.
	CoreVerifier.verify (program);
	relay.body.statements.remove_index (relay.body.statements.length - 1);
	relay.body.statements.remove_index (relay.body.statements.length - 1);
	CoreVerifier.verify (program);
}
private CoreProgram concrete() throws GLib.Error {
	var result = CoreGenericMonomorphizer.build (core ());
	CoreVerifier.verify_concrete (result);
	return result;
}
private void concrete_cycle() throws GLib.Error {
	var program = concrete ();
	var relay = function (program, "relay", true);
	var call = outgoing (relay);
	var original = (CoreOwnedArgumentValue) call.arguments[0];
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (original.span, relay.parameters[0], original.cleanup, original.source));
	arguments.add (call.arguments[1]);
	int site = -1;
	for (int i = 0; i < relay.body.statements.length; i++) {
		if (relay.body.statements[i] == call) {
			site = i;
		}
	}
	assert (site >= 0);
	relay.body.statements[site] = new CoreCallStatement (call.span, relay, arguments);
	CoreVerifier.verify_concrete (program);
	relay.body.statements[site] = call;
	CoreVerifier.verify_concrete (program);
}
private void concrete_domain(bool key) throws GLib.Error {
	var program = concrete ();
	var relay = function (program, "relay", true);
	if (key) {
		relay.parameters[0].heap_object = false;
		rejects (program, "canonical consuming storage domain");
		relay.parameters[0].heap_object = true;
	} else {
		var call = outgoing (relay);
		var lexical = function (program, "sink");
		var original = (CoreOwnedArgumentValue) call.arguments[0];
		var arguments = new GenericArray<CoreValue> ();
		arguments.add (new CoreOwnedArgumentValue (original.span, lexical.parameters[0], original.cleanup, original.source));
		arguments.add (call.arguments[1]);
		int site = -1;
		for (int i = 0; i < relay.body.statements.length; i++) {
			if (relay.body.statements[i] == call) {
				site = i;
			}
		}
		assert (site >= 0);
		relay.body.statements[site] = new CoreCallStatement (call.span, lexical, arguments);
		rejects (program, "exact target parameter");
		relay.body.statements[site] = call;
	}
	CoreVerifier.verify_concrete (program);
}
private void concrete_nominal() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("forged-generic-upcast", "class B{init(){}virtual int id(){return 1;}}class D:B{init():base(){}}void sink<T>(owned T v) where T:Ownable{}void relay<T>(owned T v) where T:Ownable{sink<T>(move v);}int main(){var b=new B();var d=new D();relay<B>(move b);relay<D>(move d);return 42;}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	var program = CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program));
	CoreVerifier.verify_concrete (program);
	CoreFunction? relay = null;
	CoreFunction? sink = null;
	foreach (var candidate in program.functions) {
		var identity = candidate.generic_instance;
		if (identity == null) {
			continue;
		}
		if (identity.origin.name == "relay" && identity.type_arguments[0].display_name () == "D") {
			relay = candidate;
		}
		if (identity.origin.name == "sink" && identity.type_arguments[0].display_name () == "B") {
			sink = candidate;
		}
	}
	assert (relay != null && sink != null);
	var original = outgoing (relay);
	var owned = (CoreOwnedArgumentValue) original.arguments[0];
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (owned.span, sink.parameters[0], sink.owned_locals[0].cleanup, owned.source, sink.parameters[0].semantic_type));
	relay.body.statements[1] = new CoreCallStatement (original.span, sink, arguments);
	rejects (program, "exact nominal source");
	relay.body.statements[1] = original;
	CoreVerifier.verify_concrete (program);
}
private CfgProgram cfg() throws GLib.Error {
	var result = CfgBuilder.build (concrete ());
	CfgVerifier.verify (result);
	assert (CfgFlowChecker.check (result).diagnostic == null);
	return result;
}
private CfgFunction cfg_relay(CfgProgram program) {
	foreach (var function in program.functions) {
		if (function.parameters.length != 2 || !function.parameters[0].heap_object) {
			continue;
		}
		foreach (var instruction in function.entry.instructions) {
			if (instruction is CfgOwnedCallTransferCommit) {
				return function;
			}
		}
	}
	assert_not_reached ();
}
private void cfg_commit() throws GLib.Error {
	var program = cfg ();
	var block = cfg_relay (program).entry;
	int site = -1;
	for (int i = 0; i < block.instructions.length; i++) {
		if (block.instructions[i] is CfgOwnedCallTransferCommit) {
			site = i;
			break;
		}
	}
	assert (site >= 0);
	var original = block.instructions[site];
	block.instructions.remove_index (site);
	bool failed = false;
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		failed = error.message.contains ("commit");
	}
	assert (failed);
	block.instructions.insert (site, original);
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}
private void cfg_moved_read() throws GLib.Error {
	var program = cfg ();
	var block = cfg_relay (program).entry;
	CfgOwnedBorrowInstruction? borrow = null;
	CfgCallInstruction? invocation = null;
	var original = new GenericArray<CfgInstruction> ();
	foreach (var instruction in block.instructions) {
		original.add (instruction);
		if (instruction is CfgOwnedBorrowInstruction) {
			borrow = (CfgOwnedBorrowInstruction) instruction;
		}
	}
	assert (borrow != null);
	foreach (var instruction in original) {
		var call = instruction as CfgCallInstruction;
		if (call != null && call.arguments.length == 1 && call.arguments[0] == borrow.result) {
			invocation = call;
		}
	}
	assert (invocation != null);
	while (block.instructions.length != 0) {
		block.instructions.remove_index (0);
	}
	bool moved = false;
	foreach (var instruction in original) {
		if (instruction == borrow || instruction == invocation) {
			continue;
		}
		block.instructions.add (instruction);
		if (instruction is CfgOwnedArgumentCapture) {
			assert (!moved);
			block.instructions.add (borrow);
			block.instructions.add (invocation);
			moved = true;
		}
	}
	assert (moved);
	CfgVerifier.verify (program);
	var result = CfgFlowChecker.check (program);
	assert (result.diagnostic != null && result.diagnostic.message.contains ("moved"));
	while (block.instructions.length != 0) {
		block.instructions.remove_index (0);
	}
	foreach (var instruction in original) {
		block.instructions.add (instruction);
	}
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}
private void cfg_double_acquire() throws GLib.Error {
	var program = cfg ();
	var entry = cfg_relay (program).entry;
	var incoming = entry.instructions[0] as CfgAcquireParameter;
	assert (incoming != null);
	entry.instructions.insert (1, new CfgAcquireParameter (incoming.span, (CfgLocalPlace) incoming.target, ((CfgParameterValue) incoming.value).parameter));
	bool failed = false;
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		failed = error.message.contains ("parameter acquisition");
	}
	assert (failed);
	entry.instructions.remove_index (1);
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}
private SsaProgram ssa() throws GLib.Error {
	var result = SsaBuilder.build (cfg ());
	SsaVerifier.verify (result);
	return result;
}
private void ssa_argument() throws GLib.Error {
	var program = ssa ();
	SsaCleanupContract? lexical = null;
	foreach (var cleanup in program.cleanups) {
		if (cleanup.is_object && !cleanup.is_heap_object) {
			lexical = cleanup;
		}
	}
	assert (lexical != null);
	bool tested = false;
	foreach (var function in program.functions) {
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call == null || call.owned_arguments.length == 0 || !call.owned_arguments[0].cleanup.is_heap_object || !function.name.has_prefix ("astra.gen.")) {
					continue;
				}
				var original = call.owned_arguments[0];
				call.owned_arguments[0] = new SsaOwnedArgument (original.span, original.parameter, original.value, lexical, original.source_ordinal, original.source_after_commit, original.source_storage);
				bool failed = false;
				try {
					SsaVerifier.verify (program);
				} catch (SsaError error) {
					failed = error.message.contains ("owned argument");
				}
				assert (failed);
				call.owned_arguments[0] = original;
				SsaVerifier.verify (program);
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
private void ssa_cleanup(bool duplicate) throws GLib.Error {
	var program = ssa ();
	SsaCleanupContract? lexical = null;
	foreach (var cleanup in program.cleanups) {
		if (cleanup.is_object && !cleanup.is_heap_object) {
			lexical = cleanup;
		}
	}
	assert (lexical != null);
	bool tested = false;
	foreach (var function in program.functions) {
		if (function.parameters.length != 2 || !function.parameters[0].heap_object) {
			continue;
		}
		bool forwards = false;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call != null && call.owned_arguments.length != 0) {
					forwards = true;
				}
			}
		}
		if (forwards) {
			continue;
		}
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var original = block.instructions[i] as SsaCleanupInstruction;
				if (original == null) {
					continue;
				}
				var forged = new SsaCleanupInstruction (original.span, original.value, duplicate ? original.cleanup : lexical);
				SsaHeapOwnerEvent? previous = null;
				int event_index = -1;
				if (duplicate) {
					block.instructions.insert (i + 1, forged);
				} else {
					block.instructions[i] = forged;
					for (int j = 0; j < block.instructions.length; j++) {
						var ended = block.instructions[j] as SsaHeapOwnerEvent;
						if (ended != null && ended.effect == original) {
							previous = ended;
							event_index = j;
							block.instructions[j] = new SsaHeapOwnerEvent (ended.span, ended.owner, ended.action, ended.value, forged);
							break;
						}
					}
					assert (previous != null);
				}
				bool failed = false;
				try {
					SsaVerifier.verify (program);
				} catch (SsaError error) {
					failed = error.message.contains (duplicate ? "cleanup" : "allocation domain");
					if (!failed) {
						GLib.error ("unexpected SSA rejection: %s", error.message);
					}
				}
				assert (failed);
				if (duplicate) {
					block.instructions.remove_index (i + 1);
				} else {
					block.instructions[i] = original;
					block.instructions[event_index] = previous;
				}
				SsaVerifier.verify (program);
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
private void native_domain() throws GLib.Error {
	var source = ssa ();
	var program = NativeAbiBuilder.build (source);
	var correspondence = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	NativeParameter? parameter = null;
	for (int i = 0; i < source.functions.length; i++) {
		correspondence.insert (source.functions[i], program.functions[i]);
		if (source.functions[i].parameters.length == 2 && source.functions[i].parameters[0].heap_object) {
			parameter = program.functions[i].signature.parameters[0];
		}
	}
	assert (parameter != null);
	NativeAbiValidator.validate_ssa_calls (source, program, correspondence);
	var original = parameter.object_origin;
	parameter.object_origin = new NativeObjectOriginPlan (original.class_ordinal, original.class_name, false);
	NativeAbiVerifier.verify (program);
	bool failed = false;
	try {
		NativeAbiValidator.validate_ssa_calls (source, program, correspondence);
	} catch (NativeAbiError error) {
		failed = error.message.contains ("allocation origin correspondence");
	}
	assert (failed);
	parameter.object_origin = original;
	NativeAbiVerifier.verify (program);
	NativeAbiValidator.validate_ssa_calls (source, program, correspondence);
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
	Test.add_func ("/gen-own-2b/semantic/forged-source-owner", semantic_owner);
	Test.add_func ("/gen-own-2b/checked/forged-eligibility-cycle", () => { run (checked_eligibility);
	});
	Test.add_func ("/gen-own-2b/core/forwarded-parameter", () => { run (() => { core_parameter (false);
	});
	});
	Test.add_func ("/gen-own-2b/core/forwarded-source", () => { run (() => { core_parameter (true);
	});
	});
	Test.add_func ("/gen-own-2b/core/missing-acquisition", () => { run (core_acquisition);
	});
	Test.add_func ("/gen-own-2b/core/dead-second-site", () => { run (core_dead_second_site);
	});
	Test.add_func ("/gen-own-2b/concrete/cycle", () => { run (concrete_cycle);
	});
	Test.add_func ("/gen-own-2b/concrete/canonical-domain", () => { run (() => { concrete_domain (true);
	});
	});
	Test.add_func ("/gen-own-2b/concrete/lexical-callee", () => { run (() => { concrete_domain (false);
	});
	});
	Test.add_func ("/gen-own-2b/concrete/no-subtype-adaptation", () => { run (concrete_nominal);
	});
	Test.add_func ("/gen-own-2b/cfg/missing-commit", () => { run (cfg_commit);
	});
	Test.add_func ("/gen-own-2b/cfg/moved-read", () => { run (cfg_moved_read);
	});
	Test.add_func ("/gen-own-2b/cfg/double-acquisition", () => { run (cfg_double_acquire);
	});
	Test.add_func ("/gen-own-2b/ssa/forwarded-domain", () => { run (ssa_argument);
	});
	Test.add_func ("/gen-own-2b/ssa/reconstructed-cleanup-domain", () => { run (() => { ssa_cleanup (false);
	});
	});
	Test.add_func ("/gen-own-2b/ssa/duplicate-cleanup", () => { run (() => { ssa_cleanup (true);
	});
	});
	Test.add_func ("/gen-own-2b/native/original-origin-plan", () => { run (native_domain);
	});
	return Test.run ();
}
}
