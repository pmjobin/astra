// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;

namespace Astra.Tests.RuntimeLifetimeSsa {
private const string API = "[CCode(destroy_function=\"astra_context17_destroy\",context=\"scoped-affine\")]handle Scoped;int query(borrowed Scoped context,int key);[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;owned Context context_open();int scalar_foreign(int value);void scalar_observe(int value);";
private const string CLASSES = "class Leaf{int code;init(int code){this.code=code;}}class Box{private owned Leaf child;init(owned Leaf child){this.child=move child;}int change(owned Leaf child){this.child=move child;return 1;}void put(owned Leaf child){this.child=move child;}}";
private const string SCOPED = "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf empty(){return null;}";
private SsaFunction function(SsaProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	error ("missing SSA function %s", name);
}

private RuntimeLifetimeSummary summary(SsaProgram program, string name) throws SsaError {
	var facts = SsaRuntimeLifetimes.analyze (program);
	var result = facts.lookup (function (program, name));
	assert (result != null && result.valid ());
	if (!result.complete) {
		error ("%s: %s", name, result.limitation);
	}
	return result;
}

private bool has(GenericArray<RuntimeScopeOrigin> origins, int parameter, string path = "") {
	foreach (var origin in origins) {
		if (origin.kind == RuntimeScopeOriginKind.OWNER_PARAMETER && origin.ordinal == parameter && origin.path == path) {
			return true;
		}
	}
	return false;
}

private SsaProgram build(string text, string? heap_boundary = null) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("lifetime-ssa.astra", text));
	assert (parsed.diagnostic == null);
	var imported = VapiParser.parse (new SourceFile.from_text ("lifetime-ssa.vapi", API));
	assert (imported.diagnostic == null);
	SemanticResult? analyzed;
	if (heap_boundary == null) {
		analyzed = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (imported.file), VapiNormalizer.normalize_handles (imported.file));
	} else {
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (parsed.unit);
		var boundaries = new GenericArray<FunctionDeclarationSyntax> ();
		foreach (string name in heap_boundary.split (",")) {
			bool found = false;
			foreach (var declaration in parsed.unit.functions) {
				if (declaration.name.spelling () == name) {
					boundaries.add (declaration);
					found = true;
				}
			}
			assert (found);
		}
		analyzed = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), VapiNormalizer.normalize (imported.file), VapiNormalizer.normalize_handles (imported.file), null, boundaries);
	} if (analyzed.diagnostic != null) {
		error ("%s", analyzed.diagnostic.message);
	}
	CheckedProgram? source = analyzed.program;
	analyzed = null;
	var checked_reference = WeakRef (source.functions[0]);
	CoreProgram? original = CoreBuilder.build (source);
	CoreProgram? core = CoreGenericMonomorphizer.build (original);
	original = null;
	source = null;
	assert (checked_reference.get () == null);
	var core_reference = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_reference.get () == null);
	var cfg_reference = WeakRef (cfg.functions[0]);
	var ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_reference.get () == null);
	SsaVerifier.verify (ssa);
	return ssa;
}

