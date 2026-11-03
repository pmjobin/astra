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

namespace Astra.Tests.VectorMemory {
private void stages() throws GLib.Error {
	foreach (string name in new string[] {"i8<16>", "u8<16>", "i16<8>", "u16<8>", "int<4>", "u32<4>", "f32<4>"}) {
		string count = name.substring (name.index_of ("<") + 1).replace (">", "");
		string one = name.has_prefix ("f32") ? "1.0" : "1";
		CheckedProgram? checked = check ("void write(%s* p){*p=splat(%s,%s);} %s f(){%s x=splat(%s,%s);%s* p=&x;write(p);return x;}".printf (name, one, count, name, name, one, count, name));
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
		int initializes = 0;
		int loads = 0;
		foreach (var instruction in ssa.functions[1].entry.instructions) {
			if (instruction is SsaInitializeInstruction) {
				initializes++;
			}
			if (instruction is SsaLoadInstruction) {
				loads++;
				assert (instruction.result.semantic_type is VectorType);
			}
		}
		assert (initializes == 1 && loads == 1);
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
	var ssa = build ("f32<4> f(bool condition){f32<4> x=splat(1.0,4);f32<4> y=splat(2.0,4);f32<4>* p=&x;f32<4>* q=null;while(condition){*p=*p+y;y=y+y;q=p;}return x+y;}");
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
				assert (parameter.semantic_type is VectorType);
			}
			if (parameter.name == "q") {
				promoted_q++;
				assert (parameter.semantic_type is TypedPointerType);
			}
		}
		foreach (var instruction in block.instructions) {
			if (instruction is SsaLoadInstruction) {
				loads++;
				assert (instruction.result.semantic_type is VectorType);
			}
			if (instruction is SsaStoreInstruction) {
				stores++;
				assert (((SsaStoreInstruction) instruction).value.semantic_type is VectorType);
			}
		}
	}
	assert (promoted_y > 0 && promoted_q > 0 && loads == 2 && stores == 1);
	assert (build ("f32<4> f(bool c){f32<4> x=splat(1.0,4);if(c){x=splat(2.0,4);}return x;}").functions[0].storage.length == 0);
	assert (build ("f32<4> f(bool c){f32<4> x=splat(1.0,4);if(c){x=splat(2.0,4);}return *(&x);}").functions[0].storage.length == 1);
	assert (build ("f32<4> f(){f32<4> x=splat(1.0,4);return x;f32<4>* p=&x;}").functions[0].storage.length == 1);
}

private void composition() throws GLib.Error {
	var core = CoreBuilder.build (check ("i16 f(i16<8>* p){return (*p)[2];}"));
	var extract = (CoreVectorExtractValue) ((CoreReturn) core.functions[0].body.statements[0]).value;
	assert (extract.vector is CoreLoadValue && ((CoreLoadValue) extract.vector).source is CoreDereferencePlace);
	var cfg = CfgBuilder.build (core);
	assert (CfgDump.format (cfg).contains ("dereference-place") && CfgDump.format (cfg).contains ("vector-extract"));
	var ssa = SsaBuilder.build (cfg);
	var instructions = ssa.functions[0].entry.instructions;
	assert (instructions.length == 2 && instructions[0] is SsaLoadInstruction && instructions[1] is SsaVectorExtractInstruction);
	assert (((SsaLoadInstruction) instructions[0]).source is SsaDereferencePlace);
	assert (instructions[0].result.semantic_type is VectorType && ((SsaVectorExtractInstruction) instructions[1]).vector == instructions[0].result);
	var order = CfgBuilder.build (CoreBuilder.build (check ("i16<8> effect(){return splat(1,8);} void f(i16<8>* p){*p=effect();}")));
	var steps = order.functions[1].entry.instructions;
	assert (steps.length == 3 && steps[0] is CfgEvaluateInstruction && steps[1] is CfgCallInstruction && steps[2] is CfgStore);
	assert (((CfgDereferencePlace) ((CfgStore) steps[2]).target).pointer == ((CfgEvaluateInstruction) steps[0]).result);
	foreach (string fixture in new string[] {"basic", "alias", "call", "null", "f32", "loop", "borrow", "lanes", "dsp", "dot", "ownership", "widths"}) {
		SsaVerifier.verify (build (read (fixture)));
	}
}

private void profiles() throws GLib.Error {
	var t = new BuiltinTypes ();
	foreach (string name in new string[] {"i8", "u8", "i16", "u16", "int", "u32", "f32"}) {
		for (int n = 2; n <= 16; n *= 2) {
			var v = t.vector_of (t.resolve (name), n);
			if (v == null) {
				continue;
			}
			string type = v.display_name ();
			var pointer = NativeAbiBuilder.build (build ("void f(" + type + "* p){*p=*p;}"));
			assert (pointer.abi_version == NativeAbiVersion.SCALAR_PTR_V1);
			assert (NativeAbiDump.format (pointer).contains ("(parameter #0 PTR)") && !NativeAbiDump.format (pointer).contains ("VECTOR("));
			assert (NativeAbiBuilder.build (build ("void f(" + type + "* p," + type + " value){*p=value;}")).abi_version == NativeAbiVersion.VECTOR_V4);
		}
	}
	assert (NativeAbiBuilder.build (build (read ("basic"))).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("int main(){i16<8> v=splat(1,8);i16<8>* p=&v;*p=splat(2,8);return 0;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	// VAPI's existing foreign grammar still has no shaped-pointer syntax.
	var vapi = VapiParser.parse (new SourceFile.from_text ("unsupported.vapi", "void f(f32<4>* p);"));
	assert (vapi.file == null && vapi.diagnostic != null);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/vecmem/pipeline/stage-lifetimes-exact-types-provenance", stages);
	add ("/vecmem/pipeline/addressability-promotion-no-stale-vector", promotion);
	add ("/vecmem/pipeline/one-vector-load-extract-store-order-fixtures", composition);
	add ("/vecmem/pipeline/ptr-and-mixed-profile-selection-vapi-deferral", profiles);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
