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

namespace DeclaredForeignContracts {
private delegate void Check() throws GLib.Error;
private void refused(string label, owned Check action) throws GLib.Error {
	bool rejected = false;
	try {
		action ();
	} catch (GLib.Error failure) {
		rejected = true;
		Test.message ("%s: %s", label, failure.message);
	}
	assert (rejected);
}

private void stage_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-proof.astra",
			"[CExport(name=\"declproof16\",profile=\"declarations-v1\",bool_abi=\"c99\")]class Cell{private i64 raw;"
			+ "[Foreign]init(i64 seed){this.raw=seed;}[Foreign]i64 echo(i64 value){return this.raw+value;}[Foreign]bool invert(bool value){return !value;}}"));
		assert (parsed.diagnostic == null);
		SemanticResult? analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var policy = checked.classes[0].foreign_export;
		assert (policy.declared_api.member_count == 3);
		checked.classes[0].foreign_export = null;
		refused ("checked missing declared policy", () => { CoreBuilder.build (checked);
		});
		checked.classes[0].foreign_export = policy;
		var upstream = WeakRef (checked.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (upstream.get () == null);
		var core_member = CoreForeignApi.target (core.classes[0], policy.declared_api.member (1));
		var core_parameter = core_member.parameters[0];
		core_member.parameters.remove_index (0);
		assert (!CoreForeignApi.valid (core.classes[0]));
		refused ("detached Core signature mutation", () => CoreVerifier.verify (core));
		core_member.parameters.add (core_parameter);
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		var cfg_member = CfgForeignApi.target (cfg.classes[0], policy.declared_api.member (1));
		var cfg_parameter = cfg_member.parameters[0];
		cfg_member.parameters.remove_index (0);
		assert (!CfgForeignApi.valid (cfg.classes[0]));
		refused ("detached CFG signature mutation", () => CfgVerifier.verify (cfg));
		cfg_member.parameters.add (cfg_parameter);
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		var ssa_member = SsaForeignApi.target (ssa.classes[0], policy.declared_api.member (1));
		var ssa_parameter = ssa_member.parameters[0];
		ssa_member.parameters.remove_index (0);
		assert (!SsaForeignApi.valid (ssa.classes[0]));
		refused ("detached SSA signature mutation", () => SsaVerifier.verify (ssa));
		ssa_member.parameters.add (ssa_parameter);
		SsaVerifier.verify (ssa);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		var native_member = native.functions[native.classes[0].foreign_member (1)];
		var native_parameter = native_member.signature.parameters[0];
		native_member.signature.parameters.remove_index (0);
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native physical signature mutation", () => NativeAbiVerifier.verify (native));
		native_member.signature.parameters.add (native_parameter);
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		var adapter = cabi.class_adapters[0];
		adapter.native_class++;
		refused ("C ABI substituted native root", () => CAbiVerifier.verify (cabi));
		adapter.native_class--;
		CAbiVerifier.verify (cabi);
		cabi.class_adapters.remove_index (0);
		refused ("C ABI omitted declared adapter", () => { LlvmLowering.lower (ssa, native, cabi);
		});
		cabi.class_adapters.add (adapter);
		upstream = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var function = CApi.named_function (artifact.module, "declproof16_invert");
		uint zeroext = CApi.enum_attribute_kind ("zeroext", 7);
		CApi.remove_enum_attribute (function, 2, zeroext);
		refused ("LLVM declared bool parameter lost zeroext", () => artifact.verify ());
		CApi.add_attribute (function, 2, CApi.create_enum_attribute (artifact.context, zeroext, 0));
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void byte_channel_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-bytes-proof.astra",
			"[CExport(name=\"byteproof16\",profile=\"declarations-v1\")]class Cell{"
			+ "[Foreign]init(){}[Foreign]int bytes(borrowed u8[] input){return len(input);}int words(borrowed u16[] input){return len(input);}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var member = core.classes[0].methods[0];
		var peer = core.classes[0].methods[1];
		var parameter = member.parameters[0];
		member.parameters.remove_index (0);
		member.parameters.add (peer.parameters[0]);
		assert (!CoreForeignApi.valid (core.classes[0]));
		refused ("Core bytes substituted by borrowed u16 pair", () => CoreVerifier.verify (core));
		member.parameters.remove_index (0);
		member.parameters.add (parameter);
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var cfg_member = cfg.classes[0].methods[0];
		var cfg_peer = cfg.classes[0].methods[1];
		var cfg_parameter = cfg_member.parameters[0];
		cfg_member.parameters.remove_index (0);
		cfg_member.parameters.add (cfg_peer.parameters[0]);
		assert (!CfgForeignApi.valid (cfg.classes[0]));
		refused ("CFG bytes substituted by borrowed u16 pair", () => CfgVerifier.verify (cfg));
		cfg_member.parameters.remove_index (0);
		cfg_member.parameters.add (cfg_parameter);
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var ssa_member = ssa.classes[0].methods[0];
		var ssa_peer = ssa.classes[0].methods[1];
		var ssa_parameter = ssa_member.parameters[0];
		ssa_member.parameters.remove_index (0);
		ssa_member.parameters.add (ssa_peer.parameters[0]);
		assert (!SsaForeignApi.valid (ssa.classes[0]));
		refused ("SSA bytes substituted by borrowed u16 pair", () => SsaVerifier.verify (ssa));
		ssa_member.parameters.remove_index (0);
		ssa_member.parameters.add (ssa_parameter);
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var native_member = native.functions[ssa_member.ordinal];
		var native_peer = native.functions[ssa_peer.ordinal];
		var native_parameter = native_member.signature.parameters[0];
		native_member.signature.parameters.remove_index (0);
		native_member.signature.parameters.add (native_peer.signature.parameters[0]);
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native byte element substituted despite identical PTR/I32 widths", () => NativeAbiVerifier.verify (native));
		native_member.signature.parameters.remove_index (0);
		native_member.signature.parameters.add (native_parameter);
		NativeAbiVerifier.verify (native);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owned_sequence_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-owned-proof.astra",
			"[CExport(name=\"ownedproof16\",profile=\"declarations-v1\")]class Cell{[Foreign]init(){}"
			+ "[Foreign]owned u8[] snapshot(){var bytes=new u8[1];return move bytes;}"
			+ "[Foreign][ForeignChannel(parameter=\"result\",encoding=\"utf8-nul\")]string text(){return \"hello\";}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var ssa = SsaBuilder.build (CfgBuilder.build (CoreBuilder.build (analyzed.program)));
		var native = NativeAbiBuilder.build (ssa);
		var member = native.functions[native.classes[0].foreign_member (1)];
		var original = member.signature.buffer_result;
		member.signature.buffer_result = new NativeBufferValuePlan (new NativeScalarAbiType (NativeScalarType.U16));
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("owned byte result substituted by wider element cleanup domain", () => NativeAbiVerifier.verify (native));
		member.signature.buffer_result = null;
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("owned result transfer omitted", () => NativeAbiVerifier.verify (native));
		member.signature.buffer_result = original;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var helper = CApi.named_function (artifact.module, "astra.text.find.nul");
		assert ((void*) helper != null);
		var branch = CApi.block_terminator (CApi.first_block (helper));
		var condition = CApi.operand (branch, 0);
		CApi.set_operand (branch, 0, CApi.const_null (CApi.type_of (condition)));
		char* llvm_message;
		assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out llvm_message) == 0);
		if (llvm_message != null) {
			CApi.dispose_message (llvm_message);
		}
		refused ("ordinary-valid NUL helper lost its null admission edge", () => artifact.verify ());
		CApi.set_operand (branch, 0, condition);
		artifact.verify ();
		var release = CApi.named_function (artifact.module, "ownedproof16_bytes_release");
		bool changed = false;
		for (var block = CApi.first_block (release); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.argument_count (instruction) != 1) {
					continue;
				}
				size_t length;
				var target = CApi.called_value (instruction);
				if (CApi.value_name (target, out length) != "free") {
					continue;
				}
				var pointer = CApi.operand (instruction, 0);
				CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (pointer)));
				refused ("ordinary-valid omitted owned byte retirement", () => artifact.verify ());
				CApi.set_operand (instruction, 0, pointer);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void record_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-record-proof.astra",
			"struct Stats{int count;f64 scale;f64 bias;}struct Other{int count;f64 scale;f64 bias;}struct Unsigned{u32 value;}"
			+ "[CExport(name=\"podproof16\",profile=\"declarations-v1\")]class Cell{[Foreign]init(){}"
			+ "[Foreign]Stats relay(Stats input){return input;}Other alternate(Other input){return input;}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		assert (CoreForeignApi.valid (core.classes[0], core));
		var field_type = core.structs[0].fields[0].semantic_type;
		core.structs[0].fields[0].semantic_type = core.structs[2].fields[0].semantic_type;
		assert (!CoreForeignApi.valid (core.classes[0], core));
		refused ("Core POD changed signed field despite equal width", () => CoreVerifier.verify (core));
		core.structs[0].fields[0].semantic_type = field_type;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var member = cfg.classes[0].methods[0];
		var peer = cfg.classes[0].methods[1];
		var group = member.struct_parameters[0];
		member.struct_parameters.remove_index (0);
		member.struct_parameters.add (peer.struct_parameters[0]);
		assert (!CfgForeignApi.valid (cfg.classes[0], cfg));
		refused ("CFG nominal POD replaced by equal scalar tuple", () => CfgVerifier.verify (cfg));
		member.struct_parameters.remove_index (0);
		member.struct_parameters.add (group);
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var ssa_member = ssa.classes[0].methods[0];
		var ssa_peer = ssa.classes[0].methods[1];
		var ssa_group = ssa_member.struct_parameters[0];
		ssa_member.struct_parameters.remove_index (0);
		ssa_member.struct_parameters.add (ssa_peer.struct_parameters[0]);
		assert (!SsaForeignApi.valid (ssa.classes[0], ssa));
		refused ("SSA nominal POD replaced by equal scalar tuple", () => SsaVerifier.verify (ssa));
		ssa_member.struct_parameters.remove_index (0);
		ssa_member.struct_parameters.add (ssa_group);
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var native_member = native.functions[ssa_member.ordinal];
		var native_peer = native.functions[ssa_peer.ordinal];
		var native_group = native_member.signature.struct_parameters[0];
		native_member.signature.struct_parameters.remove_index (0);
		native_member.signature.struct_parameters.add (native_peer.signature.struct_parameters[0]);
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native nominal POD replaced by equal physical signature", () => NativeAbiVerifier.verify (native));
		native_member.signature.struct_parameters.remove_index (0);
		native_member.signature.struct_parameters.add (native_group);
		NativeAbiVerifier.verify (native);
		refused ("native admitted POD fields cannot rebind", () => native_group.value_plan.bind_foreign_record (null));
		var result = native_member.signature.struct_result;
		native_member.signature.struct_result = native_peer.signature.struct_result;
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native nominal POD result replaced", () => NativeAbiVerifier.verify (native));
		native_member.signature.struct_result = result;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var bridge = CApi.named_function (artifact.module, "astra_foreign16_podproof16_relay");
		bool changed = false;
		for (var block = CApi.first_block (bridge); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.GEP || CApi.count_struct_element_types (CApi.gep_source_type (instruction)) != 3) {
					continue;
				}
				var index = CApi.operand (instruction, 2);
				if (CApi.const_int_zext (index) != 1) {
					continue;
				}
				CApi.set_operand (instruction, 2, CApi.const_int (CApi.type_of (index), 2, 0));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM POD field permutation", () => artifact.verify ());
				CApi.set_operand (instruction, 2, index);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void object_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-object-proof.astra",
			"[CExport(name=\"factoryproof16\",profile=\"declarations-v1\")]class Factory{[Foreign]init(){}"
			+ "[Foreign]int read(borrowed Item input){return input.code();}[Foreign]owned Item make(){var item=new Item(7);return move item;}}"
			+ "[CExport(name=\"itemproof16\",profile=\"declarations-v1\")]class Item{private int value;[Foreign]init(int value){this.value=value;}[Foreign]int code(){return this.value;}}"
			+ "[CExport(name=\"otherproof16\",profile=\"declarations-v1\")]class Other{int value;init(){this.value=0;}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var member = core.classes[0].methods[0];
		var parameter = member.parameters[0];
		var original_type = parameter.semantic_type;
		parameter.semantic_type = core.classes[2].semantic_type;
		assert (!CoreForeignApi.valid (core.classes[0], core));
		refused ("Core borrowed object substituted by other PTR root", () => CoreVerifier.verify (core));
		parameter.semantic_type = original_type;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var cfg_make = cfg.classes[0].methods[1];
		assert (cfg_make.heap_result);
		cfg_make.heap_result = false;
		assert (!CfgForeignApi.valid (cfg.classes[0], cfg));
		refused ("CFG owned foreign result lost heap cleanup authority", () => CfgVerifier.verify (cfg));
		cfg_make.heap_result = true;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var ssa_make = ssa.classes[0].methods[1];
		ssa_make.heap_result = false;
		assert (!SsaForeignApi.valid (ssa.classes[0], ssa));
		refused ("SSA owned foreign result lost heap cleanup authority", () => SsaVerifier.verify (ssa));
		ssa_make.heap_result = true;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var native_read = native.functions[native.classes[0].foreign_member (1)];
		var original = native_read.signature.parameters[0];
		var wrong_nonnull = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, original.abi_type, original.borrowed_class_ordinal, true);
		native_read.signature.parameters.remove_index (0);
		native_read.signature.parameters.add (wrong_nonnull);
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native object borrow changed its checked nonnull fact", () => NativeAbiVerifier.verify (native));
		native_read.signature.parameters.remove_index (0);
		native_read.signature.parameters.add (original);
		NativeAbiVerifier.verify (native);
		var native_make = native.functions[native.classes[0].foreign_member (2)];
		var origin = native_make.signature.heap_result;
		native_make.signature.heap_result = new NativeObjectOriginPlan (2, native.classes[2].name, true);
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native owned result substituted another nominal root", () => NativeAbiVerifier.verify (native));
		native_make.signature.heap_result = origin;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "factoryproof16_make");
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.STORE) {
					continue;
				}
				var value = CApi.operand (instruction, 0);
				if (CApi.type_kind (CApi.type_of (value)) != CApi.TypeKind.INTEGER || CApi.int_width (CApi.type_of (value)) != 64 || (void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.LOAD) {
					continue;
				}
				CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (value)));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM owned result lost original construction context", () => artifact.verify ());
				CApi.set_operand (instruction, 0, value);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void owner_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-owner-proof.astra",
			"[CExport(name=\"consumerproof16\",profile=\"declarations-v1\")]class Consumer{[Foreign]init(){}[Foreign]int take(owned Item input){return input.code();}}"
			+ "[CExport(name=\"ownedproof16\",profile=\"declarations-v1\")]class Item{private int value;[Foreign]init(int value){this.value=value;}[Foreign]int code(){return this.value;}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var parameter = core.classes[0].methods[0].parameters[0];
		assert (parameter.heap_object);
		parameter.heap_object = false;
		assert (!CoreForeignApi.valid (core.classes[0], core));
		refused ("Core consuming input lost independent heap owner", () => CoreVerifier.verify (core));
		parameter.heap_object = true;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		var native = NativeAbiBuilder.build (ssa);
		var input = native.functions[native.classes[0].foreign_member (1)].signature.parameters[0];
		var origin = input.object_origin;
		assert (origin != null && origin.heap);
		input.object_origin = new NativeObjectOriginPlan (origin.class_ordinal, origin.class_name, false);
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native consuming input lost heap authority", () => NativeAbiVerifier.verify (native));
		input.object_origin = origin;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "consumerproof16_take");
		bool disarm = false, duty = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) CApi.get_param (wrapper, 1)) {
					var original = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.get_param (wrapper, 1));
					char* message;
					assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
					if (message != null) {
						CApi.dispose_message (message);
					}
					refused ("ordinary-valid LLVM consuming owner slot not cleared", () => artifact.verify ());
					CApi.set_operand (instruction, 0, original);
					artifact.verify ();
					disarm = true;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.SUB && CApi.int_width (CApi.type_of (instruction)) == 64) {
					var original = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, CApi.const_null (CApi.type_of (original)));
					char* message;
					assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
					if (message != null) {
						CApi.dispose_message (message);
					}
					refused ("ordinary-valid LLVM transferred owner duty retained", () => artifact.verify ());
					CApi.set_operand (instruction, 1, original);
					artifact.verify ();
					duty = true;
				}
			}
		}
		assert (disarm && duty);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void error_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-error-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}class Bad:Fault{init(string text):base(text){}}"
			+ "[CExport(name=\"errorproof16\",profile=\"declarations-v1\")]class Service{[Foreign]init(){}[Foreign(error_domain=\"16\",errors=\"Bad=-1601,Fault=-1600\")]int read(int mode)throws Fault{if(mode==1){throw new Bad(\"bad\");}return 42;}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var method = core.classes[2].methods[0];
		var bound = method.throws_type;
		method.throws_type = (ClassType) core.classes[1].semantic_type;
		assert (!CoreForeignApi.valid (core.classes[2], core));
		refused ("Core checked error map changed its native throws bound", () => CoreVerifier.verify (core));
		method.throws_type = bound;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		var native = NativeAbiBuilder.build (ssa);
		var signature = native.functions[native.classes[2].foreign_member (1)].signature;
		var plan = signature.exception_plan;
		signature.exception_plan = null;
		assert (!NativeForeignApi.valid (native, native.classes[2]));
		refused ("detached native checked error became ordinary success ABI", () => NativeAbiVerifier.verify (native));
		signature.exception_plan = plan;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "errorproof16_read");
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.RET || CApi.operand_count (instruction) != 1) {
					continue;
				}
				var original = CApi.operand (instruction, 0);
				if ((void*) CApi.is_instruction (original) == null) {
					continue;
				}
				CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (original)));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM checked failure relabeled success", () => artifact.verify ());
				CApi.set_operand (instruction, 0, original);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void scalar_reference_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-scalar-pointer-proof.astra",
			"[CExport(name=\"pointerproof16\",profile=\"declarations-v1\")]class Service{[Foreign]init(){}"
			+ "[Foreign][ForeignChannel(parameter=\"value\",direction=\"inout\")]void update(borrowed f64* value){*value=*value+1.0;}"
			+ "[Foreign][ForeignChannel(parameter=\"output\",direction=\"out\",produced=\"produced\")][ForeignChannel(parameter=\"produced\",direction=\"out\")]void fill(borrowed u8[] output,borrowed int* produced){*produced=len(output);}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var core_parameters = core.classes[0].methods[0].parameters;
		var parameter = core_parameters[0];
		core_parameters.remove_index (0);
		core_parameters.add (new CoreParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal));
		assert (!CoreForeignApi.valid (core.classes[0], core));
		refused ("Core scalar reference lost noescape contract", () => CoreVerifier.verify (core));
		core_parameters.remove_index (0);
		core_parameters.add (parameter);
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		var native = NativeAbiBuilder.build (ssa);
		var parameters = native.functions[native.classes[0].foreign_member (1)].signature.parameters;
		var original = parameters[0];
		assert (original.scalar_pointee.scalar_type == NativeScalarType.F64);
		var wrong = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, original.abi_type, -1, false, new NativeScalarAbiType (NativeScalarType.U64));
		parameters.remove_index (0);
		parameters.add (wrong);
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("detached native scalar reference changed pointee with identical PTR/width", () => NativeAbiVerifier.verify (native));
		parameters.remove_index (0);
		parameters.add (original);
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "pointerproof16_fill");
		bool publication = false, bounds = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				int operand = -1;
				if (CApi.opcode (instruction) == CApi.Opcode.STORE && (void*) CApi.operand (instruction, 1) == (void*) CApi.get_param (wrapper, 3) && (void*) CApi.is_instruction (CApi.operand (instruction, 0)) != null) {
					operand = 0;
					publication = true;
				}
				if (CApi.opcode (instruction) == CApi.Opcode.ICMP && (void*) CApi.operand (instruction, 1) == (void*) CApi.get_param (wrapper, 2)) {
					operand = 1;
					bounds = true;
				}
				if (operand < 0) {
					continue;
				}
				var saved = CApi.operand (instruction, operand);
				CApi.set_operand (instruction, operand, CApi.const_null (CApi.type_of (saved)));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM scalar publication or produced-capacity operand changed", () => artifact.verify ());
				CApi.set_operand (instruction, operand, saved);
				artifact.verify ();
			}
		}
		assert (publication && bounds);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void constructor_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-constructor-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "[CExport(name=\"ctorproof16\",profile=\"declarations-v1\")]class Box{private owned Item child;[Foreign(error_domain=\"16\",errors=\"Fault=-1600\")]init(owned Item input,int mode)throws Fault{this.child=move input;if(mode!=0){throw new Fault(\"partial\");}}}"
			+ "[CExport(name=\"ctoritemproof16\",profile=\"declarations-v1\")]class Item{[Foreign]init(){}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var inventory = core.classes[1].constructor.unwind_fields;
		var field = inventory[0];
		inventory.remove_index (0);
		refused ("Core checked constructor lost field retirement inventory", () => CoreVerifier.verify (core));
		inventory.add (field);
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		bool cfg_changed = false;
		foreach (var block in cfg.classes[1].constructor.blocks) {
			if (!(block.terminator is CfgExceptionReturn)) {
				continue;
			}
			uint position = block.instructions.length - 1;
			var abort = block.instructions[position];
			assert (abort is CfgConstructorAbort);
			block.instructions.remove_index (position);
			refused ("CFG checked constructor lost exceptional compensation", () => CfgVerifier.verify (cfg));
			block.instructions.add (abort);
			CfgVerifier.verify (cfg);
			cfg_changed = true;
		}
		assert (cfg_changed);
		var ssa = SsaBuilder.build (cfg);
		bool ssa_changed = false;
		foreach (var block in ssa.classes[1].constructor.blocks) {
			foreach (var instruction in block.instructions) {
				var abort = instruction as SsaConstructorAbort;
				if (abort == null) {
					continue;
				}
				var recipe = abort.fields[0];
				abort.fields.remove_index (0);
				refused ("SSA checked constructor lost typed partial field", () => SsaVerifier.verify (ssa));
				abort.fields.add (recipe);
				SsaVerifier.verify (ssa);
				ssa_changed = true;
			}
		}
		assert (ssa_changed);
		var native = NativeAbiBuilder.build (ssa);
		var constructor = native.functions[native.classes[1].foreign_member (0)];
		var plan = constructor.constructor_unwind;
		assert (plan != null && plan.field_count == 1);
		constructor.constructor_unwind = null;
		refused ("detached native constructor lost compensation plan", () => NativeAbiVerifier.verify (native));
		constructor.constructor_unwind = plan;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "ctorproof16_create");
		CApi.ValueRef native_constructor = (CApi.ValueRef) null;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.instruction_call_conv (instruction) != LlvmLowering.CALL_CONVENTION) {
					continue;
				}
				var target = CApi.called_value (instruction);
				if ((void*) CApi.is_instruction (target) == null && CApi.count_params (target) == 3) {
					native_constructor = target;
				}
			}
		}
		assert ((void*) native_constructor != null);
		bool changed = false;
		for (var block = CApi.first_block (native_constructor); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.STORE) {
					continue;
				}
				var destination = CApi.operand (instruction, 1);
				var saved = CApi.operand (instruction, 0);
				if (CApi.type_kind (CApi.type_of (saved)) != CApi.TypeKind.INTEGER || CApi.int_width (CApi.type_of (saved)) != 32 || (void*) CApi.is_instruction (destination) == null || CApi.opcode (destination) != CApi.Opcode.GEP) {
					continue;
				}
				CApi.set_operand (instruction, 0, CApi.const_int (CApi.type_of (saved), 1, 0));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM constructor acquisition entry changed", () => artifact.verify ());
				CApi.set_operand (instruction, 0, saved);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void import_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-import-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "[CImport(name=\"importproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\",bool_abi=\"c99\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init(int seed)throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]bool choose(bool value)throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]u32 other(u32 value)throws Fault;}"));
		assert (parsed.diagnostic == null);
		SemanticResult? analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var root = checked.handles[0].c_import;
		checked.handles[0].c_import = null;
		refused ("checked imported root lost nominal cleanup authority", () => { CoreBuilder.build (checked);
		});
		checked.handles[0].c_import = root;
		var upstream = WeakRef (checked.handles[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (upstream.get () == null);
		CoreFunction? selected = null;
		foreach (var function in core.functions) {
			if (function.name == "Provider.choose") {
				selected = function;
			}
		}
		assert (selected != null);
		var marker = (CoreForeignReturn) selected.body.statements[0];
		selected.body.statements.remove_index (0);
		refused ("Core imported declaration lost typed operation", () => CoreVerifier.verify (core));
		selected.body.statements.add (marker);
		CoreVerifier.verify (core);
		var binding = marker.binding;
		marker.binding = new ForeignImportBinding (root, 2);
		refused ("Core imported member substituted by peer", () => CoreVerifier.verify (core));
		marker.binding = binding;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.handles[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		selected = null;
		marker = null;
		assert (upstream.get () == null);
		CfgForeignReturn? cfg_marker = null;
		foreach (var function in cfg.functions) {
			if (function.name == "Provider.choose") {
				cfg_marker = function.entry.terminator as CfgForeignReturn;
			}
		}
		assert (cfg_marker != null);
		var cfg_factory = cfg_marker.factory;
		cfg_marker.factory = cfg.functions[cfg.functions.length - 1];
		refused ("CFG imported error factory substituted", () => CfgVerifier.verify (cfg));
		cfg_marker.factory = cfg_factory;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.handles[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		cfg_marker = null;
		cfg_factory = null;
		assert (upstream.get () == null);
		SsaFunction? ssa_function = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Provider.choose") {
				ssa_function = function;
			}
		}
		assert (ssa_function != null);
		var ssa_marker = (SsaForeignReturn) ssa_function.entry.terminator;
		ssa_marker.binding = new ForeignImportBinding (root, 2);
		refused ("SSA imported declaration changed member identity", () => SsaVerifier.verify (ssa));
		ssa_marker.binding = binding;
		SsaVerifier.verify (ssa);
		NativeAbiProgram? native = NativeAbiBuilder.build (ssa);
		var native_function = native.functions[ssa_function.ordinal];
		var plan = native_function.foreign_import;
		native_function.foreign_import = null;
		refused ("detached native imported member lost plan", () => NativeAbiVerifier.verify (native));
		native_function.foreign_import = plan;
		NativeAbiVerifier.verify (native);
		native_function.foreign_import = new NativeForeignImportPlan (binding, ssa_function.ordinal);
		refused ("detached native import changed exception factory", () => NativeAbiVerifier.verify (native));
		native_function.foreign_import = plan;
		NativeAbiVerifier.verify (native);
		CAbiProgram? cabi = CAbiBuilder.build (ssa, native);
		CAbiForeignImport? physical = null;
		foreach (var candidate in cabi.class_imports) {
			if (candidate.native_function == ssa_function.ordinal) {
				physical = candidate;
			}
		}
		assert (physical != null);
		var parameter = physical.parameters[1];
		physical.parameters[1] = CAbiScalarType.I32;
		refused ("physical C import bool channel changed", () => CAbiVerifier.verify (cabi));
		physical.parameters[1] = parameter;
		CAbiVerifier.verify (cabi);
		physical.native_function++;
		refused ("physical C import retargeted native member", () => CAbiVerifier.verify (cabi));
		physical.native_function--;
		CAbiVerifier.verify (cabi);
		int ordinal = ssa_function.ordinal;
		upstream = WeakRef (ssa.handles[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		ssa_function = null;
		ssa_marker = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var provider = CApi.named_function (artifact.module, "importproof16_choose");
		uint zeroext = CApi.enum_attribute_kind ("zeroext", 7);
		CApi.remove_enum_attribute (provider, 2, zeroext);
		refused ("LLVM imported C bool lost target ABI extension", () => artifact.verify ());
		CApi.add_attribute (provider, 2, CApi.create_enum_attribute (artifact.context, zeroext, 0));
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (ordinal));
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.instruction_call_conv (instruction) != LlvmLowering.CALL_CONVENTION || CApi.argument_count (instruction) != 2) {
					continue;
				}
				var domain = CApi.operand (instruction, 0);
				var status = CApi.operand (instruction, 1);
				CApi.set_operand (instruction, 0, status);
				CApi.set_operand (instruction, 1, domain);
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM import swapped error domain/status", () => artifact.verify ());
				CApi.set_operand (instruction, 0, domain);
				CApi.set_operand (instruction, 1, status);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void import_reference_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-import-reference-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "[CImport(name=\"importrefproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")][ForeignChannel(parameter=\"value\",direction=\"inout\")][ForeignChannel(parameter=\"output\",direction=\"out\")]int change(borrowed f64* value,borrowed int* output)throws Fault;}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		CoreFunction? selected = null;
		foreach (var function in core.functions) {
			if (function.name == "Provider.change") {
				selected = function;
			}
		}
		assert (selected != null);
		var parameter = selected.parameters[1];
		selected.parameters[1] = new CoreParameter (parameter.span, parameter.name_span, parameter.name, parameter.semantic_type, parameter.ordinal);
		refused ("Core imported reference lost noescape", () => CoreVerifier.verify (core));
		selected.parameters[1] = parameter;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var ssa = SsaBuilder.build (cfg);
		SsaFunction? imported = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Provider.change") {
				imported = function;
			}
		}
		assert (imported != null);
		var native = NativeAbiBuilder.build (ssa);
		var function = native.functions[imported.ordinal];
		var original = function.signature.parameters[1];
		assert (original.scalar_pointee.scalar_type == NativeScalarType.F64);
		function.signature.parameters[1] = new NativeParameter.typed (original.span, original.name_span, original.name, original.ordinal, original.abi_type, -1, false, new NativeScalarAbiType (NativeScalarType.U64));
		refused ("detached imported pointer changed f64 to same-width u64", () => NativeAbiVerifier.verify (native));
		function.signature.parameters[1] = original;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (imported.ordinal));
		var destination = CApi.get_param (wrapper, 2);
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.STORE || (void*) CApi.operand (instruction, 1) != (void*) destination) {
					continue;
				}
				var value = CApi.operand (instruction, 0);
				CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (value)));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM imported reference changed staged publication", () => artifact.verify ());
				CApi.set_operand (instruction, 0, value);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void import_counted_bindings() {
	try {
		var parsed = Parser.parse(new SourceFile.from_text("declared-import-counted-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "int words(borrowed u16[] input){return len(input);}"
			+ "[CImport(name=\"importcountproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")][ForeignChannel(parameter=\"output\",direction=\"out\",produced=\"result\")]int read(borrowed u8[] input,borrowed u8[] output)throws Fault;}"));
		assert(parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze(parsed.unit);
		assert(analyzed.diagnostic == null);
		var core = CoreBuilder.build(analyzed.program);
		CoreFunction? selected = null;
		CoreFunction? peer = null;
		foreach (var function in core.functions) {
			if (function.name == "Provider.read") {
				selected = function;
			}
			if (function.name == "words") {
				peer = function;
			}
		}
		assert(selected != null && peer != null);
		var parameter = selected.parameters[1];
		selected.parameters[1] = new CoreParameter(parameter.span, parameter.name_span, parameter.name, peer.parameters[0].semantic_type, parameter.ordinal, PointerParameterContract.BORROWED_NOESCAPE);
		refused("Core imported byte view changed to same-shaped u16 view", () => CoreVerifier.verify(core));
		selected.parameters[1] = parameter;
		CoreVerifier.verify(core);
		var cfg = CfgBuilder.build(core);
		var ssa = SsaBuilder.build(cfg);
		SsaFunction? imported = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Provider.read") {
				imported = function;
			}
		}
		assert(imported != null);
		var native = NativeAbiBuilder.build(ssa);
		var function = native.functions[imported.ordinal];
		var original = function.signature.parameters[1];
		function.signature.parameters[1] = new NativeParameter.typed(original.span, original.name_span, original.name, original.ordinal, new NativeSliceType.borrowed(new NativeScalarAbiType(NativeScalarType.U16)));
		refused("detached native imported byte view changed element with same PTR/I32", () => NativeAbiVerifier.verify(native));
		function.signature.parameters[1] = original;
		NativeAbiVerifier.verify(native);
		var cabi = CAbiBuilder.build(ssa, native);
		CAbiForeignImport? physical = null;
		foreach (var candidate in cabi.class_imports) {
			if (candidate.native_function == imported.ordinal) {
				physical = candidate;
			}
		}
		assert(physical != null);
		var count = physical.parameters[2];
		physical.parameters[2] = CAbiScalarType.PTR;
		refused("physical imported byte count lost exact signed i32", () => CAbiVerifier.verify(cabi));
		physical.parameters[2] = count;
		CAbiVerifier.verify(cabi);
		var artifact = LlvmLowering.lower(ssa, native, cabi);
		new LlvmTargetMachineArtifact(0).configure(artifact);
		artifact.verify();
		var wrapper = CApi.named_function(artifact.module, "astra.fn.%d".printf(imported.ordinal));
		var release = CApi.named_function(artifact.module, "free");
		bool cleanup_changed = false, bound_changed = false;
		for (var block = CApi.first_block(wrapper); (void*)block != null; block = CApi.next_block(block)) {
			for (var instruction = CApi.first_instruction(block); (void*)instruction != null; instruction = CApi.next_instruction(instruction)) {
				if (CApi.opcode(instruction) == CApi.Opcode.CALL && (void*)CApi.called_value(instruction) == (void*)release && CApi.argument_count(instruction) == 1) {
					var value = CApi.operand(instruction, 0);
					CApi.set_operand(instruction, 0, CApi.const_null(CApi.type_of(value)));
					char* message;
					assert(CApi.verify_module(artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
					if (message != null) {
						CApi.dispose_message(message);
					}
					refused("ordinary-valid LLVM import omitted staged buffer retirement", () => artifact.verify());
					CApi.set_operand(instruction, 0, value);
					artifact.verify();
					cleanup_changed = true;
				}
				if (CApi.opcode(instruction) != CApi.Opcode.ICMP) {
					continue;
				}
				size_t size;
				string name = CApi.value_name(instruction, out size);
				if (!name.has_prefix("import.produced.excess")) {
					continue;
				}
				var bound = CApi.operand(instruction, 1);
				CApi.set_operand(instruction, 1, CApi.const_null(CApi.type_of(bound)));
				char* message;
				assert(CApi.verify_module(artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message(message);
				}
				refused("ordinary-valid LLVM import changed capacity bound", () => artifact.verify());
				CApi.set_operand(instruction, 1, bound);
				artifact.verify();
				bound_changed = true;
			}
		}
		assert(cleanup_changed && bound_changed);
	} catch (GLib.Error failure) {
		error("%s", failure.message);
	}
}

private void import_owned_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-import-owned-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "owned u16[] words(){var data=new u16[1];return move data;}"
			+ "[CImport(name=\"importownproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")][ForeignChannel(parameter=\"result\",encoding=\"utf8-counted\")]owned u8[] read()throws Fault;}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		CoreFunction? selected = null;
		CoreFunction? peer = null;
		foreach (var function in core.functions) {
			if (function.name == "Provider.read") {
				selected = function;
			}
			if (function.name == "words") {
				peer = function;
			}
		}
		assert (selected != null && peer != null);
		var result = selected.return_type;
		selected.return_type = peer.return_type;
		refused ("Core owned imported result changed byte element", () => CoreVerifier.verify (core));
		selected.return_type = result;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgFunction? cfg_import = null;
		foreach (var function in cfg.functions) {
			if (function.name == "Provider.read") {
				cfg_import = function;
			}
		}
		assert (cfg_import != null);
		var cfg_replacement = new CfgFunction (cfg_import.span, cfg_import.name_span, cfg_import.name, cfg_import.return_type, cfg_import.ordinal, cfg_import.parameters, cfg_import.locals, cfg_import.blocks, cfg_import.entry);
		cfg_replacement.throws_type = cfg_import.throws_type;
		cfg.functions[cfg_import.ordinal] = cfg_replacement;
		refused ("CFG imported owned result lost retirement", () => CfgVerifier.verify (cfg));
		cfg.functions[cfg_import.ordinal] = cfg_import;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaFunction? imported = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Provider.read") {
				imported = function;
			}
		}
		assert (imported != null);
		var ssa_replacement = new SsaFunction (imported.span, imported.name_span, imported.name, imported.return_type, imported.ordinal, imported.parameters, imported.blocks, imported.entry);
		ssa_replacement.throws_type = imported.throws_type;
		ssa.functions[imported.ordinal] = ssa_replacement;
		refused ("SSA imported owned result lost retirement", () => SsaVerifier.verify (ssa));
		ssa.functions[imported.ordinal] = imported;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var native_function = native.functions[imported.ordinal];
		var buffer = native_function.signature.buffer_result;
		native_function.signature.buffer_result = new NativeBufferValuePlan (new NativeScalarAbiType (NativeScalarType.U16));
		refused ("detached native imported owned result changed allocation element", () => NativeAbiVerifier.verify (native));
		native_function.signature.buffer_result = buffer;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		CAbiForeignImport? physical = null;
		foreach (var candidate in cabi.class_imports) {
			if (candidate.native_function == imported.ordinal) {
				physical = candidate;
			}
		}
		assert (physical != null);
		physical.parameters.remove_index (physical.parameters.length - 1);
		refused ("physical imported owned result omitted exact count place", () => CAbiVerifier.verify (cabi));
		physical.parameters.add (CAbiScalarType.PTR);
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (imported.ordinal));
		bool release_changed = false, copy_changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t size;
				string target = CApi.value_name (CApi.called_value (instruction), out size);
				uint index;
				if (target == "importownproof16_text_release") {
					index = 0;
					release_changed = true;
				} else if (target.has_prefix ("llvm.memcpy")) {
					index = 2;
					copy_changed = true;
				} else {
					continue;
				}
				var value = CApi.operand (instruction, index);
				CApi.set_operand (instruction, index, CApi.const_null (CApi.type_of (value)));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM imported owned result lost exact matching release or snapshot extent", () => artifact.verify ());
				CApi.set_operand (instruction, index, value);
				artifact.verify ();
			}
		}
		assert (release_changed && copy_changed);
		var helper = CApi.named_function (artifact.module, "astra.text.validate.utf8");
		var branch = CApi.block_terminator (CApi.first_block (helper));
		var condition = CApi.operand (branch, 0);
		CApi.set_operand (branch, 0, CApi.const_null (CApi.type_of (condition)));
		refused ("ordinary-valid LLVM imported owned UTF-8 lost validation", () => artifact.verify ());
		CApi.set_operand (branch, 0, condition);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void import_record_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-import-record-proof.astra",
			"struct Sample{int count;f64 scale;f64 bias;bool enabled;}struct Other{int count;f64 scale;f64 bias;bool enabled;}struct Unsigned{u32 value;}"
			+ "Other peer(Other value){return value;}"
			+ "[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "[CImport(name=\"importpodproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\",bool_abi=\"c99\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]Sample adjust(Sample input) throws Fault;}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var field = core.structs[0].fields[0];
		var signed_type = field.semantic_type;
		field.semantic_type = core.structs[2].fields[0].semantic_type;
		refused ("Core imported POD changed signedness despite identical width", () => CoreVerifier.verify (core));
		field.semantic_type = signed_type;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgFunction? cfg_import = null;
		CfgFunction? cfg_peer = null;
		foreach (var function in cfg.functions) {
			if (function.name == "Provider.adjust") {
				cfg_import = function;
			}
			if (function.name == "peer") {
				cfg_peer = function;
			}
		}
		assert (cfg_import != null && cfg_peer != null);
		var cfg_group = cfg_import.struct_parameters[0];
		cfg_import.struct_parameters[0] = new StructBoundaryGroup (cfg_group.source_ordinal, cfg_group.first_leaf, cfg_peer.struct_parameters[0].shape);
		refused ("CFG imported POD replaced nominal group with same-shaped record", () => CfgVerifier.verify (cfg));
		cfg_import.struct_parameters[0] = cfg_group;
		CfgVerifier.verify (cfg);
		var initialization = cfg_import.entry.instructions[0];
		cfg_import.entry.instructions.remove_index (0);
		refused ("CFG imported POD lost a mandatory input acquisition", () => CfgVerifier.verify (cfg));
		cfg_import.entry.instructions.insert (0, initialization);
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaFunction? imported = null;
		SsaFunction? peer = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Provider.adjust") {
				imported = function;
			}
			if (function.name == "peer") {
				peer = function;
			}
		}
		assert (imported != null && peer != null);
		var ssa_group = imported.struct_parameters[0];
		imported.struct_parameters[0] = new StructBoundaryGroup (ssa_group.source_ordinal, ssa_group.first_leaf, peer.struct_parameters[0].shape);
		refused ("SSA imported POD replaced nominal group with same-shaped record", () => SsaVerifier.verify (ssa));
		imported.struct_parameters[0] = ssa_group;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var target = native.functions[imported.ordinal];
		var native_peer = native.functions[peer.ordinal];
		var native_group = target.signature.struct_parameters[0];
		target.signature.struct_parameters[0] = new NativeStructParameterPlan (native_group.source_ordinal, native_group.first_leaf, native_peer.signature.struct_parameters[0].value_plan);
		refused ("detached native imported POD replaced equal-width nominal input", () => NativeAbiVerifier.verify (native));
		target.signature.struct_parameters[0] = native_group;
		NativeAbiVerifier.verify (native);
		var result = target.signature.struct_result;
		target.signature.struct_result = native_peer.signature.struct_result;
		refused ("detached native imported POD replaced equal-width nominal result", () => NativeAbiVerifier.verify (native));
		target.signature.struct_result = result;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		CAbiForeignImport? physical = null;
		foreach (var candidate in cabi.class_imports) {
			if (candidate.native_function == imported.ordinal) {
				physical = candidate;
			}
		}
		assert (physical != null);
		physical.parameters[1] = CAbiScalarType.I32;
		refused ("physical imported POD lost canonical const-record pointer", () => CAbiVerifier.verify (cabi));
		physical.parameters[1] = CAbiScalarType.PTR;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (imported.ordinal));
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.GEP || CApi.count_struct_element_types (CApi.gep_source_type (instruction)) != 4) {
					continue;
				}
				var index = CApi.operand (instruction, 2);
				if (CApi.const_int_zext (index) != 1) {
					continue;
				}
				CApi.set_operand (instruction, 2, CApi.const_int (CApi.type_of (index), 2, 0));
				char* message;
				int ordinary = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
				if (ordinary != 0) {
					error ("POD address mutation failed ordinary LLVM verification: %s", (string) message);
				}
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM imported POD changed field address", () => artifact.verify ());
				CApi.set_operand (instruction, 2, index);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void import_handle_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-import-handle-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "[CImport(name=\"importhandleproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]int read(borrowed Child input)throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]owned Child make()throws Fault;}"
			+ "[CImport(name=\"childproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Child{[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;}"
			+ "[CImport(name=\"otherproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Other{[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		CoreFunction? make = null;
		foreach (var function in core.functions) {
			if (function.name == "Provider.make") {
				make = function;
			}
		}
		assert (make != null);
		var result = make.return_type;
		make.return_type = core.handles[2].semantic_type;
		refused ("Core imported owned object changed nominal cleanup domain", () => CoreVerifier.verify (core));
		make.return_type = result;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgFunction? cfg_read = null;
		foreach (var function in cfg.functions) {
			if (function.name == "Provider.read") {
				cfg_read = function;
			}
		}
		assert (cfg_read != null);
		var cfg_parameter = cfg_read.parameters[1];
		cfg_read.parameters[1] = new CfgParameter (cfg_parameter.span, cfg_parameter.name_span, cfg_parameter.name, cfg.handles[2].semantic_type, 1, PointerParameterContract.BORROWED_NOESCAPE);
		refused ("CFG imported borrowed object changed nominal root despite PTR width", () => CfgVerifier.verify (cfg));
		cfg_read.parameters[1] = cfg_parameter;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaFunction? read = null;
		SsaFunction? create = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Provider.read") {
				read = function;
			}
			if (function.name == "Provider.make") {
				create = function;
			}
		}
		assert (read != null && create != null);
		var ssa_parameter = read.parameters[1];
		read.parameters[1] = new SsaFunctionParameter (ssa_parameter.span, ssa_parameter.name_span, ssa_parameter.name, ssa.handles[2].semantic_type, 1, PointerParameterContract.BORROWED_NOESCAPE);
		refused ("SSA imported borrowed object changed nominal root despite PTR width", () => SsaVerifier.verify (ssa));
		read.parameters[1] = ssa_parameter;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var target = native.functions[read.ordinal];
		var parameter = target.signature.parameters[1];
		var replacement = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, 1, parameter.abi_type);
		replacement.bind_resource (new NativeScalarOwner ("Other", "astra_foreign16_import_cleanup_otherproof16"), false);
		target.signature.parameters[1] = replacement;
		assert (!target.foreign_import.valid (native, target));
		refused ("detached native imported handle changed nominal resource with identical PTR", () => NativeAbiVerifier.verify (native));
		target.signature.parameters[1] = parameter;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		var root = cabi.class_import_roots[1];
		cabi.class_import_roots.remove_index (1);
		refused ("C ABI imported handle omitted its result root authority", () => CAbiVerifier.verify (cabi));
		cabi.class_import_roots.insert (1, root);
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (create.ordinal));
		var cleanup = CApi.named_function (artifact.module, "astra_foreign16_import_cleanup_childproof16");
		var wrong = CApi.named_function (artifact.module, "astra_foreign16_import_cleanup_otherproof16");
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) cleanup) {
					continue;
				}
				uint index = CApi.argument_count (instruction);
				CApi.set_operand (instruction, index, wrong);
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM imported owner retired through wrong root", () => artifact.verify ());
				CApi.set_operand (instruction, index, cleanup);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void import_consuming_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-import-consuming-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "[CImport(name=\"consumeproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]int take(owned Item input)throws Fault;}"
			+ "[CImport(name=\"consumeitemproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Item{[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		CoreFunction? source = null;
		foreach (var function in core.functions) {
			if (function.name == "Provider.take") {
				source = function;
			}
		}
		assert (source != null);
		var core_return = (CoreForeignReturn) source.body.statements[source.body.statements.length - 1];
		var core_owner = core_return.consumed[0];
		core_return.consumed.remove_index (0);
		refused ("Core imported consuming boundary lost its exact owner duty", () => CoreVerifier.verify (core));
		core_return.consumed.add (core_owner);
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgFunction? cfg_source = null;
		foreach (var function in cfg.functions) {
			if (function.name == "Provider.take") {
				cfg_source = function;
			}
		}
		assert (cfg_source != null);
		var cfg_return = (CfgForeignReturn) cfg_source.entry.terminator;
		var cfg_owner = cfg_return.consumed[0];
		cfg_return.consumed.remove_index (0);
		refused ("CFG imported consuming boundary lost its exact owner duty", () => CfgVerifier.verify (cfg));
		cfg_return.consumed.add (cfg_owner);
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		SsaFunction? imported = null;
		foreach (var function in ssa.functions) {
			if (function.name == "Provider.take") {
				imported = function;
			}
		}
		assert (imported != null);
		var returned = (SsaForeignReturn) imported.entry.terminator;
		var owner = returned.consumed[0];
		returned.consumed.remove_index (0);
		refused ("SSA imported consuming boundary lost its exact owner duty", () => SsaVerifier.verify (ssa));
		returned.consumed.add (owner);
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var target = native.functions[imported.ordinal];
		var parameter = target.signature.parameters[1];
		var replacement = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, 1, parameter.abi_type);
		replacement.bind_resource (parameter.resource, false);
		target.signature.parameters[1] = replacement;
		assert (!target.foreign_import.valid (native, target));
		refused ("detached native consuming Resource became borrowed despite PTR width", () => NativeAbiVerifier.verify (native));
		target.signature.parameters[1] = parameter;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (imported.ordinal));
		var provider = CApi.named_function (artifact.module, "consumeproof16_take");
		var input = CApi.get_param (wrapper, 2);
		bool slot_changed = false, disarm_changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) == CApi.Opcode.CALL && (void*) CApi.called_value (instruction) == (void*) provider) {
					var slot = CApi.operand (instruction, 1);
					CApi.set_operand (instruction, 1, input);
					char* message;
					assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
					if (message != null) {
						CApi.dispose_message (message);
					}
					refused ("ordinary-valid LLVM consuming call passed raw owner instead of private owner slot", () => artifact.verify ());
					CApi.set_operand (instruction, 1, slot);
					artifact.verify ();
					slot_changed = true;
				}
				if (CApi.opcode (instruction) != CApi.Opcode.STORE || (void*) CApi.is_constant_pointer_null (CApi.operand (instruction, 0)) == null) {
					continue;
				}
				size_t size;
				string name = CApi.value_name (CApi.operand (instruction, 1), out size);
				if (!name.has_prefix ("import.input.owner.slot")) {
					continue;
				}
				var empty = CApi.operand (instruction, 0);
				CApi.set_operand (instruction, 0, input);
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM consuming input failed to disarm before retirement", () => artifact.verify ());
				CApi.set_operand (instruction, 0, empty);
				artifact.verify ();
				disarm_changed = true;
			}
		}
		assert (slot_changed && disarm_changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void foreign_handle_exports() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-export-resource-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "[CImport(name=\"exportitemproof16\",profile=\"declarations-v1\",lifetime=\"shared\",threading=\"constructing\")]class Item{[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;}"
			+ "[CImport(name=\"exportotherproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Other{[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;}"
			+ "[CExport(name=\"exportresourceproof16\",profile=\"declarations-v1\")]class Box{[Foreign]init(){}[Foreign]int read(borrowed Item input){return 1;}[Foreign]owned Item relay(owned Item input){return move input;}}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		CoreClass? box = null;
		foreach (var candidate in core.classes) {
			if (candidate.name == "Box") {
				box = candidate;
			}
		}
		assert (box != null);
		var method = box.methods[0];
		var parameter = method.parameters[0];
		method.parameters[0] = new CoreParameter (parameter.span, parameter.name_span, parameter.name, core.handles[1].semantic_type, 0, PointerParameterContract.BORROWED_NOESCAPE);
		assert (!CoreForeignApi.valid (box, core));
		refused ("Core foreign-handle export changed nominal provider root", () => CoreVerifier.verify (core));
		method.parameters[0] = parameter;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var cfg_box = cfg.classes[box.ordinal];
		var cfg_method = cfg_box.methods[0];
		var cfg_parameter = cfg_method.parameters[0];
		cfg_method.parameters[0] = new CfgParameter (cfg_parameter.span, cfg_parameter.name_span, cfg_parameter.name, cfg.handles[1].semantic_type, 0, PointerParameterContract.BORROWED_NOESCAPE);
		assert (!CfgForeignApi.valid (cfg_box, cfg));
		refused ("CFG foreign-handle export changed nominal provider root", () => CfgVerifier.verify (cfg));
		cfg_method.parameters[0] = cfg_parameter;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var ssa_box = ssa.classes[box.ordinal];
		var ssa_method = ssa_box.methods[0];
		var ssa_parameter = ssa_method.parameters[0];
		ssa_method.parameters[0] = new SsaFunctionParameter (ssa_parameter.span, ssa_parameter.name_span, ssa_parameter.name, ssa.handles[1].semantic_type, 0, PointerParameterContract.BORROWED_NOESCAPE);
		assert (!SsaForeignApi.valid (ssa_box, ssa));
		refused ("SSA foreign-handle export changed nominal provider root", () => SsaVerifier.verify (ssa));
		ssa_method.parameters[0] = ssa_parameter;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var target = native.functions[ssa_method.ordinal];
		var native_parameter = target.signature.parameters[0];
		var replacement = new NativeParameter.typed (native_parameter.span, native_parameter.name_span, native_parameter.name, 0, native_parameter.abi_type);
		replacement.bind_resource (new NativeScalarOwner ("Other", "astra_foreign16_import_cleanup_exportotherproof16"), false);
		target.signature.parameters[0] = replacement;
		assert (!NativeForeignApi.valid (native, native.classes[box.ordinal]));
		refused ("detached native foreign-handle export substituted equal PTR resource", () => NativeAbiVerifier.verify (native));
		target.signature.parameters[0] = native_parameter;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		var root = cabi.class_import_roots[0];
		cabi.class_import_roots.remove_index (0);
		refused ("C ABI foreign-handle export omitted provider authority", () => CAbiVerifier.verify (cabi));
		cabi.class_import_roots.insert (0, root);
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "exportresourceproof16_read");
		var acquire = CApi.named_function (artifact.module, "exportitemproof16_acquire");
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) acquire) {
					continue;
				}
				var value = CApi.operand (instruction, 0);
				CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (value)));
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM foreign-handle export lost exact provider pin", () => artifact.verify ());
				CApi.set_operand (instruction, 0, value);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
		var cleanup = CApi.named_function (artifact.module, "astra_foreign16_import_cleanup_exportotherproof16");
		bool cleanup_changed = false;
		for (var block = CApi.first_block (cleanup); (void*) block != null; block = CApi.next_block (block)) {
			var branch = CApi.block_terminator (block);
			if (CApi.block_name (block) != "import.cleanup.live") {
				continue;
			}
			var condition = CApi.operand (branch, 0);
			CApi.set_operand (branch, 0, CApi.const_null (CApi.type_of (condition)));
			char* message;
			assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
			if (message != null) {
				CApi.dispose_message (message);
			}
			refused ("ordinary-valid LLVM unique provider cleanup lost complete retirement checks", () => artifact.verify ());
			CApi.set_operand (branch, 0, condition);
			artifact.verify ();
			cleanup_changed = true;
		}
		assert (cleanup_changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void import_property_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-import-property-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(string text){this.text=text;}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var fault=new Fault(\"foreign\");return move fault;}"
			+ "[CImport(name=\"propertyproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]property int amount throws Fault{get;set(int input);}"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]property int peer throws Fault{get;}}"
			+ "int read(borrowed Provider provider)throws Fault{provider.amount=5;return provider.amount+provider.peer;}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var root = analyzed.program.handles[0].c_import;
		assert (root.valid () && root.api.member_count == 4);
		assert (root.api.member (1).kind == ForeignMemberKind.GETTER && root.api.member (1).native_member_ordinal == 1);
		assert (root.api.member (2).kind == ForeignMemberKind.SETTER && root.api.member (2).native_member_ordinal == 1);
		assert (root.api.member (3).kind == ForeignMemberKind.GETTER && root.api.member (3).native_member_ordinal == 2);
		var core = CoreBuilder.build (analyzed.program);
		CoreFunction? selected = null;
		foreach (var function in core.functions) {
			if (function.name == "Provider." + root.native_name (1)) {
				selected = function;
			}
		}
		assert (selected != null);
		var marker = (CoreForeignReturn) selected.body.statements[0];
		var binding = marker.binding;
		marker.binding = new ForeignImportBinding (root, 3);
		refused ("Core property getter substituted equal-type peer", () => CoreVerifier.verify (core));
		marker.binding = binding;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		CfgFunction? cfg_function = null;
		foreach (var candidate in cfg.functions) {
			if (candidate.name == selected.name) {
				cfg_function = candidate;
			}
		}
		assert (cfg_function != null);
		var cfg_marker = (CfgForeignReturn) cfg_function.entry.terminator;
		cfg_marker.binding = new ForeignImportBinding (root, 3);
		refused ("CFG property getter lost its selected accessor", () => CfgVerifier.verify (cfg));
		cfg_marker.binding = binding;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var imported = ssa.functions[cfg_function.ordinal];
		var ssa_marker = (SsaForeignReturn) imported.entry.terminator;
		ssa_marker.binding = new ForeignImportBinding (root, 3);
		refused ("SSA property getter changed nominal member ordinal", () => SsaVerifier.verify (ssa));
		ssa_marker.binding = binding;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var function = native.functions[imported.ordinal];
		var plan = function.foreign_import;
		function.foreign_import = new NativeForeignImportPlan (new ForeignImportBinding (root, 3), plan.error_factory);
		refused ("native property getter rebound to equal physical signature", () => NativeAbiVerifier.verify (native));
		function.foreign_import = plan;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		CAbiForeignImport? physical = null;
		foreach (var candidate in cabi.class_imports) {
			if (candidate.native_function == imported.ordinal) {
				physical = candidate;
			}
		}
		assert (physical != null);
		physical.native_function++;
		refused ("C ABI property getter rebound to setter", () => CAbiVerifier.verify (cabi));
		physical.native_function--;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (imported.ordinal));
		var getter = CApi.named_function (artifact.module, "propertyproof16_get_amount");
		var peer = CApi.named_function (artifact.module, "propertyproof16_get_peer");
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) getter) {
					continue;
				}
				uint target = (uint) CApi.operand_count (instruction) - 1;
				CApi.set_operand (instruction, target, peer);
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM property accessor called equal-signature peer", () => artifact.verify ());
				CApi.set_operand (instruction, target, getter);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void void_callable_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("native-void-callable-proof.astra",
			"void apply(Fn<void,int> code){code(5);}int peer(Fn<int,int> code){return code(5);}"));
		assert (parsed.diagnostic == null);
		var analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		var core = CoreBuilder.build (analyzed.program);
		var apply = core.functions[0];
		var peer = core.functions[1];
		var statement = (CoreValueStatement) apply.body.statements[0];
		var call = (CoreFunctionValueCall) statement.value;
		var fake = new CoreFunctionValueCall (call.span, (FunctionValueType) peer.parameters[0].semantic_type, call.callee, call.arguments);
		apply.body.statements[0] = new CoreValueStatement (statement.span, fake);
		refused ("Core void callable forged a scalar result", () => CoreVerifier.verify (core));
		apply.body.statements[0] = statement;
		CoreVerifier.verify (core);
		var cfg = CfgBuilder.build (core);
		var cfg_apply = cfg.functions[0];
		CfgEvaluateInstruction? evaluation = null;
		int position = -1;
		for (int i = 0; i < cfg_apply.entry.instructions.length; i++) {
			var candidate = cfg_apply.entry.instructions[i] as CfgEvaluateInstruction;
			if (candidate != null && candidate.value is CfgFunctionValueCall) {
				evaluation = candidate;
				position = i;
			}
		}
		assert (evaluation != null && position >= 0);
		var cfg_call = (CfgFunctionValueCall) evaluation.value;
		var cfg_fake = new CfgFunctionValueCall (cfg_call.span, (FunctionValueType) cfg.functions[1].parameters[0].semantic_type, cfg_call.callee, cfg_call.arguments);
		cfg_apply.entry.instructions[position] = new CfgEvaluateInstruction (evaluation.span, cfg_fake, new CfgEvaluatedValue (evaluation.span, cfg_fake.semantic_type));
		refused ("CFG void callable forged an evaluated scalar", () => CfgVerifier.verify (cfg));
		cfg_apply.entry.instructions[position] = evaluation;
		CfgVerifier.verify (cfg);
		var ssa = SsaBuilder.build (cfg);
		var ssa_apply = ssa.functions[0];
		SsaFunctionValueCall? invocation = null;
		position = -1;
		for (int i = 0; i < ssa_apply.entry.instructions.length; i++) {
			if (ssa_apply.entry.instructions[i] is SsaFunctionValueCall) {
				invocation = (SsaFunctionValueCall) ssa_apply.entry.instructions[i];
				position = i;
			}
		}
		assert (invocation != null && invocation.result == null);
		ssa_apply.entry.instructions[position] = new SsaFunctionValueCall (invocation.span, (FunctionValueType) ssa.functions[1].parameters[0].semantic_type, invocation.callee, invocation.arguments, 999999);
		refused ("SSA void callable acquired a scalar definition", () => SsaVerifier.verify (ssa));
		ssa_apply.entry.instructions[position] = invocation;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var original = native.function_values[0].signature;
		assert (original.void_result && original.result_scalar () == null && original.record_result == null);
		var contradictory = new NativeFunctionPointerType (NativeScalarType.I32, original.parameter_types, null, null, null, null, null, true);
		refused ("native callable claimed both void and scalar results", () => NativeAbiVerifier.verify_type (contradictory, native.abi_version, "void proof"));
		var omitted = new NativeFunctionPointerType (null, original.parameter_types);
		refused ("native callable omitted its explicit result channel", () => NativeAbiVerifier.verify_type (omitted, native.abi_version, "void proof"));
		assert (!original.same_type (new NativeFunctionPointerType (NativeScalarType.I32, original.parameter_types)));
		var artifact = LlvmLowering.lower (ssa, native, CAbiBuilder.build (ssa, native));
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (ssa_apply.ordinal));
		bool changed = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || CApi.instruction_call_conv (instruction) != LlvmLowering.CALL_CONVENTION) {
					continue;
				}
				CApi.set_instruction_call_conv (instruction, CApi.CallConv.C);
				char* message;
				assert (CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message) == 0);
				if (message != null) {
					CApi.dispose_message (message);
				}
				refused ("ordinary-valid LLVM void callable lost native calling convention", () => artifact.verify ());
				CApi.set_instruction_call_conv (instruction, LlvmLowering.CALL_CONVENTION);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void callback_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("typed-callback-proof.astra",
			"[CExport(name=\"callbackproof16\",profile=\"declarations-v1\",bool_abi=\"c99\")]class Service{[Foreign]init(){}[Foreign]bool choose(borrowed Callback<bool,bool> code){return code(true);}}"
			+ "bool peer(Fn<bool,bool> code){return code(true);}"
			+ "[ExceptionRoot]class Fault{readonly string text;init(){this.text=\"foreign\";}virtual property string message{get{return this.text;}}}"
			+ "owned Fault imported_error(int domain,int status){var error=new Fault();return move error;}"
			+ "[CImport(name=\"callbackimportproof16\",profile=\"declarations-v1\",lifetime=\"unique\",threading=\"constructing\",bool_abi=\"c99\")]class Provider{"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]init()throws Fault;"
			+ "[Foreign(error_factory=\"imported_error\",error_domain=\"16\",errors=\"Fault=-1600\")]bool choose(borrowed Callback<bool,bool> code)throws Fault;}"));
		assert (parsed.diagnostic == null);
		SemanticResult? analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var upstream = WeakRef (checked.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (upstream.get () == null);
		CoreFunction? peer = null;
		foreach (var function in core.functions) {
			if (function.name == "peer") {
				peer = function;
			}
		}
		assert (peer != null);
		var member = core.classes[0].methods[0];
		var parameter = member.parameters[0];
		member.parameters[0] = peer.parameters[0];
		assert (!CoreForeignApi.valid (core.classes[0]));
		refused ("detached Core callback replaced by context-free Fn", () => CoreVerifier.verify (core));
		member.parameters[0] = parameter;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		CfgFunction? cfg_peer = null;
		foreach (var function in cfg.functions) {
			if (function.name == "peer") {
				cfg_peer = function;
			}
		}
		assert (cfg_peer != null);
		var cfg_member = cfg.classes[0].methods[0];
		var cfg_parameter = cfg_member.parameters[0];
		cfg_member.parameters[0] = cfg_peer.parameters[0];
		assert (!CfgForeignApi.valid (cfg.classes[0]));
		refused ("detached CFG callback lost intrinsic context", () => CfgVerifier.verify (cfg));
		cfg_member.parameters[0] = cfg_parameter;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		SsaFunction? ssa_peer = null;
		SsaFunction? imported = null;
		foreach (var function in ssa.functions) {
			if (function.name == "peer") {
				ssa_peer = function;
			}
			if (function.name == "Provider.choose") {
				imported = function;
			}
		}
		assert (ssa_peer != null && imported != null);
		var ssa_member = ssa.classes[0].methods[0];
		var ssa_parameter = ssa_member.parameters[0];
		ssa_member.parameters[0] = ssa_peer.parameters[0];
		assert (!SsaForeignApi.valid (ssa.classes[0]));
		refused ("detached SSA callback replaced by identical-width Fn", () => SsaVerifier.verify (ssa));
		ssa_member.parameters[0] = ssa_parameter;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var target = native.functions[ssa_member.ordinal];
		var native_parameter = target.signature.parameters[0];
		var callback = native_parameter.abi_type as NativeCallbackType;
		assert (callback != null);
		var plain = native.functions[ssa_peer.ordinal].signature.parameters[0];
		assert (!callback.same_type (plain.abi_type) && !plain.abi_type.same_type (callback));
		target.signature.parameters[0] = plain;
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("native callback cannot lose context despite identical physical PTR", () => NativeAbiVerifier.verify (native));
		target.signature.parameters[0] = native_parameter;
		NativeAbiVerifier.verify (native);
		var import_target = native.functions[imported.ordinal];
		var import_parameter = import_target.signature.parameters[1];
		import_target.signature.parameters[1] = plain;
		assert (!import_target.foreign_import.valid (native, import_target));
		refused ("native imported callback cannot become raw Fn", () => NativeAbiVerifier.verify (native));
		import_target.signature.parameters[1] = import_parameter;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		CAbiForeignImport? physical = null;
		foreach (var candidate in cabi.class_imports) {
			if (candidate.native_function == imported.ordinal) {
				physical = candidate;
			}
		}
		assert (physical != null && physical.parameters.length == 5);
		physical.parameters.remove_index (2);
		refused ("C ABI imported callback omitted intrinsic userdata PTR", () => CAbiVerifier.verify (cabi));
		physical.parameters.insert (2, CAbiScalarType.PTR);
		CAbiVerifier.verify (cabi);
		upstream = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		uint address_mutants = 0, context_mutants = 0, convention_mutants = 0, boolean_mutants = 0;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			string name = CApi.value_name (function, out length);
			if (!name.has_prefix ("astra.callback.from.c.") && !name.has_prefix ("astra.callback.to.c.")) {
				continue;
			}
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) == CApi.Opcode.GEP) {
						var index = CApi.operand (instruction, 2);
						uint64 member_index = CApi.const_int_zext (index);
						assert (member_index < 2);
						CApi.set_operand (instruction, 2, CApi.const_int (CApi.type_of (index), 1 - member_index, 0));
						ordinary_callback_module (artifact);
						refused ("ordinary-valid LLVM callback code/context field swap", () => artifact.verify ());
						CApi.set_operand (instruction, 2, index);
						artifact.verify ();
						address_mutants++;
					}
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					var context = CApi.operand (instruction, 0);
					CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (context)));
					ordinary_callback_module (artifact);
					refused ("ordinary-valid LLVM callback lost exact userdata", () => artifact.verify ());
					CApi.set_operand (instruction, 0, context);
					artifact.verify ();
					context_mutants++;
					uint convention = CApi.instruction_call_conv (instruction);
					CApi.set_instruction_call_conv (instruction, convention == CApi.CallConv.C ? LlvmLowering.CALL_CONVENTION : CApi.CallConv.C);
					ordinary_callback_module (artifact);
					refused ("ordinary-valid LLVM callback changed C/native calling convention", () => artifact.verify ());
					CApi.set_instruction_call_conv (instruction, convention);
					artifact.verify ();
					convention_mutants++;
					if (name.has_prefix ("astra.callback.from.c.")) {
						uint zeroext = CApi.enum_attribute_kind ("zeroext", 7);
						CApi.remove_call_enum_attribute (instruction, 2, zeroext);
						ordinary_callback_module (artifact);
						refused ("ordinary-valid C callback bool lost exact extension", () => artifact.verify ());
						CApi.add_call_attribute (instruction, 2, CApi.create_enum_attribute (artifact.context, zeroext, 0));
						artifact.verify ();
						boolean_mutants++;
					}
				}
			}
			if (name.has_prefix ("astra.callback.to.c.")) {
				uint zeroext = CApi.enum_attribute_kind ("zeroext", 7);
				CApi.remove_enum_attribute (function, 0, zeroext);
				ordinary_callback_module (artifact);
				refused ("ordinary-valid C callback thunk result lost bool extension", () => artifact.verify ());
				CApi.add_attribute (function, 0, CApi.create_enum_attribute (artifact.context, zeroext, 0));
				artifact.verify ();
				boolean_mutants++;
			}
		}
		assert (address_mutants == 4 && context_mutants == 2 && convention_mutants == 2 && boolean_mutants == 2);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void ordinary_callback_module(LlvmModuleArtifact artifact) {
	char* message;
	int status = CApi.verify_module (artifact.module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
	if (status != 0) {
		error ("callback mutation failed ordinary LLVM verification: %s", (string) message);
	}
	if (message != null) {
		CApi.dispose_message (message);
	}
}

private ForeignImportContract forged_com_parent(ForeignImportContract original) {
	var parent = original.com.parent;
	var parent_members = new GenericArray<ForeignMemberContract> ();
	string[] parent_names = {};
	for (uint m = 0; m < parent.own_count; m++) {
		parent_members.add (parent.requirement (parent.inherited_count + m));
		parent_names += "altered_binding_" + m.to_string ();
	}
	var changed = new ForeignComInterface (parent.name, parent.prefix, parent.iid, parent_members, parent_names, parent.parent);
	var members = new GenericArray<ForeignMemberContract> ();
	string[] names = {}, factories = {}, native_names = {};
	for (uint m = 0; m < original.com.own_count; m++) {
		members.add (original.com.requirement (original.com.inherited_count + m));
		names += original.com.native_name (original.com.inherited_count + m);
	}
	for (uint m = 0; m < original.api.member_count; m++) {
		factories += original.factory (m);
		native_names += original.native_name (m);
	}
	var result = new ForeignImportContract (original.api, factories, native_names, new ForeignComInterface (original.com.name, original.com.prefix, original.com.iid, members, names, changed));
	assert (result.valid () && !result.equal (original));
	return result;
}

private void com_import_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("typed-com-detached-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(){this.text=\"COM\";}virtual property string message{get{return this.text;}}}owned Fault fault(int domain,int status){var result=new Fault();return move result;}"
			+ "[COMImport(name=\"baseproof16\",iid=\"2c2d4a08-a483-4ace-9e01-f6793e47f201\",threading=\"constructing\",profile=\"declarations-v1\")]interface IBase{"
			+ "[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]init(borrowed void* unknown)throws Fault;"
			+ "[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]i64 read(i64 input)throws Fault;}"
			+ "[COMImport(name=\"derivedproof16\",iid=\"2c2d4a08-a483-4ace-9e01-f6793e47f202\",threading=\"constructing\",profile=\"declarations-v1\")]interface IDerived:IBase{"
			+ "[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]init(borrowed void* unknown)throws Fault;"
			+ "[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]bool choose(borrowed Callback<bool,bool> code)throws Fault;}"));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var upstream = WeakRef (checked.program.handles[1]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		assert (core.handles.length == 2);
		var original = core.handles[1].c_import;
		core.handles[1].c_import = forged_com_parent (original);
		refused ("Core COM changed inherited binding despite identical IID and scalar widths", () => CoreVerifier.verify (core));
		core.handles[1].c_import = original;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.handles[1]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		original = cfg.handles[1].c_import;
		cfg.handles[1].c_import = forged_com_parent (original);
		refused ("CFG COM parent differs from the independently declared base", () => CfgVerifier.verify (cfg));
		cfg.handles[1].c_import = original;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.handles[1]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		original = ssa.handles[1].c_import;
		ssa.handles[1].c_import = forged_com_parent (original);
		refused ("SSA COM changed inherited native mapping", () => SsaVerifier.verify (ssa));
		ssa.handles[1].c_import = original;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var root = native.class_imports[1];
		native.class_imports[1] = forged_com_parent (root);
		refused ("native COM omitted original inherited declaration authority", () => NativeAbiVerifier.verify (native));
		native.class_imports[1] = root;
		NativeAbiVerifier.verify (native);
		NativeFunction? acquisition = null;
		foreach (var function in native.functions) {
			if (function.foreign_import != null && function.foreign_import.binding.root.com != null && function.foreign_import.binding.member.kind == ForeignMemberKind.CONSTRUCTOR) {
				acquisition = function;
				break;
			}
		}
		assert (acquisition != null);
		var parameter = acquisition.signature.parameters[0];
		assert (parameter.com_unknown_borrow != null);
		acquisition.signature.parameters[0] = new NativeParameter.typed (parameter.span, parameter.name_span, parameter.name, parameter.ordinal, parameter.abi_type);
		refused ("native COM raw PTR omitted exact call-only IUnknown acquisition origin", () => NativeAbiVerifier.verify (native));
		acquisition.signature.parameters[0] = parameter;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		root = cabi.class_import_roots[1];
		cabi.class_import_roots[1] = forged_com_parent (root);
		refused ("C ABI COM protocol parent changed behind equal C transport", () => CAbiVerifier.verify (cabi));
		cabi.class_import_roots[1] = root;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP).configure (artifact);
		artifact.verify ();
		bool changed = false;
		var wrapper = CApi.named_function (artifact.module, "astra.fn.%d".printf (acquisition.ordinal));
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
					continue;
				}
				size_t length;
				string name = CApi.value_name (CApi.called_value (instruction), out length);
				if (name != "baseproof16_acquire") {
					continue;
				}
				var unknown = CApi.operand (instruction, 0);
				CApi.set_operand (instruction, 0, CApi.const_null (CApi.type_of (unknown)));
				ordinary_callback_module (artifact);
				refused ("ordinary-valid LLVM COM query lost its exact borrowed IUnknown", () => artifact.verify ());
				CApi.set_operand (instruction, 0, unknown);
				artifact.verify ();
				changed = true;
			}
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private ForeignClassPolicy rebound_com_export(ForeignClassPolicy original) {
	var binding = original.com_binding (0);
	uint[] targets = {
		binding.target (1), binding.target (0)
	};
	var bindings = new GenericArray<ForeignComExportBinding> ();
	bindings.add (new ForeignComExportBinding (binding.protocol, original.declared_api, targets));
	var changed = new ForeignClassPolicy.declared (original.declared_api, bindings);
	assert (changed.valid () && changed.identity () != original.identity ());
	return changed;
}