private void constructor_and_versions() {
	try {
		SsaProgram? ssa = build (CLASSES + "owned Box wrap(owned Leaf input){var box=new Box(move input);return move box;}owned Box forward(owned Leaf input){var result=wrap(move input);return move result;}void compare(borrowed Box box,owned Leaf incoming,int count){bool ignored=0<count<box.change(move incoming);}void loop(borrowed Box box,owned Leaf incoming,int count){while(count>0){box.put(move incoming);break;}}int main(){return 0;}");
		var result = summary (ssa, "forward");
		var origins = result.equations.requirements (result.result, "f0");
		assert (origins.length == 1 && has (origins, 0));
		assert (result.equations.requirements (result.result, "", false).length == 0);
		var conditional = summary (ssa, "compare");
		origins = conditional.equations.requirements (conditional.update (0), "f0");
		assert (has (origins, 0, "f0") && has (origins, 1));
		var loop = summary (ssa, "loop");
		origins = loop.equations.requirements (loop.update (0), "f0");
		assert (has (origins, 0, "f0") && has (origins, 1));
		var weak = WeakRef (function (ssa, "forward"));
		ssa = null;
		assert (weak.get () == null);
		assert (result.equations.requirements (result.result).length == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_declaration() {
	try {
		var client = Parser.parse (new SourceFile.from_text ("lifetime-ssa-client.astra", "int main(){return opaque();}"));
		var file = new SourceFile.from_text ("lifetime-ssa-native.astra", "int opaque(){return 0;}", true);
		var imported = Parser.parse (file);
		assert (client.diagnostic == null && imported.diagnostic == null);
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (client.unit);
		units.add (imported.unit);
		var registry = new NativeDeclarationRegistry ();
		registry.add_types (file, new GenericArray<string> ());
		registry.add (file, new NativeDeclarationIdentity ("lifetime-ssa-native", "F:opaque", "lifetime_opaque", "test-declaration"));
		var source = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
		if (source.diagnostic != null) {
			error ("%s", source.diagnostic.message);
		}
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (source.program))));
		var facts = SsaRuntimeLifetimes.analyze (ssa);
		assert (function (ssa, "opaque").declaration_only ());
		assert (facts.lookup (function (ssa, "opaque")) == null && !facts.lookup (function (ssa, "main")).complete);
		var origins = new SsaCodeOrigins (ssa);
		assert (origins.addressed_functions ().length == 0);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void admission_inventory() {
	try {
		var ssa = build (CLASSES + "struct Packet{owned Leaf item;int code;}[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Holder{Packet packet;init(Packet packet){this.packet=move packet;}}int main(){var context=context_open();var leaf=new Leaf(7);Packet packet={item=move leaf,code=9};var result=try_new(context) Holder(move packet);return 0;}");
		int restored = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var restore = instruction as SsaRecordAdmissionRestore;
					if (restore != null) {
						assert (restore.original.shape.leaves.length == 2 && restore.owning_leaf (0) && !restore.owning_leaf (1));
						restored++;
					}
				}
			}
		}
		assert (restored == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private SsaFunction replace_entry(SsaProgram program, SsaFunction original, SsaTerminator terminator, SemanticType? result_type = null, SsaCleanupContract? result_cleanup = null) throws SsaError {
	assert (original.blocks.length == 1);
	var entry = new SsaBlock (original.entry.span, 0, original.entry.source_ordinal);
	foreach (var instruction in original.entry.instructions) {
		entry.instructions.add (instruction);
	}
	entry.complete (terminator);
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (entry);
	var result = new SsaFunction (original.span, original.name_span, original.name, result_type ?? original.return_type, original.ordinal, original.parameters, blocks, entry, result_cleanup ?? original.owned_cleanup);
	result.heap_result = result_type != null || original.heap_result;
	result.bind_floating_policy (original.floating_policy);
	foreach (var storage in original.object_storage) {
		result.object_storage.add (storage);
	}
	foreach (var owner in original.heap_owners) {
		result.heap_owners.add (owner);
	}
	foreach (var storage in original.buffer_storage) {
		result.buffer_storage.add (storage);
	}
	foreach (var storage in original.storage) {
		result.storage.add (storage);
	}
	program.functions[original.ordinal] = result;
	return result;
}

// Isolate the SSA lifetime component after genuine Source/Core/CFG/SSA
// lowering. Public scoped-derived admission remains guarded elsewhere.
private SsaObjectStorage inject_scoped_leaf(SsaProgram program, SsaFunction target) throws SsaError {
	SsaScopedAllocator? factory = null;
	SsaValue? context = null;
	foreach (var parameter in target.parameters) {
		if (parameter.semantic_type.is_scoped_allocator ()) {
			context = parameter;
		}
	}
	foreach (var block in target.blocks) {
		foreach (var instruction in block.instructions) {
			if (instruction is SsaScopedAllocator) {
				factory = (SsaScopedAllocator) instruction;
				context = factory.result;
			}
		}
	}
	assert (context != null);
	foreach (var block in target.blocks) {
		for (int c = 0; c < block.instructions.length; c++) {
			var call = block.instructions[c] as SsaCallInstruction;
			if (call == null || call.target.name != "empty") {
				continue;
			}
			SsaHeapOwner? owner = null;
			foreach (var instruction in block.instructions) {
				var event = instruction as SsaHeapOwnerEvent;
				if (event != null && event.value == call.result && event.action == SsaHeapOwnerAction.ACQUIRE && owner == null) {
					owner = event.owner;
				}
			}
			assert (owner != null && owner.text_extent != null);
			var storage = new SsaObjectStorage (call.span, owner.cleanup.object_class, target.object_storage.length, owner.text_extent.ordinal);
			storage.text_extent = owner.text_extent;
			storage.cleanup_rank = owner.source_ordinal;
			storage.heap_allocated = storage.transferable = true;
			target.object_storage.add (storage);
			var selection = new SsaStorageReceiverInstruction (call.span, storage, storage.object_class.constructor.receiver.contract, 50000, context, factory == null ? null : factory.owner);
			var construction = new SsaLifecycleCallInstruction (call.span, storage.object_class.constructor, storage, new GenericArray<SsaValue> (), selection.result);
			var reference = new SsaObjectReferenceInstruction (call.span, storage, 50001);
			var replacements = new HashTable<SsaNode, SsaNode> (direct_hash, direct_equal);
			foreach (var source in block.instructions) {
				var cleanup = source as SsaCleanupInstruction;
				if (cleanup != null && cleanup.value == call.result) {
					replacements.insert (cleanup, new SsaCleanupInstruction (cleanup.span, reference.result, cleanup.cleanup));
				}
				var consumer = source as SsaCallInstruction;
				if (consumer == null || consumer == call) {
					continue;
				}
				for (int a = 0; a < consumer.arguments.length; a++) {
					if (consumer.arguments[a] == call.result) {
						consumer.arguments[a] = reference.result;
					}
				}
				for (int a = 0; a < consumer.owned_arguments.length; a++) {
					var argument = consumer.owned_arguments[a];
					if (argument.value != call.result) {
						continue;
					}
					var updated = new SsaOwnedArgument (argument.span, argument.parameter, reference.result, argument.cleanup, argument.source_ordinal, argument.source_after_commit, argument.source_storage);
					consumer.owned_arguments[a] = updated;
					replacements.insert (argument, updated);
				}
			}
			foreach (var source in block.instructions) {
				var event = source as SsaHeapOwnerEvent;
				if (event != null && event.value == call.result) {
					replacements.insert (event, new SsaHeapOwnerEvent (event.span, event.owner, event.action, reference.result, replacements.contains (event.effect) ? replacements.lookup (event.effect) : event.effect));
				}
			}
			block.instructions.remove_index (c);
			block.instructions.insert (c++, selection);
			if (factory != null) {
				block.instructions.insert (c++, new SsaHeapOwnerEvent (selection.span, factory.owner, SsaHeapOwnerAction.READ, context, selection));
			}
			block.instructions.insert (c++, construction);
			block.instructions.insert (c, reference);
			for (int i = 0; i < block.instructions.length; i++) {
				if (replacements.contains (block.instructions[i])) {
					block.instructions[i] = (SsaInstruction) replacements.lookup (block.instructions[i]);
				}
			}
			var returned = block.terminator as SsaOwnershipReturn;
			if (returned != null && returned.value == call.result) {
				replace_entry (program, target, new SsaOwnershipReturn (returned.span, reference.result, returned.provenance, returned.source_parameter));
			}
			return storage;
		}
	}
	error ("SSA fixture lost empty producer");
}

private void refused(SsaProgram program, string diagnostic) {
	bool rejected = false;
	try {
		SsaRuntimeLifetimes.verify (program);
	} catch (SsaError failure) {
		Test.message ("%s", failure.message);
		assert (failure.message.contains (diagnostic));
		rejected = true;
	}
	assert (rejected);
}

private void scoped_retirement() {
	try {
		for (int mode = 0; mode < 3; mode++) {
			var ssa = build (SCOPED + "int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();return 0;}int main(){return 0;}");
			var target = function (ssa, "exercise");
			inject_scoped_leaf (ssa, target);
			var block = target.entry;
			int context_end = -1;
			int destination = -1;
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				if (cleanup != null && cleanup.value.semantic_type.is_scoped_allocator ()) {
					context_end = i;
				}
				if (mode == 1 && block.instructions[i] is SsaStorageReceiverInstruction || mode == 2 && cleanup != null && cleanup.value.semantic_type.nominal_name () == "ScopedLeaf") {
					destination = i;
				}
			}
			assert (context_end > 0);
			if (mode == 0) {
				summary (ssa, "exercise");
			} else {
				assert (destination > 0 && destination < context_end);
				var cleanup = block.instructions[context_end];
				var ended = block.instructions[context_end + 1];
				assert (ended is SsaHeapOwnerEvent);
				block.instructions.remove_index (context_end + 1);
				block.instructions.remove_index (context_end);
				block.instructions.insert (destination, cleanup);
				block.instructions.insert (destination + 1, ended);
				refused (ssa, mode == 1 ? "current exact owner pointer" : "before a derived owner");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void return_leaf(SsaProgram program, SsaFunction target) throws SsaError {
	SsaHeapOwner? owner = null;
	SsaValue? pointer = null;
	foreach (var source in target.entry.instructions) {
		var event = source as SsaHeapOwnerEvent;
		if (event != null && event.action == SsaHeapOwnerAction.ACQUIRE && event.value.semantic_type.nominal_name () == "ScopedLeaf") {
			owner = event.owner;
			pointer = event.value;
		}
	}
	assert (owner != null && pointer != null);
	for (int i = 0; i < target.entry.instructions.length; i++) {
		var cleanup = target.entry.instructions[i] as SsaCleanupInstruction;
		if (cleanup == null || cleanup.value != pointer) {
			continue;
		}
		var empty = new SsaNullPointerConstant (cleanup.span, pointer.semantic_type);
		var retired = new SsaCleanupInstruction (cleanup.span, empty, cleanup.cleanup);
		target.entry.instructions[i] = retired;
		var ended = target.entry.instructions[i + 1] as SsaHeapOwnerEvent;
		assert (ended != null && ended.owner == owner);
		target.entry.instructions[i + 1] = new SsaHeapOwnerEvent (ended.span, owner, SsaHeapOwnerAction.END, empty, retired);
		target.entry.instructions.insert (i, new SsaHeapOwnerEvent (cleanup.span, owner, SsaHeapOwnerAction.RETURN, pointer));
		replace_entry (program, target, new SsaOwnershipReturn (cleanup.span, pointer, ObjectResultProvenance.HEAP_OBJECT), pointer.semantic_type, cleanup.cleanup);
		return;
	}
	error ("SSA fixture lost leaf retirement");
}

private void scoped_formal() {
	try {
		var ssa = build (SCOPED + "int exercise(borrowed Scoped context){var leaf=empty();return 0;}int main(){return 0;}");
		var target = function (ssa, "exercise");
		inject_scoped_leaf (ssa, target);
		return_leaf (ssa, target);
		var result = summary (ssa, "exercise");
		var origins = result.equations.requirements (result.result);
		assert (origins.length == 1 && origins[0].kind == RuntimeScopeOriginKind.CONTEXT_PARAMETER && origins[0].ordinal == 0);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_local_result() {
	try {
		var ssa = build (SCOPED + "int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();return 0;}int main(){return 0;}");
		var target = function (ssa, "exercise");
		inject_scoped_leaf (ssa, target);
		return_leaf (ssa, target);
		refused (ssa, "result retains a scoped local allocation");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_pending_handoff() {
	try {
		foreach (bool reordered in new bool[] { false, true }) {
			var ssa = build (SCOPED + "void consume(owned ScopedLeaf input){}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();consume(move leaf);return 0;}int main(){return 0;}");
			var target = function (ssa, "exercise");
			inject_scoped_leaf (ssa, target);
			var block = target.entry;
			int context_end = -1;
			int moved = -1;
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				if (cleanup != null && cleanup.value.semantic_type.is_scoped_allocator ()) {
					context_end = i;
				}
				var event = block.instructions[i] as SsaHeapOwnerEvent;
				if (event != null && event.action == SsaHeapOwnerAction.MOVE && event.effect is SsaOwnedArgument) {
					moved = i;
				}
			}
			assert (moved > 0 && context_end > moved);
			if (!reordered) {
				summary (ssa, "exercise");
			} else {
				var cleanup = block.instructions[context_end];
				var ended = block.instructions[context_end + 1];
				block.instructions.remove_index (context_end + 1);
				block.instructions.remove_index (context_end);
				block.instructions.insert (moved + 1, cleanup);
				block.instructions.insert (moved + 2, ended);
				refused (ssa, "before a derived owner or pending handoff");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_storage_extent() {
	try {
		var ssa = build (SCOPED + "int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();return 0;}int main(){return 0;}");
		var target = function (ssa, "exercise");
		var storage = inject_scoped_leaf (ssa, target);
		storage.text_extent = null;
		refused (ssa, "actual ObjectStorage cleanup extent");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_receiver_store() {
	try {
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		foreach (bool outer in new bool[] { false, true }) {
			var ssa = build (SCOPED + host + "int exercise(){" + (outer ? "var box=new Host(null);" : "") + "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);" + (outer ? "" : "var box=new Host(null);") + "var leaf=empty();box.put(move leaf);}return 0;}int main(){return 0;}");
			var target = function (ssa, "exercise");
			inject_scoped_leaf (ssa, target);
			if (outer) {
				refused (ssa, "cannot outlive context");
			} else {
				summary (ssa, "exercise");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void move_leaf(SsaFunction target) {
	SsaHeapOwner? leaf = null;
	SsaHeapOwner? other = null;
	SsaValue? pointer = null;
	SsaValue? old = null;
	var block = target.entry;
	foreach (var source in block.instructions) {
		var event = source as SsaHeapOwnerEvent;
		if (event == null || event.action != SsaHeapOwnerAction.ACQUIRE || event.value.semantic_type.nominal_name () != "ScopedLeaf") {
			continue;
		}
		if (leaf == null) {
			leaf = event.owner;
			pointer = event.value;
		} else {
			other = event.owner;
			old = event.value;
		}
	}
	assert (leaf != null && other != null && pointer != null && old != null);
	for (int i = 0; i < block.instructions.length; i++) {
		var cleanup = block.instructions[i] as SsaCleanupInstruction;
		if (cleanup == null) {
			continue;
		}
		if (cleanup.value == pointer) {
			var empty = new SsaNullPointerConstant (cleanup.span, pointer.semantic_type);
			var retired = new SsaCleanupInstruction (cleanup.span, empty, cleanup.cleanup);
			block.instructions[i] = retired;
			block.instructions[i + 1] = new SsaHeapOwnerEvent (cleanup.span, leaf, SsaHeapOwnerAction.END, empty, retired);
		} else if (cleanup.value == old) {
			var retired = new SsaCleanupInstruction (cleanup.span, pointer, cleanup.cleanup);
			block.instructions[i] = retired;
			block.instructions[i + 1] = new SsaHeapOwnerEvent (cleanup.span, other, SsaHeapOwnerAction.END, pointer, retired);
			block.instructions.insert (i++, new SsaHeapOwnerEvent (cleanup.span, leaf, SsaHeapOwnerAction.MOVE, pointer));
			block.instructions.insert (i++, cleanup);
			block.instructions.insert (i++, new SsaHeapOwnerEvent (cleanup.span, other, SsaHeapOwnerAction.END, old, cleanup));
			block.instructions.insert (i++, new SsaHeapOwnerEvent (cleanup.span, other, SsaHeapOwnerAction.ACQUIRE, pointer));
		}
	}
}

private void scoped_owner_move() {
	try {
		foreach (bool reordered in new bool[] { false, true }) {
			var ssa = build (SCOPED + "int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();var other=empty();return 0;}int main(){return 0;}");
			var target = function (ssa, "exercise");
			inject_scoped_leaf (ssa, target);
			move_leaf (target);
			var block = target.entry;
			int context_end = -1;
			int other_end = -1;
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as SsaCleanupInstruction;
				if (cleanup != null && cleanup.value.semantic_type.is_scoped_allocator ()) {
					context_end = i;
				}
				if (cleanup != null && cleanup.value.semantic_type.nominal_name () == "ScopedLeaf" && !(cleanup.value is SsaNullPointerConstant)) {
					other_end = i;
				}
			}
			assert (other_end > 0 && context_end > other_end);
			if (!reordered) {
				summary (ssa, "exercise");
			} else {
				var cleanup = block.instructions[context_end];
				var ended = block.instructions[context_end + 1];
				block.instructions.remove_index (context_end + 1);
				block.instructions.remove_index (context_end);
				block.instructions.insert (other_end, cleanup);
				block.instructions.insert (other_end + 1, ended);
				refused (ssa, "before a derived owner");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_contract_roles() {
	try {
		for (int mode = 0; mode < 4; mode++) {
			var graph = new RuntimeLifetimeEquations ();
			int result = graph.absent ();
			var stores = new GenericArray<RuntimeLifetimeStore> ();
			if (mode == 1) {
				result = graph.input (0);
			} else if (mode == 2) {
				var roots = new GenericArray<RuntimeScopeOrigin> ();
				roots.add (new RuntimeScopeOrigin.context_input (0));
				result = graph.product (roots, new HashTable<string, int> (str_hash, str_equal));
			} else if (mode == 3) {
				stores.add (new RuntimeLifetimeStore (0, graph.absent ()));
			}
			graph.seal ();
			var contract = new RuntimeLifetimeSummary (graph, result, new HashTable<int, int> (direct_hash, direct_equal), stores, "");
			var client = Parser.parse (new SourceFile.from_text ("lifetime-contract-client.astra", "int main(){return opaque(7);}"));
			var file = new SourceFile.from_text ("lifetime-contract-native.astra", "int opaque(int value){return 0;}", true);
			var imported = Parser.parse (file);
			var units = new GenericArray<CompilationUnitSyntax> ();
			units.add (client.unit);
			units.add (imported.unit);
			var registry = new NativeDeclarationRegistry ();
			registry.add_types (file, new GenericArray<string> ());
			registry.add (file, new NativeDeclarationIdentity ("lifetime-contract-native", "F:opaque", "lifetime_opaque", "test-declaration", "", false, "", "", contract.encode ()));
			var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
			if (mode == 0) {
				assert (checked.diagnostic == null);
				var ssa = SsaBuilder.build (CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program))));
				var facts = SsaRuntimeLifetimes.analyze (ssa);
				assert (facts.lookup (function (ssa, "opaque")).complete && facts.lookup (function (ssa, "main")).complete);
			} else {
				assert (checked.diagnostic != null && checked.diagnostic.message.contains ("native lifetime contract"));
				Test.message ("%s", checked.diagnostic.message);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_composite_coordinate_version() {
	try {
		for (int mode = 0; mode < 3; mode++) {
			var graph = new RuntimeLifetimeEquations ();
			int result = mode == 2 ? graph.input (1) : graph.absent ();
			graph.seal ();
			var descriptor = new RuntimeLifetimeSummary (graph, result, new HashTable<int, int> (direct_hash, direct_equal), new GenericArray<RuntimeLifetimeStore> (), "");
			if (mode != 0) {
				descriptor = descriptor.logical_archive ();
			}
			var client = Parser.parse (new SourceFile.from_text ("coordinate-version-client.astra", "int main(){Pair value={left=1,right=2};return opaque(value);}"));
			var file = new SourceFile.from_text ("coordinate-version-native.astra", "struct Pair{int left;int right;}int opaque(Pair value){return 0;}", true);
			var imported = Parser.parse (file);
			assert (client.diagnostic == null && imported.diagnostic == null);
			var units = new GenericArray<CompilationUnitSyntax> ();
			units.add (client.unit);
			units.add (imported.unit);
			var registry = new NativeDeclarationRegistry ();
			var names = new GenericArray<string> ();
			names.add ("Pair");
			registry.add_types (file, names);
			registry.add (file, new NativeDeclarationIdentity ("coordinate-version-native", "F:opaque", "coordinate_opaque", "test-declaration", "", false, "", "", descriptor.encode ()));
			var checked = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
			if (mode != 1) {
				assert (checked.diagnostic != null && checked.diagnostic.message.contains (mode == 0 ? "require rebuild with runtime-lifetime-logical/1" : "equation input differs"));
				Test.message ("mode %d: %s", mode, checked.diagnostic.message);
				continue;
			}
			assert (checked.diagnostic == null);
			CheckedProgram? source = checked.program;
			checked = null;
			var source_weak = WeakRef (source.functions[0]);
			CoreProgram? original = CoreBuilder.build (source);
			CoreProgram? core = CoreGenericMonomorphizer.build (original);
			original = null;
			source = null;
			assert (source_weak.get () == null);
			var core_weak = WeakRef (core.functions[0]);
			CfgProgram? cfg = CfgBuilder.build (core);
			core = null;
			assert (core_weak.get () == null);
			var cfg_weak = WeakRef (cfg.functions[0]);
			var ssa = SsaBuilder.build (cfg);
			cfg = null;
			assert (cfg_weak.get () == null);
			SsaVerifier.verify (ssa);
			summary (ssa, "opaque");
			summary (ssa, "main");
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void foreign_scalar_contracts() {
	try {
		var ssa = build ("int observe(borrowed Scoped context){scalar_observe(7);return scalar_foreign(query(context,7));}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);return observe(context);}int factory(){var context=context_open();return 0;}int main(){return 0;}");
		summary (ssa, "observe");
		summary (ssa, "exercise");
		var facts = SsaRuntimeLifetimes.analyze (ssa);
		assert (facts.lookup (function (ssa, "factory")).complete);
		SsaCFunction? query = null;
		foreach (var target in ssa.c_functions) {
			if (target.name == "query") {
				query = target;
			}
		}
		assert (query != null);
		var original = query.parameters[0];
		query.parameters[0] = new SsaFunctionParameter (original.span, original.name_span, original.name, original.semantic_type, original.ordinal, PointerParameterContract.OWNED_TRANSFER);
		facts = SsaRuntimeLifetimes.analyze (ssa);
		assert (!facts.lookup (function (ssa, "observe")).complete);
		query.parameters[0] = original;
		summary (ssa, "observe");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_carrier_signature() {
	try {
		var program = build (SCOPED.replace ("init(){}", "int code;init(){this.code=7;}int read(){int value=this.code;return value;}") + "class Inner{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}class Host{private owned Inner child;init(owned Inner child){this.child=move child;}}extern(C) void* opaque_ptr();void opaque(){opaque_ptr();}void probe(borrowed Host box){}int main(){return 0;}");
		summary (program, "probe");
		var target = function (program, "probe");
		var call = new SsaCallInstruction (target.span, null, -1, function (program, "opaque"), new GenericArray<SsaValue> ());
		target.entry.instructions.insert (0, call);
		bool rejected = false;
		try {
			SsaRuntimeLifetimes.verify (program);
		} catch (SsaError failure) {
			rejected = failure.message.contains ("scoped lifetime proof is incomplete");
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		target.entry.instructions.remove_index (0);
		SsaRuntimeLifetimes.verify (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owned_factory_roles() {
	try {
		var program = build (SCOPED + "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}int probe(borrowed Host host){var context=context_open();return 0;}int main(){return 0;}");
		summary (program, "probe");
		var target = function (program, "probe");
		SsaCFunction? factory = null;
		foreach (var candidate in program.c_functions) {
			if (candidate.name == "context_open") {
				factory = candidate;
			}
		}
		assert (factory != null && factory.owned_cleanup != null);
		foreach (bool wrong in new bool[] { false, true }) {
			var cleanup = wrong ? new SsaCleanupContract ("wrong_context_cleanup", target.span, 0) : null;
			var mutant = new SsaCFunction (factory.span, factory.name_span, factory.name, factory.metadata, factory.abi, factory.return_type, factory.parameter_types, factory.ordinal, cleanup, factory.parameters);
			var call = new SsaCCallInstruction (target.span, factory.return_type, 50000, mutant, new GenericArray<SsaValue> ());
			target.entry.instructions.insert (0, call);
			bool rejected = false;
			try {
				SsaRuntimeLifetimes.verify (program);
			} catch (SsaError failure) {
				rejected = failure.message.contains ("foreign call requires");
				Test.message ("%s", failure.message);
			}
			assert (rejected);
			target.entry.instructions.remove_index (0);
			SsaRuntimeLifetimes.verify (program);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void fallible_owner_inputs() {
	try {
		var program = build (SCOPED + "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}owned ScopedLeaf refuse(borrowed Context context,owned ScopedLeaf input){var host=try_new(context)Host(move input);if(host==null){return move input;}return null;}int main(){return 0;}");
		var result = summary (program, "refuse");
		var roots = result.equations.requirements (result.result);
		assert (roots.length == 1 && has (roots, 1));
		bool changed = false;
		foreach (var block in function (program, "refuse").blocks) {
			foreach (var source in block.instructions) {
				var call = source as SsaLifecycleCallInstruction;
				if (call == null || call.input_restores.length == 0) {
					continue;
				}
				var restored = call.input_restores[0];
				call.input_restores.remove_index (0);
				refused (program, "exact captured owner/constructor channel");
				call.input_restores.insert (0, restored);
				summary (program, "refuse");
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void exceptional_results() {
	try {
		string fault = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}";
		var ssa = build (fault + SCOPED + "owned ScopedLeaf attempt(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(\"bad\");}return move input;}owned ScopedLeaf caught(owned ScopedLeaf input,int mode){try{var result=attempt(move input,mode);return move result;}catch(Fault error){return null;}}int main(){return 0;}", "attempt,caught");
		var attempted = summary (ssa, "attempt");
		assert (attempted.has_exception && attempted.equations.requirements (attempted.exception).length == 0 && has (attempted.equations.requirements (attempted.result), 0));
		var caught = summary (ssa, "caught");
		assert (!caught.has_exception && has (caught.equations.requirements (caught.result), 0));

		var called = function (ssa, "caught");
		SsaCallInstruction? throwing_call = null;
		foreach (var block in called.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (call != null && call.target.name == "attempt") {
					throwing_call = call;
				}
			}
		}
		assert (throwing_call != null && throwing_call.exception_result != null);
		var channel = throwing_call.exception_result;
		throwing_call.exception_result = null;
		refused (ssa, "exceptional lifetime channel");
		throwing_call.exception_result = channel;
		summary (ssa, "caught");
		assert (called.handlers.length == 1);
		var handler = called.handlers[0];
		called.handlers.remove_index (0);
		refused (ssa, "protected exception channel");
		called.handlers.add (handler);
		summary (ssa, "caught");
		var weak = WeakRef (function (ssa, "attempt"));
		ssa = null;
		assert (weak.get () == null);
		assert (attempted.equations.requirements (attempted.result).length == 1);
		ssa = build (fault + SCOPED + "void consume(owned ScopedLeaf input,int marker){}int later()throws Fault{throw new Fault(\"before\");}owned ScopedLeaf restore(owned ScopedLeaf input){try{consume(move input,later());}catch(Fault error){return move input;}return null;}int main(){return 0;}", "consume,restore");
		var restored = summary (ssa, "restore");
		assert (has (restored.equations.requirements (restored.result), 0));
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		ssa = build (fault + SCOPED + host + "void alter(borrowed Host box,owned ScopedLeaf input)throws Fault{box.put(move input);throw new Fault(\"changed\");}void observe(borrowed Host box,owned ScopedLeaf input){try{alter(box,move input);}catch(Fault error){}}int main(){return 0;}", "alter,observe");
		foreach (string name in new string[] { "alter", "observe" }) {
			var effect = summary (ssa, name);
			assert (effect.updated_inputs ().length == 1 && effect.store_count == 1 && has (effect.equations.requirements (effect.update (0), "f0"), 1));
		}
		string throwing_host = "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child,int mode)throws Fault{this.child=move child;if(mode!=0){throw new Fault(\"partial\");}}}";
		ssa = build (fault + SCOPED + throwing_host + "owned ScopedLeaf recover(borrowed Context context,owned ScopedLeaf input,int mode){try{var host=try_new(context)Host(move input,mode);if(host==null){return move input;}}catch(Fault error){}return null;}int main(){return 0;}", "recover");
		var recovered = summary (ssa, "recover");
		assert (!recovered.has_exception && has (recovered.equations.requirements (recovered.result), 1));
		bool abort_checked = false;
		foreach (var target in ssa.functions) {
			if (!(target is SsaConstructor) || target.throws_type == null) {
				continue;
			}
			foreach (var block in target.blocks) {
				if (!(block.terminator is SsaExceptionReturn) || block.instructions.length == 0) {
					continue;
				}
				int last = (int) block.instructions.length - 1;
				var abort = block.instructions[last] as SsaConstructorAbort;
				if (abort == null) {
					continue;
				}
				block.instructions.remove_index (last);
				bool rejected = false;
				try {
					SsaVerifier.verify (ssa);
				} catch (SsaError failure) {
					rejected = failure.message.contains ("partial-field retirement");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				block.instructions.insert (last, abort);
				SsaVerifier.verify (ssa);
				abort_checked = true;
			}
		}
		assert (abort_checked);
		string owned_fault = "[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}";
		ssa = build (SCOPED + owned_fault + "void raise(owned ScopedLeaf input)throws Fault{throw new Fault(move input);}void reroute(owned ScopedLeaf input)throws Fault{try{raise(move input);}catch(Fault error){throw;}}int main(){return 0;}", "raise,reroute");
		var raised = summary (ssa, "raise");
		assert (raised.has_exception && has (raised.equations.requirements (raised.exception), 0));
		var rerouted = summary (ssa, "reroute");
		assert (rerouted.has_exception && has (rerouted.equations.requirements (rerouted.exception), 0));
		foreach (bool outside in new bool[] { false, true }) {
			Test.message ("scoped exception outside=%d", outside ? 1 : 0);
			string body = outside ? "try{owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}}catch(Fault error){}" : "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);try{var leaf=empty();throw new Fault(move leaf);}catch(Fault error){}}";
			ssa = build (SCOPED + owned_fault + "int exercise(){" + body + "return 0;}int main(){return 0;}");
			inject_scoped_leaf (ssa, function (ssa, "exercise"));
			if (outside) {
				refused (ssa, "context");
			} else {
				summary (ssa, "exercise");
			}
		}
		foreach (bool outside in new bool[] { false, true }) {
			Test.message ("called scoped exception outside=%d", outside ? 1 : 0);
			string body = outside ? "try{owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();raise(move leaf);}}catch(Fault error){}" : "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);try{var leaf=empty();raise(move leaf);}catch(Fault error){}}";
			ssa = build (SCOPED + owned_fault + "void raise(owned ScopedLeaf input)throws Fault{throw new Fault(move input);}int exercise(){" + body + "return 0;}int main(){return 0;}", "raise");
			inject_scoped_leaf (ssa, function (ssa, "exercise"));
			if (outside) {
				refused (ssa, "context");
			} else {
				summary (ssa, "exercise");
			}
		}
		string mutable_fault = owned_fault.replace ("virtual property", "void put(owned ScopedLeaf child){this.child=move child;}virtual property");
		ssa = build (SCOPED + mutable_fault + "void change(owned ScopedLeaf input){try{throw new Fault(null);}catch(Fault error){error.put(move input);}}int main(){return 0;}", "change");
		summary (ssa, "change");
		var changed = function (ssa, "change");
		assert (changed.handlers.length == 1);
		var matched = changed.handlers[0].matched;
		int borrow_at = -1, cleanup_at = -1;
		for (int i = 0; i < matched.instructions.length; i++) {
			if (matched.instructions[i] == changed.handlers[0].borrow) {
				borrow_at = i;
			}
			if (matched.instructions[i] is SsaCleanupInstruction && ((SsaCleanupInstruction) matched.instructions[i]).value == changed.handlers[0].borrow.exception) {
				cleanup_at = i;
			}
		}
		assert (borrow_at >= 0 && cleanup_at > borrow_at);
		var retirement = matched.instructions[cleanup_at];
		var ended = matched.instructions[cleanup_at + 1];
		assert (ended is SsaHeapOwnerEvent);
		matched.instructions.remove_index (cleanup_at + 1);
		matched.instructions.remove_index (cleanup_at);
		matched.instructions.insert (borrow_at, retirement);
		matched.instructions.insert (borrow_at + 1, ended);
		refused (ssa, "private exception owner");
		matched.instructions.remove_index (borrow_at + 1);
		matched.instructions.remove_index (borrow_at);
		matched.instructions.insert (cleanup_at, retirement);
		matched.instructions.insert (cleanup_at + 1, ended);
		summary (ssa, "change");
		ssa = build (SCOPED + mutable_fault + "void branch(owned ScopedLeaf input,int mode)throws Fault{try{if(mode!=0){throw new Fault(null);}throw new Fault(null);}catch(Fault error){error.put(move input);throw;}}void repeat(owned ScopedLeaf input,int count){int remaining=count;while(remaining>0){try{throw new Fault(null);}catch(Fault error){error.put(null);}remaining=remaining-1;}}int main(){return 0;}", "branch,repeat");
		var branched = summary (ssa, "branch");
		assert (branched.has_exception && has (branched.equations.requirements (branched.exception), 0));
		summary (ssa, "repeat");
		ssa = build (SCOPED + owned_fault + "int exercise(){owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);int count=2;while(count>0){try{var leaf=empty();throw new Fault(move leaf);}catch(Fault error){}count=count-1;}}return 0;}int main(){return 0;}");
		inject_scoped_leaf (ssa, function (ssa, "exercise"));
		summary (ssa, "exercise");
		ssa = build (SCOPED + owned_fault + "void escape()throws Fault{owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}int main(){return 0;}");
		inject_scoped_leaf (ssa, function (ssa, "escape"));
		refused (ssa, "scoped");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void checked_constructor_rollback() {
	try {
		string declarations = "[ExceptionRoot]class Fault{init(){}virtual property string message{get{return \"failed\";}}}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Item{private int code;init(int code)throws Fault{this.code=code;if(code<0){throw new Fault();}}int read(){return this.code;}}";
		foreach (bool fallible in new bool[] { false, true }) {
			for (int mode = 0; mode < 4; mode++) {
				var program = build (declarations + "int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,2,1);try{var item=" + (fallible ? "try_new" : "new") + "(context)Item(-1);if(item!=null){return item.read();}}catch(Fault error){if(query(context,1)!=0){return 1;}}return 0;}int main(){return 0;}");
				var target = function (program, "exercise");
				SsaLifecycleCallInstruction? constructor = null;
				SsaBlock? site = null;
				foreach (var block in target.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaLifecycleCallInstruction;
						if (call != null && call.constructs) {
							assert (constructor == null);
							constructor = call;
							site = block;
						}
					}
				}
				assert (constructor != null && site != null && constructor.exception_result != null);
				if (mode == 0) {
					var result = summary (program, "exercise");
					assert (result.complete && !result.has_exception && result.equations.requirements (result.result).length == 0);
					continue;
				}
				if (mode == 1) {
					constructor.exception_result = new SsaInstructionResult (constructor.span, constructor.exception_result.semantic_type, 100000);
				} else if (mode == 2) {
					site.instructions.insert (0, constructor);
				} else {
					constructor.exception_result = null;
				}
				bool rejected = false;
				try {
					SsaRuntimeLifetimes.verify (program);
				} catch (SsaError failure) {
					Test.message ("%s", failure.message);
					assert (failure.message.contains ("constructor rollback") || failure.message.contains ("exception") || failure.message.contains ("private owner binding"));
					rejected = true;
				}
				assert (rejected);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owned_record_admission() {
	try {
		for (int mode = 0; mode <= 15; mode++) {
			var program = build ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{init(){}}struct Packet{owned Leaf left;owned Leaf right;int marker;}[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private Packet packet;init(Packet packet){this.packet=move packet;}}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,1,7);var left=new(context)Leaf();var right=new(context)Leaf();Packet packet={left=move left,right=move right,marker=7};var host=try_new(context)Host(move packet);return 0;}int main(){return exercise();}");
			var target = function (program, "exercise");
			SsaFallibleRecordRestore? restored = null;
			SsaBlock? site = null;
			SsaCleanupInstruction? context_end = null;
			SsaHeapOwnerEvent? context_event = null;
			int position = -1;
			foreach (var block in target.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var restore = block.instructions[i] as SsaFallibleRecordRestore;
					if (restore != null) {
						assert (restored == null);
						restored = restore;
						site = block;
						position = i;
					}
					var cleanup = block.instructions[i] as SsaCleanupInstruction;
					if (cleanup != null && cleanup.value.semantic_type.is_scoped_allocator ()) {
						context_end = cleanup;
						context_event = i + 1 < block.instructions.length ? block.instructions[i + 1] as SsaHeapOwnerEvent : null;
					}
				}
			}
			assert (restored != null && site != null && position >= 0);
			var call = restored.call;
			var moved = restored.original;
			var acquired = restored.acquisition;
			assert (call != null && acquired != null && restored.results.leaves.length == 3);
			if (mode == 0) {
				summary (program, "exercise");
				continue;
			}
			if (mode == 1) {
				assert (call.record_restores.remove (restored));
			} else if (mode == 2) {
				call.record_restores.add (restored);
			} else if (mode == 3) {
				assert (call.record_moves.remove (moved));
			} else if (mode == 4) {
				call.record_moves.add (moved);
			} else if (mode == 5) {
				moved.consumer = null;
			} else if (mode == 6) {
				acquired.admission_restore = null;
			} else if (mode == 7) {
				restored.acquisition = null;
			} else if (mode == 8) {
				site.instructions.remove_index ((uint) position + 1);
			} else if (mode == 9) {
				acquired.leaves[0] = acquired.leaves[1];
			} else if (mode == 10) {
				var group = call.struct_arguments[0];
				call.struct_arguments[0] = new StructBoundaryGroup (group.source_ordinal + 1, group.first_leaf, group.shape);
			} else if (mode == 11) {
				call.arguments[0] = call.arguments[1];
			} else if (mode == 12) {
				restored.results.leaves[0] = restored.results.leaves[1];
			} else if (mode == 13) {
				site.instructions.insert (position + 1, restored);
			} else if (mode == 14) {
				site.instructions.remove_index ((uint) position);
				uint called = 0;
				assert (site.instructions.find (call, out called));
				site.instructions.insert ((int) called + 1, restored);
			} else {
				assert (context_end != null && context_event != null && context_event.action == SsaHeapOwnerAction.END);
				assert (site.instructions.remove (context_event) && site.instructions.remove (context_end));
				uint committed = 0;
				assert (site.instructions.find (moved, out committed));
				int after = (int) committed + 1 + (int) moved.owners.length;
				site.instructions.insert (after, context_end);
				site.instructions.insert (after + 1, context_event);
			}
			bool rejected = false;
			try {
				SsaRuntimeLifetimes.verify (program);
			} catch (SsaError failure) {
				Test.message ("%s", failure.message);
				assert (failure.message.contains (mode == 15 ? "before a derived owner or pending handoff" : "SSA record") || mode >= 6 && mode <= 9 && failure.message.contains ("requires exact initialized/live/moved disposition") || mode == 9 && failure.message.contains ("heap ownership lost exact original transfer/cleanup operand"));
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_buffer_admission() {
	try {
		for (int mode = 0; mode <= 7; mode++) {
			var program = build ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Host{private owned u8[] left;private owned i32[] right;init(owned u8[] left,owned i32[] right){this.left=move left;this.right=move right;}int count(){return len(this.left)+len(this.right);}}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,2,1);owned u8[] left=new u8[37];owned i32[] right=new i32[53];var host=try_new(context)Host(move left,move right);if(host==null){return len(left)+len(right);}if(len(left)!=0||len(right)!=0){return 1;}return host.count();}int main(){return exercise();}");
			var target = function (program, "exercise");
			SsaFallibleBufferRestore? restore = null;
			SsaBlock? site = null;
			uint position = 0;
			foreach (var block in target.blocks) {
				for (uint i = 0; i < block.instructions.length; i++) {
					if (block.instructions[i] is SsaFallibleBufferRestore) {
						restore = (SsaFallibleBufferRestore) block.instructions[i];
						site = block;
						position = i;
						break;
					}
				}
				if (restore != null) {
					break;
				}
			}
			assert (restore != null && site != null);
			var call = restore.call;
			var write = site.instructions[position + 1] as SsaBufferWriteInstruction;
			assert (call != null && write != null && call.buffer_arguments.length == 2);
			if (mode == 0) {
				summary (program, "exercise");
				continue;
			}
			if (mode == 1) {
				assert (call.buffer_restores.remove (restore));
			} else if (mode == 2) {
				site.instructions.remove_index (position + 1);
			} else if (mode == 3) {
				write.initializes = true;
			} else if (mode == 4) {
				site.instructions[position + 1] = new SsaBufferWriteInstruction (write.span, write.place, restore.argument.pair);
			} else if (mode == 5) {
				call.arguments[1] = call.arguments[3];
			} else if (mode == 6) {
				call.buffer_arguments.remove_index (0);
			} else {
				site.instructions.insert ((int) position + 2, restore);
			}
			refused (program, mode == 2 ? "definitely live captured owner" : "SSA buffer");
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_buffer_fields() {
	try {
		for (int mode = 0; mode <= 8; mode++) {
			var program = build ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Packet{private owned u8[] bytes;init(owned u8[] bytes,int marker){this.bytes=move bytes;}int count(){return len(this.bytes);}}int main(){return 0;}");
			var constructor = function (program, "init");
			assert (constructor.buffer_parameters.length == 1 && constructor.parameters.length == 3);
			var group = constructor.buffer_parameters[0];
			if (mode == 0) {
				var contract = summary (program, "init");
				assert (has (contract.equations.requirements (contract.update (-1), "f0"), 0));
				continue;
			}
			SsaBufferWriteInstruction? acquired = null, field = null;
			SsaBlock? acquired_block = null, field_block = null;
			SsaFunction? destructor = null;
			foreach (var candidate in program.functions) {
				if (candidate is SsaDestructor) {
					destructor = candidate;
				}
			}
			foreach (var block in constructor.blocks) {
				foreach (var instruction in block.instructions) {
					var write = instruction as SsaBufferWriteInstruction;
					if (write == null) {
						continue;
					}
					if (write.pair == group.pair) {
						acquired = write;
						acquired_block = block;
					}
					if (write.place.field != null) {
						field = write;
						field_block = block;
					}
				}
			}
			assert (acquired != null && acquired_block != null && field != null && field_block != null);
			if (mode == 1) {
				constructor.buffer_parameters[0] = new SsaBufferParameter (group.span, group.first_leaf + 1, group.source_ordinal, group.cleanup, group.pair);
			} else if (mode == 2) {
				var pair = new SsaBufferPair (group.span, group.pair.shape, group.pair.base_value, constructor.parameters[2]);
				constructor.buffer_parameters[0] = new SsaBufferParameter (group.span, group.first_leaf, group.source_ordinal, group.cleanup, pair);
			} else if (mode == 3) {
				acquired_block.instructions.insert (0, acquired);
			} else if (mode == 4) {
				acquired.initializes = false;
			} else if (mode == 5) {
				acquired.place.storage.text_extent = null;
			} else if (mode == 6) {
				constructor.buffer_parameters.remove_index (0);
			} else if (mode == 7) {
				var pair = new SsaBufferPair (field.span, field.pair.shape, field.pair.base_value, constructor.parameters[2]);
				var replaced = new SsaBufferWriteInstruction (field.span, field.place, pair);
				replaced.initializes = field.initializes;
				uint position = 0;
				assert (field_block.instructions.find (field, out position));
				field_block.instructions[position] = replaced;
			} else {
				assert (destructor != null);
				bool changed = false;
				foreach (var block in destructor.blocks) {
					for (int i = 0; i < block.instructions.length; i++) {
						var retired = block.instructions[i] as SsaBufferDeallocateInstruction;
						if (retired == null) {
							continue;
						}
						block.instructions.insert (i + 1, new SsaBufferDeallocateInstruction (retired.span, retired.pair, retired.cleanup));
						changed = true;
						break;
					}
					if (changed) {
						break;
					}
				}
				assert (changed);
			}
			refused (program, "SSA buffer");
		}
		var replacement = build ("owned u8[] replace(owned u8[] first,owned u8[] second){first=move second;return move first;}int main(){return 0;}");
		var contract = summary (replacement, "replace");
		var roots = contract.equations.requirements (contract.result);
		assert (roots.length == 1 && has (roots, 2));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private const string TASK_RUNTIME = "[ExceptionRoot]class TaskError{init(string message){}virtual property string message{get{return \"task\";}}}enum TaskStatus{Completed,Cancelled}async runtime Tasks throws TaskError returns TaskStatus;";
private void cold_task_contract() {
	try {
		SsaProgram? ssa = build (TASK_RUNTIME + CLASSES + "struct Packet{owned Leaf item;int marker;}async Packet deliver(Packet input){return move input;}int main(){return 0;}");
		var task = summary (ssa, "deliver");
		assert (!task.has_exception && task.store_count == 0 && task.updated_inputs ().length == 0);
		assert (has (task.equations.requirements (task.result, "f0.f0"), 0));
		assert (task.equations.requirements (task.result, "f1").length == 0);
		assert (has (task.equations.requirements (task.result, "f2.f0"), 0));
		var weak = WeakRef (function (ssa, "deliver"));
		ssa = null;
		assert (weak.get () == null);
		assert (has (task.equations.requirements (task.result, "f2.f0"), 0));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_scoped_capture() {
	try {
		foreach (bool early in new bool[] { false, true }) {
			var ssa = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();var pending=consume(move input);return 0;}int main(){return exercise();}");
			var task = summary (ssa, "consume");
			assert (has (task.equations.requirements (task.result, "f2"), 0));
			var target = function (ssa, "exercise");
			summary (ssa, "exercise");
			if (!early) {
				continue;
			}
			bool changed = false;
			foreach (var block in target.blocks) {
				int end = -1;
				int task_end = -1;
				for (int i = 0; i < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as SsaCleanupInstruction;
					if (cleanup != null && cleanup.value.semantic_type.is_scoped_allocator ()) {
						end = i;
					}
					if (block.instructions[i] is SsaTaskEnd) {
						task_end = i;
					}
				}
				if (end >= 0 && task_end >= 0) {
					assert (end > task_end);
					var cleanup = block.instructions[end];
					var event = block.instructions[end + 1] as SsaHeapOwnerEvent;
					assert (event != null && event.action == SsaHeapOwnerAction.END && event.effect == cleanup);
					block.instructions.remove_index (end + 1);
					block.instructions.remove_index (end);
					block.instructions.insert (task_end, cleanup);
					block.instructions.insert (task_end + 1, event);
					changed = true;
				}
			}
			assert (changed);
			bool rejected = false;
			try {
				SsaRuntimeLifetimes.verify (ssa);
			} catch (SsaError failure) {
				rejected = failure.message.contains ("before a derived owner or pending handoff");
				Test.message ("%s", failure.message);
			}
			assert (rejected);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_joined_capture() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}async void joined(owned Captured input) throws TaskError{var child=consume(move input);await move child;await delay_ticks(1);}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();try{var executor=Tasks.open(8);var pending=joined(move input);var status=executor.run(move pending);match(status){case TaskStatus.Completed():{}else:{return 2;}}}catch(TaskError error){return 1;}return 0;}int main(){return exercise();}");
		var joined = summary (program, "joined");
		assert (joined.equations.requirements (joined.result, "f0").length == 0);
		assert (joined.equations.requirements (joined.result, "f1").length == 0);
		assert (has (joined.equations.requirements (joined.result, "f2"), 0));
		summary (program, "exercise");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_admission_refusal() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}owned Captured refused(borrowed Context frames,owned Captured input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}return null;}int main(){return 0;}");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result), 1));
		foreach (var block in function (program, "refused").blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaTaskCreate;
				if (call == null) {
					continue;
				}
				assert (call.input_restores.length == 1);
				var restored = call.input_restores[0];
				call.input_restores.remove_index (0);
				bool rejected = false;
				try {
					SsaRuntimeLifetimes.verify (program);
				} catch (SsaError failure) {
					rejected = failure.message.contains ("original capture/admission channel");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				call.input_restores.add (restored);
				summary (program, "refused");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_admission() {
	try {
		for (int mode = 0; mode <= 10; mode++) {
			var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}struct Packet{owned Captured child;int marker;}async void consume(Packet input){}Packet refused(borrowed Context frames,Packet input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}Packet vacant={child=empty(),marker=0};return move vacant;}int main(){return 0;}");
			var refused = summary (program, "refused");
			assert (has (refused.equations.requirements (refused.result, "f0"), 1));
			if (mode == 0) {
				continue;
			}
			SsaFrameRecordRestore? restored = null;
			SsaBlock? site = null;
			int position = -1;
			foreach (var block in function (program, "refused").blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var candidate = block.instructions[i] as SsaFrameRecordRestore;
					if (candidate != null) {
						assert (restored == null);
						restored = candidate;
						site = block;
						position = i;
					}
				}
			}
			assert (restored != null && site != null);
			var call = restored.creation;
			var acquired = restored.acquisition;
			var moved = restored.original;
			assert (call != null && acquired != null);
			if (mode == 1) {
				assert (call.record_restores.remove (restored));
			} else if (mode == 2) {
				call.record_restores.add (restored);
			} else if (mode == 3) {
				assert (call.record_moves.remove (moved));
			} else if (mode == 4) {
				acquired.admission_restore = null;
			} else if (mode == 5) {
				restored.acquisition = null;
			} else if (mode == 6) {
				acquired.owners.remove_index (0);
			} else if (mode == 7) {
				restored.results.leaves[0] = restored.results.leaves[1];
			} else if (mode == 8) {
				site.instructions.insert (position + 1, restored);
			} else if (mode == 9) {
				site.instructions.remove_index (position);
				uint called;
				assert (site.instructions.find (call, out called));
				site.instructions.insert ((int) called, restored);
			} else {
				call.arguments[call.struct_arguments[0].first_leaf] = call.arguments[call.struct_arguments[0].first_leaf + 1];
			}
			bool rejected = false;
			try {
				SsaRuntimeLifetimes.verify (program);
			} catch (SsaError failure) {
				rejected = failure.message.contains ("restoration") || failure.message.contains ("record result") || failure.message.contains ("record argument") || failure.message.contains ("record capture") || failure.message.contains ("exact initialized/live/moved disposition") || failure.message.contains ("heap ownership lost exact original transfer/cleanup operand") || failure.message.contains ("original capture groups") || failure.message.contains ("exact factory/capture/admission contract");
				Test.message ("mode %d: %s", mode, failure.message);
			}
			assert (rejected);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_buffer_admission() {
	try {
		for (int mode = 0; mode <= 9; mode++) {
			var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}async void consume(owned Captured item,owned u8[] bytes){}owned Captured refused(borrowed Context frames,owned Captured item,owned u8[] bytes){try{var pending=checked_task_in(frames,consume(move item,move bytes));}catch(TaskError error){return move item;}return null;}int main(){return 0;}");
			var refused = summary (program, "refused");
			assert (has (refused.equations.requirements (refused.result), 1));
			if (mode == 0) {
				continue;
			}
			SsaFrameBufferRestore? restored = null;
			SsaBlock? site = null;
			int position = -1;
			foreach (var block in function (program, "refused").blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var candidate = block.instructions[i] as SsaFrameBufferRestore;
					if (candidate != null) {
						assert (restored == null);
						restored = candidate;
						site = block;
						position = i;
					}
				}
			}
			assert (restored != null && site != null);
			var call = restored.creation;
			var write = site.instructions[position + 1] as SsaBufferWriteInstruction;
			assert (call != null && write != null);
			if (mode == 1) {
				assert (call.buffer_restores.remove (restored));
			} else if (mode == 2) {
				call.buffer_restores.add (restored);
			} else if (mode == 3) {
				site.instructions.remove_index (position + 1);
			} else if (mode == 4) {
				write.initializes = true;
			} else if (mode == 5) {
				site.instructions[position + 1] = new SsaBufferWriteInstruction (write.span, write.place, restored.argument.pair);
			} else if (mode == 6) {
				site.instructions.insert (position + 2, restored);
			} else if (mode == 7) {
				site.instructions.remove_index (position);
				uint called;
				assert (site.instructions.find (call, out called));
				site.instructions.insert ((int) called, restored);
			} else if (mode == 8) {
				var argument = restored.argument;
				call.arguments[argument.parameter.first_leaf + 1] = call.arguments[argument.parameter.first_leaf];
			} else {
				assert (call.buffer_arguments.remove (restored.argument));
			}
			bool rejected = false;
			try {
				SsaRuntimeLifetimes.verify (program);
			} catch (SsaError failure) {
				Test.message ("mode %d: %s", mode, failure.message);
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_buffer_admission() {
	try {
		for (int mode = 0; mode <= 12; mode++) {
			var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}struct Storage{owned u8[] left;owned u8[] right;}struct Packet{owned Captured child;Storage data;int marker;}async void consume(Packet input){}Packet refused(borrowed Context frames,Packet input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}Packet vacant={child=empty(),data={left=new u8[0],right=new u8[0]},marker=0};return move vacant;}int main(){return 0;}");
			var refused = summary (program, "refused");
			assert (has (refused.equations.requirements (refused.result, "f0"), 1));
			if (mode == 0) {
				continue;
			}
			SsaFrameRecordRestore? restored = null;
			SsaBlock? site = null;
			foreach (var block in function (program, "refused").blocks) {
				foreach (var instruction in block.instructions) {
					var candidate = instruction as SsaFrameRecordRestore;
					if (candidate != null) {
						assert (restored == null);
						restored = candidate;
						site = block;
					}
				}
			}
			assert (restored != null && site != null && restored.results.buffers.length == 2);
			var moved = restored.original;
			var acquired = restored.acquisition;
			assert (acquired != null);
			if (mode == 1) {
				restored.results.buffers.remove_index (0);
			} else if (mode == 2) {
				restored.results.buffers.add (restored.results.buffers[0]);
			} else if (mode == 3) {
				moved.buffers.remove_index (0);
			} else if (mode == 4) {
				acquired.buffers.remove_index (0);
			} else if (mode == 5) {
				acquired.buffer_pairs[0] = moved.buffer_pairs[0];
			} else if (mode == 6) {
				moved.buffer_pairs[0] = new SsaBufferPair.empty (moved.span, moved.buffer_pairs[0].shape);
			} else if (mode == 7) {
				moved.buffers[0].record_path = null;
			} else if (mode == 8) {
				moved.buffers[0].record_rank++;
			} else if (mode == 9 || mode == 10) {
				bool changed = false;
				for (int i = 0; i < site.instructions.length; i++) {
					var write = site.instructions[i] as SsaBufferWriteInstruction;
					if (write != null && write.record_boundary == acquired) {
						if (mode == 9) {
							write.record_boundary = null;
						} else {
							site.instructions[i] = new SsaBufferWriteInstruction (write.span, write.place, new SsaBufferPair.empty (write.span, write.pair.shape));
						} changed = true;
						break;
					}
				}
				assert (changed);
			} else if (mode == 11) {
				var first = restored.results.buffers[0];
				restored.results.buffers[0] = restored.results.buffers[1];
				restored.results.buffers[1] = first;
			} else {
				var first = acquired.buffers[0];
				acquired.buffers[0] = acquired.buffers[1];
				acquired.buffers[1] = first;
			}
			bool rejected = false;
			try {
				SsaRuntimeLifetimes.verify (program);
			} catch (SsaError failure) {
				Test.message ("mode %d: %s", mode, failure.message);
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_deferred_error() {
	try {
		var program = build ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}[ExceptionRoot]class DeferredError{private owned Captured child;init(string message){this.child=empty();}void put(owned Captured input){this.child=move input;}virtual property string message{get{return \"deferred\";}}}enum DeferredStatus{Completed,Cancelled}async runtime DeferredTasks throws DeferredError returns DeferredStatus;async void fail(owned Captured input)throws DeferredError{var error=new DeferredError(\"deferred\");error.put(move input);throw move error;}int main(){return 0;}");
		var task = summary (program, "fail");
		assert (!task.has_exception);
		assert (task.equations.requirements (task.result, "f0").length == 0);
		assert (has (task.equations.requirements (task.result, "f1"), 0));
		assert (has (task.equations.requirements (task.result, "f2"), 0));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_observation() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}struct Packet{owned Captured child;int marker;}async Packet deliver(Packet input){return move input;}async void collect(Packet input)throws TaskError{var pending=deliver(move input);var result=await move pending;}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();Packet packet={child=move input,marker=17};try{var executor=Tasks.open(8);var root=collect(move packet);var status=executor.run(move root);}catch(TaskError error){return 1;}return 0;}int main(){return exercise();}");
		summary (program, "collect");
		summary (program, "exercise");
		bool changed = false;
		foreach (var block in function (program, "collect").blocks) {
			foreach (var instruction in block.instructions) {
				var success = instruction as SsaTaskSuccess;
				if (success == null || success.struct_result == null) {
					continue;
				}
				var group = success.struct_result;
				var leaf = group.leaves[0];
				group.leaves[0] = group.leaves[1];
				bool rejected = false;
				try {
					SsaRuntimeLifetimes.verify (program);
				} catch (SsaError failure) {
					rejected = failure.message.contains ("original physical result leaf");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				group.leaves[0] = leaf;
				summary (program, "collect");
				var wait = success.operation;
				wait.success = null;
				rejected = false;
				try {
					SsaRuntimeLifetimes.verify (program);
				} catch (SsaError failure) {
					rejected = failure.message.contains ("original success group");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				wait.success = success;
				summary (program, "collect");
				var target = function (program, "collect");
				var bypass = new SsaBlock (success.span, target.blocks.length, target.blocks.length);
				bypass.complete (new SsaBranch (success.span, new SsaEdge (block, new GenericArray<SsaValue> ())));
				target.blocks.add (bypass);
				rejected = false;
				try {
					SsaRuntimeLifetimes.verify (program);
				} catch (SsaError failure) {
					rejected = failure.message.contains ("unguarded predecessor");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				target.blocks.remove_index (target.blocks.length - 1);
				summary (program, "collect");
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void enum_owner_continuity() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void child(owned Captured input){}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,1,1);try{var input=new(context)Captured();var executor=Tasks.open(8);var pending=child(move input);var status=executor.run(move pending);match(status){case TaskStatus.Completed():{}else:{return 2;}}}catch(TaskError error){return 3;}return query(context,1);}int main(){return 0;}");
		var target = function (program, "exercise");
		summary (program, "exercise");
		foreach (var owner in target.heap_owners) {
			assert (owner.record_type == null);
		}
		var facts = SsaHeapOwnerFlow.verify (target, true);
		SsaScopedAllocator? context = null;
		bool dispatched = false;
		bool queried = false;
		foreach (var block in target.blocks) {
			if (block.terminator is SsaEnumDispatch) {
				dispatched = true;
			}
			foreach (var source in block.instructions) {
				if (source is SsaScopedAllocator) {
					context = (SsaScopedAllocator) source;
				}
			}
		}
		assert (context != null && dispatched);
		foreach (var block in target.blocks) {
			foreach (var source in block.instructions) {
				var call = source as SsaCCallInstruction;
				if (call == null || call.arguments.length == 0 || !call.arguments[0].semantic_type.is_scoped_allocator ()) {
					continue;
				}
				assert (facts.before.contains (call) && facts.before.lookup (call).state (context.owner.ordinal) == 2);
				queried = true;
			}
		}
		assert (queried);
		int controls = 0;
		foreach (var block in target.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var event = block.instructions[i] as SsaHeapOwnerEvent;
				if (event == null || event.owner != context.owner || event.action != SsaHeapOwnerAction.END) {
					continue;
				}
				var cleanup = event.effect as SsaCleanupInstruction;
				assert (cleanup != null && i > 0 && block.instructions[i - 1] == cleanup);
				block.instructions.remove_index (i);
				block.instructions.remove_index (i - 1);
				bool rejected = false;
				try {
					SsaHeapOwnerFlow.verify (target, true);
				} catch (SsaError failure) {
					Test.message ("%s", failure.message);
					rejected = failure.message.contains ("exits without exact lexical cleanup");
				}
				assert (rejected);
				block.instructions.insert (i - 1, cleanup);
				block.instructions.insert (i, event);
				SsaHeapOwnerFlow.verify (target, true);
				controls++;
			}
		}
		assert (controls != 0);
		summary (program, "exercise");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void suspended_private_catch() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}async void child(owned Captured input)throws TaskError{await delay_ticks(1);}async void caught(owned Captured input)throws TaskError{try{var pending=child(move input);await move pending;}catch(TaskError error){await delay_ticks(1);throw;}}int main(){return 0;}");
		var target = function (program, "caught");
		var contract = summary (program, "caught");
		assert (contract.complete && has (contract.equations.requirements (contract.result, "f2"), 0));
		bool changed = false;
		foreach (var block in target.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var event = block.instructions[i] as SsaFrameCatchEvent;
				if (event == null || event.source is SsaNullPointerConstant) {
					continue;
				}
				block.instructions.remove_index (i);
				refused (program, "suspended catch owner lost original");
				block.instructions.insert (i, event);
				summary (program, "caught");
				block.instructions[i] = new SsaFrameCatchEvent (event.span, event.owner, new SsaNullPointerConstant (event.span, event.owner.semantic_type));
				refused (program, "suspended catch owner lost original");
				block.instructions[i] = event;
				summary (program, "caught");
				changed = true;
				break;
			}
			if (changed) {
				break;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_buffer_observation() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}struct Storage{owned u8[] left;owned u8[] right;}struct Packet{owned Captured child;Storage data;int marker;}async Packet deliver(Packet input){return move input;}async void collect(Packet input)throws TaskError{var pending=deliver(move input);var result=await move pending;}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();Packet packet={child=move input,data={left=new u8[7],right=new u8[9]},marker=17};try{var executor=Tasks.open(8);var root=collect(move packet);var status=executor.run(move root);}catch(TaskError error){return 1;}return 0;}int main(){return exercise();}");
		summary (program, "collect");
		summary (program, "exercise");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/runtime-lifetime-ssa/enum-owner-continuity", enum_owner_continuity);
	Test.add_func ("/runtime-lifetime-ssa/suspended-private-catch", suspended_private_catch);
	Test.add_func ("/runtime-lifetime-ssa/native-composite-coordinate-version", native_composite_coordinate_version);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-record-buffer-observation", cold_task_record_buffer_observation);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-record-buffer-admission", cold_task_record_buffer_admission);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-buffer-admission", cold_task_buffer_admission);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-record-admission", cold_task_record_admission);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-record-observation", cold_task_record_observation);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-deferred-error", cold_task_deferred_error);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-admission-refusal", cold_task_admission_refusal);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-joined-capture", cold_task_joined_capture);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-contract", cold_task_contract);
	Test.add_func ("/runtime-lifetime-ssa/cold-task-scoped-capture", cold_task_scoped_capture);
	Test.add_func ("/runtime-lifetime-ssa/owned-record-admission", owned_record_admission);
	Test.add_func ("/runtime-lifetime-ssa/scoped-buffer-admission", scoped_buffer_admission);
	Test.add_func ("/runtime-lifetime-ssa/scoped-buffer-field-pairs", scoped_buffer_fields);
	Test.add_func ("/runtime-lifetime-ssa/checked-scoped-constructor-rollback", checked_constructor_rollback);
	Test.add_func ("/runtime-lifetime-ssa/exceptional-results", exceptional_results);
	Test.add_func ("/runtime-lifetime-ssa/fallible-owner-inputs", fallible_owner_inputs);
	Test.add_func ("/runtime-lifetime-ssa/owned-context-factory-roles", owned_factory_roles);
	Test.add_func ("/runtime-lifetime-ssa/scoped-carrier-signature", scoped_carrier_signature);
	Test.add_func ("/runtime-lifetime-ssa/constructor-call-controlflow-versions", constructor_and_versions);
	Test.add_func ("/runtime-lifetime-ssa/native-declaration-only", native_declaration);
	Test.add_func ("/runtime-lifetime-ssa/record-admission-inventory", admission_inventory);
	Test.add_func ("/runtime-lifetime-ssa/scoped-actual-retirement", scoped_retirement);
	Test.add_func ("/runtime-lifetime-ssa/scoped-formal-result", scoped_formal);
	Test.add_func ("/runtime-lifetime-ssa/scoped-local-result", scoped_local_result);
	Test.add_func ("/runtime-lifetime-ssa/scoped-pending-handoff", scoped_pending_handoff);
	Test.add_func ("/runtime-lifetime-ssa/scoped-storage-extent", scoped_storage_extent);
	Test.add_func ("/runtime-lifetime-ssa/scoped-receiver-store", scoped_receiver_store);
	Test.add_func ("/runtime-lifetime-ssa/scoped-owner-move", scoped_owner_move);
	Test.add_func ("/runtime-lifetime-ssa/native-exact-signature-roles", native_contract_roles);
	Test.add_func ("/runtime-lifetime-ssa/foreign-scalar-and-allocator-borrow", foreign_scalar_contracts);
	return Test.run ();
}

}
