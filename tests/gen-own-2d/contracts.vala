// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;

namespace Astra.Tests.GenericOwnerLocal {
private const string SOURCE = "class C{init(){}}class D{init(){}}void loan<T>(borrowed T v) where T:Ownable{}void sink<T>(owned T v) where T:Ownable{}void stage<T>(owned T input,bool send) where T:Ownable{owned T current=move input;loan<T>(current);if(send){sink<T>(move current);}}int main(){owned C l=C.init();var h=new C();stage<C>(move l,false);stage<C>(move h,true);return 42;}";
private CheckedProgram checked() {
	var parsed = Parser.parse (new SourceFile.from_text ("generic-owner-local", SOURCE));
	assert (parsed.diagnostic == null);
	var result = SemanticAnalyzer.analyze (parsed.unit);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.message);
	}
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

private CoreFunction stage(CoreProgram program, bool heap = false) {
	foreach (var function in program.generic_functions) {
		if (function.name == "stage") {
			return function;
		}
	}
	foreach (var function in program.functions) {
		if (function.generic_instance != null && function.generic_instance.origin.name == "stage" && (function.generic_instance.heap_owned_parameter >= 0) == heap) {
			return function;
		}
	}
	assert_not_reached ();
}

private void core_rejects(CoreProgram program) {
	bool rejected = false;
	try {
		CoreVerifier.verify (program);
	} catch (CoreError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private void checked_mutation(int mode) throws GLib.Error {
	var source = checked ();
	CheckedGenericFunction? function = null;
	foreach (var candidate in source.generic_functions) {
		if (candidate.definition.name == "stage") {
			function = candidate;
		}
	}
	assert (function != null);
	var local = function.locals[1];
	var original = local.generic_owner_source;
	if (mode == 0) {
		local.generic_owner_source = local;
	} else if (mode == 1) {
		local.heap_object = true;
	} else {
		local.generic_owner_source = null;
	}
	bool rejected = false;
	try {
		CoreBuilder.build (source);
	} catch (CoreError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
	local.generic_owner_source = original;
	local.heap_object = false;
	CoreVerifier.verify (CoreBuilder.build (source));
}

private void core_mutation(int mode, bool specialized = false, bool heap = false) throws GLib.Error {
	var program = specialized ? concrete () : core ();
	var function = stage (program, heap);
	var original = function.body.statements[1] as CoreOwnershipTransfer;
	assert (original != null);
	if (mode == 0) {
		function.body.statements.remove_index (1);
	} else if (mode == 1) {
		function.body.statements.insert (2, original);
	} else if (mode == 2) {
		function.body.statements[1] = new CoreOwnershipTransfer (original.span, original.destination, original.source, original.cleanup);
	} else if (mode == 3) {
		function.body.statements[1] = new CoreInitialize (original.span, original.destination.place, new CoreLoadValue (original.span, original.source.place), original.destination);
	} else if (mode == 4) {
		var wrong = stage (program, !heap).owned_locals[0].cleanup;
		assert (wrong != original.cleanup);
		function.body.statements[1] = new CoreOwnershipTransfer (original.span, original.source, original.destination, wrong);
	} else {
		function.parameters[0].heap_object = !function.parameters[0].heap_object;
	}
	core_rejects (program);
	if (mode == 0) {
		function.body.statements.insert (1, original);
	} else if (mode == 1) {
		function.body.statements.remove_index (2);
	} else if (mode == 5) {
		function.parameters[0].heap_object = !function.parameters[0].heap_object;
	} else {
		function.body.statements[1] = original;
	}
	CoreVerifier.verify (program);
}

private CfgProgram cfg() throws GLib.Error {
	var result = CfgBuilder.build (concrete ());
	CfgVerifier.verify (result);
	assert (CfgFlowChecker.check (result).diagnostic == null);
	return result;
}

private void core_type() throws GLib.Error {
	var program = core ();
	var function = stage (program);
	var original = (CoreOwnershipTransfer) function.body.statements[1];
	var cleanup = new CoreCleanupContract.for_object (program.classes[1], program.cleanups.length);
	program.cleanups.add (cleanup);
	var place = new CoreLocalPlace (original.span, original.destination.place.name_span, "wrong", program.classes[1].semantic_type, 1, false);
	var destination = new CoreOwnedLocal (original.span, place, cleanup, function.body);
	function.locals[1] = place;
	function.owned_locals[1] = destination;
	function.body.statements[1] = new CoreOwnershipTransfer (original.span, original.source, destination, cleanup);
	core_rejects (program);
	function.locals[1] = original.destination.place;
	function.owned_locals[1] = original.destination;
	function.body.statements[1] = original;
	program.cleanups.remove_index (program.cleanups.length - 1);
	CoreVerifier.verify (program);
}

private void core_producer() throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("forged-local-producer", SOURCE + "owned T echo<T>(owned T v) where T:Ownable{return move v;}"));
	assert (parsed.diagnostic == null);
	var source = SemanticAnalyzer.analyze (parsed.unit);
	assert (source.diagnostic == null);
	var program = CoreBuilder.build (source.program);
	CoreVerifier.verify (program);
	CoreGenericFunction? producer = null;
	foreach (var candidate in program.generic_functions) {
		if (candidate.name == "echo") {
			producer = candidate;
		}
	}
	assert (producer != null);
	var function = stage (program);
	var original = (CoreOwnershipTransfer) function.body.statements[1];
	var types = new GenericArray<SemanticType> ();
	types.add (original.source.place.semantic_type);
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (original.span, producer.parameters[0], original.cleanup, original.source, original.source.place.semantic_type));
	function.body.statements[1] = new CoreInitialize (original.span, original.destination.place, new CoreGenericCall (original.span, original.source.place.semantic_type, producer, types, arguments), original.destination);
	CoreVerifier.verify (program);
	function.body.statements[1] = original;
	CoreVerifier.verify (program);
}

