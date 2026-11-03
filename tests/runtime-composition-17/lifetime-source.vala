// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;

namespace Astra.Tests.RuntimeLifetimeSource {
private const string API = "[CCode(destroy_function=\"astra_context17_destroy\",context=\"scoped-affine\")]handle Scoped;";
private const string LEAF = "class Leaf{int code;init(int code){this.code=code;}}";
private const string HOLDER = "class Holder{private owned Leaf child;init(owned Leaf child){this.child=move child;}void put(owned Leaf child){this.child=move child;}}";
private const string SCOPED_LEAF = "[Allocator(kind=\"context\",context=\"scoped-affine\")]class ScopedLeaf{init(){}}owned ScopedLeaf empty(){return null;}";
private SemanticResult analyzed(string text, string declarations = API, string? heap_boundary = null) {
	var parsed = Parser.parse (new SourceFile.from_text ("lifetime-source.astra", text));
	if (parsed.diagnostic != null) {
		error ("%s", parsed.diagnostic.message);
	}
	var api = VapiParser.parse (new SourceFile.from_text ("lifetime-source.vapi", declarations));
	assert (api.diagnostic == null);
	if (heap_boundary == null) {
		return SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (api.file), VapiNormalizer.normalize_handles (api.file));
	}
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
		return SemanticAnalyzer.analyze_program (new SyntaxProgram (units), VapiNormalizer.normalize (api.file), VapiNormalizer.normalize_handles (api.file), null, boundaries);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private CheckedProgram checked(string text, string declarations = API, string? heap_boundary = null) {
	var result = analyzed (text, declarations, heap_boundary);
	if (result.diagnostic != null) {
		error ("%s", result.diagnostic.message);
	}
	return result.program;
}

private CheckedFunction function(CheckedProgram program, string name) {
	foreach (var definition in program.functions) {
		if (definition.symbol.name == name) {
			return definition;
		}
	}
	error ("missing %s", name);
}

private RuntimeLifetimeSummary summary(CheckedProgram program, string name) {
	var result = function (program, name).runtime_lifetimes;
	assert (result != null);
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

private void constructor_and_forward() {
	try {
		var program = checked (LEAF + HOLDER + "owned Holder wrap(owned Leaf child){var box=new Holder(move child);return move box;}owned Holder forward(owned Leaf input){var result=wrap(move input);return move result;}int main(){return 0;}");
		var wrapped = summary (program, "wrap");
		var origins = wrapped.equations.requirements (wrapped.result);
		assert (origins.length == 1 && has (origins, 0));
		assert (wrapped.equations.requirements (wrapped.result, "", false).length == 0);
		origins = wrapped.equations.requirements (wrapped.result, "f0");
		assert (origins.length == 1 && has (origins, 0));
		var forwarded = summary (program, "forward");
		origins = forwarded.equations.requirements (forwarded.result);
		assert (origins.length == 1 && has (origins, 0));
		var reference = WeakRef (function (program, "forward"));
		program = null;
		assert (reference.get () == null);
		assert (forwarded.equations.requirements (forwarded.result).length == 1);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void branch_and_loop() {
	try {
		var program = checked (LEAF + HOLDER + "owned Holder choose(owned Leaf left,owned Leaf right,int choice){if(choice==0){var box=new Holder(move left);return move box;}var box=new Holder(move right);return move box;}void replace_loop(borrowed Holder box,owned Leaf incoming,int count){while(count>0){box.put(move incoming);break;}}int main(){return 0;}");
		var selected = summary (program, "choose");
		var origins = selected.equations.requirements (selected.result);
		assert (origins.length == 2 && has (origins, 0) && has (origins, 1));
		var loop = summary (program, "replace_loop");
		assert (loop.updated_inputs ().length == 1);
		origins = loop.equations.requirements (loop.update (0));
		assert (has (origins, 0) && has (origins, 1));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void records_and_replacement() {
	try {
		var program = checked (LEAF + HOLDER + "struct Record{owned Leaf child;int marker;}Record packet(owned Leaf input){Record value={child=move input,marker=7};return move value;}void replace(borrowed Holder box,owned Leaf input){box.put(move input);}int main(){return 0;}");
		var record = summary (program, "packet");
		var origins = record.equations.requirements (record.result, "f0");
		assert (origins.length == 1 && has (origins, 0));
		var replacement = summary (program, "replace");
		assert (replacement.updated_inputs ().length == 1 && replacement.store_count == 1);
		origins = replacement.equations.requirements (replacement.update (0), "f0");
		assert (origins.length == 1 && has (origins, 1));
		origins = replacement.equations.requirements (replacement.update (0), "", false);
		assert (origins.length == 1 && has (origins, 0));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void conditional_replacement() {
	try {
		string holder = "class Holder{private owned Leaf child;init(owned Leaf child){this.child=move child;}int change(owned Leaf child){this.child=move child;return 1;}}";
		var program = checked (LEAF + holder + "void compare(borrowed Holder box,owned Leaf incoming,int count){bool ignored=0<count<box.change(move incoming);}int main(){return 0;}");
		var result = summary (program, "compare");
		var origins = result.equations.requirements (result.update (0), "f0");
		assert (has (origins, 0, "f0") && has (origins, 1));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void incomplete_contracts() {
	var program = checked (LEAF + HOLDER + "extern(C) int foreign();int opaque(){return foreign();}owned Leaf recursive(owned Leaf input,int count){if(count>0){return recursive(move input,count-1);}return move input;}void alias(borrowed Holder left,borrowed Holder right,owned Leaf input){left.put(move input);}int main(){return 0;}");
	assert (function (program, "opaque").runtime_lifetimes.complete);
	foreach (var name in new string[] { "recursive", "alias" }) {
		var result = function (program, name).runtime_lifetimes;
		assert (result != null && !result.complete && result.limitation != "");
		Test.message ("%s: %s", name, result.limitation);
	}
}

private void argument_mutation() {
	string holder = "class Holder{private owned Leaf child;init(owned Leaf child){this.child=move child;}void put(owned Leaf child){this.child=move child;}int observe(int ignored){return 0;}}";
	var program = checked (LEAF + holder + "int mutate(borrowed Holder box,owned Leaf input){box.put(move input);return 1;}int nested(borrowed Holder box,owned Leaf input){return box.observe(mutate(box,move input));}int main(){return 0;}");
	var result = function (program, "nested").runtime_lifetimes;
	assert (result != null && !result.complete && result.limitation.contains ("pending borrowed owner"));
}

private void opaque_declaration() {
	var program = checked (LEAF + "owned Leaf origin(owned Leaf input){return move input;}owned Leaf caller(owned Leaf input){return origin(move input);}int main(){return 0;}");
	summary (program, "caller");
	var producer = function (program, "origin");
	var source = producer.symbol.name_span.file;
	var registry = new NativeDeclarationRegistry ();
	var names = new GenericArray<string> ();
	names.add ("Leaf");
	registry.add_types (source, names);
	assert (registry.record_applications (source)[0] == "Leaf");
	var identity = new NativeDeclarationIdentity ("lifetime-native", "F:origin", "opaque_origin", "test-declaration");
	registry.add (source, identity);
	assert (registry.lookup (producer.symbol) == identity);
	producer.bind_native_declaration (NativeDeclarationRegistry.signature (identity, producer.symbol));
	assert (SemanticRuntimeLifetimes.check (program) == null);
	assert (producer.runtime_lifetimes == null);
	var consumer = function (program, "caller").runtime_lifetimes;
	assert (consumer != null && !consumer.complete && consumer.limitation.contains ("complete direct lifetime summary"));
}

private LocalSymbol inject_scoped_leaf(CheckedBlockStatement block, LocalSymbol context) {
	for (int i = 0; i < block.statements.length; i++) {
		var declaration = block.statements[i] as CheckedLocalDeclaration;
		if (declaration == null || declaration.local.name != "leaf") {
			continue;
		}
		var owner = declaration.local.object_owner;
		assert (owner != null);
		var storage = new LexicalObjectStorageSymbol (declaration.span, declaration.local.name_span, owner, 0, declaration.local.lexical_region);
		storage.heap_allocated = true;
		storage.cleanup_rank = declaration.local.ordinal;
		block.statements[i] = new CheckedConstructorObjectInitialization (declaration.span, storage, declaration.local, owner.constructor, new GenericArray<CheckedExpression> (), new CheckedLocalReferenceExpression (context.span, context));
		return declaration.local;
	}
	error ("scoped fixture has no leaf declaration");
}

private CheckedProgram scoped_fixture(bool escaping) {
	string source = SCOPED_LEAF + (escaping ? "owned ScopedLeaf exercise()" : "int exercise()") + "{owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();" + (escaping ? "return null;" : "return 0;") + "}int main(){return 0;}";
	var program = checked (source);
	var body = function (program, "exercise");
	LocalSymbol? context = null;
	foreach (var local in body.locals) {
		if (local.semantic_type.is_scoped_allocator ()) {
			context = local;
		}
	}
	assert (context != null);
	var leaf = inject_scoped_leaf (body.body, context);
	if (escaping) {
		var returned = body.body.statements[body.body.statements.length - 1];
		body.body.statements[body.body.statements.length - 1] = new CheckedOwnershipReturn (returned.span, leaf.semantic_type, null, new CheckedOwnershipMove (returned.span, leaf), leaf.object_owner);
	}
	return program;
}

private void scoped_receiver_storage() {
	string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
	foreach (bool outer in new bool[] { false, true }) {
		var program = checked (SCOPED_LEAF + host + "int exercise(){" + (outer ? "var box=new Host(null);" : "") + "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);" + (outer ? "" : "var box=new Host(null);") + "var leaf=empty();box.put(move leaf);}return 0;}int main(){return 0;}");
		var body = function (program, "exercise");
		LocalSymbol? context = null;
		foreach (var local in body.locals) {
			if (local.semantic_type.is_scoped_allocator ()) {
				context = local;
			}
		}
		assert (context != null);
		bool injected = false;
		foreach (var statement in body.body.statements) {
			var block = statement as CheckedBlockStatement;
			if (block != null) {
				inject_scoped_leaf (block, context);
				injected = true;
			}
		}
		assert (injected);
		var diagnostic = SemanticRuntimeLifetimes.check (program);
		if (outer) {
			assert (diagnostic != null && diagnostic.message.contains ("cannot outlive context"));
			Test.message ("%s", diagnostic.message);
		} else {
			assert (diagnostic == null);
			summary (program, "exercise");
		}
	}
}

private void scoped_formal_substitution() {
	try {
		var program = checked (SCOPED_LEAF + "owned ScopedLeaf build(borrowed Scoped context){var leaf=empty();return null;}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var result=build(context);return 0;}int main(){return 0;}");
		var builder = function (program, "build");
		var parameter = builder.symbol.parameters[0];
		var declaration = builder.body.statements[0] as CheckedLocalDeclaration;
		assert (declaration != null);
		var owner = declaration.local.object_owner;
		var storage = new LexicalObjectStorageSymbol (declaration.span, declaration.local.name_span, owner, 0, declaration.local.lexical_region);
		storage.heap_allocated = true;
		storage.cleanup_rank = declaration.local.ordinal;
		builder.body.statements[0] = new CheckedConstructorObjectInitialization (declaration.span, storage, declaration.local, owner.constructor, new GenericArray<CheckedExpression> (), new CheckedParameterReferenceExpression (parameter.span, parameter));
		builder.body.statements[1] = new CheckedOwnershipReturn (declaration.span, declaration.local.semantic_type, null, new CheckedOwnershipMove (declaration.span, declaration.local), owner);
		assert (SemanticRuntimeLifetimes.check (program) == null);
		var result = summary (program, "build");
		var origins = result.equations.requirements (result.result);
		assert (origins.length == 1 && origins[0].kind == RuntimeScopeOriginKind.CONTEXT_PARAMETER && origins[0].ordinal == 0);
		summary (program, "exercise");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scoped_actual_nodes() {
	try {
		var admitted = checked (SCOPED_LEAF + "int main(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=new(context)ScopedLeaf();return 0;}");
		summary (admitted, "main");
		var safe = scoped_fixture (false);
		assert (SemanticRuntimeLifetimes.check (safe) == null);
		summary (safe, "exercise");
		var escaping = scoped_fixture (true);
		var diagnostic = SemanticRuntimeLifetimes.check (escaping);
		assert (diagnostic != null && diagnostic.message.contains ("result retains a scoped local allocation"));
		Test.message ("%s", diagnostic.message);
		// Detach the original function before querying the retained neutral proof.
		var proof = summary (safe, "exercise");
		var weak = WeakRef (function (safe, "exercise"));
		safe = null;
		assert (weak.get () == null);
		assert (proof.equations.requirements (proof.result).length == 0);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void fallible_scoped_construction() {
	foreach (bool escaping in new bool[] { false, true }) {
		var program = scoped_fixture (escaping);
		var body = function (program, "exercise");
		bool changed = false;
		for (int i = 0; i < body.body.statements.length; i++) {
			var construction = body.body.statements[i] as CheckedConstructorObjectInitialization;
			if (construction == null) {
				continue;
			}
			var original = construction.storage;
			var fallible = new LexicalObjectStorageSymbol (original.span, original.name_span, original.object_class, original.ordinal, original.lexical_region, true);
			fallible.heap_allocated = original.heap_allocated;
			fallible.cleanup_rank = original.cleanup_rank;
			body.body.statements[i] = new CheckedConstructorObjectInitialization (construction.span, fallible, construction.local, construction.constructor, construction.arguments, construction.allocation_context);
			changed = true;
		}
		assert (changed);
		var diagnostic = SemanticRuntimeLifetimes.check (program);
		if (escaping) {
			assert (diagnostic != null && diagnostic.message.contains ("result retains a scoped local allocation"));
			Test.message ("%s", diagnostic.message);
		} else {
			assert (diagnostic == null);
			summary (program, "exercise");
		}
	}
}

private void hidden_scoped_construction() {
	string fault = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}";
	string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
	foreach (bool outer in new bool[] { false, true }) {
		var program = checked (fault + SCOPED_LEAF + host + "int exercise(){" + (outer ? "var box=new Host(null);" : "") + "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);try{" + (outer ? "" : "var box=new Host(null);") + "var leaf=empty();box.put(move leaf);}catch(Fault error){}}return 0;}int main(){return 0;}");
		var body = function (program, "exercise");
		LocalSymbol? context = null;
		foreach (var local in body.locals) {
			if (local.semantic_type.is_scoped_allocator ()) {
				context = local;
			}
		}
		assert (context != null);
		bool injected = false;
		foreach (var source in body.body.statements) {
			var block = source as CheckedBlockStatement;
			if (block == null) {
				continue;
			}
			foreach (var child in block.statements) {
				var guarded = child as CheckedTry;
				if (guarded != null) {
					inject_scoped_leaf (guarded.body, context);
					injected = true;
				}
			}
		}
		assert (injected);
		var diagnostic = SemanticRuntimeLifetimes.check (program);
		if (outer) {
			assert (diagnostic != null && diagnostic.message.contains ("cannot outlive context"));
			Test.message ("%s", diagnostic.message);
		} else {
			assert (diagnostic == null);
			summary (program, "exercise");
		}
	}
}

private void hidden_nested_carriers() {
	string fault = "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}";
	string node = "class Inner{private owned CHILD child;init(owned CHILD child){this.child=move child;}}class Node{private owned Inner child;init(owned Inner child){this.child=move child;}}";
	string exercise = "int exercise(){try{var node=new Node(null);}catch(Fault error){}return 0;}int main(){return 0;}";
	var ordinary = checked (fault + LEAF + node.replace ("CHILD", "Leaf") + exercise);
	summary (ordinary, "exercise");
	var scoped = checked (fault + SCOPED_LEAF + node.replace ("CHILD", "ScopedLeaf") + exercise);
	summary (scoped, "exercise");
	var unsafe_call = analyzed (fault + SCOPED_LEAF + node.replace ("CHILD", "ScopedLeaf") + "extern(C)void* opaque();" + exercise.replace ("var node=new Node(null);", "var node=new Node(null);opaque();"));
	assert (unsafe_call.diagnostic != null && unsafe_call.diagnostic.message.contains ("scoped lifetime proof is incomplete"));
	Test.message ("%s", unsafe_call.diagnostic.message);
}

private void scoped_carrier_signature() {
	string host = "class Inner{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}class Host{private owned Inner child;init(owned Inner child){this.child=move child;}}";
	string body = "void probe(borrowed Host box){opaque();}int main(){return 0;}";
	checked (SCOPED_LEAF + host + "void opaque(){}" + body);
	var result = analyzed (SCOPED_LEAF + host + "extern(C) void* opaque_ptr();void opaque(){opaque_ptr();}" + body);
	assert (result.program == null && result.diagnostic != null && result.diagnostic.message.contains ("scoped lifetime proof is incomplete"));
	Test.message ("%s", result.diagnostic.message);
}

private void scalar_lengths() {
	try {
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		var program = checked (SCOPED_LEAF + host + "int measure(borrowed Host box,borrowed u8[] data){return len(data);}int main(){owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);var box=new Host(null);}return len(backing)-4097;}");
		var measured = summary (program, "measure");
		assert (measured.equations.requirements (measured.result).length == 0);
		assert (summary (program, "main").equations.requirements (summary (program, "main").result).length == 0);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owned_context_factories() {
	try {
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}";
		foreach (var mode in new string[] { "owned-affine", "owned-transfer", "owned-concurrent" }) {
			string declarations = API + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"MODE\")]handle Context;owned Context context_open(int kind);".replace ("MODE", mode);
			var program = checked (SCOPED_LEAF + host + "int probe(borrowed Host host){var context=context_open(1);return 0;}int main(){return 0;}", declarations);
			assert (summary (program, "probe").equations.requirements (summary (program, "probe").result).length == 0);
			var borrowed = analyzed (SCOPED_LEAF + host + "int probe(borrowed Host host,borrowed Scoped input){var context=context_open(input);return 0;}int main(){return 0;}", declarations.replace ("int kind", "borrowed Scoped input"));
			assert (borrowed.diagnostic != null && borrowed.diagnostic.message.contains ("foreign call requires"));
			var unmanaged = analyzed (SCOPED_LEAF + host + "int probe(borrowed Host host){var context=context_open(1);return 0;}int main(){return 0;}", declarations.replace ("owned Context", "Context"));
			assert (unmanaged.diagnostic != null);
			Test.message ("%s", unmanaged.diagnostic.message);
		}
		var scoped = analyzed (SCOPED_LEAF + host + "int probe(borrowed Host host){var context=scope_open();return 0;}int main(){return 0;}", API + "owned Scoped scope_open();");
		assert (scoped.diagnostic != null);
		Test.message ("%s", scoped.diagnostic.message);
		var opaque = analyzed (SCOPED_LEAF + host + "int probe(borrowed Host host){var context=opaque_open();return 0;}int main(){return 0;}", API + "[CCode(destroy_function=\"opaque_destroy\")]handle Opaque;owned Opaque opaque_open();");
		assert (opaque.diagnostic != null && opaque.diagnostic.message.contains ("foreign call requires"));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void fallible_owner_inputs() {
	try {
		string declarations = API + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;";
		string host = "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}}";
		var program = checked (SCOPED_LEAF + host + "owned ScopedLeaf refuse(borrowed Context context,owned ScopedLeaf input){var host=try_new(context)Host(move input);if(host==null){return move input;}return null;}int main(){return 0;}", declarations);
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
		var program = checked (fault + SCOPED_LEAF + "owned ScopedLeaf attempt(owned ScopedLeaf input,int mode)throws Fault{if(mode!=0){throw new Fault(\"bad\");}return move input;}owned ScopedLeaf caught(owned ScopedLeaf input,int mode){try{var result=attempt(move input,mode);return move result;}catch(Fault error){return null;}}int main(){return 0;}", API, "attempt,caught");
		var attempted = summary (program, "attempt");
		assert (attempted.has_exception && attempted.equations.requirements (attempted.exception).length == 0 && has (attempted.equations.requirements (attempted.result), 0));
		var caught = summary (program, "caught");
		assert (!caught.has_exception && has (caught.equations.requirements (caught.result), 0));
		CheckedFunction? producer = function (program, "attempt");
		var weak = WeakRef (producer);
		var identity = new NativeDeclarationIdentity ("exception-source", "F:attempt", "opaque_attempt", "test", "", false, "", "", attempted.encode ());
		producer.bind_native_declaration (NativeDeclarationRegistry.signature (identity, producer.symbol));
		assert (SemanticRuntimeLifetimes.check (program) == null);
		var opaque_caught = summary (program, "caught");
		assert (!opaque_caught.has_exception && has (opaque_caught.equations.requirements (opaque_caught.result), 0));
		producer = null;
		program = null;
		assert (weak.get () == null);
		assert (opaque_caught.equations.requirements (opaque_caught.result).length == 1);
		string host = "class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}void put(owned ScopedLeaf child){this.child=move child;}}";
		program = checked (fault + SCOPED_LEAF + host + "void alter(borrowed Host box,owned ScopedLeaf input)throws Fault{box.put(move input);throw new Fault(\"changed\");}void observe(borrowed Host box,owned ScopedLeaf input){try{alter(box,move input);}catch(Fault error){}}int main(){return 0;}", API, "alter,observe");
		foreach (string name in new string[] { "alter", "observe" }) {
			var effect = summary (program, name);
			assert (effect.updated_inputs ().length == 1 && effect.store_count == 1 && has (effect.equations.requirements (effect.update (0), "f0"), 1));
		}
		string throwing_host = "[Allocator(kind=\"context\",context=\"owned-concurrent\")]class Host{private owned ScopedLeaf child;init(owned ScopedLeaf child,int mode)throws Fault{this.child=move child;if(mode!=0){throw new Fault(\"partial\");}}}";
		program = checked (fault + SCOPED_LEAF + throwing_host + "owned ScopedLeaf recover(borrowed Context context,owned ScopedLeaf input,int mode){try{var host=try_new(context)Host(move input,mode);if(host==null){return move input;}}catch(Fault error){}return null;}int main(){return 0;}", API + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;", "recover");
		var recovered = summary (program, "recover");
		assert (!recovered.has_exception && has (recovered.equations.requirements (recovered.result), 1));

		program = checked (fault + SCOPED_LEAF + "void consume(owned ScopedLeaf input,int marker){}int later()throws Fault{throw new Fault(\"before\");}owned ScopedLeaf restore(owned ScopedLeaf input){try{consume(move input,later());}catch(Fault error){return move input;}return null;}int main(){return 0;}", API, "consume,restore");
		var restored = summary (program, "restore");
		assert (has (restored.equations.requirements (restored.result), 0));
		string owned_fault = "[ExceptionRoot]class Fault{private owned ScopedLeaf child;init(owned ScopedLeaf child){this.child=move child;}virtual property string message{get{return \"owned\";}}}";
		program = checked (SCOPED_LEAF + owned_fault + "void raise(owned ScopedLeaf input)throws Fault{throw new Fault(move input);}void reroute(owned ScopedLeaf input)throws Fault{try{raise(move input);}catch(Fault error){throw;}}int main(){return 0;}", API, "raise,reroute");
		var raised = summary (program, "raise");
		assert (raised.has_exception && has (raised.equations.requirements (raised.exception), 0));
		var rerouted = summary (program, "reroute");
		assert (rerouted.has_exception && has (rerouted.equations.requirements (rerouted.exception), 0));
		foreach (bool outside in new bool[] { false, true }) {
			string body = outside ? "try{owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}}catch(Fault error){}" : "owned u8[] backing=new u8[4097];{var context=scoped_allocator<Scoped>(backing,1,7);try{var leaf=empty();throw new Fault(move leaf);}catch(Fault error){}}";
			program = checked (SCOPED_LEAF + owned_fault + "int exercise(){" + body + "return 0;}int main(){return 0;}");
			var definition = function (program, "exercise");
			LocalSymbol? context = null;
			foreach (var local in definition.locals) {
				if (local.semantic_type.is_scoped_allocator ()) {
					context = local;
				}
			}
			assert (context != null);
			bool injected = false;
			foreach (var source in definition.body.statements) {
				var guarded = source as CheckedTry;
				var scope = source as CheckedBlockStatement;
				if (guarded != null) {
					foreach (var child in guarded.body.statements) {
						if (child is CheckedBlockStatement) {
							inject_scoped_leaf ((CheckedBlockStatement) child, context);
							injected = true;
						}
					}
				}
				if (scope != null) {
					foreach (var child in scope.statements) {
						if (child is CheckedTry) {
							inject_scoped_leaf (((CheckedTry) child).body, context);
							injected = true;
						}
					}
				}
			}
			assert (injected);
			var diagnostic = SemanticRuntimeLifetimes.check (program);
			if (outside) {
				assert (diagnostic != null && diagnostic.message.contains ("cannot outlive context"));
				Test.message ("%s", diagnostic.message);
			} else {
				assert (diagnostic == null);
				summary (program, "exercise");
			}
		}
		program = checked (SCOPED_LEAF + owned_fault + "void escape()throws Fault{owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var leaf=empty();throw new Fault(move leaf);}int main(){return 0;}");
		var escaped = function (program, "escape");
		LocalSymbol? local_context = null;
		foreach (var local in escaped.locals) {
			if (local.semantic_type.is_scoped_allocator ()) {
				local_context = local;
			}
		}
		assert (local_context != null);
		inject_scoped_leaf (escaped.body, local_context);
		var escape = SemanticRuntimeLifetimes.check (program);
		assert (escape != null && escape.message.contains ("exception retains a scoped local allocation"));
		Test.message ("%s", escape.message);

	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private const string TASK_RUNTIME = "[ExceptionRoot]class TaskError{init(string message){}virtual property string message{get{return \"task\";}}}enum TaskStatus{Completed,Cancelled}async runtime Tasks throws TaskError returns TaskStatus;";
private void cold_task_contract() {
	try {
		var program = checked (TASK_RUNTIME + LEAF + "struct Packet{owned Leaf item;int marker;}async Packet deliver(Packet input){return move input;}int main(){return 0;}");
		var task = summary (program, "deliver");
		assert (!task.has_exception && task.store_count == 0 && task.updated_inputs ().length == 0);
		assert (has (task.equations.requirements (task.result, "f0"), 0));
		assert (task.equations.requirements (task.result, "f1").length == 0);
		assert (has (task.equations.requirements (task.result, "f2"), 0));
		var weak = WeakRef (function (program, "deliver"));
		program = null;
		assert (weak.get () == null);
		assert (has (task.equations.requirements (task.result, "f2"), 0));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_scoped_capture() {
	try {
		string text = TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();var pending=consume(move input);return 0;}int main(){return exercise();}";
		var program = checked (text);
		var task = summary (program, "consume");
		assert (task.equations.requirements (task.result, "f0").length == 0);
		assert (task.equations.requirements (task.result, "f1").length == 0);
		assert (has (task.equations.requirements (task.result, "f2"), 0));
		summary (program, "exercise");
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_frame_region() {
	foreach (bool late in new bool[] { false, true }) {
		string context_text = "owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);";
		var program = checked (TASK_RUNTIME + "async void child(){}int exercise(){" + (late ? "var pending=child();" + context_text : context_text + "var pending=child();") + "return 0;}int main(){return exercise();}");
		var target = function (program, "exercise");
		LocalSymbol? context = null;
		foreach (var local in target.locals) {
			if (local.semantic_type.is_scoped_allocator ()) {
				context = local;
			}
		}
		assert (context != null);
		bool changed = false;
		for (int i = 0; i < target.body.statements.length; i++) {
			var declaration = target.body.statements[i] as CheckedLocalDeclaration;
			if (declaration == null || declaration.local.name != "pending") {
				continue;
			}
			var creation = declaration.initializer as CheckedTaskCreate;
			assert (creation != null);
			target.body.statements[i] = new CheckedLocalDeclaration (declaration.span, declaration.local, new CheckedTaskCreate (creation.span, creation.target, creation.arguments, new CheckedLocalReferenceExpression (context.span, context)));
			changed = true;
		}
		assert (changed);
		var diagnostic = SemanticRuntimeLifetimes.check (program);
		if (late) {
			assert (diagnostic != null && diagnostic.message.contains ("cannot outlive context"));
			Test.message ("%s", diagnostic.message);
		} else {
			assert (diagnostic == null);
			summary (program, "exercise");
		}
	}
}

private void cold_task_joined_capture() {
	try {
		var program = checked (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}async void joined(owned Captured input) throws TaskError{var child=consume(move input);await move child;await delay_ticks(1);}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();try{var executor=Tasks.open(8);var pending=joined(move input);var status=executor.run(move pending);match(status){case TaskStatus.Completed():{}else:{return 2;}}}catch(TaskError error){return 1;}return 0;}int main(){return exercise();}");
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
		var program = checked (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{private int marker;init(){this.marker=17;}}async void consume(owned Captured input){}owned Captured refused(borrowed Context frames,owned Captured input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}return null;}int main(){return 0;}", API + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result), 1));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_admission() {
	try {
		var program = checked (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}struct Packet{owned Captured child;int marker;}async void consume(Packet input){}Packet refused(borrowed Context frames,Packet input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}Packet vacant={child=empty(),marker=0};return move vacant;}int main(){return 0;}", API + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result, "f0"), 1, "f0"));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_buffer_admission() {
	try {
		var program = checked (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}async void consume(owned Captured item,owned u8[] bytes){}owned Captured refused(borrowed Context frames,owned Captured item,owned u8[] bytes){try{var pending=checked_task_in(frames,consume(move item,move bytes));}catch(TaskError error){return move item;}return null;}int main(){return 0;}", API + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result), 1));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_record_buffer_admission() {
	try {
		var program = checked (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}struct Storage{owned u8[] left;owned u8[] right;}struct Packet{owned Captured child;Storage data;int marker;}async void consume(Packet input){}Packet refused(borrowed Context frames,Packet input){try{var pending=checked_task_in(frames,consume(move input));}catch(TaskError error){return move input;}Packet vacant={child=empty(),data={left=new u8[0],right=new u8[0]},marker=0};return move vacant;}int main(){return 0;}", API + "[CCode(destroy_function=\"astra_context17_destroy\",context=\"owned-concurrent\")]handle Context;");
		var refused = summary (program, "refused");
		assert (has (refused.equations.requirements (refused.result, "f0"), 1, "f0"));
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void cold_task_deferred_error() {
	try {
		var program = checked ("[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}owned Captured empty(){return null;}[ExceptionRoot]class DeferredError{private owned Captured child;init(string message){this.child=empty();}void put(owned Captured input){this.child=move input;}virtual property string message{get{return \"deferred\";}}}enum DeferredStatus{Completed,Cancelled}async runtime DeferredTasks throws DeferredError returns DeferredStatus;async void fail(owned Captured input)throws DeferredError{var error=new DeferredError(\"deferred\");error.put(move input);throw move error;}int main(){return 0;}");
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
	var program = checked (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}struct Packet{owned Captured child;int marker;}async Packet deliver(Packet input){return move input;}async void collect(Packet input)throws TaskError{var pending=deliver(move input);var result=await move pending;}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();Packet packet={child=move input,marker=17};try{var executor=Tasks.open(8);var root=collect(move packet);var status=executor.run(move root);}catch(TaskError error){return 1;}return 0;}int main(){return exercise();}");
	summary (program, "collect");
	summary (program, "exercise");
}

private void cold_task_record_buffer_observation() {
	var program = checked (TASK_RUNTIME + "[Allocator(kind=\"context\",context=\"scoped-affine\")]class Captured{init(){}}struct Storage{owned u8[] left;owned u8[] right;}struct Packet{owned Captured child;Storage data;int marker;}async Packet deliver(Packet input){return move input;}async void collect(Packet input)throws TaskError{var pending=deliver(move input);var result=await move pending;}int exercise(){owned u8[] backing=new u8[4097];var context=scoped_allocator<Scoped>(backing,1,7);var input=new(context)Captured();Packet packet={child=move input,data={left=new u8[7],right=new u8[9]},marker=17};try{var executor=Tasks.open(8);var root=collect(move packet);var status=executor.run(move root);}catch(TaskError error){return 1;}return 0;}int main(){return exercise();}");
	summary (program, "collect");
	summary (program, "exercise");
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/runtime-lifetime-source/cold-task-record-buffer-observation", cold_task_record_buffer_observation);
	Test.add_func ("/runtime-lifetime-source/cold-task-record-buffer-admission", cold_task_record_buffer_admission);
	Test.add_func ("/runtime-lifetime-source/cold-task-buffer-admission", cold_task_buffer_admission);
	Test.add_func ("/runtime-lifetime-source/cold-task-record-admission", cold_task_record_admission);
	Test.add_func ("/runtime-lifetime-source/cold-task-record-observation", cold_task_record_observation);
	Test.add_func ("/runtime-lifetime-source/cold-task-deferred-error", cold_task_deferred_error);
	Test.add_func ("/runtime-lifetime-source/cold-task-admission-refusal", cold_task_admission_refusal);
	Test.add_func ("/runtime-lifetime-source/cold-task-joined-capture", cold_task_joined_capture);
	Test.add_func ("/runtime-lifetime-source/cold-task-frame-region", cold_task_frame_region);
	Test.add_func ("/runtime-lifetime-source/cold-task-contract", cold_task_contract);
	Test.add_func ("/runtime-lifetime-source/cold-task-scoped-capture", cold_task_scoped_capture);
	Test.add_func ("/runtime-lifetime-source/exceptional-results", exceptional_results);
	Test.add_func ("/runtime-lifetime-source/fallible-owner-inputs", fallible_owner_inputs);
	Test.add_func ("/runtime-lifetime-source/owned-context-factories", owned_context_factories);
	Test.add_func ("/runtime-lifetime-source/scalar-length-effects", scalar_lengths);
	Test.add_func ("/runtime-lifetime-source/scoped-carrier-signature", scoped_carrier_signature);
	Test.add_func ("/runtime-lifetime-source/hidden-nested-carriers", hidden_nested_carriers);
	Test.add_func ("/runtime-lifetime-source/fallible-scoped-construction", fallible_scoped_construction);
	Test.add_func ("/runtime-lifetime-source/hidden-scoped-construction-inventory", hidden_scoped_construction);
	Test.add_func ("/runtime-lifetime-source/constructor-forward", constructor_and_forward);
	Test.add_func ("/runtime-lifetime-source/branch-loop", branch_and_loop);
	Test.add_func ("/runtime-lifetime-source/record-replacement", records_and_replacement);
	Test.add_func ("/runtime-lifetime-source/conditional-replacement", conditional_replacement);
	Test.add_func ("/runtime-lifetime-source/incomplete-contracts", incomplete_contracts);
	Test.add_func ("/runtime-lifetime-source/argument-mutation", argument_mutation);
	Test.add_func ("/runtime-lifetime-source/opaque-declaration", opaque_declaration);
	Test.add_func ("/runtime-lifetime-source/scoped-checked-nodes", scoped_actual_nodes);
	Test.add_func ("/runtime-lifetime-source/scoped-receiver-storage", scoped_receiver_storage);
	Test.add_func ("/runtime-lifetime-source/scoped-formal-substitution", scoped_formal_substitution);
	return Test.run ();
}

}
