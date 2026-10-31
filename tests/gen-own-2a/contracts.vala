// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.GenericHeapConsumer {
private const string SOURCE = "class C{init(){}}void consume<T>(owned T v) where T:Ownable{}int main(){owned C lexical=C.init();var heap=new C();consume<C>(move lexical);consume<C>(move heap);return 42;}";
private CoreProgram core() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("heap-consumer-control", SOURCE));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	var result = CoreBuilder.build (checked.program);
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
private void symbolic_domain() throws GLib.Error {
	var program = core ();
	var parameter = program.generic_functions[0].parameters[0];
	parameter.heap_object = true;
	rejects (program, "allocation-neutral");
	parameter.heap_object = false;
	CoreVerifier.verify (program);
}
private void source_contract() throws GLib.Error {
	var program = core ();
	CoreGenericCallStatement? call = null;
	CoreCleanupContract? lexical = null;
	foreach (var statement in program.functions[0].body.statements) {
		var candidate = statement as CoreGenericCallStatement;
		if (candidate != null && ((CoreOwnedArgumentValue) candidate.arguments[0]).cleanup.is_heap_object) {
			call = candidate;
		}
	}
	foreach (var cleanup in program.cleanups) {
		if (cleanup.is_object && !cleanup.is_heap_object) {
			lexical = cleanup;
		}
	}
	assert (call != null && lexical != null);
	var original = (CoreOwnedArgumentValue) call.arguments[0];
	call.arguments[0] = new CoreOwnedArgumentValue (original.span, original.parameter, lexical, original.source, original.semantic_type);
	rejects (program, "owned argument source must match");
	call.arguments[0] = original;
	CoreVerifier.verify (program);
}
private void forwarding() throws GLib.Error {
	var program = core ();
	var function = program.generic_functions[0];
	var owner = function.owned_locals[0];
	var types = new GenericArray<SemanticType> ();
	types.add (function.parameters[0].semantic_type);
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (function.span, function.parameters[0], owner.cleanup, owner));
	function.body.statements.insert (1, new CoreGenericCallStatement (function.span, function, types, arguments));
	// Approved M15 promotion: exact incoming-owner recursion preserves storage.
	CoreVerifier.verify (program);
	function.body.statements.remove_index (1);
	CoreVerifier.verify (program);
}
private void instance_key() throws GLib.Error {
	var program = CoreGenericMonomorphizer.build (core ());
	CoreVerifier.verify_concrete (program);
	CoreFunction? heap = null;
	CoreFunction? lexical = null;
	foreach (var function in program.functions) {
		if (function.generic_instance == null) {
			continue;
		}
		if (function.generic_instance.heap_owned_parameter == 0) {
			heap = function;
		} else {
			lexical = function;
		}
	}
	assert (heap != null && lexical != null && heap.generic_instance.origin == lexical.generic_instance.origin && heap.generic_instance.type_arguments[0] == lexical.generic_instance.type_arguments[0]);
	assert (!heap.generic_instance.matches (lexical.generic_instance.origin, lexical.generic_instance.type_arguments));
	assert (!lexical.generic_instance.matches (heap.generic_instance.origin, heap.generic_instance.type_arguments, 0));
	heap.parameters[0].heap_object = false;
	rejects (program, "canonical consuming storage domain");
	heap.parameters[0].heap_object = true;
	CoreVerifier.verify_concrete (program);
}
private CfgProgram cfg() throws GLib.Error {
	var result = CfgBuilder.build (CoreGenericMonomorphizer.build (core ()));
	CfgVerifier.verify (result);
	assert (CfgFlowChecker.check (result).diagnostic == null);
	return result;
}
private void cfg_domain() throws GLib.Error {
	var program = cfg ();
	CfgParameter? parameter = null;
	foreach (var function in program.functions) {
		if (function.name.has_prefix ("astra.gen.") && function.parameters[0].heap_object) {
			parameter = function.parameters[0];
		}
	}
	assert (parameter != null);
	parameter.heap_object = false;
	bool failed = false;
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		failed = error.message.contains ("owned");
	}
	assert (failed);
	parameter.heap_object = true;
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}
private void double_acquire() throws GLib.Error {
	var program = cfg ();
	CfgBlock? entry = null;
	CfgAcquireParameter? incoming = null;
	foreach (var function in program.functions) {
		if (function.name.has_prefix ("astra.gen.") && function.parameters[0].heap_object) {
			entry = function.entry;
			incoming = entry.instructions[0] as CfgAcquireParameter;
		}
	}
	assert (entry != null && incoming != null);
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
		if (!function.name.has_prefix ("astra.gen.") || !function.parameters[0].heap_object) {
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
		if (source.functions[i].name.has_prefix ("astra.gen.") && source.functions[i].parameters[0].heap_object) {
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
	Test.add_func ("/gen-own-2a/core/allocation-neutral-definition", () => { run (symbolic_domain);
	});
	Test.add_func ("/gen-own-2a/core/wrong-actual-cleanup", () => { run (source_contract);
	});
	Test.add_func ("/gen-own-2a/core/no-heap-forwarding", () => { run (forwarding);
	});
	Test.add_func ("/gen-own-2a/core/same-type-distinct-domain-key", () => { run (instance_key);
	});
	Test.add_func ("/gen-own-2a/cfg/wrong-domain", () => { run (cfg_domain);
	});
	Test.add_func ("/gen-own-2a/cfg/double-acquisition", () => { run (double_acquire);
	});
	Test.add_func ("/gen-own-2a/ssa/wrong-domain-cleanup", () => { run (() => { ssa_cleanup (false);
	});
	});
	Test.add_func ("/gen-own-2a/ssa/duplicate-cleanup", () => { run (() => { ssa_cleanup (true);
	});
	});
	Test.add_func ("/gen-own-2a/native/wrong-origin-plan", () => { run (native_domain);
	});
	return Test.run ();
}
}
