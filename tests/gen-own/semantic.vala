// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
namespace Astra.Tests.GenOwnSemantic {
private const string DROP = "void drop<T>(owned T value) where T : Ownable {}";
private SemanticResult check(string text) {
	var parsed = Parser.parse (new SourceFile.from_text ("ownership.astra", text));
	if (parsed.diagnostic != null) {
		GLib.error ("%s", parsed.diagnostic.format ());
	}
	var bindings = VapiParser.parse (new SourceFile.from_text ("ownership.vapi", "[CCode(destroy_function = \"release\")] handle Resource; [CCode(destroy_function = \"release\")] handle Token;"));
	return SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (bindings.file), VapiNormalizer.normalize_handles (bindings.file));
}

private CheckedProgram accept(string text) {
	var result = check (text);
	if (result.diagnostic != null) {
		GLib.error ("%s", result.diagnostic.format ());
	}
	return result.program;
}

private void reject(string text, string diagnostic) {
	var result = check (text);
	if (result.diagnostic == null || !result.diagnostic.message.contains (diagnostic)) {
		GLib.error ("expected %s, found %s", diagnostic, result.diagnostic == null ? "success" : result.diagnostic.message);
	}
	assert (result.program == null);
}

private void contracts() {
	var p = accept (DROP + "owned T relay<T>(owned T value) where T : Ownable {return move value;} U keep<T,U>(owned T owner,U value) where T : Ownable {return value;}");
	var drop = p.generic_functions[0];
	var relay = p.generic_functions[1];
	var keep = p.generic_functions[2];
	var type = relay.definition.type_parameters[0].semantic_type;
	assert (type.transport_mode == GenericTransportMode.OWNABLE && type.capability != GenericCapability.GEN1_PLAIN_COPY && !GenericArgumentTypes.plain_copy (type));
	assert (drop.capability_requirements[0].capability == relay.capability_requirements[0].capability);
	assert (relay.capability_requirements[0].capability.identity == GenericCapabilityIdentity.OWNABLE);
	assert (relay.definition.result_contract == ResultOwnershipContract.OWNED_TRANSFER && relay.definition.return_type == type && relay.definition.result_storage == null && relay.definition.owned_cleanup == null);
	assert (relay.definition.parameters[0].semantic_type == type && relay.definition.parameters[0].pointer_contract == PointerParameterContract.OWNED_TRANSFER);
	var returned = relay.body.statements[0] as CheckedOwnershipReturn;
	assert (returned != null && returned.transfer.source == relay.locals[0] && returned.transfer.semantic_type == type && relay.locals[0].incoming_parameter == relay.definition.parameters[0]);
	assert (relay.locals[0].is_generic_owner && relay.locals[0].is_owned && relay.locals[0].cleanup == null && relay.locals[0].object_storage == null);
	assert (keep.definition.type_parameters[1].transport_mode == GenericTransportMode.PLAIN_COPY && keep.definition.type_parameters[1].semantic_type.capability == GenericCapability.GEN1_PLAIN_COPY);
	assert (SemanticDump.format (p).contains ("(transport OWNABLE)") && SemanticDump.format (p).contains ("(requires #0 T Ownable)"));
	foreach (string capability in new string[] {"", "Eq", "Ordered", "Numeric", "Bitwise", "Shift"}) {
		var old = accept ("T id<T>(T value)" + (capability == "" ? "" : " where T : " + capability) + "{return value;}");
		assert (old.generic_functions[0].definition.type_parameters[0].transport_mode == GenericTransportMode.PLAIN_COPY);
		assert (old.generic_functions[0].definition.type_parameters[0].semantic_type.capability == GenericCapability.GEN1_PLAIN_COPY);
	}
	accept ("int Ownable(){return 1;} void f<Ownable>(owned Ownable v) where Ownable : Ownable {}");
}

private void matrices() {
	var types = new BuiltinTypes ();
	foreach (string name in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32", "f64", "void*", "int*", "int[]", "int[4]"}) {
		reject ("int tag<T>() where T : Ownable {return 1;} int main(){return tag<" + name + ">();}", "does not satisfy capability 'Ownable'");
		var type = types.resolve (name);
		if (type != null) {
			assert (!GenericCapabilityAuthority.satisfies (type, GenericCapabilityIdentity.OWNABLE));
		}
	}
	foreach (string element in new string[] {"bool", "i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		foreach (int lanes in new int[] {2, 4, 8, 16}) {
			var vector = types.vector_of (types.resolve (element), lanes);
			if (vector == null) {
				continue;
			}
			assert (!GenericCapabilityAuthority.satisfies (vector, GenericCapabilityIdentity.OWNABLE));
			reject ("int tag<T>() where T : Ownable {return 1;} int main(){return tag<" + vector.display_name () + ">();}", "does not satisfy capability 'Ownable'");
		}
	}
	foreach (string name in new string[] {"Resource", "Token", "Counter", "Plain", "Empty"}) {
		var p = accept ("class Counter {deinit(){}} class Plain {int x;} class Empty {} int tag<T>() where T : Ownable {return 1;} int main(){return tag<" + name + ">();}");
		var call = (CheckedGenericCall) ((CheckedReturnStatement) p.functions[0].body.statements[0]).expression;
		assert (GenericCapabilityAuthority.satisfies (call.type_arguments[0], GenericCapabilityIdentity.OWNABLE));
	}
	reject ("struct S {int x;} int tag<T>() where T : Ownable {return 1;} int main(){return tag<S>();}", "does not satisfy capability 'Ownable'");
	reject ("struct Box<U>{U value;} int tag<T>() where T : Ownable {return 1;} int main(){return tag<Box<int>>();}", "does not satisfy capability 'Ownable'");
	reject ("class Counter {} T id<T>(T v){return v;} int main(){id<Counter>(null);return 0;}", "GEN1_PLAIN_COPY");
}

