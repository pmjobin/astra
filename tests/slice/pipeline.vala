// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Slices {
private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check ("i16 f(int i){i16<8> v=splat(1,8);i16<8>[2] a={v,v};i16<8>[] s=slice(a,0,2);s[i]=insert(s[i],2,42);return s[i][2];}");
	var checked_witness = WeakRef (checked.functions[0]);
	var local_witness = WeakRef (checked.functions[0].locals[1]);
	var region_witness = WeakRef (checked.functions[0].locals[1].lexical_region);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_witness.get () == null && local_witness.get () == null && region_witness.get () == null);
	CoreVerifier.verify (core);
	assert (core.functions[0].locals.length == 3 && !core.functions[0].locals[1].is_promotable () && core.functions[0].locals[2].is_promotable ());
	var type = core.functions[0].locals[2].semantic_type as SliceType;
	assert (type.element_type is VectorType);
	assert (((CoreInitialize) core.functions[0].body.statements[2]).value is CoreSliceFromArrayValue);
	var core_witness = WeakRef (core.functions[0]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_witness.get () == null);
	CfgVerifier.verify (cfg);
	assert (cfg.functions[0].locals.length == 3 && cfg.functions[0].locals[2].semantic_type == type && cfg.functions[0].locals[2].is_promotable ());
	var cfg_witness = WeakRef (cfg.functions[0]);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_witness.get () == null);
	SsaVerifier.verify (ssa);
	assert (ssa.functions[0].storage.length == 1 && ssa.functions[0].storage[0].semantic_type is ArrayType);
	int loads = 0;
	int stores = 0;
	int bounds = 0;
	int extracts = 0;
	int slices = 0;
	foreach (var block in ssa.functions[0].blocks) {
		foreach (var instruction in block.instructions) {
			assert (instruction.result == null || !(instruction.result.semantic_type is ArrayType) && !(instruction.result.semantic_type is StructType));
			if (instruction is SsaSliceConstructInstruction) {
				slices++;
				assert (instruction.result.semantic_type == type);
			}
			if (instruction is SsaLoadInstruction) {
				loads++;
				assert (((SsaLoadInstruction) instruction).source is SsaSliceElementPlace && instruction.result.semantic_type == type.element_type);
			}
			if (instruction is SsaStoreInstruction) {
				stores++;
				assert (((SsaStoreInstruction) instruction).target is SsaSliceElementPlace && ((SsaStoreInstruction) instruction).value.semantic_type == type.element_type);
			}
			if (instruction is SsaSliceBoundsCheck) {
				bounds++;
			}
			if (instruction is SsaVectorExtractInstruction) {
				extracts++;
			}
		}
	}
	assert (slices == 1 && loads == 2 && stores == 1 && bounds == 3 && extracts == 1);
	var witness = WeakRef (ssa.functions[0].storage[0]);
	var nabi = NativeAbiBuilder.build (ssa);
	var cabi = CAbiBuilder.build (ssa, nabi);
	ssa = null;
	assert (witness.get () == null);
	NativeAbiVerifier.verify (nabi);
	CAbiVerifier.verify (cabi);
}

private void order() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check ("int start(){return 0;} int count(){return 1;} int index(){return 0;} int rhs(){return 42;} void f(){int[1] a={0};slice(a,start(),count())[index()]=rhs();}")));
	var steps = cfg.functions[4].entry.instructions;
	var events = new StringBuilder ();
	CfgValue? constructed = null;
	CfgValue? captured = null;
	foreach (var step in steps) {
		var call = step as CfgCallInstruction;
		if (call != null) {
			events.append (call.target.name + " ");
		}
		var evaluation = step as CfgEvaluateInstruction;
		if (evaluation != null && evaluation.value is CfgSliceFromArrayValue) {
			events.append ("construct ");
			constructed = evaluation.result;
		}
		var bounds = step as CfgSliceBoundsCheck;
		if (bounds != null) {
			events.append ("bounds ");
			captured = bounds.slice;
			assert (captured == constructed);
		}
		var store = step as CfgStore;
		if (store != null) {
			events.append ("store ");
			assert (((CfgSliceElementPlace) store.target).slice == captured);
		}
	}
	assert (events.str == "start count construct index bounds rhs store ");
	foreach (string fixture in new string[] {"basic", "subrange", "empty", "len", "alias", "branch", "loop", "bounds", "order", "f32", "vector", "dsp", "ownership"}) {
		SsaVerifier.verify (build (read (fixture)));
	}
	foreach (string body in new string[] {"bool f(owned Resource r){int[1] a={1};int[] s=slice(a);return (s[take(move r)]==1) & (r!=null);}", "void inspect(borrowed Resource r,int v){} void f(owned Resource r){int[1] a={1};inspect(r,slice(a)[take(move r)]);}"}) {
		var invalid = CfgBuilder.build (CoreBuilder.build (check ("int take(owned Resource r){return 0;}" + body)));
		assert (CfgFlowChecker.check (invalid).diagnostic.message.contains ("moved owned value 'r'"));
	}
}

private void merges_and_abi() throws GLib.Error {
	foreach (string fixture in new string[] {"branch", "loop"}) {
		var ssa = build (read (fixture));
		int slices = 0;
		int merged = 0;
		foreach (var block in ssa.functions[0].blocks) {
			foreach (var parameter in block.parameters) {
				if (parameter.semantic_type is SliceType) {
					merged++;
				}
			}
			foreach (var instruction in block.instructions) {
				if (instruction is SsaSliceConstructInstruction) {
					slices++;
				}
			}
		}
		assert (slices >= 2 && merged >= 1);
		assert (ssa.functions[0].storage.length == 2);
		assert (NativeAbiBuilder.build (ssa).abi_version == NativeAbiVersion.SCALAR_V0);
		string dump = SsaDump.format (ssa);
		assert (dump.contains (" : int[]") && !dump.contains (".ptr") && !dump.contains (".length"));
	}
	assert (NativeAbiBuilder.build (build ("int f(){i16<8> v=splat(1,8);i16<8>[1] a={v};i16<8>[] s=slice(a);return s[0][0] as int;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	bool rejected = false;
	var t = new BuiltinTypes ();
	try {
		NativeTypeMapper.map_type (t.slice_of (t.int_type));
	} catch (NativeAbiError error) {
		rejected = true;
	}
	assert (rejected);
	var unsupported = Astra.Syntax.Parser.parse (new Astra.Source.SourceFile.from_text ("resource-slice", "void f(){Resource[] a=null;}"));
	var vapi = Astra.Vapi.VapiParser.parse (new Astra.Source.SourceFile.from_text ("resource.vapi", declarations ()));
	var result = SemanticAnalyzer.analyze (unsupported.unit, Astra.Vapi.VapiNormalizer.normalize (vapi.file), Astra.Vapi.VapiNormalizer.normalize_handles (vapi.file));
	assert (result.diagnostic.message.contains ("unsupported slice element"));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/slice/pipeline/lifetimes-and-whole-vector-places", lifetime);
	add ("/slice/pipeline/order-fixtures-and-ownership", order);
	add ("/slice/pipeline/one-value-merges-and-abi-guards", merges_and_abi);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
