// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Properties {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check (read ("recursive"));
	var symbol = WeakRef (checked.classes[0].properties[0]);
	var getter = WeakRef (checked.classes[0].properties[0].getter);
	var receiver = WeakRef (checked.classes[0].properties[0].getter.receiver);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (symbol.get () == null && getter.get () == null && receiver.get () == null);
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("property-get"));
	var cp = WeakRef (core.classes[0].properties[0]);
	var cg = WeakRef (core.classes[0].properties[0].getter);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (cp.get () == null && cg.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgDump.format (cfg).contains ("property-get"));
	var gp = WeakRef (cfg.classes[0].properties[0]);
	var gg = WeakRef (cfg.classes[0].properties[0].getter);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (gp.get () == null && gg.get () == null);
	SsaVerifier.verify (ssa);
	assert (SsaDump.format (ssa).contains ("property-get"));
	var sp = WeakRef (ssa.classes[0].properties[0]);
	var sg = WeakRef (ssa.classes[0].properties[0].getter);
	var type = WeakRef (ssa.classes[0].semantic_type);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (sp.get () == null && sg.get () == null && type.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
}
private void storage() throws GLib.Error {
	var ssa = build (read ("struct"));
	assert (ssa.functions[0].storage.length == 1 && ssa.functions[0].storage[0].name == "b");
	assert (ssa.structs[0].fields.length == 1 && ssa.structs[0].properties.length == 1);
	ssa = build ("struct S{int raw;property int value{get{return this.raw;}}}int main(){S a={raw=42};return a.raw;}");
	assert (ssa.functions[0].storage.length == 0);
	assert (ssa.structs[0].properties[0].getter.storage.length == 0);
}
private void order() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check (read ("null-set"))));
	var events = new StringBuilder ();
	foreach (var instruction in cfg.functions[0].entry.instructions) {
		var evaluation = instruction as CfgEvaluateInstruction;
		if (evaluation != null && evaluation.value is CfgObjectValidateValue) {
			events.append ("guard ");
		}
		if (instruction is CfgCCallInstruction) {
			events.append ("rhs ");
		}
		var call = instruction as CfgCallInstruction;
		if (call != null && call.target is CfgPropertySetter) {
			events.append ("setter ");
			assert (call.arguments.length == 1 && call.receiver.semantic_type is ReceiverType);
		}
	}
	assert (events.str == "guard rhs setter ");
}
private void profiles() throws GLib.Error {
	foreach (string name in new string[] {"basic", "readonly", "effect", "alias", "struct", "method", "life", "constructor", "owned", "result", "bool", "f32", "f64", "vector", "pointer"}) {
		var ssa = build (read (name));
		var abi = NativeAbiBuilder.build (ssa);
		CAbiVerifier.verify (CAbiBuilder.build (ssa, abi));
		foreach (var function in ssa.functions) {
			var accessor = function as SsaPropertyAccessor;
			if (accessor == null) {
				continue;
			}
			var physical = abi.functions[function.ordinal];
			assert (physical.property_ordinal == accessor.property_member.ordinal && physical.method_ordinal == -1);
			assert (physical.signature.receiver.scalar_type == NativeScalarType.PTR && physical.signature.physical_parameter_count == ((function is SsaPropertyGetter) ? 1 : 2));
		}
		if (name == "f64") {
			assert (abi.abi_version == NativeAbiVersion.FP64_V6);
		}
		if (name == "f32") {
			assert (abi.abi_version == NativeAbiVersion.SCALAR_FP_V3);
		}
		if (name == "vector") {
			assert (abi.abi_version == NativeAbiVersion.VECTOR_V4);
		}
	}
	var mixed = build (read ("vector") + "class D{property f64 value{get{return 1.25;}}}");
	assert (NativeAbiBuilder.build (mixed).abi_version == NativeAbiVersion.FP64_V6);
}
private void negatives() throws GLib.Error {
	foreach (string operation in new string[] {"int x=c.value;", "c.value=42;"}) {
		string text = "class C{int raw;init(){this.raw=0;}property int value{get{return this.raw;}set(int next){this.raw=next;}}}void consume(owned C c){}void f(){owned C c=C.init();consume(move c);" + operation + "}";
		bool rejected = false;
		try {
			build (text);
		} catch (GLib.Error error) {
			rejected = error.message.contains ("owned") || error.message.contains ("owner");
		}
		assert (rejected);
	}
	bool fallthrough = false;
	try {
		build ("class C{property int value{get{}}}");
	} catch (GLib.Error error) {
		fallthrough = error.message.contains ("fall") || error.message.contains ("return");
	}
	assert (fallthrough);
	var parsed = Parser.parse (new SourceFile.from_text ("handle-property", "class C{property Resource value{get{return null;}}}"));
	string bindings;
	FileUtils.get_contents ("tests/obj-life/fixtures/lifecycle.vapi", out bindings);
	var vapi = Astra.Vapi.VapiParser.parse (new SourceFile.from_text ("lifecycle.vapi", bindings));
	var result = SemanticAnalyzer.analyze (parsed.unit, Astra.Vapi.VapiNormalizer.normalize (vapi.file), Astra.Vapi.VapiNormalizer.normalize_handles (vapi.file));
	assert (result.diagnostic != null && result.diagnostic.message.contains ("unsupported property value type 'Resource'"));
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/prop/pipeline/stage-lifetimes-and-exact-identity", lifetime);
	add ("/prop/pipeline/selective-storage", storage);
	add ("/prop/pipeline/null-guard-before-rhs-before-setter", order);
	add ("/prop/pipeline/integrations-and-profiles", profiles);
	add ("/prop/pipeline/moved-owner-fallthrough-handle-diagnostics", negatives);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