private void resource_rearm() throws GLib.Error {
	var program = core ();
	var span = program.span;
	var target = (CoreGenericFunction) stage (program);
	var token = new HandleType ("R");
	var cleanup = new CoreCleanupContract ("drop_r", span, program.cleanups.length);
	program.cleanups.add (cleanup);
	program.handles.add (new CoreHandle (span, span, token, cleanup, null, 0));
	var parameter = new CoreParameter (span, span, "input", token, 0, PointerParameterContract.OWNED_TRANSFER);
	var parameters = new GenericArray<CoreParameter> ();
	parameters.add (parameter);
	var place = new CoreLocalPlace (span, span, "input", token, 0, false, parameter);
	var locals = new GenericArray<CoreLocalPlace> ();
	locals.add (place);
	var body = new CoreBlock (span, new GenericArray<CoreStatement> ());
	var owner = new CoreOwnedLocal (span, place, cleanup, body);
	var root = new CoreFunction (span, span, "resource.root", target.return_type, parameters, locals, body);
	root.owned_locals.add (owner);
	body.statements.add (new CoreAcquireParameter (span, owner, parameter));
	var arguments = new GenericArray<CoreValue> ();
	arguments.add (new CoreOwnedArgumentValue (span, target.parameters[0], cleanup, owner, token));
	arguments.add (new CoreBooleanValue (span, target.parameters[1].semantic_type, BooleanLiteral.TRUE));
	var actuals = new GenericArray<SemanticType> ();
	actuals.add (token);
	body.statements.add (new CoreGenericCallStatement (span, target, actuals, arguments));
	program.functions.add (root);
	CoreVerifier.verify (program);
	var concrete = CoreGenericMonomorphizer.build (program);
	CoreFunction? function = null;
	foreach (var candidate in concrete.functions) {
		if (candidate.generic_instance != null && candidate.generic_instance.origin.name == "stage" && candidate.generic_instance.type_arguments[0] == token) {
			function = candidate;
		}
	}
	assert (function != null);
	var transfer = (CoreOwnershipTransfer) function.body.statements[1];
	function.body.statements.insert (2, new CoreOwnershipRearm.from_owner (span, transfer.destination, transfer.source, transfer.cleanup));
	core_rejects (concrete);
	function.body.statements.remove_index (2);
	CoreVerifier.verify_concrete (concrete);
}

