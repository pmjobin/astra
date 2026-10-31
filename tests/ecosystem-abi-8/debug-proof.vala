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

namespace Astra.Tests.SourceDebug {
private void coordinates() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("debug-proof.astra", "int add(int value) { return value + 1; }\nint main() { return add(41) - 42; }\n"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var cfg = CfgBuilder.build (CoreBuilder.build (checked.program));
		assert (CfgFlowChecker.check (cfg).diagnostic == null);
		var ssa = SsaBuilder.build (cfg);
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native), null, null, true);
		string before = artifact.dump ();
		var function = CApi.named_function (artifact.module, "astra.fn.0");
		var instruction = CApi.first_instruction (CApi.first_block (function));
		while ((void*) CApi.instruction_debug_location (instruction) == null) {
			instruction = CApi.next_instruction (instruction);
			assert ((void*) instruction != null);
		}
		var original = CApi.instruction_debug_location (instruction);
		var scope = CApi.di_location_scope (original);
		var wrong_line = CApi.di_location (artifact.context, 999, 1, scope, (CApi.MetadataRef) null);
		foreach (var corrupted in new CApi.MetadataRef[] { wrong_line, (CApi.MetadataRef) null }) {
			CApi.set_instruction_debug_location (instruction, corrupted);
			bool rejected = false;
			try {
				artifact.verify ();
			} catch (LlvmError error) {
				rejected = true;
				Test.message ("source coordinate corruption: %s", error.message);
			}
			assert (rejected);
			CApi.set_instruction_debug_location (instruction, original);
			assert (artifact.dump () == before);
		}
		var original_scope = CApi.get_subprogram (function);
		CApi.set_subprogram (function, (CApi.MetadataRef) null);
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			rejected = true;
		}
		assert (rejected);
		CApi.set_subprogram (function, original_scope);
		assert (artifact.dump () == before);
		var other = CApi.named_function (artifact.module, "astra.fn.1");
		CApi.set_subprogram (function, CApi.get_subprogram (other));
		rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			rejected = true;
		}
		assert (rejected);
		CApi.set_subprogram (function, original_scope);
		assert (artifact.dump () == before);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void record_geometry() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("debug-record-proof.astra", "struct Sample{i64 count;f64 total;}int inspect(int input){Sample sample={count=input as i64,total=3.75};Sample* address=&sample;return address->count as int;}int main(){return inspect(42)-42;}"));
		assert (parsed.diagnostic == null);
		CheckedProgram? checked = SemanticAnalyzer.analyze (parsed.unit).program;
		assert (checked != null);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var upstream = WeakRef (ssa.structs[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, true);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact ().configure (artifact);
		artifact.verify ();
		string healthy_text = artifact.dump ();
		var function = CApi.named_function (artifact.module, "astra.fn.0");
		CApi.ValueRef slot = (CApi.ValueRef) null;
		for (var instruction = CApi.first_instruction (CApi.first_block (function)); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
			size_t length;
			string name = CApi.value_name (instruction, out length);
			if (CApi.opcode (instruction) == CApi.Opcode.ALLOCA && name == "storage0") {
				slot = instruction;
				break;
			}
		}
		assert ((void*) slot != null);
		var layout = CApi.allocated_type (slot);
		var first = CApi.struct_type_at_index (layout, 0);
		var second = CApi.struct_type_at_index (layout, 1);
		var changed = new CApi.TypeRef[] {
			first, second
		};
		CApi.struct_set_body (layout, changed, 2, 1);
		char* message;
		int status = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
		if (message != null) {
			Test.message ("ordinary LLVM diagnostic: %s", (string) message);
			CApi.dispose_message (message);
		}
		assert (status == 0);
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			rejected = true;
			Test.message ("ordinary-valid same-size record packing substitution: %s", error.message);
		}
		assert (rejected);
		// LLVM's type-body API does not undo an identified type's packed bit.
		// Restore from the untouched source, requiring byte-identical LLVM.
		var restored_checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (restored_checked.diagnostic == null);
		var restored_ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (restored_checked.program)));
		var restored_native = NativeAbiBuilder.build (restored_ssa);
		var restored = LlvmLowering.lower (restored_ssa, restored_native, CAbiBuilder.build (restored_ssa, restored_native), null, null, true);
		new LlvmTargetMachineArtifact ().configure (restored);
		restored.verify ();
		assert (restored.dump () == healthy_text);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private LlvmModuleArtifact capture_frame_sample(out WeakRef upstream) throws GLib.Error {
	string text = "[ExceptionRoot] class Error{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}class AsyncError:Error{init(string message):base(message){}}enum RunStatus{Completed,Cancelled}async runtime VirtualExecutor throws AsyncError returns RunStatus;class Capture{int gain;init(int gain){this.gain=gain;}deinit(){}}extern(C) int marker(int value);int apply(borrowed Capture capture,int value){marker(value);return capture.gain+value;}async void worker(int seed)throws Error{await delay_ticks(1);marker(seed);}int main(){var capture=new Capture(7);var handler=closure_bind(move capture,apply);int registered=retained_register(handler,0);int dispatched=retained_dispatch(handler,5);try{var executor=VirtualExecutor.open(2);var status=executor.run(worker(11));}catch(Error error){return 1;}return 0;}";
	var parsed = Parser.parse (new SourceFile.from_text ("debug-capture-frame-proof.astra", text));
	assert (parsed.diagnostic == null);
	var checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("Source capture/frame proof: %s", checked.diagnostic.message);
	}
	var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (checked.program)));
	SsaClass? capture = null;
	foreach (var owner in ssa.classes) {
		if (owner.name == "Capture") {
			capture = owner;
		}
	}
	assert (capture != null);
	upstream = WeakRef (capture);
	var native = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native), null, null, true);
}

