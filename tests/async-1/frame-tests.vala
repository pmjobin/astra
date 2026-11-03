// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Vapi;
using Astra.Backend.LLVM;
namespace Astra.Tests.AsyncFrames {
private string support() {
	return "[ExceptionRoot] class Error { readonly string text; init(string s) { this.text=s; } virtual property string message { get { return this.text; } } } class AsyncError:Error { init(string s):base(s){} } enum RunStatus { Completed, Cancelled } async runtime VirtualExecutor throws AsyncError returns RunStatus;";
}

private string body() {
	return "extern(C) void event(int tag,int value); extern(C) int step(int tag,int ordinal); extern(C) int capture(int ordinal); async int worker(int tag,u32 ticks,int seed) throws Error { int value=seed; int n=0; while(n<3) { event(tag,value); await delay_ticks(ticks); value=value+step(tag,n); if(n==1) { await delay_ticks(0); } n=n+1; } return value; } async void root() throws Error { await delay_ticks(20); } export(C) int cold(){var first=worker(capture(1),capture(2) as u32,capture(3)); var second=move first; var third=worker(capture(4),capture(5) as u32,capture(6));return 42;} int main(){return 42;}";
}

private string await_body() {
	return "extern(C) void observed(int stage,int value); class DecodeError:Error { init(string s):base(s){} deinit(){observed(9,42);} } async int leaf(int seed) throws Error {await delay_ticks(1);await delay_ticks(2);return seed+5;} async int faulty() throws DecodeError {try {await delay_ticks(1);}catch(AsyncError error){}throw new DecodeError(\"original\\0é\");} async void joined() throws Error {int answer=await leaf(17);observed(1,answer);try {try {await faulty();}catch(Error error){var message=error.message;var copy=message;observed(5,42);int value=await leaf(3);if(copy==\"original\\0é\" && value==8){observed(2,42);}throw;}}catch(DecodeError error){if(error.message==\"original\\0é\"){observed(3,42);}}} async void discarded() throws Error {var task=faulty();await cancel_and_join(move task);observed(4,42);} async void propagated() throws Error {await faulty();} async void invalid_delay(int n) throws Error {try {await delay_ticks(n);observed(7,81);}catch(AsyncError error){observed(7,42);}} async void replacing() throws Error {try {await faulty();}catch(Error error){var message=error.message;await faulty();observed(8,81);}} export(C) int host_replacement(){try {var executor=VirtualExecutor.open(3);var status=executor.run(replacing());return 90;}catch(DecodeError error){if(error.message==\"original\\0é\"){observed(8,42);return 42;}return 91;}catch(Error error){return 92;}} async int timed(int stage,int ticks,int result) throws Error {await delay_ticks(ticks);observed(stage,42);return result;} async void concurrent() throws Error {var slow=timed(11,5,1);start(slow);var fast=timed(10,1,2);int fast_value=0;try {start(fast);fast_value=await move fast;}catch(Error error){await cancel_and_join(move slow);throw;}int slow_value=await move slow;if(fast_value+slow_value==3){observed(12,42);}} async void refused_start() throws Error {var child=leaf(4);try {start(child);}catch(AsyncError error){await cancel_and_join(move child);observed(13,42);return;}await move child;} async void refused_await() throws Error {try {int value=await leaf(4);observed(14,81);}catch(AsyncError error){observed(14,42);}} async void cancelled_child() throws Error {var child=leaf(4);cancel(child);try {await move child;observed(15,81);}catch(Error error){observed(15,81);}} async void sibling_error() throws Error {var slow=timed(11,5,1);start(slow);try {await faulty();}catch(Error error){var message=error.message;await cancel_and_join(move slow);if(message==\"original\\0é\"){observed(16,42);}throw;}await move slow;} export(C) int host_sibling_error(){try {var executor=VirtualExecutor.open(3);var status=executor.run(sibling_error());return 98;}catch(DecodeError error){return 42;}catch(Error error){return 99;}} async void discard_completed() throws Error {var child=leaf(4);start(child);try {await delay_ticks(10);}catch(Error error){await cancel_and_join(move child);throw;}cancel(child);await cancel_and_join(move child);observed(17,42);} async void discard_exceptional() throws Error {var child=faulty();start(child);try {await delay_ticks(10);}catch(Error error){await cancel_and_join(move child);throw;}cancel(child);await cancel_and_join(move child);observed(18,42);} export(C) int host_discard_outcomes(){try {var first=VirtualExecutor.open(3);var a=first.run(discard_completed());var second=VirtualExecutor.open(3);var b=second.run(discard_exceptional());return 42;}catch(Error error){return 100;}} async void parent_work() throws Error {int value=await leaf(4);observed(19,81);} async void parent_only(bool first) throws Error {var parent=parent_work();var unrelated=timed(20,8,2);try {if(first){start(parent);start(unrelated);}else{start(unrelated);start(parent);}await delay_ticks(2);}catch(Error error){await cancel_and_join(move parent);await cancel_and_join(move unrelated);throw;}cancel(parent);await cancel_and_join(move parent);int value=await move unrelated;if(value==2){observed(21,42);}} export(C) int host_parent_only(){try {var first=VirtualExecutor.open(4);var a=first.run(parent_only(true));var second=VirtualExecutor.open(4);var b=second.run(parent_only(false));return 42;}catch(Error error){return 101;}} export(C) int host_concurrent(){try {var executor=VirtualExecutor.open(3);var status=executor.run(concurrent());return 42;}catch(Error error){return 93;}} export(C) int host_refused_start(){try {var executor=VirtualExecutor.open(1);var status=executor.run(refused_start());return 42;}catch(Error error){return 94;}} export(C) int host_refused_await(){try {var executor=VirtualExecutor.open(1);var status=executor.run(refused_await());return 42;}catch(Error error){return 95;}} export(C) int host_child_cancel(){try {var executor=VirtualExecutor.open(1);var status=executor.run(cancelled_child());match(status){case RunStatus.Cancelled():{return 42;}else:{return 96;}}}catch(Error error){return 97;}} export(C) int host_invalid_delay(){try {var executor=VirtualExecutor.open(1);var status=executor.run(invalid_delay(-1));return 42;}catch(Error error){return 89;}} export(C) int host(){try{var executor=VirtualExecutor.open(3);var root=joined();executor.advance(0);executor.start(root);executor.pump(1);var status=executor.run(move root);match(status){case RunStatus.Completed():{return 42;}else:{return 82;}}}catch(Error error){return 81;}} export(C) int host_cancel(){try{var executor=VirtualExecutor.open(3);var root=joined();executor.start(root);executor.pump(1);executor.cancel(root);var status=executor.run(move root);match(status){case RunStatus.Cancelled():{return 42;}else:{return 84;}}}catch(Error error){return 83;}} export(C) int host_invalid_capacity(){try{var executor=VirtualExecutor.open(0);return 85;}catch(AsyncError error){return 42;}} export(C) int host_original_error(){try{var executor=VirtualExecutor.open(3);var status=executor.run(propagated());return 86;}catch(DecodeError error){if(error.message==\"original\\0é\"){observed(6,42);return 42;}return 87;}catch(Error error){return 88;}} int main(){return 42;}";
}

private string buffer_body() {
	return "extern(C) void buffered(int stage,int value); async owned int[] produce(int seed) throws Error {owned int[] values=new int[3];values[0]=seed;await delay_ticks(1);values[1]=seed+1;await delay_ticks(2);values[2]=seed+2;return move values;} async void buffers() throws Error {owned int[] values=await produce(40);buffered(1,values[0]+values[1]+values[2]);await delay_ticks(2);values[0]=values[0]+1;buffered(2,values[0]);} async void failing_buffer() throws Error {owned int[] values=new int[3];await delay_ticks(1);throw new AsyncError(\"buffer failure\");} async void keeper() throws Error {await delay_ticks(20);} async owned int[] captured(owned int[] first,owned int[] second,int seed) throws Error {first[0]=seed;await delay_ticks(1);first[1]=second[0];await delay_ticks(2);return move first;} async void capture_parent() throws Error {owned int[] first=new int[3];owned int[] second=new int[2];second[0]=2;var child=captured(move first,move second,40);owned int[] result=await move child;buffered(3,result[0]+result[1]);await delay_ticks(1);result[0]=result[0]+2;buffered(4,result[0]);} int later_failure() throws Error {throw new AsyncError(\"later capture argument\");} export(C) int cold_captures(){owned int[] first=new int[3];owned int[] second=new int[2];var child=captured(move first,move second,40);var moved=move child;return 42;} export(C) int capture_abort(){owned int[] first=new int[3];owned int[] second=new int[2];first[0]=40;second[0]=2;try {var child=captured(move first,move second,later_failure());return 80;}catch(Error error){buffered(5,first[0]+second[0]);return 42;}} export(C) int fresh_captures(){var child=captured(new int[3],new int[2],40);return 42;} export(C) int fresh_abort(){owned int[] named=new int[3];named[0]=42;try{var child=captured(move named,new int[2],later_failure());return 80;}catch(Error error){buffered(6,named[0]);return 42;}} int main(){return 42;}";
}

private string resource_api() {
	return "[CCode(destroy_function=\"close_resource\")] handle Resource; owned Resource open_resource(int id); int read_resource(borrowed Resource resource);";
}

private string resource_body() {
	return "extern(C) void resource_event(int stage,int value); async int resources(owned Resource first,owned Resource second,int seed) throws Error {resource_event(1,read_resource(first)+read_resource(second));await delay_ticks(1);owned Resource next=move first;second=open_resource(seed);await delay_ticks(2);resource_event(2,read_resource(next)+read_resource(second));return 42;} async void resource_root() throws Error {owned Resource first=open_resource(10);owned Resource second=open_resource(20);int value=await resources(move first,move second,32);resource_event(3,value);} async void resource_waiting() throws Error {owned Resource first=open_resource(40);owned Resource second=open_resource(41);await delay_ticks(20);resource_event(4,81);} int argument_failure() throws Error {throw new AsyncError(\"resource argument failure\");} export(C) int resource_cold(){owned Resource first=open_resource(10);owned Resource second=open_resource(20);var child=resources(move first,move second,32);var moved=move child;return 42;} export(C) int resource_abort(){owned Resource first=open_resource(10);owned Resource second=open_resource(20);try{var child=resources(move first,move second,argument_failure());return 81;}catch(Error error){resource_event(5,read_resource(first)+read_resource(second));return 42;}} async void resource_refused() throws Error {owned Resource first=open_resource(10);owned Resource second=open_resource(20);try{int value=await resources(move first,move second,32);resource_event(6,81);}catch(AsyncError error){resource_event(6,42);}} export(C) int resource_host(){try{var executor=VirtualExecutor.open(3);var status=executor.run(resource_root());return 42;}catch(Error error){return 80;}} export(C) int resource_admission(){try{var executor=VirtualExecutor.open(1);var status=executor.run(resource_refused());return 42;}catch(Error error){return 82;}} export(C) int resource_fresh(){var child=resources(open_resource(10),open_resource(20),32);return 42;} export(C) int resource_fresh_abort(){owned Resource named=open_resource(10);try{var child=resources(move named,open_resource(20),argument_failure());return 81;}catch(Error error){resource_event(7,read_resource(named));return 42;}} class MixedError:Error {init(string value):base(value){}deinit(){resource_event(10,42);}} enum MixedOwner {Live(owned int[] data),Empty} async void mixed_child(owned Resource first,owned int[] second,MixedOwner third) throws Error {int n=0;resource_event(11,read_resource(first));await delay_ticks(1);while(n<3){owned Resource turn=open_resource(60+n);await delay_ticks(1);n=n+1;if(n==1){continue;}if(n==2){break;}}match(move third){case MixedOwner.Live(data):{await delay_ticks(2);second[0]=data[0];}else:{resource_event(8,81);}}throw new MixedError(\"mixed original\");} async int mixed_loan(owned Resource resource,owned int[] buffer,int[] view) throws Error {await delay_ticks(1);buffer[0]=read_resource(resource)-68;view[0]=view[0]+buffer[0];await delay_ticks(2);return view[0]+view[1];} async void mixed_parent() throws Error {owned Resource retained=open_resource(50);int[2] backing={20,20};try{await mixed_child(open_resource(10),new int[2],MixedOwner.Live(new int[2]));}catch(Error error){var message=error.message;var copy=message;resource_event(9,42);await delay_ticks(1);int value=await mixed_loan(open_resource(70),new int[2],slice(backing));if(copy==\"mixed original\"){resource_event(8,read_resource(retained)+value);}}} async void mixed_replacement() throws Error {owned Resource retained=open_resource(50);try{await mixed_child(open_resource(10),new int[2],MixedOwner.Live(new int[2]));}catch(Error error){var message=error.message;resource_event(9,42);await delay_ticks(1);if(message==\"mixed original\"){await mixed_child(open_resource(10),new int[2],MixedOwner.Live(new int[2]));}}} export(C) int mixed_host(){try{var executor=VirtualExecutor.open(3);var status=executor.run(mixed_parent());return 42;}catch(Error error){return 81;}} export(C) int mixed_replace_host(){try{var executor=VirtualExecutor.open(3);var status=executor.run(mixed_replacement());return 81;}catch(MixedError error){if(error.message==\"mixed original\"){return 42;}return 82;}catch(Error error){return 83;}} owned Resource recovered_resource() throws Error {try{argument_failure();}catch(Error error){owned Resource recovered=open_resource(21);return move recovered;}owned Resource fallback=open_resource(81);return move fallback;} int completed_resource_consumer(owned Resource value){return read_resource(value);} int nested_argument_failure() throws Error {owned Resource inner=open_resource(22);int value=completed_resource_consumer(move inner);argument_failure();return value;} export(C) int resource_nested_abort(){try{var child=resources(open_resource(10),recovered_resource(),nested_argument_failure());return 81;}catch(Error error){resource_event(12,42);return 42;}} int main(){return 42;}";
}

private string storage_body() {
	return "extern(C) void storage_event(int stage,int value); struct Record{int left;int right;} enum Copy{Ready(Record record,int marker),Empty} enum Owner{Ready(owned int[] first,owned Record[] second),Empty} async void persistent(int seed) throws Error {int[3] numbers={seed,2,3};Record record={left=seed,right=2};var copied=Copy.Ready(record,3);owned Record[] records=new Record[2];records[0].left=seed;records[1].right=2;var owner=Owner.Ready(new int[2],new Record[3]);int n=0;while(n<2){await delay_ticks(1);numbers[0]=numbers[0]+1;record.left=record.left+1;records[0].left=records[0].left+1;n=n+1;}match(copied){case Copy.Ready(original,marker):{storage_event(1,original.left+original.right+marker);}else:{storage_event(1,81);}}storage_event(2,numbers[0]+numbers[1]+numbers[2]);storage_event(3,record.left+record.right);storage_event(4,records[0].left+records[1].right);match(move owner){case Owner.Ready(first,second):{storage_event(5,len(first)+len(second));}else:{storage_event(5,81);}}} async void enum_capture(Owner first,Owner second) throws Error {await delay_ticks(1);await delay_ticks(2);match(first){case Owner.Ready(a,b):{storage_event(6,len(a)+len(b));}else:{storage_event(6,81);}}match(move second){case Owner.Ready(a,_):{storage_event(7,len(a));}else:{storage_event(7,81);}}} async void enum_waiting() throws Error {var first=Owner.Ready(new int[2],new Record[3]);var second=Owner.Ready(new int[3],new Record[2]);await delay_ticks(20);storage_event(8,81);} export(C) int storage_host(){try{var executor=VirtualExecutor.open(2);var status=executor.run(persistent(35));var second=VirtualExecutor.open(2);var next=second.run(enum_capture(Owner.Ready(new int[2],new Record[3]),Owner.Ready(new int[3],new Record[2])));return 42;}catch(Error error){return 80;}} export(C) int storage_cold(){var first=Owner.Ready(new int[2],new Record[3]);var second=Owner.Ready(new int[3],new Record[2]);var child=enum_capture(move first,move second);return 42;} int main(){return 42;}";
}

private string result_body() {
	return "extern(C) void result_event(int stage,int value); extern(C) int float_bits(f32 value); extern(C) f32 input_float(); struct Record{int left;int right;f32 bits;} enum Copy{Ready(Record record,int marker),Empty} enum Owner{Ready(owned int[] first,owned Record[] second),Empty} async Record record_result(Record first,Record second) throws Error {await delay_ticks(1);await delay_ticks(2);Record result={left=first.left+second.left,right=first.right+second.right,bits=first.bits};return result;} async Copy copy_result(Copy value) throws Error {await delay_ticks(1);await delay_ticks(2);return value;} async owned Record[] array_result(owned Record[] values) throws Error {await delay_ticks(1);values[0].left=values[0].left+2;await delay_ticks(2);values[1].right=values[1].right+3;return move values;} async Owner owning_result(Owner first,Owner second) throws Error {await delay_ticks(1);match(second){case Owner.Ready(a,b):{result_event(5,len(a)+len(b));}else:{result_event(5,81);}}await delay_ticks(2);return move first;} async void results_root() throws Error {Record first={left=30,right=2,bits=input_float()};Record second={left=7,right=3,bits=1.0};var record=await record_result(first,second);result_event(1,record.left+record.right);result_event(6,float_bits(record.bits));var copied=await copy_result(Copy.Ready(record,2));match(copied){case Copy.Ready(value,marker):{result_event(2,value.left+value.right+marker);}else:{result_event(2,81);}}owned Record[] input=new Record[2];input[0].left=35;input[1].right=2;owned Record[] returned=await array_result(move input);result_event(3,returned[0].left+returned[1].right);var owner=await owning_result(Owner.Ready(new int[2],new Record[3]),Owner.Ready(new int[3],new Record[2]));await delay_ticks(1);match(move owner){case Owner.Ready(a,b):{b[0].left=37;result_event(4,a[0]+b[0].left+len(a)+len(b));}else:{result_event(4,81);}}owned f32<4>[] vector_input=new f32<4>[2];f32<4> lanes={0.5,1.0,1.5,2.0};vector_input[0]=lanes;owned f32<4>[] vector_output=await vector_array(move vector_input);if(all(vector_output[0]==lanes)){result_event(8,42);}else{result_event(8,81);}owned bool<4>[] mask_input=new bool<4>[2];mask_input[0]=lanes==lanes;owned bool<4>[] mask_output=await mask_array(move mask_input);if(all(mask_output[0])){result_event(9,42);}else{result_event(9,81);}} async void results_discard() throws Error {var child=owning_result(Owner.Ready(new int[2],new Record[3]),Owner.Ready(new int[3],new Record[2]));start(child);try{await delay_ticks(20);}catch(Error error){await cancel_and_join(move child);throw;}await cancel_and_join(move child);result_event(7,42);} export(C) int result_host(){try{var executor=VirtualExecutor.open(3);var status=executor.run(results_root());var second=VirtualExecutor.open(3);var next=second.run(results_discard());return 42;}catch(Error error){return 80;}} async owned f32<4>[] vector_array(owned f32<4>[] values) throws Error {await delay_ticks(1);await delay_ticks(2);return move values;} async owned bool<4>[] mask_array(owned bool<4>[] values) throws Error {await delay_ticks(1);await delay_ticks(2);return move values;} async void array_discard() throws Error {owned Record[] input=new Record[2];var child=array_result(move input);start(child);try{await delay_ticks(20);}catch(Error error){await cancel_and_join(move child);throw;}await cancel_and_join(move child);result_event(10,42);} Owner owner_failure() throws Error {throw new AsyncError(\"enum argument failure\");} export(C) int owning_abort(){try{var task=owning_result(Owner.Ready(new int[2],new Record[3]),owner_failure());return 81;}catch(Error error){if(error.message==\"enum argument failure\"){result_event(11,42);}else{return 82;}}var owner=Owner.Ready(new int[2],new Record[3]);try{var task=owning_result(move owner,owner_failure());return 83;}catch(Error error){match(move owner){case Owner.Ready(a,b):{result_event(11,len(a)+len(b)+37);}else:{return 84;}}}return 42;} int main(){return 42;}";
}

private string loan_body() {
	return "extern(C) void loan_event(int stage,int value); async int loan_child(int[] first,int[] second,int seed) throws Error {loan_event(1,first[0]+second[0]);await delay_ticks(2);first[0]=first[0]+seed;await delay_ticks(3);loan_event(2,first[0]+first[1]);return first[0]+first[1];} async void loan_parent() throws Error {int[4] backing={20,2,3,4};int result=await loan_child(slice(backing,0,2),slice(backing,2,2),20);loan_event(3,result);backing[0]=backing[0]-2;loan_event(4,backing[0]+backing[3]);} int main(){return 42;}";
}

private SsaProgram build(string text, string? declarations = null) throws GLib.Error {
	var parsed = Parser.parse (new SourceFile.from_text ("native-frames.astra", support () + text));
	if (parsed.diagnostic != null) {
		GLib.error ("parse: %s", parsed.diagnostic.message);
	}
	var vapi = declarations == null ? null : VapiParser.parse (new SourceFile.from_text ("async-resource.vapi", declarations));
	if (vapi != null && vapi.diagnostic != null) {
		GLib.error ("vapi: %s", vapi.diagnostic.message);
	}
	var checked = SemanticAnalyzer.analyze (parsed.unit, vapi == null ? null : VapiNormalizer.normalize (vapi.file), vapi == null ? null : VapiNormalizer.normalize_handles (vapi.file));
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

private void native_frame() {
	try {
		SsaProgram? ssa = build (body ());
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
		assert (native.async_frames.length == 2 && native.async_frames[0].state_count == 3 && native.async_frames[1].state_count == 2);
		var predecessor = WeakRef (ssa.functions[0]);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		assert (predecessor.get () == null);
		artifact.verify ();
		generic_valid (artifact);
		var text = artifact.dump ();
		assert (text.contains ("astra.task.resume.0") && text.contains ("astra.task.create.0") && text.contains ("switch i32") && text.contains ("@astra_async_delay"));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void frame_correspondence() {
	try {
		var ssa = build (body ());
		var native = NativeAbiBuilder.build (ssa);
		var foreign = CAbiBuilder.build (ssa, native);
		var original = native.async_frames[0];
		var fields = new GenericArray<NativeAsyncField> ();
		for (uint i = 0; i < original.field_count; i++) {
			var field = original.field (i);
			fields.add (new NativeAsyncField (field.definition, field.block, field.position, field.abi_type));
		}
		// Both fields are I32. Local shape and balance remain valid while the
		// association with the original parameter is independently wrong.
		var first = fields[0];
		var third = fields[2];
		fields[0] = new NativeAsyncField (third.definition, first.block, first.position, first.abi_type);
		fields[2] = new NativeAsyncField (first.definition, third.block, third.position, third.abi_type);
		var states = new GenericArray<NativeAsyncState> ();
		for (uint i = 0; i < original.state_count; i++) {
			states.add (original.state (i));
		}
		native.async_frames[0] = new NativeAsyncFramePlan (original.function_ordinal, original.declaration, original.result, fields, states);
		NativeAbiVerifier.verify (native);
		bool rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			rejected = error.message.contains ("original definition/type/site");
		}
		assert (rejected);
		native.async_frames[0] = original;
		LlvmLowering.lower (ssa, native, foreign).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void dispatcher_correspondence() {
	try {
		var ssa = build (body ());
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		var dispatch = artifact.async_frames[0].dispatcher ();
		var first = CApi.operand (dispatch, 2);
		var second = CApi.operand (dispatch, 3);
		CApi.set_operand (dispatch, 2, second);
		CApi.set_operand (dispatch, 3, first);
		generic_valid (artifact);
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			rejected = error.message.contains ("different source state");
		}
		assert (rejected);
		CApi.set_operand (dispatch, 2, first);
		CApi.set_operand (dispatch, 3, second);
		artifact.verify ();
		generic_valid (artifact);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void runtime_correspondence() {
	try {
		SsaProgram? ssa = build (body ());
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		var helper = CApi.named_function (artifact.module, "astra_async_data");
		assert (CApi.count_basic_blocks (helper) == 0);
		var block = CApi.append_basic_block_in_context (artifact.context, helper, "forged.provider");
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, block);
		CApi.build_ret (builder, CApi.const_null (CApi.pointer_type_in_context (artifact.context, 0)));
		CApi.dispose_builder (builder);
		generic_valid (artifact);
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			rejected = error.message.contains ("external provider identity");
		}
		assert (rejected);
		CApi.delete_basic_block (block);
		artifact.verify ();
		generic_valid (artifact);
		ssa = build ("export(C) void* astra_async_data(void* task){return task;}" + body ());
		native = NativeAbiBuilder.build (ssa);
		rejected = false;
		try {
			LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		} catch (LlvmError error) {
			rejected = error.message.contains ("astra_async_data") && error.message.contains ("conflicts with a native implementation");
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void unsupported_consumers() {
	foreach (var text in new string[] { "int main(){await delay_ticks(1);return 0;}", "async void f(){await delay_ticks(-1);}", "async void f(){await delay_ticks(1.5);}", "async void f(){}int main(){var task=f();var duplicate=task;return 0;}", "async void f(){}int main(){f();return 0;}", "void delay_ticks(u32 n){}async void f(){await delay_ticks(1);}" }) {
		var parsed = Parser.parse (new SourceFile.from_text ("negative.astra", support () + text));
		assert (parsed.diagnostic == null);
		assert (SemanticAnalyzer.analyze (parsed.unit).diagnostic != null);
	}
}

private void started_obligations() {
	try {
		foreach (var text in new string[] { "async void child() throws Error {await delay_ticks(1);}async void shortened() throws Error {var task=child();start(task);throw new AsyncError(\"lost sibling\");}int main(){return 42;}", "async void child() throws Error {await delay_ticks(1);}async void lost() throws Error {var task=child();start(task);return;}int main(){return 42;}", "async void child(){}async void twice(){var task=child();await move task;await move task;}int main(){return 42;}" }) {
			var parsed = Parser.parse (new SourceFile.from_text ("task-obligations.astra", support () + text));
			assert (parsed.diagnostic == null);
			var checked = SemanticAnalyzer.analyze (parsed.unit);
			if (checked.diagnostic != null) {
				assert (text.contains ("twice"));
				Test.message ("R1 repeated move: Semantic: %s", checked.diagnostic.message);
				continue;
			}
			var cfg = CfgBuilder.build (CoreBuilder.build (checked.program));
			var flow = CfgFlowChecker.check (cfg);
			assert (flow.diagnostic != null);
			Test.message ("R1 unjoined started exit: CFG source flow: %s", flow.diagnostic.message);
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void capture_correspondence() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("capture-correspondence.astra", support () + body ()));
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var core = CoreBuilder.build (checked.program);
		bool tested = false;
		foreach (var function in core.functions) {
			foreach (var statement in function.body.statements) {
				var initialization = statement as CoreInitialize;
				var task = initialization == null ? null : initialization.value as CoreTaskCreate;
				if (task == null) {
					continue;
				}
				var first = task.arguments[0];
				var third = task.arguments[2];
				assert (first.semantic_type == third.semantic_type);
				task.arguments[0] = third;
				task.arguments[2] = first;
				bool rejected = false;
				try {
					CoreVerifier.verify (core);
				} catch (CoreError error) {
					rejected = error.message.contains ("task creation requires exact");
				}
				assert (rejected);
				task.arguments[0] = first;
				task.arguments[2] = third;
				CoreVerifier.verify (core);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		var cfg = CfgBuilder.build (core);
		tested = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var task = instruction as CfgTaskCreate;
					if (task == null) {
						continue;
					}
					var first = task.arguments[0];
					var third = task.arguments[2];
					assert (first.semantic_type == third.semantic_type);
					task.arguments[0] = third;
					task.arguments[2] = first;
					bool rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						rejected = error.message.contains ("task creation requires exact");
					}
					assert (rejected);
					task.arguments[0] = first;
					task.arguments[2] = third;
					CfgVerifier.verify (cfg);
					tested = true;
					break;
				}
				if (tested) {
					break;
				}
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
		var ssa = SsaBuilder.build (cfg);
		tested = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var task = instruction as SsaTaskCreate;
					if (task == null) {
						continue;
					}
					var first = task.arguments[0];
					var third = task.arguments[2];
					assert (first.semantic_type == third.semantic_type);
					task.arguments[0] = third;
					task.arguments[2] = first;
					bool rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						rejected = error.message.contains ("task creation lost exact");
					}
					assert (rejected);
					task.arguments[0] = first;
					task.arguments[2] = third;
					SsaVerifier.verify (ssa);
					tested = true;
					break;
				}
				if (tested) {
					break;
				}
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void owner_correspondence() {
	try {
		SsaProgram? ssa = build (await_body ());
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		CAbiProgram? foreign = CAbiBuilder.build (ssa, native);
		var original = native.async_frames[2];
		assert (original.owner_count >= 2);
		var owners = new GenericArray<NativeAsyncOwner> ();
		for (uint o = 0; o < original.owner_count; o++) {
			var owner = original.owner (o);
			owners.add (new NativeAsyncOwner (owner.ordinal, owner.source_ordinal, owner.class_ordinal, owner.catch_owner));
		}
		var first = owners[0];
		var second = owners[1];
		owners[0] = new NativeAsyncOwner (first.ordinal, second.source_ordinal, first.class_ordinal, first.catch_owner);
		owners[1] = new NativeAsyncOwner (second.ordinal, first.source_ordinal, second.class_ordinal, second.catch_owner);
		var fields = new GenericArray<NativeAsyncField> ();
		for (uint f = 0; f < original.field_count; f++) {
			fields.add (original.field (f));
		}
		var states = new GenericArray<NativeAsyncState> ();
		for (uint s = 0; s < original.state_count; s++) {
			states.add (original.state (s));
		}
		var buffers = new GenericArray<NativeAsyncBuffer> ();
		for (uint b = 0; b < original.buffer_count; b++) {
			buffers.add (original.buffer (b));
		}
		native.async_frames[2] = new NativeAsyncFramePlan (original.function_ordinal, original.declaration, original.result, fields, states, original.object_count, original.owner_count, buffers, owners);
		NativeAbiVerifier.verify (native);
		bool rejected = false;
		try {
			LlvmLowering.lower (ssa, native, foreign);
		} catch (LlvmError error) {
			rejected = error.message.contains ("original local/catch/class");
		}
		assert (rejected);
		native.async_frames[2] = original;
		var predecessor = WeakRef (ssa.functions[2]);
		var artifact = LlvmLowering.lower (ssa, native, foreign);
		ssa = null;
		native = null;
		foreign = null;
		assert (predecessor.get () == null);
		artifact.verify ();
		bool tested = false;
		foreach (var frame in artifact.async_frames) {
			for (uint o = 0; o < frame.owner_write_count; o++) {
				var stored = frame.owner_write (o);
				var value = CApi.operand (stored, 0);
				var empty = CApi.const_null (CApi.type_of (value));
				if ((void*) value == (void*) empty) {
					continue;
				}
				CApi.set_operand (stored, 0, empty);
				generic_valid (artifact);
				rejected = false;
				try {
					artifact.verify ();
				} catch (LlvmError error) {
					rejected = error.message.contains ("exact frame owner acquisition");
				}
				assert (rejected);
				CApi.set_operand (stored, 0, value);
				artifact.verify ();
				generic_valid (artifact);
				tested = true;
				break;
			}
			if (tested) {
				break;
			}
		}
		assert (tested);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private NativeAsyncFramePlan copied_frame(NativeAsyncFramePlan original, GenericArray<NativeAsyncOwner>? replacement_owners = null, GenericArray<NativeAsyncBuffer>? replacement_buffers = null, GenericArray<NativeAsyncLoan>? replacement_loans = null, GenericArray<NativeAsyncWait>? replacement_waits = null, GenericArray<NativeAsyncEnumStorage>? replacement_enums = null, NativeStructValuePlan? replacement_result = null, GenericArray<NativeAsyncState>? replacement_states = null) {
	var fields = new GenericArray<NativeAsyncField> ();
	for (uint i = 0; i < original.field_count; i++) {
		fields.add (original.field (i));
	}
	var states = new GenericArray<NativeAsyncState> ();
	for (uint i = 0; i < original.state_count; i++) {
		states.add (original.state (i));
	}
	var owners = new GenericArray<NativeAsyncOwner> ();
	for (uint i = 0; i < original.owner_count; i++) {
		owners.add (original.owner (i));
	}
	var buffers = new GenericArray<NativeAsyncBuffer> ();
	for (uint i = 0; i < original.buffer_count; i++) {
		buffers.add (original.buffer (i));
	}
	var storage = new GenericArray<NativeAsyncStorage> ();
	for (uint i = 0; i < original.storage_count; i++) {
		storage.add (original.storage_slot (i));
	}
	var enums = new GenericArray<NativeAsyncEnumStorage> ();
	for (uint i = 0; i < original.enum_count; i++) {
		enums.add (original.enum_slot (i));
	}
	var loans = new GenericArray<NativeAsyncLoan> ();
	for (uint i = 0; i < original.loan_count; i++) {
		loans.add (original.loan (i));
	}
	var waits = new GenericArray<NativeAsyncWait> ();
	for (uint i = 0; i < original.wait_count; i++) {
		waits.add (original.wait (i));
	}
	return new NativeAsyncFramePlan (original.function_ordinal, original.declaration, original.result, fields, replacement_states ?? states, original.object_count, original.owner_count, replacement_buffers ?? buffers, replacement_owners ?? owners, storage, replacement_enums ?? enums, replacement_result ?? original.record_result, replacement_loans ?? loans, replacement_waits ?? waits);
}

private void wrong_plan(string name, SsaProgram ssa, NativeAbiProgram native, int ordinal, NativeAsyncFramePlan wrong, string diagnostic, string native_diagnostic = "") throws GLib.Error {
	var original = native.async_frames[ordinal];
	var foreign = CAbiBuilder.build (ssa, native);
	LlvmLowering.lower (ssa, native, foreign).verify ();
	native.async_frames[ordinal] = wrong;
	bool rejected = false;
	if (native_diagnostic == "") {
		NativeAbiVerifier.verify (native);
	} else {
		wrong.verify ();
		try {
			NativeAbiVerifier.verify (native);
		} catch (NativeAbiError error) {
			rejected = error.message.contains (native_diagnostic);
		}
		assert (rejected);
		rejected = false;
		try {
			NativeAsyncFrameBuilder.validate (wrong, ssa.functions[wrong.function_ordinal], ssa);
		} catch (NativeAbiError error) {
			rejected = error.message.contains (diagnostic);
		}
		assert (rejected);
		rejected = false;
	}
	try {
		LlvmLowering.lower (ssa, native, foreign);
	} catch (LlvmError error) {
		Test.message ("R1 %s: Native/source correspondence: %s", name, error.message);
		rejected = error.message.contains (native_diagnostic == "" ? diagnostic : native_diagnostic);
	} catch (NativeAbiError error) {
		rejected = native_diagnostic != "" && error.message.contains (native_diagnostic);
	}
	assert (rejected);
	native.async_frames[ordinal] = original;
	var restored = LlvmLowering.lower (ssa, native, foreign);
	restored.verify ();
	generic_valid (restored);
}

private void loan_stage_correspondence() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("loan-stages.astra", support () + loan_body ()));
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var core = CoreBuilder.build (checked.program);
		bool tested = false;
		foreach (var function in core.functions) {
			foreach (var statement in function.body.statements) {
				var initialization = statement as CoreInitialize;
				var wait = initialization == null ? null : initialization.value as CoreTaskAwait;
				var creation = wait == null ? null : wait.child as CoreTaskCreate;
				if (creation == null || creation.loans.length != 2) {
					continue;
				}
				var original = creation.loans[0];
				creation.loans[0] = new CoreSuspensionLoan (original.identity, original.parameter_ordinal, original.storage, creation.loans[1].view);
				bool rejected = false;
				try {
					CoreVerifier.verify (core);
				} catch (CoreError error) {
					Test.message ("R1 loan view: Core: %s", error.message);
					rejected = error.message.contains ("suspension loan lost exact");
				}
				assert (rejected);
				creation.loans[0] = original;
				CoreVerifier.verify (core);
				tested = true;
			}
		}
		assert (tested);
		var cfg = CfgBuilder.build (core);
		tested = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var creation = instruction as CfgTaskCreate;
					if (creation == null || creation.loans.length != 2) {
						continue;
					}
					var original = creation.loans[0];
					creation.loans[0] = new CfgSuspensionLoan (original.identity, original.parameter_ordinal, original.storage, creation.loans[1].view);
					bool rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						Test.message ("R1 loan view: CFG: %s", error.message);
						rejected = error.message.contains ("suspension loan lost exact");
					}
					assert (rejected);
					creation.loans[0] = original;
					CfgVerifier.verify (cfg);
					tested = true;
				}
			}
		}
		assert (tested);
		var ssa = SsaBuilder.build (cfg);
		tested = false;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var creation = instruction as SsaTaskCreate;
					if (creation == null || creation.loans.length != 2) {
						continue;
					}
					var original = creation.loans[0];
					creation.loans[0] = new SsaSuspensionLoan (original.identity, original.parameter_ordinal, original.storage, creation.loans[1].view);
					bool rejected = false;
					try {
						SsaVerifier.verify (ssa);
					} catch (SsaError error) {
						Test.message ("R1 loan view: SSA: %s", error.message);
						rejected = error.message.contains ("suspension loan lost exact");
					}
					assert (rejected);
					creation.loans[0] = original;
					SsaVerifier.verify (ssa);
					tested = true;
				}
			}
		}
		assert (tested);
		var native = NativeAbiBuilder.build (ssa);
		LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native)).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void completion_correspondence() {
	try {
		var scalar = build (body ());
		var scalar_native = NativeAbiBuilder.build (scalar);
		var alternative = build (body ().replace ("value=value+step", "value=value-step"));
		var alternative_native = NativeAbiBuilder.build (alternative);
		NativeAbiVerifier.verify (alternative_native);
		LlvmLowering.lower (alternative, alternative_native, CAbiBuilder.build (alternative, alternative_native)).verify ();
		wrong_plan ("separately-valid-body", scalar, scalar_native, 0, alternative_native.async_frames[0], "source correspondence");
		var resources = build (resource_body (), resource_api ());
		var native = NativeAbiBuilder.build (resources);
		var frame = native.async_frames[0];
		var owners = new GenericArray<NativeAsyncOwner> ();
		for (uint i = 0; i < frame.owner_count; i++) {
			var old = frame.owner (i);
			int capture = i == 0 ? frame.owner (1).capture_first_leaf : i == 1 ? frame.owner (0).capture_first_leaf : old.capture_first_leaf;
			owners.add (new NativeAsyncOwner (old.ordinal, old.source_ordinal, old.class_ordinal, old.catch_owner, old.cleanup_symbol, capture, old.cleanup_position));
		}
		wrong_plan ("balanced-Resource-captures", resources, native, 0, copied_frame (frame, owners), "original local/catch/class");
		owners = new GenericArray<NativeAsyncOwner> ();
		for (uint i = 0; i < frame.owner_count; i++) {
			owners.add (frame.owner (i));
		}
		owners[0] = new NativeAsyncOwner (frame.owner (0).ordinal, frame.owner (0).source_ordinal, -1, false, "different_resource_cleanup", frame.owner (0).capture_first_leaf, frame.owner (0).cleanup_position);
		wrong_plan ("declared-Resource-cleanup", resources, native, 0, copied_frame (frame, owners), "original local/catch/class");
		var buffers = build (buffer_body ());
		native = NativeAbiBuilder.build (buffers);
		frame = native.async_frames[4];
		assert (frame.buffer_count == 2);
		var groups = new GenericArray<NativeAsyncBuffer> ();
		for (uint i = 0; i < frame.buffer_count; i++) {
			var old = frame.buffer (i);
			groups.add (new NativeAsyncBuffer (old.ordinal, old.owner_ordinal, old.element, frame.buffer (1 - i).capture_first_leaf, old.cleanup_position));
		}
		wrong_plan ("balanced-buffer-captures", buffers, native, 4, copied_frame (frame, null, groups), "complete element/owner/storage");
		var loans = build (loan_body ());
		native = NativeAbiBuilder.build (loans);
		frame = native.async_frames[1];
		assert (frame.loan_count == 2 && frame.wait_count == 1);
		var sealed = new GenericArray<NativeAsyncLoan> ();
		for (uint i = 0; i < frame.loan_count; i++) {
			var old = frame.loan (i);
			sealed.add (new NativeAsyncLoan (old.identity, old.block, old.creation_position, old.wait_position, old.child_definition, old.child_body, old.parameter_ordinal, frame.loan (1 - i).view_definition, old.storage_ordinal));
		}
		wrong_plan ("distinct-same-root-loan-views", loans, native, 1, copied_frame (frame, null, null, sealed), "original view/child/direct wait/parent storage");
		sealed[0] = new NativeAsyncLoan (new SuspensionLoanIdentity (), frame.loan (0).block, frame.loan (0).creation_position, frame.loan (0).wait_position, frame.loan (0).child_definition, frame.loan (0).child_body, frame.loan (0).parameter_ordinal, frame.loan (0).view_definition, frame.loan (0).storage_ordinal);
		wrong_plan ("independent-loan-identity", loans, native, 1, copied_frame (frame, null, null, sealed), "original view/child/direct wait/parent storage");
		var waits = new GenericArray<NativeAsyncWait> ();
		var wait = frame.wait (0);
		var leaves = new GenericArray<int> ();
		for (uint i = 0; i < wait.leaf_count; i++) {
			leaves.add (wait.leaf (i));
		}
		waits.add (new NativeAsyncWait (wait.block, wait.position, wait.exception_definition, wait.child_definition, wait.discard, wait.identity, leaves, wait.enum_ordinal, wait.enum_instance));
		wrong_plan ("pending-child-right", loans, native, 1, copied_frame (frame, null, null, null, waits), "original child/right/exception/result");
		var results = build (result_body ());
		native = NativeAbiBuilder.build (results);
		frame = native.async_frames[0];
		var returned = frame.record_result;
		var channels = new GenericArray<NativeStructLeafChannel> ();
		foreach (var leaf in returned.leaves) {
			channels.add (leaf);
		}
		var wrong_result = new NativeStructValuePlan (returned.struct_ordinal, "DifferentRecord", channels, returned.result_carrier);
		wrong_plan ("same-layout-record-result", results, native, 0, copied_frame (frame, null, null, null, null, null, wrong_result), "complete original carrier or cleanup correspondence", "frame result differs from the exact declared carrier");
		frame = native.async_frames[3];
		var slots = new GenericArray<NativeAsyncEnumStorage> ();
		for (uint i = 0; i < frame.enum_count; i++) {
			var old = frame.enum_slot (i);
			slots.add (new NativeAsyncEnumStorage (old.ordinal, old.source_ordinal, old.capture_first_leaf, old.inspection_root, old.reservation_source, old.identity, old.instance, i == 0 ? !old.owning : old.owning, old.cleanup_position));
		}
		wrong_plan ("owning-active-carrier", results, native, 3, copied_frame (frame, null, null, null, null, slots), "nominal/instance/capture/owner");
		frame = native.async_frames[2];
		var record_buffers = new GenericArray<NativeAsyncBuffer> ();
		for (uint b = 0; b < frame.buffer_count; b++) {
			var old = frame.buffer (b);
			var element = old.record_element;
			assert (element != null);
			record_buffers.add (new NativeAsyncBuffer.for_record (old.ordinal, old.owner_ordinal, new NativeRecordElement (element.struct_ordinal, "WrongRecord", element.fields), old.capture_first_leaf, old.cleanup_position));
		}
		wrong_plan ("record-element-plan", results, native, 2, copied_frame (frame, null, record_buffers), "complete element/owner/storage");
		var loop = build (body ());
		var loop_native = NativeAbiBuilder.build (loop);
		frame = loop_native.async_frames[0];
		var wrong_states = new GenericArray<NativeAsyncState> ();
		for (uint state = 0; state < frame.state_count; state++) {
			var old = frame.state (state);
			var fields = new GenericArray<int> ();
			for (uint f = 0; f < old.initialized_count; f++) {
				if (state != 1 || f != old.initialized_count - 1) {
					fields.add (old.initialized_field (f));
				}
			}
			wrong_states.add (new NativeAsyncState (old.pc, old.block, old.position, fields));
		}
		wrong_plan ("loop-initialized-state", loop, loop_native, 0, copied_frame (frame, null, null, null, null, null, null, wrong_states), "initialized field correspondence");
		CAbiProgram? foreign = CAbiBuilder.build (results, native);
		var predecessor = WeakRef (results.functions[0]);
		var artifact = LlvmLowering.lower (results, native, foreign);
		results = null;
		native = null;
		foreign = null;
		assert (predecessor.get () == null);
		artifact.verify ();
		generic_valid (artifact);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private CApi.ValueRef named_call(LlvmModuleArtifact artifact, string symbol, int permission = -1) {
	for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) CApi.named_function (artifact.module, symbol) && (permission < 0 || CApi.const_int_zext (CApi.operand (instruction, 1)) == permission)) {
					return instruction;
				}
			}
		}
	}
	assert_not_reached ();
}

