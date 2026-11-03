// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.VectorLanes {
private const string STRAIGHT = "i16<4> f(i16 x,bool<4> m){i16<4> v=splat(x,4);i16 y=v[002];v=insert(v,01,y);v=shuffle(v,3,2,1,0);return select(m,v,v);}";

private void stages() throws GLib.Error {
	CheckedProgram? checked = check (STRAIGHT);
	var checked_ref = WeakRef (checked.functions[0]);
	var checked_shuffle = (CheckedVectorShuffleExpression) ((CheckedAssignment) checked.functions[0].body.statements[3]).expression;
	var checked_selectors = WeakRef (checked_shuffle.selectors);
	var checked_index = WeakRef (checked_shuffle.selectors.at (0));
	CoreProgram? core = CoreBuilder.build (checked);
	var core_shuffle = (CoreVectorShuffleValue) ((CoreStore) core.functions[0].body.statements[3]).value;
	assert (core_shuffle.selectors != checked_shuffle.selectors && core_shuffle.selectors.at (0) != checked_shuffle.selectors.at (0));
	checked_shuffle = null;
	checked = null;
	assert (checked_ref.get () == null && checked_selectors.get () == null && checked_index.get () == null);
	CoreVerifier.verify (core);
	assert (core.functions[0].locals.length == 2 && core.functions[0].locals[0].is_promotable ());
	var core_ref = WeakRef (core.functions[0]);
	var core_selectors = WeakRef (core_shuffle.selectors);
	core_shuffle = null;
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_selectors.get () == null);
	CfgVerifier.verify (cfg);
	assert (cfg.functions[0].blocks.length == 1 && cfg.functions[0].temporaries.length == 0 && cfg.functions[0].field_places.length == 0);
	WeakRef cfg_selectors = WeakRef (null);
	int primitives = 0;
	foreach (var instruction in cfg.functions[0].entry.instructions) {
		if (instruction is CfgVectorSplatInstruction || instruction is CfgVectorExtractInstruction || instruction is CfgVectorInsertInstruction || instruction is CfgVectorShuffleInstruction || instruction is CfgVectorSelectInstruction) {
			primitives++;
		}
		if (instruction is CfgVectorShuffleInstruction) {
			cfg_selectors = WeakRef (((CfgVectorShuffleValue) ((CfgEvaluateInstruction) instruction).value).selectors);
		}
	}
	assert (primitives == 5);
	var cfg_ref = WeakRef (cfg.functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_selectors.get () == null);
	SsaVerifier.verify (ssa);
	var function = ssa.functions[0];
	assert (function.storage.length == 0 && function.blocks.length == 1 && function.entry.instructions.length == 5);
	assert (function.entry.instructions[0] is SsaVectorSplatInstruction && function.entry.instructions[1] is SsaVectorExtractInstruction && function.entry.instructions[2] is SsaVectorInsertInstruction && function.entry.instructions[3] is SsaVectorShuffleInstruction && function.entry.instructions[4] is SsaVectorSelectInstruction);
	assert (((SsaVectorExtractInstruction) function.entry.instructions[1]).index.span.text () == "002");
	assert (((SsaVectorInsertInstruction) function.entry.instructions[2]).index.span.text () == "01");
	var shuffle = (SsaVectorShuffleInstruction) function.entry.instructions[3];
	assert (shuffle.selectors.spelling () == "3 2 1 0" && shuffle.selectors.at (0).span.text () == "3");
	var selectors_ref = WeakRef (shuffle.selectors);
	var type_ref = WeakRef (shuffle.result.semantic_type);
	shuffle = null;
	function = null;
	ssa = null;
	assert (selectors_ref.get () == null && type_ref.get () == null);
}

private void order_and_profiles() throws GLib.Error {
	string source = "bool<4> m(){return splat(true,4);} int<4> a(){return splat(1,4);} int<4> b(){return splat(2,4);} int<4> f(){return select(m(),a(),b());}";
	var ssa = build (source);
	var function = ssa.functions[3];
	assert (function.blocks.length == 1 && function.entry.instructions.length == 4);
	for (int i = 0; i < 3; i++) {
		assert (((SsaCallInstruction) function.entry.instructions[i]).target == ssa.functions[i]);
	}
	assert (function.entry.instructions[3] is SsaVectorSelectInstruction);
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4);
	CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
	string body = "int<4> a=splat(1,4);int<4> b=shuffle(a,3,2,1,0);int<4> c=select(splat(true,4),a,b);";
	assert (NativeAbiBuilder.build (build ("int f(){" + body + "return c[0];}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("u8 f(){" + body + "return 1;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	assert (NativeAbiBuilder.build (build ("f32 f(){" + body + "return 1.0;}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	bool rejected = false;
	try {
		CAbiTypeMapper.map_scalar (ssa.functions[3].return_type);
	} catch (CAbiError error) {
		rejected = true;
	}
	assert (rejected);
}

private void integration() throws GLib.Error {
	foreach (string name in new string[] {"splat", "extract", "insert", "shuffle", "select", "lane-f32", "lane-loop", "lane-ownership"}) {
		var ssa = build (read (name));
		SsaVerifier.verify (ssa);
		foreach (var function in ssa.functions) {
			assert (function.storage.length == 0 || name == "splat" || name == "extract" || name == "insert" || name == "shuffle" || name == "select");
		}
		if (name == "lane-loop") {
			int vector_parameters = 0;
			foreach (var block in ssa.functions[0].blocks) {
				foreach (var parameter in block.parameters) {
					if (parameter.semantic_type is VectorType) {
						vector_parameters++;
					}
				}
			}
			assert (vector_parameters >= 3 && ssa.functions[0].storage.length == 0);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/vec-lane/pipeline/independent-stage-lifetimes-and-whole-values", stages);
	add ("/vec-lane/pipeline/eager-order-and-unchanged-abi", order_and_profiles);
	add ("/vec-lane/pipeline/loops-branches-native-resource", integration);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
