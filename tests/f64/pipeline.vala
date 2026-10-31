// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.Vapi;

namespace Astra.Tests.F64 {
private void profiles() throws GLib.Error {
	foreach (string text in new string[] {"f64 f(){return 1.0;}", "void f(f64 x){}", "f64 f(f64 a,f64 b){return a+b;}", "f64 f(f64 x,void* p){return x;}", "f64 f(f64 x,f32<4> v){return x;}", "f64 f(f64 x,borrowed f64[] s){return x;}"}) {
		assert (NativeAbiBuilder.build (build (text)).abi_version == NativeAbiVersion.FP64_V6);
	}
	assert (NativeAbiBuilder.build (build ("int f(){f64 x=1.0;return 0;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void f(f64* p){*p=1.0;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("void f(borrowed f64[] s){s[0]=1.0;}")).abi_version == NativeAbiVersion.SLICE_V5);
	assert (NativeAbiBuilder.build (build ("f32 f(){f64 x=1.0;return x as f32;}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	assert (NativeAbiBuilder.build (build ("int<4> f(int<4> v){f64 x=1.0;return v;}")).abi_version == NativeAbiVersion.VECTOR_V4);
	assert (NativeAbiBuilder.build (build ("u8 f(){f64 x=1.0;return 1;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	var object = NativeAbiBuilder.build (build (read ("ownership")));
	assert (object.abi_version == NativeAbiVersion.FP64_V6 && NativeAbiDump.format (object).contains ("(result-storage PTR first caller-provided)"));
}

private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check ("f64 widen(f32 x){return x as f64;} f32 narrow(f64 x){return x as f32;} f64 literal(){return -0.0;}");
	var span = SourceSpan (new SourceFile.from_text ("replacement", "not numeric text"), 0, 16);
	var literal = (CheckedFloatExpression) ((CheckedReturnStatement) checked.functions[2].body.statements[0]).expression;
	var bits_ref = WeakRef (literal.value);
	checked.functions[2].body.statements[0] = new CheckedReturnStatement (span, new CheckedFloatExpression (span, literal.semantic_type, literal.value));
	literal = null;
	var checked_ref = WeakRef (checked);
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (checked_ref.get () == null);
	CoreVerifier.verify (core);
	assert (CoreDump.format (core).contains ("(f64 0x8000000000000000 : f64)"));
	assert (((CoreFloatConversionValue) ((CoreReturn) core.functions[0].body.statements[0]).value).conversion_kind == FloatConversionKind.FLOAT_WIDEN);
	var core_ref = WeakRef (core);
	CfgProgram? cfg = CfgBuilder.build (core);
	core = null;
	assert (core_ref.get () == null);
	CfgVerifier.verify (cfg);
	assert (CfgDump.format (cfg).contains ("(mode nearest-ties-even)"));
	var cfg_ref = WeakRef (cfg);
	SsaProgram? ssa = SsaBuilder.build (cfg);
	cfg = null;
	assert (cfg_ref.get () == null);
	SsaVerifier.verify (ssa);
	assert (((SsaFloatConstant) ((SsaReturn) ssa.functions[2].entry.terminator).value).value == bits_ref.get ());
	assert (((SsaFloatConversionInstruction) ssa.functions[1].entry.instructions[0]).conversion_kind == FloatConversionKind.FLOAT_NARROW);
	var ssa_ref = WeakRef (ssa);
	var native = NativeAbiBuilder.build (ssa);
	ssa = null;
	assert (ssa_ref.get () == null && bits_ref.get () == null);
	NativeAbiVerifier.verify (native);
	assert (native.functions[0].signature.result.scalar_type == NativeScalarType.F64 && native.functions[1].signature.parameters[0].scalar_type == NativeScalarType.F64);
}

private void integration() throws GLib.Error {
	foreach (string fixture in new string[] {"basic", "literal", "round", "special", "compare", "convert", "call", "loop", "pointer", "pointer-null", "array", "slice", "object", "ownership", "channels"}) {
		var ssa = build (read (fixture));
		SsaVerifier.verify (ssa);
		if (fixture == "call" || fixture == "loop") {
			bool merged = false;
			foreach (var function in ssa.functions) {
				foreach (var block in function.blocks) {
					foreach (var parameter in block.parameters) {
						if (parameter.semantic_type is F64Type) {
							merged = true;
						}
					}
				}
			}
			assert (merged);
		}
	}
	foreach (string declaration in new string[] {"f64 f();", "int f(f64 x);", "f64 f(f64 x);"}) {
		var source = new SourceFile.from_text ("foreign.vapi", declaration);
		var parsed = VapiParser.parse (source);
		assert (parsed.file != null);
		var syntax = Astra.Syntax.Parser.parse (new SourceFile.from_text ("empty.astra", ""));
		var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (parsed.file));
		assert (result.program != null && result.diagnostic == null);
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/f64/pipeline/channel-profiles-storage-ownership", profiles);
	add ("/f64/pipeline/stage-lifetime-exact-conversions-bits", lifetime);
	add ("/f64/pipeline/fixtures-ssa-control-flow-vapi-f64", integration);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