private void capture_frame_geometry() {
	try {
		WeakRef upstream;
		var artifact = capture_frame_sample (out upstream);
		assert (upstream.get () == null);
		artifact.verify ();
		string healthy = artifact.dump ();
		CApi.TypeRef capture = (CApi.TypeRef) null;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.GEP) {
						continue;
					}
					var layout = CApi.gep_source_type (instruction);
					if (CApi.type_kind (layout) == CApi.TypeKind.STRUCT && CApi.count_struct_element_types (layout) == 1 && (void*) CApi.struct_type_at_index (layout, 0) == (void*) CApi.int32_type_in_context (artifact.context)) {
						capture = layout;
					}
				}
			}
		}
		assert ((void*) capture != null);
		var fields = new CApi.TypeRef[] {
			CApi.struct_type_at_index (capture, 0)
		};
		CApi.struct_set_body (capture, fields, 1, 1);
		char* message;
		int status = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
		if (message != null) {
			CApi.dispose_message (message);
		}
		assert (status == 0);
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			rejected = true;
			Test.message (error.message);
		}
		assert (rejected);
		var restored = capture_frame_sample (out upstream);
		assert (upstream.get () == null);
		assert (restored.dump () == healthy);
		CApi.ValueRef selected = (CApi.ValueRef) null;
		for (var function = CApi.first_function (restored.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			if (!CApi.value_name (function, out length).has_prefix ("astra.task.resume.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.GEP && CApi.value_name (instruction, out length) == "task.field.1") {
						selected = instruction;
					}
				}
			}
		}
		assert ((void*) selected != null);
		var original = CApi.operand (selected, 2);
		var layout = CApi.gep_source_type (selected);
		uint index = (uint) CApi.const_int_zext (original);
		uint alternate = uint.MAX;
		for (uint i = 0; i < CApi.count_struct_element_types (layout); i++) {
			if (i != index && (void*) CApi.struct_type_at_index (layout, i) == (void*) CApi.struct_type_at_index (layout, index)) {
				alternate = i;
				break;
			}
		}
		assert (alternate != uint.MAX);
		CApi.set_operand (selected, 2, CApi.const_int (CApi.type_of (original), alternate, 0));
		status = CApi.verify_module (restored.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
		if (message != null) {
			Test.message ("ordinary LLVM async-field diagnostic: %s", (string) message);
			CApi.dispose_message (message);
		}
		assert (status == 0);
		rejected = false;
		try {
			restored.verify ();
		} catch (LlvmError error) {
			rejected = true;
			Test.message (error.message);
		}
		assert (rejected);
		CApi.set_operand (selected, 2, original);
		assert (restored.dump () == healthy);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

public int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/source-debug/coordinates-reject-restore", coordinates);
	Test.add_func ("/source-debug/record-physical-layout-restored-graphs-released", record_geometry);
	Test.add_func ("/source-debug/closure-async-physical-layout-restored-graphs-released", capture_frame_geometry);
	return Test.run ();
}
}
