// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;

namespace Astra.Tests.RuntimeLifetimeCfg {
private const string API = "[CCode(destroy_function=\"astra_context17_destroy\",context=\"scoped-affine\")]handle Scoped;int query(borrowed Scoped context,int key);" + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;owned Context context_open();";
private const string CONTROLLER = "int main(){owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);if(context==null){return 1;}if(query(context,7)!=1){return 2;}}return len(backing)-4097;}";
private const string CLASSES = "class Leaf{int code;init(int code){this.code=code;}}class Box{private owned Leaf child;init(owned Leaf child){this.child=move child;}int change(owned Leaf child){this.child=move child;return 1;}void put(owned Leaf child){this.child=move child;}}";
private const string SCOPED = "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf empty(){return null;}";
private CfgFunction function(CfgProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	error ("missing CFG function %s", name);
}

private RuntimeLifetimeSummary summary(CfgProgram program, string name) throws CfgError {
	var facts = CfgRuntimeLifetimes.analyze (program);
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

private CfgProgram build(string text, string? heap_boundary = null) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("lifetime-cfg.astra", text));
	assert (parsed.diagnostic == null);
	var imported = VapiParser.parse (new SourceFile.from_text ("lifetime-cfg.vapi", API));
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
	var cfg = CfgBuilder.build (core);
	core = null;
	assert (core_reference.get () == null);
	return cfg;
}

