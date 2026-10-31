// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
namespace Astra.Tests.CAbiFp {
private SsaProgram build(string source, string declarations = "") throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check (source, declarations))));
}
private void profiles() throws GLib.Error {
	foreach (string source in new string[] {"extern(C) void f(f32 x);", "extern(C) f32 f();", "extern(C) f32 f(f32 a,f64 b);", "export(C) f32 f(f32 x){return x;}", "extern(C) void f(f64 x);", "extern(C) f64 f();", "extern(C) f64 f(f64 a,f64 b);", "extern(C) int f(int a,f64 b,void* p);", "export(C) f64 f(f64 x){return x;}"}) {
		var ssa = build (source);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		assert (cabi.profile == CAbiProfile.SCALAR_FP_V2);
		assert (CAbiDump.format (cabi).contains ("(semantic f64) (c-type double)") || CAbiDump.format (cabi).contains ("(semantic f32) (c-type float)"));
	}
	foreach (string source in new string[] {"f64 native(f64 x){return x;}", "int main(){f64 local=1.0;return 0;}", "extern(C) int integer(int x); f64 native(f64 x){return x;}"}) {
		var ssa = build (source);
		assert (CAbiBuilder.build (ssa, NativeAbiBuilder.build (ssa)).profile == CAbiProfile.SCALAR_V0);
	}
	var owned = build ("extern(C) f32 inspect(borrowed void* p); void f(){owned void* p=acquire(); f32 x=inspect(p);}", "[CCode(destroy_function=\"release\")] void* acquire();");
	var with_cleanup = CAbiBuilder.build (owned, NativeAbiBuilder.build (owned));
	assert (with_cleanup.profile == CAbiProfile.SCALAR_FP_V2 && with_cleanup.cleanups.length == 1 && with_cleanup.cleanups[0].signature.parameters[0].scalar_type == CAbiScalarType.PTR);
	var narrow = NativeAbiBuilder.build (build ("f32 f(f32 x){return x;}"));
	assert (narrow.abi_version == NativeAbiVersion.SCALAR_FP_V3 && narrow.functions[0].signature.parameters[0].scalar_type == NativeScalarType.F32);
	var native = NativeAbiBuilder.build (build ("f64 f(f64 x){return x;}"));
	assert (native.abi_version == NativeAbiVersion.FP64_V6 && native.functions[0].signature.parameters[0].scalar_type == NativeScalarType.F64);
	var aggregate = build (fixture ("cabi-fp-struct-native"));
	native = NativeAbiBuilder.build (aggregate);
	assert (native.abi_version == NativeAbiVersion.AGGREGATE_V7 && CAbiBuilder.build (aggregate, native).profile == CAbiProfile.SCALAR_FP_V2);
	var vapi = build ("f64 f(f64 x){return echo(x);}", "double echo(double x);");
	assert (CAbiBuilder.build (vapi, NativeAbiBuilder.build (vapi)).functions[0].signature.result.scalar_type == CAbiScalarType.F64);
}
private void lifetime() throws GLib.Error {
	foreach (string width in new string[] {"f32", "f64"}) {
		string spelling = width == "f32" ? "float" : "double";
		CheckedProgram? checked = check ("export(C) " + width + " bridge(" + width + " x){return echo(x);}", "[CCode(cname=\"c_echo\")] " + spelling + " echo(" + spelling + " x);");
		var checked_ref = WeakRef (checked);
		var symbol_ref = WeakRef (checked.c_functions[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (checked_ref.get () == null && symbol_ref.get () == null);
		CoreVerifier.verify (core);
		assert (core.c_functions[0].return_type is FloatingType && core.c_functions[0].abi == ForeignAbi.C && core.c_functions[0].external_symbol == "c_echo");
		assert (core.c_functions[0].parameters[0].span.text ().contains (spelling + " x"));
		var core_ref = WeakRef (core);
		var foreign_ref = WeakRef (core.c_functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (core_ref.get () == null && foreign_ref.get () == null);
		CfgVerifier.verify (cfg);
		assert (((CfgCCallInstruction) cfg.functions[0].entry.instructions[0]).result.semantic_type is FloatingType);
		var cfg_ref = WeakRef (cfg);
		foreign_ref = WeakRef (cfg.c_functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (cfg_ref.get () == null && foreign_ref.get () == null);
		SsaVerifier.verify (ssa);
		assert (((SsaCCallInstruction) ssa.functions[0].entry.instructions[0]).result.semantic_type is FloatingType);
		var ssa_ref = WeakRef (ssa);
		var type_ref = WeakRef (ssa.c_functions[0].return_type);
		foreign_ref = WeakRef (ssa.c_functions[0]);
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		ssa = null;
		assert (ssa_ref.get () == null && type_ref.get () == null && foreign_ref.get () == null);
		CAbiVerifier.verify (cabi);
		NativeAbiVerifier.verify (nabi);
		assert (cabi.functions[0].name == "echo" && cabi.functions[0].external_symbol == "c_echo" && cabi.functions[0].span.file.path == "double.vapi");
		assert (cabi.profile == CAbiProfile.SCALAR_FP_V2 && nabi.abi_version == (width == "f32" ? NativeAbiVersion.SCALAR_FP_V3 : NativeAbiVersion.FP64_V6));
	}
}
private void malformed() throws GLib.Error {
	// Each structurally valid plan still has to match its exact SSA channel.
	for (int mode = 0; mode < 3; mode++) {
		var ssa = build ("extern(C) f64 echo(f64 x); export(C) f64 bridge(f64 x){return echo(x);}");
		var nabi = NativeAbiBuilder.build (ssa);
		var cabi = CAbiBuilder.build (ssa, nabi);
		if (mode == 0) {
			cabi.functions[0].signature.parameters[0] = new CAbiParameter (ssa.span, ssa.span, "x", 0, CAbiScalarType.I32);
		}
		if (mode == 1) {
			cabi.exports[0].signature.parameters[0] = new CAbiParameter (ssa.span, ssa.span, "x", 0, CAbiScalarType.I32);
		}
		if (mode == 2) {
			var imports = new GenericArray<CAbiFunction> ();
			var old = cabi.functions[0];
			imports.add (new CAbiFunction (old.span, old.name_span, old.name, 0, new CAbiSignature (cabi.profile, old.signature.parameters, new CAbiResult (CAbiScalarType.F32)), old.metadata));
			cabi = new CAbiProgram (ssa.span, cabi.profile, imports);
		}
		CAbiVerifier.verify (cabi);
		bool rejected = false;
		try {
			if (mode == 1) {
				var map = new HashTable<SsaFunction, NativeFunction> (direct_hash, direct_equal);
				map.insert (ssa.functions[0], nabi.functions[0]);
				CAbiValidator.validate_exports (ssa, nabi, cabi, map);
			} else {
				var map = new HashTable<SsaCFunction, CAbiFunction> (direct_hash, direct_equal);
				map.insert (ssa.c_functions[0], cabi.functions[0]);
				CAbiValidator.validate_ssa_calls (ssa, cabi, map);
			}
		} catch (CAbiError error) {
			rejected = true;
		}
		assert (rejected);
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/cabi-fp/pipeline/profiles-native-firewall-declaration-only", profiles);
	add ("/cabi-fp/pipeline/vapi-checked-core-cfg-ssa-independent-plan-lifetime", lifetime);
	add ("/cabi-fp/pipeline/mismatched-plans", malformed);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
