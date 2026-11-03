// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;

namespace Astra.Tests.RuntimeLifetimeCore {
private const string API = "[CCode(destroy_function=\"astra_context17_destroy\",context=\"scoped-affine\")]handle Scoped;" + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;owned Context context_open();";
private const string LEAF = "class Leaf{int code;init(int code){this.code=code;}}";
private const string HOLDER = "class Holder{private owned Leaf child;init(owned Leaf child){this.child=move child;}void put(owned Leaf child){this.child=move child;}int change(owned Leaf child){this.child=move child;return 1;}}";
private const string SCOPED = "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf empty(){return null;}";
private CheckedProgram checked(string text, string? heap_boundary = null) {
	var parsed = Parser.parse (new SourceFile.from_text ("lifetime-core.astra", text));
	assert (parsed.diagnostic == null);
	var imported = VapiParser.parse (new SourceFile.from_text ("lifetime-core.vapi", API));
	assert (imported.diagnostic == null);
	SemanticResult result;
	if (heap_boundary == null) {
		result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (imported.file), VapiNormalizer.normalize_handles (imported.file));
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
		try {
			result = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), VapiNormalizer.normalize (imported.file), VapiNormalizer.normalize_handles (imported.file), null, boundaries);
		} catch (GLib.Error failure) {
			error ("%s", failure.message);
		}
	}
	if (result.diagnostic != null) {
		error ("%s", result.diagnostic.message);
	}
	return result.program;
}

private CoreProgram build(string text, string? heap_boundary = null) throws CoreError {
	CheckedProgram? source = checked (text, heap_boundary);
	var weak = WeakRef (source.functions[0]);
	foreach (var definition in source.all_definitions ()) {
		definition.runtime_lifetimes = null;
	}
	var core = CoreBuilder.build (source);
	source = null;
	assert (weak.get () == null);
	return CoreGenericMonomorphizer.build (core);
}

private CoreFunction function(CoreProgram program, string name) {
	foreach (var function in program.functions) {
		if (function.name == name) {
			return function;
		}
	}
	error ("missing Core function %s", name);
}

