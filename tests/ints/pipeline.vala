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

namespace Astra.Tests.Integers {
private void profiles() throws GLib.Error {
	foreach (string t in new string[] {"i8", "u8", "i16", "u16", "u32"}) {
		var ssa = build (t + " f(" + t + " x){return x;} void* p(void* x){return x;}");
		var nabi = NativeAbiBuilder.build (ssa);
		assert (nabi.abi_version == NativeAbiVersion.SCALAR_INT_V2);
		assert (nabi.functions[0].signature.parameters[0].scalar_type.spelling () == t.up ());
		assert (nabi.functions[0].signature.result.scalar_type.spelling () == t.up ());
		assert (nabi.functions[1].signature.result.scalar_type == NativeScalarType.PTR);
		bool rejected = false;
		try {
			CAbiTypeMapper.map_scalar (ssa.functions[0].return_type);
		} catch (CAbiError error) {
			rejected = error is CAbiError.INVALID_TYPE;
		}
		assert (rejected);
		assert (CAbiBuilder.build (ssa, nabi).functions.length > 0);
	}
	assert (NativeAbiBuilder.build (build ("i32 f(i32 x){return x;} int g(){u8 x=255;return 1;} ")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void* f(void* x){u8 y=1;return x;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("u8 f(){return 1;} void* g(void* p){return p;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
}

private void lifetime() throws GLib.Error {
	foreach (string t in new string[] {"i8", "u8", "i16", "u16", "int", "u32"}) {
		CheckedProgram? checked = check (t + " f(){return 42;}");
		var type_ref = WeakRef (checked.functions[0].symbol.return_type);
		var statement_ref = WeakRef (checked.functions[0].body.statements[0]);
		// Replace the provenance with nonnumeric text. The exact typed
		// constant must remain unchanged through every downstream stage.
		var literal = (CheckedIntegerExpression) ((CheckedReturnStatement) checked.functions[0].body.statements[0]).expression;
		var value_ref = WeakRef (literal.value);
		var span = SourceSpan (literal.span.file, 0, t.length);
		checked.functions[0].body.statements[0] = new CheckedReturnStatement (span, new CheckedIntegerExpression.typed (span, literal.semantic_type, literal.value));
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
		assert (((SsaIntegerConstant) ((SsaReturn) ssa.functions[0].entry.terminator).value).value == value_ref.get ());
		assert (SsaDump.format (ssa).contains ("(integer 42 : " + t + ")"));
		var nabi = NativeAbiBuilder.build (ssa);
		ssa = null;
		assert (type_ref.get () == null && value_ref.get () == null);
		NativeAbiVerifier.verify (nabi);
		assert (nabi.functions[0].signature.result.scalar_type.spelling () == (t == "int" ? "I32" : t.up ()));
	}
}

private void foreign_deferral() throws GLib.Error {
	foreach (string t in new string[] {"i8", "u8", "i16", "u16", "u32"}) {
		foreach (string declaration in new string[] {t + " f();", "int f(" + t + " x);"}) {
			var vapi = VapiParser.parse (new SourceFile.from_text ("unsupported.vapi", declaration));
			assert (vapi.file != null);
			var syntax = Parser.parse (new SourceFile.from_text ("empty.astra", "int main(){return 0;}"));
			var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file));
			assert (result.program == null && result.diagnostic.message == "exact-width C integer channels are not supported yet");
		}
	}
}

private void fixtures() throws GLib.Error {
	foreach (string name in new string[] {"basic", "literals", "wrap", "div", "compare", "branch", "loop", "struct", "addressable", "native-call", "ownership", "physical"}) {
		var ssa = build (read (name));
		SsaVerifier.verify (ssa);
		var nabi = NativeAbiBuilder.build (ssa);
		CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
		if (name == "loop" || name == "branch" || name == "struct") {
			assert (SsaDump.format (ssa).contains (" : u8"));
			bool parameters = false;
			foreach (var f in ssa.functions) {
				foreach (var b in f.blocks) {
					foreach (var p in b.parameters) {
						if (p.semantic_type.kind == TypeKind.U8) {
							parameters = true;
						}
					}
				}
			}
			assert (parameters);
		}
	}
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/ints/pipeline/profiles-cabi-guard", profiles);
	add ("/ints/pipeline/lifetime-no-reparse", lifetime);
	add ("/ints/pipeline/foreign-deferral", foreign_deferral);
	add ("/ints/pipeline/fixtures-promotion", fixtures);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
