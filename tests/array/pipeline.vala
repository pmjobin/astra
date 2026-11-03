// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Arrays {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check ("i16 f(int i){i16<4> v=splat(1,4);i16<4>[2] a={v,v};a[i]=insert(a[i],2,42);return a[i][2];}");
	var checked_witness = WeakRef (checked.functions[0]);
	var local_witness = WeakRef (checked.functions[0].locals[1]);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_witness.get () == null && local_witness.get () == null);
	CoreVerifier.verify (core);
	assert (core.functions[0].locals.length == 2 && !core.functions[0].locals[1].is_promotable ());
	var type = core.functions[0].locals[1].semantic_type as ArrayType;
	assert (type.length == 2 && type.element_type is VectorType);
	var core_witness = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_witness.get () == null);
	CfgVerifier.verify (cfg);
	assert (cfg.functions[0].locals.length == 2 && cfg.functions[0].locals[1].semantic_type == type && !cfg.functions[0].locals[1].is_promotable ());
	var cfg_witness = WeakRef (cfg.functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_witness.get () == null);
	SsaVerifier.verify (ssa);
	assert (ssa.functions[0].storage.length == 1 && ssa.functions[0].storage[0].semantic_type == type);
	int loads = 0;
	int stores = 0;
	int bounds = 0;
	int extracts = 0;
	foreach (var block in ssa.functions[0].blocks) {
		foreach (var instruction in block.instructions) {
			assert (instruction.result == null || !(instruction.result.semantic_type is ArrayType));
			if (instruction is SsaLoadInstruction) {
				loads++;
				assert (((SsaLoadInstruction) instruction).source is SsaArrayElementPlace && instruction.result.semantic_type == type.element_type);
			}
			if (instruction is SsaStoreInstruction) {
				stores++;
				assert (((SsaStoreInstruction) instruction).target is SsaArrayElementPlace && ((SsaStoreInstruction) instruction).value.semantic_type == type.element_type);
			}
			if (instruction is SsaArrayBoundsCheck) {
				bounds++;
			}
			if (instruction is SsaVectorExtractInstruction) {
				extracts++;
			}
		}
	}
	assert (loads == 2 && stores == 1 && bounds == 3 && extracts == 1);
	var witness = WeakRef (ssa.functions[0].storage[0]);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (witness.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
	assert (!NativeAbiDump.format (nabi).contains ("ARRAY"));
}

private void order() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check ("int index(){return 0;} int rhs(){return 42;} void f(){int[1] a={0};a[index()]=rhs();}")));
	var steps = cfg.functions[2].entry.instructions;
	int index = -1;
	int bounds = -1;
	int rhs = -1;
	int store = -1;
	for (int i = 0; i < steps.length; i++) {
		var call = steps[i] as CfgCallInstruction;
		if (call != null) {
			if (call.target.name == "index") {
				index = i;
			} else {
				rhs = i;
			}
		}
		if (steps[i] is CfgArrayBoundsCheck) {
			bounds = i;
		}
		if (steps[i] is CfgStore) {
			store = i;
		}
	}
	assert (index < bounds && bounds < rhs && rhs < store);
	foreach (string fixture in new string[] {"basic", "index", "bounds", "order", "loop", "f32", "vector", "dsp", "ownership"}) {
		SsaVerifier.verify (build (read (fixture)));
	}
	foreach (string body in new string[] {"bool f(owned Resource r){int[1] a={1};return (a[take(move r)]==1) & (r!=null);}", "void inspect(borrowed Resource r,int v){} void f(owned Resource r){int[1] a={1};inspect(r,a[take(move r)]);}"}) {
		var invalid = CfgBuilder.build (CoreBuilder.build (check ("int take(owned Resource r){return 0;}" + body)));
		assert (CfgFlowChecker.check (invalid).diagnostic.message.contains ("moved owned value 'r'"));
	}
	assert (NativeAbiBuilder.build (build (read ("basic"))).abi_version == NativeAbiVersion.SCALAR_V0);
	// A local vector array alone does not add a vector boundary channel.
	assert (NativeAbiBuilder.build (build ("int f(){i16<4> v=splat(1,4);i16<4>[1] a={v};return a[0][0] as int;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	var unsupported = Astra.Syntax.Parser.parse (new Astra.Source.SourceFile.from_text ("resource-array", "void f(){Resource[1] a={null};}"));
	var vapi = Astra.Vapi.VapiParser.parse (new Astra.Source.SourceFile.from_text ("resource.vapi", declarations ()));
	var result = SemanticAnalyzer.analyze (unsupported.unit, Astra.Vapi.VapiNormalizer.normalize (vapi.file), Astra.Vapi.VapiNormalizer.normalize_handles (vapi.file));
	assert (result.diagnostic.message.contains ("unsupported array element"));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/array/pipeline/lifetimes-storage-whole-vector-values", lifetime);
	add ("/array/pipeline/order-fixtures-and-abi", order);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
