// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Vapi;

namespace Astra.Tests.IntegerConversions {
private const string STRAIGHT = "u16 f(i8 x){i16 v=x as i16;return v as u16;} i16<8> g(u8<8> v){return v as i16<8>;}";

private void stages() throws GLib.Error {
	CheckedProgram? checked = check (STRAIGHT);
	var checked_ref = WeakRef (checked.functions[1]);
	var checked_node = WeakRef (((CheckedReturnStatement) checked.functions[1].body.statements[0]).expression);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_ref.get () == null && checked_node.get () == null);
	CoreVerifier.verify (core);
	var conversion = (CoreIntegerConversionValue) ((CoreReturn) core.functions[1].body.statements[0]).value;
	assert (conversion.source_type.display_name () == "u8<8>" && conversion.destination_type.display_name () == "i16<8>" && conversion.span.text () == "v as i16<8>");
	var core_node = WeakRef (conversion);
	conversion = null;
	var core_ref = WeakRef (core.functions[1]);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null && core_node.get () == null);
	CfgVerifier.verify (cfg);
	assert (cfg.functions[1].blocks.length == 1 && cfg.functions[1].temporaries.length == 0 && cfg.functions[1].locals.length == 0 && cfg.functions[1].field_places.length == 0);
	assert (cfg.functions[1].entry.instructions.length == 1 && cfg.functions[1].entry.instructions[0] is CfgIntegerConversionInstruction);
	var cfg_ref = WeakRef (cfg.functions[1]);
	var cfg_node = WeakRef (((CfgEvaluateInstruction) cfg.functions[1].entry.instructions[0]).value);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null && cfg_node.get () == null);
	SsaVerifier.verify (ssa);
	assert (ssa.functions[0].storage.length == 0 && ssa.functions[0].entry.instructions.length == 2);
	assert (ssa.functions[1].storage.length == 0 && ssa.functions[1].entry.instructions.length == 1);
	var node = (SsaIntegerConversionInstruction) ssa.functions[1].entry.instructions[0];
	assert (node.operand == ssa.functions[1].parameters[0] && node.source_type.display_name () == "u8<8>" && node.destination_type.display_name () == "i16<8>");
	var source_type = WeakRef (node.source_type);
	var destination_type = WeakRef (node.destination_type);
	node = null;
	ssa = null;
	assert (source_type.get () == null && destination_type.get () == null);
}

private void order_and_profiles() throws GLib.Error {
	var cfg = CfgBuilder.build (CoreBuilder.build (check ("i8 a(){return -1;} u16 f(){return a() as u16;}")));
	assert (cfg.functions[1].entry.instructions.length == 2);
	assert (cfg.functions[1].entry.instructions[0] is CfgCallInstruction && cfg.functions[1].entry.instructions[1] is CfgIntegerConversionInstruction);
	var ssa = SsaBuilder.build (cfg);
	assert (ssa.functions[1].entry.instructions.length == 2 && ssa.functions[1].entry.instructions[0] is SsaCallInstruction && ssa.functions[1].entry.instructions[1] is SsaIntegerConversionInstruction);
	string body = "i8<8> x=splat(-1,8);u16<8> y=x as u16<8>;";
	assert (NativeAbiBuilder.build (build ("int f(){" + body + "return y[0] as int;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void* f(void* p){" + body + "return p;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("u8 f(){" + body + "return y[0] as u8;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	assert (NativeAbiBuilder.build (build ("f32 f(){" + body + "return 1.0;}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	var vector = build (STRAIGHT);
	var nabi = NativeAbiBuilder.build (vector);
	assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4);
	CAbiVerifier.verify (CAbiBuilder.build (vector, nabi));
}

private void integration() throws GLib.Error {
	foreach (string name in new string[] {"scalar", "vector", "control", "fields", "ownership", "values"}) {
		var ssa = build (read (name));
		SsaVerifier.verify (ssa);
		if (name == "control") {
			int scalar_parameters = 0;
			int vector_parameters = 0;
			foreach (var block in ssa.functions[0].blocks) {
				foreach (var parameter in block.parameters) {
					if (parameter.semantic_type.display_name () == "u16") {
						scalar_parameters++;
					}
				}
			}
			foreach (var block in ssa.functions[1].blocks) {
				foreach (var parameter in block.parameters) {
					if (parameter.semantic_type.display_name () == "i16<8>") {
						vector_parameters++;
					}
				}
			}
			assert (scalar_parameters >= 2 && vector_parameters >= 2 && ssa.functions[0].storage.length == 0 && ssa.functions[1].storage.length == 0);
		}
	}
	var vapi = VapiParser.parse (new SourceFile.from_text ("resource.vapi", declarations ()));
	foreach (string source in new string[] {"u32 f(){Resource r=null;return r as u32;}", "Resource f(u32 x){return x as Resource;}"}) {
		var parsed = Parser.parse (new SourceFile.from_text ("invalid", source));
		var result = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
		assert (result.program == null && result.diagnostic.message.contains ("unsupported integer conversion") && result.diagnostic.message.contains ("'Resource'"));
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/iconv/pipeline/stage-lifetimes-and-one-vector-operation", stages);
	add ("/iconv/pipeline/order-purity-and-unchanged-profiles", order_and_profiles);
	add ("/iconv/pipeline/branch-loop-fields-native-resource", integration);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
