// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.GenericHeapResult {
private const string SOURCE = "class C{init(){}}class D{init(){}}void loan<T>(borrowed T v) where T:Ownable{}owned T echo<T>(owned T v) where T:Ownable{loan<T>(v);return move v;}int main(){owned C l=C.init();owned C lr=echo<C>(move l);var h=new C();var hr=echo(move h);return 42;}";
private CheckedProgram checked() {
	var parsed = Parser.parse (new SourceFile.from_text ("heap-result-control", SOURCE));
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
private CoreProgram concrete() throws GLib.Error {
	var result = CoreGenericMonomorphizer.build (core ());
	CoreVerifier.verify_concrete (result);
	return result;
}
private void core_rejects(CoreProgram program, string text) {
	bool rejected = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains (text);
	}
	assert (rejected);
}
private CoreFunction echo(CoreProgram program, bool heap = false) {
	foreach (var function in program.generic_functions) {
		if (function.name == "echo") {
			return function;
		}
	}
	foreach (var function in program.functions) {
		if (function.generic_instance != null && function.generic_instance.origin.name == "echo" && function.heap_result == heap) {
			return function;
		}
	}
	assert_not_reached ();
}
private CoreInitialize result_acquire(CoreProgram program, bool heap) {
	foreach (var statement in program.functions[0].body.statements) {
		var init = statement as CoreInitialize;
		if (init != null && init.value is CoreCallValue && init.acquisition != null && init.acquisition.cleanup.is_heap_object == heap) {
			return init;
		}
	}
	assert_not_reached ();
}
private void semantic_source() {
	var parsed = Parser.parse (new SourceFile.from_text ("forged-source", "class C{init(){}}owned T echo<T>(owned T v) where T:Ownable{return move v;}void bad(C alias){var r=echo<C>(move alias);}int main(){return 42;}"));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	assert (result.diagnostic != null && result.diagnostic.message.contains ("nontransferable"));
	assert (checked () != null);
}
private void concrete_result_compatibility() throws GLib.Error {
	// An unrelated plain-copy type parameter does not make a concrete Class
	// result an owned-T result; preserve its established factory/forwarding ABI.
	var parsed = Parser.parse (new SourceFile.from_text ("concrete-result-compatibility", "class C{init(){}}owned C make<U>(U n){var v=new C();return move v;}owned C outer(){return make<int>(1);}int main(){var v=outer();return 42;}"));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic == null);
	var core = CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program));
	CoreVerifier.verify_concrete (core);
	var cfg = CfgBuilder.build (core);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var ssa = SsaBuilder.build (cfg);
	SsaVerifier.verify (ssa);
	NativeAbiVerifier.verify (NativeAbiBuilder.build (ssa));
}
private void checked_domain() throws GLib.Error {
	var program = checked ();
	LocalSymbol? owner = null;
	foreach (var local in program.functions[0].locals) {
		if (local.name == "hr") {
			owner = local;
		}
	}
	assert (owner != null && owner.heap_object);
	owner.heap_object = false;
	core_rejects (CoreBuilder.build (program), "acquisition domain");
	owner.heap_object = true;
	CoreVerifier.verify (CoreBuilder.build (program));
}
private void checked_eligibility() throws GLib.Error {
	var program = checked ();
	CheckedGenericFunction? function = null;
	foreach (var candidate in program.generic_functions) {
		if (candidate.definition.name == "echo") {
			function = candidate;
		}
	}
	assert (function != null);
	var returned = function.body.statements[function.body.statements.length - 1];
	var ordinal = function.definition.heap_consumer_parameter;
	function.body.statements.add (returned);
	function.definition.heap_consumer_parameter = 0;
	// The duplicate return is unreachable; the legacy flag grants no authority.
	CoreVerifier.verify (CoreBuilder.build (program));
	function.body.statements.remove_index (function.body.statements.length - 1);
	function.definition.heap_consumer_parameter = ordinal;
	CoreVerifier.verify (CoreBuilder.build (program));
}
private void core_return(int mode) throws GLib.Error {
	var program = core ();
	var function = echo (program);
	int site = (int) function.body.statements.length - 1;
	var original = function.body.statements[site] as CoreOwnershipReturn;
	assert (original != null);
	if (mode == 2) {
		function.body.statements.add (original);
	} else {
		function.body.statements[site] = new CoreOwnershipReturn (original.span, mode == 0 ? program.classes[0].semantic_type : original.semantic_type, original.cleanup, mode == 1 ? program.functions[0].owned_locals[2] : original.source);
	}
	if (mode == 2) {
		CoreVerifier.verify (program);
	} else {
		core_rejects (program, mode == 0 ? "exact function result" : "incoming owner provenance");
	}
	if (mode == 2) {
		function.body.statements.remove_index (function.body.statements.length - 1);
	} else {
		function.body.statements[site] = original;
	} CoreVerifier.verify (program);
}
private void core_entry_acquisition() throws GLib.Error {
	var program = core ();
	var function = echo (program);
	var original = function.body.statements[0];
	function.body.statements.remove_index (0);
	core_rejects (program, "owned-parameter");
	function.body.statements.insert (0, original);
	CoreVerifier.verify (program);
}
private void core_receiver(bool missing) throws GLib.Error {
	var program = core ();
	var init = result_acquire (program, true);
	var call = (CoreCallValue) init.value;
	if (missing) {
		int site = -1;
		for (int i = 0; i < program.functions[0].body.statements.length; i++) {
			if (program.functions[0].body.statements[i] == init) {
				site = i;
			}
		}
		assert (site >= 0);
		program.functions[0].body.statements[site] = new CoreInitialize (init.span, init.target, init.value);
		core_rejects (program, "owned initialization");
		program.functions[0].body.statements[site] = init;
	} else {
		var original = call.candidate_storage;
		call.candidate_storage = ((CoreCallValue) result_acquire (program, false).value).candidate_storage;
		assert (call.candidate_storage != null);
		core_rejects (program, "result storage");
		call.candidate_storage = original;
	} CoreVerifier.verify (program);
}
private void core_actual_domain() throws GLib.Error {
	var program = core ();
	var call = (CoreCallValue) result_acquire (program, true).value;
	var original = (CoreOwnedArgumentValue) call.arguments[0];
	var lexical = result_acquire (program, false).acquisition.cleanup;
	call.arguments[0] = new CoreOwnedArgumentValue (original.span, original.parameter, lexical, original.source, original.semantic_type);
	core_rejects (program, "owned argument source must match");
	call.arguments[0] = original;
	CoreVerifier.verify (program);
}
private void concrete_domain(int mode) throws GLib.Error {
	var program = concrete ();
	var function = echo (program, true);
	if (mode == 0) {
		function.parameters[0].heap_object = false;
		core_rejects (program, "canonical consuming storage domain");
		function.parameters[0].heap_object = true;
	} else if (mode == 1) {
		var original = function.result_storage;
		function.result_storage = new CoreResultObjectStorage (function.span, function.owned_cleanup.object_class);
		core_rejects (program, "canonical consuming storage domain");
		function.result_storage = original;
	} else {
		int site = (int) function.body.statements.length - 1;
		var original = (CoreOwnershipReturn) function.body.statements[site];
		function.body.statements[site] = new CoreOwnershipReturn (original.span, original.semantic_type, original.cleanup, original.source, null, ObjectResultProvenance.OWNED_PARAMETER_STORAGE);
		core_rejects (program, "storage provenance");
		function.body.statements[site] = original;
	}
	CoreVerifier.verify_concrete (program);
}
private CfgProgram cfg() throws GLib.Error {
	var result = CfgBuilder.build (concrete ());
	CfgVerifier.verify (result);
	assert (CfgFlowChecker.check (result).diagnostic == null);
	return result;
}
private CfgFunction cfg_echo(CfgProgram program) {
	foreach (var function in program.functions) {
		if (function.heap_result) {
			return function;
		}
	}
	assert_not_reached ();
}
private void cfg_rejects(CfgProgram program, string text) {
	bool rejected = false;
	try {
		CfgVerifier.verify (program);
	} catch (CfgError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains (text);
	}
	assert (rejected);
}
private void cfg_capture(bool reordered) throws GLib.Error {
	var program = cfg ();
	var block = cfg_echo (program).entry;
	int site = -1;
	for (int i = 0; i < block.instructions.length; i++) {
		if (block.instructions[i] is CfgOwnershipReturnInstruction) {
			site = i;
		}
	}
	assert (site >= 0);
	var original = block.instructions[site];
	block.instructions.remove_index (site);
	if (reordered) {
		block.instructions.add (original);
		CfgVerifier.verify (program);
		bool rejected = false;
		try {
			var result = CfgFlowChecker.check (program);
			rejected = result.diagnostic != null;
			if (result.diagnostic != null) {
				Test.message ("%s", result.diagnostic.message);
			}
		} catch (CfgError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("lexical lifetime");
		}
		assert (rejected);
		block.instructions.remove_index (block.instructions.length - 1);
	} else {
		cfg_rejects (program, "capture");
	}
	block.instructions.insert (site, original);
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}
private void cfg_moved_read() throws GLib.Error {
	var program = cfg ();
	var block = cfg_echo (program).entry;
	CfgOwnedBorrowInstruction? borrow = null;
	CfgCallInstruction? call = null;
	var original = new GenericArray<CfgInstruction> ();
	foreach (var instruction in block.instructions) {
		original.add (instruction);
		if (instruction is CfgOwnedBorrowInstruction) {
			borrow = (CfgOwnedBorrowInstruction) instruction;
		}
	}
	assert (borrow != null);
	foreach (var instruction in original) {
		var candidate = instruction as CfgCallInstruction;
		if (candidate != null && candidate.arguments.length == 1 && candidate.arguments[0] == borrow.result) {
			call = candidate;
		}
	}
	assert (call != null);
	block.instructions.remove_range (0, block.instructions.length);
	foreach (var instruction in original) {
		if (instruction == borrow || instruction == call) {
			continue;
		}
		block.instructions.add (instruction);
		if (instruction is CfgOwnershipReturnInstruction) {
			block.instructions.add (borrow);
			block.instructions.add (call);
		}
	}
	// A return capture admits only cleanup afterwards, so this moved read
	// already fails the independent CFG structural barrier.
	cfg_rejects (program, "capture");
	block.instructions.remove_range (0, block.instructions.length);
	foreach (var instruction in original) {
		block.instructions.add (instruction);
	}
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}
private void cfg_duplicate_receiver() throws GLib.Error {
	var program = cfg ();
	bool tested = false;
	foreach (var function in program.functions) {
		if (function.name != "main") {
			continue;
		}
		foreach (var block in function.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var init = block.instructions[i] as CfgInitialize;
				if (init == null || init.acquisition == null || !init.acquisition.cleanup.is_heap_object) {
					continue;
				}
				block.instructions.insert (i + 1, new CfgInitialize (init.span, init.target, init.value, init.acquisition));
				cfg_rejects (program, "initializ");
				block.instructions.remove_index (i + 1);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
	}
	assert (tested);
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}
private SsaProgram ssa() throws GLib.Error {
	var result = SsaBuilder.build (cfg ());
	SsaVerifier.verify (result);
	return result;
}
private SsaFunction ssa_echo(SsaProgram program) {
	foreach (var function in program.functions) {
		if (function.heap_result) {
			return function;
		}
	}
	assert_not_reached ();
}
private void ssa_rejects(SsaProgram program, string text) {
	bool rejected = false;
	try {
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains (text);
	}
	assert (rejected);
}
private void ssa_pointer() throws GLib.Error {
	var program = ssa ();
	var function = ssa_echo (program);
	var block = function.entry;
	var original = (SsaOwnershipReturn) block.terminator;
	int site = -1;
	SsaHeapOwnerEvent? event = null;
	for (int i = 0; i < block.instructions.length; i++) {
		var candidate = block.instructions[i] as SsaHeapOwnerEvent;
		if (candidate != null && candidate.action == SsaHeapOwnerAction.RETURN) {
			site = i;
			event = candidate;
		}
	}
	assert (event != null);
	var wrong = new SsaNullPointerConstant (original.span, original.value.semantic_type);
	block.instructions[site] = new SsaHeapOwnerEvent (event.span, event.owner, event.action, wrong);
	ssa_rejects (program, "captured owner");
	block.instructions[site] = event;
	SsaVerifier.verify (program);
}
private void ssa_missing_capture() throws GLib.Error {
	var program = ssa ();
	var block = ssa_echo (program).entry;
	int site = -1;
	for (int i = 0; i < block.instructions.length; i++) {
		var event = block.instructions[i] as SsaHeapOwnerEvent;
		if (event != null && event.action == SsaHeapOwnerAction.RETURN) {
			site = i;
		}
	}
	assert (site >= 0);
	var original = block.instructions[site];
	block.instructions.remove_index (site);
	ssa_rejects (program, "captured owner return event");
	block.instructions.insert (site, original);
	SsaVerifier.verify (program);
}
private void ssa_escaped_cleanup(bool duplicate) throws GLib.Error {
	var program = ssa ();
	var function = ssa_echo (program);
	var block = function.entry;
	var returned = (SsaOwnershipReturn) block.terminator;
	if (duplicate) {
		int site = -1;
		for (int i = 0; i < block.instructions.length; i++) {
			if (block.instructions[i] is SsaCleanupInstruction) {
				site = i;
			}
		}
		assert (site >= 0);
		var original = (SsaCleanupInstruction) block.instructions[site];
		block.instructions.insert (site + 1, new SsaCleanupInstruction (original.span, original.value, original.cleanup));
		ssa_rejects (program, "cleanup");
		block.instructions.remove_index (site + 1);
	} else {
		int site = -1;
		int end_site = -1;
		SsaCleanupInstruction? original = null;
		SsaHeapOwnerEvent? ended = null;
		for (int i = 0; i < block.instructions.length; i++) {
			var candidate = block.instructions[i] as SsaCleanupInstruction;
			if (candidate != null) {
				site = i;
				original = candidate;
			}
		}
		assert (original != null);
		for (int i = 0; i < block.instructions.length; i++) {
			var candidate = block.instructions[i] as SsaHeapOwnerEvent;
			if (candidate != null && candidate.effect == original) {
				end_site = i;
				ended = candidate;
			}
		}
		assert (ended != null);
		var cleanup = new SsaCleanupInstruction (original.span, returned.value, original.cleanup);
		block.instructions[site] = cleanup;
		block.instructions[end_site] = new SsaHeapOwnerEvent (ended.span, ended.owner, ended.action, returned.value, cleanup);
		ssa_rejects (program, "pointer");
		block.instructions[site] = original;
		block.instructions[end_site] = ended;
	}
	SsaVerifier.verify (program);
}
private void ssa_domain() throws GLib.Error {
	var program = ssa ();
	var function = ssa_echo (program);
	function.parameters[0].heap_object = false;
	ssa_rejects (program, "owned argument");
	function.parameters[0].heap_object = true;
	SsaVerifier.verify (program);
}
// Author a stage-owned graph with no call edges or predecessor approval.
// The absent optional source_parameter annotation forces independent pointer
// and origin reconstruction rather than an annotation-only comparison.
private SsaProgram standalone(bool wrong = false, SsaClass? existing_class = null, SsaCleanupContract? existing_cleanup = null) throws GLib.Error {
	var source = ssa ();
	var span = source.span;
	var type = (ClassType) (existing_class == null ? source.classes[0].semantic_type : existing_class.semantic_type);
	var object_class = existing_class ?? new SsaClass (span, span, "C", type);
	var cleanup = existing_cleanup ?? new SsaCleanupContract.for_object (object_class, 0, true);
	var parameter = new SsaFunctionParameter (span, span, "incoming", type, 0, PointerParameterContract.OWNED_TRANSFER);
	parameter.heap_object = true;
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (parameter);
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var function = new SsaFunction (span, span, "standalone.heap.echo", type, 0, parameters, blocks, block, cleanup);
	function.heap_result = true;
	var owner = new SsaHeapOwner (0, 0, cleanup, 0);
	function.heap_owners.add (owner);
	var null_pointer = new SsaNullPointerConstant (span, type);
	SsaValue returned = wrong ? (SsaValue) null_pointer : parameter;
	block.instructions.add (new SsaHeapOwnerEvent (span, owner, SsaHeapOwnerAction.ACQUIRE, parameter));
	block.instructions.add (new SsaHeapOwnerEvent (span, owner, SsaHeapOwnerAction.RETURN, returned));
	var retired = new SsaCleanupInstruction (span, null_pointer, cleanup);
	block.instructions.add (retired);
	block.instructions.add (new SsaHeapOwnerEvent (span, owner, SsaHeapOwnerAction.END, null_pointer, retired));
	block.complete (new SsaOwnershipReturn (span, returned, ObjectResultProvenance.HEAP_OBJECT));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	var program = new SsaProgram (span, functions);
	program.classes.add (object_class);
	program.cleanups.add (cleanup);
	return program;
}
private void ssa_standalone(bool pointer) throws GLib.Error {
	var program = standalone ();
	SsaVerifier.verify (program);
	if (pointer) {
		var original = program.functions[0];
		var forged = standalone (true, program.classes[0], program.cleanups[0]);
		program.functions[0] = forged.functions[0];
		ssa_rejects (program, "current exact owner pointer");
		program.functions[0] = original;
	} else {
		var parameter = program.functions[0].parameters[0];
		parameter.heap_object = false;
		ssa_rejects (program, "allocation domain");
		parameter.heap_object = true;
	}
	SsaVerifier.verify (program);
}
private void native_result(bool candidate) throws GLib.Error {
	var source = ssa ();
	var native = NativeAbiBuilder.build (source);
	var correspondence = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	NativeFunction? function = null;
	for (int i = 0; i < source.functions.length; i++) {
		correspondence.insert (source.functions[i], native.functions[i]);
		if (source.functions[i].heap_result) {
			function = native.functions[i];
		}
	}
	assert (function != null && function.signature.heap_result != null && function.signature.object_result == null);
	NativeAbiValidator.validate_ssa_calls (source, native, correspondence);
	if (candidate) {
		var original = function.signature;
		var signature = new NativeSignature (original.abi_version, original.parameters, original.result, original.receiver, new NativeOwnedObjectResultPlan ());
		signature.heap_result = original.heap_result;
		var forged = new NativeFunction (function.span, function.name_span, function.name, function.ordinal, signature, function.linkage);
		forged.claim_owner (native);
		native.functions[function.ordinal] = forged;
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("heap result");
		}
		assert (rejected);
		native.functions[function.ordinal] = function;
	} else {
		var original = function.signature.heap_result;
		function.signature.heap_result = null;
		NativeAbiVerifier.verify (native);
		bool rejected = false;
		try {
			NativeAbiValidator.validate_ssa_calls (source, native, correspondence);
		} catch (NativeAbiError error) {
			Test.message ("%s", error.message);
			rejected = error.message.contains ("heap result origin correspondence");
		}
		assert (rejected);
		function.signature.heap_result = original;
	}
	NativeAbiVerifier.verify (native);
	NativeAbiValidator.validate_ssa_calls (source, native, correspondence);
}
private void native_class() throws GLib.Error {
	var source = ssa ();
	var native = NativeAbiBuilder.build (source);
	var correspondence = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	NativeSignature? signature = null;
	for (int i = 0; i < source.functions.length; i++) {
		correspondence.insert (source.functions[i], native.functions[i]);
		if (source.functions[i].heap_result) {
			signature = native.functions[i].signature;
		}
	}
	assert (signature != null);
	var original = signature.heap_result;
	var wrong = native.classes[1];
	signature.heap_result = new NativeObjectOriginPlan (wrong.ordinal, wrong.name, true);
	NativeAbiVerifier.verify (native);
	bool rejected = false;
	try {
		NativeAbiValidator.validate_ssa_calls (source, native, correspondence);
	} catch (NativeAbiError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains ("exact source class and origin");
	}
	assert (rejected);
	signature.heap_result = new NativeObjectOriginPlan (original.class_ordinal, original.class_name, false);
	rejected = false;
	try {
		NativeAbiVerifier.verify (native);
	} catch (NativeAbiError error) {
		Test.message ("%s", error.message);
		rejected = error.message.contains ("heap result");
	}
	assert (rejected);
	signature.heap_result = original;
	NativeAbiVerifier.verify (native);
	NativeAbiValidator.validate_ssa_calls (source, native, correspondence);
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
	Test.add_func ("/gen-own-2c/semantic/exact-source-owner", semantic_source);
	Test.add_func ("/gen-own-2c/compatibility/concrete-class-result", () => { run (concrete_result_compatibility);
	});
	Test.add_func ("/gen-own-2c/checked/forged-result-domain", () => { run (checked_domain);
	});
	Test.add_func ("/gen-own-2c/checked/forged-eligibility", () => { run (checked_eligibility);
	});
	Test.add_func ("/gen-own-2c/core/wrong-result-type", () => { run (() => { core_return (0);
	});
	});
	Test.add_func ("/gen-own-2c/core/wrong-return-owner", () => { run (() => { core_return (1);
	});
	});
	Test.add_func ("/gen-own-2c/core/duplicate-return", () => { run (() => { core_return (2);
	});
	});
	Test.add_func ("/gen-own-2c/core/missing-entry-acquisition", () => { run (core_entry_acquisition);
	});
	Test.add_func ("/gen-own-2c/core/missing-result-acquisition", () => { run (() => { core_receiver (true);
	});
	});
	Test.add_func ("/gen-own-2c/core/heap-candidate-alias", () => { run (() => { core_receiver (false);
	});
	});
	Test.add_func ("/gen-own-2c/core/wrong-actual-domain", () => { run (core_actual_domain);
	});
	Test.add_func ("/gen-own-2c/concrete/canonical-formal-domain", () => { run (() => { concrete_domain (0);
	});
	});
	Test.add_func ("/gen-own-2c/concrete/heap-result-candidate", () => { run (() => { concrete_domain (1);
	});
	});
	Test.add_func ("/gen-own-2c/concrete/wrong-return-provenance", () => { run (() => { concrete_domain (2);
	});
	});
	Test.add_func ("/gen-own-2c/cfg/missing-return-capture", () => { run (() => { cfg_capture (false);
	});
	});
	Test.add_func ("/gen-own-2c/cfg/reordered-return-capture", () => { run (() => { cfg_capture (true);
	});
	});
	Test.add_func ("/gen-own-2c/cfg/moved-read", () => { run (cfg_moved_read);
	});
	Test.add_func ("/gen-own-2c/cfg/double-result-acquisition", () => { run (cfg_duplicate_receiver);
	});
	Test.add_func ("/gen-own-2c/ssa/wrong-captured-pointer", () => { run (ssa_pointer);
	});
	Test.add_func ("/gen-own-2c/ssa/missing-return-capture", () => { run (ssa_missing_capture);
	});
	Test.add_func ("/gen-own-2c/ssa/escaped-pointer-cleanup", () => { run (() => { ssa_escaped_cleanup (false);
	});
	});
	Test.add_func ("/gen-own-2c/ssa/duplicate-cleanup", () => { run (() => { ssa_escaped_cleanup (true);
	});
	});
	Test.add_func ("/gen-own-2c/ssa/incoming-signature-domain", () => { run (ssa_domain);
	});
	Test.add_func ("/gen-own-2c/ssa/independent-current-pointer", () => { run (() => { ssa_standalone (true);
	});
	});
	Test.add_func ("/gen-own-2c/ssa/independent-result-origin", () => { run (() => { ssa_standalone (false);
	});
	});
	Test.add_func ("/gen-own-2c/native/heap-result-origin-plan", () => { run (() => { native_result (false);
	});
	});
	Test.add_func ("/gen-own-2c/native/heap-result-candidate", () => { run (() => { native_result (true);
	});
	});
	Test.add_func ("/gen-own-2c/native/exact-class-and-heap-bit", () => { run (native_class);
	});
	return Test.run ();
}
}
