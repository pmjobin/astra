// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.NativeAbi;
using Astra.Continuations;
using Astra.Source;

namespace Astra.Tests.ContinuationPlans {
private NativeScalarAbiType scalar(NativeScalarType type) {
	return new NativeScalarAbiType (type);
}
private NativeContinuationRegionPlan construct () {
	var span = SourceSpan (new SourceFile.from_text ("generated-plan", ""), 0, 0);
	var fields = new GenericArray<NativeRecordField> ();
	fields.add (new NativeRecordField (0, "state", scalar (NativeScalarType.I32)));
	var leaves = new GenericArray<NativeStructLeafChannel> ();
	leaves.add (new NativeStructLeafChannel ("0", scalar (NativeScalarType.I32)));
	var env = new NativeContinuationEnvironment (new ContinuationIdentity (), new NativeRecordElement (-1, "internal", fields), null, leaves, null, true);
	var parameters = new GenericArray<NativeParameter> ();
	parameters.add (new NativeParameter (span, span, "state", 0, NativeScalarType.I32));
	parameters.add (new NativeParameter (span, span, "argument", 1, NativeScalarType.I32));
	var signature = new NativeSignature (NativeAbiVersion.SCALAR_V0, parameters, new NativeResult (NativeScalarType.I32));
	var entries = new GenericArray<NativeContinuationEntry> ();
	entries.add (new NativeContinuationEntry (new ContinuationIdentity (), ContinuationRole.STEP, env.identity, 0, signature));
	entries.add (new NativeContinuationEntry (new ContinuationIdentity (), ContinuationRole.CANCEL_DRAIN, env.identity, 1, signature));
	var families = new GenericArray<NativeContinuationFamily> ();
	families.add (new NativeContinuationFamily (new ContinuationIdentity (), env, entries, new NativeContinuationEntry (new ContinuationIdentity (), ContinuationRole.DESTROY, env.identity, -1, null), true));
	var operands = new GenericArray<NativeAbiType> ();
	operands.add (scalar (NativeScalarType.I32));
	operands.add (scalar (NativeScalarType.B1));
	var actions = new GenericArray<ContinuationAction> ();
	actions.add (new ContinuationAction (ContinuationActionKind.CREATE, 0, -1, 0, 0));
	actions.add (new ContinuationAction (ContinuationActionKind.INITIALIZE, 0, -1, -1, -1, -1, -1, -1, -1, ContinuationRole.STEP, new int[] { 0 }));
	actions.add (new ContinuationAction (ContinuationActionKind.PUBLISH, 0, -1, -1, -1, -1, 1, 0, 0));
	actions.add (new ContinuationAction (ContinuationActionKind.BEGIN, 0, -1, -1, -1, 0));
	actions.add (new ContinuationAction (ContinuationActionKind.CALL, 0, -1, -1, -1, 0, 0));
	actions.add (new ContinuationAction (ContinuationActionKind.END, 0, -1, -1, -1, 0));
	actions.add (new ContinuationAction (ContinuationActionKind.DESTROY, 0));
	return new NativeContinuationRegionPlan (new ContinuationIdentity (), 0, 0, 0, operands, families, actions);
}
private void independent() {
	try {
		for (int repeat = 0; repeat < 3; repeat++) {
			var plan = construct ();
			plan.actions[0] = plan.actions[0].copy ();
			plan.verify ();
		}
		for (int variant = 0; variant < 4; variant++) {
			var plan = construct ();
			if (variant == 0) {
				plan.actions[5] = new ContinuationAction (ContinuationActionKind.DESTROY, 0);
			}
			if (variant == 1) {
				plan.actions[2] = new ContinuationAction (ContinuationActionKind.PUBLISH, 0, -1, -1, -1, -1, 1, 1, 1);
			}
			if (variant == 2) {
				plan.actions.add (new ContinuationAction (ContinuationActionKind.DESTROY, 0));
			}
			if (variant == 3) {
				var family = plan.families[0];
				plan.families[0] = new NativeContinuationFamily (family.identity, family.environment, family.entries, null, true);
			}
			bool rejected = false;
			try {
				plan.verify ();
			} catch (NativeAbiError error) {
				Test.message ("%s", error.message);
				rejected = true;
			}
			assert (rejected);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/callable/independently-constructed-plan-without-ssa-or-llvm", independent);
	Test.add_func ("/callable/native-provenance", Astra.Tests.NativeProvenance.check);
	return Test.run ();
}
}
