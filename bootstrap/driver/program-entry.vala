// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Driver {
public errordomain ExecutionError {
	ENTRY,
	OUTPUT,
	LINK
}

public class ProgramEntry : Object {
	public static Ssa.SsaFunction resolve(Ssa.SsaProgram program) throws ExecutionError {
		foreach (var exported in program.c_exports) {
			if (exported.external_symbol == "main") {
				var diagnostic = new Source.Diagnostic (exported.name_span, "C export symbol `main` conflicts with the executable entry wrapper");
				throw new ExecutionError.ENTRY ("%s", diagnostic.format ());
			}
		}
		foreach (var function in program.functions) {
			if (function is Ssa.SsaMethod || function.name != "main") {
				continue;
			}
			string? reason = null;
			if (function.throws_type != null) {
				reason = "main must handle its checked exceptions";
			} else if (function.return_type.kind != Semantic.TypeKind.INT) {
				reason = "main must return int";
			} else if (function.parameters.length != 0 && (function.parameters.length != 1 || !function.parameters[0].semantic_type.is_text_slice () || function.parameters[0].pointer_contract != Semantic.PointerParameterContract.BORROWED_NOESCAPE)) {
				reason = "main must have zero parameters or one borrowed string[] parameter";
			}
			if (reason != null) {
				var diagnostic = new Source.Diagnostic (function.name_span, "executable requires `int main()` or `int main(string[] args)`; " + reason);
				throw new ExecutionError.ENTRY ("%s", diagnostic.format ());
			}
			// This exact identity is the only entry selection passed downstream.
			return function;
		}
		throw new ExecutionError.ENTRY ("astrac: error: executable requires `int main()`; no source function named main");
	}
}
}
