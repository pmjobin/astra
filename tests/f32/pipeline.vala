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

namespace Astra.Tests.F32 {
private void profiles() throws GLib.Error {
	var ssa = build (read ("native-call"));
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.SCALAR_FP_V3);
	assert (nabi.functions[0].signature.parameters[0].scalar_type == NativeScalarType.F32 && nabi.functions[0].signature.result.scalar_type == NativeScalarType.F32);
	assert (CAbiTypeMapper.map_scalar (ssa.functions[0].return_type) == CAbiScalarType.F32);
	var cabi = CAbiBuilder.build (ssa, nabi);
	CAbiVerifier.verify (cabi);
	// The shared harness imports Resource pointers; native f32 adds no C channel.
	assert (cabi.profile == CAbiProfile.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("int f(){f32 x=1.0;return 0;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void* f(void* p){f32 x=1.0;return p;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("u8 f(){f32 x=1.0;return 1;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	foreach (string text in new string[] {"f32 f(){return 1.0;} void* g(void* p){return p;} u8 h(){return 1;}", "u8 h(){return 1;} void* g(void* p){return p;} f32 f(){return 1.0;}"}) {
		assert (NativeAbiBuilder.build (build (text)).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	}
}

private void lifetime() throws GLib.Error {
	foreach (string t in new string[] {"f32"}) {
		CheckedProgram? checked = check (t + " f(){return -0.0;}");
		var type_ref = WeakRef (checked.functions[0].symbol.return_type);
		var statement_ref = WeakRef (checked.functions[0].body.statements[0]);
		// Replace the provenance with nonnumeric text. The exact typed
		// constant must remain unchanged through every downstream stage.
		var literal = (CheckedFloatExpression) ((CheckedReturnStatement) checked.functions[0].body.statements[0]).expression;
		var value_ref = WeakRef (literal.value);
		var span = SourceSpan (literal.span.file, 0, t.length);
		checked.functions[0].body.statements[0] = new CheckedReturnStatement (span, new CheckedFloatExpression (span, literal.semantic_type, literal.value));
		literal = null;
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (statement_ref.get () == null && type_ref.get () != null);
		CoreVerifier.verify (core);
		var core_ref = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_ref.get () == null);
		CfgVerifier.verify (cfg);
		var cfg_ref = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_ref.get () == null);
		SsaVerifier.verify (ssa);
		assert (((SsaFloatConstant) ((SsaReturn) ssa.functions[0].entry.terminator).value).value == value_ref.get ());
		assert (SsaDump.format (ssa).contains ("(f32 0x80000000 : " + t + ")"));
		var nabi = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (type_ref.get () == null && value_ref.get () == null);
		NativeAbiVerifier.verify (nabi);
		assert (nabi.functions[0].signature.result.scalar_type.spelling () == "F32");
	}
}

private void foreign_scalars() throws GLib.Error {
	foreach (string declaration in new string[] {"f32 f();", "int f(f32 x);", "f32 f(f32 x);"}) {
		var vapi = VapiParser.parse (new SourceFile.from_text ("unsupported.vapi", declaration));
		assert (vapi.file != null);
		var syntax = Parser.parse (new SourceFile.from_text ("empty.astra", "int main(){return 0;}"));
		var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file));
		assert (result.program != null && result.diagnostic == null);
	}
}

private void fixtures() throws GLib.Error {
	foreach (string name in new string[] {"basic", "literals", "special", "rounding", "compare", "branch", "loop", "struct", "addressable", "native-call", "ownership", "physical"}) {
		var ssa = build (read (name));
		SsaVerifier.verify (ssa);
		var nabi = NativeAbiBuilder.build (ssa);
		CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
		if (name == "branch" || name == "loop" || name == "struct") {
			bool promoted = false;
			foreach (var f in ssa.functions) {
				foreach (var b in f.blocks) {
					foreach (var p in b.parameters) {
						if (p.semantic_type is F32Type) {
							promoted = true;
						}
					}
				}
			}
			assert (promoted);
		}
		if (name == "addressable") {
			assert (ssa.functions[1].storage.length == 1);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/f32/pipeline/profiles-cabi-guard", profiles);
	add ("/f32/pipeline/lifetime-no-reparse", lifetime);
	add ("/f32/pipeline/vapi-c-signature-scalars", foreign_scalars);
	add ("/f32/pipeline/fixtures-promotion", fixtures);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
