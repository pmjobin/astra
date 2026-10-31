// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.VectorDot {
private class LifetimeWitness : Object {
	private WeakRef reference;
	internal LifetimeWitness (Object value) {
		reference = WeakRef (value);
	}
	internal bool gone() {
		return reference.get () == null;
	}
}

private const string STRAIGHT = "u16 f(i8<16> a,i8<16> b){return dot_wrap(a,b,u16);} i32 g(i32 c,u8<16> a,u8<16> b){return mac_wrap(c,a,b);} f32 h(f32<4> a,f32<4> b){return dot(a,b);} f32 i(f32 c,f32<2> a,f32<2> b){return mac(c,a,b);}";

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
		var node = (CoreVectorDotValue) ((CoreReturn) function.body.statements[0]).value;
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
		assert (function.entry.instructions[last] is CfgVectorDotInstruction);
		var dot = (CfgVectorDotValue) ((CfgEvaluateInstruction) function.entry.instructions[last]).value;
		assert (last == (dot.dot_kind.is_mac () ? 3 : 2));
		for (int i = 0; i < last; i++) {
			assert (((CfgEvaluateInstruction) function.entry.instructions[i]).value is CfgParameterValue);
		}
		assert (function.locals.length == 0 && function.temporaries.length == 0 && function.field_places.length == 0);
		witnesses.add (new LifetimeWitness (dot));
	}
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	foreach (var witness in witnesses) {
		assert (witness.gone ());
	}
	SsaVerifier.verify (ssa);
	foreach (var function in ssa.functions) {
		assert (function.storage.length == 0 && function.blocks.length == 1 && function.entry.instructions.length == 1);
		var node = (SsaVectorDotInstruction) function.entry.instructions[0];
		assert (node.first == function.parameters[node.dot_kind.is_mac () ? 1 : 0] && node.result.semantic_type == function.return_type);
		assert (node.second == function.parameters[node.dot_kind.is_mac () ? 2 : 1]);
		assert (node.dot_kind.is_mac () ? node.accumulator == function.parameters[0] : node.accumulator == null);
	}
	assert (!SsaDump.format (ssa).contains ("vector-extract"));
	var source_type = WeakRef (((SsaVectorDotInstruction) ssa.functions[0].entry.instructions[0]).source_type);
	var output_type = WeakRef (ssa.functions[0].return_type);
	ssa = null;
	assert (source_type.get () == null && output_type.get () == null);
}

private void order_and_profiles() throws GLib.Error {
	foreach (string op in new string[] {"dot_wrap", "mac_wrap", "dot", "mac"}) {
		bool integer = op.has_suffix ("wrap");
		bool mac = op.has_prefix ("mac");
		string element = integer ? "i16" : "f32";
		string result = integer ? "int" : "f32";
		string literal = integer ? "1" : "1.0";
		string text = "%s c(){return %s;} %s<4> a(){return splat(%s,4);} %s<4> b(){return splat(%s,4);} %s f(){return %s(%sa(),b()%s);}".printf (result, literal, element, literal, element, literal, result, op, mac ? "c()," : "", integer && !mac ? ",int" : "");
		var cfg = CfgBuilder.build (CoreBuilder.build (check (text)));
		var instructions = cfg.functions[3].entry.instructions;
		int offset = mac ? 1 : 0;
		assert (instructions.length == 3 + offset);
		if (mac) {
			assert (((CfgCallInstruction) instructions[0]).target.name == "c");
		}
		assert (((CfgCallInstruction) instructions[offset]).target.name == "a" && ((CfgCallInstruction) instructions[offset + 1]).target.name == "b" && instructions[offset + 2] is CfgVectorDotInstruction);
		var ssa = SsaBuilder.build (cfg);
		assert (ssa.functions[3].entry.instructions.length == 3 + offset && ssa.functions[3].entry.instructions[offset + 2] is SsaVectorDotInstruction);
	}
	string body = "i8<16> a=splat(1,16);int d=dot_wrap(a,a,int);";
	assert (NativeAbiBuilder.build (build ("int f(){" + body + "return d;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void* f(void* p){" + body + "return p;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("u8 f(){" + body + "return d as u8;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	assert (NativeAbiBuilder.build (build ("f32 f(){" + body + "return dot(splat(1.0,4),splat(1.0,4));}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	var vector = build (STRAIGHT);
	var nabi = NativeAbiBuilder.build (vector);
	assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4);
	CAbiVerifier.verify (CAbiBuilder.build (vector, nabi));
	var checked = check (STRAIGHT);
	assert (checked.types.vector_of (checked.types.i32_type, 16) == null);
}

private void integration() throws GLib.Error {
	foreach (string name in new string[] {"int-basic", "int-signedness", "int-wrap", "int-mac", "f32-basic", "f32-order", "f32-mac", "f32-special", "loop", "native", "order", "ownership", "values"}) {
		var ssa = build (read (name));
		SsaVerifier.verify (ssa);
		if (name == "loop") {
			for (int f = 0; f < 3; f++) {
				int parameters = 0;
				foreach (var block in ssa.functions[f].blocks) {
					foreach (var parameter in block.parameters) {
						assert (!(parameter.semantic_type is VectorType));
						parameters++;
					}
				}
				assert (parameters >= 1 && ssa.functions[f].storage.length == 0);
			}
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/dot/pipeline/stage-lifetimes-one-operation", stages);
	add ("/dot/pipeline/order-and-unchanged-profiles", order_and_profiles);
	add ("/dot/pipeline/branch-loop-lanes-resource", integration);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