private CApi.ValueRef named_instruction(LlvmModuleArtifact artifact, string prefix) {
	foreach (var binding in artifact.class_values) {
		size_t length;
		if (CApi.value_name (binding.instruction, out length) == prefix) {
			return binding.instruction;
		}
	}
	assert_not_reached ();
}

private void wrong_llvm(LlvmModuleArtifact artifact, string name, string diagnostic) {
	generic_valid (artifact);
	bool rejected = false;
	try {
		artifact.verify ();
	} catch (LlvmError error) {
		Test.message ("R1 %s: LLVM-valid concrete correspondence: %s", name, error.message);
		rejected = error.message.contains (diagnostic);
	}
	assert (rejected);
}

private void completion_llvm() {
	try {
		var ssa = build (loan_body ());
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		var wait = named_call (artifact, "astra_async_wait");
		var parent = CApi.operand (wait, 0);
		var child = CApi.operand (wait, 1);
		CApi.set_operand (wait, 1, parent);
		wrong_llvm (artifact, "pending-waiter-child", "intended receiver/input/success/cleanup channel");
		CApi.set_operand (wait, 1, child);
		artifact.verify ();
		generic_valid (artifact);
		var release = named_call (artifact, "astra_async_release_wait", 1);
		var permission = CApi.operand (release, 1);
		CApi.set_operand (release, 1, CApi.const_null (CApi.type_of (permission)));
		wrong_llvm (artifact, "observation-transfer-permission", "protocol operation");
		CApi.set_operand (release, 1, permission);
		artifact.verify ();
		generic_valid (artifact);
		ssa = build (result_body ());
		native = NativeAbiBuilder.build (ssa);
		artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		var code = artifact.async_frames[0].resume;
		CApi.ValueRef publication = (CApi.ValueRef) (void*) null;
		CApi.ValueRef store = (CApi.ValueRef) (void*) null;
		for (var block = CApi.first_block (code); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE) {
					store = instruction;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) CApi.named_function (artifact.module, "astra_async_complete") && CApi.const_int_zext (CApi.operand (instruction, 1)) == 5) {
					publication = instruction;
					break;
				}
			}
			if ((void*) publication != null) {
				break;
			}
		}
		assert ((void*) publication != null && (void*) store != null);
		var next = CApi.next_instruction (publication);
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.remove_instruction (publication);
		CApi.position_builder_before (builder, store);
		CApi.insert_instruction (builder, publication);
		wrong_llvm (artifact, "success-before-initialization", "coroutine return lacks actual completion");
		CApi.remove_instruction (publication);
		CApi.position_builder_before (builder, next);
		CApi.insert_instruction (builder, publication);
		artifact.verify ();
		generic_valid (artifact);
		var orphan = CApi.append_basic_block_in_context (artifact.context, code, "unreachable.publication");
		CApi.remove_instruction (publication);
		CApi.position_builder_at_end (builder, orphan);
		CApi.insert_instruction (builder, publication);
		CApi.build_ret_void (builder);
		wrong_llvm (artifact, "missing-reachable-publication", "coroutine return lacks actual completion");
		CApi.remove_instruction (publication);
		CApi.position_builder_before (builder, next);
		CApi.insert_instruction (builder, publication);
		CApi.delete_basic_block (orphan);
		artifact.verify ();
		generic_valid (artifact);
		CApi.dispose_builder (builder);
		foreach (var prefix in new string[] { "task.buffer.success.base", "task.buffer.success", "task.record.leaf" }) {
			var component = named_instruction (artifact, prefix);
			var saved = CApi.operand (component, 1);
			CApi.set_operand (component, 1, CApi.const_null (CApi.type_of (saved)));
			wrong_llvm (artifact, prefix, "complete task result group");
			CApi.set_operand (component, 1, saved);
			artifact.verify ();
			generic_valid (artifact);
		}
		var duplicate_builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_before (duplicate_builder, publication);
		var duplicate_arguments = new CApi.ValueRef[CApi.argument_count (publication)];
		for (uint a = 0; a < duplicate_arguments.length; a++) {
			duplicate_arguments[a] = CApi.operand (publication, a);
		}
		var duplicate = CApi.build_call (duplicate_builder, CApi.called_function_type (publication), CApi.called_value (publication), duplicate_arguments, duplicate_arguments.length, "");
		CApi.set_instruction_call_conv (duplicate, CApi.instruction_call_conv (publication));
		wrong_llvm (artifact, "duplicate-publication", "unplanned effect");
		CApi.remove_instruction (duplicate);
		var unused = CApi.append_basic_block_in_context (artifact.context, code, "unused.duplicate");
		CApi.position_builder_at_end (duplicate_builder, unused);
		CApi.insert_instruction (duplicate_builder, duplicate);
		CApi.build_ret_void (duplicate_builder);
		CApi.delete_basic_block (unused);
		CApi.dispose_builder (duplicate_builder);
		artifact.verify ();
		generic_valid (artifact);
		var destructor = artifact.async_frames[3].destroy;
		bool bypassed = false;
		for (var block = CApi.first_block (destructor); (void*) block != null && !bypassed; block = CApi.next_block (block)) {
			var branch = CApi.block_terminator (block);
			if (CApi.successor_count (branch) != 2) {
				continue;
			}
			var wanted = CApi.successor (branch, 0);
			var skipped = CApi.successor (branch, 1);
			CApi.set_successor (branch, 0, skipped);
			wrong_llvm (artifact, "missing-active-cleanup", "prerequisite control edge");
			CApi.set_successor (branch, 0, wanted);
			artifact.verify ();
			generic_valid (artifact);
			bypassed = true;
		}
		assert (bypassed);
		ssa = build (resource_body (), resource_api ());
		native = NativeAbiBuilder.build (ssa);
		artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		var cleanup = named_call (artifact, "close_resource");
		var owner = CApi.operand (cleanup, 0);
		CApi.set_operand (cleanup, 0, CApi.const_null (CApi.type_of (owner)));
		wrong_llvm (artifact, "Resource-cleanup-owner", "cleanup");
		CApi.set_operand (cleanup, 0, owner);
		artifact.verify ();
		generic_valid (artifact);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void creation_commit_abort_correspondence() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("task-argument-authority.astra", support () + buffer_body ()));
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var cfg = CfgBuilder.build (CoreBuilder.build (checked.program));
		int commits = 0;
		int aborts = 0;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var commit = block.instructions[i] as CfgOwnedCallTransferCommit;
					var abort = block.instructions[i] as CfgOwnedArgumentAbort;
					if ((commit == null || !(commit.call is CfgTaskCreate)) && abort == null) {
						continue;
					}
					var original = block.instructions[i];
					block.instructions.remove_index (i);
					bool rejected = false;
					try {
						CfgVerifier.verify (cfg);
					} catch (CfgError error) {
						Test.message ("R1 missing creation %s: CFG: %s", commit == null ? "abort" : "commit", error.message);
						rejected = true;
					}
					assert (rejected);
					block.instructions.insert (i, original);
					CfgVerifier.verify (cfg);
					block.instructions.insert (i + 1, original);
					rejected = false;
					try {
						CfgVerifier.verify (cfg);
						OwnershipFlow.analyze (function);
					} catch (CfgError error) {
						Test.message ("R1 duplicate creation %s: CFG structure/ownership flow: %s", commit == null ? "abort" : "commit", error.message);
						rejected = true;
					}
					assert (rejected);
					block.instructions.remove_index (i + 1);
					CfgVerifier.verify (cfg);
					if (commit != null) {
						commits++;
					} else {
						aborts++;
					}
				}
			}
		}
		assert (commits > 0 && aborts > 0);
		var ssa = SsaBuilder.build (cfg);
		var native = NativeAbiBuilder.build (ssa);
		LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native)).verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void suspended_message_correspondence() {
	try {
		var ssa = build (resource_body (), resource_api ());
		SsaVerifier.verify (ssa);
		int catches = 0;
		int loans = 0;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				for (int i = 0; i < block.instructions.length; i++) {
					var event = block.instructions[i] as SsaFrameCatchEvent;
					if (event != null && !(event.source is SsaNullPointerConstant)) {
						block.instructions[i] = new SsaFrameCatchEvent (event.span, event.owner, new SsaNullPointerConstant (event.span, event.owner.semantic_type));
						bool rejected = false;
						try {
							SsaVerifier.verify (ssa);
						} catch (SsaError error) {
							Test.message ("R1 suspended catch source %d: SSA: %s", catches, error.message);
							rejected = error.message.contains ("catch");
						}
						assert (rejected);
						block.instructions[i] = event;
						SsaVerifier.verify (ssa);
						catches++;
					}
					var binding = block.instructions[i] as SsaTextLoanBind;
					if (function.async_body != null && binding != null) {
						block.instructions[i] = new SsaTextLoanBind (binding.span, binding.loan, binding.value, new Astra.Text.TextLoanIntent (new GenericArray<Object> ()));
						bool rejected = false;
						try {
							SsaVerifier.verify (ssa);
						} catch (SsaError error) {
							Test.message ("R1 suspended message loan %d: SSA: %s", loans, error.message);
							rejected = error.message.contains ("receiver association");
						}
						assert (rejected);
						block.instructions[i] = binding;
						SsaVerifier.verify (ssa);
						loans++;
					}
				}
			}
		}
		assert (catches > 0 && loans > 0);
		var native = NativeAbiBuilder.build (ssa);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		artifact.verify ();
		generic_valid (artifact);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void loan_diagnostics() {
	string child = "async int child(int[] values) throws Error {await delay_ticks(1);return values[0];}";
	string[] sources = {
		"async void parent() throws Error {int[2] values={20,22};var task=child(slice(values));await move task;}", "async void parent() throws Error {int[2] values={20,22};var task=child(slice(values));start(task);await move task;}", "async void parent(int[] values) throws Error {int value=await child(values);}", "async void parent() throws Error {int[2] values={20,22};var alias=slice(values);int value=await child(slice(values));}", "async void parent() throws Error {int[2] values={20,22};int value=await child(slice(values));var alias=slice(values);}"
	};
	for (int i = 0; i < sources.length; i++) {
		var parsed = Parser.parse (new SourceFile.from_text ("loan-negative.astra", support () + child + sources[i] + "int main(){return 42;}"));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic != null && checked.diagnostic.message.contains (i == 4 ? "sealed parent-local backing" : "borrowed async capture"));
		Test.message ("R1 loan source negative %d: Semantic: %s", i, checked.diagnostic.message);
	}
	foreach (var text in new string[] { "struct Holder{Task value;}int main(){return 42;}", "void escaped(Task value){}int main(){return 42;}", "Task escaped(){return 0;}int main(){return 42;}", "async string text(){return \"borrow\";}int main(){return 42;}", "async int* pointer(){return null;}int main(){return 42;}", "async int[] borrowed_result(){int[2] local={20,22};return slice(local);}int main(){return 42;}", "async owned Error object_result(){return new AsyncError(\"x\");}int main(){return 42;}", "async Error object_result(){return new AsyncError(\"x\");}int main(){return 42;}" }) {
		var parsed = Parser.parse (new SourceFile.from_text ("excluded-source.astra", support () + text));
		assert (parsed.diagnostic == null);
		var checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic != null && (checked.diagnostic.message.contains ("Task fields, parameters and return escapes") || checked.diagnostic.message.contains ("async success requires")));
		Test.message ("R1 excluded source: Semantic: %s", checked.diagnostic.message);
	}
	var resource = Parser.parse (new SourceFile.from_text ("excluded-resource.astra", support () + "async owned Resource resource_result(){return open_resource(1);}int main(){return 42;}"));
	var api = VapiParser.parse (new SourceFile.from_text ("excluded-resource.vapi", resource_api ()));
	assert (resource.diagnostic == null && api.diagnostic == null);
	var checked_resource = SemanticAnalyzer.analyze (resource.unit, VapiNormalizer.normalize (api.file), VapiNormalizer.normalize_handles (api.file));
	assert (checked_resource.diagnostic != null && checked_resource.diagnostic.message.contains ("async success requires"));
	Test.message ("R1 Resource result: Semantic: %s", checked_resource.diagnostic.message);
	foreach (var form in new string[] { "async int generic<T>(){return 0;}", "extern(C)async void foreign();", "async extern(C)void foreign();", "export(C)async void foreign(){}", "class C{virtual async void member(){}}", "class C{override async void member(){}}" }) {
		var rejected = Parser.parse (new SourceFile.from_text ("excluded-form.astra", form));
		assert (rejected.diagnostic != null && (rejected.diagnostic.message.contains ("async foreign") || rejected.diagnostic.message.contains ("generic async") || rejected.diagnostic.message.contains ("async methods")));
		Test.message ("R1 excluded declaration: Parser: %s", rejected.diagnostic.message);
	}
	var missing_move = Parser.parse (new SourceFile.from_text ("named-await.astra", support () + "async int child()throws Error{return 42;}async void parent()throws Error{var task=child();int value=await task;}int main(){return 42;}"));
	assert (missing_move.diagnostic == null);
	var moved = SemanticAnalyzer.analyze (missing_move.unit);
	assert (moved.diagnostic != null && moved.diagnostic.message.contains ("await consumes one exact unique task"));
	Test.message ("R1 named await: Semantic: %s", moved.diagnostic.message);
	var captured_class = Parser.parse (new SourceFile.from_text ("excluded-class-capture.astra", support () + "async void child(Error value){}int main(){return 42;}"));
	assert (captured_class.diagnostic == null);
	var captured = SemanticAnalyzer.analyze (captured_class.unit);
	assert (captured.diagnostic != null && captured.diagnostic.message.contains ("async Class captures"));
	Test.message ("R1 Class capture: Semantic: %s", captured.diagnostic.message);
	var method = Parser.parse (new SourceFile.from_text ("excluded-method.astra", "class C{async void method(){}}"));
	assert (method.diagnostic != null && method.diagnostic.message.contains ("async methods"));
	Test.message ("R1 async method: Parser: %s", method.diagnostic.message);
}

