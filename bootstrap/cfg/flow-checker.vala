// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;

namespace Astra.Cfg {
public class CfgFlowResult : Object {
	public Diagnostic? diagnostic { get; private set; }

	internal CfgFlowResult (Diagnostic? diagnostic) {
		this.diagnostic = diagnostic;
	}

}

public class CfgFlowChecker : Object {
	public static CfgFlowResult check(CfgProgram program) throws CfgError {
		CfgVerifier.verify (program);
		for (int i = 0; i < program.functions.length; i++) {
			var function = program.functions[i];
			if (function.declaration_only ()) {
				continue;
			}
			var tasks = TaskFlow.check (function);
			if (tasks != null) {
				return new CfgFlowResult (tasks);
			}
			var ownership = OwnershipFlow.analyze (function);
			if (ownership.diagnostic != null) {
				return new CfgFlowResult (ownership.diagnostic);
			}
			var reachability = CfgReachability.analyze (function);
			for (int j = 0; j < function.blocks.length; j++) {
				var block = function.blocks[j];
				if (reachability.is_reachable (block) && block.terminator is CfgFunctionEnd && !(block.terminator is CfgForeignReturn) && function.return_type.kind != TypeKind.VOID) {
					return new CfgFlowResult (new Diagnostic (function.name_span, "not all paths in function '%s' return a value".printf (function.name)));
				}
			}
		}
		return new CfgFlowResult (null);
	}

}
}