private RuntimeLifetimeSummary summary(CoreProgram program, string name) throws CoreError {
	var facts = CoreRuntimeLifetimes.analyze (program);
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

private void independent_constructors() {
	try {
		CoreProgram? core = build (LEAF + HOLDER + "owned Holder wrap(owned Leaf input){var box=new Holder(move input);return move box;}owned Holder forward(owned Leaf input){var result=wrap(move input);return move result;}int main(){return 0;}");
		CoreVerifier.verify_concrete (core);
		var result = summary (core, "forward");
		var origins = result.equations.requirements (result.result, "f0");
		assert (origins.length == 1 && has (origins, 0));
		assert (result.equations.requirements (result.result, "", false).length == 0);
		var weak = WeakRef (function (core, "forward"));
		core = null;
		assert (weak.get () == null);
		assert (result.equations.requirements (result.result).length == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void records_and_control() {
	try {
		var core = build (LEAF + HOLDER + "struct Record{owned Leaf child;int marker;}Record packet(owned Leaf input){Record value={child=move input,marker=7};return move value;}void replace_loop(borrowed Holder box,owned Leaf incoming,int count){while(count>0){box.put(move incoming);break;}}void compare(borrowed Holder box,owned Leaf incoming,int count){bool ignored=0<count<box.change(move incoming);}int main(){return 0;}");
		var packet = summary (core, "packet");
		var origins = packet.equations.requirements (packet.result, "f0");
		assert (origins.length == 1 && has (origins, 0));
		var loop = summary (core, "replace_loop");
		origins = loop.equations.requirements (loop.update (0), "f0");
		assert (has (origins, 0, "f0") && has (origins, 1));
		var compare = summary (core, "compare");
		origins = compare.equations.requirements (compare.update (0), "f0");
		assert (has (origins, 0, "f0") && has (origins, 1));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void opaque_native() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("lifetime-core-client.astra", "int caller(){return opaque();}int main(){return caller();}"));
		assert (parsed.diagnostic == null);
		var file = new SourceFile.from_text ("lifetime-core-native.astra", "int opaque(){return 0;}", true);
		var imported = Parser.parse (file);
		assert (imported.diagnostic == null);
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (parsed.unit);
		units.add (imported.unit);
		var registry = new NativeDeclarationRegistry ();
		registry.add_types (file, new GenericArray<string> ());
		registry.add (file, new NativeDeclarationIdentity ("opaque-lifetime", "F:opaque", "opaque_lifetime", "test-declaration"));
		var analyzed = SemanticAnalyzer.analyze_program (new SyntaxProgram (units), null, null, null, null, registry);
		if (analyzed.diagnostic != null) {
			error ("%s", analyzed.diagnostic.message);
		}
		var core = CoreBuilder.build (analyzed.program);
		assert (function (core, "opaque").native_declaration != null);
		var facts = CoreRuntimeLifetimes.analyze (core);
		assert (!facts.contains (function (core, "opaque")));
		var caller = facts.lookup (function (core, "caller"));
		assert (caller != null && !caller.complete && caller.limitation.contains ("complete direct lifetime summary"));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private CoreOwnedLocal inject(CoreBlock block, CoreLocalPlace context, CoreFunction function) {
	for (int i = 0; i < block.statements.length; i++) {
		var initial = block.statements[i] as CoreInitialize;
		var local = initial == null ? null : initial.target as CoreLocalPlace;
		if (local == null || local.name != "leaf") {
			continue;
		}
		var acquisition = initial.acquisition;
		assert (acquisition != null && acquisition.cleanup.object_class != null);
		var owner = acquisition.cleanup.object_class;
		var storage = new CoreObjectStorage (initial.span, owner, function.object_storage.length, local.text_extent.ordinal, block);
		storage.heap_allocated = true;
		storage.transferable = true;
		storage.cleanup_rank = local.ordinal;
		function.object_storage.add (storage);
		var construction = new CoreConstructorObjectInitialization (initial.span, storage, local, owner.constructor, new GenericArray<CoreValue> (), new CoreLoadValue (context.span, context));
		construction.acquisition = acquisition;
		block.statements[i] = construction;
		return acquisition;
	}
	error ("Core fixture lost leaf initialization");
}

private void scoped_result() {
	try {
		foreach (bool escaping in new bool[] { false, true }) {
			var core = build (SCOPED + (escaping ? "owned ScopedLeaf exercise()" : "int exercise()") + "{owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();" + (escaping ? "return null;" : "return 0;") + "}int main(){return 0;}");
			var target = function (core, "exercise");
			CoreLocalPlace? context = null;
			foreach (var local in target.locals) {
				if (local.semantic_type.is_scoped_allocator ()) {
					context = local;
				}
			}
			assert (context != null);
			var leaf = inject (target.body, context, target);
			if (escaping) {
				var returned = (CoreOwnershipReturn) target.body.statements[target.body.statements.length - 1];
				target.body.statements[target.body.statements.length - 1] = new CoreOwnershipReturn (returned.span, leaf.place.semantic_type, returned.cleanup, leaf);
				bool rejected = false;
				try {
					CoreRuntimeLifetimes.verify (core);
				} catch (CoreError failure) {
					assert (failure.message.contains ("result retains a scoped local allocation"));
					rejected = true;
					Test.message ("%s", failure.message);
				}
				assert (rejected);
			} else {
				summary (core, "exercise");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_receiver() {
	try {
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		foreach (bool outer in new bool[] { false, true }) {
			var core = build (SCOPED + host + "int exercise(){" + (outer ? "var box=new Host(null);" : "") + "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);" + (outer ? "" : "var box=new Host(null);") + "var leaf=empty();box.put(move leaf);}return 0;}int main(){return 0;}");
			var target = function (core, "exercise");
			CoreLocalPlace? context = null;
			foreach (var local in target.locals) {
				if (local.semantic_type.is_scoped_allocator ()) {
					context = local;
				}
			}
			assert (context != null);
			bool changed = false;
			foreach (var source in target.body.statements) {
				if (source is CoreScope) {
					inject (((CoreScope) source).body, context, target);
					changed = true;
				}
			}
			assert (changed);
			if (outer) {
				bool rejected = false;
				try {
					CoreRuntimeLifetimes.verify (core);
				} catch (CoreError failure) {
					assert (failure.message.contains ("cannot outlive context"));
					rejected = true;
					Test.message ("%s", failure.message);
				}
				assert (rejected);
			} else {
				summary (core, "exercise");
			}
		}
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_formal() {
	try {
		var core = build (SCOPED + "owned ScopedLeaf build(borrowed Scoped context){var leaf=empty();return null;}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=build(context);return 0;}int main(){return 0;}");
		var builder = function (core, "build");
		var original = (CoreInitialize) builder.body.statements[0];
		var leaf = original.acquisition;
		assert (leaf != null);
		var owner = leaf.cleanup.object_class;
		var storage = new CoreObjectStorage (original.span, owner, builder.object_storage.length, builder.body.text_extent.ordinal, builder.body);
		storage.heap_allocated = true;
		storage.transferable = true;
		storage.cleanup_rank = leaf.place.ordinal;
		builder.object_storage.add (storage);
		var construction = new CoreConstructorObjectInitialization (original.span, storage, leaf.place, owner.constructor, new GenericArray<CoreValue> (), new CoreParameterValue (original.span, builder.parameters[0]));
		construction.acquisition = leaf;
		builder.body.statements[0] = construction;
		var returned = (CoreOwnershipReturn) builder.body.statements[1];
		builder.body.statements[1] = new CoreOwnershipReturn (returned.span, leaf.place.semantic_type, returned.cleanup, leaf);
		var result = summary (core, "build");
		var origins = result.equations.requirements (result.result);
		assert (origins.length == 1 && origins[0].kind == RuntimeScopeOriginKind.CONTEXT_PARAMETER && origins[0].ordinal == 0);
		summary (core, "exercise");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void incomplete_scoped_proof() {
	try {
		var core = build (SCOPED + "int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();return 0;}int main(){return 0;}");
		var target = function (core, "exercise");
		CoreLocalPlace? context = null;
		foreach (var local in target.locals) {
			if (local.semantic_type.is_scoped_allocator ()) {
				context = local;
			}
		}
		assert (context != null);
		var leaf = inject (target.body, context, target);
		var extent = leaf.place.text_extent;
		leaf.place.text_extent = new Astra.Text.TextLoanExtent (extent, extent.ordinal + 1);
		bool rejected = false;
		try {
			CoreRuntimeLifetimes.verify (core);
		} catch (CoreError failure) {
			assert (failure.message.contains ("actual cleanup scope/rank"));
			rejected = true;
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		leaf.place.text_extent = extent;
		summary (core, "exercise");
		var storage = target.object_storage[target.object_storage.length - 1];
		storage.cleanup_rank++;
		rejected = false;
		try {
			CoreRuntimeLifetimes.verify (core);
		} catch (CoreError failure) {
			assert (failure.message.contains ("actual cleanup scope/rank"));
			rejected = true;
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		storage.cleanup_rank--;
		summary (core, "exercise");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_carrier_signature() {
	try {
		var program = build (SCOPED.replace ("init(){}", "int code;init(){this.code=7;}int read(){int value=this.code;return value;}") + "class Inner{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}class Host{private owned Inner child;init(owned Inner child){this.child=move child;}}extern(C) void* opaque_ptr();void opaque(){opaque_ptr();}void probe(borrowed Host box){}int main(){return 0;}");
		summary (program, "probe");
		var target = function (program, "probe");
		var call = new CoreCallStatement (target.span, function (program, "opaque"), new GenericArray<CoreValue> ());
		target.body.statements.insert (0, call);
		bool rejected = false;
		try {
			CoreRuntimeLifetimes.verify (program);
		} catch (CoreError failure) {
			rejected = failure.message.contains ("scoped lifetime proof is incomplete");
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		target.body.statements.remove_index (0);
		CoreRuntimeLifetimes.verify (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owned_factory_roles() {
	try {
		var program = build (SCOPED + "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}int probe(borrowed Host host){var context=context_open();return 0;}int main(){return 0;}");
		summary (program, "probe");
		var target = function (program, "probe");
		CoreCFunction? factory = null;
		foreach (var candidate in program.c_functions) {
			if (candidate.name == "context_open") {
				factory = candidate;
			}
		}
		assert (factory != null && factory.owned_cleanup != null);
		foreach (bool wrong in new bool[] { false, true }) {
			var cleanup = wrong ? new CoreCleanupContract ("wrong_context_cleanup", target.span, 0) : null;
			var mutant = new CoreCFunction (factory.span, factory.name_span, factory.name, factory.metadata, factory.abi, factory.return_type, factory.parameter_types, factory.ordinal, cleanup, factory.parameters);
			var call = new CoreValueStatement (target.span, new CoreCCallValue (target.span, factory.return_type, mutant, new GenericArray<CoreValue> ()));
			target.body.statements.insert (0, call);
			bool rejected = false;
			try {
				CoreRuntimeLifetimes.verify (program);
			} catch (CoreError failure) {
				rejected = failure.message.contains ("foreign call requires");
				Test.message ("%s", failure.message);
			}
			assert (rejected);
			target.body.statements.remove_index (0);
			CoreRuntimeLifetimes.verify (program);
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
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void exceptional_results() {
	try {
		string fault = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}";
		var core = build (fault + SCOPED + "owned ScopedLeaf attempt(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(\"bad\");}return move input;}owned ScopedLeaf caught(owned ScopedLeaf input,int mode){try{var result=attempt(move input,mode);return move result;}catch(Fault error){return null;}}int main(){return 0;}", "attempt,caught");
		var attempted = summary (core, "attempt");
		assert (attempted.has_exception && attempted.equations.requirements (attempted.exception).length == 0 && has (attempted.equations.requirements (attempted.result), 0));
		var caught = summary (core, "caught");
		assert (!caught.has_exception && has (caught.equations.requirements (caught.result), 0));
		var weak = WeakRef (function (core, "attempt"));
		core = null;
		assert (weak.get () == null);
		assert (attempted.equations.requirements (attempted.result).length == 1);
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		core = build (fault + SCOPED + host + "void alter(borrowed Host box,owned ScopedLeaf input)throws Fault{box.put(move input);throw new Fault(\"changed\");}void observe(borrowed Host box,owned ScopedLeaf input){try{alter(box,move input);}catch(Fault error){}}int main(){return 0;}", "alter,observe");
		foreach (string name in new string[] { "alter", "observe" }) {
			var effect = summary (core, name);
			assert (effect.updated_inputs ().length == 1 && effect.store_count == 1 && has (effect.equations.requirements (effect.update (0), "f0"), 1));
		}
		string throwing_host = "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child,int mode)throws Fault{this.child=move child;if(mode!=0){throw new Fault(\"partial\");}}}";
		core = build (fault + SCOPED + throwing_host + "owned ScopedLeaf recover(borrowed Context context,owned ScopedLeaf input,int mode){try{var host=try_new(context)Host(move input,mode);if(host==null){return move input;}}catch(Fault error){}return null;}int main(){return 0;}", "recover");
		var recovered = summary (core, "recover");
		assert (!recovered.has_exception && has (recovered.equations.requirements (recovered.result), 1));

		core = build (fault + SCOPED + "void consume(owned ScopedLeaf input,int marker){}int later()throws Fault{throw new Fault(\"before\");}owned ScopedLeaf restore(owned ScopedLeaf input){try{consume(move input,later());}catch(Fault error){return move input;}return null;}int main(){return 0;}", "consume,restore");
		var restored = summary (core, "restore");
		assert (has (restored.equations.requirements (restored.result), 0));
		string owned_fault = "[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}";
		core = build (SCOPED + owned_fault + "void raise(owned ScopedLeaf input)throws Fault{throw new Fault(move input);}void reroute(owned ScopedLeaf input)throws Fault{try{raise(move input);}catch(Fault error){throw;}}int main(){return 0;}", "raise,reroute");
		var raised = summary (core, "raise");
		assert (raised.has_exception && has (raised.equations.requirements (raised.exception), 0));
		var rerouted = summary (core, "reroute");
		assert (rerouted.has_exception && has (rerouted.equations.requirements (rerouted.exception), 0));
		var raised_function = function (core, "raise");
		var bound = raised_function.throws_type;
		foreach (var owner in core.classes) {
			if (owner.name == "ScopedLeaf") {
				raised_function.throws_type = (ClassType) owner.semantic_type;
			}
		}
		assert (raised_function.throws_type != bound);
		bool wrong_bound = false;
		try {
			CoreRuntimeLifetimes.verify (core);
		} catch (CoreError failure) {
			wrong_bound = failure.message.contains ("throws bound");
			Test.message ("%s", failure.message);
		}
		assert (wrong_bound);
		raised_function.throws_type = bound;
		summary (core, "reroute");

		foreach (bool outside in new bool[] { false, true }) {
			string body = outside ? "try{owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}}catch(Fault error){}" : "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);try{var leaf=empty();throw new Fault(move leaf);}catch(Fault error){}}";
			core = build (SCOPED + owned_fault + "int exercise(){" + body + "return 0;}int main(){return 0;}");
			var target = function (core, "exercise");
			CoreLocalPlace? context = null;
			foreach (var local in target.locals) {
				if (local.semantic_type.is_scoped_allocator ()) {
					context = local;
				}
			}
			assert (context != null);
			bool injected = false;
			CoreCatch? actual_catch = null;
			foreach (var source in target.body.statements) {
				var guarded = source as CoreTry;
				var scope = source as CoreScope;
				if (guarded != null) {
					actual_catch = guarded.catches[0];
					foreach (var child in guarded.body.statements) {
						if (child is CoreScope) {
							inject (((CoreScope) child).body, context, target);
							injected = true;
						}
					}
				}
				if (scope != null) {
					foreach (var child in scope.body.statements) {
						if (child is CoreTry) {
							actual_catch = ((CoreTry) child).catches[0];
							inject (((CoreTry) child).body, context, target);
							injected = true;
						}
					}
				}
			}
			assert (injected && actual_catch != null);
			if (outside) {
				bool rejected = false;
				try {
					CoreRuntimeLifetimes.verify (core);
				} catch (CoreError failure) {
					rejected = failure.message.contains ("cannot outlive context");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
			} else {
				summary (core, "exercise");
				var extent = actual_catch.binding.text_extent;
				actual_catch.binding.text_extent = new Astra.Text.TextLoanExtent (extent, extent.ordinal + 1);
				bool rejected = false;
				try {
					CoreRuntimeLifetimes.verify (core);
				} catch (CoreError failure) {
					rejected = failure.message.contains ("exact cleanup extent");
					Test.message ("%s", failure.message);
				}
				assert (rejected);
				actual_catch.binding.text_extent = extent;
				summary (core, "exercise");
			}
		}
		core = build (SCOPED + owned_fault + "void escape()throws Fault{owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}int main(){return 0;}");
		var escaped = function (core, "escape");
		CoreLocalPlace? local_context = null;
		foreach (var local in escaped.locals) {
			if (local.semantic_type.is_scoped_allocator ()) {
				local_context = local;
			}
		}
		assert (local_context != null);
		inject (escaped.body, local_context, escaped);
		bool leaking = false;
		try {
			CoreRuntimeLifetimes.verify (core);
		} catch (CoreError failure) {
			leaking = failure.message.contains ("exception retains a scoped local allocation");
			Test.message ("%s", failure.message);
		}
		assert (leaking);

	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private const string TASK_RUNTIME = "[ExceptionRoot]class TaskError{init(string message){}virtual property string message{get{return \"task\";}}}enum TaskStatus{Completed,Cancelled}async runtime Tasks throws TaskError returns TaskStatus;";
private void cold_task_contract() {
	try {
		CoreProgram? core = build (TASK_RUNTIME + LEAF + "struct Packet{owned Leaf item;int marker;}async Packet deliver(Packet input){return move input;}int main(){return 0;}");
		var task = summary (core, "deliver");
		assert (!task.has_exception && task.store_count == 0 && task.updated_inputs ().length == 0);
		assert (has (task.equations.requirements (task.result, "f0"), 0));
		assert (task.equations.requirements (task.result, "f1").length == 0);
		assert (has (task.equations.requirements (task.result, "f2"), 0));
		var weak = WeakRef (function (core, "deliver"));
		core = null;
		assert (weak.get () == null);
		assert (has (task.equations.requirements (task.result, "f2"), 0));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_scoped_capture() {
	try {
		var core = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();var pending=consume(move input);return 0;}int main(){return exercise();}");
		var task = summary (core, "consume");
		assert (task.equations.requirements (task.result, "f0").length == 0);
		assert (task.equations.requirements (task.result, "f1").length == 0);
		assert (has (task.equations.requirements (task.result, "f2"), 0));
		summary (core, "exercise");
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
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_admission() {
	try {
		var program = build (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}struct Packet{owned Captured child;int marker;}async void consume(Packet input){}Packet refused(borrowed Context frames,Packet input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}Packet vacant={child=empty(),marker=0};return move vacant;}int main(){return 0;}");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result, "f0"), 1, "f0"));
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
		assert (has (refused.equations.requirements (refused.result, "f0"), 1, "f0"));
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

private void generic_slots_call_roles() {
	try {
		string text;
		FileUtils.get_contents ("tests/runtime-composition-17/freeze-1-owner-slot.astra", out text);
		var program = build (text);
		CoreVerifier.verify_concrete (program);
		var target = function (program, "publish");
		CoreCCallStatement? call = null;
		foreach (var statement in target.body.statements) {
			var candidate = statement as CoreCCallStatement;
			if (candidate != null && candidate.target.name == "observe") {
				call = candidate;
			}
		}
		assert (call != null);
		var query = call.arguments[1] as CoreSlotsValue;
		assert (query != null && query.action == OwnerSlotsAction.LENGTH && query.borrower == null && query.operand == null);
		call.arguments[1] = new CoreSlotsValue (query.span, query.semantic_type, query.store, query.action, query.operand, call.target.parameters[1], query.iteration);
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError failure) {
			rejected = failure.message.contains ("owner-slot query/reserve lost exact action");
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		call.arguments[1] = query;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void generic_buffer_domains() {
	try {
		var program = build ("struct Box<T>{T value;}Box<int> box(int n){Box<int> result={value=n};return result;}int main(){var context=context_open();if(context==null){return 1;}var selected=new(context)u8[17];var ordinary=new u8[19];selected[0]=3;ordinary[0]=4;var result=box(7);return result.value+(selected[0] as int)+(ordinary[0] as int);}");
		CoreVerifier.verify_concrete (program);
		CoreCleanupContract? selected = null;
		CoreCleanupContract? ordinary = null;
		foreach (var cleanup in program.cleanups) {
			if (!cleanup.is_buffer) {
				continue;
			}
			if (cleanup.buffer_type is ContextBytesType) {
				assert (selected == null);
				selected = cleanup;
			} else {
				assert (ordinary == null);
				ordinary = cleanup;
			}
		}
		assert (selected != null && ordinary != null && selected.buffer_type != ordinary.buffer_type);
		assert (selected.buffer_type.element_type == ordinary.buffer_type.element_type);
		assert (selected.buffer_type.canonical_key () != ordinary.buffer_type.canonical_key ());
		var exact = selected.buffer_shape;
		selected.buffer_shape = ordinary.buffer_shape;
		bool rejected = false;
		try {
			CoreVerifier.verify_concrete (program);
		} catch (CoreError failure) {
			rejected = failure.message.contains ("buffer cleanup");
			Test.message ("%s", failure.message);
		}
		assert (rejected);
		selected.buffer_shape = exact;
		CoreVerifier.verify_concrete (program);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/runtime-lifetime-core/generic-buffer-domains", generic_buffer_domains);
	Test.add_func ("/runtime-lifetime-core/generic-slots-call-roles", generic_slots_call_roles);
	Test.add_func ("/runtime-lifetime-core/cold-task-record-buffer-observation", cold_task_record_buffer_observation);
	Test.add_func ("/runtime-lifetime-core/cold-task-record-buffer-admission", cold_task_record_buffer_admission);
	Test.add_func ("/runtime-lifetime-core/cold-task-buffer-admission", cold_task_buffer_admission);
	Test.add_func ("/runtime-lifetime-core/cold-task-record-admission", cold_task_record_admission);
	Test.add_func ("/runtime-lifetime-core/cold-task-record-observation", cold_task_record_observation);
	Test.add_func ("/runtime-lifetime-core/cold-task-deferred-error", cold_task_deferred_error);
	Test.add_func ("/runtime-lifetime-core/cold-task-admission-refusal", cold_task_admission_refusal);
	Test.add_func ("/runtime-lifetime-core/cold-task-joined-capture", cold_task_joined_capture);
	Test.add_func ("/runtime-lifetime-core/cold-task-contract", cold_task_contract);
	Test.add_func ("/runtime-lifetime-core/cold-task-scoped-capture", cold_task_scoped_capture);
	Test.add_func ("/runtime-lifetime-core/exceptional-results", exceptional_results);
	Test.add_func ("/runtime-lifetime-core/fallible-owner-inputs", fallible_owner_inputs);
	Test.add_func ("/runtime-lifetime-core/owned-context-factory-roles", owned_factory_roles);
	Test.add_func ("/runtime-lifetime-core/scoped-carrier-signature", scoped_carrier_signature);
	Test.add_func ("/runtime-lifetime-core/independent-constructor-forward", independent_constructors);
	Test.add_func ("/runtime-lifetime-core/records-conditional-loop", records_and_control);
	Test.add_func ("/runtime-lifetime-core/opaque-native-declaration", opaque_native);
	Test.add_func ("/runtime-lifetime-core/scoped-result", scoped_result);
	Test.add_func ("/runtime-lifetime-core/scoped-receiver", scoped_receiver);
	Test.add_func ("/runtime-lifetime-core/scoped-formal", scoped_formal);
	Test.add_func ("/runtime-lifetime-core/incomplete-scoped-proof", incomplete_scoped_proof);
	return Test.run ();
}

}
