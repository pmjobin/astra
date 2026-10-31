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

namespace Astra.Tests.Vectors {
private void profiles() throws GLib.Error {
	var ssa = build (read ("native-call"));
	var nabi = NativeAbiBuilder.build (ssa);
	assert (nabi.abi_version == NativeAbiVersion.VECTOR_V4);
	var type = (NativeVectorType) nabi.functions[0].signature.result.abi_type;
	assert (type.element == NativeScalarType.I16 && type.lanes == 8 && type.same_type (nabi.functions[0].signature.parameters[0].abi_type));
	assert (nabi.functions[3].signature.parameters[0].scalar_type == NativeScalarType.PTR);
	bool rejected = false;
	try {
		CAbiTypeMapper.map_scalar (ssa.functions[0].return_type);
	} catch (CAbiError error) {
		rejected = true;
	}
	assert (rejected);
	CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
	string body = "int<4> v={1,2,3,4};";
	assert (NativeAbiBuilder.build (build ("int f(){" + body + "return 0;}")).abi_version == NativeAbiVersion.SCALAR_V0);
	assert (NativeAbiBuilder.build (build ("void* f(void* p){" + body + "return p;}")).abi_version == NativeAbiVersion.SCALAR_PTR_V1);
	assert (NativeAbiBuilder.build (build ("u8 f(){" + body + "return 1;}")).abi_version == NativeAbiVersion.SCALAR_INT_V2);
	assert (NativeAbiBuilder.build (build ("f32 f(){" + body + "return 1.0;}")).abi_version == NativeAbiVersion.SCALAR_FP_V3);
	foreach (string text in new string[] {"int<4> f(int<4> a){return a;} f32 g(){return 1.0;} void* h(void* p){return p;}", "void* h(void* p){return p;} f32 g(){return 1.0;} int<4> f(int<4> a){return a;}"}) {
		assert (NativeAbiBuilder.build (build (text)).abi_version == NativeAbiVersion.VECTOR_V4);
	}
	// Physical signedness must be validated even when LLVM types coincide.
	var signed = build ("i8<4> f(i8<4> a){return a;}");
	var unsigned = NativeAbiBuilder.build (build ("u8<4> f(u8<4> a){return a;}"));
	var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
	map.insert (signed.functions[0], unsigned.functions[0]);
	rejected = false;
	try {
		NativeAbiValidator.validate_ssa_calls (signed, unsigned, map);
	} catch (NativeAbiError error) {
		rejected = error.message.contains ("channel type");
	}
	assert (rejected);
}

private void lifetime() throws GLib.Error {
	CheckedProgram? checked = check ("f32<4> f(){f32<4> v={-0.0,1.0,2.0,3.0};return v;}");
	var vector_ref = WeakRef (checked.functions[0].symbol.return_type);
	var element_ref = WeakRef (((VectorType) checked.functions[0].symbol.return_type).element_type);
	var statement_ref = WeakRef (checked.functions[0].body.statements[0]);
	var initial = (CheckedVectorConstructExpression) ((CheckedLocalDeclaration) checked.functions[0].body.statements[0]).initializer;
	var bits_ref = WeakRef (((CheckedFloatExpression) initial.lanes[0]).value);
	var span = SourceSpan (initial.span.file, 0, 3);
	var lane = (CheckedFloatExpression) initial.lanes[0];
	initial.lanes[0] = new CheckedFloatExpression (span, lane.semantic_type, lane.value);
	lane = null;
	initial = null;
	CoreProgram? core = CoreBuilder.build (checked);
	checked = null;
	assert (statement_ref.get () == null && vector_ref.get () != null && element_ref.get () != null);
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
	var construction = (SsaVectorConstructInstruction) ssa.functions[0].entry.instructions[0];
	assert (construction.result.semantic_type == vector_ref.get () && ((SsaFloatConstant) construction.lanes[0]).value == bits_ref.get ());
	construction = null;
	assert (SsaDump.format (ssa).contains ("f32 0x80000000"));
	var nabi = NativeAbiBuilder.build (ssa);
	ssa = null;
	assert (vector_ref.get () == null && element_ref.get () == null && bits_ref.get () == null);
	NativeAbiVerifier.verify (nabi);
	assert (nabi.functions[0].signature.result.abi_type.spelling () == "VECTOR(F32,4)");
}

private void fixtures() throws GLib.Error {
	foreach (string name in new string[] {"basic", "integers", "f32", "masks", "branch", "loop", "native-call", "order", "ownership", "physical"}) {
		var checked = check (read (name));
		var core = CoreBuilder.build (checked);
		var cfg = CfgBuilder.build (core);
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		var nabi = NativeAbiBuilder.build (ssa);
		CAbiVerifier.verify (CAbiBuilder.build (ssa, nabi));
		bool vector_parameter = false;
		bool mask_parameter = false;
		foreach (var f in core.functions) {
			foreach (var local in f.locals) {
				if (local.semantic_type is VectorType) {
					assert (local.is_promotable () && !local.address_taken);
				}
			}
		}
		foreach (var f in cfg.functions) {
			foreach (var local in f.locals) {
				if (local.semantic_type is VectorType) {
					assert (local.is_promotable () && !local.address_taken);
				}
			}
		}
		foreach (var f in ssa.functions) {
			if (name != "order") {
				assert (f.storage.length == 0);
			}
			foreach (var b in f.blocks) {
				foreach (var p in b.parameters) {
					if (p.semantic_type is VectorType) {
						vector_parameter = true;
						if (((VectorType) p.semantic_type).is_mask) {
							mask_parameter = true;
						}
					}
				}
			}
		}
		if (name == "branch" || name == "loop") {
			assert (vector_parameter && mask_parameter);
		}
		if (name == "basic") {
			int adds = 0;
			foreach (var instruction in ssa.functions[0].entry.instructions) {
				if (instruction is SsaBinaryInstruction) {
					adds++;
					assert (instruction.result.semantic_type is VectorType);
				}
			}
			assert (adds == 1);
		}
	}
}

private void deferrals() throws GLib.Error {
	foreach (string declaration in new string[] {"int<4> f();", "int f(bool<4> a);"}) {
		var result = VapiParser.parse (new SourceFile.from_text ("unsupported.vapi", declaration));
		assert (result.file == null && result.diagnostic != null);
	}
	var syntax = Parser.parse (new SourceFile.from_text ("invalid.astra", "void f(Resource<4> x){}"));
	var vapi = VapiParser.parse (new SourceFile.from_text ("resource.vapi", declarations ()));
	var result = SemanticAnalyzer.analyze (syntax.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	assert (result.program == null && result.diagnostic.message.contains ("vector element must be"));
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/vec/pipeline/profiles-signedness-cabi-guard", profiles);
	add ("/vec/pipeline/lifetime-no-reparse", lifetime);
	add ("/vec/pipeline/fixtures-whole-value-promotion", fixtures);
	add ("/vec/pipeline/vapi-resource-deferral", deferrals);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
