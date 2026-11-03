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
namespace Astra.Tests.LinuxFrames {
private string support(string provider = " provider \"linux-io-uring\"", string name = "LinuxExecutor") {
	return "[ExceptionRoot] class Error { readonly string text; init(string value){this.text=value;} virtual property string message {get{return this.text;}} } class AsyncError:Error {init(string value):base(value){}} enum RunStatus{Completed,Cancelled} async runtime " + name + " throws AsyncError returns RunStatus" + provider + ";";
}

private string body() {
	return "async void worker(int ticks,u32 unsigned_ticks) throws Error {await delay_ms(ticks);await delay_ms(unsigned_ticks);} int main(){return 42;}";
}

private SsaProgram build(string text) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("linux-frames.astra", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("check: %s", checked.diagnostic.message);
	}
	return SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
}

private void generic_valid(LlvmModuleArtifact artifact) {
	char* message = null;
	assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
	if (message != null) {
		CApi.dispose_message (message);
	}
}

private void rejects(string text, string message) {
	var parsed = Parser.parse (new SourceFile.from_text ("linux-rejected.astra", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	assert (checked.diagnostic != null && checked.diagnostic.message.contains (message));
}

private void provider_selection() {
	try {
		var program = build (support (" provider \"linux-io-uring\"", "Renamed") + body () + "int provider(){return 1;}");
		assert (program.functions[0].async_body.runtime.linux && program.functions[0].async_body.runtime.executor_name == "Renamed");
		rejects (support (" provider \"unknown\"") + body (), "unsupported explicit async provider");
		rejects (support () + "async void worker() throws Error {await delay_ticks(1);} int main(){return 42;}", "delay units");
		rejects (support ("") + "async void worker() throws Error {await delay_ms(1);} int main(){return 42;}", "delay units");
		rejects (support () + "int main(){try{var ex=LinuxExecutor.open(2);ex.advance(1);}catch(Error error){}return 42;}", "does not admit virtual advance");
		rejects (support ("") + "int main(){try{var ex=LinuxExecutor.open(2);ex.wait();}catch(Error error){}return 42;}", "does not admit Linux wait");
		rejects (support () + "int delay_ms(int value){return value;} async void worker() throws Error {await delay_ms(1);} int main(){return 42;}", "conflicts with an ordinary");
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_provider_correspondence() {
	try {
		var source = build (support () + body ());
		var native = NativeAbiBuilder.build (source);
		var foreign = CAbiBuilder.build (source, native);
		var original = native.async_frames[0];
		assert (NativeAbiDump.format (native).contains (NativeAsyncFramePlan.LINUX_CAPABILITY));
		var fields = new GenericArray<NativeAsyncField> ();
		for (uint i = 0; i < original.field_count; i++) {
			fields.add (original.field (i));
		}
		var states = new GenericArray<NativeAsyncState> ();
		for (uint i = 0; i < original.state_count; i++) {
			states.add (original.state (i));
		}
		// Independently valid virtual plan, same physical fields and states.
		native.async_frames[0] = new NativeAsyncFramePlan (original.function_ordinal, original.declaration, original.result, fields, states);
		native.async_frames[0].verify ();
		bool rejected = false;
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = error.message.contains ("declaration-only callable admission authority");
		}
		assert (rejected);
		rejected = false;
		try {
			NativeAsyncFrameBuilder.validate (native.async_frames[0], source.functions[0], source);
		} catch (NativeAbiError error) {
			rejected = error.message.contains ("provider differs");
		}
		assert (rejected);
		rejected = false;
		assert (native.async_frames[0].provider == AsyncProviderKind.VIRTUAL);
		rejected = false;
		try {
			NativeAbiDump.format (native);
		} catch (NativeAbiError error) {
			rejected = error.message.contains ("declaration-only callable admission authority");
		}
		assert (rejected);
		rejected = false;
		try {
			LlvmLowering.lower (source, native, foreign);
		} catch (LlvmError error) {
			rejected = error.message.contains ("declaration-only callable admission authority");
		}
		assert (rejected);
		native.async_frames[0] = original;
		NativeAbiVerifier.verify (native);
		LlvmLowering.lower (source, native, foreign).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void llvm_correspondence() {
	try {
		SsaProgram? source = build (support () + body ());
		NativeAbiProgram? native = NativeAbiBuilder.build (source);
		CAbiProgram? foreign = CAbiBuilder.build (source, native);
		var predecessor = WeakRef (source.functions[0]);
		var artifact = LlvmLowering.lower (source, native, foreign);
		source = null;
		native = null;
		foreign = null;
		assert (predecessor.get () == null);
		artifact.verify ();
		generic_valid (artifact);
		bool target_tested = false, duration_tested = false, result_tested = false, resume_tested = false, task_tested = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.CALL) {
						size_t count;
						string name = CApi.value_name (CApi.called_value (instruction), out count);
						if (name == "astra_async_linux_delay_ms" && !target_tested) {
							var signature = CApi.called_function_type (instruction);
							var other = CApi.add_function (artifact.module, "astra_async_delay", signature);
							CApi.set_function_call_conv (other, CApi.CallConv.C);
							uint at = CApi.argument_count (instruction);
							var saved = CApi.operand (instruction, at);
							CApi.set_operand (instruction, at, other);
							generic_valid (artifact);
							bool rejected = false;
							try {
								artifact.verify ();
							} catch (LlvmError error) {
								rejected = true;
							}
							assert (rejected);
							CApi.set_operand (instruction, at, saved);
							artifact.verify ();
							target_tested = true;
						}
						if (name == "astra_async_linux_delay_result" && !result_tested) {
							var saved = CApi.operand (instruction, 1);
							CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (saved), 2, 0));
							generic_valid (artifact);
							bool rejected = false;
							try {
								artifact.verify ();
							} catch (LlvmError error) {
								rejected = true;
							}
							assert (rejected);
							CApi.set_operand (instruction, 1, saved);
							artifact.verify ();
							result_tested = true;
						}
						if (name == "astra_async_linux_delay_ms" && !task_tested) {
							var saved = CApi.operand (instruction, 0);
							CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (saved)));
							generic_valid (artifact);
							bool rejected = false;
							try {
								artifact.verify ();
							} catch (LlvmError error) {
								rejected = true;
							}
							assert (rejected);
							CApi.set_operand (instruction, 0, saved);
							artifact.verify ();
							task_tested = true;
						}
					}
					if (CApi.opcode (instruction) == CApi.Opcode.SEXT && !duration_tested) {
						var saved = CApi.operand (instruction, 0);
						CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (saved), 3, 0));
						generic_valid (artifact);
						bool rejected = false;
						try {
							artifact.verify ();
						} catch (LlvmError error) {
							rejected = true;
						}
						assert (rejected);
						CApi.set_operand (instruction, 0, saved);
						artifact.verify ();
						duration_tested = true;
					}
					if (CApi.opcode (instruction) == CApi.Opcode.ICMP && !resume_tested) {
						size_t count;
						string name = CApi.value_name (instruction, out count);
						if (name == "delay.completion.check") {
							var saved = CApi.operand (instruction, 1);
							CApi.set_operand (instruction, 1, CApi.const_int (CApi.type_of (saved), 1, 0));
							generic_valid (artifact);
							bool rejected = false;
							try {
								artifact.verify ();
							} catch (LlvmError error) {
								rejected = true;
							}
							assert (rejected);
							CApi.set_operand (instruction, 1, saved);
							artifact.verify ();
							resume_tested = true;
						}
					}
				}
			}
		}
		assert (target_tested && duration_tested && result_tested && resume_tested && task_tested);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public static int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/linux-async/provider-selection-and-units", provider_selection);
	Test.add_func ("/linux-async/native-provider-source-correspondence", native_provider_correspondence);
	Test.add_func ("/linux-async/LLVM-duration-resumption-target-correspondence", llvm_correspondence);
	return Test.run ();
}

}
