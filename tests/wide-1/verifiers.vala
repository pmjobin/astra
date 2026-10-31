// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
namespace Astra.Tests.WideVerifier {
private SsaProgram conversion(bool narrowing, int mutation) throws SsaError {
	var types = new BuiltinTypes ();
	var span = SourceSpan (new SourceFile.from_text ("independent", "checked scalar transport"), 0, 24);
	SemanticType source = narrowing ? types.i64_type : types.i32_type;
	SemanticType destination = narrowing ? types.i32_type : types.i64_type;
	SemanticType declared_source = source;
	if (mutation == 1) {
		declared_source = narrowing ? (SemanticType) types.u64_type : types.u32_type;
	}
	if (mutation == 2) {
		declared_source = narrowing ? (SemanticType) types.i32_type : types.i64_type;
	}
	if (mutation == 3) {
		destination = types.raw_pointer_type;
	}
	var parameters = new GenericArray<SsaFunctionParameter> ();
	parameters.add (new SsaFunctionParameter (span, span, "x", source, 0));
	var value = new SsaIntegerConversionInstruction (span, declared_source, destination, 1, parameters[0]);
	var entry = new SsaBlock (span, 0, 0);
	if (mutation != 4) {
		entry.instructions.add (value);
	}
	entry.complete (new SsaReturn (span, value.result));
	var blocks = new GenericArray<SsaBlock> ();
	blocks.add (entry);
	var functions = new GenericArray<SsaFunction> ();
	functions.add (new SsaFunction (span, span, "f", mutation == 5 ? types.u64_type : destination, 0, parameters, blocks, entry));
	return new SsaProgram (span, functions);
}
private void malformed() {
	try {
		foreach (bool narrowing in new bool[] {false, true}) {
			SsaVerifier.verify (conversion (narrowing, 0));
			for (int mutation = 1; mutation <= 5; mutation++) {
				bool rejected = false;
				try {
					SsaVerifier.verify (conversion (narrowing, mutation));
				} catch (SsaError error) {
					rejected = true;
				}
				if (!rejected) {
					GLib.error ("accepted malformed wide conversion %d", mutation);
				}
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/wide/ssa/sign-width-result-provenance", malformed);
	return Test.run ();
}
}