private void com_export_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("typed-com-export-proof.astra",
			"[ExceptionRoot]class Fault{readonly string text;init(){this.text=\"COM\";}virtual property string message{get{return this.text;}}}owned Fault fault(int domain,int status){var result=new Fault();return move result;}"
			+ "[COMImport(name=\"exportproof16\",iid=\"2c2d4a08-a483-4ace-9e01-f6793e47f211\",threading=\"constructing\",profile=\"declarations-v1\")]interface IProof{"
			+ "[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]init(borrowed void* unknown)throws Fault;"
			+ "[Foreign(native=\"first\",error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]i64 read(i64 input)throws Fault;"
			+ "[Foreign(native=\"second\",error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]i64 inspect(i64 input)throws Fault;}"
			+ "[Shared][CExport(name=\"nativecomproof16\",profile=\"declarations-v1\")][COMExport(interfaces=\"IProof\",threading=\"constructing\",profile=\"declarations-v1\")]class Service{[Foreign]init(){}[Foreign]i64 first(i64 input){return input+1;}[Foreign]i64 second(i64 input){return input+2;}}"));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		ClassSymbol? selected = null;
		foreach (var owner in checked.program.classes) {
			if (owner.name == "Service") {
				selected = owner;
			}
		}
		assert (selected != null);
		var policy = selected.foreign_export;
		var changed = rebound_com_export (policy);
		selected.foreign_export = changed;
		refused ("Checked COM swapped equal-signature resolved native methods", () => { CoreBuilder.build (checked.program);
		});
		selected.foreign_export = policy;
		selected = null;
		var upstream = WeakRef (checked.program.classes[1]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		core.classes[1].foreign_export = changed;
		refused ("detached Core COM export lost exact requirement targets", () => CoreVerifier.verify (core));
		core.classes[1].foreign_export = policy;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[1]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		cfg.classes[1].foreign_export = changed;
		refused ("detached CFG COM export swapped same-width slots", () => CfgVerifier.verify (cfg));
		cfg.classes[1].foreign_export = policy;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[1]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		ssa.classes[1].foreign_export = changed;
		refused ("detached SSA COM export changed exact native binding", () => SsaVerifier.verify (ssa));
		ssa.classes[1].foreign_export = policy;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		native.classes[1].foreign_export = changed;
		refused ("native COM export replaced its immutable implementation mapping", () => NativeAbiVerifier.verify (native));
		native.classes[1].foreign_export = policy;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		var adapter = cabi.class_adapters[0];
		adapter.policy = changed;
		refused ("C ABI COM export changed protocol targets behind same C functions", () => CAbiVerifier.verify (cabi));
		adapter.policy = policy;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP).configure (artifact);
		artifact.verify ();
		var wrapper = CApi.named_function (artifact.module, "nativecomproof16_first");
		var target = CApi.named_function (artifact.module, "astra.class.method.1.%d".printf (native.functions[native.classes[1].foreign_member (1)].method_ordinal));
		var peer = CApi.named_function (artifact.module, "astra.class.method.1.%d".printf (native.functions[native.classes[1].foreign_member (2)].method_ordinal));
		bool mutated = false;
		for (var block = CApi.first_block (wrapper); (void*) block != null; block = CApi.next_block (block)) {
			for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
				if (CApi.opcode (instruction) != CApi.Opcode.CALL || (void*) CApi.called_value (instruction) != (void*) target) {
					continue;
				}
				uint position = (uint) CApi.operand_count (instruction) - 1;
				CApi.set_operand (instruction, position, peer);
				ordinary_callback_module (artifact);
				refused ("ordinary-valid LLVM COM native operation called equal-signature peer", () => artifact.verify ());
				CApi.set_operand (instruction, position, target);
				artifact.verify ();
				mutated = true;
			}
		}
		assert (mutated);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void com_native_root_bindings() {
	try {
		string start = "[ExceptionRoot]class Fault{readonly string text;init(){this.text=\"COM\";}virtual property string message{get{return this.text;}}}owned Fault fault(int domain,int status){var result=new Fault();return move result;}";
		string attribute = "[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]";
		string declaration = start;
		foreach (string name in new string[] { "IValue", "IAlternate", "IProducer" }) {
			string suffix = name == "IValue" ? "221" : name == "IAlternate" ? "222" : "223";
			declaration += "[COMImport(name=\"" + name.ascii_down () + "proof16\",iid=\"2c2d4a08-a483-4ace-9e01-f6793e47f" + suffix + "\",threading=\"constructing\",profile=\"declarations-v1\")]interface " + name + "{" + attribute + "init(borrowed void* unknown)throws Fault;" + attribute + (name == "IProducer" ? "owned IValue make()throws Fault;" : "i64 read(i64 input)throws Fault;") + "}";
		}
		declaration += "[Shared][CExport(name=\"nativevalueproof16\",profile=\"declarations-v1\")][COMExport(interfaces=\"IValue\",threading=\"constructing\",profile=\"declarations-v1\")]class Value{[Foreign]init(){}[Foreign]i64 read(i64 input){return input+1;}}";
		declaration += "[Shared][CExport(name=\"nativeproducerproof16\",profile=\"declarations-v1\")][COMExport(interfaces=\"IProducer\",threading=\"constructing\",profile=\"declarations-v1\")]class Producer{[Foreign]init(){}[Foreign]owned Value make(){var result=new Value();return move result;}}";
		var parsed = Parser.parse (new SourceFile.from_text ("native-com-root-proof.astra", declaration));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var policy = checked.program.classes[1].foreign_export;
		var bindings = new GenericArray<ForeignComExportBinding> ();
		bindings.add (new ForeignComExportBinding (checked.program.handles[1].c_import.com, policy.declared_api, new uint[] { 1 }));
		var changed = new ForeignClassPolicy.declared (policy.declared_api, bindings);
		assert (changed.valid ());
		var upstream = WeakRef (checked.program.classes[2]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		core.classes[1].foreign_export = changed;
		assert (!CoreForeignApi.valid (core.classes[2], core));
		refused ("detached Core native Class result lost required COM interface despite identical C API", () => CoreVerifier.verify (core));
		core.classes[1].foreign_export = policy;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[2]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		cfg.classes[1].foreign_export = changed;
		assert (!CfgForeignApi.valid (cfg.classes[2], cfg));
		refused ("detached CFG native Class result changed interface brand", () => CfgVerifier.verify (cfg));
		cfg.classes[1].foreign_export = policy;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[2]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		ssa.classes[1].foreign_export = changed;
		assert (!SsaForeignApi.valid (ssa.classes[2], ssa));
		refused ("detached SSA native Class result changed interface brand", () => SsaVerifier.verify (ssa));
		ssa.classes[1].foreign_export = policy;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		native.classes[1].foreign_export = changed;
		assert (!NativeForeignApi.valid (native, native.classes[2]));
		refused ("native Class COM projection cannot substitute an unrelated declared interface", () => NativeAbiVerifier.verify (native));
		native.classes[1].foreign_export = policy;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		cabi.class_adapters[0].policy = changed;
		refused ("C ABI native Class COM result lost required root view", () => CAbiVerifier.verify (cabi));
		cabi.class_adapters[0].policy = policy;
		CAbiVerifier.verify (cabi);
		var function = native.functions[native.classes[2].foreign_member (1)];
		var origin = function.signature.heap_result;
		function.signature.heap_result = new NativeObjectOriginPlan (2, native.classes[2].name, true);
		refused ("native COM Class result substituted equal-width owner of another root", () => NativeAbiVerifier.verify (native));
		function.signature.heap_result = origin;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, cabi, null, null, false, false, null, LlvmTargetMachineArtifact.WINDOWS_INTEROP);
		new LlvmTargetMachineArtifact (0, LlvmTargetMachineArtifact.WINDOWS_INTEROP).configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private ForeignClassPolicy duplicate_gobject_type(ForeignClassPolicy original, GObjectExportContract other) {
	var changed = new ForeignClassPolicy.declared (original.declared_api, null, new GObjectExportContract (other.type_name, other.namespace_name, other.version, true));
	assert (changed.valid () && changed.identity () != original.identity ());
	return changed;
}

private void gobject_declaration_bindings() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("declared-gobject-detached-proof.astra",
			"[Shared][CExport(name=\"gobjectone16\",profile=\"declarations-v1\",bool_abi=\"c99\")][GObjectExport(type=\"Proof16One\",namespace=\"Proof16\",version=\"2.3\",profile=\"declarations-v1\")]class One{private bool flag;[Foreign]init(){this.flag=true;}[Foreign]property bool enabled{get{return this.flag;}set(bool input){this.flag=input;}}}"
			+ "[Shared][CExport(name=\"gobjecttwo16\",profile=\"declarations-v1\")][GObjectExport(type=\"Proof16Two\",namespace=\"Proof16\",version=\"2.3\",profile=\"declarations-v1\")]class Two{[Foreign]init(){}[Foreign]int code(int input){return input+2;}}"));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var first = checked.program.classes[0].foreign_export;
		var second = checked.program.classes[1].foreign_export;
		var changed = duplicate_gobject_type (second, first.gobject);
		var upstream = WeakRef (checked.program.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		core.classes[1].foreign_export = changed;
		assert (!CoreForeignApi.valid (core.classes[0], core));
		refused ("detached Core GObject type collision behind a different valid native C API", () => CoreVerifier.verify (core));
		core.classes[1].foreign_export = second;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		cfg.classes[1].foreign_export = changed;
		assert (!CfgForeignApi.valid (cfg.classes[0], cfg));
		refused ("detached CFG GObject namespace/type collision", () => CfgVerifier.verify (cfg));
		cfg.classes[1].foreign_export = second;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		ssa.classes[1].foreign_export = changed;
		assert (!SsaForeignApi.valid (ssa.classes[0], ssa));
		refused ("detached SSA GObject type collision", () => SsaVerifier.verify (ssa));
		ssa.classes[1].foreign_export = second;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		native.classes[1].foreign_export = changed;
		assert (!NativeForeignApi.valid (native, native.classes[0]));
		refused ("native GObject type collision cannot hide behind pointer-width equality", () => NativeAbiVerifier.verify (native));
		native.classes[1].foreign_export = second;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		cabi.class_adapters[1].policy = changed;
		refused ("C ABI GObject collision lost independently retained native type authority", () => CAbiVerifier.verify (cabi));
		cabi.class_adapters[1].policy = second;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var setter = CApi.named_function (artifact.module, "gobjectone16_set_enabled");
		assert ((void*) setter != null);
		uint zeroext = CApi.enum_attribute_kind ("zeroext", 7);
		CApi.remove_enum_attribute (setter, 2, zeroext);
		ordinary_callback_module (artifact);
		refused ("ordinary-valid LLVM GObject internal C bool omitted exact extension", () => artifact.verify ());
		CApi.add_attribute (setter, 2, CApi.create_enum_attribute (artifact.context, zeroext, 0));
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void gobject_object_roots() {
	try {
		string root = "[Shared][CExport(name=\"goitemproof16\",profile=\"declarations-v1\")]";
		string go = "[GObjectExport(type=\"Proof16Item\",namespace=\"Proof16\",version=\"2.3\",profile=\"declarations-v1\")]";
		string body = "class Item{[Foreign]init(){}[Foreign]int code(){return 7;}}";
		var parsed = Parser.parse (new SourceFile.from_text ("gobject-object-roots.astra", root + go + body + "[Shared][CExport(name=\"goproducerproof16\",profile=\"declarations-v1\")][GObjectExport(type=\"Proof16Producer\",namespace=\"Proof16\",version=\"2.3\",profile=\"declarations-v1\")]class Producer{[Foreign]init(){}[Foreign]owned Item make(){var result=new Item();return move result;}[Foreign]int inspect(borrowed Item input){return input.code();}[Foreign]property owned Item current{get{var result=new Item();return move result;}}}"));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var original = checked.program.classes[0].foreign_export;
		var separate = Parser.parse (new SourceFile.from_text ("gobject-object-c-only.astra", root + body));
		var altered = SemanticAnalyzer.analyze (separate.unit);
		assert (altered.diagnostic == null);
		var changed = altered.program.classes[0].foreign_export;
		assert (changed.valid () && changed.gobject == null && changed.native_name == original.native_name);
		altered = null;
		var upstream = WeakRef (checked.program.classes[1]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		core.classes[0].foreign_export = changed;
		assert (!CoreForeignApi.valid (core.classes[1], core));
		refused ("detached Core object channel lost exact GObject root despite valid C root", () => CoreVerifier.verify (core));
		core.classes[0].foreign_export = original;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[1]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		cfg.classes[0].foreign_export = changed;
		assert (!CfgForeignApi.valid (cfg.classes[1], cfg));
		refused ("detached CFG object channel lost GType projection", () => CfgVerifier.verify (cfg));
		cfg.classes[0].foreign_export = original;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[1]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		ssa.classes[0].foreign_export = changed;
		assert (!SsaForeignApi.valid (ssa.classes[1], ssa));
		refused ("detached SSA object channel lost GType projection", () => SsaVerifier.verify (ssa));
		ssa.classes[0].foreign_export = original;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		native.classes[0].foreign_export = changed;
		assert (!NativeForeignApi.valid (native, native.classes[1]));
		refused ("native object channel cannot borrow a C-only root as GObject", () => NativeAbiVerifier.verify (native));
		native.classes[0].foreign_export = original;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		cabi.class_adapters[0].policy = changed;
		refused ("C ABI object channel lost exact GObject view", () => CAbiVerifier.verify (cabi));
		cabi.class_adapters[0].policy = original;
		CAbiVerifier.verify (cabi);
		var getter = native.functions[native.classes[1].foreign_member (3)];
		var exact = getter.signature.heap_result;
		assert (exact != null);
		getter.signature.heap_result = new NativeObjectOriginPlan (1, native.classes[1].name, true);
		refused ("GObject owning property cannot substitute parent root origin", () => NativeAbiVerifier.verify (native));
		getter.signature.heap_result = exact;
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private ForeignImportContract forged_gobject_import(ForeignImportContract original, bool boxed) {
	string[] names = {}, factories = {};
	for (uint m = 0; m < original.api.member_count; m++) {
		factories += original.factory (m);
		names += original.native_name (m);
	}
	var meta = original.gobject;
	var changed = new ForeignImportContract (original.api, factories, names, null, new ForeignGObjectImport (meta.type_name, meta.namespace_name, meta.version, meta.symbol_prefix, boxed ? meta.header : "altered-sdk.h", boxed ? "Sample=AlteredSample:altered_sample" : meta.record_bindings));
	assert (changed.valid () && !changed.equal (original));
	return changed;
}

private void gobject_import_bindings() {
	gobject_import_bindings_case (false);
}

private void gobject_import_record_bindings() {
	gobject_import_bindings_case (true);
}

private void gobject_import_bindings_case(bool boxed) {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("typed-gobject-import-proof.astra", "struct Sample{bool flag;f64 value;}[ExceptionRoot]class Fault{readonly string text;init(){this.text=\"GLib\";}virtual property string message{get{return this.text;}}}owned Fault fault(int domain,int status){var result=new Fault();return move result;}[GObjectImport(records=\"Sample=ExternalSample:external_sample\",name=\"gotypeproof16\",type=\"ExternalObject\",namespace=\"ForeignApi\",version=\"3.2\",symbol_prefix=\"external_object\",header=\"external.h\",threading=\"constructing\",profile=\"declarations-v1\")]class External{[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]init(int seed,bool active)throws Fault;[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]Sample fold(Sample input)throws Fault;}"));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var upstream = WeakRef (checked.program.handles[0]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		var original = core.handles[0].c_import;
		core.handles[0].c_import = forged_gobject_import (original, boxed);
		refused ("detached Core GObject changed SDK behind identical logical members", () => CoreVerifier.verify (core));
		core.handles[0].c_import = original;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.handles[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		original = cfg.handles[0].c_import;
		cfg.handles[0].c_import = forged_gobject_import (original, boxed);
		refused ("detached CFG GObject SDK origin changed", () => CfgVerifier.verify (cfg));
		cfg.handles[0].c_import = original;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.handles[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		original = ssa.handles[0].c_import;
		ssa.handles[0].c_import = forged_gobject_import (original, boxed);
		refused ("detached SSA GObject SDK origin changed", () => SsaVerifier.verify (ssa));
		ssa.handles[0].c_import = original;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		original = native.class_imports[0];
		native.class_imports[0] = forged_gobject_import (original, boxed);
		refused ("native GObject import lost independently admitted SDK identity", () => NativeAbiVerifier.verify (native));
		native.class_imports[0] = original;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		original = cabi.class_import_roots[0];
		cabi.class_import_roots[0] = forged_gobject_import (original, boxed);
		refused ("C ABI GObject import changed SDK behind equal pointer widths", () => CAbiVerifier.verify (cabi));
		cabi.class_import_roots[0] = original;
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void personality_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("personality-proof.astra", "[CExport(name=\"personalityproof16\",profile=\"declarations-v1\")]class Cell{[Foreign]init(){}[Foreign]int evaluate(int input){return input+7;}}"));
		assert (parsed.diagnostic == null);
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (parsed.unit);
		var syntax = new SyntaxProgram (units);
		SemanticResult? checked = SemanticAnalyzer.analyze_program (syntax, null, null, null, null, null, 0);
		assert (checked.diagnostic == null);
		var original = checked.program.classes[0].foreign_export;
		var api = original.declared_api;
		assert (api.active_personalities == 0 && api.declared_personalities == ForeignClassPolicy.C);
		var members = new GenericArray<ForeignMemberContract> ();
		for (uint m = 0; m < api.member_count; m++) {
			members.add (api.member (m));
		}
		var substituted = new ForeignClassPolicy.declared (new ForeignApiContract (api.native_origin, api.prefix, api.lifetime, api.declared_personalities, members, 1));
		assert (substituted.valid () && !api.equal (substituted.declared_api) && api.identity () != substituted.declared_api.identity ());
		var upstream = WeakRef (checked.program.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		core.classes[0].foreign_export = substituted;
		refused ("detached Core activated an unselected C personality", () => CoreVerifier.verify (core));
		core.classes[0].foreign_export = original;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		cfg.classes[0].foreign_export = substituted;
		refused ("detached CFG substituted personality selection", () => CfgVerifier.verify (cfg));
		cfg.classes[0].foreign_export = original;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		ssa.classes[0].foreign_export = substituted;
		refused ("detached SSA substituted personality selection", () => SsaVerifier.verify (ssa));
		ssa.classes[0].foreign_export = original;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		native.classes[0].foreign_export = substituted;
		refused ("detached native ABI activated unselected adapters", () => NativeAbiVerifier.verify (native));
		native.classes[0].foreign_export = original;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		cabi.class_adapters[0].policy = substituted;
		refused ("detached CABI substituted personality selection", () => CAbiVerifier.verify (cabi));
		cabi.class_adapters[0].policy = original;
		CAbiVerifier.verify (cabi);
		upstream = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		assert ((void*) CApi.named_function (artifact.module, "personalityproof16_create") == null);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void captured_callback_views() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("captured-callback-proof.astra", "class Environment{int bias;init(int bias){this.bias=bias;}}int code(borrowed Environment environment,int value){return environment.bias+value;}int apply(borrowed Callback<int,int> callback){return callback(5);}int forward(borrowed Closure<Environment,int,int> closure){return apply(closure);}int run(){var environment=new Environment(7);var closure=closure_bind(move environment,code);return forward(closure)+apply(closure);}"));
		assert (parsed.diagnostic == null);
		SemanticResult? checked = SemanticAnalyzer.analyze (parsed.unit);
		assert (checked.diagnostic == null);
		var upstream = WeakRef (checked.program.functions[0]);
		CoreProgram? core = CoreBuilder.build (checked.program);
		checked = null;
		assert (upstream.get () == null);
		CoreVerifier.verify (core);
		bool core_changed = false;
		foreach (var function in core.functions) {
			foreach (var statement in function.body.statements) {
				var returned = statement as CoreReturn;
				var call = returned == null ? null : returned.value as CoreCallValue;
				if (call == null || call.arguments.length != 1 || !(call.arguments[0] is CoreCallbackParameterView)) {
					continue;
				}
				var view = (CoreCallbackParameterView) call.arguments[0];
				call.arguments[0] = new CoreCallbackParameterView (view.span, (CallbackType) view.semantic_type, view.parameter, view.parameter);
				refused ("detached Core borrowed Closure replaced with same-width callback parameter", () => CoreVerifier.verify (core));
				call.arguments[0] = view;
				CoreVerifier.verify (core);
				core_changed = true;
			}
		}
		assert (core_changed);
		upstream = WeakRef (core.functions[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		CfgVerifier.verify (cfg);
		bool cfg_changed = false;
		foreach (var function in cfg.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as CfgCallInstruction;
					if (call == null || call.arguments.length != 1 || !(call.arguments[0] is CfgCallbackParameterView)) {
						continue;
					}
					var view = (CfgCallbackParameterView) call.arguments[0];
					call.arguments[0] = new CfgCallbackParameterView (view.span, (CallbackType) view.semantic_type, view.parameter, view.parameter);
					refused ("detached CFG captured callback lost Closure source", () => CfgVerifier.verify (cfg));
					call.arguments[0] = view;
					CfgVerifier.verify (cfg);
					cfg_changed = true;
				}
			}
		}
		assert (cfg_changed);
		upstream = WeakRef (cfg.functions[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		SsaCallbackView? selected = null;
		foreach (var function in ssa.functions) {
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (call != null) {
						foreach (var argument in call.arguments) {
							if (argument is SsaCallbackView) {
								selected = (SsaCallbackView) argument;
								break;
							}
						}
					}
				}
			}
		}
		assert (selected != null);
		var original = selected.closure;
		selected.closure = new SsaNullPointerConstant (selected.span, selected.semantic_type);
		refused ("detached SSA captured callback source lost exact Closure type", () => SsaVerifier.verify (ssa));
		selected.closure = original;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		assert (native.callback_views.length == 2);
		var projection = native.callback_views[0];
		native.callback_views.remove_index (0);
		refused ("native callback projection inventory removed", () => NativeAbiVerifier.verify (native));
		native.callback_views.insert (0, projection);
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		assert (cabi.callback_views.length == 2);
		cabi.callback_views.remove_index (0);
		refused ("detached C ABI callback projection inventory removed", () => CAbiVerifier.verify (cabi));
		cabi.callback_views.insert (0, projection);
		CAbiVerifier.verify (cabi);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		bool llvm_changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null && !llvm_changed; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null && !llvm_changed; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.GEP || CApi.count_struct_element_types (CApi.gep_source_type (instruction)) != 5 || CApi.operand_count (instruction) != 3) {
						continue;
					}
					var index = CApi.operand (instruction, 2);
					if (CApi.const_int_zext (index) != 1) {
						continue;
					}
					CApi.set_operand (instruction, 2, CApi.const_int (CApi.type_of (index), 0, 0));
					ordinary_callback_module (artifact);
					refused ("ordinary-valid captured Closure environment read changed to code field", () => artifact.verify ());
					CApi.set_operand (instruction, 2, index);
					artifact.verify ();
					llvm_changed = true;
					break;
				}
			}
		}
		assert (llvm_changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void signal_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("signal-proof.astra", "[Shared][CExport(name=\"signalproof16\",profile=\"declarations-v1\",bool_abi=\"c99\")][GObjectExport(type=\"ProofEvents\",namespace=\"Proof\",version=\"2.0\",profile=\"declarations-v1\")]class Session{[Foreign]init(){}[Foreign]signal void first(bool input);[Foreign]signal void second(bool input);[Foreign]void update(){emit first(true);}}"));
		assert (parsed.diagnostic == null);
		SemanticResult? analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var policy = checked.classes[0].foreign_export;
		var first = new ForeignSignalBinding (policy, 1);
		var second = new ForeignSignalBinding (policy, 2);
		assert (first.valid () && second.valid ());
		var upstream = WeakRef (checked.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (upstream.get () == null);
		var core_function = CoreForeignApi.target (core.classes[0], first.member);
		var core_end = (CoreForeignSignalReturn) core_function.body.statements[0];
		core_end.binding = second;
		refused ("detached Core signal substituted member", () => CoreVerifier.verify (core));
		core_end.binding = first;
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		var cfg_function = CfgForeignApi.target (cfg.classes[0], first.member);
		var cfg_end = (CfgForeignSignalReturn) cfg_function.entry.terminator;
		cfg_end.binding = second;
		refused ("detached CFG signal substituted member", () => CfgVerifier.verify (cfg));
		cfg_end.binding = first;
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		var ssa_function = SsaForeignApi.target (ssa.classes[0], first.member);
		var ssa_end = (SsaForeignSignalReturn) ssa_function.entry.terminator;
		ssa_end.binding = second;
		refused ("detached SSA signal substituted member", () => SsaVerifier.verify (ssa));
		ssa_end.binding = first;
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		var target = native.functions[native.classes[0].foreign_member (1)];
		var plan = target.foreign_signal;
		target.foreign_signal = null;
		refused ("native omitted signal intrinsic plan", () => NativeAbiVerifier.verify (native));
		target.foreign_signal = new NativeForeignSignalPlan (second);
		refused ("native substituted signal intrinsic member", () => NativeAbiVerifier.verify (native));
		target.foreign_signal = plan;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		assert (cabi.foreign_signals.length == 2);
		var physical = cabi.foreign_signals[0];
		cabi.foreign_signals.remove_index (0);
		refused ("detached C ABI omitted signal plan", () => CAbiVerifier.verify (cabi));
		cabi.foreign_signals.insert (0, physical);
		CAbiVerifier.verify (cabi);
		upstream = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		var function = CApi.named_function (artifact.module, "astra.class.method.0.0");
		var gep = CApi.first_instruction (CApi.first_block (function));
		assert (CApi.opcode (gep) == CApi.Opcode.GEP);
		var index = CApi.operand (gep, 2);
		CApi.set_operand (gep, 2, CApi.const_int (CApi.type_of (index), 4, 0));
		ordinary_callback_module (artifact);
		refused ("ordinary-valid signal cache read changed to native header pointer", () => artifact.verify ());
		CApi.set_operand (gep, 2, index);
		artifact.verify ();
		var call = CApi.next_instruction (CApi.next_instruction (gep));
		assert (CApi.opcode (call) == CApi.Opcode.CALL);
		var receiver = CApi.operand (call, 0);
		CApi.set_operand (call, 0, CApi.get_param (function, 0));
		ordinary_callback_module (artifact);
		refused ("ordinary-valid signal bridge passed native root as foreign handle", () => artifact.verify ());
		CApi.set_operand (call, 0, receiver);
		artifact.verify ();
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void typed_retained_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("typed-retained-proof.astra", "class Environment{init(){}}int register_event(borrowed Closure<Environment,void,bool,f64> callback){return retained_signal_register(callback,1);}int stop_event(borrowed Closure<Environment,void,bool,f64> callback){return retained_signal_revoke(callback);}"));
		assert (parsed.diagnostic == null);
		SemanticResult? analyzed = SemanticAnalyzer.analyze (parsed.unit);
		assert (analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		var upstream = WeakRef (checked.classes[0]);
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		assert (upstream.get () == null);
		CoreVerifier.verify (core);
		upstream = WeakRef (core.classes[0]);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		assert (upstream.get () == null);
		CfgVerifier.verify (cfg);
		upstream = WeakRef (cfg.classes[0]);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		assert (upstream.get () == null);
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		assert (native.retained_operations.length == 2);
		var plan = native.retained_operations[0];
		var parameter = plan.handle.signature.parameter_types[0];
		plan.handle.signature.parameter_types[0] = new NativeScalarAbiType (NativeScalarType.I64);
		refused ("native retained signal changed bool to same-width-independent scalar contract", () => NativeAbiVerifier.verify (native));
		plan.handle.signature.parameter_types[0] = parameter;
		NativeAbiVerifier.verify (native);
		native.retained_operations[0] = new NativeRetainedPlan (plan.caller, plan.block, plan.instruction, 0, plan.handle);
		refused ("native retained signal replaced by legacy registration", () => NativeAbiVerifier.verify (native));
		native.retained_operations[0] = plan;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		var physical = cabi.retained_operations[0];
		assert (physical.callback_void && physical.signal_callback.callback_parameter_count == 2);
		var original = physical.callback_parameters[1];
		physical.callback_parameters[1] = CAbiScalarType.I32;
		refused ("C ABI retained bool widened to gboolean32 without typed thunk conversion", () => CAbiVerifier.verify (cabi));
		physical.callback_parameters[1] = original;
		CAbiVerifier.verify (cabi);
		cabi.retained_operations.remove_index (0);
		refused ("detached C ABI retained signal retirement inventory omitted", () => CAbiVerifier.verify (cabi));
		cabi.retained_operations.insert (0, physical);
		CAbiVerifier.verify (cabi);
		upstream = WeakRef (ssa.classes[0]);
		var artifact = LlvmLowering.lower (ssa, native, cabi);
		ssa = null;
		native = null;
		cabi = null;
		assert (upstream.get () == null);
		new LlvmTargetMachineArtifact (0).configure (artifact);
		artifact.verify ();
		bool changed = false;
		for (var function = CApi.first_function (artifact.module); (void*) function != null; function = CApi.next_function (function)) {
			size_t length;
			unowned string name = CApi.value_name (function, out length);
			if (!name.has_prefix ("astra.retained.signal.thunk.")) {
				continue;
			}
			uint zeroext = CApi.enum_attribute_kind ("zeroext", 7);
			CApi.remove_enum_attribute (function, 2, zeroext);
			ordinary_callback_module (artifact);
			refused ("ordinary-valid retained signal thunk lost exact C99 bool extension", () => artifact.verify ());
			CApi.add_attribute (function, 2, CApi.create_enum_attribute (artifact.context, zeroext, 0));
			artifact.verify ();
			changed = true;
		}
		assert (changed);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

private void gobject_carrier_authority() {
	try {
		var parsed = Parser.parse (new SourceFile.from_text ("carrier-proof.astra", "[ExceptionRoot]class Fault{readonly string text;init(){this.text=\"GLib\";}virtual property string message{get{return this.text;}}}owned Fault fault(int domain,int status){var result=new Fault();return move result;}[GObjectImport(name=\"carrier16\",type=\"ExternalObject\",namespace=\"ForeignApi\",version=\"3.2\",symbol_prefix=\"external_object\",header=\"external.h\",threading=\"constructing\",profile=\"declarations-v1\")]class External{[Foreign(error_factory=\"fault\",error_domain=\"16\",errors=\"Fault=-1600\")]init(int seed)throws Fault;}"));
		assert (parsed.diagnostic == null);
		var declarations = Astra.Vapi.VapiParser.parse (new SourceFile.from_text ("carrier-proof.vapi", "[CCode(destroy_function=\"source_free\")]handle SignalSource;[GObjectImport(name=\"source_new\",header=\"bridge.h\",carrier=\"External\")]owned SignalSource source_new(borrowed External self);"));
		assert (declarations.diagnostic == null);
		var units = new GenericArray<CompilationUnitSyntax> ();
		units.add (parsed.unit);
		var syntax = new SyntaxProgram (units);
		SemanticResult? analyzed = SemanticAnalyzer.analyze_program (syntax, Astra.Vapi.VapiNormalizer.normalize (declarations.file), Astra.Vapi.VapiNormalizer.normalize_handles (declarations.file));
		assert (analyzed.diagnostic == null);
		CheckedProgram? checked = analyzed.program;
		analyzed = null;
		CoreProgram? core = CoreBuilder.build (checked);
		checked = null;
		var metadata = core.c_functions[0].metadata;
		metadata.gobject_carrier = "Other";
		refused ("detached Core GObject carrier nominal origin substituted", () => CoreVerifier.verify (core));
		metadata.gobject_carrier = "External";
		CoreVerifier.verify (core);
		CfgProgram? cfg = CfgBuilder.build (core);
		core = null;
		metadata = cfg.c_functions[0].metadata;
		metadata.gobject_carrier = "";
		refused ("detached CFG native carrier changed to raw SDK object convention", () => CfgVerifier.verify (cfg));
		metadata.gobject_carrier = "External";
		CfgVerifier.verify (cfg);
		SsaProgram? ssa = SsaBuilder.build (cfg);
		cfg = null;
		metadata = ssa.c_functions[0].metadata;
		metadata.gobject_carrier = "Other";
		refused ("detached SSA native carrier root substituted", () => SsaVerifier.verify (ssa));
		metadata.gobject_carrier = "External";
		SsaVerifier.verify (ssa);
		var native = NativeAbiBuilder.build (ssa);
		assert (native.gobject_imports.length == 1);
		string origin = native.gobject_imports[0];
		native.gobject_imports[0] = "0;changed-carrier";
		refused ("native GObject carrier policy inventory changed", () => NativeAbiVerifier.verify (native));
		native.gobject_imports[0] = origin;
		NativeAbiVerifier.verify (native);
		var cabi = CAbiBuilder.build (ssa, native);
		metadata = cabi.functions[0].metadata;
		metadata.gobject_carrier = "";
		refused ("detached C ABI erased native carrier convention", () => CAbiVerifier.verify (cabi));
		metadata.gobject_carrier = "External";
		CAbiVerifier.verify (cabi);
	} catch (GLib.Error failure) {
		error ("%s", failure.message);
	}
}

public static int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/declared-foreign/gobject-nominal-native-carrier-bridge-authority", gobject_carrier_authority);
	Test.add_func ("/declared-foreign/typed-retained-signal-closure-signature-and-retirement-authority", typed_retained_authority);
	Test.add_func ("/declared-foreign/native-signal-intrinsic-member-cache-and-delivery-authority", signal_authority);
	Test.add_func ("/declared-foreign/captured-closure-callback-projection-authority", captured_callback_views);
	Test.add_func ("/declared-foreign/explicit-personality-selection-authority", personality_authority);
	Test.add_func ("/declared-foreign/gobject-import-sdk-gtype-reference-and-detached-authority", gobject_import_bindings);
	Test.add_func ("/declared-foreign/gobject-import-boxed-record-detached-authority", gobject_import_record_bindings);
	Test.add_func ("/declared-foreign/gobject-exact-native-object-root-projection", gobject_object_roots);
	Test.add_func ("/declared-foreign/gobject-type-version-owner-inventory-and-native-bool", gobject_declaration_bindings);
	Test.add_func ("/declared-foreign/com-native-class-exact-root-and-interface-projection", com_native_root_bindings);
	Test.add_func ("/declared-foreign/com-export-resolved-native-requirements-and-detached-targets", com_export_bindings);
	Test.add_func ("/declared-foreign/com-inherited-interface-and-iunknown-acquisition-authority", com_import_bindings);
	Test.add_func ("/declared-foreign/callback-noescape-context-signature-physical-and-llvm-mutations", callback_bindings);
	Test.add_func ("/declared-foreign/detached-stage-member-signature-ownership-and-bool-attributes", stage_bindings);
	Test.add_func ("/declared-foreign/detached-byte-element-versus-identical-physical-pair", byte_channel_bindings);
	Test.add_func ("/declared-foreign/owned-sequence-cleanup-and-nul-conversion-mutations", owned_sequence_bindings);
	Test.add_func ("/declared-foreign/nominal-pod-fields-groups-results-and-physical-addresses", record_bindings);
	Test.add_func ("/declared-foreign/nominal-object-ownership-nonnull-and-construction-context", object_bindings);
	Test.add_func ("/declared-foreign/consuming-object-heap-slot-disarm-and-duty-mutations", owner_bindings);
	Test.add_func ("/declared-foreign/checked-error-bound-private-abi-and-status-mutations", error_bindings);
	Test.add_func ("/declared-foreign/scalar-reference-pointee-noescape-produced-and-publication", scalar_reference_bindings);
	Test.add_func ("/declared-foreign/checked-constructor-partial-retirement-and-acquisition-stack", constructor_bindings);
	Test.add_func ("/declared-foreign/imported-nominal-member-status-out-factory-and-physical-mutations", import_bindings);
	Test.add_func ("/declared-foreign/import-reference-noescape-pointee-and-publication-mutations", import_reference_bindings);
	Test.add_func ("/declared-foreign/import-counted-element-capacity-and-cleanup-mutations", import_counted_bindings);
	Test.add_func ("/declared-foreign/import-owned-byte-text-transfer-release-and-snapshot-mutations", import_owned_bindings);
	Test.add_func ("/declared-foreign/import-pod-nominal-prologue-physical-and-address-mutations", import_record_bindings);
	Test.add_func ("/declared-foreign/import-handle-nominal-result-root-and-retirement-mutations", import_handle_bindings);
	Test.add_func ("/declared-foreign/import-consuming-duty-owner-slot-and-disarm-mutations", import_consuming_bindings);
	Test.add_func ("/declared-foreign/export-foreign-handle-root-provider-pin-and-retirement-mutations", foreign_handle_exports);
	Test.add_func ("/declared-foreign/import-property-accessor-ordinal-signature-and-physical-mutations", import_property_bindings);
	Test.add_func ("/declared-foreign/native-void-callable-effect-and-result-channel-mutations", void_callable_bindings);
	return Test.run ();
}

}
