// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
using Astra.Vapi;
namespace Astra.Tests.PayloadProof {
private CheckedProgram source() {
	string text = "[ExceptionRoot] class Error{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
	    + "class AsyncError:Error{init(string text):base(text){}}enum RunStatus{Completed,Cancelled}"
	    + "async runtime LinuxExecutor throws AsyncError returns RunStatus provider \"linux-io-uring\";"
	    + "async void worker(owned LinuxPayload payload)throws Error{await payload_io(payload);} int main(){return 0;}";
	var parsed = Parser.parse (new SourceFile.from_text ("payload-proof.astra", text));
	assert (parsed.diagnostic == null);
	var vapi = VapiParser.parse (new SourceFile.from_text ("payload.vapi", "[CCode(destroy_function=\"astra_linux_payload_close\")]handle LinuxPayload;"));
	assert (vapi.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit, VapiNormalizer.normalize (vapi.file), VapiNormalizer.normalize_handles (vapi.file));
	if (checked.diagnostic != null) {
		GLib.error ("%s", checked.diagnostic.message);
	}
	return checked.program;
}

private void checked_core() {
	try {
		var checked = source ();
		var body = checked.functions[0].body;
		var original = body.statements[0] as CheckedAsyncDelay;
		assert (original != null && original.payload);
		body.statements[0] = new CheckedAsyncDelay (original.span, original.body, original.ticks, false);
		bool rejected = false;
		try {
			CoreVerifier.verify (CoreBuilder.build (checked));
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Checked payload mode: %s", error.message);
		}
		assert (rejected);
		body.statements[0] = original;
		var core = CoreBuilder.build (checked);
		CoreVerifier.verify (core);
		var statements = core.functions[0].body.statements;
		int at = -1;
		for (int i = 0; i < statements.length; i++) {
			if (statements[i] is CoreAsyncDelay) {
				at = i;
			}
		}
		assert (at >= 0);
		var delay = (CoreAsyncDelay) statements[at];
		statements[at] = new CoreAsyncDelay (delay.span, delay.body, delay.ticks, false);
		rejected = false;
		try {
			CoreVerifier.verify (core);
		} catch (CoreError error) {
			rejected = true;
			Test.message ("Core payload mode: %s", error.message);
		}
		assert (rejected);
		statements[at] = delay;
		CoreVerifier.verify (core);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void cfg_ssa() {
	try {
		var cfg = CfgBuilder.build (CoreBuilder.build (source ()));
		CfgVerifier.verify (cfg);
		CfgBlock? selected = null;
		int at = -1;
		foreach (var block in cfg.functions[0].blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				if (block.instructions[i] is CfgAsyncDelay) {
					selected = block;
					at = i;
				}
			}
		}
		assert (selected != null);
		var delay = (CfgAsyncDelay) selected.instructions[at];
		selected.instructions[at] = new CfgAsyncDelay (delay.span, delay.body, delay.ticks, (ClassType) delay.exception.semantic_type, false);
		bool rejected = false;
		try {
			CfgVerifier.verify (cfg);
		} catch (CfgError error) {
			rejected = true;
			Test.message ("CFG payload mode: %s", error.message);
		}
		assert (rejected);
		selected.instructions[at] = delay;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaVerifier.verify (ssa);
		SsaBlock? block = null;
		at = -1;
		foreach (var candidate in ssa.functions[0].blocks) {
			for (int i = 0; i < candidate.instructions.length; i++) {
				if (candidate.instructions[i] is SsaAsyncDelay) {
					block = candidate;
					at = i;
				}
			}
		}
		assert (block != null && at > 0);
		var read = block.instructions[at - 1];
		assert (read is SsaHeapOwnerEvent);
		block.instructions.remove_index (at - 1);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA lost owner read: %s", error.message);
		}
		assert (rejected);
		block.instructions.insert (at - 1, read);
		SsaVerifier.verify (ssa);
		var original = (SsaAsyncDelay) block.instructions[at];
		block.instructions[at] = new SsaAsyncDelay (original.span, original.body, original.ticks, (ClassType) original.result.semantic_type, original.result.ordinal, true, null);
		rejected = false;
		try {
			SsaVerifier.verify (ssa);
		} catch (SsaError error) {
			rejected = true;
			Test.message ("SSA forged owner: %s", error.message);
		}
		assert (rejected);
		block.instructions[at] = original;
		SsaVerifier.verify (ssa);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_cabi() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source ())));
		var native = NativeAbiBuilder.build (ssa);
		var original = native.async_frames[0];
		var foreign = CAbiBuilder.build (ssa, native);
		var fields = new GenericArray<NativeAsyncField> ();
		for (uint i = 0; i < original.field_count; i++) {
			fields.add (original.field (i));
		}
		var states = new GenericArray<NativeAsyncState> ();
		for (uint i = 0; i < original.state_count; i++) {
			var state = original.state (i);
			var initialized = new GenericArray<int> ();
			for (uint f = 0; f < state.initialized_count; f++) {
				initialized.add (state.initialized_field (f));
			}
			states.add (new NativeAsyncState (state.pc, state.block, state.position, initialized));
		}
		var owners = new GenericArray<NativeAsyncOwner> ();
		for (uint i = 0; i < original.owner_count; i++) {
			owners.add (original.owner (i));
		}
		var changed = new NativeAsyncFramePlan (original.function_ordinal, original.declaration, original.result, fields, states, original.object_count, original.owner_count, null, owners, null, null, null, null, null, original.provider);
		changed.verify ();
		bool rejected = false;
		try {
			NativeAsyncFrameBuilder.validate (changed, ssa.functions[0], ssa);
		} catch (NativeAbiError error) {
			rejected = true;
			Test.message ("native missing buffer hold: %s", error.message);
		}
		assert (rejected);
		assert (foreign.cleanups.length == 1);
		var signature = foreign.cleanups[0].signature;
		var saved = signature.parameters[0];
		signature.parameters.remove_index (0);
		rejected = false;
		try {
			CAbiVerifier.verify (foreign);
		} catch (CAbiError error) {
			rejected = true;
			Test.message ("CABI lost resource cleanup pointer: %s", error.message);
		}
		assert (rejected);
		signature.parameters.add (saved);
		CAbiVerifier.verify (foreign);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_valid(LlvmModuleArtifact artifact) {
	char* message = null;
	assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
	if (message != null) {
		CApi.dispose_message (message);
	}
}

