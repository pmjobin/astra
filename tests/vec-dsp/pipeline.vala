// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.VectorDsp {
private class LifetimeWitness : Object {
	private WeakRef reference;
	internal LifetimeWitness (Object value) {
		reference = WeakRef (value);
	}

	internal bool gone() {
		return reference.get () == null;
	}

}

private const string STRAIGHT = "i8 a(i8 a,i8 b){return sat_add(a,b);} u32 b(u32 a,u32 b){return sat_sub(a,b);} i16<8> c(i16<8> a,i16<8> b){return sat_add(a,b);} u8<16> d(u8<16> a,u8<16> b){return sat_sub(a,b);} u16<8> e(i8<16> a){return widen_low(a,u16);} i16<8> f(u8<16> a){return widen_high(a,i16);} u8<16> g(i16<8> a,i16<8> b){return pack_wrap(a,b,u8);} i8<16> h(u16<8> a,u16<8> b){return pack_sat(a,b,i8);} f32<4> i(f32<4> a,f32<4> b){return interleave_low(a,b);} bool<8> j(bool<8> a,bool<8> b){return interleave_high(a,b);}";

private void stages() throws GLib.Error {
	CheckedProgram? checked = check (STRAIGHT);
	// One weak witness per primitive, with no retained stage references.
	var witnesses = new GenericArray<LifetimeWitness> ();
	foreach (var function in checked.functions) {
		witnesses.add (new LifetimeWitness (((CheckedReturnStatement) function.body.statements[0]).expression));
	}
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	foreach (var witness in witnesses) {
		assert (witness.gone ());
	}
	CoreVerifier.verify (core);
	witnesses = new GenericArray<LifetimeWitness> ();
	foreach (var function in core.functions) {
		var node = (CoreDspValue) ((CoreReturn) function.body.statements[0]).value;
		assert (node.source_type == node.first.semantic_type && node.span.text ().contains ("("));
		witnesses.add (new LifetimeWitness (node));
	}
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	foreach (var witness in witnesses) {
		assert (witness.gone ());
	}
	CfgVerifier.verify (cfg);
	witnesses = new GenericArray<LifetimeWitness> ();
	foreach (var function in cfg.functions) {
		assert (function.blocks.length == 1);
		int last = (int) function.entry.instructions.length - 1;
		assert (function.entry.instructions[last] is CfgDspInstruction);
		var dsp = (CfgDspValue) ((CfgEvaluateInstruction) function.entry.instructions[last]).value;
		assert (last == (dsp.primitive_kind.is_widen () ? 1 : 2));
		for (int i = 0; i < last; i++) {
			assert (((CfgEvaluateInstruction) function.entry.instructions[i]).value is CfgParameterValue);
		}
		assert (function.locals.length == 0 && function.temporaries.length == 0 && function.field_places.length == 0);
		witnesses.add (new LifetimeWitness (dsp));
	}
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	foreach (var witness in witnesses) {
		assert (witness.gone ());
	}
	SsaVerifier.verify (ssa);
	foreach (var function in ssa.functions) {
		assert (function.storage.length == 0 && function.blocks.length == 1 && function.entry.instructions.length == 1);
		var node = (SsaDspInstruction) function.entry.instructions[0];
		assert (node.first == function.parameters[0] && node.result.semantic_type == function.return_type);
		assert (node.primitive_kind.is_widen () ? node.second == null : node.second == function.parameters[1]);
	}
	assert (!SsaDump.format (ssa).contains ("vector-extract"));
	var source_type = WeakRef (((SsaDspInstruction) ssa.functions[4].entry.instructions[0]).source_type);
	var output_type = WeakRef (ssa.functions[4].return_type);
	ssa = null;
	assert (source_type.get () == null && output_type.get () == null);
}

private void order_and_profiles() throws GLib.Error {
	foreach (string expression in new string[] {"sat_add(a(),b())", "sat_sub(a(),b())", "pack_wrap(a(),b(),u8)", "pack_sat(a(),b(),u8)", "interleave_low(a(),b())", "interleave_high(a(),b())"}) {
		string result = expression.has_prefix ("pack") ? "u8<8>" : "i16<4>";
		string text = "i16<4> a(){return splat(1,4);} i16<4> b(){return splat(2,4);}" + result + " f(){return " + expression + ";}";
		var cfg = CfgBuilder.build (CoreBuilder.build (check (text)));
		var instructions = cfg.functions[2].entry.instructions;
		assert (instructions.length == 3 && ((CfgCallInstruction) instructions[0]).target.name == "a" && ((CfgCallInstruction) instructions[1]).target.name == "b" && instructions[2] is CfgDspInstruction);
		var ssa = SsaBuilder.build (cfg);
		assert (ssa.functions[2].entry.instructions.length == 3 && ssa.functions[2].entry.instructions[2] is SsaDspInstruction);
	}
	foreach (string op in new string[] {"widen_low", "widen_high"}) {
		var cfg = CfgBuilder.build (CoreBuilder.build (check ("i8<8> a(){return splat(-1,8);} i16<4> f(){return " + op + "(a(),i16);}")));
		assert (cfg.functions[1].entry.instructions.length == 2 && cfg.functions[1].entry.instructions[0] is CfgCallInstruction && cfg.functions[1].entry.instructions[1] is CfgDspInstruction);
	}
	string body = "i8<8> v=splat(-1,8);u16<4> w=widen_low(v,u16);i8<8> packed=pack_wrap(w,w,i8);";
	assert (NativeAbiBuilder.build (build ("int f(){" + body + "return packed[0] as int;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void* f(void* p){" + body + "return p;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("u8 f(){" + body + "return packed[0] as u8;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	assert (NativeAbiBuilder.build (build ("f32 f(){" + body + "return 1.0;}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	var vector = build (STRAIGHT);
	var nabi = NativeAbiBuilder.build (vector);
	assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4);
	CAbiVerifier.verify (CAbiBuilder.build (vector, nabi));
}

private void integration() throws GLib.Error {
	foreach (string name in new string[] {"sat-scalar", "sat-vector", "widen", "pack-wrap", "pack-sat", "interleave", "f32", "loop", "order", "ownership", "values"}) {
		var ssa = build (read (name));
		SsaVerifier.verify (ssa);
		if (name == "loop") {
			for (int f = 0; f < 4; f++) {
				int parameters = 0;
				foreach (var block in ssa.functions[f].blocks) {
					int vectors = 0;
					foreach (var parameter in block.parameters) {
						if (parameter.semantic_type is VectorType) {
							vectors++;
							parameters++;
						}
					}
					assert (vectors <= 1);
				}
				assert (parameters >= 1 && ssa.functions[f].storage.length == 0);
			}
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/dsp/pipeline/stage-lifetimes-one-operation", stages);
	add ("/dsp/pipeline/order-and-unchanged-profiles", order_and_profiles);
	add ("/dsp/pipeline/branch-loop-lanes-resource", integration);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
