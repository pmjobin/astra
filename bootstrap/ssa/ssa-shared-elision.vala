// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
namespace Astra.Ssa {
public class SsaSharedElisionPlan : Object {
	public SsaSharedOperation acquisition { get; private set; }
	public SsaCleanupInstruction cleanup { get; private set; }
	internal SsaSharedElisionPlan (SsaSharedOperation acquisition, SsaCleanupInstruction cleanup) {
		this.acquisition = acquisition;
		this.cleanup = cleanup;
	}

}
public class SsaSharedElision : Object {
	public static GenericArray<SsaSharedElisionPlan> derive(SsaFunction function) {
		return SsaSharedBalance.derive (function);
	}

	public static void annotate(SsaProgram program) {
		foreach (var function in program.functions) {
			foreach (var plan in derive (function)) {
				function.shared_elisions.add (plan);
			}
		}
	}

	public static void verify(SsaProgram program) throws SsaError {
		SsaSharedBalanceVerifier.verify (program);
	}

}
}
