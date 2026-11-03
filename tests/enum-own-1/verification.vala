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

namespace Astra.Tests.OwningVerification {
private delegate void Check() throws GLib.Error;
[CCode (cname = "LLVMInstructionEraseFromParent", cheader_filename = "llvm-c/Core.h")]
private extern static void erase_instruction(CApi.ValueRef instruction);
private const string PAIRS = "struct Record{int x;int y;} enum Child{Ready(owned int[] data),Empty} enum Owner{Ready(owned int[] first,owned int[] second,Record record,Child left,Child right),Empty} int main(){Record r={x=7,y=9};var owner=Owner.Ready(new int[2],new int[3],r,Child.Ready(new int[4]),Child.Ready(new int[5]));match(move owner){case Owner.Ready(a,b,c,d,e):{match(move d){else:{}}match(move e){else:{}}return len(a)+len(b)+c.x+c.y-21;}else:{return 1;}}}";
private const string IGNORED = "enum Owner{Ready(owned int[] first,owned int[] second),Empty} int main(){var owner=Owner.Ready(new int[2],new int[3]);match(move owner){case Owner.Ready(a,_):{return len(a)-2;}else:{return 1;}}}";
private const string CAPTURE = "enum Owner{Ready(owned int[] data),Empty} Owner relay(Owner a){return move a;} int take(Owner a,int n){match(move a){else:{return n;}}} int main(){var a=Owner.Ready(new int[2]);var b=Owner.Ready(new int[3]);return take(move a,take(relay(move b),0));}";
private const string BRANCH = "enum Owner{Ready(owned int[] data),Empty} int f(bool selected){var a=Owner.Ready(new int[2]);if(selected){a=Owner.Empty();}else{a=Owner.Ready(new int[3]);}match(a){case Owner.Ready(v):{if(len(v)!=3){return 1;}}else:{}}return 0;} int main(){return f(true)+f(false);}";
private const string LOOP = "enum Owner{Ready(owned int[] data),Empty} int f(bool early){int n=0;while(n<4){var a=Owner.Ready(new int[2]);match(a){case Owner.Ready(v):{n=n+1;if(early){return len(v)-2;}if(n<2){continue;}if(n==3){break;}}else:{return 1;}}}return n-3;} int main(){return f(true)+f(false);}";

private void valid(string id, owned Check check) throws GLib.Error {
	check ();
	Test.message ("R1 %s control PASS", id);
}

private void invalid(string id, string diagnostic, owned Check check) throws GLib.Error {
	try {
		check ();
	} catch (GLib.Error error) {
		Test.message ("R1 %s malformed REJECT: %s", id, error.message);
		assert (error.message.contains (diagnostic));
		return;
	}
	Test.message ("R1 %s BASELINE_ACCEPTED_INVALID_MODEL", id);
	assert (Environment.get_variable ("ASTRA_ENUM_R1_BASELINE") == "1");
}

private CoreProgram core(string text) throws GLib.Error {
	ParseResult? parsed = Parser.parse (new SourceFile.from_text ("enum-own-r1.astra", text));
	assert (parsed.diagnostic == null);
	SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
	if (checked.diagnostic != null) {
		GLib.error ("probe construction: %s", checked.diagnostic.message);
	}
	var upstream = WeakRef (checked.program.functions[0]);
	var result = CoreBuilder.build (checked.program);
	checked = null;
	parsed = null;
	assert (upstream.get () == null);
	CoreVerifier.verify (result);
	return result;
}

private CfgProgram cfg(string text) throws GLib.Error {
	CoreProgram? input = core (text);
	var upstream = WeakRef (input.functions[0]);
	var result = CfgBuilder.build (input);
	input = null;
	assert (upstream.get () == null);
	CfgVerifier.verify (result);
	return result;
}

private SsaProgram ssa(string text) throws GLib.Error {
	CfgProgram? input = cfg (text);
	var upstream = WeakRef (input.functions[0]);
	var result = SsaBuilder.build (input);
	input = null;
	assert (upstream.get () == null);
	SsaVerifier.verify (result);
	return result;
}

private void field_bindings() {
	try {
		var program = cfg (PAIRS);
		var buffers = new GenericArray<CfgEnumExtractBuffer> ();
		var sums = new GenericArray<CfgEnumExtractSum> ();
		CfgBlock? arm = null;
		foreach (var block in program.functions[0].blocks) {
			foreach (var instruction in block.instructions) {
				if (instruction is CfgEnumExtractBuffer) {
					buffers.add ((CfgEnumExtractBuffer) instruction);
					arm = block;
				}
				if (instruction is CfgEnumExtractSum && ((CfgEnumExtractSum) instruction).source.definition.semantic_type.identity.name == "Owner") {
					sums.add ((CfgEnumExtractSum) instruction);
				}
			}
		}
		assert (buffers.length == 2 && sums.length == 2 && arm != null);
		var a = buffers[0];
		var b = buffers[1];
		uint ai = 0, bi = 0;
		assert (arm.instructions.find (a, out ai) && arm.instructions.find (b, out bi));
		valid ("F01-CFG-before-release", () => CfgVerifier.verify (program));
		arm.instructions[ai] = new CfgEnumExtractBuffer (a.span, a.source, a.field, b.destination, a.binding);
		arm.instructions[bi] = new CfgEnumExtractBuffer (b.span, b.source, b.field, a.destination, b.binding);
		invalid ("F01-CFG-balanced-destinations", "owned enum buffer binding lost exact active field/owner correspondence", () => CfgVerifier.verify (program));
		arm.instructions[ai] = a;
		arm.instructions[bi] = b;
		valid ("F01-CFG-restored", () => CfgVerifier.verify (program));
		var d = sums[0];
		var e = sums[1];
		uint di = 0, ei = 0;
		assert (arm.instructions.find (d, out di) && arm.instructions.find (e, out ei));
		arm.instructions[di] = new CfgEnumExtractSum (d.span, d.source, e.field, d.destination, d.binding);
		arm.instructions[ei] = new CfgEnumExtractSum (e.span, e.source, d.field, e.destination, e.binding);
		invalid ("F03-CFG-nested-fields", "nested sum binding destination correspondence mismatch", () => CfgVerifier.verify (program));
		arm.instructions[di] = d;
		arm.instructions[ei] = e;
		valid ("F03-CFG-restored", () => CfgVerifier.verify (program));
		var copied = core (PAIRS.replace ("Record r={x=7,y=9};", "Record r={x=7,y=9};Record other={x=11,y=13};"));
		CoreEnumConstruct? construction = null;
		foreach (var statement in copied.functions[0].body.statements) {
			var store = statement as CoreEnumStore;
			if (store != null && store.producer is CoreEnumConstruct) {
				construction = (CoreEnumConstruct) store.producer;
			}
		}
		assert (construction != null);
		var record = construction.fields[2];
		CoreLocalPlace? other = null;
		foreach (var local in copied.functions[0].locals) {
			if (local.name == "other") {
				other = local;
			}
		}
		assert (other != null);
		construction.fields[2] = new CoreEnumFieldValue (record.span, record.field, null, new CoreStructSnapshot (record.span, other), null);
		invalid ("F03-Core-companion", "enum constructor lost intended field/operand correspondence", () => CoreVerifier.verify (copied));
		construction.fields[2] = record;
		valid ("F03-Core-restored", () => CoreVerifier.verify (copied));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void complete_pairs() {
	try {
		foreach (var text in new string[] { PAIRS, PAIRS.replace ("new int[3]", "new int[2]"), PAIRS.replace ("new int[2]", "new int[0]") }) {
			var program = ssa (text);
			var reads = new GenericArray<SsaEnumReadBuffer> ();
			var writes = new GenericArray<SsaBufferWriteInstruction> ();
			SsaBlock? arm = null;
			foreach (var block in program.functions[0].blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaEnumReadBuffer) {
						reads.add ((SsaEnumReadBuffer) instruction);
						arm = block;
					}
					if (instruction is SsaBufferWriteInstruction && !((SsaBufferWriteInstruction) instruction).pair.is_empty && reads.length > 0 && ((SsaBufferWriteInstruction) instruction).pair == reads[reads.length - 1].pair) {
						writes.add ((SsaBufferWriteInstruction) instruction);
					}
				}
			}
			assert (reads.length == 2 && writes.length == 2 && arm != null);
			var a = writes[0];
			var b = writes[1];
			uint ai = 0, bi = 0, read_index = 0;
			assert (arm.instructions.find (a, out ai));
			assert (arm.instructions.find (reads[1], out read_index));
			arm.instructions.remove_index (read_index);
			arm.instructions.insert ((int) ai, reads[1]);
			assert (arm.instructions.find (a, out ai) && arm.instructions.find (b, out bi));
			valid ("F02-SSA-before-release-both-pairs-defined", () => SsaVerifier.verify (program));
			var half = new SsaBufferPair (a.span, a.pair.shape, a.pair.base_value, b.pair.length_value);
			var changed = new SsaBufferWriteInstruction (a.span, a.place, half);
			changed.initializes = true;
			arm.instructions[ai] = changed;
			invalid ("F02-SSA-half-pair", "buffer base and length must originate as one exact complete group", () => SsaVerifier.verify (program));
			arm.instructions[ai] = a;
			valid ("F02-SSA-half-restored", () => SsaVerifier.verify (program));
			changed = new SsaBufferWriteInstruction (a.span, a.place, b.pair);
			changed.initializes = true;
			arm.instructions[ai] = changed;
			changed = new SsaBufferWriteInstruction (b.span, b.place, a.pair);
			changed.initializes = true;
			arm.instructions[bi] = changed;
			invalid ("F01-F02-SSA-whole-pairs", "owned enum buffer", () => SsaVerifier.verify (program));
			arm.instructions[ai] = a;
			arm.instructions[bi] = b;
			valid ("F01-F02-SSA-restored", () => SsaVerifier.verify (program));
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void masks() {
	try {
		var program = cfg (IGNORED);
		CfgBlock? arm = null;
		CfgEnumFinishArm? finish = null;
		uint position = 0;
		foreach (var block in program.functions[0].blocks) {
			for (uint i = 0; i < block.instructions.length; i++) {
				var found = block.instructions[i] as CfgEnumFinishArm;
				if (found != null && found.retained_count == 1) {
					arm = block;
					finish = found;
					position = i;
				}
			}
		}
		assert (arm != null && finish != null);
		var fields = new GenericArray<EnumField> ();
		fields.add (finish.field (0));
		fields.add (finish.variant.field (1));
		valid ("F04-CFG-before", () => CfgVerifier.verify (program));
		arm.instructions[position] = new CfgEnumFinishArm (finish.span, finish.source, finish.variant, fields);
		invalid ("F04-CFG-ignored-retained", "retained owning field requires exactly one complete active binding", () => CfgVerifier.verify (program));
		arm.instructions[position] = new CfgEnumFinishArm (finish.span, finish.source, finish.variant, new GenericArray<EnumField> ());
		invalid ("F04-CFG-bound-disposed", "bound owning field cannot also be disposed", () => CfgVerifier.verify (program));
		arm.instructions[position] = finish;
		valid ("F04-CFG-restored", () => CfgVerifier.verify (program));
		var all_ignored = cfg (IGNORED.replace ("(a,_)", "(_,_)").replace ("len(a)-2", "0"));
		foreach (var block in all_ignored.functions[0].blocks) {
			for (uint i = 0; i < block.instructions.length; i++) {
				var original = block.instructions[i] as CfgEnumFinishArm;
				if (original == null || original.variant == null || original.variant.identity.ordinal != 0) {
					continue;
				}
				block.instructions[i] = new CfgEnumFinishArm (original.span, original.source, original.source.definition.variant (1), new GenericArray<EnumField> ());
				invalid ("F04-CFG-inactive-disposal", "consuming arm", () => CfgVerifier.verify (all_ignored));
				block.instructions[i] = original;
				valid ("F04-CFG-inactive-restored", () => CfgVerifier.verify (all_ignored));
			}
		}
		var lowered = ssa (IGNORED.replace ("(a,_)", "(_,_)").replace ("len(a)-2", "0"));
		foreach (var block in lowered.functions[0].blocks) {
			for (uint i = 0; i < block.instructions.length; i++) {
				var original = block.instructions[i] as SsaEnumFinishArm;
				if (original == null || original.variant == null || original.variant.identity.ordinal != 0) {
					continue;
				}
				block.instructions[i] = new SsaEnumFinishArm (original.span, original.source, original.source.definition.variant (1), new GenericArray<EnumField> ());
				invalid ("F04-SSA-inactive-disposal", "consuming arm", () => SsaVerifier.verify (lowered));
				block.instructions[i] = original;
				valid ("F04-SSA-inactive-restored", () => SsaVerifier.verify (lowered));
			}
		}
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_pairs() {
	try {
		SsaProgram? source = ssa (IGNORED);
		SsaProgram? other = ssa (IGNORED.replace ("Owner", "Other"));
		var native = NativeAbiBuilder.build (source);
		var foreign = CAbiBuilder.build (source, native);
		var replacement = NativeAbiBuilder.build (other);
		var other_foreign = CAbiBuilder.build (other, replacement);
		valid ("F05-native-A-local", () => NativeAbiVerifier.verify (native));
		valid ("F05-native-B-local", () => NativeAbiVerifier.verify (replacement));
		valid ("F05-pair-A", () => LlvmLowering.lower (source, native, foreign).verify ());
		valid ("F05-pair-B", () => LlvmLowering.lower (other, replacement, other_foreign).verify ());
		invalid ("F05-wrong-valid-program", "sum plan lost exact nominal definition/variant association", () => LlvmLowering.lower (source, replacement, foreign));
		valid ("F05-restored", () => LlvmLowering.lower (source, native, foreign).verify ());
		var held = WeakRef (other.functions[0]);
		other = null;
		assert (held.get () == null);
		valid ("F18-retained-native-B", () => NativeAbiVerifier.verify (replacement));
		invalid ("F18-wrong-retained-native-B", "sum plan lost exact nominal definition/variant association", () => LlvmLowering.lower (source, replacement, foreign));
		valid ("F18-restored", () => LlvmLowering.lower (source, native, foreign).verify ());
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void generic_premises() {
	try {
		var program = core ("enum Fault{Invalid} enum ArrayResult<T,E>{Success(owned T[] value),Error(E error)} ArrayResult<T,E> relay<T,E>(ArrayResult<T,E> input){return move input;} int main(){var a=relay<int,Fault>(ArrayResult<int,Fault>.Success(new int[2]));match(move a){else:{return 0;}}}");
		var generic = program.generic_functions[0];
		var parameter = generic.type_parameters[0].semantic_type;
		valid ("F07-Core-before", () => CoreVerifier.verify (program));
		generic.element_obligations.require (parameter, GenericElementRequirements.COPY);
		invalid ("F07-Core-weakened-element", "separate copy, storage, structural zero and trivial destruction premises", () => CoreVerifier.verify (program));
		generic.element_obligations.require (parameter);
		valid ("F07-Core-restored", () => CoreVerifier.verify (program));
		var phantom = core ("enum Marker<T>{Empty} Marker<T> relay<T>(Marker<T> input){return input;} int main(){var a=relay<int>(Marker<int>.Empty());return 0;}");
		var mono = CoreGenericMonomorphizer.build (phantom);
		GenericFunctionInstance? instance = null;
		foreach (var function in mono.functions) {
			if (function.generic_instance != null) {
				instance = function.generic_instance;
			}
		}
		assert (instance != null);
		var original = instance.type_arguments[0];
		instance.type_arguments[0] = new BuiltinTypes ().u32_type;
		invalid ("F08-Core-phantom-key", "canonical", () => CoreVerifier.verify (mono));
		instance.type_arguments[0] = original;
		valid ("F08-Core-restored", () => CoreVerifier.verify (mono));
		var nested = core ("enum Inner<T>{Ready(owned T[] data),Empty} enum Outer<T>{Child(Inner<T> child),Empty} Outer<T> relay<T>(Outer<T> input){return move input;} int main(){var a=relay<int>(Outer<int>.Child(Inner<int>.Ready(new int[2])));match(move a){else:{return 0;}}}");
		var outer = nested.generic_functions[0];
		outer.element_obligations.require (outer.type_parameters[0].semantic_type, GenericElementRequirements.COPY);
		invalid ("F09-Core-transitive-premise", "separate copy, storage, structural zero and trivial destruction premises", () => CoreVerifier.verify (nested));
		outer.element_obligations.require (outer.type_parameters[0].semantic_type);
		valid ("F09-Core-restored", () => CoreVerifier.verify (nested));
		var tokens = core ("enum Marker<T>{Empty} Marker<T> inner<T,U>(Marker<T> input){return input;} Marker<T> outer<T,U>(Marker<T> input){return inner<T,U>(input);} int main(){var a=outer<int,int>(Marker<int>.Empty());return 0;}");
		var returned = (CoreEnumReturn) tokens.generic_functions[1].body.statements[1];
		var call = (CoreEnumCallResult) returned.producer;
		var left = call.type_arguments[0];
		var right = call.type_arguments[1];
		assert (left != right);
		call.type_arguments[0] = right;
		call.type_arguments[1] = left;
		invalid ("F08-Core-exact-outer-tokens", "enum call producer requires its exact concrete native target and result", () => CoreVerifier.verify (tokens));
		call.type_arguments[0] = left;
		call.type_arguments[1] = right;
		valid ("F08-Core-outer-tokens-restored", () => CoreVerifier.verify (tokens));
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void native_channels() {
	try {
		var source = ssa ("enum A{Ready(owned int[] data),Empty} enum B{Ready(owned int[] data),Empty} A fa(A input){return move input;} B fb(B input){return move input;} int main(){var a=fa(A.Ready(new int[2]));var b=fb(B.Ready(new int[3]));match(move a){else:{}}match(move b){else:{return 0;}}}");
		var native = NativeAbiBuilder.build (source);
		var foreign = CAbiBuilder.build (source, native);
		var signature = native.functions[0].signature;
		var parameter = signature.parameters[0];
		var other = native.functions[1].signature;
		valid ("F06-before", () => LlvmLowering.lower (source, native, foreign).verify ());
		signature.parameters[0] = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, other.parameters[0].abi_type);
		valid ("F06-wrong-input-local", () => NativeAbiVerifier.verify (native));
		invalid ("F06-wrong-input-instance", "parameter channel type does not match SSA function", () => LlvmLowering.lower (source, native, foreign));
		signature.parameters[0] = parameter;
		valid ("F06-input-restored", () => LlvmLowering.lower (source, native, foreign).verify ());
		var result = signature.sum_result;
		signature.sum_result = other.sum_result;
		valid ("F06-wrong-result-local", () => NativeAbiVerifier.verify (native));
		invalid ("F06-wrong-result-instance", "sum function result nominal storage correspondence mismatch", () => LlvmLowering.lower (source, native, foreign));
		signature.sum_result = result;
		valid ("F06-result-restored", () => LlvmLowering.lower (source, native, foreign).verify ());
		var records = ssa ("struct R{int a;int b;} struct S{int a;int b;} enum A{Ready(owned R[] data),Empty} enum B{Ready(owned S[] data),Empty} int main(){var a=A.Ready(new R[2]);var b=B.Ready(new S[2]);match(move a){else:{}}match(move b){else:{return 0;}}}");
		var planned = NativeAbiBuilder.build (records);
		var foreign_records = CAbiBuilder.build (records, planned);
		var field = planned.sum_values[0].variants[0].fields[0];
		var different = planned.sum_values[1].variants[0].fields[0];
		assert (field.buffer.record_element != different.buffer.record_element);
		valid ("F09-record-before", () => LlvmLowering.lower (records, planned, foreign_records).verify ());
		planned.sum_values[0].variants[0].fields[0] = new NativeSumField (field.identity, null, null, null, different.buffer);
		valid ("F09-foreign-record-local", () => NativeAbiVerifier.verify (planned));
		invalid ("F09-foreign-record-plan", "owned sum buffer lost exact element and complete descriptor plan", () => LlvmLowering.lower (records, planned, foreign_records));
		planned.sum_values[0].variants[0].fields[0] = field;
		valid ("F09-record-restored", () => LlvmLowering.lower (records, planned, foreign_records).verify ());
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void ordinary(LlvmModuleArtifact artifact) {
	char* message;
	int failed = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	string detail = message == null ? "" : (string) message;
	if (message != null) {
		CApi.dispose_message (message);
	}
	if (failed != 0) {
		GLib.error ("probe LLVM setup: %s", detail);
	}
	Test.message ("R1 ordinary LLVM PASS");
}

private LlvmModuleArtifact artifact(string text) throws GLib.Error {
	SsaProgram? input = ssa (text);
	NativeAbiProgram? native = NativeAbiBuilder.build (input);
	CAbiProgram? foreign = CAbiBuilder.build (input, native);
	var upstream = WeakRef (input.functions[0]);
	var plan = WeakRef (native.functions[0]);
	var result = LlvmLowering.lower (input, native, foreign);
	input = null;
	native = null;
	foreign = null;
	assert (upstream.get () == null && plan.get () == null);
	var target = new LlvmTargetMachineArtifact ();
	target.configure (result);
	ordinary (result);
	result.verify ();
	return result;
}

private void physical_relations() {
	try {
		var module = artifact (PAIRS);
		LlvmSumProjection? selected = null;
		foreach (var projection in module.sum_projections) {
			if (projection.field.variant.enumeration.name == "Owner" && projection.field.ordinal == 0) {
				selected = projection;
			}
		}
		assert (selected != null);
		var index = CApi.operand (selected.address, 2);
		CApi.set_operand (selected.address, 2, CApi.const_int (CApi.type_of (index), 1, 0));
		ordinary (module);
		invalid ("F16-F18-LLVM-wrong-buffer-projection", "owning sum effect changed", () => module.verify ());
		CApi.set_operand (selected.address, 2, index);
		ordinary (module);
		valid ("F16-F18-LLVM-projection-restored", () => module.verify ());
		var live_slots = new GenericArray<void*> ();
		CApi.ValueRef cleanup = (CApi.ValueRef) null;
		CApi.ValueRef flag_write = (CApi.ValueRef) null;
		for (var function = CApi.first_function (module.module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					size_t length;
					string name = CApi.value_name (instruction, out length);
					if (CApi.opcode (instruction) == CApi.Opcode.ALLOCA && name.has_prefix ("sum.live")) {
						live_slots.add ((void*) instruction);
					}
					if (CApi.opcode (instruction) == CApi.Opcode.STORE && CApi.value_name (CApi.operand (instruction, 1), out length).has_prefix ("sum.live")) {
						flag_write = instruction;
					}
					if (CApi.opcode (instruction) == CApi.Opcode.CALL && CApi.value_name (CApi.called_value (instruction), out length) == "free") {
						cleanup = instruction;
					}
				}
			}
		}
		assert (live_slots.length > 1 && (void*) flag_write != null && (void*) cleanup != null);
		var flag = CApi.operand (flag_write, 1);
		CApi.ValueRef wrong_flag = (CApi.ValueRef) live_slots[0];
		if ((void*) wrong_flag == (void*) flag) {
			wrong_flag = (CApi.ValueRef) live_slots[1];
		}
		CApi.set_operand (flag_write, 1, wrong_flag);
		ordinary (module);
		invalid ("F17-LLVM-foreign-live-slot", "owning sum effect changed", () => module.verify ());
		CApi.set_operand (flag_write, 1, flag);
		ordinary (module);
		valid ("F17-LLVM-live-slot-restored", () => module.verify ());
		var builder = CApi.create_builder_in_context (module.context);
		CApi.position_builder_before (builder, cleanup);
		CApi.ValueRef[] args = {
			CApi.operand (cleanup, 0)
		};
		var duplicate = CApi.build_call (builder, CApi.called_function_type (cleanup), CApi.called_value (cleanup), args, 1, "");
		CApi.dispose_builder (builder);
		ordinary (module);
		invalid ("F17-LLVM-duplicate-conditional-cleanup", "sum storage lost exact producer/store/call/read publication order", () => module.verify ());
		erase_instruction (duplicate);
		ordinary (module);
		valid ("F17-LLVM-duplicate-restored", () => module.verify ());
		var pointer = CApi.operand (cleanup, 0);
		CApi.set_operand (cleanup, 0, CApi.const_null (CApi.type_of (pointer)));
		ordinary (module);
		invalid ("F16-LLVM-wrong-cleanup-value", "owning sum effect changed", () => module.verify ());
		CApi.set_operand (cleanup, 0, pointer);
		ordinary (module);
		valid ("F16-LLVM-cleanup-restored", () => module.verify ());
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void captures() {
	try {
		var program = cfg (CAPTURE);
		var main = program.functions[program.functions.length - 1];
		CfgBlock? block = null;
		CfgEnumCommit? commit = null;
		uint position = 0;
		foreach (var candidate in main.blocks) {
			for (uint i = 0; i < candidate.instructions.length; i++) {
				var found = candidate.instructions[i] as CfgEnumCommit;
				if (found != null) {
					block = candidate;
					commit = found;
					position = i;
				}
			}
		}
		assert (block != null && commit != null);
		valid ("F10-CFG-before-nested-consumers", () => CfgVerifier.verify (program));
		block.instructions.insert ((int) position, new CfgEnumDrop (commit.span, commit.captured.reservation_source));
		invalid ("F10-CFG-premature-source-destruction", "enum", () => CfgVerifier.verify (program));
		block.instructions.remove_index (position);
		valid ("F10-CFG-premature-restored", () => CfgVerifier.verify (program));
		block.instructions.remove_index (position);
		invalid ("F10-CFG-omitted-commit", "enum", () => CfgVerifier.verify (program));
		block.instructions.insert ((int) position, commit);
		valid ("F10-CFG-restored-missing", () => CfgVerifier.verify (program));
		block.instructions.insert ((int) position + 1, new CfgEnumCommit (commit.span, commit.captured));
		invalid ("F10-CFG-double-commit", "enum", () => CfgVerifier.verify (program));
		block.instructions.remove_index (position + 1);
		valid ("F10-CFG-restored-double", () => CfgVerifier.verify (program));
		CfgEnumSlot? wrong = null;
		foreach (var slot in main.enum_slots) {
			if (slot.reservation_source != null && slot != commit.captured) {
				wrong = slot;
				break;
			}
		}
		assert (wrong != null);
		block.instructions[position] = new CfgEnumCommit (commit.span, wrong);
		invalid ("F10-CFG-wrong-reservation", "enum", () => CfgVerifier.verify (program));
		block.instructions[position] = commit;
		valid ("F10-CFG-restored-wrong", () => CfgVerifier.verify (program));
		var lowered = ssa (CAPTURE);
		var function = lowered.functions[lowered.functions.length - 1];
		int cases = 0;
		foreach (var candidate in function.blocks) {
			for (uint i = 0; i < candidate.instructions.length; i++) {
				var original = candidate.instructions[i] as SsaEnumCommit;
				if (original == null) {
					continue;
				}
				candidate.instructions.remove_index (i);
				invalid ("F10-SSA-omitted-commit-%u".printf (i), "enum", () => SsaVerifier.verify (lowered));
				candidate.instructions.insert ((int) i, original);
				valid ("F10-SSA-restored", () => SsaVerifier.verify (lowered));
				cases++;
			}
		}
		assert (cases > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void structured() {
	try {
		foreach (var text in new string[] { BRANCH, LOOP }) {
			var program = cfg (text);
			valid (text == BRANCH ? "F11-CFG-branch-before" : "F12-F14-CFG-loop-before", () => CfgVerifier.verify (program));
			int mutations = 0;
			foreach (var block in program.functions[0].blocks) {
				for (uint i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					if (!(instruction is CfgEnumDrop || instruction is CfgEnumEndInspection)) {
						continue;
					}
					block.instructions.remove_index (i);
					invalid ((text == BRANCH ? "F11-CFG-edge" : "F12-F14-CFG-exit") + "-%d-%u".printf (block.ordinal, i), "enum", () => CfgVerifier.verify (program));
					block.instructions.insert ((int) i, instruction);
					valid ("F11-F12-F14-CFG-restored", () => CfgVerifier.verify (program));
					mutations++;
				}
			}
			assert (mutations > 0);
			var lowered = ssa (text);
			valid ("F11-F12-SSA-correct-control", () => SsaVerifier.verify (lowered));
			foreach (var block in lowered.functions[0].blocks) {
				for (uint i = 0; i < block.instructions.length; i++) {
					var instruction = block.instructions[i];
					if (!(instruction is SsaEnumDrop || instruction is SsaEnumEndInspection)) {
						continue;
					}
					block.instructions.remove_index (i);
					invalid ((text == BRANCH ? "F11-SSA-edge" : "F12-F14-SSA-exit") + "-%d-%u".printf (block.ordinal, i), "enum", () => SsaVerifier.verify (lowered));
					block.instructions.insert ((int) i, instruction);
					valid ("F11-F12-F14-SSA-restored", () => SsaVerifier.verify (lowered));
				}
			}
		}
		var transferred = cfg (BRANCH.replace ("if(selected){", "if(selected){match(move a){else:{}}"));
		int stale = 0;
		foreach (var block in transferred.functions[0].blocks) {
			for (uint i = 0; i < block.instructions.length; i++) {
				var commit = block.instructions[i] as CfgEnumCommit;
				if (commit == null || commit.captured.reservation_source.local == null) {
					continue;
				}
				var owner = commit.captured.reservation_source;
				block.instructions.insert ((int) i + 1, new CfgEvaluateInstruction (commit.span, new CfgEnumTag (commit.span, owner.definition.tag_type, owner), new CfgEvaluatedValue (commit.span, owner.definition.tag_type)));
				invalid ("F11-CFG-claim-live-after-branch-transfer", "not initialized on every incoming path", () => CfgVerifier.verify (transferred));
				block.instructions.remove_index (i + 1);
				valid ("F11-CFG-branch-transfer-restored", () => CfgVerifier.verify (transferred));
				stale++;
			}
		}
		assert (stale > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

private void nested_inspections() {
	try {
		const string text = "enum Inner{Ready(owned int[] data),Empty} enum Outer{Child(Inner value),Empty} int main(){var a=Outer.Child(Inner.Ready(new int[2]));match(a){case Outer.Child(child):{match(child){case Inner.Ready(view):{if(len(view)!=2){return 1;}}else:{return 2;}}match(child){case Inner.Ready(view):{return len(view)-2;}else:{return 3;}}}else:{return 4;}}}";
		var program = cfg (text);
		var function = program.functions[0];
		CfgEnumSlot? surviving = null;
		foreach (var slot in function.enum_slots) {
			if (slot.inspection_root != null && slot.definition.semantic_type.identity.name == "Outer") {
				surviving = slot;
			}
		}
		assert (surviving != null);
		int probes = 0;
		foreach (var block in function.blocks) {
			for (uint i = 0; i < block.instructions.length; i++) {
				var end = block.instructions[i] as CfgEnumEndInspection;
				if (end == null || end.source.definition.semantic_type.identity.name != "Inner") {
					continue;
				}
				var read = new CfgEvaluateInstruction (end.span, new CfgEnumTag (end.span, end.source.definition.tag_type, surviving), new CfgEvaluatedValue (end.span, end.source.definition.tag_type));
				block.instructions.insert ((int) i + 1, read);
				valid ("F13-CFG-surviving-outer-loan", () => CfgVerifier.verify (program));
				block.instructions[(int) i + 1] = new CfgEvaluateInstruction (end.span, new CfgEnumTag (end.span, end.source.definition.tag_type, end.source), new CfgEvaluatedValue (end.span, end.source.definition.tag_type));
				invalid ("F13-CFG-ended-inner-loan", "enum view survives the end of its inspection", () => CfgVerifier.verify (program));
				block.instructions.remove_index (i + 1);
				valid ("F13-CFG-restored", () => CfgVerifier.verify (program));
				probes++;
			}
		}
		assert (probes > 0);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

internal void register() {
	Test.add_func ("/enum-own/r1/field-bindings", field_bindings);
	Test.add_func ("/enum-own/r1/complete-pairs", complete_pairs);
	Test.add_func ("/enum-own/r1/active-masks", masks);
	Test.add_func ("/enum-own/r1/locally-valid-native-pairings", native_pairs);
	Test.add_func ("/enum-own/r1/generic-premises", generic_premises);
	Test.add_func ("/enum-own/r1/native-channels-and-records", native_channels);
	Test.add_func ("/enum-own/r1/LLVM-retained-physical-relations", physical_relations);
	Test.add_func ("/enum-own/r1/capture-commits", captures);
	Test.add_func ("/enum-own/r1/structured-cleanup", structured);
	Test.add_func ("/enum-own/r1/nested-inspection-extents", nested_inspections);
}

}