private void context_instruction_states() {
	try {
		var cfg = build (CONTROLLER);
		var function = cfg.functions[0];
		var flow = OwnershipFlow.analyze (function);
		assert (flow.diagnostic == null);
		CfgLocalPlace? context = null;
		foreach (var local in function.locals) {
			if (local.semantic_type.is_scoped_allocator ()) {
				context = local;
			}
		}
		assert (context != null);
		int factories = 0;
		int uses = 0;
		int ends = 0;
		int after = 0;
		foreach (var block in function.blocks) {
			foreach (var instruction in block.instructions) {
				var evaluation = instruction as CfgEvaluateInstruction;
				var factory = evaluation == null ? null : evaluation.value as CfgScopedAllocator;
				var acquisition = instruction as CfgInitialize;
				var cleanup = instruction as CfgCleanupInstruction;
				var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
				if (factory != null || acquisition != null && acquisition.acquisition == context) {
					assert (flow.scoped_state_before (instruction, context) == null);
					if (factory != null) {
						factories++;
					}
				}
				if (instruction is CfgCCallInstruction && ((CfgCCallInstruction) instruction).target.name == "query") {
					var state = flow.scoped_state_before (instruction, context);
					assert (state != null && state.definitely_owned ());
					uses++;
				}
				if (load != null && load.source == context) {
					var state = flow.scoped_state_before (instruction, context);
					assert (state != null && state.definitely_owned ());
					ends++;
				}
				if (load != null && load.source is CfgLocalPlace && ((CfgLocalPlace) load.source).name == "backing") {
					assert (flow.scoped_state_before (instruction, context) == null);
					after++;
				}
			}
		}
		assert (factories == 1 && uses == 1 && ends >= 2 && after >= 2);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void native_declaration() {
	try {
		var client = Parser.parse (new SourceFile.from_text ("lifetime-cfg-client.astra", "int main(){return opaque();}"));
		var file = new SourceFile.from_text ("lifetime-cfg-native.astra", "int opaque(){return 0;}", true);
		var imported = Parser.parse (file);
		assert (client.diagnostic == null && imported.diagnostic == null);
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (client.unit);
		units.add (imported.unit);
		var registry = new NativeDeclarationRegistry ();
		registry.add_types (file, new GenericArray<string> ());
		registry.add (file, new NativeDeclarationIdentity ("lifetime-cfg-native", "F:opaque", "lifetime_opaque", "test-declaration"));
		var source = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
		if (source.diagnostic != null) {
			error ("%s", source.diagnostic.message);
		}
		var cfg = CfgBuilder.build (CoreGenericMonomorphizer.build (CoreBuilder.build (source.program)));
		bool found = false;
		foreach (var function in cfg.functions) {
			if (function.name == "opaque") {
				assert (function.declaration_only ());
				found = true;
			}
		}
		assert (found);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void constructor_and_versions() {
	try {
		CfgProgram? cfg = build (CLASSES + "owned Box wrap(owned Leaf input){var box=new Box(move input);return move box;}owned Box forward(owned Leaf input){var result=wrap(move input);return move result;}void compare(borrowed Box box,owned Leaf incoming,int count){bool ignored=0<count<box.change(move incoming);}void loop(borrowed Box box,owned Leaf incoming,int count){while(count>0){box.put(move incoming);break;}}int main(){return 0;}");
		var result = summary (cfg, "forward");
		var origins = result.equations.requirements (result.result, "f0");
		assert (origins.length == 1 && has (origins, 0));
		assert (result.equations.requirements (result.result, "", false).length == 0);
		var conditional = summary (cfg, "compare");
		origins = conditional.equations.requirements (conditional.update (0), "f0");
		assert (has (origins, 0, "f0") && has (origins, 1));
		var loop = summary (cfg, "loop");
		origins = loop.equations.requirements (loop.update (0), "f0");
		assert (has (origins, 0, "f0") && has (origins, 1));
		var weak = WeakRef (function (cfg, "forward"));
		cfg = null;
		assert (weak.get () == null);
		assert (result.equations.requirements (result.result).length == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void inject_scoped_leaf(CfgFunction function) {
	CfgLocalPlace? context = null;
	foreach (var local in function.locals) {
		if (local.semantic_type.is_scoped_allocator ()) {
			context = local;
		}
	}
	assert (context != null);
	foreach (var block in function.blocks) {
		for (int i = 0; i < block.instructions.length; i++) {
			var call = block.instructions[i] as CfgCallInstruction;
			if (call == null || call.target.name != "empty") {
				continue;
			}
			CfgLocalPlace? leaf = null;
			int publication = -1;
			for (int p = i + 1; p < block.instructions.length; p++) {
				var initial = block.instructions[p] as CfgInitialize;
				if (initial != null && initial.value == call.result && initial.target is CfgLocalPlace) {
					leaf = (CfgLocalPlace) initial.target;
					publication = p;
					break;
				}
			}
			assert (leaf != null && publication >= 0);
			var owner = leaf.cleanup.object_class;
			var storage = new CfgObjectStorage (call.span, owner, function.object_storage.length, leaf.text_extent.ordinal);
			storage.heap_allocated = true;
			storage.transferable = true;
			storage.cleanup_rank = leaf.ordinal;
			function.object_storage.add (storage);
			leaf.object_storage = storage;
			block.instructions[i] = new CfgLifecycleCallInstruction (call.span, owner.constructor, storage, new GenericArray<CfgValue> (), new CfgLoadValue (context.span, context));
			block.instructions[publication] = new CfgInitialize (call.span, leaf, new CfgObjectReferenceValue (call.span, storage), leaf);
			return;
		}
	}
	error ("CFG fixture lost empty producer");
}

private void scoped_retirement() {
	try {
		foreach (int mode in new int[] { 0, 1, 2 }) {
			var cfg = build (SCOPED + "int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();return 0;}int main(){return 0;}");
			var target = function (cfg, "exercise");
			inject_scoped_leaf (target);
			assert (target.blocks.length == 1);
			var block = target.entry;
			int context_end = -1;
			int construct = -1;
			int leaf_end = -1;
			for (int i = 0; i < block.instructions.length; i++) {
				var cleanup = block.instructions[i] as CfgCleanupInstruction;
				var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
				var local = load == null ? null : load.source as CfgLocalPlace;
				if (local != null && local.semantic_type.is_scoped_allocator ()) {
					context_end = i;
				}
				if (local != null && local.name == "leaf") {
					leaf_end = i;
				}
				if (block.instructions[i] is CfgLifecycleCallInstruction && ((CfgLifecycleCallInstruction) block.instructions[i]).constructs) {
					construct = i;
				}
			}
			assert (context_end > leaf_end && leaf_end > construct);
			if (mode != 0) {
				var end = block.instructions[context_end];
				block.instructions.remove_index (context_end);
				block.instructions.insert (mode == 1 ? construct : leaf_end, end);
			}
			if (mode == 0) {
				summary (cfg, "exercise");
			} else {
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (cfg);
				} catch (CfgError failure) {
					Test.message ("%s", failure.message);
					assert (failure.message.contains (mode == 1 ? "actual live obligation" : "before a derived owner"));
					rejected = true;
				}
				assert (rejected);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_result() {
	try {
		var cfg = build (SCOPED + "owned ScopedLeaf exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();return null;}int main(){return 0;}");
		var original = function (cfg, "exercise");
		inject_scoped_leaf (original);
		assert (original.blocks.length == 1);
		CfgLocalPlace? leaf = null;
		foreach (var local in original.locals) {
			if (local.name == "leaf") {
				leaf = local;
			}
		}
		assert (leaf != null);
		var returned = new CfgOwnedReturnValue (leaf.span, leaf.semantic_type, leaf.cleanup, leaf, null, ObjectResultProvenance.HEAP_OBJECT);
		var instructions = new GenericArray<CfgInstruction> ();
		foreach (var source in original.entry.instructions) {
			if (source is CfgOwnershipReturnInstruction) {
				instructions.add (new CfgOwnershipReturnInstruction (source.span, returned));
			} else {
				instructions.add (source);
			}
		}
		var entry = new CfgBlock (original.entry.span, 0, instructions, new CfgOwnershipReturn (leaf.span, returned));
		var blocks = new GenericArray<CfgBlock> ();
		blocks.add (entry);
		var replacement = new CfgFunction (original.span, original.name_span, original.name, original.return_type, original.ordinal, original.parameters, original.locals, blocks, entry, original.owned_cleanup);
		replacement.bind_floating_policy (original.floating_policy);
		foreach (var storage in original.object_storage) {
			replacement.object_storage.add (storage);
		}
		foreach (var field in original.field_places) {
			replacement.field_places.add (field);
		}
		foreach (var temporary in original.temporaries) {
			replacement.temporaries.add (temporary);
		}
		cfg.functions[original.ordinal] = replacement;
		bool rejected = false;
		try {
			CfgRuntimeLifetimes.verify (cfg);
		} catch (CfgError failure) {
			assert (failure.message.contains ("result retains a scoped local allocation"));
			rejected = true;
			Test.message ("%s", failure.message);
		}
		assert (rejected);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_pending_handoff() {
	try {
		foreach (bool reordered in new bool[] { false, true }) {
			var cfg = build (SCOPED + "void consume(owned ScopedLeaf input){}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();consume(move leaf);return 0;}int main(){return 0;}");
			var target = function (cfg, "exercise");
			inject_scoped_leaf (target);
			var block = target.entry;
			int captured = -1;
			int context_end = -1;
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is CfgOwnedArgumentCapture) {
					captured = i;
				}
				var cleanup = block.instructions[i] as CfgCleanupInstruction;
				var load = cleanup == null ? null : cleanup.value as CfgLoadValue;
				if (load != null && load.semantic_type.is_scoped_allocator ()) {
					context_end = i;
				}
			}
			assert (captured >= 0 && context_end > captured);
			if (reordered) {
				var end = block.instructions[context_end];
				block.instructions.remove_index (context_end);
				block.instructions.insert (captured + 1, end);
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (cfg);
				} catch (CfgError failure) {
					assert (failure.message.contains ("before a derived owner or pending handoff"));
					rejected = true;
					Test.message ("%s", failure.message);
				}
				assert (rejected);
			} else {
				summary (cfg, "exercise");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_receiver_store() {
	try {
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		foreach (bool outer in new bool[] { false, true }) {
			var cfg = build (SCOPED + host + "int exercise(){" + (outer ? "var box=new Host(null);" : "") + "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);" + (outer ? "" : "var box=new Host(null);") + "var leaf=empty();box.put(move leaf);}return 0;}int main(){return 0;}");
			var target = function (cfg, "exercise");
			inject_scoped_leaf (target);
			if (outer) {
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (cfg);
				} catch (CfgError failure) {
					assert (failure.message.contains ("cannot outlive context"));
					rejected = true;
					Test.message ("%s", failure.message);
				}
				assert (rejected);
			} else {
				summary (cfg, "exercise");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_carrier_signature() {
	try {
		var program = build (SCOPED.replace ("init(){}", "int code;init(){this.code=7;}int read(){int value=this.code;return value;}") + "class Inner{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}class Host{private owned Inner child;init(owned Inner child){this.child=move child;}}extern(C) void* opaque_ptr();void opaque(){opaque_ptr();}void probe(borrowed Host box){}int main(){return 0;}");
		summary (program, "probe");
		var target = function (program, "probe");
		var call = new CfgCallInstruction (target.span, function (program, "opaque"), new GenericArray<CfgValue> (), null);
		target.entry.instructions.insert (0, call);
		bool rejected = false;
		try {
			CfgRuntimeLifetimes.verify (program);
		} catch (CfgError failure) {
			rejected = failure.message.contains ("scoped lifetime proof is incomplete");
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		target.entry.instructions.remove_index (0);
		CfgRuntimeLifetimes.verify (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owned_factory_roles() {
	try {
		var program = build (SCOPED + "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}int probe(borrowed Host host){var context=context_open();return 0;}int main(){return 0;}");
		summary (program, "probe");
		var target = function (program, "probe");
		CfgCFunction? factory = null;
		foreach (var candidate in program.c_functions) {
			if (candidate.name == "context_open") {
				factory = candidate;
			}
		}
		assert (factory != null && factory.owned_cleanup != null);
		foreach (bool wrong in new bool[] { false, true }) {
			var cleanup = wrong ? new CfgCleanupContract ("wrong_context_cleanup", target.span, 0) : null;
			var mutant = new CfgCFunction (factory.span, factory.name_span, factory.name, factory.metadata, factory.abi, factory.return_type, factory.parameter_types, factory.ordinal, cleanup, factory.parameters);
			var call = new CfgCCallInstruction (target.span, mutant, new GenericArray<CfgValue> (), new CfgCallResultValue (target.span, factory.return_type));
			target.entry.instructions.insert (0, call);
			bool rejected = false;
			try {
				CfgRuntimeLifetimes.verify (program);
			} catch (CfgError failure) {
				rejected = failure.message.contains ("foreign call requires");
				Test.message ("%s", failure.message);
			}
			assert (rejected);
			target.entry.instructions.remove_index (0);
			CfgRuntimeLifetimes.verify (program);
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
				var call = source as CfgLifecycleCallInstruction;
				if (call == null || !call.storage.fallible) {
					continue;
				}
				foreach (var input in call.arguments) {
					var captured = input as CfgPendingOwnedArgument;
					if (captured == null) {
						continue;
					}
					captured.consumer = null;
					bool rejected = false;
					try {
						CfgRuntimeLifetimes.verify (program);
					} catch (CfgError failure) {
						rejected = failure.message.contains ("exact capture/constructor channel");
						Test.message ("%s", failure.message);
					}
					assert (rejected);
					captured.consumer = call;
					summary (program, "refuse");
					changed = true;
				}
			}
		}
		assert (changed);
		foreach (bool escaping in new bool[] { false, true }) {
			string host = "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
			var scoped = build (SCOPED + host + "int exercise(borrowed Context parent){" + (escaping ? "var outer=new(parent)Host(null);" : "") + "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();var host=try_new(parent)Host(move leaf);" + (escaping ? "outer.put(move leaf);" : "") + "}return 0;}int main(){return 0;}");
			inject_scoped_leaf (function (scoped, "exercise"));
			if (escaping) {
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (scoped);
				} catch (CfgError failure) {
					rejected = failure.message.contains ("outlive context");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
			} else {
				summary (scoped, "exercise");
			}
		}

	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void exceptional_results() {
	try {
		string fault = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}";
		var cfg = build (fault + SCOPED + "owned ScopedLeaf attempt(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(\"bad\");}return move input;}owned ScopedLeaf caught(owned ScopedLeaf input,int mode){try{var result=attempt(move input,mode);return move result;}catch(Fault error){return null;}}int main(){return 0;}", "attempt,caught");
		var attempted = summary (cfg, "attempt");
		assert (attempted.has_exception && attempted.equations.requirements (attempted.exception).length == 0 && has (attempted.equations.requirements (attempted.result), 0));
		var caught = summary (cfg, "caught");
		assert (!caught.has_exception && has (caught.equations.requirements (caught.result), 0));
		var called = function (cfg, "caught");
		CfgCallInstruction? throwing_call = null;
		foreach (var block in called.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as CfgCallInstruction;
				if (call != null && call.target.name == "attempt") {
					throwing_call = call;
				}
			}
		}
		assert (throwing_call != null && throwing_call.exception_result != null);
		var error_channel = throwing_call.exception_result;
		throwing_call.exception_result = null;
		bool lost_channel = false;
		try {
			CfgRuntimeLifetimes.verify (cfg);
		} catch (CfgError failure) {
			lost_channel = failure.message.contains ("exceptional lifetime channel");
			Test.message ("%s", failure.message);
		}
		assert (lost_channel);
		throwing_call.exception_result = error_channel;
		summary (cfg, "caught");
		assert (called.handlers.length == 1);
		var handler = called.handlers[0];
		called.handlers.remove_index (0);
		bool lost_handler = false;
		try {
			CfgRuntimeLifetimes.verify (cfg);
		} catch (CfgError failure) {
			lost_handler = failure.message.contains ("protected exception channel");
			Test.message ("%s", failure.message);
		}
		assert (lost_handler);
		called.handlers.add (handler);
		summary (cfg, "caught");

		var weak = WeakRef (function (cfg, "attempt"));
		cfg = null;
		assert (weak.get () == null);
		assert (attempted.equations.requirements (attempted.result).length == 1);
		cfg = build (fault + SCOPED + "void consume(owned ScopedLeaf input,int marker){}int later()throws Fault{throw new Fault(\"before\");}owned ScopedLeaf restore(owned ScopedLeaf input){try{consume(move input,later());}catch(Fault error){return move input;}return null;}int main(){return 0;}", "consume,restore");
		var restored = summary (cfg, "restore");
		assert (has (restored.equations.requirements (restored.result), 0));
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		cfg = build (fault + SCOPED + host + "void alter(borrowed Host box,owned ScopedLeaf input)throws Fault{box.put(move input);throw new Fault(\"changed\");}void observe(borrowed Host box,owned ScopedLeaf input){try{alter(box,move input);}catch(Fault error){}}int main(){return 0;}", "alter,observe");
		foreach (string name in new string[] { "alter", "observe" }) {
			var effect = summary (cfg, name);
			assert (effect.updated_inputs ().length == 1 && effect.store_count == 1 && has (effect.equations.requirements (effect.update (0), "f0"), 1));
		}
		string throwing_host = "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child,int mode)throws Fault{this.child=move child;if(mode!=0){throw new Fault(\"partial\");}}}";
		cfg = build (fault + SCOPED + throwing_host + "owned ScopedLeaf recover(borrowed Context context,owned ScopedLeaf input,int mode){try{var host=try_new(context)Host(move input,mode);if(host==null){return move input;}}catch(Fault error){}return null;}int main(){return 0;}", "recover");
		var recovered = summary (cfg, "recover");
		assert (!recovered.has_exception && has (recovered.equations.requirements (recovered.result), 1));
		bool abort_checked = false;
		foreach (var target in cfg.functions) {
			if (!(target is CfgConstructor) || target.throws_type == null) {
				continue;
			}
			foreach (var block in target.blocks) {
				if (!(block.terminator is CfgExceptionReturn) || block.instructions.length == 0) {
					continue;
				}
				int last = (int) block.instructions.length - 1;
				var abort = block.instructions[last] as CfgConstructorAbort;
				if (abort == null) {
					continue;
				}
				block.instructions.remove_index (last);
				bool rejected = false;
				try {
					CfgVerifier.verify (cfg);
				} catch (CfgError failure) {
					rejected = failure.message.contains ("partial-field retirement");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				block.instructions.insert (last, abort);
				CfgVerifier.verify (cfg);
				abort_checked = true;
			}
		}
		assert (abort_checked);

		string owned_fault = "[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}";
		cfg = build (SCOPED + owned_fault + "void raise(owned ScopedLeaf input)throws Fault{throw new Fault(move input);}void reroute(owned ScopedLeaf input)throws Fault{try{raise(move input);}catch(Fault error){throw;}}int main(){return 0;}", "raise,reroute");
		var raised = summary (cfg, "raise");
		assert (raised.has_exception && has (raised.equations.requirements (raised.exception), 0));
		var rerouted = summary (cfg, "reroute");
		assert (rerouted.has_exception && has (rerouted.equations.requirements (rerouted.exception), 0));
		foreach (bool outside in new bool[] { false, true }) {
			Test.message ("scoped exception outside=%d", outside ? 1 : 0);
			string body = outside ? "try{owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}}catch(Fault error){}" : "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);try{var leaf=empty();throw new Fault(move leaf);}catch(Fault error){}}";
			cfg = build (SCOPED + owned_fault + "int exercise(){" + body + "return 0;}int main(){return 0;}");
			var target = function (cfg, "exercise");
			inject_scoped_leaf (target);
			if (outside) {
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (cfg);
				} catch (CfgError failure) {
					rejected = failure.message.contains ("scoped") || failure.message.contains ("context");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
			} else {
				summary (cfg, "exercise");
				assert (target.handlers.length == 1);
				var matched = target.handlers[0].matched;
				CfgCleanupInstruction? cleanup = null;
				foreach (var block in target.blocks) {
					foreach (var instruction in block.instructions) {
						var candidate = instruction as CfgCleanupInstruction;
						var loaded = candidate == null ? null : candidate.value as CfgLoadValue;
						if (loaded != null && loaded.source is CfgExceptionStorage) {
							cleanup = candidate;
						}
					}
				}
				assert (matched != null && cleanup != null);
				var early = new CfgCleanupInstruction (cleanup.span, cleanup.value, cleanup.cleanup);
				matched.instructions.insert (0, early);
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (cfg);
				} catch (CfgError failure) {
					rejected = failure.message.contains ("catch borrow outlives");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				matched.instructions.remove_index (0);
				summary (cfg, "exercise");
			}
		}

		cfg = build (SCOPED + owned_fault + "int exercise(){owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);int count=2;while(count>0){try{var leaf=empty();throw new Fault(move leaf);}catch(Fault error){}count=count-1;}}return 0;}int main(){return 0;}");
		inject_scoped_leaf (function (cfg, "exercise"));
		summary (cfg, "exercise");
		cfg = build (SCOPED + owned_fault + "void escape()throws Fault{owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}int main(){return 0;}");
		inject_scoped_leaf (function (cfg, "escape"));
		bool escaped = false;
		try {
			CfgRuntimeLifetimes.verify (cfg);
		} catch (CfgError failure) {
			escaped = failure.message.contains ("exception retains a scoped local allocation") || failure.message.contains ("before a derived owner");
			Test.message ("%s", failure.message);
		}
		assert (escaped);

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
				CfgLifecycleCallInstruction? constructor = null;
				CfgBlock? site = null;
				foreach (var block in target.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as CfgLifecycleCallInstruction;
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
					constructor.exception_result = new CfgEvaluatedValue (constructor.span, constructor.exception_result.semantic_type);
				} else if (mode == 2) {
					site.instructions.insert (0, constructor);
				} else {
					constructor.exception_result = null;
				}
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (program);
				} catch (CfgError failure) {
					Test.message ("%s", failure.message);
					assert (failure.message.contains ("constructor rollback") || failure.message.contains ("exception"));
					rejected = true;
				}
				assert (rejected);
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owned_record_arguments() {
	try {
		for (int mode = 0; mode <= 10; mode++) {
			var program = build ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Leaf{init(){}}struct Packet{owned Leaf left;owned Leaf right;int marker;}class Host{private Packet packet;init(Packet packet){this.packet=move packet;}}int exercise(){owned u8[] backing=new u8[8197];var context=scoped_allocator<Scoped>(backing,1,7);var left=new(context)Leaf();var right=new(context)Leaf();Packet packet={left=move left,right=move right,marker=7};var host=new Host(move packet);return 0;}int main(){return exercise();}");
			var target = function (program, "exercise");
			CfgLifecycleCallInstruction? call = null;
			CfgStructBoundaryMove? moved = null;
			CfgBlock? site = null;
			CfgCleanupInstruction? context_end = null;
			foreach (var block in target.blocks) {
				foreach (var instruction in block.instructions) {
					var construction = instruction as CfgLifecycleCallInstruction;
					if (construction != null && construction.constructs && construction.target.struct_parameters.length != 0) {
						call = construction;
						site = block;
					}
					var transfer = instruction as CfgStructBoundaryMove;
					if (transfer != null && transfer.use_kind == StructResultUseKind.ARGUMENT) {
						assert (moved == null);
						moved = transfer;
					}
					var cleanup = instruction as CfgCleanupInstruction;
					if (cleanup != null && cleanup.value.semantic_type.is_scoped_allocator ()) {
						context_end = cleanup;
					}
				}
			}
			assert (call != null && moved != null && site != null && context_end != null && call.arguments.length == 3 && moved.leaves.length == 3 && moved.consumer == call);
			if (mode == 0) {
				summary (program, "exercise");
				continue;
			}
			uint position = 0;
			assert (site.instructions.find (moved, out position));
			if (mode == 1) {
				call.record_moves.remove_index (0);
			} else if (mode == 2) {
				call.record_moves.add (moved);
			} else if (mode == 3) {
				var first = call.arguments[0];
				call.arguments[0] = call.arguments[1];
				call.arguments[1] = first;
			} else if (mode == 4) {
				var first = moved.leaves[0];
				moved.leaves[0] = moved.leaves[1];
				moved.leaves[1] = first;
				call.arguments[0] = moved.leaves[0];
				call.arguments[1] = moved.leaves[1];
			} else if (mode == 5) {
				moved.consumer = null;
			} else if (mode == 6) {
				var group = call.struct_arguments[0];
				call.struct_arguments[0] = new StructBoundaryGroup (group.source_ordinal + 1, group.first_leaf, group.shape);
			} else if (mode == 7) {
				site.instructions.remove_index (position);
			} else if (mode == 8) {
				site.instructions.insert ((int) position + 1, moved);
			} else if (mode == 9) {
				moved.leaves[0] = moved.leaves[1];
				call.arguments[0] = moved.leaves[0];
			} else {
				assert (site.instructions.remove (context_end));
				site.instructions.insert ((int) position + 1, context_end);
			}
			bool rejected = false;
			try {
				CfgRuntimeLifetimes.verify (program);
			} catch (CfgError failure) {
				Test.message ("%s", failure.message);
				assert (failure.message.contains (mode == 10 ? "before a derived owner or pending handoff" : "CFG record"));
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_buffer_fields() {
	try {
		var program = build ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Packet{private owned u8[] bytes;init(owned u8[] bytes,int marker){this.bytes=move bytes;}int count(){return len(this.bytes);}}int main(){return 0;}");
		var constructor = function (program, "init");
		var contract = summary (program, "init");
		assert (has (contract.equations.requirements (contract.update (-1), "f0"), 0));
		CfgLocalPlace? buffer = null;
		foreach (var local in constructor.locals) {
			if (local.semantic_type is SliceType) {
				assert (buffer == null);
				buffer = local;
			}
		}
		assert (buffer != null && buffer.text_extent != null);
		var extent = buffer.text_extent;
		buffer.text_extent = null;
		bool rejected = false;
		try {
			CfgRuntimeLifetimes.verify (program);
		} catch (CfgError failure) {
			Test.message ("%s", failure.message);
			assert (failure.message.contains ("actual lexical cleanup extents"));
			rejected = true;
		}
		assert (rejected);
		buffer.text_extent = extent;
		CfgRuntimeLifetimes.verify (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private const string TASK_RUNTIME = "[ExceptionRoot]class TaskError{init(string message){}virtual property string message{get{return \"task\";}}}enum TaskStatus{Completed,Cancelled}async runtime Tasks throws TaskError returns TaskStatus;";
private void cold_task_contract() {
	try {
		CfgProgram? cfg = build (TASK_RUNTIME + CLASSES + "struct Packet{owned Leaf item;int marker;}async Packet deliver(Packet input){return move input;}int main(){return 0;}");
		var task = summary (cfg, "deliver");
		assert (!task.has_exception && task.store_count == 0 && task.updated_inputs ().length == 0);
		assert (has (task.equations.requirements (task.result, "f0.f0"), 0));
		assert (task.equations.requirements (task.result, "f1").length == 0);
		assert (has (task.equations.requirements (task.result, "f2.f0"), 0));
		var weak = WeakRef (function (cfg, "deliver"));
		cfg = null;
		assert (weak.get () == null);
		assert (has (task.equations.requirements (task.result, "f2.f0"), 0));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_scoped_capture() {
	try {
		foreach (bool early in new bool[] { false, true }) {
			var cfg = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();var pending=consume(move input);return 0;}int main(){return exercise();}");
			var task = summary (cfg, "consume");
			assert (has (task.equations.requirements (task.result, "f2"), 0));
			var target = function (cfg, "exercise");
			summary (cfg, "exercise");
			if (!early) {
				continue;
			}
			bool changed = false;
			foreach (var block in target.blocks) {
				int end = -1;
				int task_end = -1;
				for (int i = 0; i < block.instructions.length; i++) {
					var cleanup = block.instructions[i] as CfgCleanupInstruction;
					var loaded = cleanup == null ? null : cleanup.value as CfgLoadValue;
					if (loaded != null && loaded.semantic_type.is_scoped_allocator ()) {
						end = i;
					}
					if (block.instructions[i] is CfgTaskEnd) {
						task_end = i;
					}
				}
				if (end >= 0 && task_end >= 0) {
					assert (end > task_end);
					var cleanup = block.instructions[end];
					block.instructions.remove_index (end);
					block.instructions.insert (task_end, cleanup);
					changed = true;
				}
			}
			assert (changed);
			bool rejected = false;
			try {
				CfgRuntimeLifetimes.verify (cfg);
			} catch (CfgError failure) {
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
				var call = instruction as CfgTaskCreate;
				if (call == null) {
					continue;
				}
				foreach (var argument in call.arguments) {
					var captured = argument as CfgPendingOwnedArgument;
					if (captured == null) {
						continue;
					}
					captured.consumer = null;
					bool rejected = false;
					try {
						CfgRuntimeLifetimes.verify (program);
					} catch (CfgError failure) {
						rejected = failure.message.contains ("exact captured caller input");
						Test.message ("%s", failure.message);
					}
					assert (rejected);
					captured.consumer = call;
					summary (program, "refused");
				}
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_admission() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}struct Packet{owned Captured child;int marker;}async void consume(Packet input){}Packet refused(borrowed Context frames,Packet input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}Packet vacant={child=empty(),marker=0};return move vacant;}int main(){return 0;}");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result, "f0"), 1));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_buffer_admission() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}async void consume(owned Captured item,owned u8[] bytes){}owned Captured refused(borrowed Context frames,owned Captured item,owned u8[] bytes){try{var pending=checked_task_in(frames,consume(move item,move bytes));}catch(TaskError error){return move item;}return null;}int main(){return 0;}");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result), 1));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_buffer_admission() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}struct Storage{owned u8[] left;owned u8[] right;}struct Packet{owned Captured child;Storage data;int marker;}async void consume(Packet input){}Packet refused(borrowed Context frames,Packet input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}Packet vacant={child=empty(),data={left=new u8[0],right=new u8[0]},marker=0};return move vacant;}int main(){return 0;}");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result, "f0"), 1));
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
				var success = instruction as CfgTaskSuccess;
				if (success == null || success.struct_result == null) {
					continue;
				}
				var group = success.struct_result;
				var leaf = group.leaves[0];
				group.leaves[0] = group.leaves[1];
				bool rejected = false;
				try {
					CfgRuntimeLifetimes.verify (program);
				} catch (CfgError failure) {
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
					CfgRuntimeLifetimes.verify (program);
				} catch (CfgError failure) {
					rejected = failure.message.contains ("original success group");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				wait.success = success;
				summary (program, "collect");
				var target = function (program, "collect");
				var bypass = new CfgBlock (success.span, target.blocks.length, new GenericArray<CfgInstruction> (), new CfgBranch (success.span, block));
				target.blocks.add (bypass);
				rejected = false;
				try {
					CfgRuntimeLifetimes.verify (program);
				} catch (CfgError failure) {
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
	Test.add_func ("/runtime-lifetime-cfg/cold-task-record-buffer-observation", cold_task_record_buffer_observation);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-record-buffer-admission", cold_task_record_buffer_admission);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-buffer-admission", cold_task_buffer_admission);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-record-admission", cold_task_record_admission);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-record-observation", cold_task_record_observation);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-deferred-error", cold_task_deferred_error);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-admission-refusal", cold_task_admission_refusal);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-joined-capture", cold_task_joined_capture);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-contract", cold_task_contract);
	Test.add_func ("/runtime-lifetime-cfg/cold-task-scoped-capture", cold_task_scoped_capture);
	Test.add_func ("/runtime-lifetime-cfg/owned-record-argument-captures", owned_record_arguments);
	Test.add_func ("/runtime-lifetime-cfg/scoped-buffer-field-storage", scoped_buffer_fields);
	Test.add_func ("/runtime-lifetime-cfg/checked-scoped-constructor-rollback", checked_constructor_rollback);
	Test.add_func ("/runtime-lifetime-cfg/exceptional-results", exceptional_results);
	Test.add_func ("/runtime-lifetime-cfg/fallible-owner-inputs", fallible_owner_inputs);
	Test.add_func ("/runtime-lifetime-cfg/owned-context-factory-roles", owned_factory_roles);
	Test.add_func ("/runtime-lifetime-cfg/scoped-carrier-signature", scoped_carrier_signature);
	Test.add_func ("/runtime-lifetime-cfg/context-at-actual-instruction", context_instruction_states);
	Test.add_func ("/runtime-lifetime-cfg/native-declaration-only", native_declaration);
	Test.add_func ("/runtime-lifetime-cfg/constructor-call-controlflow-versions", constructor_and_versions);
	Test.add_func ("/runtime-lifetime-cfg/scoped-actual-retirement", scoped_retirement);
	Test.add_func ("/runtime-lifetime-cfg/scoped-result", scoped_result);
	Test.add_func ("/runtime-lifetime-cfg/scoped-pending-handoff", scoped_pending_handoff);
	Test.add_func ("/runtime-lifetime-cfg/scoped-receiver-store", scoped_receiver_store);
	return Test.run ();
}

}