private void llvm_rejected(LlvmModuleArtifact artifact, string mutation) {
	generic_valid (artifact);
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		rejected = true;
		Test.message ("%s: %s", mutation, error.message);
	}
	assert (rejected);
}

private void llvm() {
	try {
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (source ())));
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		bool tested = false;
		foreach (var binding in artifact.class_calls) {
			var call = binding.instruction;
			size_t length;
			string name = CApi.value_name (CApi.called_value (call), out length);
			if (name != "astra_async_linux_payload") {
				continue;
			}
			var pointer = CApi.operand (call, 1);
			CApi.set_operand (call, 1, CApi.const_null (CApi.type_of (pointer)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM lost pinned payload: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (call, 1, pointer);
			artifact.verify ();
			tested = true;
		}
		assert (tested);
		bool retained = false;
		foreach (var binding in artifact.class_values) {
			var check = binding.instruction;
			if (CApi.opcode (check) != CApi.Opcode.ICMP) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (check, out length);
			if (name != "payload.owner.liveness") {
				continue;
			}
			var expected = CApi.operand (check, 1);
			CApi.set_operand (check, 1, CApi.const_null (CApi.type_of (expected)));
			generic_valid (artifact);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("LLVM forged frame release authority: %s", error.message);
			}
			assert (rejected);
			CApi.set_operand (check, 1, expected);
			artifact.verify ();
			retained = true;
		}
		assert (retained);
		int comparisons = 0;
		foreach (var binding in artifact.class_values) {
			var check = binding.instruction;
			if (CApi.opcode (check) != CApi.Opcode.ICMP) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (check, out length);
			if (name != "delay.check" && name != "delay.completion.check") {
				continue;
			}
			var zero = CApi.operand (check, 1);
			CApi.set_operand (check, 1, CApi.const_int (CApi.type_of (zero), 1, 0));
			llvm_rejected (artifact, "LLVM Linux status comparison " + name);
			CApi.set_operand (check, 1, zero);
			artifact.verify ();
			comparisons++;
		}
		assert (comparisons == 2);
		int branches = 0;
		foreach (var binding in artifact.class_branches) {
			var branch = binding.instruction;
			var condition = CApi.condition (branch);
			if ((void*) CApi.is_instruction (condition) == null) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (condition, out length);
			if (name != "delay.check" && name != "delay.completion.check") {
				continue;
			}
			CApi.set_operand (branch, 0, CApi.const_null (CApi.type_of (condition)));
			llvm_rejected (artifact, "LLVM Linux status condition " + name);
			CApi.set_operand (branch, 0, condition);
			artifact.verify ();
			var yes = CApi.successor (branch, 0);
			var no = CApi.successor (branch, 1);
			assert ((void*) yes != (void*) no);
			CApi.set_successor (branch, 0, no);
			CApi.set_successor (branch, 1, yes);
			llvm_rejected (artifact, "LLVM Linux success/error successors " + name);
			CApi.set_successor (branch, 0, yes);
			CApi.set_successor (branch, 1, no);
			artifact.verify ();
			branches++;
		}
		assert (branches == 2);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/payload/checked-core-owner-protocol", checked_core);
	Test.add_func ("/payload/cfg-ssa-exact-retained-owner", cfg_ssa);
	Test.add_func ("/payload/native-cabi-private-owner-authority", native_cabi);
	Test.add_func ("/payload/llvm-stable-buffer-operand", llvm);
	return Test.run ();
}

}
