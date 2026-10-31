// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Vapi;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.DataPointers {
private void stages() throws GLib.Error {
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		string one = name == "f32" ? "1.0" : "1";
		CheckedProgram? checked = check ("void write(%s* p){*p=%s;} %s f(){%s x=%s;%s* p=&x;write(p);return x;}".printf (name, one, name, name, one, name));
		var checked_witness = WeakRef (checked.functions[1]);
		var symbol_witness = WeakRef (checked.functions[1].locals[0]);
		var region_witness = WeakRef (checked.functions[1].body.region);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (checked_witness.get () == null && symbol_witness.get () == null && region_witness.get () == null);
		CoreVerifier.verify (core);
		assert (!core.functions[1].locals[0].is_promotable () && core.functions[1].locals[1].is_promotable ());
		assert (((CoreAddressOfValue) ((CoreInitialize) core.functions[1].body.statements[1]).value).provenance.origin_ordinal == 0);
		var core_witness = WeakRef (core.functions[1]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_witness.get () == null);
		CfgVerifier.verify (cfg);
		assert (!cfg.functions[1].locals[0].is_promotable () && cfg.functions[1].locals[1].is_promotable ());
		var cfg_witness = WeakRef (cfg.functions[1]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_witness.get () == null);
		SsaVerifier.verify (ssa);
		assert (ssa.functions[1].storage.length == 1 && ssa.functions[1].storage[0].semantic_type == ssa.functions[1].return_type);
		assert (ssa.functions[1].entry.instructions[0] is SsaInitializeInstruction);
		assert (ssa.functions[1].entry.instructions[1] is SsaAddressOfInstruction);
		assert (ssa.functions[1].entry.instructions[2] is SsaCallInstruction);
		assert (ssa.functions[1].entry.instructions[3] is SsaLoadInstruction);
		var provenance = ((SsaAddressOfInstruction) ssa.functions[1].entry.instructions[1]).provenance;
		assert (provenance.is_valid () && provenance.origin_ordinal == 0);
		var storage_witness = WeakRef (ssa.functions[1].storage[0]);
		var type_witness = WeakRef (ssa.functions[0].parameters[0].semantic_type);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		assert (storage_witness.get () == null && type_witness.get () == null);
		NativeAbiVerifier.verify (nabi);
		CAbiVerifier.verify (cabi);
	}
}

private void promotion() throws GLib.Error {
	string text = "int f(bool condition){int x=1;int y=2;int* p=&x;int* q=null;while(condition){*p=*p+1;y=y+1;q=p;}return x+y;}";
	var ssa = build (text);
	assert (ssa.functions[0].storage.length == 1 && ssa.functions[0].storage[0].source_local_ordinal == 0);
	int promoted_y = 0;
	int promoted_q = 0;
	int loads = 0;
	int stores = 0;
	foreach (var block in ssa.functions[0].blocks) {
		foreach (var parameter in block.parameters) {
			assert (parameter.origin_kind == SsaPromotionOrigin.TEMPORARY || parameter.source_local_ordinal != 0);
			if (parameter.name == "y") {
				promoted_y++;
			}
			if (parameter.name == "q") {
				assert (parameter.semantic_type is TypedPointerType);
				promoted_q++;
			}
		}
		foreach (var instruction in block.instructions) {
			if (instruction is SsaLoadInstruction) {
				loads++;
			}
			if (instruction is SsaStoreInstruction) {
				stores++;
			}
		}
	}
	assert (promoted_y > 0 && promoted_q > 0 && loads == 2 && stores == 1);
	assert (build ("int f(bool c){int x=1;if(c){x=2;}return x;}").functions[0].storage.length == 0);
	var late = build ("int f(bool c){int x=1;if(c){x=2;}return *(&x);}");
	assert (late.functions[0].storage.length == 1 && late.functions[0].entry.instructions[0] is SsaInitializeInstruction);
	var unreachable = build ("int f(){int x=1;return x;int* p=&x;}");
	assert (unreachable.functions[0].storage.length == 1 && unreachable.functions[0].entry.instructions[0] is SsaInitializeInstruction);
}

private void order() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check ("int effect(){return 1;} void f(int* p){*p=effect();}")));
	var instructions = cfg.functions[1].entry.instructions;
	assert (instructions.length == 3 && instructions[0] is CfgEvaluateInstruction && instructions[1] is CfgCallInstruction && instructions[2] is CfgStore);
	assert (((CfgDereferencePlace) ((CfgStore) instructions[2]).target).pointer == ((CfgEvaluateInstruction) instructions[0]).result);
	foreach (string fixture in new string[] {"basic", "alias", "call", "null", "f32", "loop", "borrow", "integration", "ownership", "widths"}) {
		SsaVerifier.verify (build (read (fixture)));
	}
}

private void foreign_rejections() throws GLib.Error {
	foreach (string type in new string[] {"i8*", "u16*", "int*", "f32*", "Pair*"}) {
		var vapi = VapiParser.parse (new SourceFile.from_text ("bad.vapi", "void f(" + type + " p);"));
		assert (vapi.file != null);
		var syntax = Parser.parse (new SourceFile.from_text ("empty.astra", ""));
		var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file));
		assert (result.program == null && result.diagnostic.message == "unsupported foreign pointer type; C/VAPI supports only 'void*'");
	}
	foreach (string text in new string[] {"void f(Resource* p){}", "void f(){Resource r=lookup_resource();void* p=&r;}"}) {
		var syntax = Parser.parse (new SourceFile.from_text ("resource.astra", text));
		var vapi = VapiParser.parse (new SourceFile.from_text ("resource.vapi", declarations ()));
		var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
		assert (result.program == null && result.diagnostic != null);
	}
}

private void profiles() throws GLib.Error {
	foreach (string type in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		assert (NativeAbiBuilder.build (build ("void f(" + type + "* p){}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
		var nabi = NativeAbiBuilder.build (build (type + " f(" + type + "* p){return *p;}"));
		assert (nabi.abi_version == (type == "f32" ? NativeAbiVersion.SCALAR_FP_V3 : type == "int" ? NativeAbiVersion.SCALAR_PTR_V1 : NativeAbiVersion.SCALAR_INT_V2));
	}
	assert (NativeAbiBuilder.build (build ("int main(){int x=1;int* p=&x;*p=2;return x;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build (read ("integration"))).abi_version == NativeAbiVersion.VECTOR_V4);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/dptr/pipeline/stage-lifetimes-exact-types-and-provenance", stages);
	add ("/dptr/pipeline/promotion-memory-and-no-stale-local", promotion);
	add ("/dptr/pipeline/base-first-order-and-fixtures", order);
	add ("/dptr/pipeline/cabi-vapi-and-resource-deferrals", foreign_rejections);
	add ("/dptr/pipeline/existing-profile-selection", profiles);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