private void buffer_compatibility() throws GLib.Error {
	string slices;
	string buffers;
	FileUtils.get_contents ("lib/astra/base/slices.astra", out slices);
	FileUtils.get_contents ("lib/astra/base/buffers.astra", out buffers);
	var parsed = Parser.parse (new SourceFile.from_text ("separate-buffer-contract", slices + buffers + "void arrays<T>(owned T[] input){owned T[] current=move input;current=clone_array(current);}void root(owned int[] input){arrays<int>(move input);}"));
	assert (parsed.diagnostic == null);
	var source = SemanticAnalyzer.analyze (parsed.unit);
	if (source.diagnostic != null) {
		GLib.error ("%s", source.diagnostic.format ());
	}
	var concrete = CoreGenericMonomorphizer.build (CoreBuilder.build (source.program));
	CoreVerifier.verify_concrete (concrete);
	foreach (var function in concrete.functions) {
		if (function.generic_instance != null) {
			assert (function.generic_instance.local_owned_parameter == -1 && !function.generic_instance.owns_parameter (0));
		}
	}
	var cfg = CfgBuilder.build (concrete);
	assert (CfgFlowChecker.check (cfg).diagnostic == null);
	var ssa = SsaBuilder.build (cfg);
	SsaVerifier.verify (ssa);
	NativeAbiVerifier.verify (NativeAbiBuilder.build (ssa));
}

private CfgFunction cfg_stage(CfgProgram program, bool heap) {
	foreach (var function in program.functions) {
		if (function.parameters.length != 2 || function.parameters[0].heap_object != heap) {
			continue;
		}
		foreach (var instruction in function.entry.instructions) {
			if (instruction is CfgOwnershipTransferInstruction) {
				return function;
			}
		}
	}
	assert_not_reached ();
}

