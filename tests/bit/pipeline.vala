// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;

namespace Astra.Tests.Bit {
private void stages() throws GLib.Error {
	foreach (string type in new string[] {"u8", "i16<8>", "bool", "bool<8>"}) {
		foreach (string op in type.has_prefix ("bool") ? new string[] {"&", "|", "^"} : new string[] {"&", "|", "^", "~", "<<", ">>"}) {
			bool shift = op == "<<" || op == ">>";
			string text = "%s f(%s a,%s b){return %s;}".printf (type, type, shift ? "u32" : type, op == "~" ? "~a" : "a" + op + "b");
			CheckedProgram? checked = check (text);
			var checked_witness = WeakRef (checked.functions[0]);
			CoreProgram? core = CoreBuilder.build (checked);
			checked = null;
			assert (checked_witness.get () == null);
			CoreVerifier.verify (core);
			var core_witness = WeakRef (core.functions[0]);
			CfgProgram? cfg = CfgBuilder.build (core);
			core = null;
			assert (core_witness.get () == null);
			CfgVerifier.verify (cfg);
			assert (cfg.functions[0].blocks.length == 1 && cfg.functions[0].temporaries.length == 0 && cfg.functions[0].field_places.length == 0);
			if (shift) {
				assert (cfg.functions[0].entry.instructions[cfg.functions[0].entry.instructions.length - 1] is CfgIntegerShiftInstruction);
			}
			var cfg_witness = WeakRef (cfg.functions[0]);
			SsaProgram? ssa = SsaBuilder.build (cfg);
			cfg = null;
			assert (cfg_witness.get () == null);
			SsaVerifier.verify (ssa);
			assert (ssa.functions[0].blocks.length == 1 && ssa.functions[0].entry.instructions.length == 1 && ssa.functions[0].storage.length == 0);
			assert (ssa.functions[0].entry.instructions[0].result.semantic_type == ssa.functions[0].return_type);
			if (shift) {
				var node = (SsaIntegerShiftInstruction) ssa.functions[0].entry.instructions[0];
				assert (node.operand == ssa.functions[0].parameters[0] && node.count == ssa.functions[0].parameters[1] && node.count.semantic_type.kind == TypeKind.U32);
			}
			assert (!SsaDump.format (ssa).contains ("vector-extract"));
			var type_witness = WeakRef (ssa.functions[0].return_type);
			ssa = null;
			assert (type_witness.get () == null);
		}
	}
}

private void order() throws GLib.Error {
	foreach (string type in new string[] {"bool", "bool<4>", "u8<16>"}) {
		string literal = type.has_prefix ("bool") ? "true" : "1";
		string result = type == "bool" ? literal : "splat(" + literal + "," + (type == "bool<4>" ? "4" : "16") + ")";
		foreach (string op in new string[] {"&", "|", "^"}) {
			var cfg = CfgBuilder.build (CoreBuilder.build (check ("%s a(){return %s;} %s b(){return %s;} %s f(){return a()%sb();}".printf (type, result, type, result, type, op))));
			var function = cfg.functions[2];
			assert (function.blocks.length == 1 && function.entry.instructions.length == 2);
			assert (((CfgCallInstruction) function.entry.instructions[0]).target.name == "a" && ((CfgCallInstruction) function.entry.instructions[1]).target.name == "b");
			assert (((CfgReturn) function.entry.terminator).value is CfgBinaryValue);
			var ssa = SsaBuilder.build (cfg);
			assert (ssa.functions[2].entry.instructions.length == 3 && ssa.functions[2].entry.instructions[2] is SsaBinaryInstruction);
		}
	}
	foreach (string op in new string[] {"&&", "||"}) {
		var cfg = CfgBuilder.build (CoreBuilder.build (check ("bool f(bool a,bool b){return a" + op + "b;}")));
		assert (cfg.functions[0].blocks.length > 1 && CfgDump.format (cfg).contains ("conditional-branch"));
	}
	foreach (string name in new string[] {"basic", "signed", "bool", "mask", "shift", "shift-trap", "vector", "loop", "integration", "ownership", "values"}) {
		SsaVerifier.verify (build (read (name)));
	}
}

private void profiles() throws GLib.Error {
	string body = "u8<16> v=splat(3,16);v=(~v|splat(1,16))<<1;";
	assert (NativeAbiBuilder.build (build ("int f(){" + body + "return 1;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void* f(void* p){" + body + "return p;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("u8 f(){" + body + "return v[0];}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	assert (NativeAbiBuilder.build (build ("f32 f(){" + body + "return 1.0;}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	var ssa = build ("i16<8> f(i16<8> a,int c){return ~a>>c;}");
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4);
	CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/bit/pipeline/stage-lifetimes-one-operation", stages);
	add ("/bit/pipeline/eager-order-shortcircuit-and-integration", order);
	add ("/bit/pipeline/unchanged-abi-profiles", profiles);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