private void emit_fixture(string path, bool awaited = false, bool buffered = false, bool resource = false, bool stored = false, bool results = false, bool loaned = false) throws GLib.Error {
	var ssa = build (loaned ? loan_body () : results ? result_body () : stored ? storage_body () : resource ? resource_body () : buffered ? buffer_body () : awaited ? await_body () : body (), resource ? resource_api () : null);
	var native = NativeAbiBuilder.build (ssa);
	var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
	var builder = CApi.create_builder_in_context (artifact.context);
	// Private observer wrappers expose generated factories to the native
	// protocol harness. They add no source Task FFI or installed surface.
	foreach (var frame in artifact.async_frames) {
		// The C observers retain their original capture/parent prototype.
		// The current private native factory adds allocator/context tails.
		uint count = CApi.count_params (frame.factory);
		assert (count >= 3);
		var probe_parameters = new CApi.TypeRef[count - 2];
		for (uint p = 0; p < probe_parameters.length; p++) {
			probe_parameters[p] = CApi.type_of (CApi.get_param (frame.factory, p));
		}
		var probe_type = CApi.function_type (CApi.return_type (frame.factory_type), probe_parameters, probe_parameters.length, 0);
		var wrapper = CApi.add_function (artifact.module, "test_factory_%d".printf (frame.plan.function_ordinal), probe_type);
		CApi.set_function_call_conv (wrapper, CApi.CallConv.C);
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, wrapper, "factory.probe"));
		var arguments = new CApi.ValueRef[count];
		for (uint p = 0; p < arguments.length; p++) {
			arguments[p] = p < probe_parameters.length ? CApi.get_param (wrapper, p) : CApi.const_null (CApi.type_of (CApi.get_param (frame.factory, p)));
		}
		var created = CApi.build_call (builder, frame.factory_type, frame.factory, arguments, arguments.length, "created");
		CApi.set_instruction_call_conv (created, LlvmLowering.CALL_CONVENTION);
		CApi.build_ret (builder, created);
	}
	if (loaned) {
		var frame = artifact.async_frames[0];
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var signature = CApi.function_type (pointer, new CApi.TypeRef[] { pointer }, 1, 0);
		var wrapper = CApi.add_function (artifact.module, "test_loan_view", signature);
		CApi.set_function_call_conv (wrapper, CApi.CallConv.C);
		CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, wrapper, "actual.borrowed.capture"));
		var environment = frame.environment (builder, CApi.get_param (wrapper, 0));
		var address = frame.field_address (builder, environment, 1);
		var carrier = CApi.struct_type_at_index (frame.frame_type, 1);
		var view = CApi.build_load (builder, carrier, address, "actual.borrowed.view");
		CApi.build_ret (builder, CApi.build_extract_value (builder, view, 0, "actual.borrowed.base"));
	}
	if (results) {
		var pointer = CApi.pointer_type_in_context (artifact.context, 0);
		var signature = CApi.function_type (pointer, new CApi.TypeRef[] { pointer }, 1, 0);
		for (int kind = 0; kind < 2; kind++) {
			var frame = artifact.async_frames[kind == 0 ? 3 : 2];
			var wrapper = CApi.add_function (artifact.module, kind == 0 ? "test_owning_backing" : "test_record_backing", signature);
			CApi.set_function_call_conv (wrapper, CApi.CallConv.C);
			CApi.position_builder_at_end (builder, CApi.append_basic_block_in_context (artifact.context, wrapper, "actual.owned.capture"));
			var environment = frame.environment (builder, CApi.get_param (wrapper, 0));
			CApi.ValueRef address;
			CApi.TypeRef carrier;
			if (kind == 0) {
				LlvmSumLayout? layout = null;
				foreach (var candidate in artifact.sum_layouts) {
					if (candidate.plan.identity == frame.plan.enum_slot (0).identity) {
						layout = candidate;
					}
				}
				assert (layout != null);
				var root = frame.field_address (builder, environment, frame.enum_field (0));
				var payload = CApi.build_struct_gep (builder, layout.carrier, root, 1, "actual.active.payload");
				var variant = (CApi.TypeRef) layout.variants[0];
				address = CApi.build_struct_gep (builder, variant, payload, 0, "actual.first.buffer");
				carrier = CApi.struct_type_at_index (variant, 0);
			} else {
				uint field = frame.buffer_field (0);
				address = frame.field_address (builder, environment, field);
				carrier = CApi.struct_type_at_index (frame.frame_type, field);
			}
			var pair = CApi.build_load (builder, carrier, address, "actual.owned.pair");
			CApi.build_ret (builder, CApi.build_extract_value (builder, pair, 0, "actual.owned.base"));
		}
	}
	CApi.dispose_builder (builder);
	artifact.verify ();
	generic_valid (artifact);
	var target = new LlvmTargetMachineArtifact ();
	target.configure (artifact);
	target.emit_object (artifact, path);
}

