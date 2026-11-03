// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.F64 {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void physical() throws GLib.Error {
	string arithmetic = lower (build (read ("basic"))).dump ();
	foreach (string op in new string[] {"fadd", "fsub", "fmul", "fdiv", "fneg"}) {
		assert (arithmetic.contains (op + " double "));
	}
	string comparison = lower (build (read ("compare"))).dump ();
	foreach (string predicate in new string[] {"oeq", "une", "olt", "ole", "ogt", "oge"}) {
		assert (comparison.contains ("fcmp " + predicate + " double "));
	}
	string conversion = lower (build (read ("convert"))).dump ();
	assert (conversion.contains ("fpext float") && conversion.contains ("fptrunc double"));
	foreach (string name in new string[] {"basic", "special", "round", "compare", "call", "loop", "pointer", "array", "slice", "object", "ownership", "channels"}) {
		string dump = lower (build (read (name))).dump ();
		foreach (string flag in new string[] {"reassoc", "nnan", "ninf", "nsz", "arcp", "contract", "afn", "fast", "llvm.fma", "llvm.fmuladd"}) {
			assert (!dump.contains (" " + flag + " ") && !dump.contains ("@" + flag));
		}
		if (name == "call" || name == "loop") {
			assert (dump.contains ("phi double "));
		}
		if (name == "pointer") {
			assert (dump.contains ("alloca double") && dump.contains ("load double,") && dump.contains ("store double "));
		}
		if (name == "array" || name == "slice") {
			assert (dump.contains ("[4 x double]"));
		}
		if (name == "object") {
			assert (dump.contains ("type { double }") && dump.contains ("ptr %result.storage, double"));
		}
	}
}

private void exact_constants() throws GLib.Error {
	var artifact = new LlvmModuleArtifact ();
	var types = new LlvmTypeMapper (artifact.context);
	var builder = CApi.create_builder_in_context (artifact.context);
	var function = CApi.add_function (artifact.module, "unused", CApi.function_type (types.scalar (NativeScalarType.F64), null, 0, 0));
	var scalars = new LlvmScalarLowering (artifact, types, builder, function);
	uint64[] patterns = {
		0, 0x8000000000000000UL, 1, 0x000fffffffffffffUL, 0x0010000000000000UL, 0x3ff0000000000001UL, 0x4340000000000000UL, 0x7fefffffffffffffUL, 0x7ff0000000000000UL, 0xfff0000000000000UL, 0x7ff8000000000001UL, 0xfff0000000000001UL
	};
	foreach (uint64 bits in patterns) {
		var constant = scalars.floating (new BinaryFloatValue.from_bits (BinaryFloatFormat.BINARY64, bits));
		assert ((void*) CApi.type_of (constant) == (void*) types.scalar (NativeScalarType.F64));
		var back = CApi.const_bit_cast (constant, types.float_bits_type (BinaryFloatFormat.BINARY64));
		assert ((uint64) CApi.constant_signed (back) == bits);
	}
	CApi.dispose_builder (builder);
	artifact.verify ();
}

private void lifetime() throws GLib.Error {
	SsaProgram? ssa = build (read ("literal") + "f64 dynamic(f64 a,f64 b){return -(a*b+a/b);}");
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
	assert (dump.contains ("ret double -0.000000e+00") && dump.contains ("fdiv double") && dump.contains ("fmul double"));
	var target = new LlvmTargetMachineArtifact ();
	string path = Path.build_filename (Environment.get_tmp_dir (), "astra-f64-%u.o".printf (Random.next_int ()));
	target.configure (artifact);
	target.emit_object (artifact, path);
	assert (FileUtils.test (path, FileTest.IS_REGULAR) && FileUtils.unlink (path) == 0);
}

int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	add ("/f64/llvm/operations-comparisons-phis-memory", physical);
	add ("/f64/llvm/bit-exact-constants-all-classes", exact_constants);
	add ("/f64/llvm/lifetime-object", lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}

}
