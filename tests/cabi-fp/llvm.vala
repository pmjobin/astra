// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.CAbiFp {
private SsaProgram build(string source) throws GLib.Error {
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (check (source))));
}
private void physical_lifetime() throws GLib.Error {
	var aggregate = build (fixture ("cabi-fp-struct-native"));
	var native = NativeAbiBuilder.build (aggregate);
	assert (native.abi_version == NativeAbiVersion.AGGREGATE_V7);
	LlvmLowering.lower (aggregate, native, CAbiBuilder.build (aggregate, native)).verify ();
	foreach (string type in new string[] {"f32", "f64"}) {
		string physical = type == "f32" ? "float" : "double";
		SsaProgram? ssa = build ("extern(C) " + type + " echo(" + type + " x); export(C) " + type + " bridge(" + type + " x){return echo(x);}");
		NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
		var type_ref = WeakRef (ssa.c_functions[0].return_type);
		var source_ref = WeakRef (ssa.span.file);
		var ssa_ref = WeakRef (ssa);
		var cabi_ref = WeakRef (cabi);
		var artifact = LlvmLowering.lower (ssa, nabi, cabi);
		ssa = null;
		nabi = null;
		cabi = null;
		assert (type_ref.get () == null && source_ref.get () == null && ssa_ref.get () == null && cabi_ref.get () == null);
		artifact.verify ();
		string ir = artifact.dump ();
		assert (artifact.requires_c_floating && ir.contains ("declare " + physical + " @echo(" + physical + ")") && ir.contains ("call " + physical + " @echo(" + physical));
		assert (ir.contains ("define " + physical + " @bridge(" + physical) && ir.contains ("call fastcc " + physical));
		foreach (string forbidden in new string[] {"fpext", "fptrunc", "bitcast", "readnone", "readonly", "memory(none)", " fast ", " contract ", "llvm.fma", "llvm.fmuladd", "malloc", "alloca"}) {
			assert (!ir.contains (forbidden));
		}
		var target = new LlvmTargetMachineArtifact ();
		target.configure (artifact);
		string path = GLib.Path.build_filename (Environment.get_tmp_dir (), "astra-cabi-fp-%u.o".printf (Random.next_int ()));
		target.emit_object (artifact, path);
		assert (FileUtils.unlink (path) == 0);
	}
}
private void target_gate() throws GLib.Error {
	LlvmTargetMachineArtifact.qualify_c_floating ("x86_64-unknown-linux-gnu");
	foreach (string triple in new string[] {"sh4-unknown-linux-gnu", "aarch64-unknown-linux-gnu", "x86_64-pc-windows-msvc", "unknown"}) {
		bool rejected = false;
		try {
			LlvmTargetMachineArtifact.qualify_c_floating (triple);
		} catch (LlvmError.TARGET error) {
			rejected = true;
		}
		assert (rejected);
	}
	foreach (string type in new string[] {"f32", "f64"}) {
		var ssa = build ("extern(C) " + type + " unused();");
		var nabi = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
		assert (artifact.requires_c_floating && !artifact.requires_binary32 && !artifact.requires_binary64);
	}
}
int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/cabi-fp/llvm/exact-import-export-stage-lifetime-object", physical_lifetime);
	add ("/cabi-fp/llvm/foreign-target-gate-including-unused-declarations", target_gate);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