public static int main(string[] args) {
	if (args.length == 3 && (args[1] == "--emit-fixture" || args[1] == "--emit-await-fixture" || args[1] == "--emit-buffer-fixture" || args[1] == "--emit-resource-fixture" || args[1] == "--emit-storage-fixture" || args[1] == "--emit-result-fixture" || args[1] == "--emit-loan-fixture")) {
		try {
			emit_fixture (args[2], args[1] == "--emit-await-fixture", args[1] == "--emit-buffer-fixture", args[1] == "--emit-resource-fixture", args[1] == "--emit-storage-fixture", args[1] == "--emit-result-fixture", args[1] == "--emit-loan-fixture");
			return 0;
		} catch (GLib.Error error) {
			stderr.printf ("%s\n", error.message);
			return 1;
		}
	}
	Test.init (ref args);
	Test.add_func ("/async-1/frame/creation-commit-abort-correspondence", creation_commit_abort_correspondence);
	Test.add_func ("/async-1/frame/suspended-message-correspondence", suspended_message_correspondence);
	Test.add_func ("/async-1/frame/loan-stage-correspondence", loan_stage_correspondence);
	Test.add_func ("/async-1/frame/completion-correspondence", completion_correspondence);
	Test.add_func ("/async-1/frame/completion-llvm", completion_llvm);
	Test.add_func ("/async-1/frame/loan-and-excluded-diagnostics", loan_diagnostics);
	Test.add_func ("/async-1/frame/native-resume", native_frame);
	Test.add_func ("/async-1/frame/native-correspondence", frame_correspondence);
	Test.add_func ("/async-1/frame/llvm-dispatcher", dispatcher_correspondence);
	Test.add_func ("/async-1/frame/unsupported-consumers", unsupported_consumers);
	Test.add_func ("/async-1/frame/capture-correspondence", capture_correspondence);
	Test.add_func ("/async-1/frame/owner-correspondence", owner_correspondence);
	Test.add_func ("/async-1/frame/started-obligations", started_obligations);
	Test.add_func ("/async-1/frame/runtime-correspondence", runtime_correspondence);
	return Test.run ();
}

}