private void positions() {
	reject ("void bad<T>(owned T v){}", "owned T requires explicit capability Ownable");
	reject ("owned T bad<T>(){return null;}", "owned T requires explicit capability Ownable");
	reject ("void bad<T>(owned T v) where T : Eq {}", "owned T requires explicit capability Ownable");
	reject ("T bad<T>(T v) where T : Ownable {return v;}", "plain T value transport");
	reject ("void bad<T>(T v) where T : Ownable {}", "plain T value transport");
	accept ("void good<T>(borrowed T v) where T : Ownable {}");
	reject ("void bad<T>(borrowed T a,borrowed T b) where T : Ownable {}", "generic borrowing requires one borrowed T");
	foreach (string capability in new string[] {"Eq", "Ordered", "Numeric", "Bitwise", "Shift"}) {
		reject ("void bad<T>(owned T v) where T : Ownable, " + capability + " {}", "Ownable cannot combine");
	}
	foreach (string expression in new string[] {"v", "null"}) {
		reject ("void bad<T>(owned T v) where T : Ownable {owned T local = " + expression + ";}", "generic owned locals");
	}
	accept ("void bad<T>(owned T v) where T : Ownable {owned T local = move v;owned T second = move local;}");
	reject ("void bad<T>(owned T v) where T : Ownable {T local = v;}", "plain Ownable T locals");
	reject ("struct Box<U>{U value;} void bad<T>(owned T v) where T : Ownable {Box<T> local = {value=v};}", "requires GEN1_PLAIN_COPY");
	reject (DROP + "void bad<T>(owned T v) where T : Ownable {drop<T>(v);}", "requires explicit 'move owner'");
	reject (DROP + "void bad<T>() where T : Ownable {drop<T>(null);}", "generic null construction");
	reject ("owned T bad<T>(owned T v) where T : Ownable {return v;}", "copying and generic null");
	foreach (string expression in new string[] {"v == null", "v == v", "v.field", "*v", "&v"}) {
		assert (check ("bool bad<T>(owned T v) where T : Ownable {return " + expression + ";}").diagnostic != null);
	}
}

private void flow() {
	reject (DROP + "void bad<T>(bool b,owned T v) where T : Ownable {drop<T>(move v); drop<T>(move v);}", "use of moved owned value");
	foreach (string body in new string[] {"if (b) {drop<T>(move v);} drop<T>(move v);", "while (b) {drop<T>(move v);}", "while (true) {drop<T>(move v); continue;}"}) {
		var result = check (DROP + "void bad<T>(bool b,owned T v) where T : Ownable {" + body + "}");
		assert (result.program == null && result.diagnostic != null);
		assert (result.diagnostic.message.contains ("owned value 'v'") && result.diagnostic.message.contains ("moved"));
	}
	reject (DROP + "owned T bad<T>(owned T v) where T : Ownable {drop<T>(move v);return move v;}", "use of moved owned value");
	reject ("void sink<T>(owned T a,owned T b) where T : Ownable {} void bad<T>(owned T v) where T : Ownable {sink<T>(move v,move v);}", "use of moved owned value");
	foreach (string body in new string[] {"if (b) {drop<T>(move v);}", "if (b) {drop<T>(move v);return;} drop<T>(move v);", "while (true) {drop<T>(move v);break;}", "while (b) {drop<T>(move v);return;}", "if (false) {drop<T>(move v);} drop<T>(move v);"}) {
		accept (DROP + "void good<T>(bool b,owned T v) where T : Ownable {" + body + "}");
	}
	reject ("owned T bad<T>(owned T v) where T : Ownable {}", "every normal return path");
}

private void forwarding() {
	accept (DROP + "void outer<T>(owned T v) where T : Ownable {drop<T>(move v);}");
	accept ("owned T relay<T>(owned T v) where T : Ownable {return move v;} owned T outer<T>(owned T v) where T : Ownable {return relay<T>(move v);}");
	foreach (string requirement in new string[] {"", " where T : Eq"}) {
		reject ("int tag<T>() where T : Ownable {return 1;} int bad<T>()" + requirement + "{return tag<T>();}", "does not satisfy capability 'Ownable'");
	}
	reject ("int tag<U>() {return 1;} int bad<T>() where T : Ownable {return tag<T>();}", "GEN1_PLAIN_COPY");
	reject (DROP + "owned T relay<T>(owned T v) where T : Ownable {return move v;} void bad<T>(owned T v) where T : Ownable {drop<T>(relay<T>(move v));}", "requires explicit 'move owner'");
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-own/semantic/identity-contract-transport-old-stability", contracts);
	Test.add_func ("/gen-own/semantic/central-concrete-matrix", matrices);
	Test.add_func ("/gen-own/semantic/positions-no-copy-locals-fields", positions);
	Test.add_func ("/gen-own/semantic/checked-once-unused-control-flow", flow);
	Test.add_func ("/gen-own/semantic/exact-forwarding-no-temporaries", forwarding);
	return Test.run ();
}

}