private void cfg_rejects(CfgProgram program) {
	bool rejected = false;
	try {
		CfgVerifier.verify (program);
		var result = CfgFlowChecker.check (program);
		if (result.diagnostic != null) {
			Test.message ("%s", result.diagnostic.message);
			rejected = true;
		}
	} catch (CfgError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

private void cfg_mutation(int mode, bool heap) throws GLib.Error {
	var program = cfg ();
	var function = cfg_stage (program, heap);
	var block = function.entry;
	int site = -1;
	for (int i = 0; i < block.instructions.length; i++) {
		if (block.instructions[i] is CfgOwnershipTransferInstruction) {
			site = i;
		}
	}
	assert (site >= 0);
	var original = (CfgOwnershipTransferInstruction) block.instructions[site];
	if (mode == 0 || mode == 1) {
		block.instructions.remove_index (site);
		if (mode == 1) {
			block.instructions.add (original);
		}
	} else if (mode == 2) {
		block.instructions.insert (site + 1, original);
	} else {
		block.instructions[site] = new CfgOwnershipTransferInstruction (original.span, original.destination, original.source, original.cleanup);
	}
	cfg_rejects (program);
	if (mode == 1) {
		block.instructions.remove_index (block.instructions.length - 1);
	}
	if (mode == 0 || mode == 1) {
		block.instructions.insert (site, original);
	} else if (mode == 2) {
		block.instructions.remove_index (site + 1);
	} else {
		block.instructions[site] = original;
	}
	CfgVerifier.verify (program);
	assert (CfgFlowChecker.check (program).diagnostic == null);
}

private SsaProgram ssa() throws GLib.Error {
	var result = SsaBuilder.build (cfg ());
	SsaVerifier.verify (result);
	return result;
}

private void ssa_rejects(SsaProgram program) {
	bool rejected = false;
	try {
		SsaVerifier.verify (program);
	} catch (SsaError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
}

// This graph has no Checked, Core, CFG or generic-instance annotation.
// Independently exercise original pointer transfer in all three domains.
private SsaProgram standalone(int domain) throws GLib.Error {
	var source = ssa ();
	var span = source.span;
	var types = new BuiltinTypes ();
	SemanticType type;
	SsaClass? object_class = null;
	SsaHandle? handle = null;
	SsaCleanupContract cleanup;
	if (domain == 2) {
		var token = new HandleType ("R");
		type = token;
		cleanup = new SsaCleanupContract ("drop_r", span, 0);
		handle = new SsaHandle (span, span, token, cleanup, null, 0);
	} else {
		type = source.classes[0].semantic_type;
		object_class = new SsaClass (span, span, "C", (ClassType) type);
		cleanup = new SsaCleanupContract.for_object (object_class, 0, domain == 1);
	}
	var parameter = new SsaFunctionParameter (span, span, "input", type, 0, PointerParameterContract.OWNED_TRANSFER);
	parameter.heap_object = domain == 1;
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (parameter);
	var block = new SsaBlock (span, 0, 0);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (block);
	var function = new SsaFunction (span, span, "independent.local", types.void_type, 0, parameters, blocks, block);
	var incoming = new SsaHeapOwner (0, 0, cleanup, span.start);
	var local = new SsaHeapOwner (1, 1, cleanup, span.start);
	function.heap_owners.add (incoming);
	function.heap_owners.add (local);
	block.instructions.add (new SsaHeapOwnerEvent (span, incoming, SsaHeapOwnerAction.ACQUIRE, parameter));
	block.instructions.add (new SsaHeapOwnerEvent (span, incoming, SsaHeapOwnerAction.MOVE, parameter));
	block.instructions.add (new SsaHeapOwnerEvent (span, local, SsaHeapOwnerAction.ACQUIRE, parameter));
	var empty = new SsaNullPointerConstant (span, type);
	var old_cleanup = new SsaCleanupInstruction (span, empty, cleanup);
	var final_cleanup = new SsaCleanupInstruction (span, parameter, cleanup);
	block.instructions.add (old_cleanup);
	block.instructions.add (new SsaHeapOwnerEvent (span, incoming, SsaHeapOwnerAction.END, empty, old_cleanup));
	block.instructions.add (final_cleanup);
	block.instructions.add (new SsaHeapOwnerEvent (span, local, SsaHeapOwnerAction.END, parameter, final_cleanup));
	block.complete (new SsaReturn (span, null));
	var functions = new GenericArray<SsaFunction> ();
	functions.add (function);
	var program = new SsaProgram (span, functions);
	program.cleanups.add (cleanup);
	if (object_class != null) {
		program.classes.add (object_class);
	}
	if (handle != null) {
		program.handles.add (handle);
	}
	SsaVerifier.verify (program);
	return program;
}

private void ssa_mutation(int domain, int mode) throws GLib.Error {
	var program = standalone (domain);
	var function = program.functions[0];
	var block = function.entry;
	var original = new GenericArray<SsaInstruction> ();
	foreach (var instruction in block.instructions) {
		original.add (instruction);
	}
	if (mode == 0) {
		block.instructions.remove_index (1);
	} else if (mode == 1) {
		block.instructions.remove_index (2);
	} else if (mode == 2) {
		block.instructions.insert (3, block.instructions[2]);
	} else if (mode == 3) {
		var acquire = (SsaHeapOwnerEvent) block.instructions[2];
		block.instructions[2] = new SsaHeapOwnerEvent (acquire.span, acquire.owner, acquire.action, new SsaNullPointerConstant (acquire.span, acquire.value.semantic_type));
	} else if (mode == 4) {
		var event = (SsaHeapOwnerEvent) block.instructions[6];
		var cleanup = new SsaCleanupInstruction (event.span, new SsaNullPointerConstant (event.span, event.value.semantic_type), event.owner.cleanup);
		block.instructions[5] = cleanup;
		block.instructions[6] = new SsaHeapOwnerEvent (event.span, event.owner, event.action, cleanup.value, cleanup);
	} else {
		block.instructions.insert (6, block.instructions[5]);
	}
	ssa_rejects (program);
	block.instructions.remove_range (0, block.instructions.length);
	foreach (var instruction in original) {
		block.instructions.add (instruction);
	}
	SsaVerifier.verify (program);
}

private void native_mutation(bool heap, bool wrong_class) throws GLib.Error {
	var source = ssa ();
	var native = NativeAbiBuilder.build (source);
	var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	NativeParameter? parameter = null;
	for (int i = 0; i < source.functions.length; i++) {
		map.insert (source.functions[i], native.functions[i]);
		var function = source.functions[i];
		if (function.heap_owners.length == 2 && function.parameters.length == 2 && function.parameters[0].heap_object == heap) {
			parameter = native.functions[i].signature.parameters[0];
		}
	}
	assert (parameter != null && parameter.object_origin != null);
	NativeAbiValidator.validate_ssa_calls (source, native, map);
	var original = parameter.object_origin;
	parameter.object_origin = wrong_class ? new NativeObjectOriginPlan (1, native.classes[1].name, heap) : new NativeObjectOriginPlan (original.class_ordinal, original.class_name, !heap);
	bool rejected = false;
	try {
		NativeAbiVerifier.verify (native);
		NativeAbiValidator.validate_ssa_calls (source, native, map);
	} catch (NativeAbiError error) {
		Test.message ("%s", error.message);
		rejected = true;
	}
	assert (rejected);
	parameter.object_origin = original;
	NativeAbiVerifier.verify (native);
	NativeAbiValidator.validate_ssa_calls (source, native, map);
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
	Test.add_func ("/gen-own-2d/checked/wrong-source", () => { run (() => { checked_mutation (0);
	});
	});
	Test.add_func ("/gen-own-2d/checked/forged-heap-origin", () => { run (() => { checked_mutation (1);
	});
	});
	Test.add_func ("/gen-own-2d/checked/missing-source", () => { run (() => { checked_mutation (2);
	});
	});
	Test.add_func ("/gen-own-2d/core/mutation-0", () => { run (() => { core_mutation (0);
	});
	});
	Test.add_func ("/gen-own-2d/core/mutation-1", () => { run (() => { core_mutation (1);
	});
	});
	Test.add_func ("/gen-own-2d/core/mutation-2", () => { run (() => { core_mutation (2);
	});
	});
	Test.add_func ("/gen-own-2d/core/mutation-3", () => { run (() => { core_mutation (3);
	});
	});
	Test.add_func ("/gen-own-2d/core/wrong-T", () => { run (core_type);
	});
	Test.add_func ("/gen-own-2d/core/producer-instead-of-move", () => { run (core_producer);
	});
	Test.add_func ("/gen-own-2d/concrete/resource-rearm", () => { run (resource_rearm);
	});
	Test.add_func ("/gen-own-2d/compatibility/owned-buffer-local-and-rearm", () => { run (buffer_compatibility);
	});
	Test.add_func ("/gen-own-2d/concrete/domain-false", () => { run (() => { core_mutation (5, true, false);
	});
	});
	Test.add_func ("/gen-own-2d/concrete/cleanup-false", () => { run (() => { core_mutation (4, true, false);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-false/mutation-0", () => { run (() => { cfg_mutation (0, false);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-false/mutation-1", () => { run (() => { cfg_mutation (1, false);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-false/mutation-2", () => { run (() => { cfg_mutation (2, false);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-false/mutation-3", () => { run (() => { cfg_mutation (3, false);
	});
	});
	Test.add_func ("/gen-own-2d/native/domain-false/wrong-heap", () => { run (() => { native_mutation (false, false);
	});
	});
	Test.add_func ("/gen-own-2d/native/domain-false/wrong-class", () => { run (() => { native_mutation (false, true);
	});
	});
	Test.add_func ("/gen-own-2d/concrete/domain-true", () => { run (() => { core_mutation (5, true, true);
	});
	});
	Test.add_func ("/gen-own-2d/concrete/cleanup-true", () => { run (() => { core_mutation (4, true, true);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-true/mutation-0", () => { run (() => { cfg_mutation (0, true);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-true/mutation-1", () => { run (() => { cfg_mutation (1, true);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-true/mutation-2", () => { run (() => { cfg_mutation (2, true);
	});
	});
	Test.add_func ("/gen-own-2d/cfg/domain-true/mutation-3", () => { run (() => { cfg_mutation (3, true);
	});
	});
	Test.add_func ("/gen-own-2d/native/domain-true/wrong-heap", () => { run (() => { native_mutation (true, false);
	});
	});
	Test.add_func ("/gen-own-2d/native/domain-true/wrong-class", () => { run (() => { native_mutation (true, true);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-0/mutation-0", () => { run (() => { ssa_mutation (0, 0);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-0/mutation-1", () => { run (() => { ssa_mutation (0, 1);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-0/mutation-2", () => { run (() => { ssa_mutation (0, 2);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-0/mutation-3", () => { run (() => { ssa_mutation (0, 3);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-0/mutation-4", () => { run (() => { ssa_mutation (0, 4);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-0/mutation-5", () => { run (() => { ssa_mutation (0, 5);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-1/mutation-0", () => { run (() => { ssa_mutation (1, 0);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-1/mutation-1", () => { run (() => { ssa_mutation (1, 1);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-1/mutation-2", () => { run (() => { ssa_mutation (1, 2);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-1/mutation-3", () => { run (() => { ssa_mutation (1, 3);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-1/mutation-4", () => { run (() => { ssa_mutation (1, 4);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-1/mutation-5", () => { run (() => { ssa_mutation (1, 5);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-2/mutation-0", () => { run (() => { ssa_mutation (2, 0);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-2/mutation-1", () => { run (() => { ssa_mutation (2, 1);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-2/mutation-2", () => { run (() => { ssa_mutation (2, 2);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-2/mutation-3", () => { run (() => { ssa_mutation (2, 3);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-2/mutation-4", () => { run (() => { ssa_mutation (2, 4);
	});
	});
	Test.add_func ("/gen-own-2d/ssa/independent-domain-2/mutation-5", () => { run (() => { ssa_mutation (2, 5);
	});
	});
	return Test.run ();
}

}
