// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.F32 {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void physical() throws GLib.Error {
	string arithmetic = lower (build (read ("basic"))).dump ();
	foreach (string op in new string[] {"fadd", "fsub", "fmul", "fdiv", "fneg"}) {
		assert (arithmetic.contains (op + " float "));
	}
	assert (!arithmetic.contains ("llvm.trap") && !arithmetic.contains (".nonzero") && !arithmetic.contains ("double"));
	string comparison = lower (build (read ("compare"))).dump ();
	foreach (string predicate in new string[] {"oeq", "une", "olt", "ole", "ogt", "oge"}) {
		assert (comparison.contains ("fcmp " + predicate + " float "));
	}
	assert (!comparison.contains ("fcmp one"));
	foreach (string name in new string[] {"basic", "special", "rounding", "compare", "branch", "loop", "struct", "addressable", "native-call", "ownership", "physical"}) {
		string dump = lower (build (read (name))).dump ();
		foreach (string flag in new string[] {"reassoc", "nnan", "ninf", "nsz", "arcp", "contract", "afn", "fast", "double", "llvm.fma", "llvm.fmuladd"}) {
			assert (!dump.contains (" " + flag + " ") && !dump.contains ("@" + flag));
		}
		if (name == "branch" || name == "loop" || name == "struct") {
			assert (dump.contains ("phi float "));
		}
		if (name == "addressable") {
			assert (dump.contains ("load float,") && dump.contains ("store float ") && dump.contains ("getelementptr") && dump.contains ("type { float, float }"));
		}
	}
}

private void exact_constants() throws GLib.Error {
	var artifact = new LlvmModuleArtifact ();
	var types = new LlvmTypeMapper (artifact.context);
	var builder = CApi.create_builder_in_context (artifact.context);
	var function = CApi.add_function (artifact.module, "unused", CApi.function_type (types.scalar (NativeScalarType.F32), null, 0, 0));
	var scalars = new LlvmScalarLowering (artifact, types, builder, function);
	uint32[] patterns = {
		0, 0x80000000U, 1, 0x007fffffU, 0x00800000U, 0x3f800000U, 0xbf800000U, 0x7f7fffffU, 0x7f800000U, 0xff800000U, 0x7fc00001U, 0xff800001U
	};
	foreach (uint32 bits in patterns) {
		var constant = scalars.floating (new AstraF32Value.from_bits (bits));
		assert ((void*) CApi.type_of (constant) == (void*) types.scalar (NativeScalarType.F32));
		var back = CApi.const_bit_cast (constant, types.scalar (NativeScalarType.I32));
		assert ((uint32) CApi.constant_signed (back) == bits);
	}
	CApi.dispose_builder (builder);
	artifact.verify ();
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("literals") + "f32 dynamic(f32 a,f32 b){return -(a*b+a/b);}");
	NativeAbiProgram? nabi = NativeAbiBuilder.build (ssa);
	CAbiProgram? cabi = CAbiBuilder.build (ssa, nabi);
	var type_ref = WeakRef (ssa.functions[0].return_type);
	var ssa_ref = WeakRef (ssa);
	var native_ref = WeakRef (nabi);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = LlvmLowering.lower (ssa, nabi, cabi);
	ssa = null;
	nabi = null;
	cabi = null;
	assert (type_ref.get () == null && ssa_ref.get () == null && native_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	string dump = artifact.dump ();
	assert (dump.contains ("ret float -0.000000e+00") && dump.contains ("fdiv float") && dump.contains ("fmul float"));
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-f32-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/f32/llvm/operations-comparisons-phis-memory", physical);
	add ("/f32/llvm/bit-exact-constants-all-classes", exact_constants);
	add ("/f32/llvm/lifetime-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
